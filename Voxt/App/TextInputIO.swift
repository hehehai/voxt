// TextInputIO.swift
// Provides Text Input IO for app lifecycle and routing.

import Foundation
import AppKit
import ApplicationServices
import Carbon

enum SelectedTextSystemSelectionSupport {
    /// Hard gate: a caret-only range (`length == 0`) must not count as a selection.
    static func hasNonEmptySelectedTextRange(length: CFIndex) -> Bool {
        length > 0
    }

    /// Editors that implement "Cmd+C with no selection copies the current line"
    /// (VS Code `editor.emptySelectionClipboard`, Sublime, Zed, JetBrains, etc.).
    ///
    /// This is a clipboard-semantics capability class. Many of these apps also
    /// fail AX focus lookup with `kAXErrorCannotComplete` (-25204), so
    /// "focused == nil" alone cannot mean "safe to Cmd+C" — that path remains
    /// necessary for AX-dead apps such as WeChat, but must stay denied here.
    static func copiesCurrentLineWhenSelectionEmpty(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }

        // Stable first-party / well-known IDs.
        let exactIDs: Set<String> = [
            // Microsoft / OSS VS Code
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.microsoft.VSCodeExploration",
            "com.visualstudio.code.oss",
            "com.visualstudio.code",
            "com.vscodium",
            // Google Antigravity (VS Code-based)
            "com.google.antigravity",
            // Sublime
            "com.sublimetext.3",
            "com.sublimetext.4",
            // Zed
            "dev.zed.Zed",
            "dev.zed.Zed-Preview",
            // Trae / Qoder (VS Code forks)
            "com.trae.app",
            "com.trae.solo.app",
            "cn.trae.app",
            "com.qoder.app"
        ]
        if exactIDs.contains(bundleID) {
            return true
        }

        // Family prefixes: ToDesktop-packaged Electron IDEs (Cursor, etc.),
        // JetBrains suite, Windsurf/Codeium, Trae/Qoder variants.
        let prefixes = [
            "com.todesktop.",
            "com.jetbrains.",
            "com.exafunction.",
            "com.trae.",
            "cn.trae.",
            "com.qoder."
        ]
        if prefixes.contains(where: bundleID.hasPrefix) {
            return true
        }

        // Catch less common VS Code forks that keep "VSCode" in the bundle ID.
        let lowered = bundleID.lowercased()
        if lowered.contains("vscode") || lowered.contains("vscodium") {
            return true
        }
        return false
    }

    /// Whether Cmd+C may run after all non-destructive reads missed.
    ///
    /// - caret-only range (`length == 0`) → deny
    /// - non-empty range → allow (recover text when attributes are empty)
    /// - no focused element:
    ///   - deny when app copies the current line on empty selection
    ///   - allow otherwise (AX-dead apps such as WeChat)
    /// - focused element but no range attribute:
    ///   - browser → allow
    ///   - otherwise → deny
    static func shouldAttemptSimulatedCopy(
        focusedElementAvailable: Bool,
        selectedTextRange: CFRange?,
        isBrowser: Bool,
        copiesLineOnEmptySelection: Bool
    ) -> Bool {
        if focusedElementAvailable, let selectedTextRange {
            return selectedTextRange.length > 0
        }
        if !focusedElementAvailable {
            return !copiesLineOnEmptySelection
        }
        return isBrowser
    }

    /// Range attribute present with `length == 0` means caret-only; further probes cannot help.
    static func isConfirmedCaretOnly(selectedTextRange: CFRange?) -> Bool {
        guard let selectedTextRange else { return false }
        return selectedTextRange.length == 0
    }

    /// AppleScript ran without an execution error and returned empty/whitespace selection text.
    /// Dialect retries are only useful when the script form itself fails.
    static func isDefinitiveEmptyBrowserSelection(output: String?, hadExecutionError: Bool) -> Bool {
        guard !hadExecutionError, let output else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension AppDelegate {
    private static let axMessagingTimeout: Float = 0.05
    /// Selection probe uses a modestly longer AX timeout than injection helpers.
    /// Keep this well under 1s: AX-dead apps (WeChat/Cursor) often still return
    /// `kAXErrorCannotComplete` (-25204), and each focus lookup pays the full timeout.
    private static let selectionAXMessagingTimeout: Float = 0.2
    private static let automaticDictionaryLearningSnippetBeforeCursor = 4_000
    private static let automaticDictionaryLearningSnippetAfterCursor = 1_000
    private static let nativeWritableTextRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        "AXSearchField",
        kAXComboBoxRole as String
    ]
    private static let genericEditableTextRoles: Set<String> = [
        "AXWebArea",
        "AXGroup",
        "AXLayoutArea",
        "AXScrollArea",
        "AXDocument",
        "AXUnknown"
    ]
    private static let nonEditableFalsePositiveRoles: Set<String> = [
        kAXWindowRole as String,
        kAXButtonRole as String,
        kAXStaticTextRole as String,
        "AXToolbar",
        "AXMenuBar",
        "AXMenuItem",
        "AXMenu",
        "AXSplitter",
        "AXList",
        "AXTable",
        "AXOutline",
        "AXRow"
    ]

    struct FocusedInputTextSnapshot {
        let text: String
        let bundleIdentifier: String?
        let processIdentifier: pid_t?
        let role: String?
        let isEditable: Bool
        let isFocusedTarget: Bool
        let selectedRange: NSRange?
        let failureReason: String?
        let textSource: String?
    }

    func selectedTextFromSystemSelection() -> String? {
        let appBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        let isBrowser = isBrowserBundleID(appBundleID == "unknown" ? nil : appBundleID)
        let axTrusted = AccessibilityPermissionManager.isTrusted()

        VoxtLog.input(
            "selectionProbe.begin: app=\(appBundleID) name=\(appName) browser=\(isBrowser) axTrusted=\(axTrusted)"
        )

        guard axTrusted else {
            logSelectionProbe(
                range: nil,
                textSource: "nil",
                app: appBundleID,
                isBrowser: isBrowser,
                detail: "accessibility-not-trusted"
            )
            return nil
        }

        // Phase 1: resolve focus and gather non-destructive evidence.
        let focusedElement = focusedElementForSystemSelection()
        if let focusedElement {
            let role = axStringAttribute(
                kAXRoleAttribute as CFString,
                for: focusedElement,
                timeout: Self.selectionAXMessagingTimeout
            ) ?? "nil"
            let subrole = axStringAttribute(
                kAXSubroleAttribute as CFString,
                for: focusedElement,
                timeout: Self.selectionAXMessagingTimeout
            ) ?? "nil"
            VoxtLog.input("selectionProbe.focused: role=\(role) subrole=\(subrole)")
        } else {
            VoxtLog.input("selectionProbe.focused: element=nil")
        }

        let rawSelectedRange = focusedElement.flatMap {
            axRangeAttribute(
                kAXSelectedTextRangeAttribute as CFString,
                for: $0,
                timeout: Self.selectionAXMessagingTimeout
            )
        }
        VoxtLog.input(
            "selectionProbe.range: raw=\(selectionRangeDescription(rawSelectedRange)) nonEmpty=\(nonEmptySelectedTextRange(rawSelectedRange) != nil)"
        )

        // Confirmed caret-only: skip TextMarker / AppleScript / Cmd+C entirely.
        if SelectedTextSystemSelectionSupport.isConfirmedCaretOnly(selectedTextRange: rawSelectedRange) {
            logSelectionProbe(
                range: rawSelectedRange,
                textSource: "nil",
                app: appBundleID,
                isBrowser: isBrowser,
                detail: "confirmed-caret-only"
            )
            return nil
        }

        // Phase 2: non-destructive text reads (never mutate pasteboard).
        if let focusedElement {
            let axSelectedResult = probeAXSelectedText(from: focusedElement)
            VoxtLog.input(
                "selectionProbe.read.axSelected: status=\(axSelectedResult.status) chars=\(axSelectedResult.characterCount) preview=\(selectionPreview(axSelectedResult.text))"
            )
            if let text = axSelectedResult.text {
                logSelectionProbe(
                    range: rawSelectedRange,
                    textSource: "axSelected",
                    app: appBundleID,
                    isBrowser: isBrowser,
                    detail: "chars=\(text.count)"
                )
                return text
            }
        } else {
            VoxtLog.input("selectionProbe.read.axSelected: skipped focused=nil")
        }

        if let focusedElement,
           let selectedRange = nonEmptySelectedTextRange(rawSelectedRange) {
            let rangeText = axParameterizedString(
                kAXStringForRangeParameterizedAttribute as CFString,
                range: selectedRange,
                for: focusedElement,
                timeout: Self.selectionAXMessagingTimeout
            )
            let trimmedRangeText = rangeText?.trimmingCharacters(in: .whitespacesAndNewlines)
            VoxtLog.input(
                "selectionProbe.read.stringForRange: chars=\(trimmedRangeText?.count ?? 0) preview=\(selectionPreview(trimmedRangeText))"
            )
            if let trimmedRangeText, !trimmedRangeText.isEmpty {
                logSelectionProbe(
                    range: selectedRange,
                    textSource: "stringForRange",
                    app: appBundleID,
                    isBrowser: isBrowser,
                    detail: "chars=\(trimmedRangeText.count)"
                )
                return rangeText
            }
        } else {
            VoxtLog.input("selectionProbe.read.stringForRange: skipped")
        }

        if let focusedElement {
            let markerText = selectedTextFromAXTextMarker(startingAt: focusedElement)
            VoxtLog.input(
                "selectionProbe.read.textMarker: chars=\(markerText?.count ?? 0) preview=\(selectionPreview(markerText))"
            )
            if let text = markerText {
                logSelectionProbe(
                    range: rawSelectedRange,
                    textSource: "textMarker",
                    app: appBundleID,
                    isBrowser: isBrowser,
                    detail: "chars=\(text.count)"
                )
                return text
            }
        } else {
            VoxtLog.input("selectionProbe.read.textMarker: skipped focused=nil")
        }

        // Browser AppleScript is still non-destructive and often better than Cmd+C on Safari.
        if isBrowser {
            let scriptText = selectedTextFromBrowserAppleScript(bundleID: appBundleID)
            VoxtLog.input(
                "selectionProbe.read.appleScript: chars=\(scriptText?.count ?? 0) preview=\(selectionPreview(scriptText))"
            )
            if let text = scriptText {
                logSelectionProbe(
                    range: rawSelectedRange,
                    textSource: "appleScript",
                    app: appBundleID,
                    isBrowser: isBrowser,
                    detail: "chars=\(text.count)"
                )
                return text
            }
        } else {
            VoxtLog.input("selectionProbe.read.appleScript: skipped not-browser")
        }

        // Phase 3: Cmd+C only with evidence-based policy (see shouldAttemptSimulatedCopy).
        let copiesLineOnEmptySelection = SelectedTextSystemSelectionSupport
            .copiesCurrentLineWhenSelectionEmpty(bundleID: appBundleID)
        let allowCopy = SelectedTextSystemSelectionSupport.shouldAttemptSimulatedCopy(
            focusedElementAvailable: focusedElement != nil,
            selectedTextRange: rawSelectedRange,
            isBrowser: isBrowser,
            copiesLineOnEmptySelection: copiesLineOnEmptySelection
        )
        VoxtLog.input(
            "selectionProbe.copy.policy: allow=\(allowCopy) focused=\(focusedElement != nil) range=\(selectionRangeDescription(rawSelectedRange)) browser=\(isBrowser) copiesLineOnEmpty=\(copiesLineOnEmptySelection)"
        )
        if allowCopy, let text = selectedTextBySimulatedCopy(reason: "policyAllowed") {
            logSelectionProbe(
                range: rawSelectedRange,
                textSource: "copy",
                app: appBundleID,
                isBrowser: isBrowser,
                detail: "chars=\(text.count)"
            )
            return text
        }

        let denyDetail: String
        if allowCopy {
            denyDetail = "copy-missed"
        } else if focusedElement == nil, copiesLineOnEmptySelection {
            denyDetail = "ax-focus-unavailable-line-copy-editor"
        } else if focusedElement != nil, rawSelectedRange?.length == 0 {
            denyDetail = "confirmed-caret-only"
        } else if focusedElement != nil, rawSelectedRange == nil, !isBrowser {
            denyDetail = "focused-without-range-non-browser"
        } else {
            denyDetail = "copy-denied"
        }
        logSelectionProbe(
            range: rawSelectedRange,
            textSource: "nil",
            app: appBundleID,
            isBrowser: isBrowser,
            detail: denyDetail
        )
        return nil
    }

    private func focusedElementForSystemSelection() -> AXUIElement? {
        // Selection must come from the actual focused element only.
        // Do not reuse writable-input focus resolution (best-editable / window fallbacks),
        // which can probe a different field with a leftover selection.
        if let systemFocused = copyFocusedUIElement(
            from: AXUIElementCreateSystemWide(),
            source: "systemWide"
        ) {
            return systemFocused
        }

        if let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let appFocused = copyFocusedUIElement(
            from: AXUIElementCreateApplication(processID),
            source: "frontmostApp"
           ) {
            return appFocused
        }

        VoxtLog.input("selectionProbe.focusedResolve: all focus lookups failed")
        return nil
    }

    private func copyFocusedUIElement(from root: AXUIElement, source: String) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(root, Self.selectionAXMessagingTimeout)
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedStatus == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            VoxtLog.input(
                "selectionProbe.focusedResolve: source=\(source) failed status=\(focusedStatus.rawValue) timeoutSec=\(Self.selectionAXMessagingTimeout)"
            )
            return nil
        }
        VoxtLog.input("selectionProbe.focusedResolve: source=\(source) ok")
        return unsafeBitCast(focusedElementRef, to: AXUIElement.self)
    }

    private struct AXSelectedTextProbeResult {
        let text: String?
        let status: String
        let characterCount: Int
    }

    private func probeAXSelectedText(from element: AXUIElement) -> AXSelectedTextProbeResult {
        AXUIElementSetMessagingTimeout(element, Self.selectionAXMessagingTimeout)
        var selectedTextRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        guard selectedStatus == .success, let selectedTextRef else {
            return AXSelectedTextProbeResult(
                text: nil,
                status: "ax-error-\(selectedStatus.rawValue)",
                characterCount: 0
            )
        }

        let selectedText: String?
        let typeName: String
        if let text = selectedTextRef as? String {
            selectedText = text
            typeName = "String"
        } else if let attributed = selectedTextRef as? NSAttributedString {
            selectedText = attributed.string
            typeName = "NSAttributedString"
        } else {
            selectedText = nil
            typeName = "unsupported(\(CFGetTypeID(selectedTextRef)))"
        }

        let trimmed = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return AXSelectedTextProbeResult(
                text: nil,
                status: "empty-\(typeName)",
                characterCount: selectedText?.count ?? 0
            )
        }
        return AXSelectedTextProbeResult(
            text: selectedText,
            status: "ok-\(typeName)",
            characterCount: selectedText?.count ?? 0
        )
    }

    private func nonEmptyAXSelectedText(from element: AXUIElement) -> String? {
        probeAXSelectedText(from: element).text
    }

    private func selectedTextFromAXTextMarker(startingAt element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for depth in 0..<6 {
            guard let currentElement = current else { break }
            let role = axStringAttribute(
                kAXRoleAttribute as CFString,
                for: currentElement,
                timeout: Self.selectionAXMessagingTimeout
            ) ?? "nil"
            let result = selectedTextFromAXTextMarkerRange(on: currentElement)
            VoxtLog.input(
                "selectionProbe.textMarker.depth=\(depth) role=\(role) status=\(result.status) chars=\(result.text?.count ?? 0)"
            )
            if let text = result.text {
                return text
            }
            current = axElementAttribute(
                kAXParentAttribute as CFString,
                for: currentElement,
                timeout: Self.selectionAXMessagingTimeout
            )
        }
        return nil
    }

    private struct TextMarkerProbeResult {
        let text: String?
        let status: String
    }

    private func selectedTextFromAXTextMarkerRange(on element: AXUIElement) -> TextMarkerProbeResult {
        AXUIElementSetMessagingTimeout(element, Self.selectionAXMessagingTimeout)
        var markerRangeRef: CFTypeRef?
        let markerStatus = AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &markerRangeRef
        )
        guard markerStatus == .success, let markerRangeRef else {
            return TextMarkerProbeResult(text: nil, status: "marker-error-\(markerStatus.rawValue)")
        }

        var stringRef: CFTypeRef?
        let stringStatus = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            markerRangeRef,
            &stringRef
        )
        if stringStatus == .success,
           let text = stringRef as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TextMarkerProbeResult(text: text, status: "string-ok")
        }

        var attributedRef: CFTypeRef?
        let attributedStatus = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForTextMarkerRange" as CFString,
            markerRangeRef,
            &attributedRef
        )
        if attributedStatus == .success {
            if let attributed = attributedRef as? NSAttributedString,
               !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return TextMarkerProbeResult(text: attributed.string, status: "attributed-ok")
            }
            if let text = attributedRef as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return TextMarkerProbeResult(text: text, status: "attributed-string-ok")
            }
            return TextMarkerProbeResult(
                text: nil,
                status: "marker-present-empty stringStatus=\(stringStatus.rawValue) attributedStatus=\(attributedStatus.rawValue)"
            )
        }
        return TextMarkerProbeResult(
            text: nil,
            status: "resolve-failed stringStatus=\(stringStatus.rawValue) attributedStatus=\(attributedStatus.rawValue)"
        )
    }

    private func selectedTextFromBrowserAppleScript(bundleID: String) -> String? {
        if let deniedUntil = browserAutomationDeniedUntilByBundleID[bundleID],
           deniedUntil > Date() {
            let remaining = Int(deniedUntil.timeIntervalSinceNow)
            VoxtLog.input(
                "selectionProbe.appleScript: skipped denied-cache bundleID=\(bundleID) remainingSec=\(remaining)"
            )
            return nil
        }

        let displayName = browserScriptProvider(for: bundleID)?.name
        let scripts = BrowserAutomationScriptBuilder.selectionScripts(
            bundleID: bundleID,
            displayName: displayName
        )
        VoxtLog.input(
            "selectionProbe.appleScript: candidates=\(scripts.count) provider=\(displayName ?? "nil") bundleID=\(bundleID)"
        )
        for (index, source) in scripts.enumerated() {
            var executionError: NSDictionary?
            let startedAt = Date()
            // `runAppleScript` ceilings fractional timeouts to whole seconds; pass 1 explicitly.
            let rawOutput = runAppleScript(
                source,
                error: &executionError,
                logFailure: false,
                timeout: 1
            )
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            if SelectedTextSystemSelectionSupport.isDefinitiveEmptyBrowserSelection(
                output: rawOutput,
                hadExecutionError: executionError != nil
            ) {
                VoxtLog.input(
                    "selectionProbe.appleScript.candidate=\(index + 1): empty-selection elapsedMs=\(elapsedMs)"
                )
                return nil
            }

            let trimmed = rawOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                VoxtLog.input(
                    "selectionProbe.appleScript.candidate=\(index + 1): ok chars=\(trimmed.count) elapsedMs=\(elapsedMs) preview=\(selectionPreview(trimmed))"
                )
                return trimmed
            }

            let errorNumber = executionError?["NSAppleScriptErrorNumber"] as? Int
            let errorMessage = executionError?["NSAppleScriptErrorMessage"] as? String ?? "nil"
            VoxtLog.input(
                "selectionProbe.appleScript.candidate=\(index + 1): miss elapsedMs=\(elapsedMs) errorNumber=\(errorNumber.map(String.init) ?? "nil") message=\(errorMessage)"
            )

            if let errorNumber {
                if errorNumber == -1743 || errorNumber == -10004 {
                    browserAutomationDeniedUntilByBundleID[bundleID] = Date().addingTimeInterval(300)
                    VoxtLog.input(
                        "selectionProbe.appleScript: caching denial for 300s bundleID=\(bundleID) error=\(errorNumber)"
                    )
                    break
                }
                if errorNumber == -600 {
                    VoxtLog.input("selectionProbe.appleScript: app not running error=-600")
                    break
                }
            }
        }
        return nil
    }

    private func nonEmptySelectedTextRange(_ range: CFRange?) -> CFRange? {
        guard let range,
              SelectedTextSystemSelectionSupport.hasNonEmptySelectedTextRange(length: range.length) else {
            return nil
        }
        return range
    }

    private func logSelectionProbe(
        range: CFRange?,
        textSource: String,
        app: String,
        isBrowser: Bool,
        detail: String = ""
    ) {
        let rangeDescription = selectionRangeDescription(range)
        let suffix = detail.isEmpty ? "" : " detail=\(detail)"
        VoxtLog.input(
            "selectionProbe.result: range=\(rangeDescription) textSource=\(textSource) browser=\(isBrowser) app=\(app)\(suffix)"
        )
    }

    private func selectionRangeDescription(_ range: CFRange?) -> String {
        range.map { "{\($0.location),\($0.length)}" } ?? "nil"
    }

    private func selectionPreview(_ text: String?) -> String {
        guard let text else { return "nil" }
        let collapsed = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if collapsed.count <= 48 {
            return "\"\(collapsed)\""
        }
        let prefix = collapsed.prefix(48)
        return "\"\(prefix)…\"(+\(collapsed.count - 48))"
    }

    private func selectedTextBySimulatedCopy(reason: String = "unspecified") -> String? {
        VoxtLog.input("selectionProbe.copy.begin: reason=\(reason)")
        guard AccessibilityPermissionManager.isTrusted() else {
            VoxtLog.input("selectionProbe.copy.miss: accessibility-not-trusted")
            return nil
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            VoxtLog.input("selectionProbe.copy.miss: no-event-source")
            return nil
        }

        let pasteboard = NSPasteboard.general
        let previous = readStringFromPasteboard(pasteboard)
        let originalChangeCount = pasteboard.changeCount
        VoxtLog.input(
            "selectionProbe.copy.pasteboard: changeCount=\(originalChangeCount) previousChars=\(previous?.count ?? 0)"
        )

        let cKeyCode: CGKeyCode = 0x08
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand
        guard cmdDown != nil, cmdUp != nil else {
            VoxtLog.input("selectionProbe.copy.miss: failed-to-create-key-events")
            return nil
        }

        HotkeyEventSupport.markAsVoxtInjected(cmdDown)
        HotkeyEventSupport.markAsVoxtInjected(cmdUp)
        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)

        // AX-poor apps (WeChat, some web views) can take longer to honor Cmd+C.
        let waitSeconds: TimeInterval = 0.15
        let deadline = Date().addingTimeInterval(waitSeconds)
        while pasteboard.changeCount == originalChangeCount, Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        let copiedChangeCount = pasteboard.changeCount
        guard copiedChangeCount != originalChangeCount else {
            VoxtLog.input(
                "selectionProbe.copy.miss: pasteboard-unchanged changeCount=\(copiedChangeCount) waitedSec=\(waitSeconds) reason=\(reason)"
            )
            return nil
        }

        let copied = readStringFromPasteboard(pasteboard)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        pasteboard.clearContents()
        if let previous, !previous.isEmpty {
            pasteboard.setString(previous, forType: .string)
        }

        guard let copied, !copied.isEmpty else {
            VoxtLog.input(
                "selectionProbe.copy.miss: empty-after-change changeCount=\(copiedChangeCount)"
            )
            return nil
        }
        VoxtLog.input(
            "selectionProbe.copy.ok: reason=\(reason) chars=\(copied.count) preview=\(selectionPreview(copied))"
        )
        return copied
    }

    func hasWritableFocusedTextInput() -> Bool {
        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let focusedElement = focusedAXElement(preferredProcessID: processID) else {
            VoxtLog.input("Focused input check: no focused AX element.")
            return false
        }

        if let writableElement = writableTextInputElement(from: focusedElement) {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: writableElement) ?? "unknown"
            let editable = isWritableTextInputElement(writableElement)
            let valueSettable = isAttributeSettable(kAXValueAttribute as CFString, on: writableElement)
            VoxtLog.input(
                "Focused input check: writable descendant detected. role=\(role), editable=\(editable), valueSettable=\(valueSettable)"
            )
            return true
        }

        let editable = axBoolAttribute("AXEditable" as CFString, for: focusedElement)
        if editable == true {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) ?? "unknown"
            VoxtLog.input("Focused input check: editable AX element detected. role=\(role)")
            return true
        }

        if isAttributeSettable(kAXValueAttribute as CFString, on: focusedElement) {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) ?? "unknown"
            VoxtLog.input("Focused input check: settable AX value detected. role=\(role)")
            return true
        }

        guard let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) else {
            VoxtLog.input(
                "Focused input check: role unavailable. editable=\(editable == true), valueSettable=false"
            )
            return false
        }

        let isWritable = Self.nativeWritableTextRoles.contains(role)
        VoxtLog.input(
            "Focused input check: role=\(role), editable=\(editable == true), valueSettable=false, result=\(isWritable)"
        )
        return isWritable
    }

    func currentFocusedInputTextSnapshot(
        expectedBundleID: String? = nil,
        logDiagnostics: Bool = true
    ) -> FocusedInputTextSnapshot? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            if logDiagnostics {
                VoxtLog.input("Focused input snapshot unavailable: no frontmost application.")
            }
            return nil
        }
        if let expectedBundleID,
           let bundleIdentifier = frontmostApplication.bundleIdentifier,
           bundleIdentifier != expectedBundleID {
            if logDiagnostics {
                VoxtLog.input(
                    "Focused input snapshot skipped: frontmost app changed. expectedBundleID=\(expectedBundleID), actualBundleID=\(bundleIdentifier)"
                )
            }
            return nil
        }

        let bundleIdentifier = frontmostApplication.bundleIdentifier
        let processIdentifier = frontmostApplication.processIdentifier

        guard let focusedElement = focusedAXElement(
            preferredProcessID: processIdentifier,
            logDiagnostics: logDiagnostics
        ) else {
            if logDiagnostics {
                VoxtLog.input(
                    "Focused input snapshot unavailable: no focused AX element. bundleID=\(bundleIdentifier ?? "unknown")"
                )
            }
            return nil
        }

        let writableElement = writableTextInputElement(from: focusedElement) ?? (
            isWritableTextInputElement(focusedElement) ? focusedElement : nil
        )
        guard let writableElement else {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) ?? "unknown"
            if logDiagnostics {
                VoxtLog.input(
                    "Focused input snapshot unavailable: no writable text element found. bundleID=\(bundleIdentifier ?? "unknown"), role=\(role)"
                )
            }
            return nil
        }

        let role = axStringAttribute(kAXRoleAttribute as CFString, for: writableElement)
        let isFocusedTarget = axBoolAttribute(kAXFocusedAttribute as CFString, for: writableElement) == true
        let value = axTextValue(for: writableElement)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text = value, !text.isEmpty else {
            let textFailureReason = unreadableTextFailureReason(for: writableElement)
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: writableElement) ?? "unknown"
            if logDiagnostics {
                VoxtLog.input(
                    "Focused input snapshot unavailable: writable element has empty/unreadable value. bundleID=\(bundleIdentifier ?? "unknown"), role=\(role), failureReason=\(textFailureReason)"
                )
            }
            return nil
        }

        let snapshot = FocusedInputTextSnapshot(
            text: text,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            role: role,
            isEditable: isWritableTextInputElement(writableElement),
            isFocusedTarget: isFocusedTarget,
            selectedRange: selectedNSRange(from: axRangeAttribute(kAXSelectedTextRangeAttribute as CFString, for: writableElement)),
            failureReason: nil,
            textSource: "ax-value"
        )
        if logDiagnostics {
            VoxtLog.input("Focused input snapshot ready: \(focusedInputSnapshotSummary(snapshot))")
        }
        return snapshot
    }

    func currentFocusedInputTextSnapshotForAutomaticDictionaryLearning(
        expectedBundleID: String? = nil
    ) async -> FocusedInputTextSnapshot? {
        let startedAt = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed >= 0.08 {
                let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                VoxtLog.input(
                    "Automatic dictionary focused input snapshot was slow. elapsedMs=\(Int(elapsed * 1000)), bundleID=\(bundleID), expectedBundleID=\(expectedBundleID ?? "nil")"
                )
            }
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        if let expectedBundleID,
           let bundleIdentifier = frontmostApplication.bundleIdentifier,
           bundleIdentifier != expectedBundleID {
            return nil
        }

        let bundleIdentifier = frontmostApplication.bundleIdentifier
        let processIdentifier = frontmostApplication.processIdentifier
        if let focusedElement = focusedAXElement(
            preferredProcessID: processIdentifier,
            logDiagnostics: false
        ) {
            let writableElement = writableTextInputElement(from: focusedElement) ?? (
                isWritableTextInputElement(focusedElement) ? focusedElement : nil
            )
            if let writableElement,
               let snippetSnapshot = focusedInputSnippetSnapshot(
                    for: writableElement,
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: processIdentifier
               ) {
                return snippetSnapshot
            }
        }

        if let snapshot = currentFocusedInputTextSnapshot(
            expectedBundleID: expectedBundleID,
            logDiagnostics: false
        ) {
            return snapshot
        }

        if let cdpSnapshot = await electronCDPFocusedInputTextSnapshot(
            bundleIdentifier: frontmostApplication.bundleIdentifier,
            processIdentifier: frontmostApplication.processIdentifier
        ) {
            return cdpSnapshot
        }

        return nil
    }

    private func focusedInputSnippetSnapshot(
        for writableElement: AXUIElement,
        bundleIdentifier: String?,
        processIdentifier: pid_t
    ) -> FocusedInputTextSnapshot? {
        guard axParameterizedAttributeNames(for: writableElement)
            .contains(kAXStringForRangeParameterizedAttribute as String) else {
            return nil
        }

        let role = axStringAttribute(kAXRoleAttribute as CFString, for: writableElement)
        let isFocusedTarget = axBoolAttribute(kAXFocusedAttribute as CFString, for: writableElement) == true
        let selectedRange = axRangeAttribute(kAXSelectedTextRangeAttribute as CFString, for: writableElement)
        let sourceRange: CFRange?
        if let selectedRange,
           selectedRange.location >= 0,
           let numberOfCharacters = axIntAttribute("AXNumberOfCharacters" as CFString, for: writableElement),
           numberOfCharacters > 0 {
            sourceRange = automaticDictionaryLearningSnippetRange(
                selectedRange: selectedRange,
                numberOfCharacters: numberOfCharacters
            )
        } else if let visibleRange = axRangeAttribute(kAXVisibleCharacterRangeAttribute as CFString, for: writableElement),
                  visibleRange.location >= 0,
                  visibleRange.length > 0 {
            sourceRange = visibleRange
        } else {
            sourceRange = nil
        }

        guard let sourceRange,
              sourceRange.length > 0,
              let text = axParameterizedString(
                kAXStringForRangeParameterizedAttribute as CFString,
                range: sourceRange,
                for: writableElement
              ),
              !text.isEmpty else {
            return nil
        }

        return FocusedInputTextSnapshot(
            text: text,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            role: role,
            isEditable: isWritableTextInputElement(writableElement),
            isFocusedTarget: isFocusedTarget,
            selectedRange: selectedNSRange(from: selectedRange),
            failureReason: nil,
            textSource: "ax-focused-range"
        )
    }

    private func automaticDictionaryLearningSnippetRange(
        selectedRange: CFRange,
        numberOfCharacters: Int
    ) -> CFRange {
        let selectedLocation = min(max(selectedRange.location, 0), numberOfCharacters)
        let selectedLength = max(selectedRange.length, 0)
        let before = min(Self.automaticDictionaryLearningSnippetBeforeCursor, selectedLocation)
        let start = max(selectedLocation - before, 0)
        let requestedLength = before + selectedLength + Self.automaticDictionaryLearningSnippetAfterCursor
        let availableLength = max(numberOfCharacters - start, 0)
        return CFRange(location: start, length: min(requestedLength, availableLength))
    }

    private func focusedAXElement(
        preferredProcessID: pid_t,
        logDiagnostics: Bool = true
    ) -> AXUIElement? {
        guard AccessibilityPermissionManager.isTrusted() else {
            if logDiagnostics {
                VoxtLog.input("Focused input check: accessibility not trusted.")
            }
            return nil
        }

        if let appFocusedElement = focusedAXElement(for: preferredProcessID, logDiagnostics: logDiagnostics) {
            return appFocusedElement
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        if let systemFocusedElement = systemFocusedAXElement(logDiagnostics: logDiagnostics) {
            if logDiagnostics {
                VoxtLog.input("Focused input check: falling back to system-wide focused element. bundleID=\(bundleID)")
            }
            return systemFocusedElement
        }

        if logDiagnostics {
            VoxtLog.input("Focused input check: app/system focus resolution failed. bundleID=\(bundleID)")
        }
        return nil
    }

    private func systemFocusedAXElement(logDiagnostics: Bool = true) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.axMessagingTimeout)
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedStatus == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
            if logDiagnostics {
                VoxtLog.input(
                    "Focused input check: system-wide focused element unavailable. status=\(focusedStatus.rawValue), bundleID=\(bundleID)"
                )
            }
            return nil
        }
        let focusedElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        return resolveFocusedElement(focusedElement)
    }

    private func focusedAXElement(
        for processID: pid_t,
        logDiagnostics: Bool = true
    ) -> AXUIElement? {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let appElement = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(appElement, Self.axMessagingTimeout)
        if let focusedAppElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: appElement),
           let resolved = resolveFocusedElement(focusedAppElement) {
            if logDiagnostics {
                VoxtLog.input(
                    "Focused input check: using frontmost app focused element. bundleID=\(bundleID), role=\(axStringAttribute(kAXRoleAttribute as CFString, for: resolved) ?? "unknown")"
                )
            }
            return resolved
        }

        guard let focusedWindow = axElementAttribute(kAXFocusedWindowAttribute as CFString, for: appElement) else {
            if logDiagnostics {
                VoxtLog.input("Focused input check: no focused window on frontmost app. bundleID=\(bundleID)")
            }
            return nil
        }

        if let focusedWindowElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: focusedWindow),
           let resolved = resolveFocusedElement(focusedWindowElement) {
            if logDiagnostics {
                VoxtLog.input(
                    "Focused input check: using focused window focused element. bundleID=\(bundleID), role=\(axStringAttribute(kAXRoleAttribute as CFString, for: resolved) ?? "unknown")"
                )
            }
            return resolved
        }

        if let focusedDescendant = findFocusedDescendant(in: focusedWindow, depthRemaining: 8),
           let resolved = resolveFocusedElement(focusedDescendant) {
            if logDiagnostics {
                VoxtLog.input(
                    "Focused input check: resolved focused descendant from window subtree. bundleID=\(bundleID), role=\(axStringAttribute(kAXRoleAttribute as CFString, for: resolved) ?? "unknown")"
                )
            }
            return resolved
        }

        if let bestEditableDescendant = findBestWritableTextDescendant(in: focusedWindow, depthRemaining: 8) {
            if logDiagnostics {
                VoxtLog.input(
                    "Focused input check: using best editable descendant from focused window. bundleID=\(bundleID), role=\(axStringAttribute(kAXRoleAttribute as CFString, for: bestEditableDescendant) ?? "unknown")"
                )
            }
            return bestEditableDescendant
        }

        if logDiagnostics {
            VoxtLog.input("Focused input check: falling back to focused window element. bundleID=\(bundleID)")
        }
        return resolveFocusedElement(focusedWindow)
    }

    private func axBoolAttribute(_ attribute: CFString, for element: AXUIElement) -> Bool? {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success, let valueRef else { return nil }
        if let boolValue = valueRef as? Bool {
            return boolValue
        }
        if let numberValue = valueRef as? NSNumber {
            return numberValue.boolValue
        }
        return nil
    }

    private func axStringAttribute(_ attribute: CFString, for element: AXUIElement) -> String? {
        axStringAttribute(attribute, for: element, timeout: Self.axMessagingTimeout)
    }

    private func axStringAttribute(
        _ attribute: CFString,
        for element: AXUIElement,
        timeout: Float
    ) -> String? {
        AXUIElementSetMessagingTimeout(element, timeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success else { return nil }
        return valueRef as? String
    }

    private func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return status == .success && settable.boolValue
    }

    private func axIntAttribute(_ attribute: CFString, for element: AXUIElement) -> Int? {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success, let valueRef else { return nil }
        if let number = valueRef as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func axRangeAttribute(_ attribute: CFString, for element: AXUIElement) -> CFRange? {
        axRangeAttribute(attribute, for: element, timeout: Self.axMessagingTimeout)
    }

    private func axRangeAttribute(
        _ attribute: CFString,
        for element: AXUIElement,
        timeout: Float
    ) -> CFRange? {
        AXUIElementSetMessagingTimeout(element, timeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success,
              let valueRef,
              CFGetTypeID(valueRef) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(valueRef, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private func setAXRangeAttribute(
        _ attribute: CFString,
        range: CFRange,
        for element: AXUIElement
    ) -> Bool {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return false
        }
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        let status = AXUIElementSetAttributeValue(element, attribute, rangeValue)
        return status == .success
    }

    private func hasSelectedTextRange(_ element: AXUIElement) -> Bool {
        axRangeAttribute(kAXSelectedTextRangeAttribute as CFString, for: element) != nil
    }

    private func axParameterizedString(
        _ attribute: CFString,
        range: CFRange,
        for element: AXUIElement
    ) -> String? {
        axParameterizedString(attribute, range: range, for: element, timeout: Self.axMessagingTimeout)
    }

    private func axParameterizedString(
        _ attribute: CFString,
        range: CFRange,
        for element: AXUIElement,
        timeout: Float
    ) -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(element, timeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute,
            rangeValue,
            &valueRef
        )
        guard status == .success, let valueRef else { return nil }
        if let text = valueRef as? String {
            return normalizedAXTextValue(text, for: element)
        }
        if let text = valueRef as? NSAttributedString {
            return normalizedAXTextValue(text.string, for: element)
        }
        return nil
    }

    private func axParameterizedAttributeNames(for element: AXUIElement) -> [String] {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        var valueRef: CFArray?
        let status = AXUIElementCopyParameterizedAttributeNames(element, &valueRef)
        guard status == .success, let names = valueRef as? [String] else { return [] }
        return names
    }

    private func axTextValue(for element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        var valueRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        )

        if let stringValue = valueRef as? String,
           let normalizedStringValue = normalizedAXTextValue(stringValue, for: element) {
            return normalizedStringValue
        }
        if let attributedValue = valueRef as? NSAttributedString,
           let normalizedAttributedValue = normalizedAXTextValue(attributedValue.string, for: element) {
            return normalizedAttributedValue
        }

        if let selectedText = axStringAttribute(kAXSelectedTextAttribute as CFString, for: element),
           let normalizedSelectedText = normalizedAXTextValue(selectedText, for: element) {
            VoxtLog.input(
                "Focused input snapshot: resolved text via selected text attribute. role=\(axStringAttribute(kAXRoleAttribute as CFString, for: element) ?? "unknown"), length=\(normalizedSelectedText.count)"
            )
            return normalizedSelectedText
        }

        if let visibleRange = axRangeAttribute(kAXVisibleCharacterRangeAttribute as CFString, for: element),
           visibleRange.length > 0,
           let visibleText = axParameterizedString(
               kAXStringForRangeParameterizedAttribute as CFString,
               range: visibleRange,
               for: element
           ) {
            VoxtLog.input(
                "Focused input snapshot: resolved text via visible character range. role=\(axStringAttribute(kAXRoleAttribute as CFString, for: element) ?? "unknown"), length=\(visibleText.count)"
            )
            return visibleText
        }

        if let numberOfCharacters = axIntAttribute("AXNumberOfCharacters" as CFString, for: element),
           numberOfCharacters > 0 {
            let fullRange = CFRange(location: 0, length: numberOfCharacters)
            if let fullText = axParameterizedString(
                kAXStringForRangeParameterizedAttribute as CFString,
                range: fullRange,
                for: element
            ) {
                VoxtLog.input(
                    "Focused input snapshot: resolved text via full character range. role=\(axStringAttribute(kAXRoleAttribute as CFString, for: element) ?? "unknown"), length=\(fullText.count)"
                )
                return fullText
            }
        }
        return nil
    }

    private func axElementAttribute(_ attribute: CFString, for element: AXUIElement) -> AXUIElement? {
        axElementAttribute(attribute, for: element, timeout: Self.axMessagingTimeout)
    }

    private func axElementAttribute(
        _ attribute: CFString,
        for element: AXUIElement,
        timeout: Float
    ) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(element, timeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success,
              let valueRef,
              CFGetTypeID(valueRef) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(valueRef, to: AXUIElement.self)
    }

    private func axElementArrayAttribute(_ attribute: CFString, for element: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success,
              let valueRef,
              let array = valueRef as? [Any]
        else {
            return []
        }

        return array.compactMap { item in
            let cfItem = item as AnyObject
            guard CFGetTypeID(cfItem) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(cfItem, to: AXUIElement.self)
        }
    }

    private func writableTextInputElement(from element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth <= 8 else { return nil }

        if isWritableTextInputElement(element) {
            return element
        }

        if let focusedChild = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: element),
           let writableFocusedChild = writableTextInputElement(from: focusedChild, depth: depth + 1) {
            return writableFocusedChild
        }

        for child in axElementArrayAttribute(kAXChildrenAttribute as CFString, for: element) {
            if let writableChild = writableTextInputElement(from: child, depth: depth + 1) {
                return writableChild
            }
        }

        return nil
    }

    private func isWritableTextInputElement(_ element: AXUIElement) -> Bool {
        let role = axStringAttribute(kAXRoleAttribute as CFString, for: element)

        if let role, Self.nonEditableFalsePositiveRoles.contains(role) {
            return false
        }
        if axBoolAttribute("AXEditable" as CFString, for: element) == true {
            return true
        }
        if Self.nativeWritableTextRoles.contains(role ?? "") {
            return true
        }
        let hasSettableTextAttributes =
            isAttributeSettable(kAXSelectedTextRangeAttribute as CFString, on: element)
            || isAttributeSettable(kAXSelectedTextAttribute as CFString, on: element)
            || isAttributeSettable(kAXValueAttribute as CFString, on: element)
        let hasSelectedRange = hasSelectedTextRange(element)

        if Self.genericEditableTextRoles.contains(role ?? "") {
            return hasSelectedRange || hasSettableTextAttributes
        }

        return hasSelectedRange && hasSettableTextAttributes
    }

    private func resolveFocusedElement(_ element: AXUIElement, depthRemaining: Int = 8) -> AXUIElement? {
        guard depthRemaining >= 0 else { return nil }

        if isWritableTextInputElement(element) {
            return element
        }

        if let nestedFocused = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: element),
           let resolvedNestedFocused = resolveFocusedElement(nestedFocused, depthRemaining: depthRemaining - 1) {
            return resolvedNestedFocused
        }

        if let focusedDescendant = findFocusedDescendant(in: element, depthRemaining: depthRemaining - 1),
           let resolvedDescendant = resolveFocusedElement(focusedDescendant, depthRemaining: depthRemaining - 1) {
            return resolvedDescendant
        }

        if let bestEditableDescendant = findBestWritableTextDescendant(in: element, depthRemaining: depthRemaining - 1) {
            return bestEditableDescendant
        }

        return element
    }

    private func findFocusedDescendant(in element: AXUIElement, depthRemaining: Int) -> AXUIElement? {
        guard depthRemaining >= 0 else { return nil }

        if axBoolAttribute(kAXFocusedAttribute as CFString, for: element) == true {
            return element
        }

        for child in axElementArrayAttribute(kAXChildrenAttribute as CFString, for: element) {
            if let nested = findFocusedDescendant(in: child, depthRemaining: depthRemaining - 1) {
                return nested
            }
        }

        return nil
    }

    private func findBestWritableTextDescendant(in element: AXUIElement, depthRemaining: Int) -> AXUIElement? {
        guard depthRemaining >= 0 else { return nil }

        let children = axElementArrayAttribute(kAXChildrenAttribute as CFString, for: element)
        var bestElement: AXUIElement?
        var bestScore = 0

        for child in children {
            let score = writableCandidateScore(for: child)
            if score > bestScore {
                bestScore = score
                bestElement = child
            }

            if let nested = findBestWritableTextDescendant(in: child, depthRemaining: depthRemaining - 1) {
                let nestedScore = writableCandidateScore(for: nested)
                if nestedScore > bestScore {
                    bestScore = nestedScore
                    bestElement = nested
                }
            }
        }

        return bestElement
    }

    private func writableCandidateScore(for element: AXUIElement) -> Int {
        var score = 0
        let role = axStringAttribute(kAXRoleAttribute as CFString, for: element)
        if axBoolAttribute("AXEditable" as CFString, for: element) == true {
            score += 6
        }
        if axBoolAttribute(kAXFocusedAttribute as CFString, for: element) == true {
            score += 4
        }
        if hasSelectedTextRange(element) {
            score += 3
        }
        if isAttributeSettable(kAXSelectedTextRangeAttribute as CFString, on: element) {
            score += 3
        }
        if isAttributeSettable(kAXSelectedTextAttribute as CFString, on: element) {
            score += 3
        }
        if isAttributeSettable(kAXValueAttribute as CFString, on: element) {
            score += 2
        }
        if Self.nativeWritableTextRoles.contains(role ?? "") {
            score += 5
        } else if Self.genericEditableTextRoles.contains(role ?? "") {
            score += 2
        }
        if Self.nonEditableFalsePositiveRoles.contains(role ?? "") {
            score = 0
        }
        return score
    }

    private func normalizedAXTextValue(_ rawValue: String, for element: AXUIElement) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let placeholder = axStringAttribute(kAXPlaceholderValueAttribute as CFString, for: element),
           placeholder.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
            return nil
        }
        if let title = axStringAttribute(kAXTitleAttribute as CFString, for: element),
           title.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
            return nil
        }
        return trimmed
    }

    private func unreadableTextFailureReason(for element: AXUIElement) -> String {
        let selectedRange = axRangeAttribute(kAXSelectedTextRangeAttribute as CFString, for: element)
        let visibleRange = axRangeAttribute(kAXVisibleCharacterRangeAttribute as CFString, for: element)
        let numberOfCharacters = axIntAttribute("AXNumberOfCharacters" as CFString, for: element) ?? -1
        let hasStringForRange = axParameterizedAttributeNames(for: element)
            .contains(kAXStringForRangeParameterizedAttribute as String)
        let diagnostics =
            "numChars=\(numberOfCharacters), selectedRange=\(selectedRange.map { "{\($0.location),\($0.length)}" } ?? "nil"), visibleRange=\(visibleRange.map { "{\($0.location),\($0.length)}" } ?? "nil"), hasStringForRange=\(hasStringForRange)"
        if let placeholder = axStringAttribute(kAXPlaceholderValueAttribute as CFString, for: element),
           let value = axStringAttribute(kAXValueAttribute as CFString, for: element),
           placeholder.trimmingCharacters(in: .whitespacesAndNewlines)
                == value.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "value-matched-placeholder, \(diagnostics)"
        }
        if let title = axStringAttribute(kAXTitleAttribute as CFString, for: element),
           let value = axStringAttribute(kAXValueAttribute as CFString, for: element),
           title.trimmingCharacters(in: .whitespacesAndNewlines)
                == value.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "value-matched-title, \(diagnostics)"
        }
        if !isAttributeSettable(kAXValueAttribute as CFString, on: element) {
            return "ax-value-not-settable, \(diagnostics)"
        }
        return "missing-ax-value, \(diagnostics)"
    }

    private func selectedNSRange(from range: CFRange?) -> NSRange? {
        guard let range, range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func focusedInputSnapshotSummary(_ snapshot: FocusedInputTextSnapshot) -> String {
        let preview = String(snapshot.text.prefix(80))
        let selectedRangeDescription = snapshot.selectedRange.map {
            "{\($0.location),\($0.length)}"
        } ?? "nil"
        return
            "bundleID=\(snapshot.bundleIdentifier ?? "nil") pid=\(snapshot.processIdentifier.map(String.init) ?? "nil") "
                + "role=\(snapshot.role ?? "nil") editable=\(snapshot.isEditable) "
                + "focused=\(snapshot.isFocusedTarget) selectedRange=\(selectedRangeDescription) textLength=\(snapshot.text.count) "
                + "textSource=\(snapshot.textSource ?? "nil") preview=\(preview)"
    }

    @discardableResult
    private func restoreSessionTargetApplicationIfNeeded() -> Bool {
        guard let ownBundleID = Bundle.main.bundleIdentifier else { return false }
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmostApplication?.bundleIdentifier
        let frontmostPID = frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier

        guard frontmostPID == ownPID || frontmostBundleID == ownBundleID else {
            return false
        }

        if let targetPID = sessionTargetApplicationPID,
           let targetApplication = NSRunningApplication(processIdentifier: targetPID),
           !targetApplication.isTerminated {
            VoxtLog.input(
                "Restoring focus to session target app before text injection. bundleID=\(targetApplication.bundleIdentifier ?? "unknown"), pid=\(targetPID)"
            )
            return targetApplication.activate(options: [])
        }

        if let targetBundleID = sessionTargetApplicationBundleID,
           let targetApplication = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID)
            .first(where: { !$0.isTerminated }) {
            VoxtLog.input(
                "Restoring focus to session target app by bundle ID before text injection. bundleID=\(targetBundleID), pid=\(targetApplication.processIdentifier)"
            )
            return targetApplication.activate(options: [])
        }

        VoxtLog.input(
            "Session target app restoration skipped: target app unavailable. targetBundleID=\(sessionTargetApplicationBundleID ?? "nil"), targetPID=\(sessionTargetApplicationPID.map(String.init) ?? "nil")"
        )
        return false
    }

    func typeText(
        _ text: String,
        restoreSessionTarget: Bool = true,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }

        let injectionStartedAt = Date()
        let pasteboard = NSPasteboard.general
        let previous = readStringFromPasteboard(pasteboard) ?? ""
        let accessibilityTrusted = AccessibilityPermissionManager.isTrusted()
        let keepResultInClipboard = autoCopyWhenNoFocusedInput

        guard accessibilityTrusted else {
            writeTextToPasteboard(text)
            promptForAccessibilityPermission()
            VoxtLog.inputWarning("Accessibility permission missing. Transcription copied; paste manually after granting permission.")
            completion?(false)
            return
        }

        let activationRestored = restoreSessionTarget ? restoreSessionTargetApplicationIfNeeded() : false
        let activationDelay: TimeInterval = activationRestored ? 0.04 : 0
        VoxtLog.input(
            "Text injection prepared. characters=\(text.count), activationRestored=\(activationRestored), restoreSessionTarget=\(restoreSessionTarget), activationDelayMs=\(Int(activationDelay * 1000))",
            verbose: true
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) { [weak self] in
            guard let self else {
                completion?(false)
                return
            }

            self.pasteTextByShortcut(
                text,
                previousClipboardValue: previous,
                keepResultInClipboard: keepResultInClipboard,
                completion: { didInject in
                    let elapsedMs = Int(Date().timeIntervalSince(injectionStartedAt) * 1000)
                    VoxtLog.input(
                        "Text injection completed via paste fallback. characters=\(text.count), elapsedMs=\(elapsedMs), didInject=\(didInject)"
                    )
                    completion?(didInject)
                }
            )
        }
    }

    func pressAutoKeyAfterTextInjection(
        _ hotkey: HotkeyPreference.Hotkey,
        delay: TimeInterval = 0.12
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard AccessibilityPermissionManager.isTrusted() else {
                VoxtLog.inputWarning("Auto Key skipped: accessibility permission missing.")
                return
            }
            guard let source = CGEventSource(stateID: .hidSystemState) else {
                VoxtLog.error("Auto Key failed: unable to create CGEventSource")
                return
            }
            guard case .keyboard(let keyCode) = hotkey.input,
                  keyCode != HotkeyPreference.modifierOnlyKeyCode
            else {
                VoxtLog.inputWarning("Auto Key skipped: unsupported shortcut input.")
                return
            }

            let cgKeyCode = CGKeyCode(keyCode)
            let flags = Self.cgEventFlags(for: hotkey.modifiers)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cgKeyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cgKeyCode, keyDown: false)

            guard let keyDown, let keyUp else {
                VoxtLog.error("Auto Key failed: unable to create key events")
                return
            }

            keyDown.flags = flags
            keyUp.flags = flags
            HotkeyEventSupport.markAsVoxtInjected(keyDown)
            HotkeyEventSupport.markAsVoxtInjected(keyUp)
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            VoxtLog.input(
                "Auto Key event posted after text injection. hotkey=\(HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: false))",
                verbose: true
            )
        }
    }

    private static func cgEventFlags(for modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.control) {
            flags.insert(.maskControl)
        }
        if modifiers.contains(.option) {
            flags.insert(.maskAlternate)
        }
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }
        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
        }
        if modifiers.contains(.function) {
            flags.insert(.maskSecondaryFn)
        }
        return flags
    }

    func beginOverlayOutputDelivery() {
        overlayState.isRequesting = true
        overlayState.isCompleting = false
        if overlayState.displayMode != .answer {
            overlayState.displayMode = .processing
        }
    }

    func endOverlayOutputDelivery() {
        overlayState.isRequesting = false
    }

    func writeTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func cacheLatestInjectableOutputText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        latestInjectableOutputText = trimmed
    }

    private func resolvedLatestInjectableOutputText() -> String? {
        let cached = latestInjectableOutputText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cached.isEmpty {
            return cached
        }

        let historyText = historyStore.latestEntryText()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return historyText.isEmpty ? nil : historyText
    }

    func injectLatestResultByCustomPasteHotkey() {
        guard let latestText = resolvedLatestInjectableOutputText() else {
            showOverlayStatus(AppLocalization.localizedString("No recent result available to paste yet."), clearAfter: 2.0)
            return
        }

        typeText(latestText)
    }

    private func pasteTextByShortcut(
        _ text: String,
        previousClipboardValue: String,
        keepResultInClipboard: Bool,
        completion: ((Bool) -> Void)?
    ) {
        writeTextToPasteboard(text)

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            VoxtLog.error("typeText fallback failed: unable to create CGEventSource")
            completion?(false)
            return
        }

        let vKeyCode: CGKeyCode = 0x09
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand

        guard cmdDown != nil, cmdUp != nil else {
            VoxtLog.error("typeText fallback failed: unable to create key events")
            completion?(false)
            return
        }

        HotkeyEventSupport.markAsVoxtInjected(cmdDown)
        HotkeyEventSupport.markAsVoxtInjected(cmdUp)
        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)
        completion?(true)

        guard !keepResultInClipboard else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if !previousClipboardValue.isEmpty {
                pasteboard.setString(previousClipboardValue, forType: .string)
            }
        }
    }

    private func promptForAccessibilityPermission() {
        _ = AccessibilityPermissionManager.request(prompt: true)
    }

    func makePendingOutputReplacementTransaction(
        previewText: String,
        sessionID: UUID,
        expectedBundleID: String?
    ) -> PendingOutputReplacementTransaction? {
        let normalizedPreview = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPreview.isEmpty else { return nil }
        guard let snapshot = currentFocusedInputTextSnapshot(
            expectedBundleID: expectedBundleID,
            logDiagnostics: false
        ) else {
            return nil
        }
        guard let selectedRange = snapshot.selectedRange else {
            VoxtLog.input("Preview replacement transaction skipped: selected range unavailable.")
            return nil
        }

        let baselineNSString = snapshot.text as NSString
        guard selectedRange.location >= 0,
              NSMaxRange(selectedRange) <= baselineNSString.length else {
            VoxtLog.input("Preview replacement transaction skipped: selected range exceeded baseline text.")
            return nil
        }

        let prefix = baselineNSString.substring(to: selectedRange.location)
        let suffix = baselineNSString.substring(from: NSMaxRange(selectedRange))
        let expectedTextAfterPreview = prefix + normalizedPreview + suffix
        let previewLength = (normalizedPreview as NSString).length

        return PendingOutputReplacementTransaction(
            sessionID: sessionID,
            bundleIdentifier: snapshot.bundleIdentifier ?? expectedBundleID,
            baselineText: snapshot.text,
            expectedTextAfterPreview: expectedTextAfterPreview,
            previewText: normalizedPreview,
            replacementRange: NSRange(location: selectedRange.location, length: previewLength)
        )
    }

    func performPendingOutputReplacement(
        _ transaction: PendingOutputReplacementTransaction,
        replacementText: String
    ) async -> Bool {
        let trimmedReplacement = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReplacement.isEmpty else {
            VoxtLog.input("Pending output replacement skipped: replacement text was empty.")
            return false
        }

        guard let snapshot = currentFocusedInputTextSnapshot(
            expectedBundleID: transaction.bundleIdentifier,
            logDiagnostics: false
        ) else {
            VoxtLog.input("Pending output replacement skipped: focused input snapshot unavailable.")
            return false
        }

        guard snapshot.text == transaction.expectedTextAfterPreview else {
            VoxtLog.input(
                "Pending output replacement skipped: focused input changed after preview injection. baselineChars=\(transaction.baselineText.count), expectedChars=\(transaction.expectedTextAfterPreview.count), currentChars=\(snapshot.text.count)"
            )
            return false
        }

        guard let processIdentifier = snapshot.processIdentifier,
              let focusedElement = focusedAXElement(preferredProcessID: processIdentifier, logDiagnostics: false)
        else {
            VoxtLog.input("Pending output replacement skipped: focused AX element unavailable.")
            return false
        }

        let writableElement = writableTextInputElement(from: focusedElement) ?? (
            isWritableTextInputElement(focusedElement) ? focusedElement : nil
        )
        guard let writableElement else {
            VoxtLog.input("Pending output replacement skipped: writable AX element unavailable.")
            return false
        }

        let replacementCFRange = CFRange(
            location: transaction.replacementRange.location,
            length: transaction.replacementRange.length
        )
        guard setAXRangeAttribute(
            kAXSelectedTextRangeAttribute as CFString,
            range: replacementCFRange,
            for: writableElement
        ) else {
            VoxtLog.input("Pending output replacement skipped: unable to set selected text range.")
            return false
        }

        let didInject = await typeTextAsync(trimmedReplacement)
        if didInject {
            sessionOutputDestinationContext = captureCurrentOutputDestinationContext()
            VoxtLog.input(
                "Pending output replacement succeeded. previewChars=\(transaction.previewText.count), replacementChars=\(trimmedReplacement.count)"
            )
        }
        return didInject
    }

    private func typeTextAsync(_ text: String) async -> Bool {
        await withCheckedContinuation { continuation in
            typeText(text) { didInject in
                continuation.resume(returning: didInject)
            }
        }
    }
}

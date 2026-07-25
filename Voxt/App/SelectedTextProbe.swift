// SelectedTextProbe.swift
// System selection probe for dictionary / note / translation hotkeys.

import Foundation
import AppKit
import ApplicationServices
import Carbon

extension AppDelegate {
    private static let selectionAXFocusTimeout: Float = 0.2
    /// After primary FocusedUIElement failed, keep secondary AX cheap.
    private static let selectionAXFallbackTimeout: Float = 0.05

    func selectedTextFromSystemSelection() -> String? {
        let appBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        let isBrowser = isBrowserBundleID(appBundleID == "unknown" ? nil : appBundleID)
        let axTrusted = AccessibilityPermissionManager.isTrusted()

        VoxtLog.input(
            "selectionProbe.begin: app=\(appBundleID) name=\(appName) browser=\(isBrowser) axTrusted=\(axTrusted)"
        )

        guard axTrusted else {
            logSelectionProbeResult(
                range: nil,
                textSource: "nil",
                app: appBundleID,
                isBrowser: isBrowser,
                detail: "accessibility-not-trusted"
            )
            return nil
        }

        let focusResolve = resolveFocusForSystemSelection()
        let focusedElement = focusResolve.focusedElement
        logSelectionFocusedElement(focusedElement)

        let rawSelectedRange = focusedElement.flatMap {
            axRangeAttribute(
                kAXSelectedTextRangeAttribute as CFString,
                for: $0,
                timeout: Self.selectionAXFocusTimeout
            )
        }
        VoxtLog.input(
            "selectionProbe.range: raw=\(selectionRangeDescription(rawSelectedRange)) nonEmpty=\(nonEmptySelectedTextRange(rawSelectedRange) != nil)"
        )

        if SelectedTextSystemSelectionSupport.isConfirmedCaretOnly(selectedTextRange: rawSelectedRange) {
            logSelectionProbeResult(
                range: rawSelectedRange,
                textSource: "nil",
                app: appBundleID,
                isBrowser: isBrowser,
                detail: "confirmed-caret-only"
            )
            return nil
        }

        if let text = readSelectedTextNonDestructively(
            focusedElement: focusedElement,
            rawSelectedRange: rawSelectedRange,
            isBrowser: isBrowser,
            appBundleID: appBundleID
        ) {
            return text
        }

        return readSelectedTextBySimulatedCopyIfAllowed(
            focusedElement: focusedElement,
            rawSelectedRange: rawSelectedRange,
            isBrowser: isBrowser,
            appBundleID: appBundleID,
            axWindowCandidatesAvailable: focusResolve.candidateWindowCount > 0
        )
    }

    // MARK: - Non-destructive reads

    private func readSelectedTextNonDestructively(
        focusedElement: AXUIElement?,
        rawSelectedRange: CFRange?,
        isBrowser: Bool,
        appBundleID: String
    ) -> String? {
        if let focusedElement {
            let axSelectedResult = probeAXSelectedText(from: focusedElement)
            VoxtLog.input(
                "selectionProbe.read.axSelected: status=\(axSelectedResult.status) chars=\(axSelectedResult.characterCount) preview=\(selectionPreview(axSelectedResult.text))"
            )
            if let text = axSelectedResult.text {
                logSelectionProbeResult(
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
                timeout: Self.selectionAXFocusTimeout
            )
            let trimmedRangeText = rangeText?.trimmingCharacters(in: .whitespacesAndNewlines)
            VoxtLog.input(
                "selectionProbe.read.stringForRange: chars=\(trimmedRangeText?.count ?? 0) preview=\(selectionPreview(trimmedRangeText))"
            )
            if let trimmedRangeText, !trimmedRangeText.isEmpty {
                logSelectionProbeResult(
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
                logSelectionProbeResult(
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

        if isBrowser {
            let scriptText = selectedTextFromBrowserAppleScript(bundleID: appBundleID)
            VoxtLog.input(
                "selectionProbe.read.appleScript: chars=\(scriptText?.count ?? 0) preview=\(selectionPreview(scriptText))"
            )
            if let text = scriptText {
                logSelectionProbeResult(
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

        return nil
    }

    private func readSelectedTextBySimulatedCopyIfAllowed(
        focusedElement: AXUIElement?,
        rawSelectedRange: CFRange?,
        isBrowser: Bool,
        appBundleID: String,
        axWindowCandidatesAvailable: Bool
    ) -> String? {
        let copiesLineOnEmptySelection = SelectedTextSystemSelectionSupport
            .copiesCurrentLineWhenSelectionEmpty(bundleID: appBundleID)
        let allowCopy = SelectedTextSystemSelectionSupport.shouldAttemptSimulatedCopy(
            focusedElementAvailable: focusedElement != nil,
            selectedTextRange: rawSelectedRange,
            isBrowser: isBrowser,
            copiesLineOnEmptySelection: copiesLineOnEmptySelection
        )
        let allowBlackoutProbe = SelectedTextSystemSelectionSupport.shouldAttemptAXBlackoutClipboardProbe(
            focusedElementAvailable: focusedElement != nil,
            axWindowCandidatesAvailable: axWindowCandidatesAvailable,
            copiesLineOnEmptySelection: copiesLineOnEmptySelection
        )
        VoxtLog.input(
            "selectionProbe.copy.policy: allow=\(allowCopy) blackoutProbe=\(allowBlackoutProbe) focused=\(focusedElement != nil) windows=\(axWindowCandidatesAvailable) range=\(selectionRangeDescription(rawSelectedRange)) browser=\(isBrowser) copiesLineOnEmpty=\(copiesLineOnEmptySelection)"
        )

        if allowCopy, let text = selectedTextBySimulatedCopy(reason: "policyAllowed") {
            logSelectionProbeResult(
                range: rawSelectedRange,
                textSource: "copy",
                app: appBundleID,
                isBrowser: isBrowser,
                detail: "chars=\(text.count)"
            )
            return text
        }

        if allowBlackoutProbe {
            VoxtLog.input("selectionProbe.copy.blackoutProbe: begin")
            if let capture = captureTextBySimulatedCopy(reason: "axBlackoutLineCopyEditor") {
                if SelectedTextSystemSelectionSupport.looksLikeEmptySelectionLineCopy(
                    rawClipboardText: capture.raw
                ) {
                    VoxtLog.input(
                        "selectionProbe.copy.blackoutProbe: rejected-likely-line-copy chars=\(capture.trimmed.count) preview=\(selectionPreview(capture.raw))"
                    )
                    logSelectionProbeResult(
                        range: rawSelectedRange,
                        textSource: "nil",
                        app: appBundleID,
                        isBrowser: isBrowser,
                        detail: "ax-blackout-rejected-line-copy"
                    )
                    return nil
                }
                logSelectionProbeResult(
                    range: rawSelectedRange,
                    textSource: "copyBlackoutFiltered",
                    app: appBundleID,
                    isBrowser: isBrowser,
                    detail: "chars=\(capture.trimmed.count)"
                )
                return capture.trimmed
            }
            VoxtLog.input("selectionProbe.copy.blackoutProbe: copy-missed")
        }

        let denyDetail = SelectedTextSystemSelectionSupport.denialDetail(
            allowCopy: allowCopy,
            focusedElementAvailable: focusedElement != nil,
            selectedTextRange: rawSelectedRange,
            isBrowser: isBrowser,
            copiesLineOnEmptySelection: copiesLineOnEmptySelection
        )
        logSelectionProbeResult(
            range: rawSelectedRange,
            textSource: "nil",
            app: appBundleID,
            isBrowser: isBrowser,
            detail: denyDetail
        )
        return nil
    }

    // MARK: - Focus resolve

    private struct SystemSelectionFocusResolve {
        let focusedElement: AXUIElement?
        let candidateWindowCount: Int
    }

    private func resolveFocusForSystemSelection() -> SystemSelectionFocusResolve {
        // Actual focused element only — never best-editable / leftover-field fallbacks.
        if let systemFocused = copyFocusedUIElement(
            from: AXUIElementCreateSystemWide(),
            source: "systemWide"
        ) {
            return SystemSelectionFocusResolve(focusedElement: systemFocused, candidateWindowCount: 0)
        }

        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            VoxtLog.input("selectionProbe.focusedResolve: all focus lookups failed no-frontmost-app")
            return SystemSelectionFocusResolve(focusedElement: nil, candidateWindowCount: 0)
        }

        let appElement = AXUIElementCreateApplication(processID)
        if let appFocused = copyFocusedUIElement(from: appElement, source: "frontmostApp") {
            return SystemSelectionFocusResolve(focusedElement: appFocused, candidateWindowCount: 0)
        }

        let candidateWindows = selectionProbeCandidateWindows(from: appElement)
        if candidateWindows.isEmpty {
            VoxtLog.input("selectionProbe.focusedResolve: no candidate windows")
            VoxtLog.input("selectionProbe.focusedResolve: all focus lookups failed")
            return SystemSelectionFocusResolve(focusedElement: nil, candidateWindowCount: 0)
        }

        for (index, window) in candidateWindows.enumerated() {
            if let descendant = findFocusedDescendant(in: window, depthRemaining: 6) {
                VoxtLog.input(
                    "selectionProbe.focusedResolve: source=candidateWindowDescendant[\(index)] ok"
                )
                return SystemSelectionFocusResolve(
                    focusedElement: descendant,
                    candidateWindowCount: candidateWindows.count
                )
            }
        }

        VoxtLog.input(
            "selectionProbe.focusedResolve: candidate windows=\(candidateWindows.count) but no focused descendant"
        )
        VoxtLog.input("selectionProbe.focusedResolve: all focus lookups failed")
        return SystemSelectionFocusResolve(
            focusedElement: nil,
            candidateWindowCount: candidateWindows.count
        )
    }

    private func selectionProbeCandidateWindows(from appElement: AXUIElement) -> [AXUIElement] {
        var windows: [AXUIElement] = []

        func appendUnique(_ window: AXUIElement) {
            for existing in windows where CFEqual(existing, window) {
                return
            }
            windows.append(window)
        }

        var hadFocusedWindow = false
        if let focusedWindow = axElementAttribute(
            kAXFocusedWindowAttribute as CFString,
            for: appElement,
            timeout: Self.selectionAXFallbackTimeout
        ) {
            hadFocusedWindow = true
            appendUnique(focusedWindow)
        }
        if let mainWindow = axElementAttribute(
            kAXMainWindowAttribute as CFString,
            for: appElement,
            timeout: Self.selectionAXFallbackTimeout
        ) {
            appendUnique(mainWindow)
        }
        let listedWindows = axElementArrayAttribute(
            kAXWindowsAttribute as CFString,
            for: appElement,
            timeout: Self.selectionAXFallbackTimeout
        )
        for window in listedWindows.prefix(3) {
            appendUnique(window)
        }
        VoxtLog.input(
            "selectionProbe.windows: hadFocused=\(hadFocusedWindow) totalCandidates=\(windows.count) listed=\(listedWindows.count)"
        )
        return windows
    }

    private func copyFocusedUIElement(from root: AXUIElement, source: String) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(root, Self.selectionAXFocusTimeout)
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
                "selectionProbe.focusedResolve: source=\(source) failed status=\(focusedStatus.rawValue) timeoutSec=\(Self.selectionAXFocusTimeout)"
            )
            return nil
        }
        VoxtLog.input("selectionProbe.focusedResolve: source=\(source) ok")
        return unsafeBitCast(focusedElementRef, to: AXUIElement.self)
    }

    // MARK: - AX / AppleScript / clipboard readers

    private struct AXSelectedTextProbeResult {
        let text: String?
        let status: String
        let characterCount: Int
    }

    private func probeAXSelectedText(from element: AXUIElement) -> AXSelectedTextProbeResult {
        AXUIElementSetMessagingTimeout(element, Self.selectionAXFocusTimeout)
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

    private func selectedTextFromAXTextMarker(startingAt element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for depth in 0..<6 {
            guard let currentElement = current else { break }
            let role = axStringAttribute(
                kAXRoleAttribute as CFString,
                for: currentElement,
                timeout: Self.selectionAXFocusTimeout
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
                timeout: Self.selectionAXFocusTimeout
            )
        }
        return nil
    }

    private struct TextMarkerProbeResult {
        let text: String?
        let status: String
    }

    private func selectedTextFromAXTextMarkerRange(on element: AXUIElement) -> TextMarkerProbeResult {
        AXUIElementSetMessagingTimeout(element, Self.selectionAXFocusTimeout)
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

    private struct SimulatedCopyCapture {
        let raw: String

        var trimmed: String {
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func selectedTextBySimulatedCopy(reason: String = "unspecified") -> String? {
        captureTextBySimulatedCopy(reason: reason)?.trimmed
    }

    private func captureTextBySimulatedCopy(reason: String = "unspecified") -> SimulatedCopyCapture? {
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

        let raw = readStringFromPasteboard(pasteboard) ?? ""

        pasteboard.clearContents()
        if let previous, !previous.isEmpty {
            pasteboard.setString(previous, forType: .string)
        }

        let capture = SimulatedCopyCapture(raw: raw)
        guard !capture.trimmed.isEmpty else {
            VoxtLog.input(
                "selectionProbe.copy.miss: empty-after-change changeCount=\(copiedChangeCount)"
            )
            return nil
        }
        VoxtLog.input(
            "selectionProbe.copy.ok: reason=\(reason) chars=\(capture.trimmed.count) preview=\(selectionPreview(capture.raw))"
        )
        return capture
    }

    // MARK: - Logging helpers

    private func logSelectionFocusedElement(_ focusedElement: AXUIElement?) {
        guard let focusedElement else {
            VoxtLog.input("selectionProbe.focused: element=nil")
            return
        }
        let role = axStringAttribute(
            kAXRoleAttribute as CFString,
            for: focusedElement,
            timeout: Self.selectionAXFocusTimeout
        ) ?? "nil"
        let subrole = axStringAttribute(
            kAXSubroleAttribute as CFString,
            for: focusedElement,
            timeout: Self.selectionAXFocusTimeout
        ) ?? "nil"
        VoxtLog.input("selectionProbe.focused: role=\(role) subrole=\(subrole)")
    }

    private func nonEmptySelectedTextRange(_ range: CFRange?) -> CFRange? {
        guard let range,
              SelectedTextSystemSelectionSupport.hasNonEmptySelectedTextRange(length: range.length) else {
            return nil
        }
        return range
    }

    private func logSelectionProbeResult(
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
}

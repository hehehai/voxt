import Foundation
import AppKit
import ApplicationServices

extension AppDelegate {
    private static let axMessagingTimeout: Float = 0.05
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
    private static let electronCDPInputSnapshotJavaScript = """
    (() => {
        const deepActiveElement = (root) => {
            let current = root && root.activeElement ? root.activeElement : null;
            while (current && current.shadowRoot && current.shadowRoot.activeElement) {
                current = current.shadowRoot.activeElement;
            }
            return current;
        };

        const elementSnapshot = (element, source) => {
            if (!element) {
                return { text: "", selectionStart: 0, selectionEnd: 0, tag: null, source };
            }

            if (typeof element.value === "string") {
                return {
                    text: element.value,
                    selectionStart: typeof element.selectionStart === "number" ? element.selectionStart : 0,
                    selectionEnd: typeof element.selectionEnd === "number" ? element.selectionEnd : 0,
                    tag: element.tagName || null,
                    source
                };
            }

            if (element.isContentEditable) {
                return {
                    text: element.innerText || element.textContent || "",
                    selectionStart: 0,
                    selectionEnd: 0,
                    tag: element.tagName || null,
                    source
                };
            }

            if (element.classList && element.classList.contains("cm-content")) {
                return {
                    text: element.innerText || element.textContent || "",
                    selectionStart: 0,
                    selectionEnd: 0,
                    tag: element.tagName || null,
                    source
                };
            }

            return {
                text: "",
                selectionStart: 0,
                selectionEnd: 0,
                tag: element.tagName || null,
                source
            };
        };

        const active = deepActiveElement(document);
        const candidates = [elementSnapshot(active, "active-element")];
        const querySelectors = [
            "textarea",
            "input",
            "[contenteditable='true']",
            "[role='textbox']",
            ".cm-content",
            "[data-lexical-editor='true']"
        ];

        for (const selector of querySelectors) {
            const match = document.querySelector(selector);
            if (match) {
                candidates.push(elementSnapshot(match, `query:${selector}`));
            }
        }

        const resolved = candidates.find((item) => typeof item.text === "string" && item.text.trim().length > 0)
            || candidates[0]
            || { text: "", selectionStart: 0, selectionEnd: 0, tag: null, source: "none" };

        return JSON.stringify(resolved);
    })()
    """
    private static let electronCDPInputSnapshotJavaScriptEscaped = electronCDPInputSnapshotJavaScript
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: " ")
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
        let failureReason: String?
        let textSource: String?
    }

    private struct ElectronCDPTarget: Decodable {
        let id: String
        let type: String
        let title: String?
        let url: String?
        let webSocketDebuggerUrl: String?
    }

    private struct ElectronCDPEvaluationResponse: Decodable {
        struct ResultContainer: Decodable {
            struct RemoteObject: Decodable {
                let value: String?
            }

            let result: RemoteObject?
        }

        struct CDPError: Decodable {
            let message: String
        }

        let id: Int?
        let result: ResultContainer?
        let error: CDPError?
    }

    private struct ElectronCDPInputSnapshotPayload: Decodable {
        let text: String
        let selectionStart: Int
        let selectionEnd: Int
        let tag: String?
        let source: String?
    }

    private enum ElectronCDPClientError: LocalizedError {
        case socketCreateFailed
        case socketConnectFailed
        case socketWriteFailed
        case socketReadFailed
        case invalidHTTPResponse
        case invalidWebSocketHandshake
        case invalidWebSocketFrame

        var errorDescription: String? {
            switch self {
            case .socketCreateFailed:
                return "socket create failed"
            case .socketConnectFailed:
                return "socket connect failed"
            case .socketWriteFailed:
                return "socket write failed"
            case .socketReadFailed:
                return "socket read failed"
            case .invalidHTTPResponse:
                return "invalid HTTP response"
            case .invalidWebSocketHandshake:
                return "invalid websocket handshake"
            case .invalidWebSocketFrame:
                return "invalid websocket frame"
            }
        }
    }

    func selectedTextFromSystemSelection() -> String? {
        if let axSelected = selectedTextFromAXFocusedElement(),
           !axSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return axSelected
        }
        return selectedTextBySimulatedCopy()
    }

    private func selectedTextFromAXFocusedElement() -> String? {
        guard AccessibilityPermissionManager.isTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedStatus == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var selectedTextRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        guard selectedStatus == .success, let selectedTextRef else {
            return nil
        }

        if let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            return selectedText
        }
        if let selectedText = selectedTextRef as? NSAttributedString, !selectedText.string.isEmpty {
            return selectedText.string
        }
        return nil
    }

    private func selectedTextBySimulatedCopy() -> String? {
        guard AccessibilityPermissionManager.isTrusted() else { return nil }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount

        let cKeyCode: CGKeyCode = 0x08
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand
        guard cmdDown != nil, cmdUp != nil else { return nil }

        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)

        let deadline = Date().addingTimeInterval(0.06)
        while pasteboard.changeCount == originalChangeCount, Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        let copiedChangeCount = pasteboard.changeCount
        guard copiedChangeCount != originalChangeCount else {
            return nil
        }

        let copied = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        pasteboard.clearContents()
        if let previous, !previous.isEmpty {
            pasteboard.setString(previous, forType: .string)
        }

        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    func hasWritableFocusedTextInput() -> Bool {
        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let focusedElement = focusedAXElement(preferredProcessID: processID) else {
            VoxtLog.info("Focused input check: no focused AX element.")
            return false
        }

        if let writableElement = writableTextInputElement(from: focusedElement) {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: writableElement) ?? "unknown"
            let editable = isWritableTextInputElement(writableElement)
            let valueSettable = isAttributeSettable(kAXValueAttribute as CFString, on: writableElement)
            VoxtLog.info(
                "Focused input check: writable descendant detected. role=\(role), editable=\(editable), valueSettable=\(valueSettable)"
            )
            return true
        }

        let editable = axBoolAttribute("AXEditable" as CFString, for: focusedElement)
        if editable == true {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) ?? "unknown"
            VoxtLog.info("Focused input check: editable AX element detected. role=\(role)")
            return true
        }

        if isAttributeSettable(kAXValueAttribute as CFString, on: focusedElement) {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) ?? "unknown"
            VoxtLog.info("Focused input check: settable AX value detected. role=\(role)")
            return true
        }

        guard let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) else {
            VoxtLog.info(
                "Focused input check: role unavailable. editable=\(editable == true), valueSettable=false"
            )
            return false
        }

        let isWritable = Self.nativeWritableTextRoles.contains(role)
        VoxtLog.info(
            "Focused input check: role=\(role), editable=\(editable == true), valueSettable=false, result=\(isWritable)"
        )
        return isWritable
    }

    func currentFocusedInputTextSnapshot(
        expectedBundleID: String? = nil
    ) -> FocusedInputTextSnapshot? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            VoxtLog.info("Focused input snapshot unavailable: no frontmost application.")
            return nil
        }
        if let expectedBundleID,
           let bundleIdentifier = frontmostApplication.bundleIdentifier,
           bundleIdentifier != expectedBundleID {
            VoxtLog.info(
                "Focused input snapshot skipped: frontmost app changed. expectedBundleID=\(expectedBundleID), actualBundleID=\(bundleIdentifier)"
            )
            return nil
        }

        let bundleIdentifier = frontmostApplication.bundleIdentifier
        let processIdentifier = frontmostApplication.processIdentifier

        guard let focusedElement = focusedAXElement(preferredProcessID: processIdentifier) else {
            VoxtLog.info(
                "Focused input snapshot unavailable: no focused AX element. bundleID=\(bundleIdentifier ?? "unknown")"
            )
            return nil
        }

        let writableElement = writableTextInputElement(from: focusedElement) ?? (
            isWritableTextInputElement(focusedElement) ? focusedElement : nil
        )
        guard let writableElement else {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) ?? "unknown"
            VoxtLog.info(
                "Focused input snapshot unavailable: no writable text element found. bundleID=\(bundleIdentifier ?? "unknown"), role=\(role)"
            )
            return nil
        }

        let role = axStringAttribute(kAXRoleAttribute as CFString, for: writableElement)
        let isFocusedTarget = axBoolAttribute(kAXFocusedAttribute as CFString, for: writableElement) == true
        let value = axTextValue(for: writableElement)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text = value, !text.isEmpty else {
            let textFailureReason = unreadableTextFailureReason(for: writableElement)
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: writableElement) ?? "unknown"
            VoxtLog.info(
                "Focused input snapshot unavailable: writable element has empty/unreadable value. bundleID=\(bundleIdentifier ?? "unknown"), role=\(role), failureReason=\(textFailureReason)"
            )
            return nil
        }

        let snapshot = FocusedInputTextSnapshot(
            text: text,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            role: role,
            isEditable: isWritableTextInputElement(writableElement),
            isFocusedTarget: isFocusedTarget,
            failureReason: nil,
            textSource: "ax-value"
        )
        VoxtLog.info("Focused input snapshot ready: \(focusedInputSnapshotSummary(snapshot))")
        return snapshot
    }

    func currentFocusedInputTextSnapshotForAutomaticDictionaryLearning(
        expectedBundleID: String? = nil
    ) async -> FocusedInputTextSnapshot? {
        if let snapshot = currentFocusedInputTextSnapshot(expectedBundleID: expectedBundleID) {
            return snapshot
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        if let expectedBundleID,
           let bundleIdentifier = frontmostApplication.bundleIdentifier,
           bundleIdentifier != expectedBundleID {
            return nil
        }

        if let cdpSnapshot = await electronCDPFocusedInputTextSnapshot(
            bundleIdentifier: frontmostApplication.bundleIdentifier,
            processIdentifier: frontmostApplication.processIdentifier
        ) {
            VoxtLog.info("Focused input snapshot ready via CDP: \(focusedInputSnapshotSummary(cdpSnapshot))")
            return cdpSnapshot
        }

        return nil
    }

    private func focusedAXElement(preferredProcessID: pid_t) -> AXUIElement? {
        guard AccessibilityPermissionManager.isTrusted() else {
            VoxtLog.info("Focused input check: accessibility not trusted.")
            return nil
        }

        if let appFocusedElement = focusedAXElement(for: preferredProcessID) {
            return appFocusedElement
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        if let systemFocusedElement = systemFocusedAXElement() {
            VoxtLog.info("Focused input check: falling back to system-wide focused element. bundleID=\(bundleID)")
            return systemFocusedElement
        }

        VoxtLog.info("Focused input check: app/system focus resolution failed. bundleID=\(bundleID)")
        return nil
    }

    private func electronCDPFocusedInputTextSnapshot(
        bundleIdentifier: String?,
        processIdentifier: pid_t?
    ) async -> FocusedInputTextSnapshot? {
        guard let processIdentifier else { return nil }
        guard let port = commandLineRemoteDebuggingPort(for: processIdentifier) else {
            VoxtLog.info(
                "Focused input CDP fallback unavailable: remote debugging port missing. bundleID=\(bundleIdentifier ?? "unknown"), pid=\(processIdentifier)"
            )
            return nil
        }

        do {
            guard let target = try await electronCDPPageTarget(port: port) else {
                VoxtLog.info(
                    "Focused input CDP fallback unavailable: no page target. bundleID=\(bundleIdentifier ?? "unknown"), pid=\(processIdentifier), port=\(port)"
                )
                return nil
            }
            guard let payload = try await electronCDPInputPayload(
                webSocketDebuggerURL: target.webSocketDebuggerUrl,
                port: port
            ) else {
                VoxtLog.info(
                    "Focused input CDP fallback unavailable: active element payload empty. bundleID=\(bundleIdentifier ?? "unknown"), pid=\(processIdentifier), port=\(port), targetTitle=\(target.title ?? "nil")"
                )
                return nil
            }

            let trimmedText = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                VoxtLog.info(
                    "Focused input CDP fallback unavailable: extracted text empty. bundleID=\(bundleIdentifier ?? "unknown"), pid=\(processIdentifier), port=\(port), tag=\(payload.tag ?? "nil"), source=\(payload.source ?? "nil")"
                )
                return nil
            }

            return FocusedInputTextSnapshot(
                text: trimmedText,
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier,
                role: payload.tag ?? "CDP",
                isEditable: true,
                isFocusedTarget: true,
                failureReason: nil,
                textSource: "electron-cdp:\(payload.source ?? "unknown")"
            )
        } catch {
            VoxtLog.info(
                "Focused input CDP fallback failed. bundleID=\(bundleIdentifier ?? "unknown"), pid=\(processIdentifier), error=\(error.localizedDescription)"
            )
            return nil
        }
    }

    private func systemFocusedAXElement() -> AXUIElement? {
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
            VoxtLog.info(
                "Focused input check: system-wide focused element unavailable. status=\(focusedStatus.rawValue), bundleID=\(bundleID)"
            )
            return nil
        }
        let focusedElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        return resolveFocusedElement(focusedElement)
    }

    private func focusedAXElement(for processID: pid_t) -> AXUIElement? {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let appElement = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(appElement, Self.axMessagingTimeout)
        if let focusedAppElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: appElement),
           let resolved = resolveFocusedElement(focusedAppElement) {
            VoxtLog.info(
                "Focused input check: using frontmost app focused element. bundleID=\(bundleID), role=\(axStringAttribute(kAXRoleAttribute as CFString, for: resolved) ?? "unknown")"
            )
            return resolved
        }

        guard let focusedWindow = axElementAttribute(kAXFocusedWindowAttribute as CFString, for: appElement) else {
            VoxtLog.info("Focused input check: no focused window on frontmost app. bundleID=\(bundleID)")
            return nil
        }

        if let focusedWindowElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: focusedWindow),
           let resolved = resolveFocusedElement(focusedWindowElement) {
            VoxtLog.info(
                "Focused input check: using focused window focused element. bundleID=\(bundleID), role=\(axStringAttribute(kAXRoleAttribute as CFString, for: resolved) ?? "unknown")"
            )
            return resolved
        }

        if let focusedDescendant = findFocusedDescendant(in: focusedWindow, depthRemaining: 8),
           let resolved = resolveFocusedElement(focusedDescendant) {
            VoxtLog.info(
                "Focused input check: resolved focused descendant from window subtree. bundleID=\(bundleID), role=\(axStringAttribute(kAXRoleAttribute as CFString, for: resolved) ?? "unknown")"
            )
            return resolved
        }

        if let bestEditableDescendant = findBestWritableTextDescendant(in: focusedWindow, depthRemaining: 8) {
            VoxtLog.info(
                "Focused input check: using best editable descendant from focused window. bundleID=\(bundleID), role=\(axStringAttribute(kAXRoleAttribute as CFString, for: bestEditableDescendant) ?? "unknown")"
            )
            return bestEditableDescendant
        }

        VoxtLog.info("Focused input check: falling back to focused window element. bundleID=\(bundleID)")
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
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
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
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
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

    private func hasSelectedTextRange(_ element: AXUIElement) -> Bool {
        axRangeAttribute(kAXSelectedTextRangeAttribute as CFString, for: element) != nil
    }

    private func axParameterizedString(
        _ attribute: CFString,
        range: CFRange,
        for element: AXUIElement
    ) -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
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
            VoxtLog.info(
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
            VoxtLog.info(
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
                VoxtLog.info(
                    "Focused input snapshot: resolved text via full character range. role=\(axStringAttribute(kAXRoleAttribute as CFString, for: element) ?? "unknown"), length=\(fullText.count)"
                )
                return fullText
            }
        }
        return nil
    }

    private func axElementAttribute(_ attribute: CFString, for element: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
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

    private func commandLineRemoteDebuggingPort(for processIdentifier: pid_t) -> Int? {
        guard let commandLine = processCommandLine(for: processIdentifier) else { return nil }
        let patterns = [
            #"--remote-debugging-port=(\d+)"#,
            #"--remote-debugging-port\s+(\d+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: commandLine.utf16.count)
            guard let match = regex.firstMatch(in: commandLine, range: range),
                  match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: commandLine) else {
                continue
            }
            return Int(commandLine[captureRange])
        }
        return nil
    }

    private func processCommandLine(for processIdentifier: pid_t) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-o", "command=", "-p", String(processIdentifier)]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }

    private func electronCDPPageTarget(port: Int) async throws -> ElectronCDPTarget? {
        let data = try electronCDPHTTPGet(path: "/json/list", port: port)
        let targets = try JSONDecoder().decode([ElectronCDPTarget].self, from: data)
        return targets.first {
            $0.type == "page"
                && ($0.webSocketDebuggerUrl?.isEmpty == false)
        }
    }

    private func electronCDPInputPayload(
        webSocketDebuggerURL: String?,
        port: Int
    ) async throws -> ElectronCDPInputSnapshotPayload? {
        guard let webSocketDebuggerURL,
              let components = URLComponents(string: webSocketDebuggerURL),
              let host = components.host else {
            return nil
        }

        let requestID = 1
        let requestPayload = """
        {"id":\(requestID),"method":"Runtime.evaluate","params":{"expression":"\(Self.electronCDPInputSnapshotJavaScriptEscaped)","returnByValue":true,"awaitPromise":true}}
        """

        let socket = try electronCDPOpenSocket(host: host, port: components.port ?? port)
        defer { close(socket) }

        let path = (components.path.isEmpty ? "/" : components.path)
            + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        try electronCDPPerformWebSocketHandshake(
            socket: socket,
            host: host,
            port: components.port ?? port,
            path: path
        )
        try electronCDPSendWebSocketTextFrame(socket: socket, text: requestPayload)

        while true {
            let text = try electronCDPReceiveWebSocketTextFrame(socket: socket)
            guard let responseData = text.data(using: .utf8),
                  let response = try? JSONDecoder().decode(ElectronCDPEvaluationResponse.self, from: responseData),
                  response.id == requestID else {
                continue
            }

            if let error = response.error {
                throw NSError(
                    domain: "Voxt.ElectronCDP",
                    code: port,
                    userInfo: [NSLocalizedDescriptionKey: error.message]
                )
            }

            guard let value = response.result?.result?.value,
                  let payloadData = value.data(using: .utf8) else {
                return nil
            }
            return try JSONDecoder().decode(ElectronCDPInputSnapshotPayload.self, from: payloadData)
        }
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

    private func electronCDPOpenSocket(host: String, port: Int) throws -> Int32 {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw ElectronCDPClientError.socketCreateFailed
        }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(socketDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socketDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        let conversion = host.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard conversion == 1 else {
            close(socketDescriptor)
            throw ElectronCDPClientError.socketConnectFailed
        }

        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                connect(socketDescriptor, pointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            close(socketDescriptor)
            throw ElectronCDPClientError.socketConnectFailed
        }

        return socketDescriptor
    }

    private func electronCDPHTTPGet(path: String, port: Int) throws -> Data {
        let socket = try electronCDPOpenSocket(host: "127.0.0.1", port: port)
        defer { close(socket) }

        let request = """
        GET \(path) HTTP/1.1\r
        Host: 127.0.0.1:\(port)\r
        Connection: close\r
        \r
        """
        try electronCDPWriteAll(socket: socket, data: Data(request.utf8))
        let responseData = try electronCDPReadUntilClose(socket: socket)

        guard let separatorRange = responseData.range(of: Data("\r\n\r\n".utf8)) else {
            throw ElectronCDPClientError.invalidHTTPResponse
        }
        let headerData = responseData.subdata(in: 0..<separatorRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8),
              headerText.hasPrefix("HTTP/1.1 200") || headerText.hasPrefix("HTTP/1.0 200") else {
            throw ElectronCDPClientError.invalidHTTPResponse
        }
        return responseData.subdata(in: separatorRange.upperBound..<responseData.count)
    }

    private func electronCDPPerformWebSocketHandshake(
        socket: Int32,
        host: String,
        port: Int,
        path: String
    ) throws {
        let websocketKey = Data(UUID().uuidString.utf8).base64EncodedString()
        let request = """
        GET \(path) HTTP/1.1\r
        Host: \(host):\(port)\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Key: \(websocketKey)\r
        Sec-WebSocket-Version: 13\r
        \r
        """
        try electronCDPWriteAll(socket: socket, data: Data(request.utf8))
        let handshake = try electronCDPReadUntilHeaderTerminator(socket: socket)
        guard let handshakeText = String(data: handshake, encoding: .utf8),
              handshakeText.hasPrefix("HTTP/1.1 101") || handshakeText.hasPrefix("HTTP/1.0 101") else {
            throw ElectronCDPClientError.invalidWebSocketHandshake
        }
    }

    private func electronCDPSendWebSocketTextFrame(socket: Int32, text: String) throws {
        let payload = Data(text.utf8)
        var frame = Data()
        frame.append(0x81)

        let maskKey = UInt32.random(in: UInt32.min...UInt32.max)
        let maskBytes: [UInt8] = [
            UInt8((maskKey >> 24) & 0xff),
            UInt8((maskKey >> 16) & 0xff),
            UInt8((maskKey >> 8) & 0xff),
            UInt8(maskKey & 0xff)
        ]

        if payload.count < 126 {
            frame.append(UInt8(payload.count) | 0x80)
        } else if payload.count <= UInt16.max {
            frame.append(126 | 0x80)
            var length = UInt16(payload.count).bigEndian
            withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        } else {
            frame.append(127 | 0x80)
            var length = UInt64(payload.count).bigEndian
            withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        }

        frame.append(contentsOf: maskBytes)
        for (index, byte) in payload.enumerated() {
            frame.append(byte ^ maskBytes[index % maskBytes.count])
        }

        try electronCDPWriteAll(socket: socket, data: frame)
    }

    private func electronCDPReceiveWebSocketTextFrame(socket: Int32) throws -> String {
        while true {
            let header = try electronCDPReadExactly(socket: socket, count: 2)
            guard header.count == 2 else { throw ElectronCDPClientError.invalidWebSocketFrame }

            let first = header[header.startIndex]
            let second = header[header.startIndex + 1]
            let opcode = first & 0x0f
            let masked = (second & 0x80) != 0

            var payloadLength = Int(second & 0x7f)
            if payloadLength == 126 {
                let extended = try electronCDPReadExactly(socket: socket, count: 2)
                payloadLength = Int(extended.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
            } else if payloadLength == 127 {
                let extended = try electronCDPReadExactly(socket: socket, count: 8)
                payloadLength = Int(extended.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            }

            let maskData = masked ? try electronCDPReadExactly(socket: socket, count: 4) : Data()
            var payload = try electronCDPReadExactly(socket: socket, count: payloadLength)
            if masked {
                for index in payload.indices {
                    payload[index] ^= maskData[maskData.startIndex + (payload.distance(from: payload.startIndex, to: index) % 4)]
                }
            }

            switch opcode {
            case 0x1:
                guard let text = String(data: payload, encoding: .utf8) else {
                    throw ElectronCDPClientError.invalidWebSocketFrame
                }
                return text
            case 0x8:
                throw ElectronCDPClientError.invalidWebSocketFrame
            case 0x9:
                try electronCDPSendWebSocketControlFrame(socket: socket, opcode: 0xA, payload: payload)
            default:
                continue
            }
        }
    }

    private func electronCDPSendWebSocketControlFrame(
        socket: Int32,
        opcode: UInt8,
        payload: Data
    ) throws {
        guard payload.count < 126 else {
            throw ElectronCDPClientError.invalidWebSocketFrame
        }
        var frame = Data()
        frame.append(0x80 | opcode)
        frame.append(UInt8(payload.count))
        frame.append(payload)
        try electronCDPWriteAll(socket: socket, data: frame)
    }

    private func electronCDPWriteAll(socket: Int32, data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw ElectronCDPClientError.socketWriteFailed
            }
            var totalSent = 0
            while totalSent < data.count {
                let sent = send(socket, baseAddress.advanced(by: totalSent), data.count - totalSent, 0)
                guard sent > 0 else {
                    throw ElectronCDPClientError.socketWriteFailed
                }
                totalSent += sent
            }
        }
    }

    private func electronCDPReadUntilClose(socket: Int32) throws -> Data {
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let received = recv(socket, &buffer, buffer.count, 0)
            if received == 0 {
                return collected
            }
            guard received > 0 else {
                throw ElectronCDPClientError.socketReadFailed
            }
            collected.append(buffer, count: received)
        }
    }

    private func electronCDPReadUntilHeaderTerminator(socket: Int32) throws -> Data {
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 512)
        while collected.range(of: Data("\r\n\r\n".utf8)) == nil {
            let received = recv(socket, &buffer, buffer.count, 0)
            guard received > 0 else {
                throw ElectronCDPClientError.socketReadFailed
            }
            collected.append(buffer, count: received)
            guard collected.count < 16_384 else {
                throw ElectronCDPClientError.invalidWebSocketHandshake
            }
        }
        return collected
    }

    private func electronCDPReadExactly(socket: Int32, count: Int) throws -> Data {
        var collected = Data(count: count)
        try collected.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw ElectronCDPClientError.socketReadFailed
            }
            var totalRead = 0
            while totalRead < count {
                let received = recv(socket, baseAddress.advanced(by: totalRead), count - totalRead, 0)
                guard received > 0 else {
                    throw ElectronCDPClientError.socketReadFailed
                }
                totalRead += received
            }
        }
        return collected
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

    private func focusedInputSnapshotSummary(_ snapshot: FocusedInputTextSnapshot) -> String {
        let preview = String(snapshot.text.prefix(80))
        return
            "bundleID=\(snapshot.bundleIdentifier ?? "nil") pid=\(snapshot.processIdentifier.map(String.init) ?? "nil") "
                + "role=\(snapshot.role ?? "nil") editable=\(snapshot.isEditable) "
                + "focused=\(snapshot.isFocusedTarget) textLength=\(snapshot.text.count) "
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
            VoxtLog.info(
                "Restoring focus to session target app before text injection. bundleID=\(targetApplication.bundleIdentifier ?? "unknown"), pid=\(targetPID)"
            )
            return targetApplication.activate(options: [])
        }

        if let targetBundleID = sessionTargetApplicationBundleID,
           let targetApplication = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID)
            .first(where: { !$0.isTerminated }) {
            VoxtLog.info(
                "Restoring focus to session target app by bundle ID before text injection. bundleID=\(targetBundleID), pid=\(targetApplication.processIdentifier)"
            )
            return targetApplication.activate(options: [])
        }

        VoxtLog.info(
            "Session target app restoration skipped: target app unavailable. targetBundleID=\(sessionTargetApplicationBundleID ?? "nil"), targetPID=\(sessionTargetApplicationPID.map(String.init) ?? "nil")"
        )
        return false
    }

    func typeText(_ text: String, completion: ((Bool) -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }

        let injectionStartedAt = Date()
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string) ?? ""
        let accessibilityTrusted = AccessibilityPermissionManager.isTrusted()
        let keepResultInClipboard = autoCopyWhenNoFocusedInput

        guard accessibilityTrusted else {
            writeTextToPasteboard(text)
            promptForAccessibilityPermission()
            VoxtLog.warning("Accessibility permission missing. Transcription copied; paste manually after granting permission.")
            completion?(false)
            return
        }

        let activationRestored = restoreSessionTargetApplicationIfNeeded()
        let activationDelay: TimeInterval = activationRestored ? 0.04 : 0
        VoxtLog.info(
            "Text injection prepared. characters=\(text.count), activationRestored=\(activationRestored), activationDelayMs=\(Int(activationDelay * 1000))"
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
                    VoxtLog.info(
                        "Text injection completed via paste fallback. characters=\(text.count), elapsedMs=\(elapsedMs), didInject=\(didInject)"
                    )
                    completion?(didInject)
                }
            )
        }
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

        let historyText = historyStore.allHistoryEntries.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return historyText.isEmpty ? nil : historyText
    }

    func injectLatestResultByCustomPasteHotkey() {
        guard let latestText = resolvedLatestInjectableOutputText() else {
            showOverlayStatus(String(localized: "No recent result available to paste yet."), clearAfter: 2.0)
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
}

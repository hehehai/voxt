import Foundation
import AppKit
import ApplicationServices

extension AppDelegate {
    private enum SessionOutputDelivery {
        case typeText
        case answerOverlay
    }

    private struct NormalizeOutputStage: SessionFinalizeStage {
        let normalize: (String) -> String

        var name: String { "normalizeOutput" }

        func run(context: inout SessionFinalizeContext) {
            context.outputText = normalize(context.outputText)
        }
    }

    private struct DictionaryCorrectionStage: SessionFinalizeStage {
        let correct: (String) -> DictionaryCorrectionResult

        var name: String { "dictionaryCorrection" }

        func run(context: inout SessionFinalizeContext) {
            let result = correct(context.outputText)
            context.outputText = result.text
            context.dictionaryMatches = result.candidates
            context.dictionaryCorrectedTerms = result.correctedTerms
        }
    }

    private struct DictionarySuggestionStage: SessionFinalizeStage {
        let suggest: (String, [DictionaryMatchCandidate], [String]) -> [DictionarySuggestionDraft]

        var name: String { "dictionarySuggestions" }

        func run(context: inout SessionFinalizeContext) {
            context.dictionarySuggestions = suggest(
                context.outputText,
                context.dictionaryMatches,
                context.dictionaryCorrectedTerms
            )
        }
    }

    private struct RewriteAnswerExtractionStage: SessionFinalizeStage {
        let extract: (String) -> RewriteAnswerPayload?

        var name: String { "rewriteAnswerExtraction" }

        func run(context: inout SessionFinalizeContext) {
            guard let payload = extract(context.outputText) else { return }
            context.rewriteAnswerPayload = payload
            context.outputText = payload.content
        }
    }

    private struct DeliverOutputStage: SessionFinalizeStage {
        let deliver: (SessionFinalizeContext) -> Void

        var name: String { "deliverOutput" }

        func run(context: inout SessionFinalizeContext) {
            deliver(context)
        }
    }

    private struct PersistDictionaryEvidenceStage: SessionFinalizeStage {
        let persist: ([DictionaryMatchCandidate], [DictionarySuggestionDraft], UUID?) -> Void

        var name: String { "persistDictionaryEvidence" }

        func run(context: inout SessionFinalizeContext) {
            persist(context.dictionaryMatches, context.dictionarySuggestions, context.historyEntryID)
        }
    }

    private struct AppendHistoryStage: SessionFinalizeStage {
        let append: (String, TimeInterval?, [String], [String], [DictionarySuggestionSnapshot]) -> UUID?

        var name: String { "appendHistory" }

        func run(context: inout SessionFinalizeContext) {
            context.historyEntryID = append(
                context.outputText,
                context.llmDurationSeconds,
                Self.uniqueTerms(from: context.dictionaryMatches),
                Self.deduplicatedTerms(context.dictionaryCorrectedTerms),
                context.dictionarySuggestions.map(\.snapshot)
            )
        }

        private static func uniqueTerms(from candidates: [DictionaryMatchCandidate]) -> [String] {
            var seen = Set<String>()
            var ordered: [String] = []
            for candidate in candidates {
                let normalized = DictionaryStore.normalizeTerm(candidate.term)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                ordered.append(candidate.term)
            }
            return ordered
        }

        private static func deduplicatedTerms(_ values: [String]) -> [String] {
            var seen = Set<String>()
            var ordered: [String] = []
            for value in values {
                let normalized = DictionaryStore.normalizeTerm(value)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                ordered.append(value)
            }
            return ordered
        }
    }

    // MARK: - Session Text I/O
    // Keeps clipboard/AX/paste simulation logic isolated from recording orchestration.

    func commitTranscription(_ text: String, llmDurationSeconds: TimeInterval?) {
        if didCommitSessionOutput {
            VoxtLog.info("Skipping duplicate commit for current session output.")
            return
        }
        didCommitSessionOutput = true

        let pipeline = SessionFinalizePipelineRunner(
            stages: [
                NormalizeOutputStage(normalize: { [weak self] value in
                    self?.normalizedOutputText(value) ?? value
                }),
                RewriteAnswerExtractionStage(extract: { [weak self] value in
                    self?.extractRewriteAnswerPayload(from: value)
                }),
                DictionaryCorrectionStage(correct: { [weak self] value in
                    self?.resolveDictionaryCorrection(for: value)
                        ?? DictionaryCorrectionResult(text: value, candidates: [], correctedTerms: [])
                }),
                DictionarySuggestionStage(suggest: { [weak self] value, candidates, correctedTerms in
                    self?.previewDictionarySuggestions(
                        for: value,
                        candidates: candidates,
                        correctedTerms: correctedTerms
                    ) ?? []
                }),
                DeliverOutputStage(deliver: { [weak self] context in
                    self?.deliverCommittedOutput(context)
                }),
                AppendHistoryStage(append: { [weak self] value, duration, hitTerms, correctedTerms, suggestions in
                    self?.appendHistoryIfNeeded(
                        text: value,
                        llmDurationSeconds: duration,
                        dictionaryHitTerms: hitTerms,
                        dictionaryCorrectedTerms: correctedTerms,
                        dictionarySuggestedTerms: suggestions
                    )
                }),
                PersistDictionaryEvidenceStage(persist: { [weak self] candidates, suggestions, historyEntryID in
                    self?.persistDictionaryEvidence(
                        candidates: candidates,
                        suggestions: suggestions,
                        historyEntryID: historyEntryID
                    )
                })
            ]
        )
        _ = pipeline.run(
            initial: SessionFinalizeContext(
                outputText: text,
                llmDurationSeconds: llmDurationSeconds,
                dictionaryMatches: [],
                dictionaryCorrectedTerms: [],
                dictionarySuggestions: [],
                historyEntryID: nil,
                rewriteAnswerPayload: nil
            )
        )
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
        Thread.sleep(forTimeInterval: 0.06)

        let copiedChangeCount = pasteboard.changeCount
        guard copiedChangeCount != originalChangeCount else {
            // No clipboard update means no effective selection copy.
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

    private func normalizedOutputText(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return value }

        // Remove paired wrapping quotes from some model outputs.
        let left = value.first
        let right = value.last
        let isWrappedByDoubleQuotes =
            (left == "\"" && right == "\"") ||
            (left == "“" && right == "”")

        if isWrappedByDoubleQuotes {
            value.removeFirst()
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if sessionOutputMode != .translation {
            let normalizedChineseScript = ChineseScriptNormalizer.normalize(
                value,
                preferredMainLanguage: userMainLanguage
            )
            if normalizedChineseScript != value {
                VoxtLog.info(
                    "Normalized Chinese script variant for final output. preferred=\(userMainLanguage.code), chars=\(normalizedChineseScript.count)",
                    verbose: true
                )
            }
            value = normalizedChineseScript
        }

        return value
    }

    private func deliverCommittedOutput(_ context: SessionFinalizeContext) {
        switch resolvedOutputDelivery(for: context) {
        case .typeText:
            typeText(context.outputText)
        case .answerOverlay:
            let payload = resolvedAnswerPayload(for: context)
            presentRewriteAnswerOverlay(title: payload.title, content: payload.content)
        }
    }

    private func resolvedOutputDelivery(for context: SessionFinalizeContext) -> SessionOutputDelivery {
        shouldPresentRewriteAnswerOverlay(hasSelectedSourceText: rewriteSessionHasSelectedSourceText)
            ? .answerOverlay
            : .typeText
    }

    func shouldPresentRewriteAnswerOverlay(hasSelectedSourceText: Bool) -> Bool {
        sessionOutputMode == .rewrite && !hasSelectedSourceText
    }

    private func resolvedAnswerPayload(for context: SessionFinalizeContext) -> RewriteAnswerPayload {
        if let payload = context.rewriteAnswerPayload,
           !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !payload.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return payload
        }

        if let placeholderTitle = emptyRewriteAnswerPlaceholderTitle(from: context.outputText) {
            return RewriteAnswerPayload(
                title: placeholderTitle,
                content: "Unable to generate answer."
            )
        }

        return RewriteAnswerPayload(
            title: String(localized: "AI Answer"),
            content: context.outputText
        )
    }

    private func presentRewriteAnswerOverlay(title: String, content: String) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        if autoCopyWhenNoFocusedInput {
            writeTextToPasteboard(trimmedContent)
        }

        overlayWindow.onRequestInject = { [weak self] in
            Task { @MainActor [weak self] in
                self?.injectAnswerOverlayContent()
            }
        }
        let liveHasWritableFocusedInput = hasWritableFocusedTextInput()
        let hasFallbackInjectTarget = rewriteSessionFallbackInjectBundleID != nil
        let canInjectIntoFocusedInput =
            rewriteSessionHadWritableFocusedInput ||
            liveHasWritableFocusedInput ||
            hasFallbackInjectTarget
        VoxtLog.info(
            "Rewrite answer overlay inject check. sessionHadWritableFocusedInput=\(rewriteSessionHadWritableFocusedInput), liveHasWritableFocusedInput=\(liveHasWritableFocusedInput), fallbackBundleID=\(rewriteSessionFallbackInjectBundleID ?? "nil"), canInject=\(canInjectIntoFocusedInput)"
        )
        overlayState.presentAnswer(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "AI Answer")
                : title,
            content: trimmedContent,
            canInject: canInjectIntoFocusedInput
        )
        overlayWindow.show(state: overlayState, position: overlayPosition)
    }

    func dismissAnswerOverlay() {
        guard overlayState.displayMode == .answer else { return }
        overlayWindow.hide { [weak self] in
            guard let self else { return }
            self.overlayWindow.onRequestInject = nil
            self.overlayState.reset()
        }
    }

    func injectAnswerOverlayContent() {
        let trimmed = overlayState.answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard overlayState.canInjectAnswer else { return }
        VoxtLog.info("Rewrite answer inject requested. chars=\(trimmed.count), canInject=\(overlayState.canInjectAnswer)")
        typeText(trimmed)
    }

    func extractRewriteAnswerPayload(from text: String) -> RewriteAnswerPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidateStrings = [trimmed, strippedCodeFencePayload(from: trimmed)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidateStrings {
            if let payload = decodeRewriteAnswerPayload(from: candidate) {
                return payload
            }

            if let objectRange = candidate.firstIndex(of: "{").flatMap({ start in
                candidate.lastIndex(of: "}").map { start...$0 }
            }) {
                let objectString = String(candidate[objectRange])
                if let payload = decodeRewriteAnswerPayload(from: objectString) {
                    return payload
                }
            }
        }

        return nil
    }

    private func decodeRewriteAnswerPayload(from text: String) -> RewriteAnswerPayload? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return decodeLooseRewriteAnswerPayload(from: text)
        }

        if let dict = object as? [String: Any] {
            return rewriteAnswerPayload(from: dict)
        }

        if let string = object as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != text else {
                return decodeLooseRewriteAnswerPayload(from: text)
            }
            return decodeRewriteAnswerPayload(from: trimmed) ?? decodeLooseRewriteAnswerPayload(from: trimmed)
        }

        return decodeLooseRewriteAnswerPayload(from: text)
    }

    private func rewriteAnswerPayload(from object: [String: Any]) -> RewriteAnswerPayload? {
        let titleKeys = ["title", "heading", "summary"]
        let contentKeys = ["content", "answer", "body", "text"]

        let title = titleKeys
            .compactMap { object[$0] }
            .map { String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        let content = contentKeys
            .compactMap { object[$0] }
            .map { String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        guard !content.isEmpty else {
            return decodeLooseRewriteAnswerPayload(
                from: object
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "\n")
            )
        }
        return RewriteAnswerPayload(
            title: title.isEmpty ? String(localized: "AI Answer") : title,
            content: content
        )
    }

    private func decodeLooseRewriteAnswerPayload(from text: String) -> RewriteAnswerPayload? {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let title = firstMatch(
            in: normalized,
            patterns: [
                #"(?is)(?:^|\n)\s*["']?title["']?\s*[:：]\s*["']?(.+?)["']?(?=\n\s*["']?(?:content|answer|body|text)["']?\s*[:：]|\n{2,}|$)"#,
                #"(?is)(?:^|\n)\s*["']?(?:heading|summary)["']?\s*[:：]\s*["']?(.+?)["']?(?=\n\s*["']?(?:content|answer|body|text)["']?\s*[:：]|\n{2,}|$)"#
            ]
        )

        let content = firstMatch(
            in: normalized,
            patterns: [
                #"(?is)(?:^|\n)\s*["']?(?:content|answer|body|text)["']?\s*[:：]\s*["']?([\s\S]+?)["']?\s*$"#
            ]
        )

        guard let content, !content.isEmpty else { return nil }
        return RewriteAnswerPayload(
            title: (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? title!.trimmingCharacters(in: .whitespacesAndNewlines)
                : String(localized: "AI Answer")),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func firstMatch(in text: String, patterns: [String]) -> String? {
        let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(in: text, options: [], range: searchRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text)
            else {
                continue
            }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func strippedCodeFencePayload(from text: String) -> String? {
        guard text.hasPrefix("```"), text.hasSuffix("```") else { return nil }
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return nil }
        lines.removeFirst()
        if !lines.isEmpty, lines.last == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private func emptyRewriteAnswerPlaceholderTitle(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = (object["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, content.isEmpty else { return nil }
        return title
    }

    func hasWritableFocusedTextInput() -> Bool {
        guard let focusedElement = focusedAXElement() else {
            VoxtLog.info("Focused input check: no focused AX element.")
            return false
        }

        if let writableElement = writableTextInputElement(from: focusedElement) {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: writableElement) ?? "unknown"
            let editable = axBoolAttribute("AXEditable" as CFString, for: writableElement) == true
            var isSettable = DarwinBoolean(false)
            let settableStatus = AXUIElementIsAttributeSettable(
                writableElement,
                kAXValueAttribute as CFString,
                &isSettable
            )
            let valueSettable = settableStatus == .success && isSettable.boolValue
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

        var isSettable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &isSettable
        )
        if settableStatus == .success, isSettable.boolValue {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) ?? "unknown"
            VoxtLog.info("Focused input check: settable AX value detected. role=\(role)")
            return true
        }

        guard let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) else {
            VoxtLog.info(
                "Focused input check: role unavailable. editable=\(editable == true), valueSettable=\(isSettable.boolValue)"
            )
            return false
        }

        let writableRoles: Set<String> = [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            "AXSearchField",
            kAXComboBoxRole as String
        ]
        let isWritable = writableRoles.contains(role)
        VoxtLog.info(
            "Focused input check: role=\(role), editable=\(editable == true), valueSettable=\(isSettable.boolValue), result=\(isWritable)"
        )
        return isWritable
    }

    private func focusedAXElement() -> AXUIElement? {
        guard AccessibilityPermissionManager.isTrusted() else {
            VoxtLog.info("Focused input check: accessibility not trusted.")
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        if focusedStatus == .success,
           let focusedElementRef,
           CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() {
            return unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        VoxtLog.info(
            "Focused input check: system-wide focused element unavailable. status=\(focusedStatus.rawValue), bundleID=\(bundleID)"
        )

        guard let appPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            VoxtLog.info("Focused input check: no frontmost application PID.")
            return nil
        }

        let appElement = AXUIElementCreateApplication(appPID)
        if let focusedAppElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: appElement) {
            VoxtLog.info("Focused input check: using frontmost app focused element. bundleID=\(bundleID)")
            return focusedAppElement
        }

        guard let focusedWindow = axElementAttribute(kAXFocusedWindowAttribute as CFString, for: appElement) else {
            VoxtLog.info("Focused input check: no focused window on frontmost app. bundleID=\(bundleID)")
            return nil
        }

        if let focusedWindowElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: focusedWindow) {
            VoxtLog.info("Focused input check: using focused window focused element. bundleID=\(bundleID)")
            return focusedWindowElement
        }

        VoxtLog.info("Focused input check: falling back to focused window element. bundleID=\(bundleID)")
        return focusedWindow
    }

    private func axBoolAttribute(_ attribute: CFString, for element: AXUIElement) -> Bool? {
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
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success else { return nil }
        return valueRef as? String
    }

    private func axElementAttribute(_ attribute: CFString, for element: AXUIElement) -> AXUIElement? {
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
        guard depth <= 5 else { return nil }

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
        if axBoolAttribute("AXEditable" as CFString, for: element) == true {
            return true
        }

        var isSettable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        )
        if settableStatus == .success, isSettable.boolValue {
            return true
        }

        guard let role = axStringAttribute(kAXRoleAttribute as CFString, for: element) else {
            return false
        }

        let writableRoles: Set<String> = [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            "AXSearchField",
            kAXComboBoxRole as String
        ]
        return writableRoles.contains(role)
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

    private func typeText(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string) ?? ""
        let accessibilityTrusted = AccessibilityPermissionManager.isTrusted()
        let keepResultInClipboard = autoCopyWhenNoFocusedInput

        writeTextToPasteboard(text)

        if restoreSessionTargetApplicationIfNeeded() {
            Thread.sleep(forTimeInterval: 0.06)
        }

        guard accessibilityTrusted else {
            promptForAccessibilityPermission()
            VoxtLog.warning("Accessibility permission missing. Transcription copied; paste manually after granting permission.")
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            VoxtLog.error("typeText failed: unable to create CGEventSource")
            return
        }

        let vKeyCode: CGKeyCode = 0x09
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand

        guard cmdDown != nil, cmdUp != nil else {
            VoxtLog.error("typeText failed: unable to create key events")
            return
        }

        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)

        if !keepResultInClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                pasteboard.clearContents()
                if !previous.isEmpty {
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    private func writeTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func promptForAccessibilityPermission() {
        _ = AccessibilityPermissionManager.request(prompt: true)
    }
}

import Foundation
import AppKit
import ApplicationServices

extension AppDelegate {
    private static let axMessagingTimeout: Float = 0.05

    private enum SessionOutputDelivery {
        case typeText
        case answerOverlay
        case selectedTextTranslationResultWindow
    }

    private struct DictionaryResolutionPlan {
        let matcher: DictionaryMatcher?
        let usesConservativeEvidence: Bool
        let automaticReplacementEnabled: Bool

        func resolve(text: String) -> DictionaryCorrectionResult {
            guard let matcher else {
                return DictionaryCorrectionResult(text: text, candidates: [], correctedTerms: [])
            }

            if usesConservativeEvidence {
                let candidates = matcher.recallCandidates(in: text)
                return DictionaryCorrectionResult(text: text, candidates: candidates, correctedTerms: [])
            }

            return matcher.applyCorrections(
                to: text,
                automaticReplacementEnabled: automaticReplacementEnabled
            )
        }
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
        let append: (String, String?, TimeInterval?, [String], [String], [DictionarySuggestionSnapshot]) -> UUID?

        var name: String { "appendHistory" }

        func run(context: inout SessionFinalizeContext) {
            context.historyEntryID = append(
                context.outputText,
                context.rewriteAnswerPayload?.trimmedTitle,
                context.llmDurationSeconds,
                Self.uniqueTerms(from: context.dictionaryMatches),
                Self.deduplicatedTerms(context.dictionaryCorrectedTerms),
                context.dictionarySuggestions.map(\.snapshot)
            )
        }

        private static func uniqueTerms(from candidates: [DictionaryMatchCandidate]) -> [String] {
            AppDelegate.orderedUniqueDictionaryTerms(from: candidates.map(\.term))
        }

        private static func deduplicatedTerms(_ values: [String]) -> [String] {
            AppDelegate.orderedUniqueDictionaryTerms(from: values)
        }
    }

    // MARK: - Session Text I/O
    // Keeps clipboard/AX/paste simulation logic isolated from recording orchestration.

    func commitTranscription(
        _ text: String,
        llmDurationSeconds: TimeInterval?,
        onDeliveryCompleted: (() -> Void)? = nil
    ) {
        if didCommitSessionOutput {
            VoxtLog.info("Skipping duplicate commit for current session output.")
            return
        }
        didCommitSessionOutput = true
        let sessionID = activeRecordingSessionID
        let sessionOutputMode = sessionOutputMode
        let userMainLanguage = userMainLanguage
        guard shouldHandleCallbacks(for: sessionID) else { return }

        VoxtLog.info("Commit transcription entered. characters=\(text.count)")

        let normalized = Self.normalizedOutputText(
            text,
            sessionOutputMode: sessionOutputMode,
            userMainLanguage: userMainLanguage
        )

        var outputText = normalized
        let rewriteAnswerPayload = extractRewriteAnswerPayload(from: outputText)
        if let rewriteAnswerPayload {
            outputText = rewriteAnswerPayload.content
        }

        VoxtLog.info(
            "Commit transcription prepared payload. inputChars=\(text.count), outputChars=\(outputText.count), hasRewritePayload=\(rewriteAnswerPayload != nil)"
        )

        let context = SessionFinalizeContext(
            outputText: outputText,
            llmDurationSeconds: llmDurationSeconds,
            dictionaryMatches: [],
            dictionaryCorrectedTerms: [],
            dictionarySuggestions: [],
            historyEntryID: nil,
            rewriteAnswerPayload: rewriteAnswerPayload
        )

        deliverCommittedOutput(context) { [weak self] in
            guard let self else { return }
            self.finalizeCommittedOutputPostDeliveryAsync(
                originalText: text,
                deliveredContext: context,
                llmDurationSeconds: llmDurationSeconds,
                sessionOutputMode: sessionOutputMode,
                userMainLanguage: userMainLanguage
            )
            onDeliveryCompleted?()
        }
    }

    nonisolated private static func orderedUniqueDictionaryTerms(from values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let normalized = DictionaryStore.normalizeTerm(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(value)
        }
        return ordered
    }

    private func shouldUseConservativeDictionaryEvidenceForCurrentSession() -> Bool {
        let featureSettings = FeatureSettingsStore.load(defaults: .standard)
        let selectionID: FeatureModelSelectionID
        switch sessionOutputMode {
        case .translation:
            selectionID = featureSettings.translation.asrSelectionID
        case .rewrite:
            selectionID = featureSettings.rewrite.asrSelectionID
        case .transcription:
            selectionID = featureSettings.transcription.asrSelectionID
        }

        guard case .remote(let provider)? = selectionID.asrSelection,
              provider == .doubaoASR
        else {
            return false
        }

        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        let stored = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: stored)

        switch configuration.doubaoDictionaryModeValue {
        case .off:
            return false
        case .requestScoped:
            return configuration.doubaoEnableRequestCorrections
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
        Self.normalizedOutputText(
            text,
            sessionOutputMode: sessionOutputMode,
            userMainLanguage: userMainLanguage
        )
    }

    nonisolated private static func normalizedOutputText(
        _ text: String,
        sessionOutputMode: SessionOutputMode,
        userMainLanguage: UserMainLanguageOption
    ) -> String {
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

        switch sessionOutputMode {
        case .translation:
            break
        case .transcription, .rewrite:
            let normalizedChineseScript = ChineseScriptNormalizer.normalize(
                value,
                preferredMainLanguage: userMainLanguage
            )
            value = normalizedChineseScript
        }

        return value
    }

    private func deliverCommittedOutput(
        _ context: SessionFinalizeContext,
        completion: (() -> Void)? = nil
    ) {
        let delivery = resolvedOutputDelivery(for: context)
        let deliveryLabel: String
        switch delivery {
        case .typeText:
            deliveryLabel = "typeText"
        case .answerOverlay:
            deliveryLabel = "answerOverlay"
        case .selectedTextTranslationResultWindow:
            deliveryLabel = "selectedTextTranslationResultWindow"
        }
        VoxtLog.info(
            "Deliver committed output started. delivery=\(deliveryLabel), characters=\(context.outputText.count)"
        )

        switch delivery {
        case .typeText:
            beginOverlayOutputDelivery()
            typeText(context.outputText) { [weak self] _ in
                self?.endOverlayOutputDelivery()
                completion?()
            }
        case .answerOverlay:
            if overlayState.isRewriteConversationActive, context.rewriteAnswerPayload == nil {
                presentRewriteConversationAnswerOverlay(content: context.outputText)
            } else {
                let payload = resolvedAnswerPayload(for: context)
                presentRewriteAnswerOverlay(title: payload.title, content: payload.content)
            }
            completion?()
        case .selectedTextTranslationResultWindow:
            presentSelectedTextTranslationAnswerOverlay(content: context.outputText)
            completion?()
        }
    }

    private func finalizeCommittedOutputPostDeliveryAsync(
        originalText: String,
        deliveredContext: SessionFinalizeContext,
        llmDurationSeconds: TimeInterval?,
        sessionOutputMode: SessionOutputMode,
        userMainLanguage: UserMainLanguageOption
    ) {
        let deliveredText = deliveredContext.outputText
        let displayTitle = deliveredContext.rewriteAnswerPayload?.trimmedTitle

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let dictionaryPlan = await MainActor.run {
                DictionaryResolutionPlan(
                    matcher: self.dictionaryStore.makeMatcherIfEnabled(activeGroupID: self.activeDictionaryGroupID()),
                    usesConservativeEvidence: self.shouldUseConservativeDictionaryEvidenceForCurrentSession(),
                    automaticReplacementEnabled: UserDefaults.standard.bool(
                        forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled
                    )
                )
            }

            let normalized = Self.normalizedOutputText(
                originalText,
                sessionOutputMode: sessionOutputMode,
                userMainLanguage: userMainLanguage
            )

            let postProcessedSource: String
            if let payload = RewriteAnswerPayloadParser.extract(from: normalized) {
                postProcessedSource = payload.content
            } else {
                postProcessedSource = deliveredText
            }

            let dictionaryCorrection = await MainActor.run {
                dictionaryPlan.resolve(text: postProcessedSource)
            }
            let dictionarySuggestions = await MainActor.run {
                self.previewDictionarySuggestions(
                    for: dictionaryCorrection.text,
                    candidates: dictionaryCorrection.candidates,
                    correctedTerms: dictionaryCorrection.correctedTerms
                )
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                let historyEntryID = self.appendHistoryIfNeeded(
                    text: deliveredText,
                    outputMode: sessionOutputMode,
                    displayTitle: displayTitle,
                    llmDurationSeconds: llmDurationSeconds,
                    dictionaryHitTerms: Self.orderedUniqueDictionaryTerms(from: dictionaryCorrection.candidates.map(\.term)),
                    dictionaryCorrectedTerms: Self.orderedUniqueDictionaryTerms(from: dictionaryCorrection.correctedTerms),
                    dictionarySuggestedTerms: dictionarySuggestions.map(\.snapshot)
                )
                self.overlayState.latestHistoryEntryID = historyEntryID
                self.persistDictionaryEvidence(
                    candidates: dictionaryCorrection.candidates,
                    suggestions: dictionarySuggestions,
                    historyEntryID: historyEntryID
                )
                VoxtLog.info(
                    "Deliver committed output finalized. historyEntryID=\(historyEntryID?.uuidString ?? "nil"), characters=\(deliveredText.count)"
                )
            }
        }
    }

    private func resolvedOutputDelivery(for context: SessionFinalizeContext) -> SessionOutputDelivery {
        if shouldPresentSelectedTextTranslationAnswerOverlay() {
            return .selectedTextTranslationResultWindow
        }

        if shouldAutoInjectSelectedTextTranslationResult() {
            return .typeText
        }

        return shouldPresentRewriteAnswerOverlay(hasSelectedSourceText: rewriteSessionHasSelectedSourceText)
            ? SessionOutputDelivery.answerOverlay
            : SessionOutputDelivery.typeText
    }

    static func shouldPresentSelectedTextTranslationAnswerOverlay(
        sessionOutputMode: SessionOutputMode,
        isSelectedTextTranslationFlow: Bool,
        showResultWindow: Bool
    ) -> Bool {
        sessionOutputMode == .translation &&
            isSelectedTextTranslationFlow &&
            showResultWindow
    }

    func shouldPresentSelectedTextTranslationAnswerOverlay() -> Bool {
        Self.shouldPresentSelectedTextTranslationAnswerOverlay(
            sessionOutputMode: sessionOutputMode,
            isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
            showResultWindow: showSelectedTextTranslationResultWindow
        )
    }

    static func shouldAutoInjectSelectedTextTranslationResult(
        sessionOutputMode: SessionOutputMode,
        isSelectedTextTranslationFlow: Bool,
        showResultWindow: Bool
    ) -> Bool {
        sessionOutputMode == .translation &&
            isSelectedTextTranslationFlow &&
            !showResultWindow
    }

    func shouldAutoInjectSelectedTextTranslationResult() -> Bool {
        Self.shouldAutoInjectSelectedTextTranslationResult(
            sessionOutputMode: sessionOutputMode,
            isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
            showResultWindow: showSelectedTextTranslationResultWindow
        )
    }

    static func shouldPresentRewriteAnswerOverlay(
        sessionOutputMode: SessionOutputMode,
        hasSelectedSourceText _: Bool
    ) -> Bool {
        sessionOutputMode == .rewrite
    }

    func shouldPresentRewriteAnswerOverlay(hasSelectedSourceText: Bool) -> Bool {
        Self.shouldPresentRewriteAnswerOverlay(
            sessionOutputMode: sessionOutputMode,
            hasSelectedSourceText: hasSelectedSourceText
        )
    }

    static func shouldUseStructuredRewriteAnswerOutput(
        sessionOutputMode: SessionOutputMode,
        hasSelectedSourceText: Bool
    ) -> Bool {
        sessionOutputMode == .rewrite && !hasSelectedSourceText
    }

    func shouldUseStructuredRewriteAnswerOutput(hasSelectedSourceText: Bool) -> Bool {
        Self.shouldUseStructuredRewriteAnswerOutput(
            sessionOutputMode: sessionOutputMode,
            hasSelectedSourceText: hasSelectedSourceText
        )
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
        let resolvedPayload = normalizedRewriteAnswerPayload(
            RewriteAnswerPayload(title: title, content: content)
        )
        let trimmedContent = resolvedPayload.trimmedContent
        guard !trimmedContent.isEmpty else { return }

        if autoCopyWhenNoFocusedInput {
            writeTextToPasteboard(trimmedContent)
        }

        configureAnswerOverlayInjectionHandler()
        let canInjectIntoFocusedInput = resolvedCanInjectIntoFocusedInputForRewriteAnswer(logResult: true)
        overlayState.presentAnswer(
            title: resolvedPayload.trimmedTitle.isEmpty
                ? String(localized: "AI Answer")
                : resolvedPayload.trimmedTitle,
            content: trimmedContent,
            canInject: canInjectIntoFocusedInput
        )
        overlayWindow.show(state: overlayState, position: overlayPosition)
    }

    private func presentSelectedTextTranslationAnswerOverlay(content: String) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        if autoCopyWhenNoFocusedInput {
            writeTextToPasteboard(trimmedContent)
        }

        configureAnswerOverlayInjectionHandler()

        overlayState.configureSessionTranslationTargetLanguage(
            translationTargetLanguage,
            allowsSwitching: true
        )
        overlayState.presentAnswer(
            title: String(localized: "Translation"),
            content: trimmedContent,
            canInject: true
        )
        overlayWindow.show(state: overlayState, position: overlayPosition)
    }

    private func presentRewriteConversationAnswerOverlay(content: String) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        if autoCopyWhenNoFocusedInput {
            writeTextToPasteboard(trimmedContent)
        }

        configureAnswerOverlayInjectionHandler()
        let canInjectIntoFocusedInput = resolvedCanInjectIntoFocusedInputForRewriteAnswer(logResult: true)
        overlayState.presentConversationAnswer(
            content: trimmedContent,
            canInject: canInjectIntoFocusedInput
        )
        overlayWindow.show(state: overlayState, position: overlayPosition)
    }

    func presentRewriteAnswerStreamingPreview(rawText: String) {
        let previewPayload = RewriteAnswerPayloadParser.preview(from: rawText) ?? RewriteAnswerPayload(
            title: String(localized: "AI Answer"),
            content: rawText
        )
        guard !previewPayload.trimmedTitle.isEmpty || !previewPayload.trimmedContent.isEmpty else { return }

        configureAnswerOverlayInjectionHandler()
        let canInjectIntoFocusedInput =
            overlayState.latestCompletedAnswerPayload != nil
                ? resolvedCanInjectIntoFocusedInputForRewriteAnswer(logResult: false)
                : false

        overlayState.presentStreamingAnswer(
            title: previewPayload.title,
            content: previewPayload.content,
            canInject: canInjectIntoFocusedInput
        )
        overlayWindow.show(state: overlayState, position: overlayPosition)
    }

    func presentRewriteConversationStreamingPreview(content: String) {
        let normalizedContent = RewriteAnswerContentNormalizer.normalizePlainTextStreamingPreview(content)
        guard !normalizedContent.isEmpty else { return }

        configureAnswerOverlayInjectionHandler()
        let canInjectIntoFocusedInput =
            overlayState.latestCompletedAnswerPayload != nil
                ? resolvedCanInjectIntoFocusedInputForRewriteAnswer(logResult: false)
                : false

        overlayState.presentStreamingConversationAnswer(
            content: normalizedContent,
            canInject: canInjectIntoFocusedInput
        )
        overlayWindow.show(state: overlayState, position: overlayPosition)
    }

    private func normalizedRewriteAnswerPayload(_ payload: RewriteAnswerPayload) -> RewriteAnswerPayload {
        RewriteAnswerPayloadParser.normalize(payload)
    }

    func dismissAnswerOverlay() {
        guard overlayState.displayMode == .answer else { return }
        cancelPendingSelectedTextTranslationRefresh()
        releaseResidualRecordingResources(reason: "dismiss-answer-overlay")
        overlayWindow.hide { [weak self] in
            guard let self else { return }
            self.overlayWindow.onRequestInject = nil
            self.overlayState.reset()
            self.sessionTargetApplicationPID = nil
            self.sessionTargetApplicationBundleID = nil
            self.selectedTextTranslationHadWritableFocusedInput = false
        }
    }

    func injectAnswerOverlayContent() {
        let trimmed = overlayState.latestCompletedAnswerPayload?.trimmedContent ?? ""
        guard !trimmed.isEmpty else { return }
        guard overlayState.canInjectAnswer else { return }
        VoxtLog.info("Answer overlay inject requested. chars=\(trimmed.count), canInject=\(overlayState.canInjectAnswer)")
        typeText(trimmed) { [weak self] didInject in
            guard let self, didInject else { return }
            self.dismissAnswerOverlay()
        }
    }

    func showCurrentTranscriptionDetailWindow() {
        guard let historyEntryID = overlayState.latestHistoryEntryID else {
            VoxtLog.warning("Transcription detail open skipped: latest history entry ID was unavailable.")
            return
        }
        showTranscriptionDetailWindow(for: historyEntryID)
    }

    private func configureAnswerOverlayInjectionHandler() {
        overlayWindow.onRequestInject = { [weak self] in
            Task { @MainActor [weak self] in
                self?.injectAnswerOverlayContent()
            }
        }
    }

    private func resolvedCanInjectIntoFocusedInputForRewriteAnswer(logResult: Bool) -> Bool {
        let liveHasWritableFocusedInput = hasWritableFocusedTextInput()
        let hasFallbackInjectTarget = rewriteSessionFallbackInjectBundleID != nil
        let canInjectIntoFocusedInput =
            rewriteSessionHadWritableFocusedInput ||
            liveHasWritableFocusedInput ||
            hasFallbackInjectTarget
        if logResult {
            VoxtLog.info(
                "Rewrite answer overlay inject check. sessionHadWritableFocusedInput=\(rewriteSessionHadWritableFocusedInput), liveHasWritableFocusedInput=\(liveHasWritableFocusedInput), fallbackBundleID=\(rewriteSessionFallbackInjectBundleID ?? "nil"), canInject=\(canInjectIntoFocusedInput)"
            )
        }
        return canInjectIntoFocusedInput
    }

    func extractRewriteAnswerPayload(from text: String) -> RewriteAnswerPayload? {
        RewriteAnswerPayloadParser.extract(from: text)
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
        AXUIElementSetMessagingTimeout(systemWide, Self.axMessagingTimeout)
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
        AXUIElementSetMessagingTimeout(appElement, Self.axMessagingTimeout)
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

    private func typeText(_ text: String, completion: ((Bool) -> Void)? = nil) {
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

    private func beginOverlayOutputDelivery() {
        overlayState.isRequesting = true
        overlayState.isCompleting = false
        if overlayState.displayMode != .answer {
            overlayState.displayMode = .processing
        }
    }

    private func endOverlayOutputDelivery() {
        overlayState.isRequesting = false
    }

    private func writeTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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

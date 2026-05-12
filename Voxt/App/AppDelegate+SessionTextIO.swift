import Foundation
import AppKit
import ApplicationServices

extension AppDelegate {
    private enum SessionOutputDelivery {
        case typeText
        case answerOverlay
        case selectedTextTranslationResultWindow
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
            context.dictionaryCorrectionSnapshots = result.correctionSnapshots
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

    private struct SessionTimingSummarySnapshot {
        let transcriptionCapturePipeline: TranscriptionCapturePipeline
        let captureStageLabels: [String]
        let asrProvider: String
        let asrModel: String
        let captureMetrics: TranscriptionCaptureMetrics?
        let recordingRequestedAt: Date?
        let recordingStartedAt: Date?
        let recordingStoppedAt: Date?
        let transcriptionResultReceivedAt: Date?
        let firstLiveASRPartialReceivedAt: Date?
        let sessionFinalOutputDeliveredAt: Date?
        let llmExecutions: [SessionLLMExecutionTiming]
    }

    private struct PersistDictionaryEvidenceStage: SessionFinalizeStage {
        let persist: ([DictionaryMatchCandidate], [DictionarySuggestionDraft], UUID?) -> Void

        var name: String { "persistDictionaryEvidence" }

        func run(context: inout SessionFinalizeContext) {
            persist(context.dictionaryMatches, context.dictionarySuggestions, context.historyEntryID)
        }
    }

    private struct AppendHistoryStage: SessionFinalizeStage {
        let append: (String, String?, TimeInterval?, [String], [String], [DictionaryCorrectionSnapshot], [DictionarySuggestionSnapshot]) -> UUID?

        var name: String { "appendHistory" }

        func run(context: inout SessionFinalizeContext) {
            context.historyEntryID = append(
                context.outputText,
                context.rewriteAnswerPayload?.trimmedTitle,
                context.llmDurationSeconds,
                Self.uniqueTerms(from: context.dictionaryMatches),
                Self.deduplicatedTerms(context.dictionaryCorrectedTerms),
                context.dictionaryCorrectionSnapshots,
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
        let callbackDecision = Self.sessionCallbackHandlingDecision(
            requestedSessionID: sessionID,
            activeSessionID: activeRecordingSessionID,
            isSessionCancellationRequested: isSessionCancellationRequested
        )
        guard callbackDecision == .accept else {
            VoxtLog.warning(
                """
                Commit transcription abandoned after session invalidation. reason=\(callbackDecision.logDescription), sessionID=\(sessionID.uuidString), activeSessionID=\(activeRecordingSessionID.uuidString), outputMode=\(RecordingSessionSupport.outputLabel(for: sessionOutputMode)), chars=\(text.count), stopped=\(recordingStoppedAt != nil)
                """
            )
            return
        }

        VoxtLog.info("Commit transcription entered. characters=\(text.count)")

        let context = Self.preparedDeliveryContext(
            originalText: text,
            llmDurationSeconds: llmDurationSeconds,
            sessionOutputMode: sessionOutputMode,
            userMainLanguage: userMainLanguage,
            matcher: dictionaryStore.makeMatcherIfEnabled(activeGroupID: activeDictionaryGroupID()),
            usesConservativeEvidence: shouldUseConservativeDictionaryEvidenceForCurrentSession(),
            automaticReplacementEnabled: UserDefaults.standard.bool(
                forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled
            )
        )
        cacheLatestInjectableOutputText(context.outputText)

        VoxtLog.info(
            "Commit transcription prepared payload. inputChars=\(text.count), outputChars=\(context.outputText.count), hasRewritePayload=\(context.rewriteAnswerPayload != nil), dictionaryMatches=\(context.dictionaryMatches.count), dictionaryCorrections=\(context.dictionaryCorrectedTerms.count)"
        )

        deliverCommittedOutput(context) { [weak self] didInject in
            guard let self else { return }
            self.finalizeCommittedOutputPostDeliveryAsync(
                deliveredContext: context,
                outputMode: sessionOutputMode,
                didInject: didInject
            )
            onDeliveryCompleted?()
        }
    }

    func preparedDeliveryContextForCurrentSession(
        originalText: String,
        llmDurationSeconds: TimeInterval?
    ) -> SessionFinalizeContext {
        Self.preparedDeliveryContext(
            originalText: originalText,
            llmDurationSeconds: llmDurationSeconds,
            sessionOutputMode: sessionOutputMode,
            userMainLanguage: userMainLanguage,
            matcher: dictionaryStore.makeMatcherIfEnabled(activeGroupID: activeDictionaryGroupID()),
            usesConservativeEvidence: shouldUseConservativeDictionaryEvidenceForCurrentSession(),
            automaticReplacementEnabled: UserDefaults.standard.bool(
                forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled
            )
        )
    }

    func finalizePreviouslyDeliveredOutput(
        _ text: String,
        llmDurationSeconds: TimeInterval?,
        didInject: Bool,
        onDeliveryCompleted: (() -> Void)? = nil
    ) {
        if didCommitSessionOutput {
            VoxtLog.info("Skipping duplicate finalize for previously delivered session output.")
            return
        }
        didCommitSessionOutput = true

        let sessionID = activeRecordingSessionID
        let callbackDecision = Self.sessionCallbackHandlingDecision(
            requestedSessionID: sessionID,
            activeSessionID: activeRecordingSessionID,
            isSessionCancellationRequested: isSessionCancellationRequested
        )
        guard callbackDecision == .accept else {
            VoxtLog.warning(
                "Finalize previously delivered output abandoned after session invalidation. reason=\(callbackDecision.logDescription), sessionID=\(sessionID.uuidString)"
            )
            return
        }

        let context = preparedDeliveryContextForCurrentSession(
            originalText: text,
            llmDurationSeconds: llmDurationSeconds
        )
        cacheLatestInjectableOutputText(context.outputText)
        finalizeCommittedOutputPostDeliveryAsync(
            deliveredContext: context,
            outputMode: sessionOutputMode,
            didInject: didInject
        )
        onDeliveryCompleted?()
    }

    func tryDeliverPreviewOutputIfPossible(
        _ text: String,
        sessionID: UUID,
        requestID: UUID?
    ) async -> String? {
        let context = preparedDeliveryContextForCurrentSession(
            originalText: text,
            llmDurationSeconds: nil
        )
        guard resolvedOutputDelivery(for: context) == .typeText else {
            return nil
        }
        guard let transaction = makePendingOutputReplacementTransaction(
            previewText: context.outputText,
            sessionID: sessionID,
            expectedBundleID: sessionTargetApplicationBundleID
        ) else {
            return nil
        }

        beginOverlayOutputDelivery()
        let didInject = await withCheckedContinuation { continuation in
            typeText(context.outputText) { injected in
                continuation.resume(returning: injected)
            }
        }
        endOverlayOutputDelivery()

        guard didInject else { return nil }
        guard shouldHandleCallbacks(for: sessionID),
              requestID.map(isCurrentLLMRequest) ?? true
        else {
            return nil
        }

        pendingOutputReplacementTransaction = transaction
        cacheLatestInjectableOutputText(context.outputText)
        VoxtLog.info(
            "Preview output injected. chars=\(context.outputText.count), sessionID=\(sessionID.uuidString)"
        )
        return context.outputText
    }

    func performPendingOutputReplacementIfPossible(
        with text: String,
        sessionID: UUID
    ) async -> Bool {
        guard let transaction = pendingOutputReplacementTransaction,
              transaction.sessionID == sessionID else {
            return false
        }

        defer {
            pendingOutputReplacementTransaction = nil
        }

        return await performPendingOutputReplacement(transaction, replacementText: text)
    }

    nonisolated static func resolveDictionaryOutput(
        text: String,
        matcher: DictionaryMatcher?,
        usesConservativeEvidence: Bool,
        automaticReplacementEnabled: Bool
    ) -> DictionaryCorrectionResult {
        guard let matcher else {
            return DictionaryCorrectionResult(
                text: text,
                candidates: [],
                correctedTerms: [],
                correctionSnapshots: []
            )
        }

        if usesConservativeEvidence {
            let candidates = matcher.recallCandidates(in: text)
            return DictionaryCorrectionResult(
                text: text,
                candidates: candidates,
                correctedTerms: [],
                correctionSnapshots: []
            )
        }

        return matcher.applyCorrections(
            to: text,
            automaticReplacementEnabled: automaticReplacementEnabled
        )
    }

    nonisolated static func preparedDeliveryContext(
        originalText: String,
        llmDurationSeconds: TimeInterval?,
        sessionOutputMode: SessionOutputMode,
        userMainLanguage: UserMainLanguageOption,
        matcher: DictionaryMatcher?,
        usesConservativeEvidence: Bool,
        automaticReplacementEnabled: Bool
    ) -> SessionFinalizeContext {
        let normalized = normalizedOutputText(
            originalText,
            sessionOutputMode: sessionOutputMode,
            userMainLanguage: userMainLanguage
        )

        let extractedRewriteAnswerPayload = RewriteAnswerPayloadParser.extract(from: normalized)
        let rewriteContent = extractedRewriteAnswerPayload?.content ?? normalized
        let dictionaryCorrection = resolveDictionaryOutput(
            text: rewriteContent,
            matcher: matcher,
            usesConservativeEvidence: usesConservativeEvidence,
            automaticReplacementEnabled: automaticReplacementEnabled
        )
        let uniqueDictionaryMatches = orderedUniqueDictionaryMatches(dictionaryCorrection.candidates)
        let rewriteAnswerPayload = extractedRewriteAnswerPayload.map {
            RewriteAnswerPayload(title: $0.title, content: dictionaryCorrection.text)
        }

        return SessionFinalizeContext(
            outputText: dictionaryCorrection.text,
            llmDurationSeconds: llmDurationSeconds,
            dictionaryMatches: uniqueDictionaryMatches,
            dictionaryCorrectedTerms: dictionaryCorrection.correctedTerms,
            dictionaryCorrectionSnapshots: dictionaryCorrection.correctionSnapshots,
            dictionarySuggestions: [],
            historyEntryID: nil,
            rewriteAnswerPayload: rewriteAnswerPayload
        )
    }

    nonisolated private static func orderedUniqueDictionaryMatches(
        _ candidates: [DictionaryMatchCandidate]
    ) -> [DictionaryMatchCandidate] {
        var seen = Set<String>()
        var ordered: [DictionaryMatchCandidate] = []
        for candidate in candidates {
            let normalized = DictionaryStore.normalizeTerm(candidate.term)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(candidate)
        }
        return ordered
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
        completion: ((Bool) -> Void)? = nil
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
            typeText(context.outputText) { [weak self] didInject in
                self?.sessionFinalOutputDeliveredAt = Date()
                self?.endOverlayOutputDelivery()
                completion?(didInject)
            }
        case .answerOverlay:
            if overlayState.isRewriteConversationActive, context.rewriteAnswerPayload == nil {
                presentRewriteConversationAnswerOverlay(content: context.outputText)
            } else {
                let payload = resolvedAnswerPayload(for: context)
                presentRewriteAnswerOverlay(title: payload.title, content: payload.content)
            }
            sessionFinalOutputDeliveredAt = Date()
            completion?(false)
        case .selectedTextTranslationResultWindow:
            presentSelectedTextTranslationAnswerOverlay(content: context.outputText)
            sessionFinalOutputDeliveredAt = Date()
            completion?(false)
        }
    }

    private func finalizeCommittedOutputPostDeliveryAsync(
        deliveredContext: SessionFinalizeContext,
        outputMode: SessionOutputMode,
        didInject: Bool
    ) {
        let deliveredText = deliveredContext.outputText
        let displayTitle = deliveredContext.rewriteAnswerPayload?.trimmedTitle
        let dictionaryMatches = deliveredContext.dictionaryMatches
        let dictionaryCorrectedTerms = deliveredContext.dictionaryCorrectedTerms
        let dictionaryCorrectionSnapshots = deliveredContext.dictionaryCorrectionSnapshots
        let llmDurationSeconds = deliveredContext.llmDurationSeconds
        let asrSummary = sessionASRSummary(for: outputMode)
        let timingSnapshot = SessionTimingSummarySnapshot(
            transcriptionCapturePipeline: transcriptionCapturePipeline,
            captureStageLabels: transcriptionCapturePipeline.stageLabels,
            asrProvider: asrSummary.provider,
            asrModel: asrSummary.model,
            captureMetrics: currentTranscriptionCaptureMetrics(),
            recordingRequestedAt: recordingRequestedAt,
            recordingStartedAt: recordingStartedAt,
            recordingStoppedAt: recordingStoppedAt,
            transcriptionResultReceivedAt: transcriptionResultReceivedAt,
            firstLiveASRPartialReceivedAt: firstLiveASRPartialReceivedAt,
            sessionFinalOutputDeliveredAt: sessionFinalOutputDeliveredAt,
            llmExecutions: sessionLLMExecutionTimings
        )

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let dictionarySuggestions = await MainActor.run {
                self.previewDictionarySuggestions(
                    for: deliveredText,
                    candidates: dictionaryMatches,
                    correctedTerms: dictionaryCorrectedTerms
                )
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                let historyEntryID = self.appendHistoryIfNeeded(
                    text: deliveredText,
                    outputMode: outputMode,
                    displayTitle: displayTitle,
                    llmDurationSeconds: llmDurationSeconds,
                    dictionaryHitTerms: Self.orderedUniqueDictionaryTerms(from: dictionaryMatches.map(\.term)),
                    dictionaryCorrectedTerms: Self.orderedUniqueDictionaryTerms(from: dictionaryCorrectedTerms),
                    dictionaryCorrectionSnapshots: dictionaryCorrectionSnapshots,
                    dictionarySuggestedTerms: dictionarySuggestions.map(\.snapshot)
                )
                self.overlayState.latestHistoryEntryID = historyEntryID
                self.scheduleAutomaticDictionaryLearningIfNeeded(
                    insertedText: deliveredText,
                    outputMode: outputMode,
                    didInject: didInject,
                    historyEntryID: historyEntryID
                )
                self.persistDictionaryEvidence(
                    candidates: dictionaryMatches,
                    suggestions: dictionarySuggestions,
                    historyEntryID: historyEntryID
                )
                VoxtLog.info(
                    "Deliver committed output finalized. historyEntryID=\(historyEntryID?.uuidString ?? "nil"), characters=\(deliveredText.count)"
                )
                self.logSessionTimingSummaryIfPossible(
                    snapshot: timingSnapshot,
                    deliveredText: deliveredText,
                    outputMode: outputMode,
                    didInject: didInject
                )
            }
        }
    }

    private func logSessionTimingSummaryIfPossible(
        snapshot: SessionTimingSummarySnapshot,
        deliveredText: String,
        outputMode: SessionOutputMode,
        didInject: Bool
    ) {
        let outputCompletedAt = snapshot.sessionFinalOutputDeliveredAt ?? Date()
        let firstLLMExecution = snapshot.llmExecutions.first
        let finalLLMExecution = snapshot.llmExecutions.last

        let requestToStartMs = resolvedDurationMs(from: snapshot.recordingRequestedAt, to: snapshot.recordingStartedAt)
        let startToStopMs = resolvedDurationMs(from: snapshot.recordingStartedAt, to: snapshot.recordingStoppedAt)
        let startToFirstLiveASRMs = resolvedDurationMs(
            from: snapshot.recordingStartedAt,
            to: snapshot.firstLiveASRPartialReceivedAt
        )
        let stopToASRMs = resolvedDurationMs(from: snapshot.recordingStoppedAt, to: snapshot.transcriptionResultReceivedAt)
        let asrToFirstChunkMs = resolvedDurationMs(
            from: snapshot.transcriptionResultReceivedAt,
            to: firstLLMExecution?.firstChunkAt
        )
        let asrToFirstCompleteMs = resolvedDurationMs(
            from: snapshot.transcriptionResultReceivedAt,
            to: firstLLMExecution?.completedAt
        )
        let asrToFinalCompleteMs = resolvedDurationMs(
            from: snapshot.transcriptionResultReceivedAt,
            to: finalLLMExecution?.completedAt
        )
        let asrToDeliveredMs = resolvedDurationMs(
            from: snapshot.transcriptionResultReceivedAt,
            to: outputCompletedAt
        )
        let wallClockCaptureMs = resolvedDurationMs(
            from: snapshot.recordingStartedAt,
            to: snapshot.recordingStoppedAt
        )
        let capturedAudioMs = snapshot.captureMetrics.map { Int($0.capturedAudioSeconds * 1000) }
        let captureGapMs = resolvedCaptureGapMs(
            wallClockCaptureMs: wallClockCaptureMs,
            capturedAudioMs: capturedAudioMs
        )
        let stopToDeliveredMs = resolvedDurationMs(from: snapshot.recordingStoppedAt, to: outputCompletedAt)
        let overallMs = resolvedDurationMs(from: snapshot.recordingRequestedAt, to: outputCompletedAt)

        let firstLLMSummary = sessionLLMSummaryLabel(firstLLMExecution)
        let finalLLMSummary = sessionLLMSummaryLabel(finalLLMExecution)

        if let captureGapMs, captureGapMs >= 350 {
            VoxtLog.warning(
                "Transcription capture gap detected. pipeline=\(snapshot.transcriptionCapturePipeline.rawValue), captureGapMs=\(captureGapMs), capturedAudioMs=\(timingValueLabel(capturedAudioMs)), startToStopMs=\(timingValueLabel(startToStopMs))"
            )
        }

        VoxtLog.info(
            """
            Session timing summary. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), pipeline=\(snapshot.transcriptionCapturePipeline.rawValue), stages=\(snapshot.captureStageLabels.joined(separator: ">")), asrProvider=\(snapshot.asrProvider), asrModel=\(snapshot.asrModel), llmCalls=\(snapshot.llmExecutions.count), deliveredChars=\(deliveredText.count), didInject=\(didInject), requestToStartMs=\(timingValueLabel(requestToStartMs)), startToStopMs=\(timingValueLabel(startToStopMs)), startToFirstLiveASRMs=\(timingValueLabel(startToFirstLiveASRMs)), capturedAudioMs=\(timingValueLabel(capturedAudioMs)), captureGapMs=\(timingValueLabel(captureGapMs)), stopToASRMs=\(timingValueLabel(stopToASRMs)), asrToFirstLLMChunkMs=\(timingValueLabel(asrToFirstChunkMs)), asrToFirstLLMCompleteMs=\(timingValueLabel(asrToFirstCompleteMs)), asrToFinalLLMCompleteMs=\(timingValueLabel(asrToFinalCompleteMs)), asrToDeliveredMs=\(timingValueLabel(asrToDeliveredMs)), stopToDeliveredMs=\(timingValueLabel(stopToDeliveredMs)), overallMs=\(timingValueLabel(overallMs)), firstLLM=\(firstLLMSummary), finalLLM=\(finalLLMSummary)
            """
        )
    }

    private func sessionASRSummary(for outputMode: SessionOutputMode) -> (provider: String, model: String) {
        let selectionID: FeatureModelSelectionID
        switch outputMode {
        case .transcription:
            selectionID = transcriptionFeatureSettings.asrSelectionID
        case .translation:
            selectionID = translationFeatureSettings.asrSelectionID
        case .rewrite:
            selectionID = rewriteFeatureSettings.asrSelectionID
        }

        switch selectionID.asrSelection {
        case .dictation:
            return ("dictation", "builtin")
        case .mlx(let repo):
            return ("mlx", MLXModelManager.canonicalModelRepo(repo))
        case .whisper(let modelID):
            return ("whisper", WhisperKitModelManager.canonicalModelID(modelID))
        case .remote(let provider):
            let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
            let stored = RemoteModelConfigurationStore.loadConfigurations(from: raw)
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: stored)
            return ("remote:\(provider.rawValue)", configuration.model)
        case .none:
            switch transcriptionEngine {
            case .dictation:
                return ("dictation", "builtin")
            case .mlxAudio:
                return ("mlx", MLXModelManager.canonicalModelRepo(mlxModelManager.currentModelRepo))
            case .whisperKit:
                return ("whisper", WhisperKitModelManager.canonicalModelID(whisperModelManager.currentModelID))
            case .remote:
                return ("remote", "unknown")
            }
        }
    }

    private func resolvedDurationMs(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return max(Int(end.timeIntervalSince(start) * 1000), 0)
    }

    private func resolvedLeadMs(earlier: Date?, later: Date?) -> Int? {
        guard let earlier, let later else { return nil }
        let deltaMs = Int(later.timeIntervalSince(earlier) * 1000)
        return deltaMs >= 0 ? deltaMs : nil
    }

    private func resolvedCaptureGapMs(
        wallClockCaptureMs: Int?,
        capturedAudioMs: Int?
    ) -> Int? {
        guard let wallClockCaptureMs, let capturedAudioMs else { return nil }
        return max(wallClockCaptureMs - capturedAudioMs, 0)
    }

    private func timingValueLabel(_ value: Int?) -> String {
        value.map(String.init) ?? "n/a"
    }

    private func sessionLLMSummaryLabel(_ execution: SessionLLMExecutionTiming?) -> String {
        guard let execution else { return "n/a" }
        let diagnostics = execution.diagnostics
        let firstChunk = diagnostics?.overallFirstChunkMs.map(String.init) ?? "n/a"
        let prefill = diagnostics?.prefillMs.map(String.init) ?? "n/a"
        let generation = diagnostics?.generationMs.map(String.init) ?? "n/a"
        let total = diagnostics.map { String($0.totalElapsedMs) } ?? timingValueLabel(
            resolvedDurationMs(from: execution.startedAt, to: execution.completedAt)
        )
        return
            "task=\(execution.taskLabel),provider=\(execution.providerLabel),firstChunkMs=\(firstChunk),prefillMs=\(prefill),generationMs=\(generation),totalElapsedMs=\(total)"
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

}

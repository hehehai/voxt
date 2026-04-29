import Foundation
import AppKit

extension AppDelegate {
    private struct TranslateStage: SessionPipelineStage {
        let targetLanguage: TranslationTargetLanguage
        let transform: @MainActor (String, TranslationTargetLanguage) async throws -> String

        var name: String { "translate" }

        func run(context: SessionPipelineContext) async throws -> SessionPipelineContext {
            var next = context
            next.workingText = try await transform(context.workingText, targetLanguage)
            return next
        }
    }

    private struct RewriteStage: SessionPipelineStage {
        let sourceText: String
        let transform: @MainActor (String, String) async throws -> String

        var name: String { "rewrite" }

        func run(context: SessionPipelineContext) async throws -> SessionPipelineContext {
            var next = context
            next.workingText = try await transform(context.workingText, sourceText)
            return next
        }
    }

    private struct StrictRetryTranslateStage: SessionPipelineStage {
        let targetLanguage: TranslationTargetLanguage
        let shouldRetry: @MainActor (String, String) -> Bool
        let strictTranslate: @MainActor (String, TranslationTargetLanguage) async throws -> String

        var name: String { "strictRetryTranslate" }

        func run(context: SessionPipelineContext) async throws -> SessionPipelineContext {
            guard shouldRetry(context.originalText, context.workingText) else { return context }
            var next = context
            next.workingText = try await strictTranslate(context.originalText, targetLanguage)
            return next
        }
    }

    // MARK: - Translation Flow
    // Keeps translation/enhancement orchestration isolated from recording lifecycle.

    func runTranslationPreview(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let previousSelectedTextTranslationFlow = isSelectedTextTranslationFlow
        isSelectedTextTranslationFlow = false
        defer {
            isSelectedTextTranslationFlow = previousSelectedTextTranslationFlow
        }

        return try await runTranslationPipeline(
            text: trimmed,
            targetLanguage: translationTargetLanguage,
            allowStrictRetry: true
        )
    }

    func runRewritePreview(dictatedPrompt: String, sourceText: String) async throws -> String {
        let trimmedPrompt = dictatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty || !trimmedSource.isEmpty else { return "" }

        return try await runRewritePipeline(
            dictatedText: trimmedPrompt,
            selectedSourceText: trimmedSource,
            conversationHistory: [],
            structuredAnswerOutput: trimmedSource.isEmpty
        )
    }

    func processTranslatedTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        let targetLanguage = effectiveSessionTranslationTargetLanguage
        let resolution = resolvedTranslationProviderResolution(
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: false
        )
        VoxtLog.info(
            "Translation flow started. inputChars=\(text.count), targetLanguage=\(targetLanguage.instructionName), translationModelProvider=\(translationModelProvider.rawValue), resolvedProvider=\(resolution.provider.rawValue)"
        )
        setEnhancingState(true)
        _Concurrency.Task<Void, Never> {
            defer {
                self.setEnhancingState(false)
            }

            let llmStartedAt = Date()
            do {
                // Translation mode pipeline: translate only.
                let translated = try await self.runTranslationPipeline(
                    text: text,
                    targetLanguage: targetLanguage,
                    allowStrictRetry: false
                )
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Translation output may be untranslated. sourceChars=\(text.count), outputChars=\(translated.count)")
                }
                VoxtLog.info("Translation flow succeeded. outputChars=\(translated.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.commitTranscription(translated, llmDurationSeconds: llmDuration) { [weak self] in
                    guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                    self.finishSession(after: 0)
                }
            } catch {
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                VoxtLog.warning("Translation flow failed, using raw text: \(error)")
                self.commitTranscription(text, llmDurationSeconds: nil) { [weak self] in
                    guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                    self.finishSession(after: 0)
                }
            }
        }
    }

    func processWhisperTranslatedTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        VoxtLog.info("Whisper direct translation completed. outputChars=\(text.count)")
        commitTranscription(text, llmDurationSeconds: nil) { [weak self] in
            self?.finishSession(after: 0)
        }
    }

    func translateMeetingRealtimeText(_ text: String, targetLanguage: TranslationTargetLanguage) async throws -> String {
        let resolution = MeetingTranslationSupport.resolvedProvider(
            selectedProvider: translationModelProvider,
            fallbackProvider: translationFallbackModelProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: targetLanguage,
            whisperModelState: whisperModelManager.state
        )
        let resolvedPrompt = resolvedTranslationPrompt(
            targetLanguage: targetLanguage,
            sourceText: text,
            strict: false
        )

        switch resolution.provider {
        case .customLLM:
            let repo = translationCustomLLMRepo
            guard customLLMManager.isModelDownloaded(repo: repo) else {
                throw NSError(
                    domain: "Voxt.MeetingTranslation",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Custom LLM model is not installed.")]
                )
            }
            return try await customLLMManager.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: resolvedPrompt,
                modelRepo: repo
            )
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: true)
            guard context.configuration.hasUsableModel else {
                throw NSError(
                    domain: "Voxt.MeetingTranslation",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("No configured remote LLM model yet.")]
                )
            }
            return try await RemoteLLMRuntimeClient().translate(
                text: text,
                systemPrompt: resolvedPrompt,
                provider: context.provider,
                configuration: context.configuration
            )
        case .whisperKit:
            throw NSError(
                domain: "Voxt.MeetingTranslation",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Meeting realtime translation requires a text-capable translation provider.")]
            )
        }
    }

    func beginSelectedTextTranslationIfPossible() -> Bool {
        guard translateSelectedTextOnTranslationHotkey else { return false }
        guard !isSessionActive else { return false }
        guard let selectedText = selectedTextFromSystemSelection(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        pendingSessionFinishTask?.cancel()
        pendingSessionFinishTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
        releaseResidualRecordingResources(reason: "selected-text-translation-begin")
        resetSessionTranslationState()
        overlayState.reset()
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmostApplication?.bundleIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier
        if let frontmostBundleID,
           frontmostBundleID != ownBundleID {
            sessionTargetApplicationBundleID = frontmostBundleID
        } else {
            sessionTargetApplicationBundleID = nil
        }
        sessionTargetApplicationPID = sessionTargetApplicationBundleID == nil ? nil : frontmostApplication?.processIdentifier
        selectedTextTranslationHadWritableFocusedInput = hasWritableFocusedTextInput()
        overlayState.transcribedText = selectedText
        overlayState.setAnswerTranslationSourceText(selectedText)
        overlayState.statusMessage = ""
        overlayState.presentRecording(iconMode: .translation)
        overlayWindow.show(state: overlayState, position: overlayPosition)

        let startedAt = Date()
        isSessionActive = true
        isSelectedTextTranslationFlow = true
        didCommitSessionOutput = false
        isSessionCancellationRequested = false
        activeRecordingSessionID = UUID()
        currentEndingSessionID = nil
        lastCompletedSessionEndSessionID = nil
        sessionOutputMode = .translation
        recordingStartedAt = startedAt
        recordingStoppedAt = startedAt
        transcriptionProcessingStartedAt = nil
        transcriptionResultReceivedAt = nil
        enhancementContextSnapshot = nil
        lastEnhancementPromptContext = nil

        if interactionSoundsEnabled {
            interactionSoundPlayer.playStart()
        }

        VoxtLog.info("Selected text translation started. inputChars=\(selectedText.count)")
        processSelectedTextTranslation(selectedText)
        return true
    }

    func processRewriteTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        let isConversationContinuation = overlayState.isRewriteConversationActive
        let selectedSourceText: String
        let conversationHistory: [RewriteConversationPromptTurn]
        let prefersStructuredAnswerOutput: Bool
        let previousConversationResponseID: String?

        if isConversationContinuation {
            selectedSourceText = ""
            conversationHistory = overlayState.rewriteConversationPromptHistory
            rewriteSessionHasSelectedSourceText = false
            prefersStructuredAnswerOutput = false
            previousConversationResponseID = overlayState.rewriteConversationRemoteResponseID
            overlayState.stageConversationUserPrompt(text)
        } else {
            selectedSourceText = selectedTextFromSystemSelection()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            rewriteSessionHasSelectedSourceText = !selectedSourceText.isEmpty
            conversationHistory = []
            prefersStructuredAnswerOutput = shouldUseStructuredRewriteAnswerOutput(
                hasSelectedSourceText: rewriteSessionHasSelectedSourceText
            )
            previousConversationResponseID = nil
        }
        VoxtLog.info(
            "Rewrite flow started. promptChars=\(text.count), selectedSourceChars=\(selectedSourceText.count), rewriteModelProvider=\(rewriteModelProvider.rawValue), structuredAnswerOutput=\(prefersStructuredAnswerOutput), conversationHistoryTurns=\(conversationHistory.count)"
        )
        setEnhancingState(true)
        let progressHandler: (@Sendable (String) -> Void)? = if isConversationContinuation {
            { [weak self] partialOutput in
                Task { @MainActor [weak self] in
                    guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                    self.presentRewriteConversationStreamingPreview(content: partialOutput)
                }
            }
        } else {
            nil
        }

        Task {
            defer {
                self.setEnhancingState(false)
            }

            let llmStartedAt = Date()
            var latestConversationResponseID: String?
            do {
                var rewritten = try await self.runRewritePipeline(
                    dictatedText: text,
                    selectedSourceText: selectedSourceText,
                    conversationHistory: conversationHistory,
                    structuredAnswerOutput: prefersStructuredAnswerOutput,
                    previousConversationResponseID: previousConversationResponseID,
                    onProgress: progressHandler,
                    onResponseID: { responseID in
                        latestConversationResponseID = responseID
                    }
                )
                if prefersStructuredAnswerOutput,
                   self.shouldRetryStructuredRewriteAnswer(for: rewritten, dictatedPrompt: text) {
                    VoxtLog.warning("Rewrite structured answer was missing usable content; retrying in direct-answer mode.")
                    if let retried = try? await self.rewriteText(
                        dictatedPrompt: text,
                        sourceText: "",
                        conversationHistory: conversationHistory,
                        structuredAnswerOutput: true,
                        forceNonEmptyAnswer: true,
                        previousConversationResponseID: previousConversationResponseID,
                        onProgress: nil,
                        onResponseID: { responseID in
                            latestConversationResponseID = responseID
                        }
                    ) {
                        rewritten = retried
                    }
                }
                if !prefersStructuredAnswerOutput {
                    let normalized = RewriteAnswerContentNormalizer.normalizePlainTextAnswer(rewritten)
                    if normalized != rewritten.trimmingCharacters(in: .whitespacesAndNewlines) {
                        VoxtLog.warning(
                            """
                            Rewrite plain-text answer normalized before delivery.
                            [raw]
                            \(VoxtLog.llmPreview(rewritten))
                            [normalized]
                            \(VoxtLog.llmPreview(normalized))
                            """
                        )
                    }
                    rewritten = normalized
                }
                if prefersStructuredAnswerOutput,
                   self.shouldRetryStructuredRewriteAnswer(for: rewritten, dictatedPrompt: text) {
                    VoxtLog.warning("Rewrite structured answer still unusable after retry; substituting empty-answer placeholder.")
                    rewritten = self.rewriteUnavailableFallbackText(
                        dictatedPrompt: text,
                        sourceText: selectedSourceText,
                        structuredAnswerOutput: true
                    )
                }
                if !prefersStructuredAnswerOutput,
                   RewriteAnswerContentNormalizer.isUnusablePlainTextAnswer(rewritten, dictatedPrompt: text) {
                    VoxtLog.warning("Rewrite plain-text answer was empty or unusable; retrying with stricter non-empty guidance.")
                    if let retried = try? await self.rewriteText(
                        dictatedPrompt: text,
                        sourceText: selectedSourceText,
                        conversationHistory: conversationHistory,
                        structuredAnswerOutput: false,
                        forceNonEmptyAnswer: true,
                        previousConversationResponseID: previousConversationResponseID,
                        onProgress: progressHandler,
                        onResponseID: { responseID in
                            latestConversationResponseID = responseID
                        }
                    ) {
                        rewritten = RewriteAnswerContentNormalizer.normalizePlainTextAnswer(retried)
                    }
                }
                if !prefersStructuredAnswerOutput,
                   RewriteAnswerContentNormalizer.isUnusablePlainTextAnswer(rewritten, dictatedPrompt: text) {
                    VoxtLog.warning("Rewrite plain-text answer remained unusable after retry; substituting fallback text.")
                    rewritten = self.rewriteUnavailableFallbackText(
                        dictatedPrompt: text,
                        sourceText: selectedSourceText,
                        structuredAnswerOutput: false
                    )
                }
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                if isConversationContinuation, let latestConversationResponseID {
                    self.overlayState.rewriteConversationRemoteResponseID = latestConversationResponseID
                }
                if isConversationContinuation,
                   !self.overlayState.isStreamingAnswer,
                   !rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await self.presentRewriteConversationPseudoStreamingPreview(
                        content: rewritten,
                        sessionID: sessionID
                    )
                }
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                VoxtLog.info("Rewrite flow succeeded. outputChars=\(rewritten.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.commitTranscription(rewritten, llmDurationSeconds: llmDuration) { [weak self] in
                    guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                    self.finishSession(after: 0)
                }
            } catch {
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                VoxtLog.warning("Rewrite flow failed, using rewrite fallback: \(error)")
                let fallback = self.rewriteUnavailableFallbackText(
                    dictatedPrompt: text,
                    sourceText: selectedSourceText,
                    structuredAnswerOutput: prefersStructuredAnswerOutput
                )
                self.commitTranscription(fallback, llmDurationSeconds: nil) { [weak self] in
                    guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                    self.finishSession(after: 0)
                }
            }
        }
    }

    func resolvedRemoteLLMContext(forTranslation: Bool) -> (provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration) {
        let provider: RemoteLLMProvider
        if forTranslation, let translationProvider = translationRemoteLLMProvider {
            provider = translationProvider
        } else {
            provider = remoteLLMSelectedProvider
        }

        let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: remoteLLMConfigurations
        )
        return (provider, configuration)
    }

    func resolvedRemoteLLMContext(forRewrite: Bool) -> (provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration) {
        let provider: RemoteLLMProvider
        if forRewrite, let rewriteProvider = rewriteRemoteLLMProvider {
            provider = rewriteProvider
        } else {
            provider = remoteLLMSelectedProvider
        }

        let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: remoteLLMConfigurations
        )
        return (provider, configuration)
    }

    private func translateText(_ text: String, targetLanguage: TranslationTargetLanguage) async throws -> String {
        let resolvedPrompt = resolvedTranslationPrompt(
            targetLanguage: targetLanguage,
            sourceText: text,
            strict: false
        )
        let translationRepo = translationCustomLLMRepo
        let resolution = resolvedTranslationProviderResolution(
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: isSelectedTextTranslationFlow
        )
        let modelProvider = resolution.provider
        VoxtLog.llm(
            "Translation request. promptChars=\(resolvedPrompt.count), inputChars=\(text.count), provider=\(modelProvider.rawValue), selectedProvider=\(translationModelProvider.rawValue), fallbackReason=\(resolution.fallbackReason.map(String.init(describing:)) ?? "none"), translationRepo=\(translationRepo)"
        )

        switch modelProvider {
        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: translationRepo) else {
                VoxtLog.warning("Translation provider customLLM unavailable: model not downloaded. repo=\(translationRepo)")
                showOverlayStatus(
                    String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
                return text
            }
            VoxtLog.info("Translation provider selected: customLLM")
            return try await customLLMManager.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: resolvedPrompt,
                modelRepo: translationRepo
            )
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: true)
            guard context.configuration.hasUsableModel else {
                VoxtLog.warning("Translation provider remoteLLM unavailable: no configured model.")
                showOverlayStatus(
                    String(localized: "No configured remote LLM model yet. Configure a provider in Settings > Model."),
                    clearAfter: 2.5
                )
                return text
            }
            VoxtLog.info("Translation provider selected: remoteLLM(\(context.provider.rawValue))")
            return try await RemoteLLMRuntimeClient().translate(
                text: text,
                systemPrompt: resolvedPrompt,
                provider: context.provider,
                configuration: context.configuration
            )
        case .whisperKit:
            return text
        }
    }

    private func rewriteText(
        dictatedPrompt: String,
        sourceText: String,
        conversationHistory: [RewriteConversationPromptTurn],
        structuredAnswerOutput: Bool,
        forceNonEmptyAnswer: Bool = false,
        previousConversationResponseID: String? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil,
        onResponseID: ((String) -> Void)? = nil
    ) async throws -> String {
        let directAnswerMode = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let modelProvider = rewriteModelProvider
        let runtimeClient = RemoteLLMRuntimeClient()
        let remoteContext = rewriteModelProvider == .remoteLLM ? resolvedRemoteLLMContext(forRewrite: true) : nil
        let shouldUseProviderManagedConversation =
            (remoteContext?.provider.usesResponsesAPI ?? false) &&
            directAnswerMode &&
            !structuredAnswerOutput
        let shouldUseChatMessageConversation =
            modelProvider == .remoteLLM &&
            directAnswerMode &&
            !structuredAnswerOutput &&
            !conversationHistory.isEmpty &&
            !shouldUseProviderManagedConversation
        if shouldUseChatMessageConversation {
            let latestTurn = conversationHistory.last
            VoxtLog.info(
                """
                Rewrite continue conversation context prepared. turns=\(conversationHistory.count), latestTitle=\(VoxtLog.llmPreview(latestTurn?.resultTitle ?? "")), latestContent=\(VoxtLog.llmPreview(latestTurn?.resultContent ?? "")), currentPrompt=\(VoxtLog.llmPreview(dictatedPrompt))
                """
            )
        }
        let resolvedPrompt = shouldUseChatMessageConversation
            ? resolvedRewriteConversationPrompt(forceNonEmptyAnswer: forceNonEmptyAnswer)
            : resolvedRewritePrompt(
                dictatedPrompt: dictatedPrompt,
                sourceText: sourceText,
                conversationHistory: shouldUseProviderManagedConversation ? [] : conversationHistory,
                structuredAnswerOutput: structuredAnswerOutput,
                directAnswerMode: directAnswerMode,
                forceNonEmptyAnswer: forceNonEmptyAnswer
            )
        let rewriteRepo = rewriteCustomLLMRepo
        VoxtLog.llm(
            "Rewrite request. promptChars=\(resolvedPrompt.count), dictatedChars=\(dictatedPrompt.count), sourceChars=\(sourceText.count), provider=\(modelProvider.rawValue), rewriteRepo=\(rewriteRepo), structuredAnswerOutput=\(structuredAnswerOutput), directAnswerMode=\(directAnswerMode), forceNonEmptyAnswer=\(forceNonEmptyAnswer)"
        )
        if shouldUseProviderManagedConversation, let remoteContext {
            VoxtLog.info(
                "Rewrite continue using Responses API. provider=\(remoteContext.provider.rawValue), endpoint=\(remoteContext.configuration.endpoint)"
            )
        } else if modelProvider == .remoteLLM,
                  directAnswerMode,
                  !structuredAnswerOutput,
                  onProgress != nil,
                  let remoteContext {
            VoxtLog.info(
                "Rewrite continue using chat completions stream. provider=\(remoteContext.provider.rawValue), endpoint=\(remoteContext.configuration.endpoint)"
            )
        }

        switch modelProvider {
        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: rewriteRepo) else {
                VoxtLog.warning("Rewrite provider customLLM unavailable: model not downloaded. repo=\(rewriteRepo)")
                showOverlayStatus(
                    String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
                return rewriteUnavailableFallbackText(
                    dictatedPrompt: dictatedPrompt,
                    sourceText: sourceText,
                    structuredAnswerOutput: structuredAnswerOutput
                )
            }
            return try await customLLMManager.rewrite(
                sourceText: sourceText,
                dictatedPrompt: dictatedPrompt,
                systemPrompt: resolvedPrompt,
                modelRepo: rewriteRepo,
                onPartialText: onProgress
            )
        case .remoteLLM:
            let context = remoteContext ?? resolvedRemoteLLMContext(forRewrite: true)
            guard context.configuration.hasUsableModel else {
                VoxtLog.warning("Rewrite provider remoteLLM unavailable: no configured model.")
                showOverlayStatus(
                    String(localized: "No configured remote LLM model yet. Configure a provider in Settings > Model."),
                    clearAfter: 2.5
                )
                return rewriteUnavailableFallbackText(
                    dictatedPrompt: dictatedPrompt,
                    sourceText: sourceText,
                    structuredAnswerOutput: structuredAnswerOutput
                )
            }
            return try await runtimeClient.rewrite(
                sourceText: sourceText,
                dictatedPrompt: dictatedPrompt,
                systemPrompt: resolvedPrompt,
                provider: context.provider,
                configuration: context.configuration,
                conversationHistory: (shouldUseProviderManagedConversation || shouldUseChatMessageConversation) ? conversationHistory : [],
                previousResponseID: shouldUseProviderManagedConversation ? previousConversationResponseID : nil,
                onPartialText: onProgress,
                onResponseID: onResponseID
            )
        }
    }

    private func translateTextStrict(_ text: String, targetLanguage: TranslationTargetLanguage) async throws -> String {
        let strictPrompt = resolvedTranslationPrompt(
            targetLanguage: targetLanguage,
            sourceText: text,
            strict: true
        )
        let translationRepo = translationCustomLLMRepo
        let resolution = resolvedTranslationProviderResolution(
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: isSelectedTextTranslationFlow
        )
        let modelProvider = resolution.provider
        VoxtLog.llm(
            "Strict translation retry. promptChars=\(strictPrompt.count), inputChars=\(text.count), provider=\(modelProvider.rawValue), selectedProvider=\(translationModelProvider.rawValue), fallbackReason=\(resolution.fallbackReason.map(String.init(describing:)) ?? "none"), translationRepo=\(translationRepo)"
        )

        switch modelProvider {
        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: translationRepo) else {
                return text
            }
            return try await customLLMManager.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: strictPrompt,
                modelRepo: translationRepo
            )
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: true)
            guard context.configuration.hasUsableModel else {
                return text
            }
            return try await RemoteLLMRuntimeClient().translate(
                text: text,
                systemPrompt: strictPrompt,
                provider: context.provider,
                configuration: context.configuration
            )
        case .whisperKit:
            return text
        }
    }

    static func effectiveTranslationTargetLanguage(
        savedTargetLanguage: TranslationTargetLanguage,
        sessionOverride: TranslationTargetLanguage?,
        isSelectedTextTranslation: Bool
    ) -> TranslationTargetLanguage {
        guard !isSelectedTextTranslation, let sessionOverride else {
            return savedTargetLanguage
        }
        return sessionOverride
    }

    var effectiveSessionTranslationTargetLanguage: TranslationTargetLanguage {
        Self.effectiveTranslationTargetLanguage(
            savedTargetLanguage: translationTargetLanguage,
            sessionOverride: sessionTranslationTargetLanguageOverride,
            isSelectedTextTranslation: isSelectedTextTranslationFlow
        )
    }

    func resolvedTranslationProviderResolution(
        targetLanguage: TranslationTargetLanguage,
        isSelectedTextTranslation: Bool
    ) -> TranslationProviderResolution {
        Self.resolvedSessionTranslationProviderResolution(
            lockedResolution: activeSessionTranslationProviderResolution,
            selectedProvider: translationModelProvider,
            fallbackProvider: translationFallbackModelProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: isSelectedTextTranslation,
            whisperModelState: whisperModelManager.state
        )
    }

    static func resolvedSessionTranslationProviderResolution(
        lockedResolution: TranslationProviderResolution?,
        selectedProvider: TranslationModelProvider,
        fallbackProvider: TranslationModelProvider,
        transcriptionEngine: TranscriptionEngine,
        targetLanguage: TranslationTargetLanguage,
        isSelectedTextTranslation: Bool,
        whisperModelState: WhisperKitModelManager.ModelState
    ) -> TranslationProviderResolution {
        if !isSelectedTextTranslation,
           let lockedResolution {
            return lockedResolution
        }

        return TranslationProviderResolver.resolve(
            selectedProvider: selectedProvider,
            fallbackProvider: fallbackProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: isSelectedTextTranslation,
            whisperModelState: whisperModelState
        )
    }

    func prepareMicrophoneTranslationSessionState() {
        let persistedTargetLanguage = translationTargetLanguage
        let resolution = TranslationProviderResolver.resolve(
            selectedProvider: translationModelProvider,
            fallbackProvider: translationFallbackModelProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: persistedTargetLanguage,
            isSelectedTextTranslation: false,
            whisperModelState: whisperModelManager.state
        )

        sessionTranslationTargetLanguageOverride = persistedTargetLanguage
        activeSessionTranslationProviderResolution = resolution
        sessionUsesWhisperDirectTranslation = resolution.usesWhisperDirectTranslation
        overlayState.configureSessionTranslationTargetLanguage(
            persistedTargetLanguage,
            allowsSwitching: Self.shouldAllowSessionTranslationLanguageSwitching(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false,
                sessionUsesWhisperDirectTranslation: resolution.usesWhisperDirectTranslation
            )
        )
    }

    func resetSessionTranslationState() {
        cancelPendingSelectedTextTranslationRefresh()
        sessionTranslationTargetLanguageOverride = nil
        activeSessionTranslationProviderResolution = nil
        sessionUsesWhisperDirectTranslation = false
        overlayState.configureSessionTranslationTargetLanguage(nil, allowsSwitching: false)
    }

    static func shouldAllowSessionTranslationLanguageSwitching(
        sessionOutputMode: SessionOutputMode,
        isSelectedTextTranslationFlow: Bool,
        sessionUsesWhisperDirectTranslation: Bool
    ) -> Bool {
        sessionOutputMode == .translation &&
            !isSelectedTextTranslationFlow &&
            !sessionUsesWhisperDirectTranslation
    }

    func toggleSessionTranslationTargetPicker() {
        guard overlayState.allowsSessionTranslationLanguageSwitching else { return }
        if overlayState.isSessionTranslationTargetPickerPresented {
            dismissSessionTranslationTargetPicker()
        } else {
            overlayState.presentSessionTranslationTargetPicker()
        }
    }

    func selectSessionTranslationTargetLanguage(_ language: TranslationTargetLanguage) {
        guard overlayState.allowsSessionTranslationLanguageSwitching else { return }
        let previousLanguage = overlayState.sessionTranslationTargetLanguage
        let shouldRefreshDisplayedTranslation = shouldRefreshDisplayedTranslationAnswer(
            targetLanguage: language,
            previousLanguage: previousLanguage
        )

        if shouldRefreshDisplayedTranslation {
            overlayState.configureSessionTranslationTargetLanguage(language, allowsSwitching: true)
            overlayState.dismissSessionTranslationTargetPicker()
            refreshDisplayedTranslationAnswer(
                targetLanguage: language,
                previousLanguage: previousLanguage
            )
            return
        }

        if isSessionActive {
            sessionTranslationTargetLanguageOverride = language
        } else {
            UserDefaults.standard.set(language.rawValue, forKey: AppPreferenceKey.translationTargetLanguage)
        }
        overlayState.configureSessionTranslationTargetLanguage(language, allowsSwitching: true)
        overlayState.dismissSessionTranslationTargetPicker()
    }

    func dismissSessionTranslationTargetPicker() {
        overlayState.dismissSessionTranslationTargetPicker()
    }

    private func shouldRefreshDisplayedTranslationAnswer(
        targetLanguage: TranslationTargetLanguage,
        previousLanguage: TranslationTargetLanguage?
    ) -> Bool {
        guard overlayState.displayMode == .answer,
              overlayState.sessionIconMode == .translation,
              overlayState.answerInteractionMode == .singleResult
        else {
            return false
        }
        guard targetLanguage != previousLanguage else { return false }
        return !overlayState.answerTranslationSourceText.isEmpty
    }

    private func refreshDisplayedTranslationAnswer(
        targetLanguage: TranslationTargetLanguage,
        previousLanguage: TranslationTargetLanguage?
    ) {
        let sourceText = overlayState.answerTranslationSourceText
        guard !sourceText.isEmpty else { return }

        cancelPendingSelectedTextTranslationRefresh()
        overlayState.isRequesting = true

        let refreshID = UUID()
        selectedTextTranslationRefreshID = refreshID
        pendingSelectedTextTranslationRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                if self.selectedTextTranslationRefreshID == refreshID {
                    self.overlayState.isRequesting = false
                    self.pendingSelectedTextTranslationRefreshTask = nil
                }
            }

            do {
                let translated = try await self.runTranslationPipeline(
                    text: sourceText,
                    targetLanguage: targetLanguage,
                    allowStrictRetry: true
                )
                guard !Task.isCancelled,
                      self.selectedTextTranslationRefreshID == refreshID,
                      self.overlayState.sessionTranslationTargetLanguage == targetLanguage
                else {
                    return
                }

                self.overlayState.replaceCurrentAnswer(
                    title: String(localized: "Translation"),
                    content: translated
                )
            } catch {
                guard !Task.isCancelled,
                      self.selectedTextTranslationRefreshID == refreshID
                else {
                    return
                }

                VoxtLog.warning(
                    "Displayed translation refresh failed. sourceChars=\(sourceText.count), targetLanguage=\(targetLanguage.instructionName), error=\(error)"
                )

                if let previousLanguage {
                    if self.isSessionActive {
                        self.sessionTranslationTargetLanguageOverride = previousLanguage
                    } else {
                        UserDefaults.standard.set(
                            previousLanguage.rawValue,
                            forKey: AppPreferenceKey.translationTargetLanguage
                        )
                    }
                    self.overlayState.configureSessionTranslationTargetLanguage(
                        previousLanguage,
                        allowsSwitching: true
                    )
                }
            }
        }
    }

    func cancelPendingSelectedTextTranslationRefresh() {
        selectedTextTranslationRefreshID = UUID()
        pendingSelectedTextTranslationRefreshTask?.cancel()
        pendingSelectedTextTranslationRefreshTask = nil
        overlayState.isRequesting = false
    }

    private func resolvedTranslationPrompt(
        targetLanguage: TranslationTargetLanguage,
        sourceText: String,
        strict: Bool
    ) -> String {
        let basePrompt = TranslationPromptBuilder.build(
            systemPrompt: translationSystemPrompt,
            targetLanguage: targetLanguage,
            sourceText: sourceText,
            userMainLanguagePromptValue: userMainLanguagePromptValue,
            strict: strict
        )
        return appendDictionaryTranslationGlossary(
            to: basePrompt,
            sourceText: sourceText
        )
    }

    private func resolvedRewritePrompt(
        dictatedPrompt: String,
        sourceText: String,
        conversationHistory: [RewriteConversationPromptTurn],
        structuredAnswerOutput: Bool,
        directAnswerMode: Bool,
        forceNonEmptyAnswer: Bool
    ) -> String {
        let resolved = RewritePromptBuilder.build(
            systemPrompt: rewriteSystemPrompt,
            dictatedPrompt: dictatedPrompt,
            sourceText: sourceText,
            conversationHistory: conversationHistory,
            structuredAnswerOutput: structuredAnswerOutput,
            directAnswerMode: directAnswerMode,
            forceNonEmptyAnswer: forceNonEmptyAnswer
        )
        return appendDictionaryRewriteGlossary(
            to: resolved,
            sourceText: "\(dictatedPrompt)\n\(sourceText)"
        )
    }

    private func resolvedRewriteConversationPrompt(forceNonEmptyAnswer: Bool) -> String {
        let retryConstraint = forceNonEmptyAnswer
            ? """
            Retry rule:
            - A previous answer was empty, quoted-empty, or otherwise unusable.
            - This time, you must return a non-empty plain-text answer.
            - Do not return surrounding quotes.
            """
            : ""

        let base = """
        You are Voxt's follow-up voice conversation assistant.

        The previous conversation is provided as chat messages.
        Respond to the latest user message directly based on that conversation.

        Rules:
        1. Treat the latest user message as a follow-up to the previous assistant reply.
        2. If the user omits context with a short follow-up like “那大同呢”, infer the missing subject from the conversation history.
        3. Return plain text only.
        4. Do not return JSON, field names, markdown, or surrounding quotes.
        5. Do not return an empty string.
        """

        let prompt = [base, retryConstraint]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return appendDictionaryRewriteGlossary(to: prompt, sourceText: "")
    }

    private func shouldRetryStructuredRewriteAnswer(for text: String, dictatedPrompt: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if let payload = extractRewriteAnswerPayload(from: trimmed) {
            let normalizedContent = payload.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPrompt = dictatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedContent.isEmpty || normalizedContent.caseInsensitiveCompare(normalizedPrompt) == .orderedSame
        }

        let normalizedPrompt = dictatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare(normalizedPrompt) == .orderedSame {
            return true
        }

        let lowered = trimmed.lowercased()
        let looksStructuredStub =
            (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
            lowered.contains("\"title\"") ||
            lowered.contains("\"content\"") ||
            lowered.contains("title:") ||
            lowered.contains("content:")
        return looksStructuredStub
    }

    private func rewriteUnavailableFallbackText(
        dictatedPrompt: String,
        sourceText: String,
        structuredAnswerOutput: Bool
    ) -> String {
        if structuredAnswerOutput {
            return serializedRewriteAnswerPayload(
                RewriteAnswerPayload(
                    title: String(localized: "AI Answer"),
                    content: String(localized: "Unable to generate answer.")
                )
            ) ?? #"{"title":"AI Answer","content":"Unable to generate answer."}"#
        }

        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSource.isEmpty {
            return sourceText
        }

        return String(localized: "Unable to generate answer.")
    }

    private func serializedRewriteAnswerPayload(_ payload: RewriteAnswerPayload) -> String? {
        let object: [String: String] = [
            "title": payload.title,
            "content": payload.content
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private func processSelectedTextTranslation(_ text: String) {
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
            }

            let llmStartedAt = Date()
            do {
                let translated = try await self.runTranslationPipeline(
                    text: text,
                    targetLanguage: self.translationTargetLanguage,
                    allowStrictRetry: true
                )
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Selected text translation output may be untranslated. inputChars=\(text.count), outputChars=\(translated.count)")
                }
                VoxtLog.info("Selected text translation succeeded. outputChars=\(translated.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.overlayState.transcribedText = translated
                self.commitTranscription(translated, llmDurationSeconds: llmDuration) { [weak self] in
                    self?.finishSession(after: 0)
                }
            } catch {
                VoxtLog.warning("Selected text translation failed, using original selected text: \(error)")
                self.overlayState.transcribedText = text
                self.commitTranscription(text, llmDurationSeconds: nil) { [weak self] in
                    self?.finishSession(after: 0)
                }
            }
        }
    }

    private func runTranslationPipeline(
        text: String,
        targetLanguage: TranslationTargetLanguage,
        allowStrictRetry: Bool
    ) async throws -> String {
        var stages: [any SessionPipelineStage] = []

        stages.append(
            TranslateStage(
                targetLanguage: targetLanguage,
                transform: { [weak self] value, targetLanguage in
                    guard let self else { return value }
                    return try await self.translateText(value, targetLanguage: targetLanguage)
                }
            )
        )

        if allowStrictRetry {
            stages.append(
                StrictRetryTranslateStage(
                    targetLanguage: targetLanguage,
                    shouldRetry: { [weak self] source, result in
                        guard let self else { return false }
                        if self.looksUntranslated(source: source, result: result) {
                            VoxtLog.warning("Selected text translation first-pass looks untranslated. Retrying with strict translation prompt.")
                            return true
                        }
                        return false
                    },
                    strictTranslate: { [weak self] value, targetLanguage in
                        guard let self else { return value }
                        return try await self.translateTextStrict(value, targetLanguage: targetLanguage)
                    }
                )
            )
        }

        let runner = SessionPipelineRunner(stages: stages)
        let initial = SessionPipelineContext(originalText: text, workingText: text)
        let result = try await runner.run(initial: initial)
        return result.workingText
    }

    private func runRewritePipeline(
        dictatedText: String,
        selectedSourceText: String,
        conversationHistory: [RewriteConversationPromptTurn],
        structuredAnswerOutput: Bool,
        previousConversationResponseID: String? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil,
        onResponseID: ((String) -> Void)? = nil
    ) async throws -> String {
        let stages: [any SessionPipelineStage] = [
            RewriteStage(
                sourceText: selectedSourceText,
                transform: { [weak self] dictatedPrompt, sourceText in
                    guard let self else { return dictatedPrompt }
                    return try await self.rewriteText(
                        dictatedPrompt: dictatedPrompt,
                        sourceText: sourceText,
                        conversationHistory: conversationHistory,
                        structuredAnswerOutput: structuredAnswerOutput,
                        previousConversationResponseID: previousConversationResponseID,
                        onProgress: onProgress,
                        onResponseID: onResponseID
                    )
                }
            )
        ]

        let runner = SessionPipelineRunner(stages: stages)
        let initial = SessionPipelineContext(originalText: dictatedText, workingText: dictatedText)
        let result = try await runner.run(initial: initial)
        return result.workingText
    }

    private func presentRewriteConversationPseudoStreamingPreview(
        content: String,
        sessionID: UUID
    ) async {
        let normalized = RewriteAnswerContentNormalizer.normalizePlainTextAnswer(content)
        guard !normalized.isEmpty else { return }

        // Large answers should appear immediately; dozens of staged updates stall the
        // overlay and spinner on the main thread without adding useful feedback.
        guard normalized.count < 360 else {
            guard shouldHandleCallbacks(for: sessionID) else { return }
            presentRewriteConversationStreamingPreview(content: normalized)
            return
        }

        let characters = Array(normalized)
        let stageCount = min(4, max(2, Int(ceil(Double(characters.count) / 96.0))))
        let chunkSize = max(24, Int(ceil(Double(characters.count) / Double(stageCount))))

        var rendered = ""
        var index = 0
        while index < characters.count {
            guard shouldHandleCallbacks(for: sessionID) else { return }
            let upperBound = min(index + chunkSize, characters.count)
            rendered += String(characters[index..<upperBound])
            presentRewriteConversationStreamingPreview(content: rendered)
            index = upperBound
            guard index < characters.count else { continue }
            do {
                try await Task.sleep(for: .milliseconds(45))
            } catch {
                return
            }
        }
    }

    private func looksUntranslated(source: String, result: String) -> Bool {
        let sourceTrimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultTrimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceTrimmed.isEmpty, !resultTrimmed.isEmpty else { return false }
        return sourceTrimmed.caseInsensitiveCompare(resultTrimmed) == .orderedSame
    }
}

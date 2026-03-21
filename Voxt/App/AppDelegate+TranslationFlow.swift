import Foundation

extension AppDelegate {
    private struct EnhanceStage: SessionPipelineStage {
        let useAppBranchPrompt: Bool
        let transform: @MainActor (String, Bool) async throws -> String

        var name: String { "enhance" }

        func run(context: SessionPipelineContext) async throws -> SessionPipelineContext {
            var next = context
            next.workingText = try await transform(context.workingText, useAppBranchPrompt)
            return next
        }
    }

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

    func processTranslatedTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        let resolution = resolvedTranslationProviderResolution(isSelectedTextTranslation: false)
        VoxtLog.info(
            "Translation flow started. inputChars=\(text.count), targetLanguage=\(translationTargetLanguage.instructionName), enhancementMode=\(enhancementMode.rawValue), provider=\(resolution.provider.rawValue)"
        )
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
                if self.shouldHandleCallbacks(for: sessionID) {
                    self.finishSession()
                }
            }

            let llmStartedAt = Date()
            do {
                // Translation mode pipeline: enhance -> translate.
                let translated = try await self.runTranslationPipeline(
                    text: text,
                    targetLanguage: self.translationTargetLanguage,
                    includeEnhancement: true,
                    allowStrictRetry: false
                )
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Translation output may be untranslated. sourceChars=\(text.count), outputChars=\(translated.count)")
                }
                VoxtLog.info("Translation flow succeeded. outputChars=\(translated.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.commitTranscription(translated, llmDurationSeconds: llmDuration)
            } catch {
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                VoxtLog.warning("Translation flow failed, using raw text: \(error)")
                self.commitTranscription(text, llmDurationSeconds: nil)
            }
        }
    }

    func processWhisperTranslatedTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        VoxtLog.info("Whisper direct translation completed. outputChars=\(text.count)")
        commitTranscription(text, llmDurationSeconds: nil)
        finishSession()
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
        overlayState.reset()
        overlayState.transcribedText = selectedText
        overlayState.statusMessage = ""
        overlayState.presentRecording(iconMode: .translation)
        overlayWindow.show(state: overlayState, position: overlayPosition)

        let startedAt = Date()
        isSessionActive = true
        isSelectedTextTranslationFlow = true
        didCommitSessionOutput = false
        isSessionCancellationRequested = false
        activeRecordingSessionID = UUID()
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
        let selectedSourceText = selectedTextFromSystemSelection()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        rewriteSessionHasSelectedSourceText = !selectedSourceText.isEmpty
        let prefersStructuredAnswerOutput = shouldPresentRewriteAnswerOverlay(
            hasSelectedSourceText: rewriteSessionHasSelectedSourceText
        )
        VoxtLog.info(
            "Rewrite flow started. promptChars=\(text.count), selectedSourceChars=\(selectedSourceText.count), enhancementMode=\(enhancementMode.rawValue), structuredAnswerOutput=\(prefersStructuredAnswerOutput)"
        )
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
                if self.shouldHandleCallbacks(for: sessionID) {
                    self.finishSession()
                }
            }

            let llmStartedAt = Date()
            do {
                var rewritten = try await self.runRewritePipeline(
                    dictatedText: text,
                    selectedSourceText: selectedSourceText,
                    structuredAnswerOutput: prefersStructuredAnswerOutput
                )
                if prefersStructuredAnswerOutput,
                   self.shouldRetryStructuredRewriteAnswer(for: rewritten) {
                    VoxtLog.warning("Rewrite structured answer was missing usable content; retrying in direct-answer mode.")
                    if let retried = try? await self.rewriteText(
                        dictatedPrompt: text,
                        sourceText: "",
                        structuredAnswerOutput: true,
                        forceNonEmptyAnswer: true
                    ) {
                        rewritten = retried
                    }
                }
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                VoxtLog.info("Rewrite flow succeeded. outputChars=\(rewritten.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.commitTranscription(rewritten, llmDurationSeconds: llmDuration)
            } catch {
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                VoxtLog.warning("Rewrite flow failed, using enhanced prompt fallback: \(error)")
                let fallback = (try? await self.enhanceTextIfNeeded(text, useAppBranchPrompt: true)) ?? text
                self.commitTranscription(fallback, llmDurationSeconds: nil)
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

    private func enhanceTextIfNeeded(_ text: String, useAppBranchPrompt: Bool = true) async throws -> String {
        let promptResolution: EnhancementPromptResolution
        if useAppBranchPrompt {
            promptResolution = resolvedEnhancementPrompt(rawTranscription: text)
        } else {
            promptResolution = EnhancementPromptResolution(
                content: resolveGlobalEnhancementPromptTemplate(
                    resolvedGlobalEnhancementPrompt(),
                    rawTranscription: text
                ),
                delivery: .systemPrompt
            )
        }
        if !useAppBranchPrompt {
            VoxtLog.info("Enhancement prompt source: global/default (translation flow)")
        }

        switch enhancementMode {
        case .off:
            return text
        case .appleIntelligence:
            guard let enhancer else { return text }
            if #available(macOS 26.0, *) {
                switch promptResolution.delivery {
                case .systemPrompt:
                    return try await enhancer.enhance(text, systemPrompt: promptResolution.content)
                case .userMessage:
                    return try await enhancer.enhance(userPrompt: promptResolution.content)
                }
            }
            return text
        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo) else { return text }
            switch promptResolution.delivery {
            case .systemPrompt:
                return try await customLLMManager.enhance(text, systemPrompt: promptResolution.content)
            case .userMessage:
                return try await customLLMManager.enhance(userPrompt: promptResolution.content)
            }
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: false)
            switch promptResolution.delivery {
            case .systemPrompt:
                return try await RemoteLLMRuntimeClient().enhance(
                    text: text,
                    systemPrompt: promptResolution.content,
                    provider: context.provider,
                    configuration: context.configuration
                )
            case .userMessage:
                return try await RemoteLLMRuntimeClient().enhance(userPrompt: promptResolution.content, provider: context.provider, configuration: context.configuration)
            }
        }
    }

    private func translateText(_ text: String, targetLanguage: TranslationTargetLanguage) async throws -> String {
        let resolvedPrompt = resolvedTranslationPrompt(
            targetLanguage: targetLanguage,
            sourceText: text,
            strict: false
        )
        let translationRepo = translationCustomLLMRepo
        let resolution = resolvedTranslationProviderResolution(isSelectedTextTranslation: isSelectedTextTranslationFlow)
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
        structuredAnswerOutput: Bool,
        forceNonEmptyAnswer: Bool = false
    ) async throws -> String {
        let directAnswerMode = structuredAnswerOutput && sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let resolvedPrompt = resolvedRewritePrompt(
            dictatedPrompt: dictatedPrompt,
            sourceText: sourceText,
            structuredAnswerOutput: structuredAnswerOutput,
            directAnswerMode: directAnswerMode,
            forceNonEmptyAnswer: forceNonEmptyAnswer
        )
        let rewriteRepo = rewriteCustomLLMRepo
        let modelProvider = rewriteModelProvider
        VoxtLog.llm(
            "Rewrite request. promptChars=\(resolvedPrompt.count), dictatedChars=\(dictatedPrompt.count), sourceChars=\(sourceText.count), provider=\(modelProvider.rawValue), rewriteRepo=\(rewriteRepo), structuredAnswerOutput=\(structuredAnswerOutput), directAnswerMode=\(directAnswerMode), forceNonEmptyAnswer=\(forceNonEmptyAnswer)"
        )

        switch modelProvider {
        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: rewriteRepo) else {
                VoxtLog.warning("Rewrite provider customLLM unavailable: model not downloaded. repo=\(rewriteRepo)")
                showOverlayStatus(
                    String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
                return dictatedPrompt
            }
            return try await customLLMManager.rewrite(
                sourceText: sourceText,
                dictatedPrompt: dictatedPrompt,
                systemPrompt: resolvedPrompt,
                modelRepo: rewriteRepo
            )
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forRewrite: true)
            guard context.configuration.hasUsableModel else {
                VoxtLog.warning("Rewrite provider remoteLLM unavailable: no configured model.")
                showOverlayStatus(
                    String(localized: "No configured remote LLM model yet. Configure a provider in Settings > Model."),
                    clearAfter: 2.5
                )
                return dictatedPrompt
            }
            return try await RemoteLLMRuntimeClient().rewrite(
                sourceText: sourceText,
                dictatedPrompt: dictatedPrompt,
                systemPrompt: resolvedPrompt,
                provider: context.provider,
                configuration: context.configuration
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
        let resolution = resolvedTranslationProviderResolution(isSelectedTextTranslation: isSelectedTextTranslationFlow)
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

    private func resolvedTranslationProviderResolution(isSelectedTextTranslation: Bool) -> TranslationProviderResolution {
        TranslationProviderResolver.resolve(
            selectedProvider: translationModelProvider,
            fallbackProvider: translationFallbackModelProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: translationTargetLanguage,
            isSelectedTextTranslation: isSelectedTextTranslation,
            whisperModelState: whisperModelManager.state
        )
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
        structuredAnswerOutput: Bool,
        directAnswerMode: Bool,
        forceNonEmptyAnswer: Bool
    ) -> String {
        let resolved = RewritePromptBuilder.build(
            systemPrompt: rewriteSystemPrompt,
            dictatedPrompt: dictatedPrompt,
            sourceText: sourceText,
            structuredAnswerOutput: structuredAnswerOutput,
            directAnswerMode: directAnswerMode,
            forceNonEmptyAnswer: forceNonEmptyAnswer
        )
        return appendDictionaryRewriteGlossary(
            to: resolved,
            sourceText: "\(dictatedPrompt)\n\(sourceText)"
        )
    }

    private func shouldRetryStructuredRewriteAnswer(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if let payload = extractRewriteAnswerPayload(from: trimmed) {
            return payload.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func processSelectedTextTranslation(_ text: String) {
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
                self.isSelectedTextTranslationFlow = false
                self.finishSession()
            }

            let llmStartedAt = Date()
            do {
                let translated = try await self.runTranslationPipeline(
                    text: text,
                    targetLanguage: self.translationTargetLanguage,
                    includeEnhancement: false,
                    allowStrictRetry: true
                )
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Selected text translation output may be untranslated. inputChars=\(text.count), outputChars=\(translated.count)")
                }
                VoxtLog.info("Selected text translation succeeded. outputChars=\(translated.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.overlayState.transcribedText = translated
                self.commitTranscription(translated, llmDurationSeconds: llmDuration)
            } catch {
                VoxtLog.warning("Selected text translation failed, using original selected text: \(error)")
                self.overlayState.transcribedText = text
                self.commitTranscription(text, llmDurationSeconds: nil)
            }
        }
    }

    private func runTranslationPipeline(
        text: String,
        targetLanguage: TranslationTargetLanguage,
        includeEnhancement: Bool,
        allowStrictRetry: Bool
    ) async throws -> String {
        var stages: [any SessionPipelineStage] = []

        if includeEnhancement {
            stages.append(
                EnhanceStage(
                    useAppBranchPrompt: true,
                    transform: { [weak self] value, useAppBranchPrompt in
                        guard let self else { return value }
                        return try await self.enhanceTextIfNeeded(value, useAppBranchPrompt: useAppBranchPrompt)
                    }
                )
            )
        }

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
        structuredAnswerOutput: Bool
    ) async throws -> String {
        let stages: [any SessionPipelineStage] = [
            EnhanceStage(
                useAppBranchPrompt: true,
                transform: { [weak self] value, useAppBranchPrompt in
                    guard let self else { return value }
                    return try await self.enhanceTextIfNeeded(value, useAppBranchPrompt: useAppBranchPrompt)
                }
            ),
            RewriteStage(
                sourceText: selectedSourceText,
                transform: { [weak self] enhancedPrompt, sourceText in
                    guard let self else { return enhancedPrompt }
                    return try await self.rewriteText(
                        dictatedPrompt: enhancedPrompt,
                        sourceText: sourceText,
                        structuredAnswerOutput: structuredAnswerOutput
                    )
                }
            )
        ]

        let runner = SessionPipelineRunner(stages: stages)
        let initial = SessionPipelineContext(originalText: dictatedText, workingText: dictatedText)
        let result = try await runner.run(initial: initial)
        return result.workingText
    }

    private func looksUntranslated(source: String, result: String) -> Bool {
        let sourceTrimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultTrimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceTrimmed.isEmpty, !resultTrimmed.isEmpty else { return false }
        return sourceTrimmed.caseInsensitiveCompare(resultTrimmed) == .orderedSame
    }
}

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

    func processTranslatedTranscription(_ text: String) {
        VoxtLog.info(
            "Translation flow started. inputChars=\(text.count), targetLanguage=\(translationTargetLanguage.instructionName), enhancementMode=\(enhancementMode.rawValue)"
        )
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
                self.finishSession()
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
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Translation output may be untranslated. sourceChars=\(text.count), outputChars=\(translated.count)")
                }
                VoxtLog.info("Translation flow succeeded. outputChars=\(translated.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.commitTranscription(translated, llmDurationSeconds: llmDuration)
            } catch {
                VoxtLog.warning("Translation flow failed, using raw text: \(error)")
                self.commitTranscription(text, llmDurationSeconds: nil)
            }
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
        overlayState.reset()
        overlayState.transcribedText = selectedText
        overlayState.statusMessage = ""
        overlayWindow.show(state: overlayState, position: overlayPosition)

        let startedAt = Date()
        isSessionActive = true
        isSelectedTextTranslationFlow = true
        didCommitSessionOutput = false
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

    private func enhanceTextIfNeeded(_ text: String, useAppBranchPrompt: Bool = true) async throws -> String {
        let prompt = useAppBranchPrompt ? resolvedEnhancementPrompt() : resolvedGlobalEnhancementPrompt()
        if !useAppBranchPrompt {
            VoxtLog.info("Enhancement prompt source: global/default (translation flow)")
        }

        switch enhancementMode {
        case .off:
            return text
        case .appleIntelligence:
            guard let enhancer else { return text }
            if #available(macOS 26.0, *) {
                return try await enhancer.enhance(text, systemPrompt: prompt)
            }
            return text
        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo) else { return text }
            return try await customLLMManager.enhance(text, systemPrompt: prompt)
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: false)
            return try await RemoteLLMRuntimeClient().enhance(
                text: text,
                systemPrompt: prompt,
                provider: context.provider,
                configuration: context.configuration
            )
        }
    }

    private func translateText(_ text: String, targetLanguage: TranslationTargetLanguage) async throws -> String {
        let resolvedPrompt = resolvedTranslationPrompt(targetLanguage: targetLanguage, strict: false)
        let translationRepo = translationCustomLLMRepo
        let modelProvider = translationModelProvider
        VoxtLog.info(
            "Translation request. promptChars=\(resolvedPrompt.count), inputChars=\(text.count), provider=\(modelProvider.rawValue), translationRepo=\(translationRepo)"
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
        }
    }

    private func translateTextStrict(_ text: String, targetLanguage: TranslationTargetLanguage) async throws -> String {
        let strictPrompt = resolvedTranslationPrompt(targetLanguage: targetLanguage, strict: true)
        let translationRepo = translationCustomLLMRepo
        let modelProvider = translationModelProvider
        VoxtLog.info(
            "Strict translation retry. promptChars=\(strictPrompt.count), inputChars=\(text.count), provider=\(modelProvider.rawValue), translationRepo=\(translationRepo)"
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
        }
    }

    private func resolvedTranslationPrompt(targetLanguage: TranslationTargetLanguage, strict: Bool) -> String {
        let basePrompt = translationSystemPrompt.replacingOccurrences(
            of: "{target_language}",
            with: targetLanguage.instructionName
        )

        let enforcement = strict
            ? """
            Mandatory translation rules:
            - Translate every linguistic token into \(targetLanguage.instructionName), including very short text (1-3 characters).
            - Output must not copy source-language wording.
            - Keep proper nouns, product names, URLs, emails, and pure numbers/symbols unchanged when needed.
            - Do not add explanations, quotes, or markdown.
            - Return only the translated text.
            """
            : """
            Mandatory translation rules:
            - Translate to \(targetLanguage.instructionName).
            - Keep meaning, tone, names, numbers, and formatting.
            - For short text, still translate when it is linguistic content.
            - Do not output explanations.
            - Return only the translated text.
            """
        return "\(basePrompt)\n\(enforcement)"
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

    private func looksUntranslated(source: String, result: String) -> Bool {
        let sourceTrimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultTrimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceTrimmed.isEmpty, !resultTrimmed.isEmpty else { return false }
        return sourceTrimmed.caseInsensitiveCompare(resultTrimmed) == .orderedSame
    }
}

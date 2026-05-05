import Foundation

extension AppDelegate {
    private struct TranscriptionEnhanceStage: SessionPipelineStage {
        let transform: @MainActor (String) async throws -> String

        var name: String { "transcriptionEnhance" }

        func run(context: SessionPipelineContext) async throws -> SessionPipelineContext {
            var next = context
            next.workingText = try await transform(context.workingText)
            return next
        }
    }

    // MARK: - Standard Transcription Flow

    func processStandardTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        VoxtLog.info("Standard transcription flow entered. characters=\(text.count), enhancementMode=\(enhancementMode.rawValue)", verbose: true)
        switch enhancementMode {
        case .off:
            setEnhancingState(false)
            overlayState.transcribedText = text
            VoxtLog.info("Standard transcription committing raw text immediately. characters=\(text.count)", verbose: true)
            commitTranscription(text, llmDurationSeconds: nil) { [weak self] in
                self?.finishSession(after: 0)
            }

        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo) else {
                VoxtLog.warning("Custom LLM selected but local model is not installed. Using raw transcription.")
                showOverlayStatus(
                    String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
                setEnhancingState(false)
                overlayState.transcribedText = text
                VoxtLog.info("Standard transcription falling back to raw text because custom model is unavailable. characters=\(text.count)", verbose: true)
                commitTranscription(text, llmDurationSeconds: nil) { [weak self] in
                    self?.finishSession(after: 0)
                }
                return
            }
            runStandardTranscriptionPipelineAsync(text, sessionID: sessionID)

        case .appleIntelligence, .remoteLLM:
            runStandardTranscriptionPipelineAsync(text, sessionID: sessionID)
        }
    }

    private func runStandardTranscriptionPipelineAsync(_ text: String, sessionID: UUID) {
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
            }

            let llmStartedAt = Date()
            if let asrAt = self.transcriptionResultReceivedAt {
                let handoffMs = Int(llmStartedAt.timeIntervalSince(asrAt) * 1000)
                VoxtLog.info("Enhancement handoff. mode=\(self.enhancementMode.rawValue), handoffMs=\(max(handoffMs, 0)), inputChars=\(text.count)", verbose: true)
            } else {
                VoxtLog.info("Enhancement handoff. mode=\(self.enhancementMode.rawValue), handoffMs=unknown, inputChars=\(text.count)", verbose: true)
            }
            do {
                let enhanced = try await self.runStandardTranscriptionPipeline(text: text)
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                VoxtLog.info("Enhancement completed. mode=\(self.enhancementMode.rawValue), inputChars=\(text.count), outputChars=\(enhanced.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.overlayState.transcribedText = enhanced
                self.commitTranscription(enhanced, llmDurationSeconds: llmDuration) { [weak self] in
                    self?.finishSession(after: 0)
                }
            } catch {
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                VoxtLog.warning("Standard transcription pipeline enhancement failed, using raw text: \(error)")
                self.overlayState.transcribedText = text
                self.commitTranscription(text, llmDurationSeconds: nil) { [weak self] in
                    self?.finishSession(after: 0)
                }
            }
        }
    }

    private func runStandardTranscriptionPipeline(text: String) async throws -> String {
        let sessionID = activeRecordingSessionID
        let runner = SessionPipelineRunner(
            stages: [
                TranscriptionEnhanceStage(transform: { [weak self] value in
                    guard let self else { return value }
                    return try await self.enhanceTextForCurrentMode(value, sessionID: sessionID)
                })
            ]
        )
        let result = try await runner.run(initial: SessionPipelineContext(originalText: text, workingText: text))
        return result.workingText
    }

    func enhanceTextForCurrentMode(_ text: String, sessionID: UUID? = nil) async throws -> String {
        let promptResolution = resolvedEnhancementPrompt(rawTranscription: text)
        if promptResolution.delivery == .skipEnhancement {
            return text
        }
        if let sessionID {
            applyEnhancementOverlayIconIfNeeded(match: promptResolution.overlayIconMatch, sessionID: sessionID)
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
                case .skipEnhancement:
                    return text
                }
            }
            return text
        case .customLLM:
            switch promptResolution.delivery {
            case .systemPrompt:
                return try await customLLMManager.enhance(text, systemPrompt: promptResolution.content)
            case .userMessage:
                return try await customLLMManager.enhance(userPrompt: promptResolution.content)
            case .skipEnhancement:
                return text
            }
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: false)
                VoxtLog.llm(
                    "Remote LLM enhancement request. provider=\(context.provider.rawValue), model=\(context.configuration.model)"
                )
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
            case .skipEnhancement:
                return text
            }
        }
    }
}

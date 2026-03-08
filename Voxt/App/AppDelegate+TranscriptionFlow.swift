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

    func processStandardTranscription(_ text: String) {
        switch enhancementMode {
        case .off:
            setEnhancingState(false)
            commitTranscription(text, llmDurationSeconds: nil)
            finishSession()

        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo) else {
                VoxtLog.warning("Custom LLM selected but local model is not installed. Using raw transcription.")
                showOverlayStatus(
                    String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
                setEnhancingState(false)
                commitTranscription(text, llmDurationSeconds: nil)
                finishSession()
                return
            }
            runStandardTranscriptionPipelineAsync(text)

        case .appleIntelligence, .remoteLLM:
            runStandardTranscriptionPipelineAsync(text)
        }
    }

    private func runStandardTranscriptionPipelineAsync(_ text: String) {
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
                self.finishSession()
            }

            let llmStartedAt = Date()
            if let asrAt = self.transcriptionResultReceivedAt {
                let handoffMs = Int(llmStartedAt.timeIntervalSince(asrAt) * 1000)
                VoxtLog.info("Enhancement handoff. mode=\(self.enhancementMode.rawValue), handoffMs=\(max(handoffMs, 0)), inputChars=\(text.count)")
            } else {
                VoxtLog.info("Enhancement handoff. mode=\(self.enhancementMode.rawValue), handoffMs=unknown, inputChars=\(text.count)")
            }
            do {
                let enhanced = try await self.runStandardTranscriptionPipeline(text: text)
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                VoxtLog.info("Enhancement completed. mode=\(self.enhancementMode.rawValue), inputChars=\(text.count), outputChars=\(enhanced.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.commitTranscription(enhanced, llmDurationSeconds: llmDuration)
            } catch {
                VoxtLog.warning("Standard transcription pipeline enhancement failed, using raw text: \(error)")
                self.commitTranscription(text, llmDurationSeconds: nil)
            }
        }
    }

    private func runStandardTranscriptionPipeline(text: String) async throws -> String {
        let runner = SessionPipelineRunner(
            stages: [
                TranscriptionEnhanceStage(transform: { [weak self] value in
                    guard let self else { return value }
                    return try await self.enhanceTextForCurrentMode(value)
                })
            ]
        )
        let result = try await runner.run(initial: SessionPipelineContext(originalText: text, workingText: text))
        return result.workingText
    }

    func enhanceTextForCurrentMode(_ text: String) async throws -> String {
        let prompt = resolvedEnhancementPrompt()

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
            return try await customLLMManager.enhance(text, systemPrompt: prompt)
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: false)
            VoxtLog.info(
                "Remote LLM enhancement request. provider=\(context.provider.rawValue), model=\(context.configuration.model)"
            )
            return try await RemoteLLMRuntimeClient().enhance(
                text: text,
                systemPrompt: prompt,
                provider: context.provider,
                configuration: context.configuration
            )
        }
    }
}

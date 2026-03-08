import Foundation

extension AppDelegate {
    private struct PauseEnhanceStage: SessionPipelineStage {
        let transform: @MainActor (String) async throws -> String

        var name: String { "pauseEnhance" }

        func run(context: SessionPipelineContext) async throws -> SessionPipelineContext {
            var next = context
            next.workingText = try await transform(context.workingText)
            return next
        }
    }

    // MARK: - Pause Enhancement Flow

    func runPauseEnhancementIfNeeded() {
        guard enhancementMode != .off else { return }
        let input = overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        pauseLLMTask?.cancel()
        pauseLLMTask = Task { [weak self] in
            guard let self else { return }
            self.setEnhancingState(true)
            defer {
                self.setEnhancingState(false)
                self.pauseLLMTask = nil
            }

            do {
                let enhanced = try await self.runPauseEnhancementPipeline(input: input)
                guard !Task.isCancelled else { return }
                guard self.isSessionActive else { return }

                // Apply only if text has not moved forward during pause.
                let current = self.overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard current == input else { return }

                self.mlxTranscriber?.transcribedText = enhanced
                self.remoteASRTranscriber.transcribedText = enhanced
                self.speechTranscriber.transcribedText = enhanced
            } catch {
                VoxtLog.warning("Pause-time LLM enhancement skipped: \(error)")
            }
        }
    }

    private func runPauseEnhancementPipeline(input: String) async throws -> String {
        let runner = SessionPipelineRunner(
            stages: [
                PauseEnhanceStage(transform: { [weak self] value in
                    guard let self else { return value }
                    return try await self.enhanceTextForCurrentMode(value)
                })
            ]
        )
        let result = try await runner.run(initial: SessionPipelineContext(originalText: input, workingText: input))
        return result.workingText
    }
}

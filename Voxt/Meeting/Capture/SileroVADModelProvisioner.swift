// SileroVADModelProvisioner.swift
// Provisions the single supported Silero VAD checkpoint on demand.

import Foundation
import MLXAudioVAD

@MainActor
final class SileroVADModelProvisioner {
    static let shared = SileroVADModelProvisioner()

    private let modelManager = MLXModelManager(modelRepo: SileroVADModelSupport.repo)
    private var inFlightTask: Task<URL, Error>?

    nonisolated static func prefetchIfNeeded(for mode: LocalVADMode) {
        guard ASRVoiceActivityRuntimePolicy.requiresSileroModel(mode: mode) else { return }
        Task {
            do {
                _ = try await shared.ensureModelDirectory()
            } catch is CancellationError {
                return
            } catch {
                VoxtLog.modelWarning(
                    "Automatic Silero VAD download failed. repo=\(SileroVADModelSupport.repo), error=\(error.localizedDescription)"
                )
            }
        }
    }

    func ensureModelDirectory() async throws -> URL {
        if let directory = MeetingVADModelStorage.modelDirectory(requireValid: true) {
            return directory
        }
        if let inFlightTask {
            return try await inFlightTask.value
        }

        let repo = SileroVADModelSupport.repo
        let task = Task { @MainActor [modelManager] in
            let directory = try await modelManager.ensureModelDirectory(repo: repo)
            try Task.checkCancellation()
            _ = try SileroVAD.fromModelDirectory(directory)
            return directory
        }
        inFlightTask = task
        defer { inFlightTask = nil }

        let directory = try await task.value
        VoxtLog.modelInfo("Automatic Silero VAD download complete. repo=\(repo)")
        return directory
    }
}

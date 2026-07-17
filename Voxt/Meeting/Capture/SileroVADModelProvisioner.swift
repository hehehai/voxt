// SileroVADModelProvisioner.swift
// Provisions the single supported Silero VAD checkpoint on demand.

import Foundation
import MLXAudioVAD

@MainActor
final class SileroVADModelProvisioner {
    static let shared = SileroVADModelProvisioner()

    private let modelManager = MLXModelManager(modelRepo: SileroVADModelSupport.repo)
    private var inFlightTask: Task<URL, Error>?
    private var prefetchTask: Task<Void, Never>?
    private var isShuttingDownForApplicationTermination = false

    static func prefetchIfNeeded(for mode: LocalVADMode) {
        guard ASRVoiceActivityRuntimePolicy.requiresSileroModel(mode: mode) else { return }
        shared.startPrefetchIfNeeded()
    }

    private func startPrefetchIfNeeded() {
        guard !isShuttingDownForApplicationTermination, prefetchTask == nil else { return }
        prefetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.prefetchTask = nil }
            do {
                _ = try await self.ensureModelDirectory()
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
        guard !isShuttingDownForApplicationTermination else { throw CancellationError() }
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

    func shutdownForApplicationTermination() async {
        guard !isShuttingDownForApplicationTermination else { return }
        isShuttingDownForApplicationTermination = true
        let prefetchTask = prefetchTask
        let inFlightTask = inFlightTask
        prefetchTask?.cancel()
        inFlightTask?.cancel()
        await prefetchTask?.value
        _ = try? await inFlightTask?.value
        self.prefetchTask = nil
        self.inFlightTask = nil
        await modelManager.shutdownForApplicationTermination()
    }
}

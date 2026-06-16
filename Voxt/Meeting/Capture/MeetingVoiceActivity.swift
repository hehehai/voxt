// MeetingVoiceActivity.swift
// Provides Meeting Voice Activity for meeting capture.

import Foundation
import HuggingFace
import MLX
import MLXAudioVAD

struct MeetingVoiceActivityDecision: Equatable, Sendable {
    let isSpeech: Bool
    let probability: Float?
    let source: Source

    enum Source: Equatable, Sendable {
        case energy
        case silero
        case fallbackEnergy
    }
}

actor MeetingVoiceActivityDetector {
    private static let sileroBalancedThreshold: Float = 0.5

    private var sileroDetector = MeetingSileroStreamingDetector()
    private var sileroFallbackWarningLogged = false

    func refreshFromPreferences() async {
        sileroFallbackWarningLogged = false
    }

    func reset() async {
        await sileroDetector.reset()
        sileroFallbackWarningLogged = false
    }

    func activity(
        samples: [Float],
        sampleRate: Double,
        speaker: MeetingSpeaker,
        fallbackLevel: Float,
        fallbackThreshold: Float
    ) async -> MeetingVoiceActivityDecision {
        let fallback = MeetingVoiceActivityDecision(
            isSpeech: fallbackLevel >= fallbackThreshold,
            probability: nil,
            source: .energy
        )
        do {
            if let probability = try await sileroDetector.probability(
                samples: samples,
                sampleRate: sampleRate,
                speaker: speaker
            ) {
                return MeetingVoiceActivityDecision(
                    isSpeech: probability >= Self.sileroBalancedThreshold,
                    probability: probability,
                    source: .silero
                )
            }
        } catch {
            if shouldLogSileroFallback(error) {
                VoxtLog.meetingWarning("Meeting Silero VAD failed; falling back to energy VAD. error=\(error.localizedDescription)")
                sileroFallbackWarningLogged = true
            }
            await sileroDetector.reset()
        }

        return MeetingVoiceActivityDecision(
            isSpeech: fallback.isSpeech,
            probability: nil,
            source: .fallbackEnergy
        )
    }

    private func shouldLogSileroFallback(_ error: Error) -> Bool {
        if let modelError = error as? MeetingVADModelError {
            switch modelError {
            case .modelNotDownloaded, .runtimeUnavailable:
                return false
            }
        }
        return !sileroFallbackWarningLogged
    }
}

private actor MeetingSileroStreamingDetector {
    private let sampleRate = 16_000
    private let chunkSize = 512
    private var model: SileroVAD?
    private var states: [MeetingSpeaker: SileroVADStreamingState] = [:]
    private var pendingSamples: [MeetingSpeaker: [Float]] = [:]
    private var lastProbabilities: [MeetingSpeaker: Float] = [:]

    func reset() {
        states.removeAll()
        pendingSamples.removeAll()
        lastProbabilities.removeAll()
    }

    func probability(
        samples: [Float],
        sampleRate inputSampleRate: Double,
        speaker: MeetingSpeaker
    ) async throws -> Float? {
        guard !samples.isEmpty else { return nil }
        let model = try await loadModelIfAvailable()
        let prepared = MeetingAudioSampleRateConverter.resample(
            samples: samples,
            from: inputSampleRate,
            to: Double(sampleRate)
        )
        guard !prepared.isEmpty else { return lastProbabilities[speaker] }

        var pending = pendingSamples[speaker] ?? []
        pending.append(contentsOf: prepared)
        var latestProbability: Float?

        while pending.count >= chunkSize {
            let chunk = Array(pending.prefix(chunkSize))
            pending.removeFirst(chunkSize)
            let state = states[speaker]
            let (probabilityArray, nextState) = try model.feed(
                chunk: MLXArray(chunk),
                state: state,
                sampleRate: sampleRate
            )
            eval(probabilityArray)
            if let probability = probabilityArray.asArray(Float.self).first {
                latestProbability = probability
            }
            states[speaker] = nextState
        }

        pendingSamples[speaker] = pending
        if let latestProbability {
            lastProbabilities[speaker] = latestProbability
            return latestProbability
        }
        return nil
    }

    private func loadModelIfAvailable() async throws -> SileroVAD {
        if let model {
            return model
        }
        let directory = await MainActor.run {
            MeetingVADModelStorage.modelDirectory(requireValid: true)
        }
        guard let directory else {
            throw MeetingVADModelError.modelNotDownloaded
        }
        let loaded = try SileroVAD.fromModelDirectory(directory)
        model = loaded
        return loaded
    }
}

enum MeetingVADModelError: LocalizedError {
    case modelNotDownloaded
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return AppLocalization.localizedString("VAD model is not downloaded.")
        case .runtimeUnavailable(let detail):
            return detail
        }
    }
}

enum MeetingVADModelStorage {
    static let sileroRepo = "mlx-community/silero-vad"
    static let sortformerV2Repo = "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
    static let fallbackRemoteSizeText = "2 MB"
    static let sortformerFallbackRemoteSizeText = "120 MB"

    static let repo = sileroRepo

    static func modelDirectory(requireValid: Bool) -> URL? {
        for rootDirectory in ModelStorageDirectoryManager.resolvedReadableRootURLs() {
            guard let directory = MLXModelStorageSupport.cacheDirectory(
                for: repo,
                rootDirectory: rootDirectory
            ),
                  FileManager.default.fileExists(atPath: directory.path)
            else {
                continue
            }
            if requireValid && !isValidModelDirectory(directory) {
                continue
            }
            return directory
        }
        return nil
    }

    static func writeModelDirectory() -> URL? {
        return MLXModelStorageSupport.cacheDirectory(
            for: repo,
            rootDirectory: ModelStorageDirectoryManager.resolvedWriteRootURL()
        )
    }

    static func downloadTempDirectory() -> URL? {
        guard let repoID = Repo.ID(rawValue: repo) else { return nil }
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        return ModelStorageDirectoryManager.resolvedWriteRootURL()
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent("\(modelSubdir)-download", isDirectory: true)
    }

    nonisolated static func isValidModelDirectory(_ directory: URL, fileManager: FileManager = .default) -> Bool {
        isValidSileroModelDirectory(directory, fileManager: fileManager)
    }

    nonisolated private static func isValidSileroModelDirectory(_ directory: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
            return false
        }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return entries.contains { $0.pathExtension == "safetensors" }
    }

    static func clearHubCache(rootDirectory: URL = ModelStorageDirectoryManager.resolvedWriteRootURL()) {
        guard let repoID = Repo.ID(rawValue: repo) else { return }
        MLXModelStorageSupport.clearHubCache(for: repoID, rootDirectory: rootDirectory)
    }
}

enum MeetingAudioSampleRateConverter {
    nonisolated static func resample(samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard !samples.isEmpty, inputRate > 0, outputRate > 0 else { return samples }
        if abs(inputRate - outputRate) <= 1 {
            return samples
        }

        let ratio = outputRate / inputRate
        let outputCount = max(Int(Double(samples.count) * ratio), 1)
        var output = [Float](repeating: 0, count: outputCount)

        for index in 0..<outputCount {
            let position = Double(index) / ratio
            let lowerIndex = min(Int(position), samples.count - 1)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(position - Double(lowerIndex))
            let lower = samples[lowerIndex]
            let upper = samples[upperIndex]
            output[index] = lower + (upper - lower) * fraction
        }

        return output
    }
}

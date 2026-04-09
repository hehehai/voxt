import Foundation
import WhisperKit
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioSTT

protocol MeetingSegmentTranscribing {
    func transcribe(chunk: BufferedMeetingChunk) async -> MeetingTranscriptSegment?
    func cancelPendingWork() async
}

extension MeetingSegmentTranscribing {
    func cancelPendingWork() async {}
}

actor MeetingRemoteTranscriptionGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isBusy = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}

@MainActor
final class MeetingWhisperSegmentTranscriber: MeetingSegmentTranscribing {
    private static let minimumChunkRMS: Float = 0.003

    private let whisper: WhisperKit
    private let mainLanguage: UserMainLanguageOption
    private let temperature: Float
    private let hintPayload: ResolvedASRHintPayload
    private let targetSampleRate = Double(WhisperKit.sampleRate)

    init(
        whisper: WhisperKit,
        mainLanguage: UserMainLanguageOption,
        temperature: Float,
        hintPayload: ResolvedASRHintPayload
    ) {
        self.whisper = whisper
        self.mainLanguage = mainLanguage
        self.temperature = temperature
        self.hintPayload = hintPayload
    }

    func transcribe(chunk: BufferedMeetingChunk) async -> MeetingTranscriptSegment? {
        let preparedSamples = Self.resample(samples: chunk.samples, from: chunk.sampleRate, to: targetSampleRate)
        guard !preparedSamples.isEmpty else { return nil }
        guard Self.rootMeanSquare(preparedSamples) >= Self.minimumChunkRMS else {
            return nil
        }

        do {
            let detectLanguage = hintPayload.language == nil
            let promptTokens: [Int]?
            if let prompt = hintPayload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty,
               let tokenizer = whisper.tokenizer {
                promptTokens = tokenizer.encode(text: " " + prompt)
                    .filter { token in token < tokenizer.specialTokens.specialTokenBegin }
            } else {
                promptTokens = nil
            }

            let results = try await whisper.transcribe(
                audioArray: preparedSamples,
                decodeOptions: DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    language: hintPayload.language,
                    temperature: temperature,
                    temperatureFallbackCount: 0,
                    usePrefillPrompt: true,
                    detectLanguage: detectLanguage,
                    skipSpecialTokens: true,
                    withoutTimestamps: true,
                    wordTimestamps: false,
                    promptTokens: promptTokens,
                    chunkingStrategy: nil
                )
            )
            let rawText = results.map(\.text).joined(separator: " ")
            let text = await MainActor.run {
                WhisperTextPostProcessor.normalize(
                    rawText,
                    preferredMainLanguage: mainLanguage,
                    outputMode: .transcription,
                    usesBuiltInTranslationTask: false
                )
            }
            guard !text.isEmpty else { return nil }
            return MeetingTranscriptSegment(
                id: chunk.segmentID,
                speaker: chunk.speaker,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                text: text
            )
        } catch {
            await MainActor.run {
                VoxtLog.error("Meeting Whisper transcription failed: \(error)")
            }
            return nil
        }
    }

    private static func resample(samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard !samples.isEmpty, inputRate > 0, outputRate > 0 else { return samples }
        if abs(inputRate - outputRate) <= 1 {
            return samples
        }

        let ratio = outputRate / inputRate
        let outputCount = max(Int(Double(samples.count) * ratio), 1)
        var output = [Float](repeating: 0, count: outputCount)

        for index in 0..<outputCount {
            let position = Double(index) / ratio
            let lowerIndex = Int(position)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(position - Double(lowerIndex))
            let lower = samples[min(lowerIndex, samples.count - 1)]
            let upper = samples[upperIndex]
            output[index] = lower + (upper - lower) * fraction
        }

        return output
    }

    private static func rootMeanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var energy: Float = 0
        for sample in samples {
            energy += sample * sample
        }
        return sqrt(energy / Float(samples.count))
    }
}

@MainActor
final class MeetingMLXSegmentTranscriber: MeetingSegmentTranscribing {
    private let mlxTranscriber: MLXTranscriber

    init(modelManager: MLXModelManager) {
        self.mlxTranscriber = MLXTranscriber(modelManager: modelManager)
    }

    func transcribe(chunk: BufferedMeetingChunk) async -> MeetingTranscriptSegment? {
        guard let text = await mlxTranscriber.transcribeMeetingChunk(
            samples: chunk.samples,
            sampleRate: chunk.sampleRate
        ) else {
            return nil
        }
        return MeetingTranscriptSegment(
            id: chunk.segmentID,
            speaker: chunk.speaker,
            startSeconds: chunk.startSeconds,
            endSeconds: chunk.endSeconds,
            text: text
        )
    }
}

@MainActor
final class MeetingRemoteASRSegmentTranscriber: MeetingSegmentTranscribing {
    private let transcriptionGate = MeetingRemoteTranscriptionGate()
    private let remoteTranscriber: RemoteASRTranscriber = {
        let transcriber = RemoteASRTranscriber()
        transcriber.doubaoDictionaryEntryProvider = {
            guard let appDelegate = AppDelegate.shared else { return [] }
            return appDelegate.dictionaryStore.activeEntriesForRemoteRequest(
                activeGroupID: appDelegate.activeDictionaryGroupID()
            )
        }
        return transcriber
    }()
    private var isCancelled = false

    func cancelPendingWork() async {
        isCancelled = true
    }

    func transcribe(chunk: BufferedMeetingChunk) async -> MeetingTranscriptSegment? {
        guard !isCancelled else { return nil }
        await transcriptionGate.acquire()
        defer {
            Task {
                await transcriptionGate.release()
            }
        }
        guard !isCancelled else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Voxt-Meeting-Chunk-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        do {
            try MeetingAudioChunkWAVExporter.write(
                samples: chunk.samples,
                sampleRate: Int(chunk.sampleRate.rounded()),
                to: tempURL
            )
            let text = try await transcribeWithRetry(tempURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: tempURL)
            guard !text.isEmpty else { return nil }
            return MeetingTranscriptSegment(
                id: chunk.segmentID,
                speaker: chunk.speaker,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                text: text
            )
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            VoxtLog.error("Meeting Remote ASR transcription failed: \(error)")
            return nil
        }
    }

    private func transcribeWithRetry(_ fileURL: URL) async throws -> String {
        let configuration = remoteTranscriber.currentMeetingConfiguration()
        let retryLimit = configuration.provider == .doubaoASR ? 2 : 1
        var attempt = 0
        var lastError: Error?

        while attempt < retryLimit {
            try Task.checkCancellation()
            if isCancelled {
                throw CancellationError()
            }
            do {
                return try await remoteTranscriber.transcribeMeetingAudioFile(fileURL)
            } catch {
                if error is CancellationError || isCancelled || Task.isCancelled {
                    throw CancellationError()
                }
                lastError = error
                attempt += 1
                guard attempt < retryLimit, shouldRetry(error, provider: configuration.provider) else {
                    throw error
                }
                VoxtLog.warning(
                    "Meeting Remote ASR chunk retry scheduled. provider=\(configuration.provider.rawValue), attempt=\(attempt + 1)"
                )
                try? await Task.sleep(for: .milliseconds(220))
            }
        }

        throw lastError ?? NSError(
            domain: "Voxt.Meeting",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Meeting Remote ASR transcription failed."]
        )
    }

    private func shouldRetry(_ error: Error, provider: RemoteASRProvider) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 57 {
            return true
        }

        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorTimedOut
            ].contains(nsError.code)
        }

        if provider == .doubaoASR {
            let description = nsError.localizedDescription.lowercased()
            return description.contains("socket is not connected")
        }

        return false
    }
}

import Foundation
import AVFoundation
import WhisperKit

struct BufferedMeetingChunk {
    let segmentID: UUID
    let speaker: MeetingSpeaker
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let sampleRate: Double
    let samples: [Float]
    let isFinal: Bool
}

enum MeetingChunkingProfile: Equatable, Sendable {
    case quality
    case realtime

    struct Configuration: Equatable, Sendable {
        let silenceFlushSeconds: TimeInterval
        let minSpeechSeconds: TimeInterval
        let maxChunkSeconds: TimeInterval
        let partialEmitIntervalSeconds: TimeInterval?
    }

}

actor MeetingChunkAccumulator {
    private let speaker: MeetingSpeaker
    private let speechThreshold: Float
    private let config: MeetingChunkingProfile.Configuration

    private var currentSamples: [Float] = []
    private var currentStartSeconds: TimeInterval?
    private var currentSampleRate: Double = Double(WhisperKit.sampleRate)
    private var accumulatedSilenceSeconds: TimeInterval = 0
    private var currentSegmentID = UUID()
    private var lastPartialEmissionDuration: TimeInterval = 0

    init(speaker: MeetingSpeaker, speechThreshold: Float, profile: MeetingChunkingProfile) {
        self.speaker = speaker
        self.speechThreshold = speechThreshold
        switch profile {
        case .quality:
            self.config = .init(
                silenceFlushSeconds: 0.45,
                minSpeechSeconds: 0.35,
                maxChunkSeconds: 2.6,
                partialEmitIntervalSeconds: nil
            )
        case .realtime:
            self.config = .init(
                silenceFlushSeconds: 0.18,
                minSpeechSeconds: 0.18,
                maxChunkSeconds: 1.0,
                partialEmitIntervalSeconds: 0.55
            )
        }
    }

    func append(
        samples: [Float],
        sampleRate: Double,
        level: Float,
        bufferEndSeconds: TimeInterval
    ) -> BufferedMeetingChunk? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }
        let bufferDuration = Double(samples.count) / sampleRate
        let bufferStartSeconds = max(bufferEndSeconds - bufferDuration, 0)

        if currentStartSeconds == nil {
            guard level >= speechThreshold else { return nil }
            currentStartSeconds = bufferStartSeconds
            currentSampleRate = sampleRate
            currentSamples.removeAll(keepingCapacity: true)
            currentSegmentID = UUID()
            lastPartialEmissionDuration = 0
        }

        if abs(currentSampleRate - sampleRate) > 1 {
            if let flushed = flushCurrent(endSeconds: bufferStartSeconds) {
                currentStartSeconds = bufferStartSeconds
                currentSampleRate = sampleRate
                currentSamples = samples
                currentSegmentID = UUID()
                lastPartialEmissionDuration = 0
                accumulatedSilenceSeconds = level >= speechThreshold ? 0 : bufferDuration
                return flushed
            }
            currentStartSeconds = bufferStartSeconds
            currentSampleRate = sampleRate
            currentSamples.removeAll(keepingCapacity: true)
            currentSegmentID = UUID()
            lastPartialEmissionDuration = 0
        }

        currentSamples.append(contentsOf: samples)

        if level >= speechThreshold {
            accumulatedSilenceSeconds = 0
        } else {
            accumulatedSilenceSeconds += bufferDuration
        }

        let currentDuration = Double(currentSamples.count) / currentSampleRate
        let bufferEndSeconds = bufferStartSeconds + bufferDuration

        if currentDuration >= config.maxChunkSeconds {
            return flushCurrent(endSeconds: bufferEndSeconds)
        }

        if accumulatedSilenceSeconds >= config.silenceFlushSeconds {
            return flushCurrent(endSeconds: bufferEndSeconds)
        }

        if let partialEmitIntervalSeconds = config.partialEmitIntervalSeconds,
           level >= speechThreshold,
           currentDuration >= config.minSpeechSeconds,
           currentDuration - lastPartialEmissionDuration >= partialEmitIntervalSeconds {
            lastPartialEmissionDuration = currentDuration
            return makeChunk(endSeconds: bufferEndSeconds, isFinal: false)
        }

        return nil
    }

    func finish(at endSeconds: TimeInterval) -> BufferedMeetingChunk? {
        flushCurrent(endSeconds: endSeconds)
    }

    private func flushCurrent(endSeconds: TimeInterval) -> BufferedMeetingChunk? {
        guard let currentStartSeconds else { return nil }
        let duration = Double(currentSamples.count) / max(currentSampleRate, 1)
        defer {
            self.currentStartSeconds = nil
            self.currentSamples.removeAll(keepingCapacity: false)
            self.accumulatedSilenceSeconds = 0
            self.lastPartialEmissionDuration = 0
            self.currentSegmentID = UUID()
        }
        guard duration >= config.minSpeechSeconds else {
            return nil
        }
        return makeChunk(
            segmentID: currentSegmentID,
            startSeconds: currentStartSeconds,
            endSeconds: max(endSeconds, currentStartSeconds),
            isFinal: true
        )
    }

    private func makeChunk(endSeconds: TimeInterval, isFinal: Bool) -> BufferedMeetingChunk? {
        guard let currentStartSeconds else { return nil }
        return makeChunk(
            segmentID: currentSegmentID,
            startSeconds: currentStartSeconds,
            endSeconds: max(endSeconds, currentStartSeconds),
            isFinal: isFinal
        )
    }

    private func makeChunk(
        segmentID: UUID,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        isFinal: Bool
    ) -> BufferedMeetingChunk {
        BufferedMeetingChunk(
            segmentID: segmentID,
            speaker: speaker,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            sampleRate: currentSampleRate,
            samples: currentSamples,
            isFinal: isFinal
        )
    }
}

enum MeetingAudioChunkWAVExporter {
    static func write(samples: [Float], sampleRate: Int, to destinationURL: URL) throws {
        let normalizedSampleRate = max(sampleRate, 1)
        let data = wavData(for: samples, sampleRate: normalizedSampleRate)
        try data.write(to: destinationURL, options: .atomic)
    }

    private static func wavData(for samples: [Float], sampleRate: Int) -> Data {
        var pcmData = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let intSample = Int16((clamped * Float(Int16.max)).rounded())
            var littleEndian = intSample.littleEndian
            pcmData.append(Data(bytes: &littleEndian, count: MemoryLayout<Int16>.size))
        }

        let dataChunkSize = UInt32(pcmData.count)
        let riffChunkSize = 36 + dataChunkSize
        let byteRate = UInt32(sampleRate * 2)
        let blockAlign = UInt16(2)
        let bitsPerSample = UInt16(16)

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(riffChunkSize.littleEndianData)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(byteRate.littleEndianData)
        data.append(blockAlign.littleEndianData)
        data.append(bitsPerSample.littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(dataChunkSize.littleEndianData)
        data.append(pcmData)
        return data
    }
}

extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

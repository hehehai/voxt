import Foundation
import WhisperKit

actor MeetingAudioArchive {
    private let targetSampleRate: Double = HistoryAudioArchiveSupport.targetSampleRate
    private var meSamples: [Float] = []
    private var themSamples: [Float] = []
    private var meWrittenRange: Range<Int>?
    private var themWrittenRange: Range<Int>?

    func append(
        samples: [Float],
        sampleRate: Double,
        speaker: MeetingSpeaker,
        startSeconds: TimeInterval
    ) {
        guard !samples.isEmpty else { return }
        let preparedSamples = Self.resample(samples: samples, from: sampleRate, to: targetSampleRate)
        guard !preparedSamples.isEmpty else { return }

        let startIndex = max(Int((startSeconds * targetSampleRate).rounded()), 0)
        switch speaker {
        case .me:
            Self.write(preparedSamples, at: startIndex, to: &meSamples)
            meWrittenRange = Self.union(meWrittenRange, with: startIndex..<(startIndex + preparedSamples.count))
        case .them:
            Self.write(preparedSamples, at: startIndex, to: &themSamples)
            themWrittenRange = Self.union(themWrittenRange, with: startIndex..<(startIndex + preparedSamples.count))
        }
    }

    func exportWAV(to destinationURL: URL) throws -> Bool {
        let mixed = mixedSamples()
        return try HistoryAudioArchiveSupport.exportWAV(
            samples: mixed,
            sampleRate: targetSampleRate,
            to: destinationURL
        )
    }

    func analysisAssets() -> [MeetingAudioAsset] {
        let mixed = mixedSamples()
        return Self.asset(
            source: .mixed,
            samples: mixed,
            sampleRate: targetSampleRate,
            sampleRange: combinedWrittenRange()
        )
            .map { [$0] } ?? []
    }

    func finalTranscriptionAssets() -> [MeetingAudioAsset] {
        [
            Self.asset(
                source: .microphone,
                samples: meSamples,
                sampleRate: targetSampleRate,
                sampleRange: meWrittenRange
            ),
            Self.asset(
                source: .systemAudio,
                samples: themSamples,
                sampleRate: targetSampleRate,
                sampleRange: themWrittenRange
            )
        ]
        .compactMap { $0 }
    }

    func reset() {
        meSamples.removeAll(keepingCapacity: false)
        themSamples.removeAll(keepingCapacity: false)
        meWrittenRange = nil
        themWrittenRange = nil
    }

    private func mixedSamples() -> [Float] {
        let count = max(meSamples.count, themSamples.count)
        guard count > 0 else { return [] }

        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let me = index < meSamples.count ? meSamples[index] : 0
            let them = index < themSamples.count ? themSamples[index] : 0
            let mixed = (me + them) * 0.5
            output[index] = max(-1, min(1, mixed))
        }
        return output
    }

    private static func write(_ samples: [Float], at startIndex: Int, to track: inout [Float]) {
        guard !samples.isEmpty else { return }

        let endIndex = startIndex + samples.count
        if track.count < endIndex {
            track.append(contentsOf: repeatElement(0, count: endIndex - track.count))
        }

        for (offset, sample) in samples.enumerated() {
            track[startIndex + offset] = sample
        }
    }

    private static func asset(
        source: TranscriptAudioSource,
        samples: [Float],
        sampleRate: Double,
        sampleRange: Range<Int>?
    ) -> MeetingAudioAsset? {
        guard let sampleRange else {
            return nil
        }
        let lowerBound = max(sampleRange.lowerBound, 0)
        let upperBound = min(sampleRange.upperBound, samples.count)
        guard lowerBound < upperBound else { return nil }

        let trimmedSamples = Array(samples[lowerBound..<upperBound])
        guard trimmedSamples.contains(where: { abs($0) > 0.0001 }) else { return nil }

        return MeetingAudioAsset(
            source: source,
            samples: trimmedSamples,
            sampleRate: sampleRate,
            sessionStartOffset: Double(lowerBound) / sampleRate
        )
    }

    private func combinedWrittenRange() -> Range<Int>? {
        switch (meWrittenRange, themWrittenRange) {
        case let (lhs?, rhs?):
            return min(lhs.lowerBound, rhs.lowerBound)..<max(lhs.upperBound, rhs.upperBound)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private static func union(_ existing: Range<Int>?, with next: Range<Int>) -> Range<Int> {
        guard let existing else { return next }
        return min(existing.lowerBound, next.lowerBound)..<max(existing.upperBound, next.upperBound)
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
}

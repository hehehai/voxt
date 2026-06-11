import Foundation
import WhisperKit

actor MeetingAudioArchive {
    private let targetSampleRate: Double = HistoryAudioArchiveSupport.targetSampleRate
    private var meSamples: [Float] = []
    private var themSamples: [Float] = []

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
        case .them:
            Self.write(preparedSamples, at: startIndex, to: &themSamples)
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

    func reset() {
        meSamples.removeAll(keepingCapacity: false)
        themSamples.removeAll(keepingCapacity: false)
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

import Foundation
import WhisperKit

actor MeetingAudioArchive {
    private let targetSampleRate: Double = Double(WhisperKit.sampleRate)
    private var meSamples: [Float] = []
    private var themSamples: [Float] = []

    func append(samples: [Float], sampleRate: Double, speaker: MeetingSpeaker) {
        guard !samples.isEmpty else { return }
        let preparedSamples = Self.resample(samples: samples, from: sampleRate, to: targetSampleRate)
        guard !preparedSamples.isEmpty else { return }

        switch speaker {
        case .me:
            meSamples.append(contentsOf: preparedSamples)
        case .them:
            themSamples.append(contentsOf: preparedSamples)
        }
    }

    func exportWAV(to destinationURL: URL) throws -> Bool {
        let mixed = mixedSamples()
        guard !mixed.isEmpty else { return false }
        let data = Self.wavData(for: mixed, sampleRate: Int(targetSampleRate))
        let directory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: destinationURL, options: .atomic)
        return true
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

    private static func wavData(for samples: [Float], sampleRate: Int) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)

        var pcmData = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var value = Int16((clamped * Float(Int16.max)).rounded())
            pcmData.append(Data(bytes: &value, count: MemoryLayout<Int16>.size))
        }

        let riffChunkSize = UInt32(36 + pcmData.count)
        let dataChunkSize = UInt32(pcmData.count)

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(Self.bytes(of: riffChunkSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(Self.bytes(of: UInt32(16)))
        data.append(Self.bytes(of: UInt16(1)))
        data.append(Self.bytes(of: channelCount))
        data.append(Self.bytes(of: UInt32(sampleRate)))
        data.append(Self.bytes(of: byteRate))
        data.append(Self.bytes(of: blockAlign))
        data.append(Self.bytes(of: bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.append(Self.bytes(of: dataChunkSize))
        data.append(pcmData)
        return data
    }

    private static func bytes<T>(of value: T) -> Data {
        var mutableValue = value
        return withUnsafeBytes(of: &mutableValue) { Data($0) }
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

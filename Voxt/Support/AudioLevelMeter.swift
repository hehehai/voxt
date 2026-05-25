import Foundation
import AVFoundation

nonisolated enum AudioLevelMeter {
    private static let defaultNoiseGate: Float = 0.010
    private static let defaultGain: Float = 8.5
    private static let defaultExponent: Float = 0.88

    static func normalizedLevel(
        from buffer: AVAudioPCMBuffer,
        noiseGate: Float = defaultNoiseGate,
        gain: Float = defaultGain,
        exponent: Float = defaultExponent
    ) -> Float {
        guard let samples = monoSamples(from: buffer) else { return 0 }
        return normalizedLevel(
            fromSamples: samples,
            noiseGate: noiseGate,
            gain: gain,
            exponent: exponent
        )
    }

    static func normalizedLevel(
        fromPCM16 data: Data,
        noiseGate: Float = defaultNoiseGate,
        gain: Float = defaultGain,
        exponent: Float = defaultExponent
    ) -> Float {
        guard data.count >= 2 else { return 0 }
        var sum: Float = 0
        var count: Int = 0
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let normalized = Float(sample) / Float(Int16.max)
                sum += normalized * normalized
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return normalizedLevel(
            fromLinearRMS: sqrt(sum / Float(count)),
            noiseGate: noiseGate,
            gain: gain,
            exponent: exponent
        )
    }

    static func normalizedLevel(
        fromSamples samples: [Float],
        noiseGate: Float = defaultNoiseGate,
        gain: Float = defaultGain,
        exponent: Float = defaultExponent
    ) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return normalizedLevel(
            fromLinearRMS: sqrt(sum / Float(samples.count)),
            noiseGate: noiseGate,
            gain: gain,
            exponent: exponent
        )
    }

    static func normalizedLevel(
        fromLinearRMS rms: Float,
        noiseGate: Float = defaultNoiseGate,
        gain: Float = defaultGain,
        exponent: Float = defaultExponent
    ) -> Float {
        let clampedRMS = max(0, min(rms, 1))
        guard clampedRMS > noiseGate else { return 0 }

        let gated = min(max((clampedRMS - noiseGate) / max(1 - noiseGate, 0.001), 0), 1)
        let amplified = min(max(gated * gain, 0), 1)
        return min(max(Float(pow(Double(amplified), Double(exponent))), 0), 1)
    }

    static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(max(buffer.format.channelCount, 1))
        guard frameLength > 0 else { return nil }

        if let channelData = buffer.floatChannelData {
            if channelCount == 1 {
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            }
            return (0..<frameLength).map { index in
                var total: Float = 0
                for channel in 0..<channelCount {
                    total += channelData[channel][index]
                }
                return total / Float(channelCount)
            }
        }

        if let channelData = buffer.int16ChannelData {
            let scale: Float = 1 / Float(Int16.max)
            if channelCount == 1 {
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength)).map { Float($0) * scale }
            }
            return (0..<frameLength).map { index in
                var total: Float = 0
                for channel in 0..<channelCount {
                    total += Float(channelData[channel][index]) * scale
                }
                return total / Float(channelCount)
            }
        }

        if let channelData = buffer.int32ChannelData {
            let scale: Float = 1 / Float(Int32.max)
            if channelCount == 1 {
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength)).map { Float($0) * scale }
            }
            return (0..<frameLength).map { index in
                var total: Float = 0
                for channel in 0..<channelCount {
                    total += Float(channelData[channel][index]) * scale
                }
                return total / Float(channelCount)
            }
        }

        guard buffer.format.isInterleaved else { return nil }

        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard let audioBuffer = audioBuffers.first,
              let sourceData = audioBuffer.mData
        else {
            return nil
        }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            let values = sourceData.assumingMemoryBound(to: Float.self)
            return (0..<frameLength).map { frameIndex in
                var total: Float = 0
                let baseIndex = frameIndex * channelCount
                for channel in 0..<channelCount {
                    total += values[baseIndex + channel]
                }
                return total / Float(channelCount)
            }
        case .pcmFormatInt16:
            let scale: Float = 1 / Float(Int16.max)
            let values = sourceData.assumingMemoryBound(to: Int16.self)
            return (0..<frameLength).map { frameIndex in
                var total: Float = 0
                let baseIndex = frameIndex * channelCount
                for channel in 0..<channelCount {
                    total += Float(values[baseIndex + channel]) * scale
                }
                return total / Float(channelCount)
            }
        case .pcmFormatInt32:
            let scale: Float = 1 / Float(Int32.max)
            let values = sourceData.assumingMemoryBound(to: Int32.self)
            return (0..<frameLength).map { frameIndex in
                var total: Float = 0
                let baseIndex = frameIndex * channelCount
                for channel in 0..<channelCount {
                    total += Float(values[baseIndex + channel]) * scale
                }
                return total / Float(channelCount)
            }
        default:
            return nil
        }
    }
}

nonisolated final class CanonicalAudioStreamConverter {
    static let sampleRate: Double = 16_000

    private var nextSourceFrameOffset: Double = 0
    private var lastInputSampleRate: Double?

    func reset() {
        nextSourceFrameOffset = 0
        lastInputSampleRate = nil
    }

    func monoFloat16kSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let samples = AudioLevelMeter.monoSamples(from: buffer), !samples.isEmpty else {
            return nil
        }
        return monoFloat16kSamples(from: samples, inputSampleRate: buffer.format.sampleRate)
    }

    func pcm16Mono16kData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let samples = monoFloat16kSamples(from: buffer), !samples.isEmpty else {
            return nil
        }
        return Self.pcm16Data(from: samples)
    }

    func monoFloat16kSamples(from samples: [Float], inputSampleRate: Double) -> [Float] {
        guard !samples.isEmpty, inputSampleRate > 0 else { return [] }

        if let lastInputSampleRate, abs(lastInputSampleRate - inputSampleRate) > 1 {
            nextSourceFrameOffset = 0
        }
        lastInputSampleRate = inputSampleRate

        guard abs(inputSampleRate - Self.sampleRate) > 1 else {
            nextSourceFrameOffset = 0
            return samples
        }

        let step = inputSampleRate / Self.sampleRate
        var position = max(0, nextSourceFrameOffset)
        var output: [Float] = []
        output.reserveCapacity(max(Int(Double(samples.count) / step), 1))

        while position < Double(samples.count) {
            let sourceIndex = min(Int(position.rounded(.down)), samples.count - 1)
            output.append(samples[sourceIndex])
            position += step
        }

        nextSourceFrameOffset = position - Double(samples.count)
        return output
    }

    static func monoFloat16kSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let samples = AudioLevelMeter.monoSamples(from: buffer), !samples.isEmpty else {
            return nil
        }
        return monoFloat16kSamples(from: samples, inputSampleRate: buffer.format.sampleRate)
    }

    static func monoFloat16kSamples(from samples: [Float], inputSampleRate: Double) -> [Float] {
        guard !samples.isEmpty, inputSampleRate > 0 else { return [] }
        guard abs(inputSampleRate - sampleRate) > 1 else { return samples }

        let ratio = sampleRate / inputSampleRate
        let outputCount = max(Int(Double(samples.count) * ratio), 1)
        return (0..<outputCount).map { index in
            let sourcePosition = Double(index) / ratio
            let sourceIndex = min(Int(sourcePosition.rounded(.down)), samples.count - 1)
            return samples[sourceIndex]
        }
    }

    static func pcm16Mono16kData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let samples = monoFloat16kSamples(from: buffer), !samples.isEmpty else {
            return nil
        }
        return pcm16Data(from: samples)
    }

    static func pcm16Data(from samples: [Float]) -> Data {
        var data = Data(count: samples.count * MemoryLayout<Int16>.size)
        data.withUnsafeMutableBytes { rawBuffer in
            let output = rawBuffer.bindMemory(to: Int16.self)
            for (index, sample) in samples.enumerated() {
                let clamped = max(-1.0, min(1.0, sample))
                output[index] = Int16(clamped * Float(Int16.max))
            }
        }
        return data
    }
}

import Foundation

struct TranscriptionCaptureMetrics: Equatable, Sendable {
    let callbackCount: Int
    let sampleCount: Int
    let sampleRate: Double

    var capturedAudioSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(sampleCount) / sampleRate
    }
}

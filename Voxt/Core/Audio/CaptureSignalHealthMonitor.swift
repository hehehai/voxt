// CaptureSignalHealthMonitor.swift
// Detects microphones that deliver callbacks but only digital silence.

import Foundation

/// A real microphone always carries some noise floor, so a run of samples that are exactly
/// zero means the device is disconnected or muted in hardware (for example a laptop's
/// internal microphone with the lid closed), not that the user is quiet.
nonisolated struct CaptureSignalHealthMonitor: Sendable {
    enum Event: Equatable, Sendable {
        case digitalSilenceDetected(durationMs: Int)
        case signalRecovered(afterSilenceMs: Int)
    }

    static let defaultSilenceThresholdSeconds: Double = 1.5
    /// Below this the sample is indistinguishable from an exact zero (covers -0.0 and denormals).
    static let digitalSilencePeak: Float = 1e-7

    let silenceThresholdSeconds: Double
    private(set) var currentSilenceSeconds: Double = 0
    private(set) var totalSilenceSeconds: Double = 0
    private(set) var maximumPeak: Float = 0
    private(set) var isReportingSilence = false

    init(silenceThresholdSeconds: Double = Self.defaultSilenceThresholdSeconds) {
        self.silenceThresholdSeconds = max(silenceThresholdSeconds, 0)
    }

    mutating func observe(peak: Float, durationSeconds: Double) -> Event? {
        let duration = durationSeconds.isFinite ? max(durationSeconds, 0) : 0
        let magnitude = peak.isFinite ? abs(peak) : 0
        maximumPeak = max(maximumPeak, magnitude)

        guard magnitude <= Self.digitalSilencePeak else {
            let silence = currentSilenceSeconds
            currentSilenceSeconds = 0
            guard isReportingSilence else { return nil }
            isReportingSilence = false
            return .signalRecovered(afterSilenceMs: Self.milliseconds(silence))
        }

        currentSilenceSeconds += duration
        totalSilenceSeconds += duration
        guard !isReportingSilence, currentSilenceSeconds >= silenceThresholdSeconds else { return nil }
        isReportingSilence = true
        return .digitalSilenceDetected(durationMs: Self.milliseconds(currentSilenceSeconds))
    }

    private static func milliseconds(_ seconds: Double) -> Int {
        Int((seconds * 1000).rounded())
    }
}

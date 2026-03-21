import XCTest
@testable import Voxt

final class RecentAudioWaveformStateTests: XCTestCase {
    func testWaveformMaintainsConfiguredBarCount() {
        var waveform = RecentAudioWaveformModel(barCount: 16, historyDuration: 2.0, framesPerSecond: 18)

        waveform.ingest(level: 0.9)
        waveform.advanceFrame()

        XCTAssertEqual(waveform.barLevels.count, 16)
        XCTAssertTrue(waveform.barLevels.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testWaveformRisesForLoudInputAndDecaysAfterSilence() {
        var waveform = RecentAudioWaveformModel(barCount: 16, historyDuration: 2.0, framesPerSecond: 18)

        waveform.ingest(level: 0.95)
        for _ in 0..<6 {
            waveform.advanceFrame()
        }
        let loudPeak = waveform.barLevels.max() ?? 0

        for _ in 0..<36 {
            waveform.advanceFrame()
        }
        let decayedPeak = waveform.barLevels.max() ?? 0

        XCTAssertGreaterThan(loudPeak, 0.55)
        XCTAssertLessThan(decayedPeak, loudPeak)
        XCTAssertLessThan(decayedPeak, 0.18)
    }

    func testSilenceDoesNotProduceFlatFullWaveform() {
        var waveform = RecentAudioWaveformModel(barCount: 16, historyDuration: 2.0, framesPerSecond: 18)

        for _ in 0..<18 {
            waveform.advanceFrame()
        }

        let peak = waveform.barLevels.max() ?? 0
        XCTAssertLessThan(peak, 0.08)
    }

    func testLoudInputCreatesHigherPeakThanMediumInput() {
        var mediumWaveform = RecentAudioWaveformModel(barCount: 16, historyDuration: 2.0, framesPerSecond: 18)
        var loudWaveform = RecentAudioWaveformModel(barCount: 16, historyDuration: 2.0, framesPerSecond: 18)

        for _ in 0..<6 {
            mediumWaveform.ingest(level: 0.35)
            mediumWaveform.advanceFrame()
            loudWaveform.ingest(level: 0.85)
            loudWaveform.advanceFrame()
        }

        XCTAssertGreaterThan(loudWaveform.barLevels.max() ?? 0, mediumWaveform.barLevels.max() ?? 0)
    }
}

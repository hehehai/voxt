// MeetingAudioAnalysisSchedulerTests.swift
// Provides bounded meeting audio analysis scheduler coverage.

import XCTest
@testable import Voxt

final class MeetingAudioAnalysisSchedulerTests: XCTestCase {
    func testSchedulerCoalescesFramesWhileProcessorIsBusy() async {
        let scheduler = MeetingAudioAnalysisScheduler()
        let collector = MeetingAudioAnalysisFrameCollector()
        let sampleRate = 16_000.0
        let frameSamples = [Float](repeating: 0.2, count: 160)

        for index in 0..<10 {
            let start = Double(index * frameSamples.count) / sampleRate
            let frame = MeetingAudioAnalysisFrame(
                samples: frameSamples,
                sampleRate: sampleRate,
                level: 0.2,
                speaker: .me,
                startSeconds: start,
                endSeconds: start + Double(frameSamples.count) / sampleRate
            )
            _ = await scheduler.submit(frame) { frame in
                try? await Task.sleep(for: .milliseconds(50))
                await collector.append(frame)
            }
        }

        await scheduler.flush()
        let processedFrames = await collector.frames()
        let statistics = await scheduler.currentStatistics()

        XCTAssertLessThanOrEqual(processedFrames.count, 2)
        XCTAssertEqual(processedFrames.reduce(0) { $0 + $1.samples.count }, 1_600)
        XCTAssertGreaterThanOrEqual(statistics.mergedFrameCount, 8)
        XCTAssertEqual(statistics.overloadedFrameCount, 0)
    }

    func testSchedulerRejectsAnalysisBeyondSafetyBound() async {
        let scheduler = MeetingAudioAnalysisScheduler()
        let sampleRate = 16_000.0
        let samples = [Float](repeating: 0.2, count: Int(sampleRate * 10.1))
        let frame = MeetingAudioAnalysisFrame(
            samples: samples,
            sampleRate: sampleRate,
            level: 0.2,
            speaker: .them,
            startSeconds: 0,
            endSeconds: 10.1
        )

        let result = await scheduler.submit(frame) { _ in
            XCTFail("An overloaded frame must not be processed.")
        }
        let statistics = await scheduler.currentStatistics()

        guard case .overloaded = result else {
            return XCTFail("Expected the scheduler to enforce its 10-second bound.")
        }
        XCTAssertEqual(statistics.overloadedFrameCount, 1)
        XCTAssertEqual(statistics.processedBatchCount, 0)
    }

    func testCancelledProcessorFinishesBeforeReplacementStarts() async {
        let scheduler = MeetingAudioAnalysisScheduler()
        let gate = MeetingAudioAnalysisTestGate()
        let concurrency = MeetingAudioAnalysisConcurrencyTracker()
        let frame = MeetingAudioAnalysisFrame(
            samples: [Float](repeating: 0.2, count: 160),
            sampleRate: 16_000,
            level: 0.2,
            speaker: .me,
            startSeconds: 0,
            endSeconds: 0.01
        )

        _ = await scheduler.submit(frame) { _ in
            await concurrency.begin()
            await gate.wait()
            await concurrency.end()
        }
        await gate.waitUntilStarted()
        await scheduler.cancel()

        _ = await scheduler.submit(frame) { _ in
            await concurrency.begin()
            await concurrency.end()
        }
        try? await Task.sleep(for: .milliseconds(20))
        let activeCountBeforeRelease = await concurrency.activeCount()
        XCTAssertEqual(activeCountBeforeRelease, 1)

        await gate.open()
        await scheduler.flush()
        let peakCount = await concurrency.peakCount()
        XCTAssertEqual(peakCount, 1)
    }
}

private actor MeetingAudioAnalysisFrameCollector {
    private var collectedFrames: [MeetingAudioAnalysisFrame] = []

    func append(_ frame: MeetingAudioAnalysisFrame) {
        collectedFrames.append(frame)
    }

    func frames() -> [MeetingAudioAnalysisFrame] {
        collectedFrames
    }
}

private actor MeetingAudioAnalysisTestGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private actor MeetingAudioAnalysisConcurrencyTracker {
    private var active = 0
    private var peak = 0

    func begin() {
        active += 1
        peak = max(peak, active)
    }

    func end() {
        active -= 1
    }

    func activeCount() -> Int { active }
    func peakCount() -> Int { peak }
}

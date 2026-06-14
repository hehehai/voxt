import XCTest
@testable import Voxt

final class MeetingAudioChunkingTests: XCTestCase {
    func testChunkAccumulatorsUseSharedTimelineAcrossSpeakers() async {
        let me = MeetingChunkAccumulator(speaker: .me, speechThreshold: 0.012, profile: .quality)
        let them = MeetingChunkAccumulator(speaker: .them, speechThreshold: 0.025, profile: .quality)
        let speechSamples = [Float](repeating: 0.2, count: 19_200) // 0.4s @ 48kHz
        let silenceSamples = [Float](repeating: 0, count: 24_000) // 0.5s @ 48kHz

        _ = await them.append(
            samples: speechSamples,
            sampleRate: 48_000,
            level: 0.1,
            bufferEndSeconds: 0.4
        )
        let firstThem = await them.append(
            samples: silenceSamples,
            sampleRate: 48_000,
            level: 0,
            bufferEndSeconds: 0.9
        )

        _ = await me.append(
            samples: speechSamples,
            sampleRate: 48_000,
            level: 0.1,
            bufferEndSeconds: 1.6
        )
        let meChunk = await me.append(
            samples: silenceSamples,
            sampleRate: 48_000,
            level: 0,
            bufferEndSeconds: 2.1
        )

        _ = await them.append(
            samples: speechSamples,
            sampleRate: 48_000,
            level: 0.1,
            bufferEndSeconds: 2.8
        )
        let secondThem = await them.append(
            samples: silenceSamples,
            sampleRate: 48_000,
            level: 0,
            bufferEndSeconds: 3.3
        )

        XCTAssertNotNil(firstThem)
        XCTAssertNotNil(meChunk)
        XCTAssertNotNil(secondThem)
        XCTAssertEqual(firstThem?.speaker, .them)
        XCTAssertEqual(meChunk?.speaker, .me)
        XCTAssertEqual(secondThem?.speaker, .them)
        XCTAssertLessThan(firstThem?.startSeconds ?? .greatestFiniteMagnitude, meChunk?.startSeconds ?? 0)
        XCTAssertLessThan(meChunk?.startSeconds ?? .greatestFiniteMagnitude, secondThem?.startSeconds ?? 0)
    }

    func testQualityAccumulatorEmitsRealtimeFinalChunksThatCanBeMerged() async {
        let accumulator = MeetingChunkAccumulator(speaker: .them, speechThreshold: 0.025, profile: .quality)
        let speechSamples = [Float](repeating: 0.2, count: 19_200) // 0.4s @ 48kHz
        let silenceSamples = [Float](repeating: 0, count: 24_000) // 0.5s @ 48kHz

        for index in 1...6 {
            let chunk = await accumulator.append(
                samples: speechSamples,
                sampleRate: 48_000,
                level: 0.1,
                bufferEndSeconds: Double(index) * 0.4
            )
            XCTAssertNil(chunk)
        }

        let realtimeChunk = await accumulator.append(
            samples: speechSamples,
            sampleRate: 48_000,
            level: 0.1,
            bufferEndSeconds: 2.8
        )

        XCTAssertNotNil(realtimeChunk)
        XCTAssertEqual(realtimeChunk?.speaker, .them)
        XCTAssertTrue(realtimeChunk?.isFinal ?? false)
        XCTAssertFalse(realtimeChunk?.preventsAdjacentMerge ?? true)
        XCTAssertEqual(realtimeChunk?.startSeconds ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(realtimeChunk?.endSeconds ?? -1, 2.8, accuracy: 0.001)

        _ = await accumulator.append(
            samples: speechSamples,
            sampleRate: 48_000,
            level: 0.1,
            bufferEndSeconds: 3.2
        )
        let pauseChunk = await accumulator.append(
            samples: silenceSamples,
            sampleRate: 48_000,
            level: 0,
            bufferEndSeconds: 3.7
        )

        XCTAssertNotNil(pauseChunk)
        XCTAssertTrue(pauseChunk?.isFinal ?? false)
        XCTAssertTrue(pauseChunk?.preventsAdjacentMerge ?? false)
        XCTAssertNotEqual(pauseChunk?.segmentID, realtimeChunk?.segmentID)
    }

    func testRealtimeAccumulatorEmitsPartialAndShortFinalChunks() async {
        let accumulator = MeetingChunkAccumulator(speaker: .me, speechThreshold: 0.012, profile: .realtime)
        let speechSamples = [Float](repeating: 0.2, count: 14_400) // 0.3s @ 48kHz

        _ = await accumulator.append(
            samples: speechSamples,
            sampleRate: 48_000,
            level: 0.1,
            bufferEndSeconds: 0.3
        )
        let partial = await accumulator.append(
            samples: speechSamples,
            sampleRate: 48_000,
            level: 0.1,
            bufferEndSeconds: 0.6
        )
        _ = await accumulator.append(
            samples: speechSamples,
            sampleRate: 48_000,
            level: 0.1,
            bufferEndSeconds: 0.9
        )
        let finalChunk = await accumulator.append(
            samples: speechSamples,
            sampleRate: 48_000,
            level: 0.1,
            bufferEndSeconds: 1.2
        )

        XCTAssertNotNil(partial)
        XCTAssertFalse(partial?.isFinal ?? true)
        XCTAssertFalse(partial?.preventsAdjacentMerge ?? true)
        XCTAssertNotNil(finalChunk)
        XCTAssertTrue(finalChunk?.isFinal ?? false)
        XCTAssertEqual(finalChunk?.segmentID, partial?.segmentID)
        XCTAssertFalse(finalChunk?.preventsAdjacentMerge ?? true)
        XCTAssertEqual(finalChunk?.endSeconds ?? -1, 1.2, accuracy: 0.001)
    }
}

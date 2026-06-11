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
}

import XCTest
@testable import Voxt

final class MeetingSpeakerAttributionTests: XCTestCase {
    func testSingleActiveRemoteSpeakerKeepsLegacyThemLabel() {
        let result = MeetingDiarizationManager.attributedSpeaker(
            for: .them,
            speakerTimelines: [
                MeetingDiarizationSpeakerTimeline(
                    index: 0,
                    isActive: true,
                    segments: [
                        MeetingDiarizationSegment(startTime: 1.0, endTime: 3.0)
                    ]
                )
            ],
            startSeconds: 1.2,
            endSeconds: 2.4
        )

        XCTAssertEqual(result, .them)
    }

    func testDominantOverlapMapsToRemoteSpeakerIndex() {
        let result = MeetingDiarizationManager.attributedSpeaker(
            for: .them,
            speakerTimelines: [
                MeetingDiarizationSpeakerTimeline(
                    index: 0,
                    isActive: true,
                    segments: [
                        MeetingDiarizationSegment(startTime: 0.0, endTime: 1.3)
                    ]
                ),
                MeetingDiarizationSpeakerTimeline(
                    index: 1,
                    isActive: true,
                    segments: [
                        MeetingDiarizationSegment(startTime: 1.0, endTime: 3.0)
                    ]
                )
            ],
            startSeconds: 1.1,
            endSeconds: 2.2
        )

        XCTAssertEqual(result, .remote(2))
    }

    func testNoOverlapKeepsOriginalSpeaker() {
        let result = MeetingDiarizationManager.attributedSpeaker(
            for: .them,
            speakerTimelines: [
                MeetingDiarizationSpeakerTimeline(
                    index: 0,
                    isActive: true,
                    segments: [
                        MeetingDiarizationSegment(startTime: 0.0, endTime: 0.5)
                    ]
                ),
                MeetingDiarizationSpeakerTimeline(
                    index: 1,
                    isActive: true,
                    segments: [
                        MeetingDiarizationSegment(startTime: 3.0, endTime: 4.0)
                    ]
                )
            ],
            startSeconds: 1.2,
            endSeconds: 1.8
        )

        XCTAssertEqual(result, .them)
    }

    func testOpenEndedSegmentUsesMinimumWindowForAttribution() {
        let result = MeetingDiarizationManager.attributedSpeaker(
            for: .them,
            speakerTimelines: [
                MeetingDiarizationSpeakerTimeline(
                    index: 0,
                    isActive: true,
                    segments: [
                        MeetingDiarizationSegment(startTime: 0.8, endTime: 1.9)
                    ]
                ),
                MeetingDiarizationSpeakerTimeline(
                    index: 1,
                    isActive: true,
                    segments: [
                        MeetingDiarizationSegment(startTime: 2.4, endTime: 3.0)
                    ]
                )
            ],
            startSeconds: 1.0,
            endSeconds: nil
        )

        XCTAssertEqual(result, .remote(1))
    }

    func testNearestSpeakerFallbackHandlesSmallTimelineOffset() {
        let result = MeetingDiarizationManager.attributedSpeaker(
            for: .them,
            speakerTimelines: [
                MeetingDiarizationSpeakerTimeline(
                    index: 0,
                    isActive: true,
                    segments: [
                        MeetingDiarizationSegment(startTime: 0.0, endTime: 0.8)
                    ]
                ),
                MeetingDiarizationSpeakerTimeline(
                    index: 1,
                    isActive: true,
                    segments: [
                        MeetingDiarizationSegment(startTime: 1.0, endTime: 1.5)
                    ]
                )
            ],
            startSeconds: 1.72,
            endSeconds: 1.95
        )

        XCTAssertEqual(result, .remote(2))
    }
}

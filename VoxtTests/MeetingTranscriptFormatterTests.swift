import XCTest
@testable import Voxt

final class MeetingTranscriptFormatterTests: XCTestCase {
    func testTimestampStringUsesMinuteSecondFormatUnderOneHour() {
        XCTAssertEqual(MeetingTranscriptFormatter.timestampString(for: 65.8), "01:05")
    }

    func testCopyStringIncludesTimestampSpeakerAndText() {
        let segment = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 9,
            endSeconds: 12,
            text: "你好，开始吧。"
        )

        XCTAssertEqual(MeetingTranscriptFormatter.copyString(for: segment), "00:09 我 你好，开始吧。")
    }

    func testJoinedTextPreservesSegmentOrderWithLineBreaks() {
        let first = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 3,
            endSeconds: 5,
            text: "先过一下议程。"
        )
        let second = MeetingTranscriptSegment(
            speaker: .them,
            startSeconds: 7,
            endSeconds: 10,
            text: "好的，我先看一下。"
        )

        XCTAssertEqual(
            MeetingTranscriptFormatter.joinedText(for: [first, second]),
            """
            00:03 我 先过一下议程。
            00:07 them 好的，我先看一下。
            """
        )
    }

    func testJoinedTextIncludesTranslatedLineForMeetingSegments() {
        let segment = MeetingTranscriptSegment(
            speaker: .them,
            startSeconds: 12,
            endSeconds: 15,
            text: "Can you send the latest timeline?",
            translatedText: "你可以发送最新的时间线吗？"
        )

        XCTAssertEqual(
            MeetingTranscriptFormatter.joinedText(for: [segment]),
            """
            00:12 them Can you send the latest timeline?
               -> 你可以发送最新的时间线吗？
            """
        )
    }

    func testMergedSegmentsForPersistenceFallsBackToVisibleSnapshotWhenFinalSegmentsAreEmpty() {
        let snapshot = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 4,
            endSeconds: 7,
            text: "我们继续。"
        )

        let merged = MeetingTranscriptFormatter.mergedSegmentsForPersistence(
            primarySegments: [],
            fallbackSegments: [snapshot]
        )

        XCTAssertEqual(merged, [snapshot])
        XCTAssertEqual(MeetingTranscriptFormatter.joinedText(for: merged), "00:04 我 我们继续。")
    }

    func testMergedSegmentsForPersistencePrefersFinalTranslatedContent() {
        let id = UUID()
        let snapshot = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 8,
            endSeconds: 12,
            text: "Can we ship on Friday?"
        )
        let final = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 8,
            endSeconds: 12,
            text: "Can we ship on Friday?",
            translatedText: "我们可以周五发布吗？"
        )

        let merged = MeetingTranscriptFormatter.mergedSegmentsForPersistence(
            primarySegments: [final],
            fallbackSegments: [snapshot]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].translatedText, "我们可以周五发布吗？")
    }
}

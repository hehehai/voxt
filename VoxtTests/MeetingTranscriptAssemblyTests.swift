import XCTest
@testable import Voxt

final class MeetingTranscriptAssemblyTests: XCTestCase {
    func testPartialThenFinalReusesSegmentID() {
        let id = UUID()
        let partial = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 2.5,
            text: "hello"
        )
        let final = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 3,
            text: "hello world"
        )

        let partialResult = MeetingTranscriptAssembler.apply(.partial(partial), to: [])
        let finalResult = MeetingTranscriptAssembler.apply(.final(final), to: partialResult.segments)

        XCTAssertEqual(partialResult.segments.count, 1)
        XCTAssertEqual(finalResult.segments.count, 1)
        XCTAssertEqual(finalResult.segments[0].id, id)
        XCTAssertEqual(finalResult.segments[0].text, "hello world")
        XCTAssertEqual(finalResult.finalizedSegmentID, id)
    }

    func testFinalSegmentsMergeWithinTwoSecondsForSameSpeaker() {
        let first = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .me,
            startSeconds: 1,
            endSeconds: 2,
            text: "hello"
        )
        let second = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .me,
            startSeconds: 3.2,
            endSeconds: 4.1,
            text: "world"
        )

        let firstResult = MeetingTranscriptAssembler.apply(.final(first), to: [])
        let secondResult = MeetingTranscriptAssembler.apply(.final(second), to: firstResult.segments)

        XCTAssertEqual(secondResult.segments.count, 1)
        XCTAssertEqual(secondResult.segments[0].text, "hello world")
        XCTAssertEqual(Set(secondResult.supersededSegmentIDs), Set([first.id, second.id]))
        XCTAssertEqual(secondResult.finalizedSegmentID, first.id)
    }

    func testDifferentSpeakersDoNotMerge() {
        let first = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .me,
            startSeconds: 1,
            endSeconds: 2,
            text: "hello"
        )
        let second = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .them,
            startSeconds: 2.5,
            endSeconds: 3,
            text: "world"
        )

        let firstResult = MeetingTranscriptAssembler.apply(.final(first), to: [])
        let secondResult = MeetingTranscriptAssembler.apply(.final(second), to: firstResult.segments)

        XCTAssertEqual(secondResult.segments.count, 2)
        XCTAssertTrue(secondResult.supersededSegmentIDs.isEmpty)
    }

    func testDifferentRemoteSpeakersDoNotMerge() {
        let first = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .remote(1),
            startSeconds: 1,
            endSeconds: 2,
            text: "hello"
        )
        let second = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .remote(2),
            startSeconds: 2.2,
            endSeconds: 3.1,
            text: "world"
        )

        let firstResult = MeetingTranscriptAssembler.apply(.final(first), to: [])
        let secondResult = MeetingTranscriptAssembler.apply(.final(second), to: firstResult.segments)

        XCTAssertEqual(secondResult.segments.count, 2)
        XCTAssertTrue(secondResult.supersededSegmentIDs.isEmpty)
    }

    func testMeetingSpeakerDecodesLegacyAndRemoteValues() throws {
        let decoder = JSONDecoder()

        let legacyData = #"{"id":"0F8FAD5B-D9CB-469F-A165-70867728950E","speaker":"them","startSeconds":0,"endSeconds":1,"text":"hello","isTranslationPending":false}"#.data(using: .utf8)!
        let remoteData = #"{"id":"7D444840-9DC0-11D1-B245-5FFDCE74FAD2","speaker":"remote_2","startSeconds":0,"endSeconds":1,"text":"hello","isTranslationPending":false}"#.data(using: .utf8)!

        let legacySegment = try decoder.decode(MeetingTranscriptSegment.self, from: legacyData)
        let remoteSegment = try decoder.decode(MeetingTranscriptSegment.self, from: remoteData)

        XCTAssertEqual(legacySegment.speaker, .them)
        XCTAssertEqual(remoteSegment.speaker, .remote(2))
    }

    func testUpdatedSegmentPreservesExistingTranslationWhileRefreshIsPending() {
        let id = UUID()
        let existing = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 4,
            text: "hello there",
            translatedText: "你好",
            isTranslationPending: false
        )
        let updated = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 5,
            text: "hello there again"
        )

        let result = MeetingTranscriptAssembler.apply(.final(updated), to: [existing])

        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].translatedText, "你好")
        XCTAssertTrue(result.segments[0].isTranslationPending)
    }

    func testUpdatedSegmentDoesNotEnterPendingStateWithoutExistingTranslation() {
        let id = UUID()
        let existing = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 4,
            text: "hello there",
            translatedText: nil,
            isTranslationPending: false
        )
        let updated = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 5,
            text: "hello there again"
        )

        let result = MeetingTranscriptAssembler.apply(.final(updated), to: [existing])

        XCTAssertEqual(result.segments.count, 1)
        XCTAssertNil(result.segments[0].translatedText)
        XCTAssertFalse(result.segments[0].isTranslationPending)
    }
}

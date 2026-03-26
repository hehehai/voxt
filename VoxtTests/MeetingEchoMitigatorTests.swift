import XCTest
@testable import Voxt

final class MeetingEchoMitigatorTests: XCTestCase {
    private let mitigator = MeetingEchoMitigator()

    func testDropsExactRemoteDuplicateOfRecentLocalSegment() {
        let recentLocal = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 1,
            endSeconds: 2,
            text: "hello team"
        )
        let remoteDuplicate = MeetingTranscriptSegment(
            speaker: .remote(1),
            startSeconds: 2.4,
            endSeconds: 3,
            text: "hello team"
        )

        let result = mitigator.mitigate(remoteDuplicate, against: [recentLocal])

        XCTAssertNil(result)
    }

    func testTrimsDuplicatedPrefixFromRemoteSegment() {
        let recentLocal = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 1,
            endSeconds: 2,
            text: "hello team"
        )
        let remoteSegment = MeetingTranscriptSegment(
            speaker: .remote(1),
            startSeconds: 2.2,
            endSeconds: 3.4,
            text: "hello team next topic"
        )

        let result = mitigator.mitigate(remoteSegment, against: [recentLocal])

        XCTAssertEqual(result?.text, "next topic")
    }

    func testKeepsDistinctRemoteSegment() {
        let recentLocal = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 1,
            endSeconds: 2,
            text: "hello team"
        )
        let remoteSegment = MeetingTranscriptSegment(
            speaker: .remote(1),
            startSeconds: 2.6,
            endSeconds: 3.8,
            text: "next topic starts now"
        )

        let result = mitigator.mitigate(remoteSegment, against: [recentLocal])

        XCTAssertEqual(result?.text, "next topic starts now")
    }

    func testTrimsRemotePrefixWithPunctuationAndCaseDifferences() {
        let recentLocal = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 1,
            endSeconds: 2,
            text: "Hello, team"
        )
        let remoteSegment = MeetingTranscriptSegment(
            speaker: .remote(1),
            startSeconds: 2.1,
            endSeconds: 3.4,
            text: "hello team, next topic"
        )

        let result = mitigator.mitigate(remoteSegment, against: [recentLocal])

        XCTAssertEqual(result?.text, "next topic")
    }

    func testDropsHighTokenOverlapRemoteEcho() {
        let recentLocal = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 1,
            endSeconds: 2,
            text: "we should ship this tomorrow morning"
        )
        let remoteSegment = MeetingTranscriptSegment(
            speaker: .remote(1),
            startSeconds: 2.2,
            endSeconds: 3.1,
            text: "we should ship this tomorrow"
        )

        let result = mitigator.mitigate(remoteSegment, against: [recentLocal])

        XCTAssertNil(result)
    }
}

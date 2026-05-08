import XCTest
@testable import Voxt

final class SessionEndFlowTests: XCTestCase {
    func testSessionCallbackHandlingDecisionAcceptsActiveNonCancelledSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            AppDelegate.sessionCallbackHandlingDecision(
                requestedSessionID: sessionID,
                activeSessionID: sessionID,
                isSessionCancellationRequested: false
            ),
            .accept
        )
    }

    func testSessionCallbackHandlingDecisionRejectsStaleSession() {
        XCTAssertEqual(
            AppDelegate.sessionCallbackHandlingDecision(
                requestedSessionID: UUID(),
                activeSessionID: UUID(),
                isSessionCancellationRequested: false
            ),
            .rejectStale
        )
    }

    func testSessionCallbackHandlingDecisionRejectsCancelledSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            AppDelegate.sessionCallbackHandlingDecision(
                requestedSessionID: sessionID,
                activeSessionID: sessionID,
                isSessionCancellationRequested: true
            ),
            .rejectCancelled
        )
    }

    func testSessionEndExecutionDecisionAllowsFreshSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            AppDelegate.sessionEndExecutionDecision(
                requestedSessionID: sessionID,
                currentEndingSessionID: nil,
                lastCompletedSessionEndSessionID: nil
            ),
            .execute
        )
    }

    func testSessionEndExecutionDecisionRejectsDuplicateInFlightSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            AppDelegate.sessionEndExecutionDecision(
                requestedSessionID: sessionID,
                currentEndingSessionID: sessionID,
                lastCompletedSessionEndSessionID: nil
            ),
            .skipDuplicateInFlight
        )
    }

    func testSessionEndExecutionDecisionRejectsAlreadyCompletedSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            AppDelegate.sessionEndExecutionDecision(
                requestedSessionID: sessionID,
                currentEndingSessionID: nil,
                lastCompletedSessionEndSessionID: sessionID
            ),
            .skipAlreadyCompleted
        )
    }

    func testStopRecordingFallbackDecisionExtendsGraceForWhisperFinalizationWithoutResult() {
        XCTAssertEqual(
            AppDelegate.stopRecordingFallbackDecision(
                transcriptionEngine: .whisperKit,
                isWhisperFinalizing: true,
                transcriptionResultReceived: false,
                isExtendedGrace: false
            ),
            .extendGrace(seconds: 12)
        )
    }

    func testStopRecordingFallbackDecisionFinishesWhenWhisperAlreadyProducedResult() {
        XCTAssertEqual(
            AppDelegate.stopRecordingFallbackDecision(
                transcriptionEngine: .whisperKit,
                isWhisperFinalizing: true,
                transcriptionResultReceived: true,
                isExtendedGrace: false
            ),
            .finishNow
        )
    }

    func testStopRecordingFallbackDecisionFinishesForExtendedGraceTimeout() {
        XCTAssertEqual(
            AppDelegate.stopRecordingFallbackDecision(
                transcriptionEngine: .whisperKit,
                isWhisperFinalizing: true,
                transcriptionResultReceived: false,
                isExtendedGrace: true
            ),
            .finishNow
        )
    }

    func testStopRecordingFallbackDecisionFinishesForNonWhisperEngines() {
        XCTAssertEqual(
            AppDelegate.stopRecordingFallbackDecision(
                transcriptionEngine: .mlxAudio,
                isWhisperFinalizing: true,
                transcriptionResultReceived: false,
                isExtendedGrace: false
            ),
            .finishNow
        )
        XCTAssertEqual(
            AppDelegate.stopRecordingFallbackDecision(
                transcriptionEngine: .remote,
                isWhisperFinalizing: true,
                transcriptionResultReceived: false,
                isExtendedGrace: false
            ),
            .finishNow
        )
    }
}

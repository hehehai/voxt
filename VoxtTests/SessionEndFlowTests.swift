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
}

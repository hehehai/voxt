// OverlayStateConversationTests.swift
// Provides Overlay State Conversation Tests for Voxt test coverage.

import XCTest
@testable import Voxt

@MainActor
final class OverlayStateConversationTests: XCTestCase {
    func testBeginRewriteConversationSeedsExistingAnswerAndSwitchesSpaceAction() {
        let state = OverlayState()
        state.sessionIconMode = .rewrite
        state.presentAnswer(title: "Draft", content: "First answer", canInject: true)

        XCTAssertEqual(state.answerInteractionMode, .singleResult)
        XCTAssertEqual(state.answerSpaceShortcutAction, .continueAndRecord)

        state.beginRewriteConversationIfNeeded()

        XCTAssertEqual(state.answerInteractionMode, .conversation)
        XCTAssertEqual(state.rewriteConversationTurns.count, 1)
        XCTAssertEqual(state.rewriteConversationTurns[0].userPromptText, "")
        XCTAssertEqual(state.rewriteConversationTurns[0].resultTitle, "Draft")
        XCTAssertEqual(state.rewriteConversationTurns[0].resultContent, "First answer")
        XCTAssertEqual(state.answerSpaceShortcutAction, .toggleConversationRecording)
    }

    func testPresentAnswerInConversationAppendsPendingUserPromptAndUpdatesLatestResult() {
        let state = OverlayState()
        state.sessionIconMode = .rewrite
        state.presentAnswer(title: "Draft", content: "First answer", canInject: true)
        state.beginRewriteConversationIfNeeded()
        state.stageConversationUserPrompt("Make it shorter")

        state.presentAnswer(title: "Shorter", content: "Short answer", canInject: true)

        XCTAssertEqual(state.rewriteConversationTurns.count, 2)
        XCTAssertEqual(state.rewriteConversationTurns[1].userPromptText, "Make it shorter")
        XCTAssertEqual(state.rewriteConversationTurns[1].resultTitle, "Shorter")
        XCTAssertEqual(state.rewriteConversationTurns[1].resultContent, "Short answer")
        XCTAssertEqual(state.latestRewriteResult, RewriteAnswerPayload(title: "Shorter", content: "Short answer"))
        XCTAssertNil(state.pendingConversationUserPrompt)
    }

    func testContinueButtonHidesDuringConversationContinuationTurn() {
        let state = OverlayState()
        state.sessionIconMode = .rewrite
        state.presentAnswer(title: "Draft", content: "First answer", canInject: true)
        state.beginRewriteConversationIfNeeded()

        XCTAssertTrue(state.showsRewriteContinueButton)

        state.isRewriteConversationTurnInProgress = true

        XCTAssertFalse(state.showsRewriteContinueButton)
        XCTAssertEqual(state.answerSpaceShortcutAction, .toggleConversationRecording)

        state.presentConversationAnswer(content: "Follow-up answer", canInject: true)

        XCTAssertTrue(state.showsRewriteContinueButton)
    }

    func testAnswerSpaceShortcutUnavailableForNonRewriteAnswer() {
        let state = OverlayState()
        state.sessionIconMode = .translation
        state.presentAnswer(title: "Translation", content: "Bonjour", canInject: false)

        XCTAssertNil(state.answerSpaceShortcutAction)
        XCTAssertFalse(state.canContinueRewriteAnswer)
    }

    func testStreamingAnswerKeepsLatestCompletedPayloadForActions() {
        let state = OverlayState()
        state.sessionIconMode = .rewrite
        state.presentAnswer(title: "Draft", content: "First answer", canInject: true)
        state.beginRewriteConversationIfNeeded()

        state.presentStreamingAnswer(title: "Second Draft", content: "Working...", canInject: true)

        XCTAssertTrue(state.isStreamingAnswer)
        XCTAssertEqual(state.currentAnswerPayload, RewriteAnswerPayload(title: "Second Draft", content: "Working..."))
        XCTAssertEqual(state.latestCompletedAnswerPayload, RewriteAnswerPayload(title: "Draft", content: "First answer"))
        XCTAssertTrue(state.canCopyLatestAnswer)
    }
}

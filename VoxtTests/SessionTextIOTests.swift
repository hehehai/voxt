import XCTest
@testable import Voxt

@MainActor
final class SessionTextIOTests: XCTestCase {
    func testRewriteAlwaysPresentsAnswerOverlay() {
        XCTAssertTrue(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: false
            )
        )
        XCTAssertTrue(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: true
            )
        )
    }

    func testOnlyDirectAnswerRewriteUsesStructuredOutput() {
        XCTAssertTrue(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: true
            )
        )
    }

    func testNonRewriteSessionsDoNotPresentRewriteAnswerOverlay() {
        XCTAssertFalse(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .transcription,
                hasSelectedSourceText: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .transcription,
                hasSelectedSourceText: false
            )
        )

        XCTAssertFalse(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .translation,
                hasSelectedSourceText: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .translation,
                hasSelectedSourceText: false
            )
        )
    }

    func testSelectedTextTranslationShowsAnswerOverlayOnlyWhenConfigured() {
        XCTAssertTrue(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                showResultWindow: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                showResultWindow: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false,
                showResultWindow: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .transcription,
                isSelectedTextTranslationFlow: true,
                showResultWindow: true
            )
        )
    }

    func testSelectedTextTranslationAutoInjectFollowsResultWindowToggle() {
        XCTAssertTrue(
            AppDelegate.shouldAutoInjectSelectedTextTranslationResult(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                showResultWindow: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldAutoInjectSelectedTextTranslationResult(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                showResultWindow: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldAutoInjectSelectedTextTranslationResult(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false,
                showResultWindow: false
            )
        )
    }
}

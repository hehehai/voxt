// SessionTextIOTests.swift
// Provides Session Text IOTests for Voxt test coverage.

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

    func testPreparedDeliveryContextAppliesDictionaryCorrectionsBeforeDelivery() {
        let matcher = DictionaryMatcher(
            entries: [TestFactories.makeEntry(term: "Anthropic", observedVariants: ["anthropic ai"])],
            blockedGlobalMatchKeys: []
        )

        let context = AppDelegate.preparedDeliveryContext(
            originalText: """
            {"title":"AI Answer","content":"anthropic ai"}
            """,
            llmDurationSeconds: 0.5,
            sessionOutputMode: .rewrite,
            userMainLanguage: .fallbackOption(),
            matcher: matcher,
            usesConservativeEvidence: false,
            automaticReplacementEnabled: true
        )

        XCTAssertEqual(context.outputText, "Anthropic")
        XCTAssertEqual(context.dictionaryCorrectedTerms, ["Anthropic"])
        XCTAssertEqual(context.rewriteAnswerPayload?.title, "AI Answer")
        XCTAssertEqual(context.rewriteAnswerPayload?.content, "Anthropic")
    }

    func testPreparedDeliveryContextKeepsOriginalTextForConservativeDictionaryEvidence() {
        let matcher = DictionaryMatcher(
            entries: [TestFactories.makeEntry(term: "Anthropic", observedVariants: ["anthropic ai"])],
            blockedGlobalMatchKeys: []
        )

        let context = AppDelegate.preparedDeliveryContext(
            originalText: "anthropic ai",
            llmDurationSeconds: nil,
            sessionOutputMode: .transcription,
            userMainLanguage: .fallbackOption(),
            matcher: matcher,
            usesConservativeEvidence: true,
            automaticReplacementEnabled: true
        )

        XCTAssertEqual(context.outputText, "anthropic ai")
        XCTAssertEqual(context.dictionaryCorrectedTerms, [])
        XCTAssertEqual(context.dictionaryMatches.map(\.term), ["Anthropic"])
    }

    func testPreparedDeliveryContextPreservesTextWhenAutomaticReplacementIsDisabled() {
        let matcher = DictionaryMatcher(
            entries: [TestFactories.makeEntry(term: "Anthropic", observedVariants: ["anthropic ai"])],
            blockedGlobalMatchKeys: []
        )

        let context = AppDelegate.preparedDeliveryContext(
            originalText: """
            {"title":"AI Answer","content":"anthropic ai"}
            """,
            llmDurationSeconds: nil,
            sessionOutputMode: .rewrite,
            userMainLanguage: .fallbackOption(),
            matcher: matcher,
            usesConservativeEvidence: false,
            automaticReplacementEnabled: false
        )

        XCTAssertEqual(context.outputText, "anthropic ai")
        XCTAssertEqual(context.dictionaryCorrectedTerms, [])
        XCTAssertEqual(context.dictionaryMatches.map(\.term), ["Anthropic"])
        XCTAssertEqual(context.rewriteAnswerPayload?.content, "anthropic ai")
    }
}

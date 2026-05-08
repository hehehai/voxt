import XCTest
@testable import Voxt

final class AutomaticDictionaryLearningMonitorTests: XCTestCase {
    func testBuildsLearningRequestForInPlaceCorrection() {
        let request = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "anthropic ai",
            baselineText: "Please ship anthropic ai today.",
            finalText: "Please ship Anthropic today."
        )

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.insertedText, "anthropic ai")
        XCTAssertEqual(request?.baselineChangedFragment, "anthropic ai")
        XCTAssertEqual(request?.finalChangedFragment, "Anthropic")
        XCTAssertLessThanOrEqual(request?.editRatio ?? 1, AutomaticDictionaryLearningMonitor.maximumEditRatio)
    }

    func testRejectsPureAppendAfterInsertion() {
        let request = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "hello",
            baselineText: "hello",
            finalText: "hello world"
        )

        XCTAssertNil(request)
    }

    func testRejectsUnrelatedEditsOutsideInsertedText() {
        let request = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "Anthropic",
            baselineText: "Anthropic works. tomorrow 3pm",
            finalText: "Anthropic works. tomorrow 4pm"
        )

        XCTAssertNil(request)
    }

    func testRejectsLargeRewrite() {
        let request = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "short note",
            baselineText: "short note",
            finalText: "Completely different long paragraph with multiple rewritten clauses and unrelated content."
        )

        XCTAssertNil(request)
    }

    func testBuildPromptResolvesTemplateVariables() {
        let request = AutomaticDictionaryLearningRequest(
            insertedText: "anthropic ai",
            baselineContext: "Please ship anthropic ai today.",
            finalContext: "Please ship Anthropic today.",
            baselineChangedFragment: "anthropic ai",
            finalChangedFragment: "Anthropic",
            editRatio: 0.2
        )

        let prompt = AutomaticDictionaryLearningMonitor.buildPrompt(
            template: """
            {{INSERTED_TEXT}}
            {{FINAL_CHANGED_FRAGMENT}}
            {{EXISTING_TERMS}}
            """,
            for: request,
            existingTerms: ["OpenAI", "Claude"],
            userMainLanguage: "Chinese",
            userOtherLanguages: "English"
        )

        XCTAssertTrue(prompt.contains("anthropic ai"))
        XCTAssertTrue(prompt.contains("Anthropic"))
        XCTAssertTrue(prompt.contains("- OpenAI"))
        XCTAssertTrue(prompt.contains("- Claude"))
        XCTAssertFalse(prompt.contains("{{EXISTING_TERMS}}"))
    }
}

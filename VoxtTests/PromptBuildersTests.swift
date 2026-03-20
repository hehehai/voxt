import XCTest
@testable import Voxt

final class PromptBuildersTests: XCTestCase {
    func testTranslationPromptBuilderReplacesVariablesAndAddsStrictRules() {
        let prompt = TranslationPromptBuilder.build(
            systemPrompt: "Translate {{SOURCE_TEXT}} to {{TARGET_LANGUAGE}} for {{USER_MAIN_LANGUAGE}}",
            targetLanguage: .japanese,
            sourceText: "hello",
            userMainLanguagePromptValue: "English",
            strict: true
        )

        XCTAssertContains(prompt, "Translate hello to Japanese for English")
        XCTAssertContains(prompt, "Translate every linguistic token into Japanese")
    }

    func testRewritePromptBuilderAppendsConstraintsInStableOrder() {
        let prompt = RewritePromptBuilder.build(
            systemPrompt: "Base {{DICTATED_PROMPT}} / {{SOURCE_TEXT}}",
            dictatedPrompt: "reply politely",
            sourceText: "",
            structuredAnswerOutput: true,
            directAnswerMode: true,
            forceNonEmptyAnswer: true
        )

        XCTAssertContains(prompt, "Base reply politely / ")
        XCTAssertTrue(prompt.contains("Direct-answer mode:"))
        XCTAssertTrue(prompt.contains("Runtime output format rules:"))
        XCTAssertTrue(prompt.contains("Retry rule:"))
        XCTAssertLessThan(
            prompt.range(of: "Direct-answer mode:")!.lowerBound,
            prompt.range(of: "Runtime output format rules:")!.lowerBound
        )
    }

    func testRewritePromptBuilderReturnsBasePromptWhenNoExtraConstraints() {
        let prompt = RewritePromptBuilder.build(
            systemPrompt: "Base {{DICTATED_PROMPT}} / {{SOURCE_TEXT}}",
            dictatedPrompt: "reply",
            sourceText: "source",
            structuredAnswerOutput: false,
            directAnswerMode: false,
            forceNonEmptyAnswer: false
        )

        XCTAssertEqual(prompt, "Base reply / source")
    }
}


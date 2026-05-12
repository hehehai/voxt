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
        XCTAssertContains(prompt, "Return translated text only.")
    }

    func testRewritePromptBuilderAppendsConstraintsInStableOrder() {
        let prompt = RewritePromptBuilder.build(
            systemPrompt: "Base {{DICTATED_PROMPT}} / {{SOURCE_TEXT}}",
            dictatedPrompt: "reply politely",
            sourceText: "",
            conversationHistory: [],
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

    func testRewritePromptBuilderAddsPlainTextRuntimeRulesWhenNotStructured() {
        let prompt = RewritePromptBuilder.build(
            systemPrompt: "Base {{DICTATED_PROMPT}} / {{SOURCE_TEXT}}",
            dictatedPrompt: "reply",
            sourceText: "source",
            conversationHistory: [],
            structuredAnswerOutput: false,
            directAnswerMode: false,
            forceNonEmptyAnswer: false
        )

        XCTAssertContains(prompt, "Base reply / source")
        XCTAssertContains(prompt, "Runtime output format rules:")
        XCTAssertContains(prompt, "Return plain text only.")
        XCTAssertContains(prompt, "Do not return JSON")
    }

    func testRewritePromptBuilderAppendsConversationHistoryBeforeRuntimeConstraints() {
        let prompt = RewritePromptBuilder.build(
            systemPrompt: "Base {{DICTATED_PROMPT}} / {{SOURCE_TEXT}}",
            dictatedPrompt: "make it shorter",
            sourceText: "",
            conversationHistory: [
                RewriteConversationPromptTurn(
                    userPromptText: "",
                    resultTitle: "Initial Draft",
                    resultContent: "Thanks for your note. Here is the full version."
                ),
                RewriteConversationPromptTurn(
                    userPromptText: "make it warmer",
                    resultTitle: "Warmer Draft",
                    resultContent: "Thanks so much for your note. Here is the full version."
                )
            ],
            structuredAnswerOutput: true,
            directAnswerMode: true,
            forceNonEmptyAnswer: false
        )

        XCTAssertContains(prompt, "Previous conversation:")
        XCTAssertContains(prompt, "Assistant Title: Initial Draft")
        XCTAssertContains(prompt, "Assistant Content: Thanks for your note. Here is the full version.")
        XCTAssertContains(prompt, "User: make it warmer")
        XCTAssertContains(prompt, "Assistant Title: Warmer Draft")
        XCTAssertLessThan(
            prompt.range(of: "Previous conversation:")!.lowerBound,
            prompt.range(of: "Runtime output format rules:")!.lowerBound
        )
    }

    func testRewritePromptBuilderAddsConversationPlainTextRulesForContinueMode() {
        let prompt = RewritePromptBuilder.build(
            systemPrompt: "Base {{DICTATED_PROMPT}} / {{SOURCE_TEXT}}",
            dictatedPrompt: "继续展开",
            sourceText: "",
            conversationHistory: [
                RewriteConversationPromptTurn(
                    userPromptText: "",
                    resultTitle: "山西省会",
                    resultContent: "山西省的省会是太原。"
                )
            ],
            structuredAnswerOutput: false,
            directAnswerMode: true,
            forceNonEmptyAnswer: true
        )

        XCTAssertContains(prompt, "Conversation mode:")
        XCTAssertContains(prompt, "Return the next assistant reply as plain text only.")
        XCTAssertContains(prompt, "Do not return JSON, markdown fences, labels, or quotes.")
        XCTAssertContains(prompt, "A previous answer was empty or unusable.")
    }
}

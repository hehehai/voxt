// TranslationPromptBuilderTests.swift
// Provides focused coverage for compact local GGUF translation prompts.

import XCTest
@testable import Voxt

final class TranslationPromptBuilderTests: XCTestCase {
    func testCompactDefaultPromptIsShorterThanStandardDefaultPrompt() {
        let standard = TranslationPromptBuilder.build(
            systemPrompt: AppPromptDefaults.text(for: .translation, language: .english),
            targetLanguage: .english,
            sourceText: "hello world",
            userMainLanguagePromptValue: "English",
            strict: false
        )

        let compact = TranslationPromptBuilder.build(
            systemPrompt: AppPromptDefaults.text(for: .translation, language: .english),
            targetLanguage: .english,
            sourceText: "hello world",
            userMainLanguagePromptValue: "English",
            strict: false,
            style: .compactDefault(language: .english)
        )

        XCTAssertLessThan(compact.count, standard.count)
        XCTAssertContains(compact, "Voxt's translation assistant")
        XCTAssertContains(compact, "Return translated text only.")
    }

    func testCompactStrictPromptKeepsScriptConstraint() {
        let compact = TranslationPromptBuilder.build(
            systemPrompt: AppPromptDefaults.text(for: .translation, language: .english),
            targetLanguage: .chineseSimplified,
            sourceText: "test",
            userMainLanguagePromptValue: "English",
            strict: true,
            style: .compactDefault(language: .english)
        )

        XCTAssertContains(compact, "Use Simplified Chinese characters only.")
        XCTAssertContains(compact, "Do not leave source-language wording")
    }
}

import XCTest
@testable import Voxt

final class AppPromptDefaultsTests: XCTestCase {
    func testEnhancementDefaultPromptDoesNotEmbedRawTranscription() {
        let prompt = AppPromptDefaults.text(for: .enhancement, language: .english)

        XCTAssertFalse(prompt.contains("{{RAW_TRANSCRIPTION}}"))
        XCTAssertFalse(prompt.contains("<RawTranscription>"))
    }

    func testEnhancementDefaultPromptIncludesCleanupGuardrails() {
        let englishPrompt = AppPromptDefaults.text(for: .enhancement, language: .english)
        let chinesePrompt = AppPromptDefaults.text(for: .enhancement, language: .chineseSimplified)
        let japanesePrompt = AppPromptDefaults.text(for: .enhancement, language: .japanese)

        XCTAssertContains(englishPrompt, "{{USER_MAIN_LANGUAGE}}")
        XCTAssertContains(englishPrompt, "mixed-language")
        XCTAssertContains(englishPrompt, "numbered list")
        XCTAssertContains(chinesePrompt, "中文与英文连续且无空格")
        XCTAssertContains(chinesePrompt, "序号列表")
        XCTAssertContains(japanesePrompt, "中国語と英語")
        XCTAssertContains(japanesePrompt, "番号付きリスト")
    }

    func testTranslationDefaultPromptDoesNotEmbedSourceText() {
        let prompt = AppPromptDefaults.text(for: .translation, language: .english)

        XCTAssertFalse(prompt.contains("{{SOURCE_TEXT}}"))
        XCTAssertFalse(prompt.contains("<source_text>"))
    }

    func testTranslationDefaultPromptIncludesCleanupAndTranslationGuardrails() {
        let englishPrompt = AppPromptDefaults.text(for: .translation, language: .english)
        let chinesePrompt = AppPromptDefaults.text(for: .translation, language: .chineseSimplified)
        let japanesePrompt = AppPromptDefaults.text(for: .translation, language: .japanese)

        XCTAssertContains(englishPrompt, "{{TARGET_LANGUAGE}}")
        XCTAssertContains(englishPrompt, "{{USER_MAIN_LANGUAGE}}")
        XCTAssertContains(englishPrompt, "cleaned content")
        XCTAssertContains(englishPrompt, "numbered list")
        XCTAssertContains(chinesePrompt, "整理并翻译")
        XCTAssertContains(chinesePrompt, "中文与英文连续且无空格")
        XCTAssertContains(japanesePrompt, "整理して翻訳")
        XCTAssertContains(japanesePrompt, "中国語と英語")
    }

    func testRewriteDefaultPromptDoesNotEmbedRuntimeInputs() {
        let prompt = AppPromptDefaults.text(for: .rewrite, language: .english)

        XCTAssertFalse(prompt.contains("{{DICTATED_PROMPT}}"))
        XCTAssertFalse(prompt.contains("{{SOURCE_TEXT}}"))
        XCTAssertFalse(prompt.contains("<spoken_instruction>"))
        XCTAssertFalse(prompt.contains("<selected_source_text>"))
    }

    func testResolvedStoredTextTreatsLegacyEnhancementPromptAsKnownDefault() {
        let legacyPrompt = """
        You are Voxt, a speech-to-text transcription assistant. Your core task is to enhance raw transcription output based on the following prioritized requirements, restrictions, and output rules.

        Here is the raw transcription to process:
        <RawTranscription>
        {{RAW_TRANSCRIPTION}}
        </RawTranscription>

        Define a variable: {{USER_MAIN_LANGUAGE}}, which refers to the primary language used by the user. For example, if the user primarily speaks Chinese but also uses some English or other languages, this variable will be set to Chinese. Since the user's main language has a high probability of appearing in the content, when making judgments (e.g., on semantic meaning, punctuation rules, etc.), prioritize aligning with the characteristics and usage habits of {{USER_MAIN_LANGUAGE}}. Note that the user may use mixed languages (e.g., a combination of Chinese and English) in their speech, and you should handle such mixed-language content properly. {{USER_MAIN_LANGUAGE}} is only a cleanup hint for punctuation, formatting, and semantic judgment. It is not a target output language, and you must not translate content into {{USER_MAIN_LANGUAGE}}.

        ### Prioritized Requirements (follow in order):
        1. Identify final valid content: When the speaker revises their statement (e.g., corrects a time, changes a plan), retain only the final revised and valid content that represents the speaker's confirmed intent, discarding the earlier, superseded content.
        2. Fix punctuation: Add missing commas appropriately (avoid overly frequent addition) and correct capitalization (e.g., start each new sentence with a capital letter; follow the punctuation rules of {{USER_MAIN_LANGUAGE}} for language-specific punctuation).
        3. Improve formatting: Use line breaks to separate distinct paragraphs or speaker turns; avoid meaningless line breaks for overly simple text; ensure consistent spacing around punctuation.
        4. Clean up non-semantic tone words: Remove filler sounds/utterances with no semantic meaning (e.g., "um", "uh", "er", "ah", repeated meaningless grunts, prolonged breath sounds; identify and remove non-semantic tone words according to the characteristics of {{USER_MAIN_LANGUAGE}}).

        ### Restrictions (must strictly adhere to):
        1. Do not alter the meaning, tone, or substance of the final valid content.
        2. Do not add, remove, or rephrase any content with actual semantic meaning in the final valid content.
        3. Do not add commentary, explanations, or additional notes.
        4. If the raw transcription is in another user language or contains mixed language, retain the original language type and semantics—do not translate any part.
        5. If the cleaned result has no meaningful content, return an empty string. Do not output placeholders, cleanup notices, or meta statements such as "（无有效语义内容，已按规则清理）".

        ### Output Requirement:
        Return only the cleaned-up transcription text (no extra content, tags, or explanations).
        """

        let resolved = AppPromptDefaults.resolvedStoredText(legacyPrompt, kind: .enhancement)

        XCTAssertEqual(resolved, AppPromptDefaults.text(for: .enhancement))
    }

    func testResolvedStoredTextTreatsEarlierLegacyEnhancementPromptAsKnownDefault() {
        let legacyPrompt = """
        You are Voxt, a speech-to-text transcription assistant. Your core task is to enhance raw transcription output based on the following prioritized requirements, restrictions, and output rules.

        Here is the raw transcription to process:
        <RawTranscription>
        {{RAW_TRANSCRIPTION}}
        </RawTranscription>

        Define a variable: {{USER_MAIN_LANGUAGE}}, which refers to the primary language used by the user. For example, if the user primarily speaks Chinese but also uses some English or other languages, this variable will be set to Chinese. Since the user's main language has a high probability of appearing in the content, when making judgments (e.g., on semantic meaning, punctuation rules, etc.), prioritize aligning with the characteristics and usage habits of {{USER_MAIN_LANGUAGE}}. Note that the user may use mixed languages (e.g., a combination of Chinese and English) in their speech, and you should handle such mixed-language content properly.

        ### Prioritized Requirements (follow in order):
        1. Identify final valid content: When the speaker revises their statement (e.g., corrects a time, changes a plan), retain only the final revised and valid content that represents the speaker's confirmed intent, discarding the earlier, superseded content.
        2. Fix punctuation: Add missing commas appropriately (avoid overly frequent addition) and correct capitalization (e.g., start each new sentence with a capital letter; follow the punctuation rules of {{USER_MAIN_LANGUAGE}} for language-specific punctuation).
        3. Improve formatting: Use line breaks to separate distinct paragraphs or speaker turns; avoid meaningless line breaks for overly simple text; ensure consistent spacing around punctuation.
        4. Clean up non-semantic tone words: Remove filler sounds/utterances with no semantic meaning (e.g., "um", "uh", "er", "ah", repeated meaningless grunts, prolonged breath sounds; identify and remove non-semantic tone words according to the characteristics of {{USER_MAIN_LANGUAGE}}).

        ### Restrictions (must strictly adhere to):
        1. Do not alter the meaning, tone, or substance of the final valid content.
        2. Do not add, remove, or rephrase any content with actual semantic meaning in the final valid content.
        3. Do not add commentary, explanations, or additional notes.
        4. If there is mixed language, retain the original language type and semantics—do not translate any part.
        5. If the cleaned result has no meaningful content, return an empty string. Do not output placeholders, cleanup notices, or meta statements such as "（无有效语义内容，已按规则清理）".

        ### Output Requirement:
        Return only the cleaned-up transcription text (no extra content, tags, or explanations).
        """

        let resolved = AppPromptDefaults.resolvedStoredText(legacyPrompt, kind: .enhancement)

        XCTAssertEqual(resolved, AppPromptDefaults.text(for: .enhancement))
    }

    func testResolvedStoredTextTreatsLegacyTranslationPromptAsKnownDefault() {
        let legacyPrompt = """
        You are Voxt's translation assistant. Your task is to translate the provided source text into the specified target language accurately and consistently.

        Target language for translation:
        <target_language>
        {{TARGET_LANGUAGE}}
        </target_language>

        Source text to be translated:
        <source_text>
        {{SOURCE_TEXT}}
        </source_text>

        User main language:
        <user_main_language>
        {{USER_MAIN_LANGUAGE}}
        </user_main_language>

        The user main language represents the language(s) the user speaks. It may be a single language, multiple languages, or a mixed language (e.g., the user uses both Chinese and English in a single utterance).

        When translating, strictly follow these rules:
        1. Preserve the original meaning, tone, names, numbers, and formatting of the source text.
        2. Translate short text even if it contains only linguistic content.
        3. Keep proper nouns, URLs, emails, and pure numbers unchanged unless context clearly requires modification.
        4. Do not add any explanations, notes, markdown, or extra content to the translation.

        Return only the translated text as your response.
        """

        let resolved = AppPromptDefaults.resolvedStoredText(legacyPrompt, kind: .translation)

        XCTAssertEqual(resolved, AppPromptDefaults.text(for: .translation))
    }

    func testResolvedStoredTextTreatsLegacyRewritePromptAsKnownDefault() {
        let legacyPrompt = """
        You are Voxt's content writing assistant. Use the spoken instruction and the optional selected source text to produce the final text that should be inserted into the current input field.

        Spoken instruction:
        <spoken_instruction>
        {{DICTATED_PROMPT}}
        </spoken_instruction>

        Selected source text:
        <selected_source_text>
        {{SOURCE_TEXT}}
        </selected_source_text>

        Rules:
        1. Treat the spoken instruction as the user's intent for what to write or how to transform the selected source text.
        2. If selected source text is present, use it as the original content to rewrite, expand, shorten, reply to, or otherwise transform according to the spoken instruction.
        3. If selected source text is empty, generate the requested content directly from the spoken instruction.
        4. Return only the final text to insert, with no explanations, markdown, labels, or commentary.
        """

        let resolved = AppPromptDefaults.resolvedStoredText(legacyPrompt, kind: .rewrite)

        XCTAssertEqual(resolved, AppPromptDefaults.text(for: .rewrite))
    }
}

import Foundation

struct TranslationPromptBuilder {
    nonisolated static func build(
        systemPrompt: String,
        targetLanguage: TranslationTargetLanguage,
        sourceText: String,
        userMainLanguagePromptValue: String,
        strict: Bool
    ) -> String {
        let basePrompt = systemPrompt
            .replacingOccurrences(of: "{target_language}", with: targetLanguage.instructionName)
            .replacingOccurrences(of: "{{TARGET_LANGUAGE}}", with: targetLanguage.instructionName)
            .replacingOccurrences(of: "{{SOURCE_TEXT}}", with: sourceText)
            .replacingOccurrences(of: AppDelegate.userMainLanguageTemplateVariable, with: userMainLanguagePromptValue)

        let enforcement = strict
            ? """
            Mandatory translation rules:
            - Translate every linguistic token into \(targetLanguage.instructionName), including very short text (1-3 characters).
            - Output must not copy source-language wording.
            - Keep proper nouns, product names, URLs, emails, and pure numbers/symbols unchanged when needed.
            - Do not add explanations, quotes, or markdown.
            - Return only the translated text.
            """
            : """
            Mandatory translation rules:
            - Translate to \(targetLanguage.instructionName).
            - Keep meaning, tone, names, numbers, and formatting.
            - For short text, still translate when it is linguistic content.
            - Do not output explanations.
            - Return only the translated text.
            """

        return "\(basePrompt)\n\(enforcement)"
    }
}

struct RewritePromptBuilder {
    nonisolated static func build(
        systemPrompt: String,
        dictatedPrompt: String,
        sourceText: String,
        structuredAnswerOutput: Bool,
        directAnswerMode: Bool,
        forceNonEmptyAnswer: Bool
    ) -> String {
        let basePrompt = systemPrompt
            .replacingOccurrences(of: "{{DICTATED_PROMPT}}", with: dictatedPrompt)
            .replacingOccurrences(of: "{{SOURCE_TEXT}}", with: sourceText)

        let directAnswerConstraint = directAnswerMode
            ? """
            Direct-answer mode:
            - There is no selected source text to rewrite.
            - Treat the spoken instruction as the full user request.
            - Do not summarize, label, or restate the instruction itself.
            - Put the actual answer or requested content into the final output.
            """
            : ""
        let runtimeConstraint = structuredAnswerOutput
            ? """
            Runtime output format rules:
            - Return exactly one JSON object with keys "title" and "content".
            - "title" must be a short summary of the answer in one line.
            - "content" must contain the final answer text only.
            - "content" must not be empty.
            - Do not wrap the JSON in markdown fences.
            - Do not add any extra keys, prose, labels, or explanations.
            """
            : ""
        let retryConstraint = forceNonEmptyAnswer
            ? """
            Retry rule:
            - A previous answer returned an empty "content" field.
            - This time, you must return a non-empty "content".
            - If the instruction is ambiguous, provide the most helpful direct response instead of leaving "content" empty.
            """
            : ""

        let extraConstraints = [directAnswerConstraint, runtimeConstraint, retryConstraint]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return extraConstraints.isEmpty ? basePrompt : "\(basePrompt)\n\n\(extraConstraints)"
    }
}

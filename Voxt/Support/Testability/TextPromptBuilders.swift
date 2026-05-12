import Foundation

struct TranslationPromptBuilder {
    static func build(
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
            - Translate every linguistic token into \(targetLanguage.instructionName), including very short text.
            - Do not copy source-language wording.
            - Keep proper nouns, product names, URLs, emails, and pure numbers unchanged when needed.
            - Return translated text only.
            """
            : """
            Mandatory translation rules:
            - Translate to \(targetLanguage.instructionName).
            - Translate short linguistic text too.
            - Return translated text only.
            """

        return "\(basePrompt)\n\(enforcement)"
    }
}

struct RewritePromptBuilder {
    static func build(
        systemPrompt: String,
        dictatedPrompt: String,
        sourceText: String,
        conversationHistory: [RewriteConversationPromptTurn] = [],
        structuredAnswerOutput: Bool,
        directAnswerMode: Bool,
        forceNonEmptyAnswer: Bool
    ) -> String {
        let basePrompt = systemPrompt
            .replacingOccurrences(of: "{{DICTATED_PROMPT}}", with: dictatedPrompt)
            .replacingOccurrences(of: "{{SOURCE_TEXT}}", with: sourceText)

        let conversationSection = conversationHistorySection(from: conversationHistory)

        let directAnswerConstraint = directAnswerMode
            ? """
            Direct-answer mode:
            - No source text is selected.
            - Treat the spoken instruction as the full request.
            - Output the requested answer directly.
            """
            : ""
        let conversationConstraint: String
        if conversationHistory.isEmpty {
            conversationConstraint = ""
        } else if structuredAnswerOutput {
            conversationConstraint = """
            Conversation mode:
            - Use the previous conversation as the only context.
            - Treat the spoken instruction as a follow-up to the latest assistant answer.
            """
        } else {
            conversationConstraint = """
            Conversation mode:
            - Use the previous conversation as the only context.
            - Treat the spoken instruction as a follow-up to the latest assistant answer.
            - Return the next assistant reply as plain text only.
            - Do not return JSON, markdown fences, labels, or quotes.
            """
        }
        let runtimeConstraint = structuredAnswerOutput
            ? """
            Runtime output format rules:
            - Return exactly one JSON object with keys "title" and "content".
            - "title" must be a short one-line summary.
            - "content" must contain only the final answer text.
            - "content" must not be empty.
            - Do not wrap the JSON in markdown fences or add extra keys.
            """
            : """
            Runtime output format rules:
            - Return plain text only.
            - Return only the final answer or rewrite content.
            - Do not return JSON, labels, markdown fences, or quotes.
            - Do not leave the answer empty.
            """
        let retryConstraint = forceNonEmptyAnswer
            ? (structuredAnswerOutput
                ? """
                Retry rule:
                - A previous answer returned an empty or unusable "content".
                - This time, you must return a non-empty "content".
                - If the instruction is ambiguous, return the most helpful direct answer instead of leaving "content" empty.
                """
                : """
                Retry rule:
                - A previous answer was empty or unusable.
                - This time, you must return a non-empty plain-text answer.
                - Do not return JSON, labels, or quotes.
                - If the instruction is ambiguous, return the most helpful direct answer instead of nothing.
                """)
            : ""

        let extraConstraints = [directAnswerConstraint, conversationConstraint, runtimeConstraint, retryConstraint]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let promptSections = [basePrompt, conversationSection]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let promptWithHistory = promptSections.joined(separator: "\n\n")

        return extraConstraints.isEmpty ? promptWithHistory : "\(promptWithHistory)\n\n\(extraConstraints)"
    }

    private static func conversationHistorySection(from turns: [RewriteConversationPromptTurn]) -> String {
        let segments = turns.compactMap { turn -> String? in
            let userPrompt = turn.userPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
            let resultTitle = turn.resultTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let resultContent = turn.resultContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !userPrompt.isEmpty || !resultTitle.isEmpty || !resultContent.isEmpty else {
                return nil
            }

            var lines: [String] = []
            if !userPrompt.isEmpty {
                lines.append("User: \(userPrompt)")
            }
            if !resultTitle.isEmpty {
                lines.append("Assistant Title: \(resultTitle)")
            }
            if !resultContent.isEmpty {
                lines.append("Assistant Content: \(resultContent)")
            }
            return lines.joined(separator: "\n")
        }

        guard !segments.isEmpty else { return "" }
        return """
        Previous conversation:
        \(segments.joined(separator: "\n\n"))
        """
    }
}

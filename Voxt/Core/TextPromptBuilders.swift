// TextPromptBuilders.swift
// Provides Text Prompt Builders for core app behavior.

import Foundation

struct TranslationPromptBuilder {
    enum Style: Equatable {
        case standard
        case compactDefault(language: AppInterfaceLanguage)
    }

    static func build(
        systemPrompt: String,
        targetLanguage: TranslationTargetLanguage,
        sourceText: String,
        userMainLanguagePromptValue: String,
        strict: Bool,
        style: Style = .standard
    ) -> String {
        switch style {
        case .standard:
            break
        case .compactDefault(let language):
            return compactDefaultPrompt(
                language: language,
                targetLanguage: targetLanguage,
                userMainLanguagePromptValue: userMainLanguagePromptValue,
                strict: strict
            )
        }

        let basePrompt = systemPrompt
            .replacingOccurrences(of: "{target_language}", with: targetLanguage.instructionName)
            .replacingOccurrences(of: "{{TARGET_LANGUAGE}}", with: targetLanguage.instructionName)
            .replacingOccurrences(of: "{{SOURCE_TEXT}}", with: sourceText)
            .replacingOccurrences(of: AppDelegate.userMainLanguageTemplateVariable, with: userMainLanguagePromptValue)

        let enforcement = strict
            ? """
            Mandatory translation rules:
            - Translate every linguistic token into \(targetLanguage.instructionName), including very short text.
            \(targetLanguage.translationScriptConstraint.map { "- \($0)" } ?? "")
            - Do not copy source-language wording.
            - Keep proper nouns, product names, URLs, emails, and pure numbers unchanged when needed.
            - Return translated text only.
            """
            : """
            Mandatory translation rules:
            - Translate to \(targetLanguage.instructionName).
            \(targetLanguage.translationScriptConstraint.map { "- \($0)" } ?? "")
            - Translate short linguistic text too.
            - Return translated text only.
            """

        let normalizedEnforcement = enforcement
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        return "\(basePrompt)\n\(normalizedEnforcement)"
    }

    private static func compactDefaultPrompt(
        language: AppInterfaceLanguage,
        targetLanguage: TranslationTargetLanguage,
        userMainLanguagePromptValue: String,
        strict: Bool
    ) -> String {
        switch resolvedLanguage(language) {
        case .english:
            return compactEnglishPrompt(
                targetLanguage: targetLanguage,
                userMainLanguagePromptValue: userMainLanguagePromptValue,
                strict: strict
            )
        case .chineseSimplified:
            return compactChinesePrompt(
                targetLanguage: targetLanguage,
                userMainLanguagePromptValue: userMainLanguagePromptValue,
                strict: strict
            )
        case .japanese:
            return compactJapanesePrompt(
                targetLanguage: targetLanguage,
                userMainLanguagePromptValue: userMainLanguagePromptValue,
                strict: strict
            )
        case .system:
            return compactEnglishPrompt(
                targetLanguage: targetLanguage,
                userMainLanguagePromptValue: userMainLanguagePromptValue,
                strict: strict
            )
        }
    }

    private static func resolvedLanguage(_ language: AppInterfaceLanguage) -> AppInterfaceLanguage {
        language == .system ? .resolvedSystemLanguage : language
    }

    private static func compactEnglishPrompt(
        targetLanguage: TranslationTargetLanguage,
        userMainLanguagePromptValue: String,
        strict: Bool
    ) -> String {
        let scriptRule = targetLanguage.translationScriptConstraint.map { "- \($0)" } ?? ""
        let strictRule = strict
            ? "- Translate every meaningful linguistic token. Do not leave source-language wording except for names, code, URLs, emails, and pure numbers."
            : "- Translate short text too."
        return """
        You are Voxt's translation assistant.

        User main language: \(userMainLanguagePromptValue)
        Target language: \(targetLanguage.instructionName)

        Rules:
        - Keep only the final intended content when spoken self-corrections appear.
        - Remove obvious filler words and simple ASR disfluency only when they do not change meaning.
        - Preserve names, product names, commands, code, paths, URLs, emails, and numbers.
        - Preserve list structure and line breaks when clear.
        \(scriptRule)
        \(strictRule)
        - Return translated text only.
        """
    }

    private static func compactChinesePrompt(
        targetLanguage: TranslationTargetLanguage,
        userMainLanguagePromptValue: String,
        strict: Bool
    ) -> String {
        let scriptRule = targetLanguage.translationScriptConstraint.map { "- \($0)" } ?? ""
        let strictRule = strict
            ? "- 所有有意义的语言内容都要翻译；除人名、代码、URL、邮箱和纯数字外，不要保留源语言措辞。"
            : "- 很短的语言内容也要翻译。"
        return """
        你是 Voxt 的翻译助手。

        用户主要语言：\(userMainLanguagePromptValue)
        目标语言：\(targetLanguage.instructionName)

        规则：
        - 若口语中出现自我纠正，只保留最后确认的意思。
        - 仅在不影响语义时去除明显语气词和简单口语停顿。
        - 保留人名、产品名、命令、代码、路径、URL、邮箱和数字。
        - 若原文有明确列表或换行结构，尽量保留。
        \(scriptRule)
        \(strictRule)
        - 只返回翻译结果，不要附加说明。
        """
    }

    private static func compactJapanesePrompt(
        targetLanguage: TranslationTargetLanguage,
        userMainLanguagePromptValue: String,
        strict: Bool
    ) -> String {
        let scriptRule = targetLanguage.translationScriptConstraint.map { "- \($0)" } ?? ""
        let strictRule = strict
            ? "- 意味のある言語内容はすべて翻訳し、人名・コード・URL・メールアドレス・純粋な数字以外は原文の言い回しを残さないでください。"
            : "- 短いテキストも翻訳してください。"
        return """
        あなたは Voxt の翻訳アシスタントです。

        ユーザーの主要言語：\(userMainLanguagePromptValue)
        翻訳先言語：\(targetLanguage.instructionName)

        ルール：
        - 話しながら自己修正した場合は、最後に確定した内容だけを残してください。
        - 意味が変わらない場合に限り、明らかなフィラーや単純な言いよどみを除去してください。
        - 人名、製品名、コマンド、コード、パス、URL、メールアドレス、数字は保持してください。
        - 元の箇条書きや改行構造が明確なら、できるだけ維持してください。
        \(scriptRule)
        \(strictRule)
        - 翻訳結果だけを返し、説明は付けないでください。
        """
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

enum RewriteAppContextGuidance {
    static func content(
        hasTextContext: Bool,
        imageAttachmentCount: Int,
        directAnswerMode: Bool
    ) -> String? {
        guard hasTextContext || imageAttachmentCount > 0 else { return nil }

        var lines = [
            "- Active app context may include current app text and one or more screenshots.",
            "- Use app context only to identify the user's target, resolve references like \"this\", \"that\", or \"the latest message\", and infer the current screen state.",
            "- If app context reveals the target message or target UI content, answer based on that content instead of repeating the spoken instruction.",
            "- Do not restate the user's request when the target can be identified from app context.",
            "- If the target cannot be identified from app context, return a short, helpful fallback instead of inventing details."
        ]

        if imageAttachmentCount > 0 {
            lines.append("- When screenshots are attached, inspect them first for the latest visible message or relevant UI content.")
        }

        if directAnswerMode {
            lines.append("- In direct-answer mode, generate the final reply or text directly once the target is identified.")
        }

        return lines.joined(separator: "\n")
    }
}

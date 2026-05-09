import Foundation

struct RewriteAnswerPayload: Equatable {
    let title: String
    let content: String

    nonisolated var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RewriteConversationTurn: Identifiable, Equatable {
    let id: UUID
    let userPromptText: String
    let resultTitle: String
    let resultContent: String

    init(
        id: UUID = UUID(),
        userPromptText: String,
        resultTitle: String,
        resultContent: String
    ) {
        self.id = id
        self.userPromptText = userPromptText
        self.resultTitle = resultTitle
        self.resultContent = resultContent
    }

    static func seed(from payload: RewriteAnswerPayload) -> RewriteConversationTurn {
        RewriteConversationTurn(
            userPromptText: "",
            resultTitle: payload.title,
            resultContent: payload.content
        )
    }

    var promptTurn: RewriteConversationPromptTurn {
        RewriteConversationPromptTurn(
            userPromptText: userPromptText,
            resultTitle: resultTitle,
            resultContent: resultContent
        )
    }
}

struct RewriteConversationPromptTurn: Equatable {
    let userPromptText: String
    let resultTitle: String
    let resultContent: String
}

enum RewriteAnswerContentNormalizer {
    static func normalizePlainTextStreamingPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let openingQuotes: Set<Character> = ["\"", "'", "“"]
        let closingQuotes: Set<Character> = ["\"", "'", "”"]

        if looksStructuredAnswerCandidate(trimmed),
           let payload = RewriteAnswerPayloadParser.extract(from: trimmed) {
            let content = payload.trimmedContent
            if !content.isEmpty {
                return content
            }
        }

        var normalized = trimmed

        if ["\"", "'", "“", "”", "\"\"", "''", "{}", "[]"].contains(normalized) {
            return ""
        }

        if let first = normalized.first,
           openingQuotes.contains(first) {
            normalized.removeFirst()
        }

        if let last = normalized.last,
           closingQuotes.contains(last) {
            normalized.removeLast()
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizePlainTextAnswer(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if looksStructuredAnswerCandidate(trimmed),
           let payload = RewriteAnswerPayloadParser.extract(from: trimmed) {
            let content = payload.trimmedContent
            if !content.isEmpty {
                return content
            }
        }

        var normalized = trimmed
        if normalized.count >= 2 {
            let left = normalized.first
            let right = normalized.last
            let isWrappedByQuotes =
                (left == "\"" && right == "\"") ||
                (left == "'" && right == "'") ||
                (left == "“" && right == "”")
            if isWrappedByQuotes {
                normalized.removeFirst()
                normalized.removeLast()
                normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if ["{}", "[]", "\"\"", "''"].contains(normalized) {
            return ""
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isUnusablePlainTextAnswer(_ text: String, dictatedPrompt: String) -> Bool {
        let normalized = normalizePlainTextAnswer(text)
        guard !normalized.isEmpty else { return true }

        let normalizedPrompt = dictatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedPrompt.isEmpty,
           normalized.caseInsensitiveCompare(normalizedPrompt) == .orderedSame {
            return true
        }

        let lowered = normalized.lowercased()
        return ["null", "nil", "none", "n/a", "na"].contains(lowered)
    }

    private static func looksStructuredAnswerCandidate(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return text.hasPrefix("{") ||
            text.hasPrefix("[") ||
            text.hasPrefix("```") ||
            lowered.contains("\"title\"") ||
            lowered.contains("\"content\"") ||
            (lowered.contains("title:") && lowered.contains("content:"))
    }
}

struct SessionFinalizeContext {
    var outputText: String
    let llmDurationSeconds: TimeInterval?
    var dictionaryMatches: [DictionaryMatchCandidate]
    var dictionaryCorrectedTerms: [String]
    var dictionaryCorrectionSnapshots: [DictionaryCorrectionSnapshot]
    var dictionarySuggestions: [DictionarySuggestionDraft]
    var historyEntryID: UUID?
    var rewriteAnswerPayload: RewriteAnswerPayload?
}

protocol SessionFinalizeStage {
    var name: String { get }
    func run(context: inout SessionFinalizeContext)
}

struct SessionFinalizePipelineRunner {
    let stages: [any SessionFinalizeStage]

    func run(initial: SessionFinalizeContext) -> SessionFinalizeContext {
        var context = initial
        for stage in stages {
            stage.run(context: &context)
        }
        return context
    }
}

import Foundation
import FoundationModels

@MainActor
protocol TextEnhancing: AnyObject {
    func enhance(_ rawText: String, systemPrompt: String) async throws -> String
    func enhance(userPrompt: String) async throws -> String
    func dictionaryHistoryScanTerms(userPrompt: String) async throws -> [String]
    func translate(
        _ text: String,
        targetLanguage: TranslationTargetLanguage,
        systemPrompt: String
    ) async throws -> String
}

/// Uses Apple Intelligence (on-device Foundation Models) to clean up
/// and enhance raw speech transcription output.
@available(macOS 26.0, *)
@MainActor
class TextEnhancer: TextEnhancing {
    @Generable
    struct EnhancementOutput {
        var resultText: String
    }

    @Generable
    struct DictionaryHistoryScanGeneratedItem {
        var term: String
    }

    @Generable
    struct DictionaryHistoryScanGeneratedOutput {
        var terms: [DictionaryHistoryScanGeneratedItem]
    }

    /// Whether Apple Intelligence is available on this device.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Enhances raw transcribed text by fixing grammar, punctuation,
    /// and formatting while preserving the original meaning.
    /// - Parameters:
    ///   - rawText: The raw transcription output to clean up.
    ///   - systemPrompt: The system prompt that instructs the model how to enhance the text.
    func enhance(_ rawText: String, systemPrompt: String) async throws -> String {
        guard TextEnhancer.isAvailable else {
            return rawText
        }

        let session = LanguageModelSession(
            instructions: systemPrompt
        )

        let response = try await session.respond(
            to: """
            Clean up this transcription while preserving meaning and style.
            Input:
            \(rawText)
            """,
            generating: EnhancementOutput.self
        )

        let enhanced = Self.normalizeResultText(response.content.resultText)
        return enhanced.isEmpty ? rawText : enhanced
    }

    func enhance(userPrompt: String) async throws -> String {
        let input = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return "" }
        guard TextEnhancer.isAvailable else {
            return input
        }

        let session = LanguageModelSession(instructions: "")
        let response = try await session.respond(
            to: input,
            generating: EnhancementOutput.self
        )

        let enhanced = Self.normalizeResultText(response.content.resultText)
        return enhanced.isEmpty ? input : enhanced
    }

    func dictionaryHistoryScanTerms(userPrompt: String) async throws -> [String] {
        let input = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return [] }
        guard TextEnhancer.isAvailable else { return [] }

        let session = LanguageModelSession(instructions: "")
        let response = try await session.respond(
            to: input,
            generating: DictionaryHistoryScanGeneratedOutput.self
        )

        return DictionaryHistoryScanResponseParser.normalizeAcceptedTerms(
            from: response.content.terms.map(\.term)
        )
    }

    /// Translates text to the requested target language.
    func translate(
        _ text: String,
        targetLanguage: TranslationTargetLanguage,
        systemPrompt: String
    ) async throws -> String {
        guard TextEnhancer.isAvailable else {
            return text
        }

        let session = LanguageModelSession(
            instructions: systemPrompt
        )

        let response = try await session.respond(
            to: """
            Translate the following text according to the instructions.
            Input:
            \(text)
            """,
            generating: EnhancementOutput.self
        )

        let translated = Self.normalizeResultText(response.content.resultText)
        return translated.isEmpty ? text : translated
    }

    private static func normalizeResultText(_ output: String) -> String {
        var cleaned = output
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: (cleaned as NSString).length)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        cleaned = unwrapCodeFenceIfNeeded(cleaned)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unwrapCodeFenceIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
            return trimmed
        }
        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return trimmed }
        lines.removeFirst()
        if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

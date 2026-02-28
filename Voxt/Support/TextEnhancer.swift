import Foundation
import FoundationModels

/// Uses Apple Intelligence (on-device Foundation Models) to clean up
/// and enhance raw speech transcription output.
@available(macOS 26.0, *)
@MainActor
class TextEnhancer {

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
            to: "Clean up this transcription:\n\n\(rawText)"
        )

        let enhanced = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return enhanced.isEmpty ? rawText : enhanced
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
            to: text
        )

        let translated = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return translated.isEmpty ? text : translated
    }
}

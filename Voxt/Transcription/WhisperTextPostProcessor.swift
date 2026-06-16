// WhisperTextPostProcessor.swift
// Provides Whisper Text Post Processor for transcription engines.

import Foundation

enum WhisperTextPostProcessor {
    static func normalize(
        _ text: String,
        preferredMainLanguage: UserMainLanguageOption,
        outputMode: SessionOutputMode,
        usesBuiltInTranslationTask: Bool
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard outputMode != .translation || !usesBuiltInTranslationTask else {
            return trimmed
        }
        return ChineseScriptNormalizer.normalize(
            trimmed,
            preferredMainLanguage: preferredMainLanguage
        )
    }
}

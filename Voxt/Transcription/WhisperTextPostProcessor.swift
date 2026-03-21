import Foundation

enum WhisperTextPostProcessor {
    static func normalize(
        _ text: String,
        preferredMainLanguage: UserMainLanguageOption,
        outputMode: AppDelegate.SessionOutputMode,
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

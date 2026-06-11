import Foundation

enum MeetingTranslationSupport {
    static func resolvedProvider(
        selectedProvider: TranslationModelProvider,
        fallbackProvider: TranslationModelProvider,
        transcriptionEngine: TranscriptionEngine,
        targetLanguage: TranslationTargetLanguage,
        whisperModelState: WhisperKitModelManager.ModelState
    ) -> TranslationProviderResolution {
        let resolution = TranslationProviderResolver.resolve(
            selectedProvider: selectedProvider,
            fallbackProvider: fallbackProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: false,
            whisperModelState: whisperModelState
        )

        guard resolution.provider == .whisperKit else { return resolution }

        return TranslationProviderResolution(
            provider: resolution.fallbackProvider,
            fallbackProvider: resolution.fallbackProvider,
            usesWhisperDirectTranslation: false,
            fallbackReason: resolution.fallbackReason ?? .selectedTextTranslation
        )
    }
}

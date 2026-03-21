import SwiftUI

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case dictation
    case mlxAudio
    case whisperKit
    case remote

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .dictation: return "Direct Dictation"
        case .mlxAudio: return "MLX Audio (On-device)"
        case .whisperKit: return "Whisper (On-device)"
        case .remote: return "Remote ASR"
        }
    }

    var title: String {
        switch self {
        case .dictation: return AppLocalization.localizedString("Direct Dictation")
        case .mlxAudio: return AppLocalization.localizedString("MLX Audio (On-device)")
        case .whisperKit: return AppLocalization.localizedString("Whisper (On-device)")
        case .remote: return AppLocalization.localizedString("Remote ASR")
        }
    }

    var description: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Uses Apple's built-in speech recognition. Works immediately with no setup.")
        case .mlxAudio:
            return AppLocalization.localizedString("Uses MLX Audio speech models running locally. Requires a one-time model download.")
        case .whisperKit:
            return AppLocalization.localizedString("Uses WhisperKit speech models running locally. Supports multiple Whisper models and configurable decoding.")
        case .remote:
            return AppLocalization.localizedString("Uses remote speech recognition providers and cloud-hosted ASR models.")
        }
    }
}

enum EnhancementMode: String, CaseIterable, Identifiable {
    case off
    case appleIntelligence
    case customLLM
    case remoteLLM

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .off: return "Off"
        case .appleIntelligence: return "Apple Intelligence"
        case .customLLM: return "Custom LLM"
        case .remoteLLM: return "Remote LLM"
        }
    }

    var title: String {
        switch self {
        case .off: return AppLocalization.localizedString("Off")
        case .appleIntelligence: return AppLocalization.localizedString("Apple Intelligence")
        case .customLLM: return AppLocalization.localizedString("Custom LLM")
        case .remoteLLM: return AppLocalization.localizedString("Remote LLM")
        }
    }
}

enum TranslationModelProvider: String, CaseIterable, Identifiable {
    case customLLM
    case remoteLLM
    case whisperKit

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .customLLM: return "Custom LLM"
        case .remoteLLM: return "Remote LLM"
        case .whisperKit: return "Whisper"
        }
    }

    var title: String {
        switch self {
        case .customLLM: return AppLocalization.localizedString("Custom LLM")
        case .remoteLLM: return AppLocalization.localizedString("Remote LLM")
        case .whisperKit: return AppLocalization.localizedString("Whisper")
        }
    }
}

enum TranslationProviderFallbackReason: Equatable {
    case asrEngineNotWhisper
    case targetLanguageNotEnglish
    case selectedTextTranslation
    case whisperModelUnavailable
}

struct TranslationProviderResolution: Equatable {
    let provider: TranslationModelProvider
    let fallbackProvider: TranslationModelProvider
    let usesWhisperDirectTranslation: Bool
    let fallbackReason: TranslationProviderFallbackReason?
}

enum TranslationProviderResolver {
    static func sanitizedFallbackProvider(_ provider: TranslationModelProvider) -> TranslationModelProvider {
        provider == .whisperKit ? .customLLM : provider
    }

    static func resolve(
        selectedProvider: TranslationModelProvider,
        fallbackProvider: TranslationModelProvider,
        transcriptionEngine: TranscriptionEngine,
        targetLanguage: TranslationTargetLanguage,
        isSelectedTextTranslation: Bool,
        whisperModelState: WhisperKitModelManager.ModelState
    ) -> TranslationProviderResolution {
        let sanitizedFallback = sanitizedFallbackProvider(fallbackProvider)
        guard selectedProvider == .whisperKit else {
            return TranslationProviderResolution(
                provider: selectedProvider,
                fallbackProvider: sanitizedFallback,
                usesWhisperDirectTranslation: false,
                fallbackReason: nil
            )
        }

        if isSelectedTextTranslation {
            return TranslationProviderResolution(
                provider: sanitizedFallback,
                fallbackProvider: sanitizedFallback,
                usesWhisperDirectTranslation: false,
                fallbackReason: .selectedTextTranslation
            )
        }

        guard transcriptionEngine == .whisperKit else {
            return TranslationProviderResolution(
                provider: sanitizedFallback,
                fallbackProvider: sanitizedFallback,
                usesWhisperDirectTranslation: false,
                fallbackReason: .asrEngineNotWhisper
            )
        }

        guard targetLanguage == .english else {
            return TranslationProviderResolution(
                provider: sanitizedFallback,
                fallbackProvider: sanitizedFallback,
                usesWhisperDirectTranslation: false,
                fallbackReason: .targetLanguageNotEnglish
            )
        }

        guard isWhisperModelUsable(whisperModelState) else {
            return TranslationProviderResolution(
                provider: sanitizedFallback,
                fallbackProvider: sanitizedFallback,
                usesWhisperDirectTranslation: false,
                fallbackReason: .whisperModelUnavailable
            )
        }

        return TranslationProviderResolution(
            provider: .whisperKit,
            fallbackProvider: sanitizedFallback,
            usesWhisperDirectTranslation: true,
            fallbackReason: nil
        )
    }

    static func warningMessage(
        selectedProvider: TranslationModelProvider,
        transcriptionEngine: TranscriptionEngine,
        targetLanguage: TranslationTargetLanguage,
        whisperModelState: WhisperKitModelManager.ModelState
    ) -> String? {
        guard selectedProvider == .whisperKit else { return nil }

        let resolution = resolve(
            selectedProvider: selectedProvider,
            fallbackProvider: .customLLM,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: false,
            whisperModelState: whisperModelState
        )

        switch resolution.fallbackReason {
        case .asrEngineNotWhisper:
            return AppLocalization.localizedString("Whisper translation works only when the ASR engine is Whisper. Voxt will fall back to your saved LLM provider.")
        case .targetLanguageNotEnglish:
            return AppLocalization.localizedString("Whisper translation only supports English output. Voxt will fall back to your saved LLM provider.")
        case .whisperModelUnavailable:
            return AppLocalization.localizedString("Whisper translation needs a ready Whisper model. Voxt will fall back to your saved LLM provider until the model is ready.")
        case .selectedTextTranslation, .none:
            return nil
        }
    }

    private static func isWhisperModelUsable(_ state: WhisperKitModelManager.ModelState) -> Bool {
        switch state {
        case .downloaded, .loading, .ready:
            return true
        case .notDownloaded, .downloading, .error:
            return false
        }
    }
}

enum RewriteModelProvider: String, CaseIterable, Identifiable {
    case customLLM
    case remoteLLM

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .customLLM: return "Custom LLM"
        case .remoteLLM: return "Remote LLM"
        }
    }

    var title: String {
        switch self {
        case .customLLM: return AppLocalization.localizedString("Custom LLM")
        case .remoteLLM: return AppLocalization.localizedString("Remote LLM")
        }
    }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case bottom
    case top

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        }
    }

    var title: String {
        switch self {
        case .bottom: return AppLocalization.localizedString("Bottom")
        case .top: return AppLocalization.localizedString("Top")
        }
    }
}

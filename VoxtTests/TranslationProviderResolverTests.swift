import XCTest
@testable import Voxt

final class TranslationProviderResolverTests: XCTestCase {
    func testWhisperDirectTranslationRequiresWhisperASRAndEnglish() {
        let resolution = TranslationProviderResolver.resolve(
            selectedProvider: .whisperKit,
            fallbackProvider: .remoteLLM,
            transcriptionEngine: .whisperKit,
            targetLanguage: .english,
            isSelectedTextTranslation: false,
            whisperModelState: .downloaded
        )

        XCTAssertEqual(resolution.provider, .whisperKit)
        XCTAssertTrue(resolution.usesWhisperDirectTranslation)
        XCTAssertNil(resolution.fallbackReason)
        XCTAssertEqual(resolution.fallbackProvider, .remoteLLM)
    }

    func testWhisperProviderFallsBackForNonEnglishTargets() {
        let resolution = TranslationProviderResolver.resolve(
            selectedProvider: .whisperKit,
            fallbackProvider: .customLLM,
            transcriptionEngine: .whisperKit,
            targetLanguage: .japanese,
            isSelectedTextTranslation: false,
            whisperModelState: .downloaded
        )

        XCTAssertEqual(resolution.provider, .customLLM)
        XCTAssertFalse(resolution.usesWhisperDirectTranslation)
        XCTAssertEqual(resolution.fallbackReason, .targetLanguageNotEnglish)
    }

    func testWhisperProviderFallsBackForSelectedTextTranslation() {
        let resolution = TranslationProviderResolver.resolve(
            selectedProvider: .whisperKit,
            fallbackProvider: .remoteLLM,
            transcriptionEngine: .whisperKit,
            targetLanguage: .english,
            isSelectedTextTranslation: true,
            whisperModelState: .downloaded
        )

        XCTAssertEqual(resolution.provider, .remoteLLM)
        XCTAssertFalse(resolution.usesWhisperDirectTranslation)
        XCTAssertEqual(resolution.fallbackReason, .selectedTextTranslation)
    }

    func testWhisperProviderFallsBackWhenASREngineIsNotWhisper() {
        let resolution = TranslationProviderResolver.resolve(
            selectedProvider: .whisperKit,
            fallbackProvider: .remoteLLM,
            transcriptionEngine: .mlxAudio,
            targetLanguage: .english,
            isSelectedTextTranslation: false,
            whisperModelState: .downloaded
        )

        XCTAssertEqual(resolution.provider, .remoteLLM)
        XCTAssertFalse(resolution.usesWhisperDirectTranslation)
        XCTAssertEqual(resolution.fallbackReason, .asrEngineNotWhisper)
    }

    func testWhisperFallbackProviderSanitizesNestedWhisperSelection() {
        let resolution = TranslationProviderResolver.resolve(
            selectedProvider: .whisperKit,
            fallbackProvider: .whisperKit,
            transcriptionEngine: .mlxAudio,
            targetLanguage: .english,
            isSelectedTextTranslation: false,
            whisperModelState: .notDownloaded
        )

        XCTAssertEqual(resolution.provider, .customLLM)
        XCTAssertEqual(resolution.fallbackProvider, .customLLM)
    }

    func testOfflineWhisperPartialStrategyUsesQualityFirstThresholds() {
        XCTAssertEqual(WhisperKitTranscriber.offlinePartialPollInterval, .seconds(6))
        XCTAssertEqual(WhisperKitTranscriber.offlineFirstPartialMinimumSeconds, 5.0, accuracy: 0.0001)
    }
}

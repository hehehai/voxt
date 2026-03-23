import XCTest
@testable import Voxt

final class MeetingTranslationSupportTests: XCTestCase {
    func testCustomLLMProviderPassesThrough() {
        let resolution = MeetingTranslationSupport.resolvedProvider(
            selectedProvider: .customLLM,
            fallbackProvider: .remoteLLM,
            transcriptionEngine: .mlxAudio,
            targetLanguage: .japanese,
            whisperModelState: .ready
        )

        XCTAssertEqual(resolution.provider, .customLLM)
        XCTAssertFalse(resolution.usesWhisperDirectTranslation)
    }

    func testWhisperMeetingTranslationFallsBackToConfiguredLLMProvider() {
        let resolution = MeetingTranslationSupport.resolvedProvider(
            selectedProvider: .whisperKit,
            fallbackProvider: .remoteLLM,
            transcriptionEngine: .whisperKit,
            targetLanguage: .english,
            whisperModelState: .ready
        )

        XCTAssertEqual(resolution.provider, .remoteLLM)
        XCTAssertEqual(resolution.fallbackProvider, .remoteLLM)
        XCTAssertFalse(resolution.usesWhisperDirectTranslation)
    }

    func testWhisperFallbackProviderIsSanitized() {
        let resolution = MeetingTranslationSupport.resolvedProvider(
            selectedProvider: .whisperKit,
            fallbackProvider: .whisperKit,
            transcriptionEngine: .remote,
            targetLanguage: .english,
            whisperModelState: .notDownloaded
        )

        XCTAssertEqual(resolution.provider, .customLLM)
        XCTAssertEqual(resolution.fallbackProvider, .customLLM)
        XCTAssertFalse(resolution.usesWhisperDirectTranslation)
    }
}

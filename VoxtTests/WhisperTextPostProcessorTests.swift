import XCTest
@testable import Voxt

final class WhisperTextPostProcessorTests: XCTestCase {
    func testTranscriptionNormalizesToSimplifiedChinese() {
        let result = WhisperTextPostProcessor.normalize(
            "語音轉錄結果",
            preferredMainLanguage: UserMainLanguageOption.option(for: "zh-hans") ?? .fallbackOption(),
            outputMode: .transcription,
            usesBuiltInTranslationTask: false
        )

        XCTAssertEqual(result, "语音转录结果")
    }

    func testBuiltInTranslationTaskDoesNotRewriteOutputScript() {
        let result = WhisperTextPostProcessor.normalize(
            "Traditional output",
            preferredMainLanguage: UserMainLanguageOption.option(for: "zh-hans") ?? .fallbackOption(),
            outputMode: .translation,
            usesBuiltInTranslationTask: true
        )

        XCTAssertEqual(result, "Traditional output")
    }
}

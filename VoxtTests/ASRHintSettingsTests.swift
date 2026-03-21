import XCTest
@testable import Voxt

@MainActor
final class ASRHintSettingsTests: XCTestCase {
    func testLoadSanitizesUnsupportedPromptEditors() {
        let raw = """
        {"mlxAudio":{"followsUserMainLanguage":true,"promptTemplate":"  should be removed  "},"openAIWhisper":{"followsUserMainLanguage":false,"promptTemplate":"  Bias {{USER_MAIN_LANGUAGE}}  "}}
        """

        let loaded = ASRHintSettingsStore.load(from: raw)

        XCTAssertEqual(loaded[.mlxAudio]?.promptTemplate, "")
        XCTAssertEqual(loaded[.openAIWhisper]?.promptTemplate, "Bias {{USER_MAIN_LANGUAGE}}")
    }

    func testResolvedSettingsFallsBackToDefaults() {
        let settings = ASRHintSettingsStore.resolvedSettings(for: .glmASR, rawValue: nil)

        XCTAssertTrue(settings.followsUserMainLanguage)
        XCTAssertEqual(settings.promptTemplate, AppPreferenceKey.defaultGLMASRHintPrompt)
    }

    func testResolveOpenAIUsesBaseLanguageAndResolvedPrompt() {
        let payload = ASRHintResolver.resolve(
            target: .openAIWhisper,
            settings: ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: "Primary {{USER_MAIN_LANGUAGE}}"
            ),
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertEqual(payload.language, "zh")
        XCTAssertEqual(payload.prompt, "Primary Traditional Chinese")
    }

    func testResolveWhisperKitUsesBaseLanguageAndResolvedPrompt() {
        let payload = ASRHintResolver.resolve(
            target: .whisperKit,
            settings: ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: "Bias {{USER_MAIN_LANGUAGE}} punctuation"
            ),
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertEqual(payload.language, "zh")
        XCTAssertEqual(payload.prompt, "Bias Traditional Chinese punctuation")
    }

    func testResolvedWhisperSettingsDefaultToEmptyPrompt() {
        let settings = ASRHintSettingsStore.resolvedSettings(for: .whisperKit, rawValue: nil)

        XCTAssertTrue(settings.followsUserMainLanguage)
        XCTAssertEqual(settings.promptTemplate, "")
    }

    func testSanitizedWhisperLegacyDefaultPromptMigratesToEmpty() {
        let settings = ASRHintSettingsStore.sanitized(
            ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: AppPreferenceKey.legacyDefaultWhisperASRHintPrompt
            ),
            for: .whisperKit
        )

        XCTAssertEqual(settings.promptTemplate, "")
    }

    func testResolveDoubaoUsesVariantMappingForTraditionalChinese() {
        let payload = ASRHintResolver.resolve(
            target: .doubaoASR,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertEqual(payload.language, "zh-CN")
        XCTAssertEqual(payload.chineseOutputVariant, "zh-Hant")
        XCTAssertNil(payload.prompt)
    }

    func testResolveAliyunDeduplicatesAndLimitsLanguageHints() {
        let payload = ASRHintResolver.resolve(
            target: .aliyunBailianASR,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hans", "en", "zh-Hant", "ja", "ko"]
        )

        XCTAssertEqual(payload.languageHints, ["zh", "en", "ja"])
        XCTAssertEqual(payload.language, "zh")
    }

    func testResolveMLXUsesPromptNameForQwenModel() {
        let payload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hant"],
            mlxModelRepo: "mlx-community/Qwen3-ASR"
        )

        XCTAssertEqual(payload.language, "Traditional Chinese")
    }

    func testLanguageSummaryAndOutputVariantDescription() {
        XCTAssertEqual(
            ASRHintResolver.selectedLanguageSummary(["zh-Hans", "en"]),
            "Simplified Chinese, English"
        )
        XCTAssertEqual(
            ASRHintResolver.outputVariantDescription(for: UserMainLanguageOption.option(for: "zh-hant")!),
            AppLocalization.localizedString("Traditional Chinese")
        )
    }
}

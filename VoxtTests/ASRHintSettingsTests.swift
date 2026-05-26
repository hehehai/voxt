import XCTest
@testable import Voxt

@MainActor
final class ASRHintSettingsTests: XCTestCase {
    func testLoadSanitizesUnsupportedPromptEditors() {
        let raw = """
        {"mlxAudio":{"followsUserMainLanguage":true,"promptTemplate":"  should be removed  "},"openAIWhisper":{"followsUserMainLanguage":false,"promptTemplate":"  Bias {{USER_MAIN_LANGUAGE}}  "}}
        """

        let loaded = ASRHintSettingsStore.load(from: raw)

        XCTAssertEqual(
            loaded[.mlxAudio]?.promptTemplate,
            AppPromptDefaults.text(for: .whisperASRHint)
        )
        XCTAssertEqual(loaded[.openAIWhisper]?.promptTemplate, "Bias {{USER_MAIN_LANGUAGE}}")
    }

    func testResolvedSettingsFallsBackToDefaults() {
        let settings = ASRHintSettingsStore.resolvedSettings(for: .glmASR, rawValue: nil)

        XCTAssertTrue(settings.followsUserMainLanguage)
        XCTAssertEqual(settings.promptTemplate, AppPromptDefaults.text(for: .glmASRHint))
        XCTAssertEqual(settings.promptTemplate, AppPreferenceKey.asrDictionaryTermsTemplateVariable)
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

    func testResolveWhisperKitAvoidsPromptBiasAndForcedLanguage() {
        let payload = ASRHintResolver.resolve(
            target: .whisperKit,
            settings: ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: "Bias {{USER_MAIN_LANGUAGE}} punctuation"
            ),
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertNil(payload.language)
        XCTAssertNil(payload.prompt)
    }

    func testResolvedWhisperSettingsDefaultToEmptyPrompt() {
        let settings = ASRHintSettingsStore.resolvedSettings(for: .whisperKit, rawValue: nil)

        XCTAssertTrue(settings.followsUserMainLanguage)
        XCTAssertEqual(settings.promptTemplate, AppPromptDefaults.text(for: .whisperASRHint))
        XCTAssertEqual(settings.promptTemplate, AppPreferenceKey.asrDictionaryTermsTemplateVariable)
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

    func testDefaultASRPromptResolvesToDictionaryTermsOnly() {
        let payload = ASRHintResolver.resolve(
            target: .openAIWhisper,
            settings: ASRHintSettingsStore.resolvedSettings(for: .openAIWhisper, rawValue: nil),
            userLanguageCodes: ["zh-Hans", "en"],
            dictionaryTerms: "Codex\nVoxt"
        )

        XCTAssertEqual(payload.language, nil)
        XCTAssertEqual(payload.prompt, "Codex\nVoxt")
    }

    func testDefaultASRPromptDoesNotAutoAppendLanguageContext() {
        let payload = ASRHintResolver.resolve(
            target: .glmASR,
            settings: ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: ""
            ),
            userLanguageCodes: ["zh-Hans", "en"],
            dictionaryTerms: ""
        )

        XCTAssertNil(payload.prompt)
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

    func testResolveStepFunBuildsPromptFromTerms() {
        let payload = ASRHintResolver.resolve(
            target: .stepFunASR,
            settings: ASRHintSettings(contextualPhrasesText: "Voxt\nFireRed\nVoxt"),
            userLanguageCodes: ["zh-Hans"],
            dictionaryTerms: "Codex\nFireRed"
        )

        XCTAssertEqual(payload.language, "zh")
        XCTAssertEqual(payload.contextualPhrases, ["Voxt", "FireRed", "Codex"])
        XCTAssertNotNil(payload.prompt)
        XCTAssertContains(payload.prompt ?? "", "Preserve names")
        XCTAssertContains(payload.prompt ?? "", "Voxt")
        XCTAssertContains(payload.prompt ?? "", "FireRed")
        XCTAssertContains(payload.prompt ?? "", "Codex")
        XCTAssertEqual(payload.prompt?.components(separatedBy: "Voxt").count, 2)
        XCTAssertEqual(payload.prompt?.components(separatedBy: "FireRed").count, 2)
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

    func testQwenLocalTuningDefaultsToDictionaryTermsOnly() {
        let settings = MLXLocalTuningSettingsStore.resolvedSettings(
            for: "mlx-community/Qwen3-ASR-1.7B-4bit",
            rawValue: nil
        )

        XCTAssertEqual(settings.qwenContextBias, AppPreferenceKey.asrDictionaryTermsTemplateVariable)
    }

    func testQwenLocalTuningMigratesLegacyDefaultContextBiasToDictionaryTermsOnly() throws {
        let legacyDefault = AppPromptDefaults.text(for: .qwenASRContextBias, language: .chineseSimplified)
        XCTAssertEqual(legacyDefault, AppPreferenceKey.asrDictionaryTermsTemplateVariable)

        let rawStoredSettings = [
            MLXLocalTuningSettingsStore.familyKey(for: "mlx-community/Qwen3-ASR-1.7B-4bit"): MLXLocalTuningSettings(
                qwenContextBias: """
                说话者的主要语言是 {{USER_MAIN_LANGUAGE}}，其他常用语言是 {{USER_OTHER_LANGUAGES}}。

                请将识别偏向于人名、产品名、技术术语和混合语言内容的正确拼写，并保持与原始发音一致，不要翻译。

                当音频中确实出现这些词时，请优先参考下列词典词汇：
                {{DICTIONARY_TERMS}}
                """
            )
        ]
        let data = try JSONEncoder().encode(rawStoredSettings)
        let stored = try XCTUnwrap(String(data: data, encoding: .utf8))

        let settings = MLXLocalTuningSettingsStore.resolvedSettings(
            for: "mlx-community/Qwen3-ASR-1.7B-4bit",
            rawValue: stored
        )

        XCTAssertEqual(settings.qwenContextBias, AppPreferenceKey.asrDictionaryTermsTemplateVariable)
    }

    func testQwenLocalTuningMigratesResolvedLegacyContextBiasToDictionaryTermsOnly() throws {
        let rawStoredSettings = [
            MLXLocalTuningSettingsStore.familyKey(for: "mlx-community/Qwen3-ASR-1.7B-4bit"): MLXLocalTuningSettings(
                qwenContextBias: """
                说话者的主要语言是 Simplified Chinese，其他常用语言是 None specified。

                请将识别偏向于人名、产品名、技术术语和混合语言内容的正确拼写，并保持与原始发音一致，不要翻译。

                当音频中确实出现这些词时，请优先参考下列词典词汇：
                """
            )
        ]
        let data = try JSONEncoder().encode(rawStoredSettings)
        let stored = try XCTUnwrap(String(data: data, encoding: .utf8))

        let settings = MLXLocalTuningSettingsStore.resolvedSettings(
            for: "mlx-community/Qwen3-ASR-1.7B-4bit",
            rawValue: stored
        )

        XCTAssertEqual(settings.qwenContextBias, AppPreferenceKey.asrDictionaryTermsTemplateVariable)
    }

    func testKnownQwenContextLeakageIsRemovedFromASROutput() {
        let leaked = "说话者的主要语言是 Simplified Chinese，其他常用语言是 None specified。"

        XCTAssertEqual(MLXTranscriptionPlanning.removingKnownASRContextLeakage(from: leaked), "")

        let mixed = """
        说话者的主要语言是 Simplified Chinese，其他常用语言是 None specified。
        今天要整理 Codex 体验。
        """

        XCTAssertEqual(
            MLXTranscriptionPlanning.removingKnownASRContextLeakage(from: mixed),
            "今天要整理 Codex 体验。"
        )
    }

    func testMLXModelFamilyRecognizesCohereTranscribe() {
        XCTAssertEqual(
            MLXModelFamily.family(for: "beshkenadze/cohere-transcribe-03-2026-mlx-fp16"),
            .cohereTranscribe
        )
    }

    func testMLXAutomaticBiasesDoNotInjectMultilingualContextIntoLocalStreamingModels() {
        let multilingualContext = """
        Primary language: Chinese
        Other frequently used languages: English
        Mixed-language speech may appear. Preserve names, brands, URLs, and code-like text exactly as spoken.
        """

        let qwenBiases = MLXTranscriptionPlanning.automaticBiases(
            for: .qwen3ASR,
            multilingualContext: multilingualContext
        )
        XCTAssertNil(qwenBiases.qwenContextBias)
        XCTAssertNil(qwenBiases.granitePromptBias)

        let graniteBiases = MLXTranscriptionPlanning.automaticBiases(
            for: .graniteSpeech,
            multilingualContext: multilingualContext
        )
        XCTAssertNil(graniteBiases.qwenContextBias)
        XCTAssertNil(graniteBiases.granitePromptBias)
    }

    func testResolveDictationSettingsUsesMainLanguageAndContextualPhrases() {
        let settings = ASRHintSettings(
            followsUserMainLanguage: true,
            contextualPhrasesText: "Voxt\nFireRed\n Voxt \n",
            prefersOnDeviceRecognition: true,
            addsPunctuation: false,
            reportsPartialResults: false
        )

        let resolved = ASRHintResolver.resolveDictationSettings(
            settings: settings,
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertEqual(resolved.localeIdentifier, "zh-TW")
        XCTAssertEqual(resolved.contextualPhrases, ["Voxt", "FireRed", "Voxt"])
        XCTAssertTrue(resolved.prefersOnDeviceRecognition)
        XCTAssertFalse(resolved.addsPunctuation)
        XCTAssertFalse(resolved.reportsPartialResults)
    }

    func testSanitizedDictationContextualPhrasesTrimBlankLines() {
        let settings = ASRHintSettingsStore.sanitized(
            ASRHintSettings(
                contextualPhrasesText: "\n  Voxt  \n\n FireRed ASR \n"
            ),
            for: .dictation
        )

        XCTAssertEqual(settings.contextualPhrasesText, "Voxt\nFireRed ASR")
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

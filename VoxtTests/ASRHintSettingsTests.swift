// ASRHintSettingsTests.swift
// Provides ASRHint Settings Tests for Voxt test coverage.

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
            ""
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

    func testResolveMLXAvoidsPromptBiasAndForcedLanguage() {
        let payload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: "Bias {{USER_MAIN_LANGUAGE}} punctuation"
            ),
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertNil(payload.language)
        XCTAssertNil(payload.prompt)
    }

    func testResolvedMLXSettingsDefaultToEmptyPrompt() {
        let settings = ASRHintSettingsStore.resolvedSettings(for: .mlxAudio, rawValue: nil)

        XCTAssertTrue(settings.followsUserMainLanguage)
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

    func testResolveAliyunBuildsHotwordsFromContextAndDictionaryTerms() {
        let payload = ASRHintResolver.resolve(
            target: .aliyunBailianASR,
            settings: ASRHintSettings(contextualPhrasesText: "Voxt\nFireRed\nVoxt"),
            userLanguageCodes: ["zh-Hans"],
            dictionaryTerms: "Codex\nFireRed"
        )

        XCTAssertEqual(payload.language, "zh")
        XCTAssertEqual(payload.contextualPhrases, ["Voxt", "FireRed", "Codex"])
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

    func testResolveMLXUsesSenseVoiceLanguageRoutingOnlyForSupportedLocales() {
        let cantonesePayload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["yue"],
            mlxModelRepo: "mlx-community/SenseVoiceSmall"
        )
        XCTAssertEqual(cantonesePayload.language, "yue")

        let chinesePayload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hant"],
            mlxModelRepo: "mlx-community/SenseVoiceSmall"
        )
        XCTAssertEqual(chinesePayload.language, "zh")

        let unsupportedPayload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["fr"],
            mlxModelRepo: "mlx-community/SenseVoiceSmall"
        )
        XCTAssertNil(unsupportedPayload.language)
    }

    func testQwenLocalTuningDefaultsToDictionaryTermsOnly() {
        let settings = MLXLocalTuningSettingsStore.resolvedSettings(
            for: "mlx-community/Qwen3-ASR-1.7B-4bit",
            rawValue: nil
        )

        XCTAssertEqual(settings.qwenContextBias, AppPreferenceKey.asrDictionaryTermsTemplateVariable)
    }

    func testSherpaFunASRTuningDefaultsToDictionaryTermsOnlyContext() {
        let settings = SherpaOnnxLocalTuningSettingsStore.resolvedSettings(
            for: SherpaOnnxModelCatalog.funASRNanoModelID,
            kind: .funASRNano,
            rawValue: nil
        )

        XCTAssertEqual(settings.contextBias, AppPreferenceKey.asrDictionaryTermsTemplateVariable)
        XCTAssertEqual(settings.numThreads, 2)
        XCTAssertEqual(settings.funASRMaxNewTokens, 512)
        XCTAssertTrue(settings.funASRUseITN)
    }

    func testSherpaTuningSanitizesModelParameters() {
        let stored = SherpaOnnxLocalTuningSettingsStore.save(
            SherpaOnnxLocalTuningSettings(
                numThreads: 99,
                contextBias: "  Voxt\nCodex  ",
                funASRMaxNewTokens: 8,
                funASRTopP: 2,
                funASRUseITN: false
            ),
            for: SherpaOnnxModelCatalog.funASRNanoModelID,
            rawValue: nil
        )

        let settings = SherpaOnnxLocalTuningSettingsStore.resolvedSettings(
            for: SherpaOnnxModelCatalog.funASRNanoModelID,
            kind: .funASRNano,
            rawValue: stored
        )

        XCTAssertEqual(settings.numThreads, 8)
        XCTAssertEqual(settings.contextBias, "Voxt\nCodex")
        XCTAssertEqual(settings.funASRMaxNewTokens, 64)
        XCTAssertEqual(settings.funASRTopP, 1.0)
        XCTAssertFalse(settings.funASRUseITN)
    }

    func testResolveSherpaOnnxUsesLanguageAndMergedTerms() {
        let payload = ASRHintResolver.resolve(
            target: .sherpaOnnx,
            settings: ASRHintSettings(contextualPhrasesText: "Voxt\nFireRed\nVoxt"),
            userLanguageCodes: ["zh-Hans"],
            dictionaryTerms: "Codex\nFireRed"
        )

        XCTAssertEqual(payload.language, "zh")
        XCTAssertEqual(payload.contextualPhrases, ["Voxt", "FireRed", "Codex"])
    }

    func testMLXLocalTuningLoadsStoredSettingsWithoutWhisperTemperature() throws {
        let raw = """
        {"whisper":{"preset":"accuracyFirst","qwenContextBias":"","granitePromptBias":"","senseVoiceUseITN":false}}
        """

        let settings = MLXLocalTuningSettingsStore.resolvedSettings(
            for: "mlx-community/whisper-large-v3-mlx",
            rawValue: raw
        )

        XCTAssertEqual(settings.preset, .accuracyFirst)
        XCTAssertEqual(settings.whisperTemperature, 0.0)
    }

    func testMLXWhisperTemperatureIsSanitized() throws {
        let stored = MLXLocalTuningSettingsStore.save(
            MLXLocalTuningSettings(whisperTemperature: 1.8),
            for: "mlx-community/whisper-large-v3-mlx",
            rawValue: nil
        )

        let settings = MLXLocalTuningSettingsStore.resolvedSettings(
            for: "mlx-community/whisper-large-v3-mlx",
            rawValue: stored
        )

        XCTAssertEqual(settings.whisperTemperature, 1.0)
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

    func testMLXModelFamilyRecognizesLatestMLXAudioFamilies() {
        XCTAssertEqual(
            MLXModelFamily.family(for: "OpenMOSS-Team/MOSS-Transcribe-Diarize"),
            .mossTranscribeDiarize
        )
        XCTAssertEqual(
            MLXModelFamily.family(for: "Mediform/canary-1b-v2-mlx-q8"),
            .canary
        )
        XCTAssertEqual(
            MLXModelFamily.family(for: "UsefulSensors/moonshine-tiny"),
            .moonshine
        )
        XCTAssertEqual(
            MLXModelFamily.family(for: "facebook/wav2vec2-base-960h"),
            .wav2vec2CTC
        )
        XCTAssertEqual(
            MLXModelFamily.family(for: "facebook/mms-1b-fl102"),
            .mmsCTC
        )
        XCTAssertEqual(
            MLXModelFamily.family(for: "example/lasr-ctc-checkpoint"),
            .lasrCTC
        )
    }

    func testLatestMLXModelTuningRoundTripsAndSanitizes() {
        let stored = MLXLocalTuningSettingsStore.save(
            MLXLocalTuningSettings(
                cohereLongFormStrategy: .fixedChunks,
                cohereUsePunctuation: false,
                cohereMaxTokens: 4096,
                cohereTemperature: 1.4,
                canaryTaskMode: .translateFromEnglish,
                canaryTranslationLanguage: "DE",
                canaryUsePunctuation: false,
                canaryMaxTokens: 12,
                canaryTemperature: -1,
                moonshineMaxTokens: 480,
                moonshineTemperature: 0.35,
                mmsLanguageCode: " JPN "
            ),
            for: "Mediform/canary-1b-v2-mlx-q8",
            rawValue: nil
        )

        let settings = MLXLocalTuningSettingsStore.resolvedSettings(
            for: "Mediform/canary-1b-v2-mlx-q8",
            rawValue: stored
        )

        XCTAssertEqual(settings.cohereLongFormStrategy, .fixedChunks)
        XCTAssertFalse(settings.cohereUsePunctuation)
        XCTAssertEqual(settings.cohereMaxTokens, 2048)
        XCTAssertEqual(settings.cohereTemperature, 1.0)
        XCTAssertEqual(settings.canaryTaskMode, .translateFromEnglish)
        XCTAssertEqual(settings.canaryTranslationLanguage, "de")
        XCTAssertFalse(settings.canaryUsePunctuation)
        XCTAssertEqual(settings.canaryMaxTokens, 32)
        XCTAssertEqual(settings.canaryTemperature, 0.0)
        XCTAssertEqual(settings.moonshineMaxTokens, 480)
        XCTAssertEqual(settings.moonshineTemperature, 0.35)
        XCTAssertEqual(settings.mmsLanguageCode, "jpn")
    }

    func testCanaryTaskLanguageRoutesRespectOfficialEnglishTranslationConstraint() {
        let transcription = CanaryLanguageSupport.resolvedTaskLanguages(
            mode: .transcription,
            sourceLanguage: "de",
            translationLanguage: "fr"
        )
        XCTAssertEqual(transcription.source, "de")
        XCTAssertEqual(transcription.target, "de")

        let toEnglish = CanaryLanguageSupport.resolvedTaskLanguages(
            mode: .translateToEnglish,
            sourceLanguage: "uk",
            translationLanguage: "fr"
        )
        XCTAssertEqual(toEnglish.source, "uk")
        XCTAssertEqual(toEnglish.target, "en")

        let fromEnglish = CanaryLanguageSupport.resolvedTaskLanguages(
            mode: .translateFromEnglish,
            sourceLanguage: "de",
            translationLanguage: "es"
        )
        XCTAssertEqual(fromEnglish.source, "en")
        XCTAssertEqual(fromEnglish.target, "es")

        let unsupported = CanaryLanguageSupport.resolvedTaskLanguages(
            mode: .transcription,
            sourceLanguage: "zh",
            translationLanguage: "fr"
        )
        XCTAssertEqual(unsupported.source, "en")
        XCTAssertEqual(unsupported.target, "en")
    }

    func testMOSSLocalTuningDefaultsToOfficialFormatAndDictionaryHotwords() {
        let settings = MLXLocalTuningSettingsStore.resolvedSettings(
            for: "OpenMOSS-Team/MOSS-Transcribe-Diarize",
            rawValue: nil
        )

        XCTAssertEqual(settings.mossOutputMode, .timestampedDiarization)
        XCTAssertEqual(settings.mossHotwords, AppPreferenceKey.asrDictionaryTermsTemplateVariable)
        XCTAssertEqual(settings.mossCustomPrompt, "")
    }

    func testMOSSLocalTuningRoundTripsPromptConfiguration() {
        let stored = MLXLocalTuningSettingsStore.save(
            MLXLocalTuningSettings(
                mossOutputMode: .customPrompt,
                mossHotwords: "  Voxt\nCodex  ",
                mossCustomPrompt: "  Transcribe with concise paragraphs.  "
            ),
            for: "OpenMOSS-Team/MOSS-Transcribe-Diarize",
            rawValue: nil
        )

        let settings = MLXLocalTuningSettingsStore.resolvedSettings(
            for: "OpenMOSS-Team/MOSS-Transcribe-Diarize",
            rawValue: stored
        )
        XCTAssertEqual(settings.mossOutputMode, .customPrompt)
        XCTAssertEqual(settings.mossHotwords, "Voxt\nCodex")
        XCTAssertEqual(settings.mossCustomPrompt, "Transcribe with concise paragraphs.")
    }

    func testMOSSPromptSupportUsesOfficialModesAndHotwords() {
        XCTAssertEqual(
            MossASRPromptSupport.resolvedPrompt(
                outputMode: .speakerOnly,
                customPrompt: "",
                hotwords: "Voxt\nCodex"
            ),
            "Transcribe the audio as text using speaker labels such as [S01], [S02], and [S03]. Hotwords: Voxt, Codex"
        )
        XCTAssertEqual(
            MossASRPromptSupport.resolvedPrompt(
                outputMode: .customPrompt,
                customPrompt: "Keep paragraph breaks.",
                hotwords: ""
            ),
            "Keep paragraph breaks."
        )
    }

    func testMOSSRenderingRemovesOnlyConfiguredStructuredTags() {
        let raw = "[0.48][S01]Welcome everyone[1.66][2.10][S02]Ready to begin[3.25]"

        XCTAssertEqual(
            MossASRTranscriptRendering.renderedText(raw, outputMode: .speakerOnly),
            "[S01] Welcome everyone\n[S02] Ready to begin"
        )
        XCTAssertEqual(
            MossASRTranscriptRendering.renderedText(raw, outputMode: .plainText),
            "Welcome everyone\nReady to begin"
        )
        XCTAssertEqual(
            MossASRTranscriptRendering.renderedText(raw, outputMode: .timestampedDiarization),
            raw
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

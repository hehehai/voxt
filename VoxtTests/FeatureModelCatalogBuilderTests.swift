import XCTest
@testable import Voxt

@MainActor
final class FeatureModelCatalogBuilderTests: XCTestCase {
    func testTranslationEntriesDisableWhisperDirectTranslateWithoutWhisperASR() throws {
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                translationASR: .mlx(MLXModelManager.defaultModelRepo),
                translationModel: .remoteLLM(.openAI),
                translationTarget: .english
            )
        )

        let directTranslate = try XCTUnwrap(
            builder.entries(for: .translationModel)
                .first(where: { $0.selectionID == .whisperDirectTranslate })
        )

        XCTAssertFalse(directTranslate.isSelectable)
        XCTAssertEqual(
            directTranslate.disabledReason,
            AppLocalization.localizedString("Whisper direct translation requires Whisper as the translation ASR model.")
        )
    }

    func testTranslationEntriesDisableWhisperDirectTranslateForNonEnglishOutput() throws {
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                translationASR: .whisper(WhisperKitModelManager.defaultModelID),
                translationModel: .remoteLLM(.openAI),
                translationTarget: .japanese
            )
        )

        let directTranslate = try XCTUnwrap(
            builder.entries(for: .translationModel)
                .first(where: { $0.selectionID == .whisperDirectTranslate })
        )

        XCTAssertFalse(directTranslate.isSelectable)
        XCTAssertEqual(
            directTranslate.disabledReason,
            AppLocalization.localizedString("Whisper direct translation only supports English output.")
        )
    }

    func testConfiguredRemoteEntriesExposeUsageAndSelectionSummary() throws {
        let remoteASRConfigurations = RemoteModelConfigurationStore.saveConfigurations([
            RemoteASRProvider.aliyunBailianASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
                model: "fun-asr-realtime",
                endpoint: "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription",
                apiKey: "token"
            )
        ])
        let remoteLLMConfigurations = RemoteModelConfigurationStore.saveConfigurations([
            RemoteLLMProvider.openAI.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "https://example.com/v1",
                apiKey: "secret"
            )
        ])

        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                translationASR: .remoteASR(.aliyunBailianASR),
                translationModel: .remoteLLM(.openAI)
            ),
            remoteASRConfigurationsRaw: remoteASRConfigurations,
            remoteLLMConfigurationsRaw: remoteLLMConfigurations
        )

        let translationASREntry = try XCTUnwrap(
            builder.entries(for: .translationASR)
                .first(where: { $0.selectionID == .remoteASR(.aliyunBailianASR) })
        )
        let translationLLMEntry = try XCTUnwrap(
            builder.entries(for: .translationModel)
                .first(where: { $0.selectionID == .remoteLLM(.openAI) })
        )

        XCTAssertTrue(translationASREntry.isSelectable)
        XCTAssertTrue(translationASREntry.filterTags.contains(AppLocalization.localizedString("Configured")))
        XCTAssertTrue(translationASREntry.usageLocations.contains(AppLocalization.localizedString("Translation")))

        XCTAssertTrue(translationLLMEntry.isSelectable)
        XCTAssertTrue(translationLLMEntry.displayTags.contains(AppLocalization.localizedString("Configured")))
        XCTAssertTrue(translationLLMEntry.usageLocations.contains(AppLocalization.localizedString("Translation")))
        XCTAssertEqual(builder.llmSelectionSummary(.remoteLLM(.openAI)), "OpenAI · gpt-5.2")
        XCTAssertEqual(
            builder.asrSelectionSummary(.remoteASR(.aliyunBailianASR)),
            "\(RemoteASRProvider.aliyunBailianASR.title) · fun-asr-realtime"
        )
    }

    func testUnconfiguredRemoteLLMEntryRemainsNotConfiguredInSelector() throws {
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(translationModel: .remoteLLM(.openAI))
        )

        let entry = try XCTUnwrap(
            builder.entries(for: .translationModel)
                .first(where: { $0.selectionID == .remoteLLM(.openAI) })
        )

        XCTAssertFalse(entry.isSelectable)
        XCTAssertEqual(entry.statusText, AppLocalization.localizedString("Not configured"))
        XCTAssertFalse(entry.filterTags.contains(AppLocalization.localizedString("Configured")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Configured")))
    }

    func testOllamaRemoteEntryIsSelectableWithoutAPIKey() throws {
        let remoteLLMConfigurations = RemoteModelConfigurationStore.saveConfigurations([
            RemoteLLMProvider.ollama.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3",
                endpoint: "http://127.0.0.1:11434/api/chat"
            )
        ])

        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(translationModel: .remoteLLM(.ollama)),
            remoteLLMConfigurationsRaw: remoteLLMConfigurations
        )

        let entry = try XCTUnwrap(
            builder.entries(for: .translationModel)
                .first(where: { $0.selectionID == .remoteLLM(.ollama) })
        )

        XCTAssertTrue(entry.isSelectable)
        XCTAssertEqual(entry.statusText, AppLocalization.localizedString("Configured"))
        XCTAssertEqual(builder.llmSelectionSummary(.remoteLLM(.ollama)), "Ollama · qwen3")
    }

    func testOMLXRemoteEntryIsSelectableWithoutAPIKey() throws {
        let remoteLLMConfigurations = RemoteModelConfigurationStore.saveConfigurations([
            RemoteLLMProvider.omlx.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.omlx.rawValue,
                model: "qwen3",
                endpoint: "http://localhost:8000/v1"
            )
        ])

        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(translationModel: .remoteLLM(.omlx)),
            remoteLLMConfigurationsRaw: remoteLLMConfigurations
        )

        let entry = try XCTUnwrap(
            builder.entries(for: .translationModel)
                .first(where: { $0.selectionID == .remoteLLM(.omlx) })
        )

        XCTAssertTrue(entry.isSelectable)
        XCTAssertEqual(entry.statusText, AppLocalization.localizedString("Configured"))
        XCTAssertEqual(builder.llmSelectionSummary(.remoteLLM(.omlx)), "oMLX · qwen3")
    }

    func testASRSelectorEntryDisplaysSupportsPrimaryLanguageTag() throws {
        let repo = "mlx-community/Qwen3-ASR-0.6B-4bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(repo)),
            primaryUserLanguageCode: "zh-Hans"
        )

        let entry = try XCTUnwrap(
            builder.entries(for: .transcriptionASR)
                .first(where: { $0.selectionID == .mlx(repo) })
        )

        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Supports Primary Language")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Does Not Support Primary Language")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Multilingual")))
    }

    func testASRSelectorEntryDisplaysDoesNotSupportPrimaryLanguageTag() throws {
        let repo = "mlx-community/parakeet-tdt-0.6b-v3"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(repo)),
            primaryUserLanguageCode: "zh-Hans"
        )

        let entry = try XCTUnwrap(
            builder.entries(for: .transcriptionASR)
                .first(where: { $0.selectionID == .mlx(repo) })
        )

        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Does Not Support Primary Language")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Supports Primary Language")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Multilingual")))
    }

    func testLLMSelectorUsesCuratedRatingAndTags() throws {
        let repo = "mlx-community/MiniCPM4-8B-4bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(translationModel: .localLLM(repo))
        )

        let entry = try XCTUnwrap(
            builder.entries(for: .translationModel)
                .first(where: { $0.selectionID == .localLLM(repo) })
        )

        XCTAssertEqual(entry.ratingText, "4.8")
        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Accurate")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Fast")))
    }

    func testMLXSelectorUsesCuratedRatingAndTags() throws {
        let repo = "mlx-community/GLM-ASR-Nano-2512-4bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(repo))
        )

        let entry = try XCTUnwrap(
            builder.entries(for: .transcriptionASR)
                .first(where: { $0.selectionID == .mlx(repo) })
        )

        XCTAssertEqual(entry.ratingText, "4.1")
        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Fast")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Accurate")))
    }

    func testQwen3SelectorShowsRealtimeTag() throws {
        let repo = "mlx-community/Qwen3-ASR-0.6B-4bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(repo))
        )

        let entry = try XCTUnwrap(
            builder.entries(for: .transcriptionASR)
                .first(where: { $0.selectionID == .mlx(repo) })
        )

        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Realtime")))
    }

    func testWhisperSelectorUsesCuratedRatingAndTags() throws {
        let modelID = "medium"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .whisper(modelID))
        )

        let entry = try XCTUnwrap(
            builder.entries(for: .transcriptionASR)
                .first(where: { $0.selectionID == .whisper(modelID) })
        )

        XCTAssertEqual(entry.ratingText, "4.7")
        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Accurate")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Fast")))
    }

    func testSelectorEntriesShowRecommendedBadgesForTargetedSinglesAndProviders() throws {
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                transcriptionASR: .mlx("mlx-community/SenseVoiceSmall"),
                translationModel: .remoteLLM(.deepseek)
            )
        )

        let asrEntries = builder.entries(for: .transcriptionASR)
        let llmEntries = builder.entries(for: .translationModel)
        let recommended = AppLocalization.localizedString("Recommended")

        let senseVoice = try XCTUnwrap(
            asrEntries.first(where: { $0.selectionID == .mlx("mlx-community/SenseVoiceSmall") })
        )
        let doubaoASR = try XCTUnwrap(
            asrEntries.first(where: { $0.selectionID == .remoteASR(.doubaoASR) })
        )
        let stepFunASR = try XCTUnwrap(
            asrEntries.first(where: { $0.selectionID == .remoteASR(.stepFunASR) })
        )
        let deepSeek = try XCTUnwrap(
            llmEntries.first(where: { $0.selectionID == .remoteLLM(.deepseek) })
        )
        let ollama = try XCTUnwrap(
            llmEntries.first(where: { $0.selectionID == .remoteLLM(.ollama) })
        )
        let omlx = try XCTUnwrap(
            llmEntries.first(where: { $0.selectionID == .remoteLLM(.omlx) })
        )
        let aliyun = try XCTUnwrap(
            llmEntries.first(where: { $0.selectionID == .remoteLLM(.aliyunBailian) })
        )

        XCTAssertEqual(senseVoice.badgeText, recommended)
        XCTAssertEqual(doubaoASR.badgeText, recommended)
        XCTAssertEqual(stepFunASR.badgeText, recommended)
        XCTAssertEqual(deepSeek.badgeText, recommended)
        XCTAssertEqual(ollama.badgeText, recommended)
        XCTAssertEqual(omlx.badgeText, recommended)
        XCTAssertEqual(aliyun.badgeText, recommended)
    }

    func testSelectorGroupedFamiliesShowRecommendedBadgesForQwenASRAndGemma() throws {
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                transcriptionASR: .mlx("mlx-community/Qwen3-ASR-0.6B-4bit"),
                translationModel: .localLLM("mlx-community/gemma-2-2b-it-4bit")
            )
        )

        let asrGroups = LocalModelSeriesGrouping.featureSelectorItems(
            from: builder.entries(for: .transcriptionASR),
            selectedID: .mlx("mlx-community/Qwen3-ASR-0.6B-4bit")
        )
        let llmGroups = LocalModelSeriesGrouping.featureSelectorItems(
            from: builder.entries(for: .translationModel),
            selectedID: .localLLM("mlx-community/gemma-2-2b-it-4bit")
        )
        let recommended = AppLocalization.localizedString("Recommended")

        let qwenGroup = try XCTUnwrap(
            asrGroups.compactMap { item -> FeatureModelSelectorGroupSection? in
                guard case .group(let group) = item, group.title == "Qwen3-ASR" else { return nil }
                return group
            }.first
        )
        let gemmaGroup = try XCTUnwrap(
            llmGroups.compactMap { item -> FeatureModelSelectorGroupSection? in
                guard case .group(let group) = item, group.title == "Gemma" else { return nil }
                return group
            }.first
        )

        XCTAssertEqual(qwenGroup.badgeText, recommended)
        XCTAssertEqual(gemmaGroup.badgeText, recommended)
    }

    private func makeBuilder(
        featureSettings: FeatureSettings,
        remoteASRConfigurationsRaw: String = "",
        remoteLLMConfigurationsRaw: String = "",
        primaryUserLanguageCode: String? = "en"
    ) -> FeatureModelCatalogBuilder {
        FeatureModelCatalogBuilder(
            mlxModelManager: TestModelManagers.mlx,
            whisperModelManager: TestModelManagers.whisper,
            customLLMManager: TestModelManagers.customLLM,
            featureSettings: featureSettings,
            remoteASRProviderConfigurationsRaw: remoteASRConfigurationsRaw,
            remoteLLMProviderConfigurationsRaw: remoteLLMConfigurationsRaw,
            appleIntelligenceAvailable: true,
            primaryUserLanguageCode: primaryUserLanguageCode
        )
    }

    private func makeFeatureSettings(
        transcriptionASR: FeatureModelSelectionID = .dictation,
        transcriptionLLM: FeatureModelSelectionID = .localLLM(CustomLLMModelManager.defaultModelRepo),
        translationASR: FeatureModelSelectionID = .dictation,
        translationModel: FeatureModelSelectionID = .localLLM(CustomLLMModelManager.defaultModelRepo),
        translationTarget: TranslationTargetLanguage = .english,
        rewriteASR: FeatureModelSelectionID = .dictation,
        rewriteLLM: FeatureModelSelectionID = .localLLM(CustomLLMModelManager.defaultModelRepo)
    ) -> FeatureSettings {
        FeatureSettings(
            transcription: .init(
                asrSelectionID: transcriptionASR,
                llmEnabled: true,
                llmSelectionID: transcriptionLLM,
                prompt: AppPreferenceKey.defaultEnhancementPrompt
            ),
            translation: .init(
                asrSelectionID: translationASR,
                modelSelectionID: translationModel,
                targetLanguageRawValue: translationTarget.rawValue,
                prompt: AppPreferenceKey.defaultTranslationPrompt
            ),
            rewrite: .init(
                asrSelectionID: rewriteASR,
                llmSelectionID: rewriteLLM,
                prompt: AppPreferenceKey.defaultRewritePrompt,
                appEnhancementEnabled: true
            )
        )
    }
}

@MainActor
private enum TestModelManagers {
    static let mlx = MLXModelManager(modelRepo: MLXModelManager.defaultModelRepo)
    static let whisper = WhisperKitModelManager(
        modelID: WhisperKitModelManager.defaultModelID,
        hubBaseURL: URL(string: "https://huggingface.co")!
    )
    static let customLLM = CustomLLMModelManager(modelRepo: CustomLLMModelManager.defaultModelRepo)
}

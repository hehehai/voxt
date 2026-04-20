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
                meetingModel: "qwen3-asr-flash-filetrans",
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
                translationModel: .remoteLLM(.openAI),
                meetingASR: .remoteASR(.aliyunBailianASR),
                meetingSummary: .remoteLLM(.openAI)
            ),
            remoteASRConfigurationsRaw: remoteASRConfigurations,
            remoteLLMConfigurationsRaw: remoteLLMConfigurations
        )

        let meetingASREntry = try XCTUnwrap(
            builder.entries(for: .meetingASR)
                .first(where: { $0.selectionID == .remoteASR(.aliyunBailianASR) })
        )
        let translationLLMEntry = try XCTUnwrap(
            builder.entries(for: .translationModel)
                .first(where: { $0.selectionID == .remoteLLM(.openAI) })
        )

        XCTAssertTrue(meetingASREntry.isSelectable)
        XCTAssertTrue(meetingASREntry.filterTags.contains(AppLocalization.localizedString("Configured")))
        XCTAssertTrue(meetingASREntry.usageLocations.contains(AppLocalization.localizedString("Meeting")))

        XCTAssertTrue(translationLLMEntry.isSelectable)
        XCTAssertTrue(translationLLMEntry.displayTags.contains(AppLocalization.localizedString("Configured")))
        XCTAssertTrue(translationLLMEntry.usageLocations.contains(AppLocalization.localizedString("Translation")))
        XCTAssertEqual(builder.llmSelectionSummary(.remoteLLM(.openAI)), "OpenAI · gpt-5.2")
        XCTAssertEqual(builder.asrSelectionSummary(.remoteASR(.aliyunBailianASR)), "Aliyun Bailian ASR · fun-asr-realtime")
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
        rewriteLLM: FeatureModelSelectionID = .localLLM(CustomLLMModelManager.defaultModelRepo),
        meetingASR: FeatureModelSelectionID = .dictation,
        meetingSummary: FeatureModelSelectionID = .localLLM(CustomLLMModelManager.defaultModelRepo)
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
                prompt: AppPreferenceKey.defaultTranslationPrompt,
                replaceSelectedText: true
            ),
            rewrite: .init(
                asrSelectionID: rewriteASR,
                llmSelectionID: rewriteLLM,
                prompt: AppPreferenceKey.defaultRewritePrompt,
                appEnhancementEnabled: true
            ),
            meeting: .init(
                enabled: true,
                asrSelectionID: meetingASR,
                summaryModelSelectionID: meetingSummary,
                summaryPrompt: AppPreferenceKey.defaultMeetingSummaryPrompt,
                summaryAutoGenerate: true,
                realtimeTranslateEnabled: false,
                realtimeTargetLanguageRawValue: "",
                showOverlayInScreenShare: false
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

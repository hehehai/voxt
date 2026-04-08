import XCTest
@testable import Voxt

@MainActor
final class ModelCatalogBuilderTests: XCTestCase {
    func testASRCatalogIncludesDirectDictationSettingsEntry() throws {
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                transcriptionASR: .dictation
            )
        )

        let directDictation = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == FeatureModelSelectionID.dictation.rawValue })
        )

        XCTAssertEqual(directDictation.engine, AppLocalization.localizedString("System ASR"))
        XCTAssertEqual(directDictation.primaryAction?.title, AppLocalization.localizedString("Settings"))
        XCTAssertTrue(directDictation.usageLocations.contains(AppLocalization.localizedString("Transcription")))
        XCTAssertTrue(directDictation.displayTags.contains(AppLocalization.localizedString("In Use")))
    }

    func testConfiguredRemoteASREntryShowsNeedsSetupBadgeWhenProviderHasConfigurationIssue() throws {
        let remoteASRConfigurations: [String: RemoteProviderConfiguration] = [
            RemoteASRProvider.aliyunBailianASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
                model: "fun-asr-realtime",
                endpoint: "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription",
                apiKey: "token"
            )
        ]
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                meetingASR: .remoteASR(.aliyunBailianASR)
            ),
            remoteASRConfigurations: remoteASRConfigurations,
            hasIssue: { scope in
                if case .remoteASRProvider(.aliyunBailianASR) = scope {
                    return true
                }
                return false
            }
        )

        let entry = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "remote-asr:\(RemoteASRProvider.aliyunBailianASR.rawValue)" })
        )

        XCTAssertEqual(entry.badgeText, AppLocalization.localizedString("Needs Setup"))
        XCTAssertTrue(entry.filterTags.contains(AppLocalization.localizedString("Configured")))
        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("In Use")))
        XCTAssertEqual(entry.primaryAction?.title, AppLocalization.localizedString("Configure"))
    }

    func testConfiguredRemoteLLMEntryShowsConfiguredTagAndUsage() throws {
        let remoteLLMConfigurations: [String: RemoteProviderConfiguration] = [
            RemoteLLMProvider.openAI.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "https://example.com/v1",
                apiKey: "secret"
            )
        ]
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                translationModel: .remoteLLM(.openAI)
            ),
            remoteLLMConfigurations: remoteLLMConfigurations
        )

        let entry = try XCTUnwrap(
            builder.llmEntries().first(where: { $0.id == "remote-llm:\(RemoteLLMProvider.openAI.rawValue)" })
        )

        XCTAssertTrue(entry.filterTags.contains(AppLocalization.localizedString("Configured")))
        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("In Use")))
        XCTAssertTrue(entry.usageLocations.contains(AppLocalization.localizedString("Translation")))
        XCTAssertEqual(entry.sizeText, "gpt-5.2")
        XCTAssertEqual(entry.primaryAction?.title, AppLocalization.localizedString("Configure"))
    }

    private func makeBuilder(
        featureSettings: FeatureSettings,
        remoteASRConfigurations: [String: RemoteProviderConfiguration] = [:],
        remoteLLMConfigurations: [String: RemoteProviderConfiguration] = [:],
        hasIssue: @escaping (ConfigurationTransferManager.MissingConfigurationIssue.Scope) -> Bool = { _ in false }
    ) -> ModelCatalogBuilder {
        ModelCatalogBuilder(
            mlxModelManager: TestModelManagers.mlx,
            whisperModelManager: TestModelManagers.whisper,
            customLLMManager: TestModelManagers.customLLM,
            remoteASRConfigurations: remoteASRConfigurations,
            remoteLLMConfigurations: remoteLLMConfigurations,
            featureSettings: featureSettings,
            hasIssue: hasIssue,
            modelStatusText: { _ in "" },
            whisperModelStatusText: { _ in "" },
            customLLMStatusText: { _ in "" },
            customLLMBadgeText: { _ in nil },
            remoteASRStatusText: { _, _ in "" },
            remoteLLMBadgeText: { _ in nil },
            isDownloadingModel: { _ in false },
            isAnotherModelDownloading: { _ in false },
            isDownloadingWhisperModel: { _ in false },
            isAnotherWhisperModelDownloading: { _ in false },
            isDownloadingCustomLLM: { _ in false },
            isAnotherCustomLLMDownloading: { _ in false },
            downloadModel: { _ in },
            deleteModel: { _ in },
            openMLXModelDirectory: { _ in },
            downloadWhisperModel: { _ in },
            deleteWhisperModel: { _ in },
            openWhisperModelDirectory: { _ in },
            presentWhisperSettings: {},
            downloadCustomLLM: { _ in },
            deleteCustomLLM: { _ in },
            openCustomLLMModelDirectory: { _ in },
            configureASRProvider: { _ in },
            configureLLMProvider: { _ in },
            showASRHintTarget: { _ in }
        )
    }

    private func makeFeatureSettings(
        transcriptionASR: FeatureModelSelectionID = .dictation,
        translationModel: FeatureModelSelectionID = .localLLM(CustomLLMModelManager.defaultModelRepo),
        meetingASR: FeatureModelSelectionID = .dictation
    ) -> FeatureSettings {
        FeatureSettings(
            transcription: .init(
                asrSelectionID: transcriptionASR,
                llmEnabled: false,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultEnhancementPrompt
            ),
            translation: .init(
                asrSelectionID: .dictation,
                modelSelectionID: translationModel,
                targetLanguageRawValue: TranslationTargetLanguage.english.rawValue,
                prompt: AppPreferenceKey.defaultTranslationPrompt,
                replaceSelectedText: true
            ),
            rewrite: .init(
                asrSelectionID: .dictation,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultRewritePrompt,
                appEnhancementEnabled: false
            ),
            meeting: .init(
                enabled: true,
                asrSelectionID: meetingASR,
                summaryModelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
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

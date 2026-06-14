import XCTest
@testable import Voxt

@MainActor
final class ModelCatalogBuilderTests: XCTestCase {
    func testModelCatalogTagPriorityDoesNotExposeMultilingualFilter() {
        XCTAssertFalse(ModelCatalogTag.priority.contains(AppLocalization.localizedString("Multilingual")))
    }

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
                transcriptionASR: .remoteASR(.aliyunBailianASR)
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

    func testMultilingualMLXModelDisplaysSupportsPrimaryLanguageTag() throws {
        let repo = "mlx-community/Qwen3-ASR-0.6B-4bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(repo)),
            primaryUserLanguageCode: "zh-Hans"
        )

        let entry = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "mlx:\(repo)" })
        )

        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Supports Primary Language")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Does Not Support Primary Language")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Multilingual")))
    }

    func testEnglishOnlyMLXModelDisplaysDoesNotSupportPrimaryLanguageTag() throws {
        let repo = "mlx-community/parakeet-tdt-0.6b-v3"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(repo)),
            primaryUserLanguageCode: "zh-Hans"
        )

        let entry = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "mlx:\(repo)" })
        )

        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Does Not Support Primary Language")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Supports Primary Language")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Multilingual")))
    }

    func testMLXCatalogShowsPauseForDownloadingNonSelectedModel() throws {
        let selectedRepo = "mlx-community/parakeet-tdt-0.6b-v3"
        let downloadingRepo = "mlx-community/Qwen3-ASR-0.6B-4bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(selectedRepo)),
            isDownloadingModel: { repo in
                MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(downloadingRepo)
            }
        )

        let entry = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "mlx:\(downloadingRepo)" })
        )

        XCTAssertEqual(entry.primaryAction?.title, AppLocalization.localizedString("Pause"))
    }

    func testMLXCatalogPauseActionTargetsDownloadingRepo() throws {
        let selectedRepo = "mlx-community/parakeet-tdt-0.6b-v3"
        let downloadingRepo = "mlx-community/Qwen3-ASR-0.6B-4bit"
        var pausedRepo: String?
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(selectedRepo)),
            isDownloadingModel: { repo in
                MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(downloadingRepo)
            },
            pauseModelDownload: { pausedRepo = $0 }
        )

        let entry = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "mlx:\(downloadingRepo)" })
        )
        let action = try XCTUnwrap(entry.primaryAction)
        action.handler()

        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo(pausedRepo ?? ""),
            MLXModelManager.canonicalModelRepo(downloadingRepo)
        )
    }

    func testMLXCatalogCancelActionTargetsDownloadingRepo() throws {
        let selectedRepo = "mlx-community/parakeet-tdt-0.6b-v3"
        let downloadingRepo = "mlx-community/Qwen3-ASR-0.6B-4bit"
        var cancelledRepo: String?
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(selectedRepo)),
            isDownloadingModel: { repo in
                MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(downloadingRepo)
            },
            cancelModelDownload: { cancelledRepo = $0 }
        )

        let entry = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "mlx:\(downloadingRepo)" })
        )
        let cancelAction = try XCTUnwrap(
            entry.secondaryActions.first(where: { $0.title == AppLocalization.localizedString("Cancel") })
        )
        cancelAction.handler()

        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo(cancelledRepo ?? ""),
            MLXModelManager.canonicalModelRepo(downloadingRepo)
        )
    }

    func testCustomLLMCatalogShowsPauseForDownloadingNonSelectedModel() throws {
        let selectedRepo = "mlx-community/Qwen3-8B-4bit"
        let downloadingRepo = "mlx-community/Qwen3-4B-4bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(translationModel: .localLLM(selectedRepo)),
            isDownloadingCustomLLM: { repo in
                repo == downloadingRepo
            }
        )

        let entry = try XCTUnwrap(
            builder.llmEntries().first(where: { $0.id == "local-llm:\(downloadingRepo)" })
        )

        XCTAssertEqual(entry.primaryAction?.title, AppLocalization.localizedString("Pause"))
    }

    func testCustomLLMCatalogInstalledModelIncludesConfigureAction() throws {
        let repo = "mlx-community/Qwen3.5-4B-OptiQ-4bit"
        var configuredRepo: String?
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(translationModel: .localLLM(repo)),
            isCustomLLMInstalled: { candidate in
                CustomLLMModelManager.canonicalModelRepo(candidate) == CustomLLMModelManager.canonicalModelRepo(repo)
            },
            configureCustomLLMGeneration: { configuredRepo = $0 }
        )

        let entry = try XCTUnwrap(
            builder.llmEntries().first(where: { $0.id == "local-llm:\(repo)" })
        )
        let action = try XCTUnwrap(
            entry.secondaryActions.first(where: { $0.title == AppLocalization.localizedString("Configure") })
        )
        action.handler()

        XCTAssertEqual(
            CustomLLMModelManager.canonicalModelRepo(configuredRepo ?? ""),
            CustomLLMModelManager.canonicalModelRepo(repo)
        )
    }

    func testCustomLLMCatalogUninstalledModelDoesNotIncludeConfigureAction() throws {
        let repo = "mlx-community/Qwen3.5-4B-OptiQ-4bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(translationModel: .localLLM(repo)),
            isCustomLLMInstalled: { _ in false }
        )

        let entry = try XCTUnwrap(
            builder.llmEntries().first(where: { $0.id == "local-llm:\(repo)" })
        )

        XCTAssertFalse(entry.secondaryActions.contains(where: { $0.title == AppLocalization.localizedString("Configure") }))
    }

    func testCustomLLMCatalogUsesCuratedRatingAndTags() throws {
        let repo = "mlx-community/Qwen3.5-4B-OptiQ-4bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(translationModel: .localLLM(repo))
        )

        let entry = try XCTUnwrap(
            builder.llmEntries().first(where: { $0.id == "local-llm:\(repo)" })
        )

        XCTAssertEqual(entry.ratingText, "4.8")
        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Balanced")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Accurate")))
    }

    func testMLXCatalogUsesCuratedRatingAndTags() throws {
        let repo = "mlx-community/Voxtral-Mini-4B-Realtime-6bit"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .mlx(repo))
        )

        let entry = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "mlx:\(repo)" })
        )

        XCTAssertEqual(entry.ratingText, "4.7")
        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Realtime")))
        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Balanced")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Fast")))
    }

    func testWhisperCatalogUsesCuratedRatingAndTags() throws {
        let modelID = "base"
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(transcriptionASR: .whisper(modelID))
        )

        let entry = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "whisper:\(modelID)" })
        )

        XCTAssertEqual(entry.ratingText, "4.3")
        XCTAssertTrue(entry.displayTags.contains(AppLocalization.localizedString("Balanced")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Fast")))
        XCTAssertFalse(entry.displayTags.contains(AppLocalization.localizedString("Accurate")))
    }

    func testCatalogShowsRecommendedBadgesForTargetedSingleEntriesAndProviders() throws {
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                transcriptionASR: .mlx("mlx-community/SenseVoiceSmall"),
                translationModel: .remoteLLM(.deepseek)
            )
        )

        let senseVoice = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "mlx:mlx-community/SenseVoiceSmall" })
        )
        let doubaoASR = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "remote-asr:\(RemoteASRProvider.doubaoASR.rawValue)" })
        )
        let stepFunASR = try XCTUnwrap(
            builder.asrEntries().first(where: { $0.id == "remote-asr:\(RemoteASRProvider.stepFunASR.rawValue)" })
        )
        let deepSeek = try XCTUnwrap(
            builder.llmEntries().first(where: { $0.id == "remote-llm:\(RemoteLLMProvider.deepseek.rawValue)" })
        )
        let ollama = try XCTUnwrap(
            builder.llmEntries().first(where: { $0.id == "remote-llm:\(RemoteLLMProvider.ollama.rawValue)" })
        )
        let omlx = try XCTUnwrap(
            builder.llmEntries().first(where: { $0.id == "remote-llm:\(RemoteLLMProvider.omlx.rawValue)" })
        )
        let aliyun = try XCTUnwrap(
            builder.llmEntries().first(where: { $0.id == "remote-llm:\(RemoteLLMProvider.aliyunBailian.rawValue)" })
        )

        let recommended = AppLocalization.localizedString("Recommended")
        XCTAssertEqual(senseVoice.badgeText, recommended)
        XCTAssertEqual(doubaoASR.badgeText, recommended)
        XCTAssertEqual(stepFunASR.badgeText, recommended)
        XCTAssertEqual(deepSeek.badgeText, recommended)
        XCTAssertEqual(ollama.badgeText, recommended)
        XCTAssertEqual(omlx.badgeText, recommended)
        XCTAssertEqual(aliyun.badgeText, recommended)
    }

    func testCatalogShowsRecommendedBadgeForQwenASRAndGemmaGroups() throws {
        let builder = makeBuilder(
            featureSettings: makeFeatureSettings(
                transcriptionASR: .mlx("mlx-community/Qwen3-ASR-0.6B-4bit"),
                translationModel: .localLLM("mlx-community/gemma-2-2b-it-4bit")
            )
        )

        let asrGroups = LocalModelSeriesGrouping.modelCatalogItems(from: builder.asrEntries())
        let llmGroups = LocalModelSeriesGrouping.modelCatalogItems(from: builder.llmEntries())
        let recommended = AppLocalization.localizedString("Recommended")

        let qwenGroup = try XCTUnwrap(
            asrGroups.compactMap { item -> ModelCatalogGroupSection? in
                guard case .group(let group) = item, group.title == "Qwen3-ASR" else { return nil }
                return group
            }.first
        )
        let gemmaGroup = try XCTUnwrap(
            llmGroups.compactMap { item -> ModelCatalogGroupSection? in
                guard case .group(let group) = item, group.title == "Gemma" else { return nil }
                return group
            }.first
        )

        XCTAssertEqual(qwenGroup.badgeText, recommended)
        XCTAssertEqual(gemmaGroup.badgeText, recommended)
    }

    private func makeBuilder(
        featureSettings: FeatureSettings,
        remoteASRConfigurations: [String: RemoteProviderConfiguration] = [:],
        remoteLLMConfigurations: [String: RemoteProviderConfiguration] = [:],
        primaryUserLanguageCode: String? = "en",
        hasIssue: @escaping (ConfigurationTransferManager.MissingConfigurationIssue.Scope) -> Bool = { _ in false },
        isDownloadingModel: @escaping (String) -> Bool = { _ in false },
        isPausedModel: @escaping (String) -> Bool = { _ in false },
        isDownloadingWhisperModel: @escaping (String) -> Bool = { _ in false },
        isPausedWhisperModel: @escaping (String) -> Bool = { _ in false },
        isAnotherWhisperModelDownloading: @escaping (String) -> Bool = { _ in false },
        isDownloadingCustomLLM: @escaping (String) -> Bool = { _ in false },
        isPausedCustomLLM: @escaping (String) -> Bool = { _ in false },
        isAnotherCustomLLMDownloading: @escaping (String) -> Bool = { _ in false },
        isCustomLLMInstalled: @escaping (String) -> Bool = { _ in false },
        isUninstallingModel: @escaping (String) -> Bool = { _ in false },
        isUninstallingWhisperModel: @escaping (String) -> Bool = { _ in false },
        isUninstallingCustomLLM: @escaping (String) -> Bool = { _ in false },
        pauseModelDownload: @escaping (String) -> Void = { _ in },
        cancelModelDownload: @escaping (String) -> Void = { _ in },
        configureCustomLLMGeneration: @escaping (String) -> Void = { _ in }
    ) -> ModelCatalogBuilder {
        let performAction: (LocalModelInstallTarget, LocalModelInstallActionKind) -> Void = { target, action in
            switch (target, action) {
            case let (.mlx(repo), .pause):
                pauseModelDownload(repo)
            case let (.mlx(repo), .cancel):
                cancelModelDownload(repo)
            case let (.customLLM(repo), .configure):
                configureCustomLLMGeneration(repo)
            default:
                break
            }
        }

        let mlxInstallSnapshot: (String) -> LocalModelInstallSnapshot = { repo in
            let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
            let isDownloading = isDownloadingModel(canonicalRepo)
            let isPaused = isPausedModel(canonicalRepo)
            let isUninstalling = isUninstallingModel(canonicalRepo)
            let isInstalled = !isDownloading && !isPaused && !isUninstalling
            let state: LocalModelInstallState
            if isUninstalling {
                state = .uninstalling
            } else if isDownloading {
                state = .downloading
            } else if isPaused {
                state = .paused
            } else if isInstalled {
                state = .installed
            } else {
                state = .installable(isEnabled: true)
            }
            return LocalModelInstallSnapshot(
                target: .mlx(canonicalRepo),
                state: state,
                isInstalled: isInstalled,
                isCurrentSelection: featureSettings.transcription.asrSelectionID == .mlx(canonicalRepo),
                statusText: "",
                badgeText: nil,
                downloadStatus: nil,
                canOpenLocation: isInstalled,
                canConfigure: false,
                configureActionTitle: nil
            )
        }

        let whisperInstallSnapshot: (String) -> LocalModelInstallSnapshot = { modelID in
            let canonicalModelID = WhisperKitModelManager.canonicalModelID(modelID)
            let isDownloading = isDownloadingWhisperModel(canonicalModelID)
            let isPaused = isPausedWhisperModel(canonicalModelID)
            let isUninstalling = isUninstallingWhisperModel(canonicalModelID)
            let isInstalled = !isDownloading && !isPaused && !isUninstalling
            let state: LocalModelInstallState
            if isUninstalling {
                state = .uninstalling
            } else if isDownloading {
                state = .downloading
            } else if isPaused {
                state = .paused
            } else if isInstalled {
                state = .installed
            } else {
                state = .installable(isEnabled: !isAnotherWhisperModelDownloading(canonicalModelID))
            }
            return LocalModelInstallSnapshot(
                target: .whisper(canonicalModelID),
                state: state,
                isInstalled: isInstalled,
                isCurrentSelection: featureSettings.transcription.asrSelectionID == .whisper(canonicalModelID),
                statusText: "",
                badgeText: nil,
                downloadStatus: nil,
                canOpenLocation: isInstalled,
                canConfigure: false,
                configureActionTitle: nil
            )
        }

        let customLLMInstallSnapshot: (String) -> LocalModelInstallSnapshot = { repo in
            let canonicalRepo = CustomLLMModelManager.canonicalModelRepo(repo)
            let isDownloading = isDownloadingCustomLLM(canonicalRepo)
            let isPaused = isPausedCustomLLM(canonicalRepo)
            let isUninstalling = isUninstallingCustomLLM(canonicalRepo)
            let isInstalled = !isDownloading && !isPaused && !isUninstalling && isCustomLLMInstalled(canonicalRepo)
            let state: LocalModelInstallState
            if isUninstalling {
                state = .uninstalling
            } else if isDownloading {
                state = .downloading
            } else if isPaused {
                state = .paused
            } else if isInstalled {
                state = .installed
            } else {
                state = .installable(isEnabled: !isAnotherCustomLLMDownloading(canonicalRepo))
            }
            return LocalModelInstallSnapshot(
                target: .customLLM(canonicalRepo),
                state: state,
                isInstalled: isInstalled,
                isCurrentSelection: featureSettings.translation.modelSelectionID == .localLLM(canonicalRepo),
                statusText: "",
                badgeText: nil,
                downloadStatus: nil,
                canOpenLocation: isInstalled,
                canConfigure: isInstalled,
                configureActionTitle: isInstalled ? AppLocalization.localizedString("Configure") : nil
            )
        }

        return ModelCatalogBuilder(
            mlxModelManager: TestModelManagers.mlx,
            whisperModelManager: TestModelManagers.whisper,
            customLLMManager: TestModelManagers.customLLM,
            remoteASRConfigurations: remoteASRConfigurations,
            remoteLLMConfigurations: remoteLLMConfigurations,
            featureSettings: featureSettings,
            hasIssue: hasIssue,
            customLLMBadgeText: { _ in nil },
            remoteASRStatusText: { _, _ in "" },
            remoteLLMBadgeText: { _ in nil },
            primaryUserLanguageCode: primaryUserLanguageCode,
            mlxInstallSnapshot: mlxInstallSnapshot,
            whisperInstallSnapshot: whisperInstallSnapshot,
            customLLMInstallSnapshot: customLLMInstallSnapshot,
            catalogPrimaryAction: { snapshot in
                ModelSettingsInstallActionResolver.catalogPrimaryAction(
                    for: snapshot,
                    perform: performAction
                )
            },
            catalogSecondaryActions: { snapshot in
                ModelSettingsInstallActionResolver.catalogSecondaryActions(
                    for: snapshot,
                    perform: performAction
                )
            },
            configureASRProvider: { _ in },
            configureLLMProvider: { _ in },
            showASRHintTarget: { _ in }
        )
    }

    private func makeFeatureSettings(
        transcriptionASR: FeatureModelSelectionID = .dictation,
        translationModel: FeatureModelSelectionID = .localLLM(CustomLLMModelManager.defaultModelRepo)
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
                prompt: AppPreferenceKey.defaultTranslationPrompt
            ),
            rewrite: .init(
                asrSelectionID: .dictation,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultRewritePrompt,
                appEnhancementEnabled: false
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

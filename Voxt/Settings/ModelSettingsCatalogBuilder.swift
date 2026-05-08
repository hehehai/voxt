import SwiftUI

private func localizedModelCatalog(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

@MainActor
struct ModelCatalogBuilder {
    let mlxModelManager: MLXModelManager
    let whisperModelManager: WhisperKitModelManager
    let customLLMManager: CustomLLMModelManager
    let remoteASRConfigurations: [String: RemoteProviderConfiguration]
    let remoteLLMConfigurations: [String: RemoteProviderConfiguration]
    let featureSettings: FeatureSettings
    let hasIssue: (ConfigurationTransferManager.MissingConfigurationIssue.Scope) -> Bool
    let modelStatusText: (String) -> String
    let whisperModelStatusText: (String) -> String
    let customLLMStatusText: (String) -> String
    let customLLMBadgeText: (String) -> String?
    let remoteASRStatusText: (RemoteASRProvider, RemoteProviderConfiguration) -> String
    let remoteLLMBadgeText: (RemoteLLMProvider) -> String?
    let primaryUserLanguageCode: String?
    let isDownloadingModel: (String) -> Bool
    let isPausedModel: (String) -> Bool
    let isAnotherModelDownloading: (String) -> Bool
    let isDownloadingWhisperModel: (String) -> Bool
    let isPausedWhisperModel: (String) -> Bool
    let isAnotherWhisperModelDownloading: (String) -> Bool
    let isDownloadingCustomLLM: (String) -> Bool
    let isPausedCustomLLM: (String) -> Bool
    let isAnotherCustomLLMDownloading: (String) -> Bool
    let isUninstallingModel: (String) -> Bool
    let isUninstallingWhisperModel: (String) -> Bool
    let isUninstallingCustomLLM: (String) -> Bool
    let downloadModel: (String) -> Void
    let cancelModelDownload: (String) -> Void
    let deleteModel: (String) -> Void
    let openMLXModelDirectory: (String) -> Void
    let presentMLXSettings: (String) -> Void
    let downloadWhisperModel: (String) -> Void
    let cancelWhisperDownload: (String) -> Void
    let deleteWhisperModel: (String) -> Void
    let openWhisperModelDirectory: (String) -> Void
    let presentWhisperSettings: () -> Void
    let downloadCustomLLM: (String) -> Void
    let cancelCustomLLMDownload: (String) -> Void
    let deleteCustomLLM: (String) -> Void
    let openCustomLLMModelDirectory: (String) -> Void
    let configureASRProvider: (RemoteASRProvider) -> Void
    let configureLLMProvider: (RemoteLLMProvider) -> Void
    let showASRHintTarget: (ASRHintTarget) -> Void

    func asrEntries() -> [ModelCatalogEntry] {
        var entries = [ModelCatalogEntry]()

        entries.append(dictationASREntry())
        entries.append(contentsOf: mlxASREntries())
        entries.append(contentsOf: whisperASREntries())

        entries.append(contentsOf: RemoteASRProvider.allCases.map { provider in
            let selectionID = FeatureModelSelectionID.remoteASR(provider)
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
                provider: provider,
                stored: remoteASRConfigurations
            )
            let configured = configuration.isConfigured
            let needsMeetingSetup =
                hasIssue(.remoteASRProvider(provider)) ||
                (featureSettings.meeting.enabled &&
                    configured &&
                    RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(provider, configuration: configuration) &&
                    !RemoteASRMeetingConfiguration.hasValidMeetingModel(provider: provider, configuration: configuration))

            return ModelCatalogEntry(
                id: "remote-asr:\(provider.rawValue)",
                title: provider.title,
                engine: localizedModelCatalog("Remote ASR"),
                sizeText: configuration.hasUsableModel ? configuration.model : localizedModelCatalog("Cloud"),
                ratingText: provider == .openAIWhisper ? "4.6" : "4.4",
                filterTags: catalogFilterTags(
                    base: [localizedModelCatalog("Remote")] + remoteASRCatalogTags(for: provider, configuration: configuration),
                    installed: false,
                    requiresConfiguration: true,
                    configured: configured,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localizedModelCatalog("Remote")] + remoteASRCatalogTags(for: provider, configuration: configuration),
                    requiresConfiguration: true,
                    configured: configured,
                    selectionID: selectionID
                ),
                statusText: remoteASRStatusText(provider, configuration),
                usageLocations: usageLocations(for: selectionID),
                badgeText: needsMeetingSetup ? localizedModelCatalog("Needs Setup") : nil,
                primaryAction: ModelTableAction(title: localizedModelCatalog("Configure")) {
                    configureASRProvider(provider)
                },
                secondaryActions: []
            )
        })

        return entries
    }

    func llmEntries() -> [ModelCatalogEntry] {
        var entries = [ModelCatalogEntry]()

        entries.append(contentsOf: CustomLLMModelManager.availableModels.map { model in
            let repo = model.id
            let selectionID = FeatureModelSelectionID.localLLM(repo)
            let isInstalled = customLLMManager.isModelDownloaded(repo: repo)
            let badge = customLLMBadgeText(repo)
            let status = isUninstallingCustomLLM(repo) ? localizedModelCatalog("Uninstalling…") : customLLMStatusText(repo)

            let primaryAction: ModelTableAction?
            let secondaryActions: [ModelTableAction]
            if isUninstallingCustomLLM(repo) {
                primaryAction = ModelTableAction(title: localizedModelCatalog("Uninstalling…"), isEnabled: false) {}
                secondaryActions = []
            } else if isDownloadingCustomLLM(repo) {
                primaryAction = ModelTableAction(title: localizedModelCatalog("Pause")) {
                    customLLMManager.pauseDownload()
                }
                secondaryActions = [
                    ModelTableAction(title: localizedModelCatalog("Cancel"), role: .destructive) {
                        customLLMManager.cancelDownload()
                    }
                ]
            } else if isPausedCustomLLM(repo) {
                primaryAction = ModelTableAction(title: localizedModelCatalog("Continue")) {
                    downloadCustomLLM(repo)
                }
                secondaryActions = [
                    ModelTableAction(title: localizedModelCatalog("Cancel"), role: .destructive) {
                        cancelCustomLLMDownload(repo)
                    }
                ]
            } else if isInstalled {
                primaryAction = ModelTableAction(title: localizedModelCatalog("Uninstall"), role: .destructive) {
                    deleteCustomLLM(repo)
                }
                secondaryActions = [
                    ModelTableAction(title: localizedModelCatalog("Open Location")) {
                        openCustomLLMModelDirectory(repo)
                    }
                ]
            } else {
                primaryAction = ModelTableAction(title: localizedModelCatalog("Install"), isEnabled: !isAnotherCustomLLMDownloading(repo)) {
                    downloadCustomLLM(repo)
                }
                secondaryActions = []
            }

            return ModelCatalogEntry(
                id: "local-llm:\(repo)",
                title: customLLMManager.displayTitle(for: repo),
                engine: localizedModelCatalog("Local LLM"),
                sizeText: isInstalled
                    ? (customLLMManager.cachedModelSizeText(repo: repo) ?? customLLMManager.remoteSizeText(repo: repo))
                    : customLLMManager.remoteSizeText(repo: repo),
                ratingText: CustomLLMModelManager.ratingText(for: repo),
                filterTags: catalogFilterTags(
                    base: [localizedModelCatalog("Local")] + llmCatalogTags(for: repo),
                    installed: isInstalled,
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localizedModelCatalog("Local")] + llmCatalogTags(for: repo),
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                statusText: status,
                usageLocations: usageLocations(for: selectionID),
                badgeText: badge,
                primaryAction: primaryAction,
                secondaryActions: secondaryActions
            )
        })

        entries.append(contentsOf: RemoteLLMProvider.allCases.map { provider in
            let selectionID = FeatureModelSelectionID.remoteLLM(provider)
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            let configured = configuration.isConfigured && configuration.hasUsableModel
            let status = configured ? "" : localizedModelCatalog("Not configured")

            return ModelCatalogEntry(
                id: "remote-llm:\(provider.rawValue)",
                title: provider.title,
                engine: localizedModelCatalog("Remote LLM"),
                sizeText: configuration.hasUsableModel ? configuration.model : localizedModelCatalog("Cloud"),
                ratingText: "4.5",
                filterTags: catalogFilterTags(
                    base: [localizedModelCatalog("Remote")] + remoteLLMCatalogTags(for: provider),
                    installed: false,
                    requiresConfiguration: true,
                    configured: configured,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localizedModelCatalog("Remote")] + remoteLLMCatalogTags(for: provider),
                    requiresConfiguration: true,
                    configured: configured,
                    selectionID: selectionID
                ),
                statusText: status,
                usageLocations: usageLocations(for: selectionID),
                badgeText: remoteLLMBadgeText(provider),
                primaryAction: ModelTableAction(title: localizedModelCatalog("Configure")) {
                    configureLLMProvider(provider)
                },
                secondaryActions: []
            )
        })

        return entries
    }

    func usageLocations(for selectionID: FeatureModelSelectionID) -> [String] {
        var labels = [String]()
        if featureSettings.transcription.asrSelectionID == selectionID ||
            (featureSettings.transcription.llmEnabled && featureSettings.transcription.llmSelectionID == selectionID) {
            labels.append(localizedModelCatalog("Transcription"))
        }
        if featureSettings.translation.asrSelectionID == selectionID ||
            featureSettings.translation.modelSelectionID == selectionID {
            labels.append(localizedModelCatalog("Translation"))
        }
        if featureSettings.rewrite.asrSelectionID == selectionID ||
            featureSettings.rewrite.llmSelectionID == selectionID {
            labels.append(localizedModelCatalog("Rewrite"))
        }
        if featureSettings.meeting.enabled &&
            (featureSettings.meeting.asrSelectionID == selectionID ||
                featureSettings.meeting.summaryModelSelectionID == selectionID) {
            labels.append(localizedModelCatalog("Meeting"))
        }
        return labels
    }

    func catalogFilterTags(
        base: [String],
        installed: Bool,
        requiresConfiguration: Bool,
        configured: Bool,
        selectionID: FeatureModelSelectionID
    ) -> [String] {
        var tags = base
        if installed {
            tags.append(localizedModelCatalog("Installed"))
        }
        if requiresConfiguration && configured {
            tags.append(localizedModelCatalog("Configured"))
        }
        if !usageLocations(for: selectionID).isEmpty {
            tags.append(localizedModelCatalog("In Use"))
        }
        return deduplicatedTags(tags)
    }

    func catalogDisplayTags(
        base: [String],
        requiresConfiguration: Bool,
        configured: Bool,
        selectionID: FeatureModelSelectionID
    ) -> [String] {
        var tags = base.filter { $0 != localizedModelCatalog("Multilingual") }
        if let languageSupportTag = primaryLanguageSupportTag(for: selectionID) {
            tags.append(languageSupportTag)
        }
        if requiresConfiguration && configured {
            tags.append(localizedModelCatalog("Configured"))
        }
        if !usageLocations(for: selectionID).isEmpty {
            tags.append(localizedModelCatalog("In Use"))
        }
        return deduplicatedTags(tags)
    }

    func mlxCatalogTags(for repo: String) -> [String] {
        deduplicatedTags(MLXModelManager.catalogTagKeys(for: repo).map(localizedModelCatalog))
    }

    func whisperCatalogTags(for modelID: String) -> [String] {
        deduplicatedTags(WhisperKitModelManager.catalogTagKeys(for: modelID).map(localizedModelCatalog))
    }

    private func llmCatalogTags(for repo: String) -> [String] {
        deduplicatedTags(CustomLLMModelManager.catalogTagKeys(for: repo).map(localizedModelCatalog))
    }

    private func remoteASRCatalogTags(
        for provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> [String] {
        var tags = [String]()
        switch provider {
        case .openAIWhisper:
            tags.append(localizedModelCatalog("Multilingual"))
        case .doubaoASR:
            tags.append(contentsOf: [localizedModelCatalog("Realtime"), localizedModelCatalog("Multilingual")])
        case .glmASR:
            tags.append(contentsOf: [localizedModelCatalog("Accurate"), localizedModelCatalog("Multilingual")])
        case .aliyunBailianASR:
            tags.append(localizedModelCatalog("Multilingual"))
            if RemoteASRRealtimeSupport.isAliyunRealtimeModel(configuration.model) {
                tags.append(localizedModelCatalog("Realtime"))
            }
        }
        return deduplicatedTags(tags)
    }

    private func remoteLLMCatalogTags(for provider: RemoteLLMProvider) -> [String] {
        switch provider {
        case .lmStudio, .ollama:
            return []
        default:
            return [localizedModelCatalog("Accurate")]
        }
    }

    private func mlxSupportsMultilingual(_ repo: String) -> Bool {
        MLXModelManager.isMultilingualModelRepo(repo)
    }

    private func primaryLanguageSupportTag(for selectionID: FeatureModelSelectionID) -> String? {
        guard let support = supportsPrimaryLanguage(for: selectionID) else { return nil }
        return localizedModelCatalog(support ? "Supports Primary Language" : "Does Not Support Primary Language")
    }

    private func supportsPrimaryLanguage(for selectionID: FeatureModelSelectionID) -> Bool? {
        guard let primaryLanguage = resolvedPrimaryLanguageOption() else { return nil }

        switch selectionID.asrSelection {
        case .dictation:
            return true
        case .mlx(let repo):
            return mlxSupportsPrimaryLanguage(repo, primaryLanguage: primaryLanguage)
        case .whisper:
            return true
        case .remote:
            return true
        case .none:
            return nil
        }
    }

    private func resolvedPrimaryLanguageOption() -> UserMainLanguageOption? {
        guard let primaryUserLanguageCode else { return nil }
        return UserMainLanguageOption.option(for: primaryUserLanguageCode)
    }

    private func mlxSupportsPrimaryLanguage(
        _ repo: String,
        primaryLanguage: UserMainLanguageOption
    ) -> Bool {
        let key = repo.lowercased()
        let baseCode = primaryLanguage.baseLanguageCode

        if key.contains("parakeet") {
            return baseCode == "en"
        }

        if key.contains("glm-asr") {
            return ["zh", "en"].contains(baseCode)
        }

        if key.contains("firered") {
            return ["zh", "en"].contains(baseCode)
        }

        return mlxSupportsMultilingual(repo)
    }

    private func deduplicatedTags(_ tags: [String]) -> [String] {
        Array(NSOrderedSet(array: tags)) as? [String] ?? tags
    }
}

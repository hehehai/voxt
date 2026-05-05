import SwiftUI

private func localized(_ key: String) -> String {
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
    let isAnotherModelDownloading: (String) -> Bool
    let isDownloadingWhisperModel: (String) -> Bool
    let isAnotherWhisperModelDownloading: (String) -> Bool
    let isDownloadingCustomLLM: (String) -> Bool
    let isAnotherCustomLLMDownloading: (String) -> Bool
    let downloadModel: (String) -> Void
    let deleteModel: (String) -> Void
    let openMLXModelDirectory: (String) -> Void
    let presentMLXSettings: (String) -> Void
    let downloadWhisperModel: (String) -> Void
    let deleteWhisperModel: (String) -> Void
    let openWhisperModelDirectory: (String) -> Void
    let presentWhisperSettings: () -> Void
    let downloadCustomLLM: (String) -> Void
    let deleteCustomLLM: (String) -> Void
    let openCustomLLMModelDirectory: (String) -> Void
    let configureASRProvider: (RemoteASRProvider) -> Void
    let configureLLMProvider: (RemoteLLMProvider) -> Void
    let showASRHintTarget: (ASRHintTarget) -> Void

    func asrEntries() -> [ModelCatalogEntry] {
        var entries = [ModelCatalogEntry]()

        entries.append(
            ModelCatalogEntry(
                id: FeatureModelSelectionID.dictation.rawValue,
                title: localized("Direct Dictation"),
                engine: localized("System ASR"),
                sizeText: localized("Built-in"),
                ratingText: "3.4",
                filterTags: catalogFilterTags(
                    base: [localized("Local"), localized("Built-in"), localized("Fast")],
                    installed: true,
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: .dictation
                ),
                displayTags: catalogDisplayTags(
                    base: [localized("Local"), localized("Built-in"), localized("Fast")],
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: .dictation
                ),
                statusText: "",
                usageLocations: usageLocations(for: .dictation),
                badgeText: nil,
                primaryAction: ModelTableAction(title: localized("Settings")) {
                    showASRHintTarget(.dictation)
                },
                secondaryActions: []
            )
        )

        entries.append(contentsOf: MLXModelManager.availableModels.map { model in
            let repo = MLXModelManager.canonicalModelRepo(model.id)
            let selectionID = FeatureModelSelectionID.mlx(repo)
            let isInstalled = mlxModelManager.isModelDownloaded(repo: repo)
            let badge = hasIssue(.mlxModel(repo)) ? localized("Needs Setup") : nil
            let status = modelStatusText(repo)

            let primaryAction: ModelTableAction?
            var secondaryActions = [ModelTableAction]()
            if isDownloadingModel(repo) {
                primaryAction = ModelTableAction(title: localized("Pause")) {
                    mlxModelManager.pauseDownload()
                }
                secondaryActions.append(
                    ModelTableAction(title: localized("Cancel"), role: .destructive) {
                        mlxModelManager.cancelDownload()
                    }
                )
            } else if ModelDownloadStateRouting.isMLXPaused(
                repo: repo,
                managerRepo: mlxModelManager.currentModelRepo,
                state: mlxModelManager.state
            ) {
                primaryAction = ModelTableAction(title: localized("Continue")) {
                    downloadModel(repo)
                }
                secondaryActions.append(
                    ModelTableAction(title: localized("Cancel"), role: .destructive) {
                        mlxModelManager.cancelDownload()
                    }
                )
            } else if isInstalled {
                primaryAction = ModelTableAction(title: localized("Uninstall"), role: .destructive) {
                    deleteModel(repo)
                }
                secondaryActions.append(
                    ModelTableAction(title: localized("Open Location")) {
                        openMLXModelDirectory(repo)
                    }
                )
            } else {
                primaryAction = ModelTableAction(title: localized("Install"), isEnabled: !isAnotherModelDownloading(repo)) {
                    downloadModel(repo)
                }
            }
            secondaryActions.append(
                ModelTableAction(title: localized("Settings")) {
                    presentMLXSettings(repo)
                }
            )

            return ModelCatalogEntry(
                id: "mlx:\(repo)",
                title: mlxModelManager.displayTitle(for: repo),
                engine: localized("MLX Audio"),
                sizeText: isInstalled
                    ? (mlxModelManager.cachedModelSizeText(repo: repo) ?? mlxModelManager.remoteSizeText(repo: repo))
                    : mlxModelManager.remoteSizeText(repo: repo),
                ratingText: MLXModelManager.ratingText(for: repo),
                filterTags: catalogFilterTags(
                    base: [localized("Local")] + mlxCatalogTags(for: repo),
                    installed: isInstalled,
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localized("Local")] + mlxCatalogTags(for: repo),
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

        entries.append(contentsOf: WhisperKitModelManager.availableModels.map { model in
            let modelID = WhisperKitModelManager.canonicalModelID(model.id)
            let selectionID = FeatureModelSelectionID.whisper(modelID)
            let isInstalled = whisperModelManager.isModelDownloaded(id: modelID)
            let badge = hasIssue(.whisperModel(modelID)) ? localized("Needs Setup") : nil
            let status = whisperModelStatusText(modelID)

            let primaryAction: ModelTableAction?
            var secondaryActions = [ModelTableAction]()
            if isDownloadingWhisperModel(modelID) {
                primaryAction = ModelTableAction(title: localized("Pause")) {
                    whisperModelManager.pauseDownload()
                }
                secondaryActions.append(
                    ModelTableAction(title: localized("Cancel"), role: .destructive) {
                        whisperModelManager.cancelDownload()
                    }
                )
            } else if whisperModelManager.activeDownload?.modelID == modelID,
                      whisperModelManager.activeDownload?.isPaused == true {
                primaryAction = ModelTableAction(title: localized("Continue")) {
                    downloadWhisperModel(modelID)
                }
                secondaryActions.append(
                    ModelTableAction(title: localized("Cancel"), role: .destructive) {
                        whisperModelManager.cancelDownload()
                    }
                )
            } else if isInstalled {
                primaryAction = ModelTableAction(title: localized("Uninstall"), role: .destructive) {
                    deleteWhisperModel(modelID)
                }
            } else {
                primaryAction = ModelTableAction(title: localized("Install"), isEnabled: !isAnotherWhisperModelDownloading(modelID)) {
                    downloadWhisperModel(modelID)
                }
            }

            if isInstalled {
                secondaryActions.append(
                    ModelTableAction(title: localized("Open Location")) {
                        openWhisperModelDirectory(modelID)
                    }
                )
            }
            secondaryActions.append(
                ModelTableAction(title: localized("Whisper Settings")) {
                    presentWhisperSettings()
                }
            )

            return ModelCatalogEntry(
                id: "whisper:\(modelID)",
                title: whisperModelManager.displayTitle(for: modelID),
                engine: localized("Whisper"),
                sizeText: isInstalled
                    ? (whisperModelManager.cachedModelSizeText(id: modelID) ?? whisperModelManager.remoteSizeText(id: modelID))
                    : whisperModelManager.remoteSizeText(id: modelID),
                ratingText: WhisperKitModelManager.ratingText(for: modelID),
                filterTags: catalogFilterTags(
                    base: [localized("Local")] + whisperCatalogTags(for: modelID),
                    installed: isInstalled,
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localized("Local")] + whisperCatalogTags(for: modelID),
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
                engine: localized("Remote ASR"),
                sizeText: configuration.hasUsableModel ? configuration.model : localized("Cloud"),
                ratingText: provider == .openAIWhisper ? "4.6" : "4.4",
                filterTags: catalogFilterTags(
                    base: [localized("Remote")] + remoteASRCatalogTags(for: provider, configuration: configuration),
                    installed: false,
                    requiresConfiguration: true,
                    configured: configured,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localized("Remote")] + remoteASRCatalogTags(for: provider, configuration: configuration),
                    requiresConfiguration: true,
                    configured: configured,
                    selectionID: selectionID
                ),
                statusText: remoteASRStatusText(provider, configuration),
                usageLocations: usageLocations(for: selectionID),
                badgeText: needsMeetingSetup ? localized("Needs Setup") : nil,
                primaryAction: ModelTableAction(title: localized("Configure")) {
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
            let status = customLLMStatusText(repo)

            let primaryAction: ModelTableAction?
            let secondaryActions: [ModelTableAction]
            if isDownloadingCustomLLM(repo) {
                primaryAction = ModelTableAction(title: localized("Pause")) {
                    customLLMManager.pauseDownload()
                }
                secondaryActions = [
                    ModelTableAction(title: localized("Cancel"), role: .destructive) {
                        customLLMManager.cancelDownload()
                    }
                ]
            } else if ModelDownloadStateRouting.isCustomLLMPaused(
                repo: repo,
                managerRepo: customLLMManager.currentModelRepo,
                state: customLLMManager.state
            ) {
                primaryAction = ModelTableAction(title: localized("Continue")) {
                    downloadCustomLLM(repo)
                }
                secondaryActions = [
                    ModelTableAction(title: localized("Cancel"), role: .destructive) {
                        customLLMManager.cancelDownload()
                    }
                ]
            } else if isInstalled {
                primaryAction = ModelTableAction(title: localized("Uninstall"), role: .destructive) {
                    deleteCustomLLM(repo)
                }
                secondaryActions = [
                    ModelTableAction(title: localized("Open Location")) {
                        openCustomLLMModelDirectory(repo)
                    }
                ]
            } else {
                primaryAction = ModelTableAction(title: localized("Install"), isEnabled: !isAnotherCustomLLMDownloading(repo)) {
                    downloadCustomLLM(repo)
                }
                secondaryActions = []
            }

            return ModelCatalogEntry(
                id: "local-llm:\(repo)",
                title: customLLMManager.displayTitle(for: repo),
                engine: localized("Local LLM"),
                sizeText: isInstalled
                    ? (customLLMManager.cachedModelSizeText(repo: repo) ?? customLLMManager.remoteSizeText(repo: repo))
                    : customLLMManager.remoteSizeText(repo: repo),
                ratingText: CustomLLMModelManager.ratingText(for: repo),
                filterTags: catalogFilterTags(
                    base: [localized("Local")] + llmCatalogTags(for: repo),
                    installed: isInstalled,
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localized("Local")] + llmCatalogTags(for: repo),
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
            let status = configured ? "" : localized("Not configured")

            return ModelCatalogEntry(
                id: "remote-llm:\(provider.rawValue)",
                title: provider.title,
                engine: localized("Remote LLM"),
                sizeText: configuration.hasUsableModel ? configuration.model : localized("Cloud"),
                ratingText: "4.5",
                filterTags: catalogFilterTags(
                    base: [localized("Remote")] + remoteLLMCatalogTags(for: provider),
                    installed: false,
                    requiresConfiguration: true,
                    configured: configured,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localized("Remote")] + remoteLLMCatalogTags(for: provider),
                    requiresConfiguration: true,
                    configured: configured,
                    selectionID: selectionID
                ),
                statusText: status,
                usageLocations: usageLocations(for: selectionID),
                badgeText: remoteLLMBadgeText(provider),
                primaryAction: ModelTableAction(title: localized("Configure")) {
                    configureLLMProvider(provider)
                },
                secondaryActions: []
            )
        })

        return entries
    }

    private func usageLocations(for selectionID: FeatureModelSelectionID) -> [String] {
        var labels = [String]()
        if featureSettings.transcription.asrSelectionID == selectionID ||
            (featureSettings.transcription.llmEnabled && featureSettings.transcription.llmSelectionID == selectionID) {
            labels.append(localized("Transcription"))
        }
        if featureSettings.translation.asrSelectionID == selectionID ||
            featureSettings.translation.modelSelectionID == selectionID {
            labels.append(localized("Translation"))
        }
        if featureSettings.rewrite.asrSelectionID == selectionID ||
            featureSettings.rewrite.llmSelectionID == selectionID {
            labels.append(localized("Rewrite"))
        }
        if featureSettings.meeting.enabled &&
            (featureSettings.meeting.asrSelectionID == selectionID ||
                featureSettings.meeting.summaryModelSelectionID == selectionID) {
            labels.append(localized("Meeting"))
        }
        return labels
    }

    private func catalogFilterTags(
        base: [String],
        installed: Bool,
        requiresConfiguration: Bool,
        configured: Bool,
        selectionID: FeatureModelSelectionID
    ) -> [String] {
        var tags = base
        if installed {
            tags.append(localized("Installed"))
        }
        if requiresConfiguration && configured {
            tags.append(localized("Configured"))
        }
        if !usageLocations(for: selectionID).isEmpty {
            tags.append(localized("In Use"))
        }
        return deduplicatedTags(tags)
    }

    private func catalogDisplayTags(
        base: [String],
        requiresConfiguration: Bool,
        configured: Bool,
        selectionID: FeatureModelSelectionID
    ) -> [String] {
        var tags = base.filter { $0 != localized("Multilingual") }
        if let languageSupportTag = primaryLanguageSupportTag(for: selectionID) {
            tags.append(languageSupportTag)
        }
        if requiresConfiguration && configured {
            tags.append(localized("Configured"))
        }
        if !usageLocations(for: selectionID).isEmpty {
            tags.append(localized("In Use"))
        }
        return deduplicatedTags(tags)
    }

    private func mlxCatalogTags(for repo: String) -> [String] {
        deduplicatedTags(MLXModelManager.catalogTagKeys(for: repo).map(localized))
    }

    private func whisperCatalogTags(for modelID: String) -> [String] {
        deduplicatedTags(WhisperKitModelManager.catalogTagKeys(for: modelID).map(localized))
    }

    private func llmCatalogTags(for repo: String) -> [String] {
        deduplicatedTags(CustomLLMModelManager.catalogTagKeys(for: repo).map(localized))
    }

    private func remoteASRCatalogTags(
        for provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> [String] {
        var tags = [String]()
        switch provider {
        case .openAIWhisper:
            tags.append(localized("Multilingual"))
        case .doubaoASR:
            tags.append(contentsOf: [localized("Realtime"), localized("Multilingual")])
        case .glmASR:
            tags.append(contentsOf: [localized("Accurate"), localized("Multilingual")])
        case .aliyunBailianASR:
            tags.append(localized("Multilingual"))
            if RemoteASRRealtimeSupport.isAliyunRealtimeModel(configuration.model) {
                tags.append(localized("Realtime"))
            }
        }
        return deduplicatedTags(tags)
    }

    private func remoteLLMCatalogTags(for provider: RemoteLLMProvider) -> [String] {
        switch provider {
        case .lmStudio, .ollama:
            return []
        default:
            return [localized("Accurate")]
        }
    }

    private func mlxSupportsMultilingual(_ repo: String) -> Bool {
        MLXModelManager.isMultilingualModelRepo(repo)
    }

    private func primaryLanguageSupportTag(for selectionID: FeatureModelSelectionID) -> String? {
        guard let support = supportsPrimaryLanguage(for: selectionID) else { return nil }
        return localized(support ? "Supports Primary Language" : "Does Not Support Primary Language")
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

import SwiftUI

private func localizedModelCatalog(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

@MainActor
struct ModelCatalogBuilder {
    struct CatalogDecoration {
        let filterTags: [String]
        let displayTags: [String]
        let usageLocations: [String]
    }

    let mlxModelManager: MLXModelManager
    let whisperModelManager: WhisperKitModelManager
    let customLLMManager: CustomLLMModelManager
    let remoteASRConfigurations: [String: RemoteProviderConfiguration]
    let remoteLLMConfigurations: [String: RemoteProviderConfiguration]
    let featureSettings: FeatureSettings
    let hasIssue: (ConfigurationTransferManager.MissingConfigurationIssue.Scope) -> Bool
    let customLLMBadgeText: (String) -> String?
    let remoteASRStatusText: (RemoteASRProvider, RemoteProviderConfiguration) -> String
    let remoteLLMBadgeText: (RemoteLLMProvider) -> String?
    let primaryUserLanguageCode: String?
    let mlxInstallSnapshot: (String) -> LocalModelInstallSnapshot
    let whisperInstallSnapshot: (String) -> LocalModelInstallSnapshot
    let customLLMInstallSnapshot: (String) -> LocalModelInstallSnapshot
    let catalogPrimaryAction: (LocalModelInstallSnapshot) -> ModelTableAction?
    let catalogSecondaryActions: (LocalModelInstallSnapshot) -> [ModelTableAction]
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
            let needsSetup = hasIssue(.remoteASRProvider(provider))
            let decoration = catalogDecoration(
                base: [localizedModelCatalog("Remote")] + remoteASRCatalogTags(for: provider, configuration: configuration),
                installed: false,
                requiresConfiguration: true,
                configured: configured,
                selectionID: selectionID
            )

            return ModelCatalogEntry(
                id: "remote-asr:\(provider.rawValue)",
                title: provider.title,
                engine: localizedModelCatalog("Remote ASR"),
                sizeText: configuration.hasUsableModel ? configuration.model : localizedModelCatalog("Cloud"),
                ratingText: provider == .openAIWhisper ? "4.6" : "4.4",
                filterTags: decoration.filterTags,
                displayTags: decoration.displayTags,
                statusText: remoteASRStatusText(provider, configuration),
                usageLocations: decoration.usageLocations,
                badgeText: needsSetup
                    ? localizedModelCatalog("Needs Setup")
                    : ModelCatalogBadgeSupport.recommendedBadgeText(forRemoteASRProvider: provider),
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
            let snapshot = customLLMInstallSnapshot(repo)
            let decoration = catalogDecoration(
                base: [localizedModelCatalog("Local")] + llmCatalogTags(for: repo),
                installed: snapshot.isInstalled,
                requiresConfiguration: false,
                configured: true,
                selectionID: selectionID
            )

            return ModelCatalogEntry(
                id: "local-llm:\(repo)",
                title: customLLMManager.displayTitle(for: repo),
                engine: localizedModelCatalog("Local LLM"),
                sizeText: snapshot.isInstalled
                    ? (customLLMManager.cachedModelSizeText(repo: repo) ?? customLLMManager.remoteSizeText(repo: repo))
                    : customLLMManager.remoteSizeText(repo: repo),
                ratingText: CustomLLMModelManager.ratingText(for: repo),
                filterTags: decoration.filterTags,
                displayTags: decoration.displayTags,
                statusText: snapshot.statusText,
                usageLocations: decoration.usageLocations,
                badgeText: snapshot.badgeText,
                primaryAction: catalogPrimaryAction(snapshot),
                secondaryActions: catalogSecondaryActions(snapshot)
            )
        })

        entries.append(contentsOf: RemoteLLMProvider.allCases.map { provider in
            let selectionID = FeatureModelSelectionID.remoteLLM(provider)
            let configured = RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            let status = configured ? "" : localizedModelCatalog("Not configured")
            let decoration = catalogDecoration(
                base: [localizedModelCatalog("Remote")] + remoteLLMCatalogTags(for: provider),
                installed: false,
                requiresConfiguration: true,
                configured: configured,
                selectionID: selectionID
            )

            return ModelCatalogEntry(
                id: "remote-llm:\(provider.rawValue)",
                title: provider.title,
                engine: localizedModelCatalog("Remote LLM"),
                sizeText: configured ? configuration.model : localizedModelCatalog("Cloud"),
                ratingText: "4.5",
                filterTags: decoration.filterTags,
                displayTags: decoration.displayTags,
                statusText: status,
                usageLocations: decoration.usageLocations,
                badgeText: remoteLLMBadgeText(provider)
                    ?? ModelCatalogBadgeSupport.recommendedBadgeText(forRemoteLLMProvider: provider),
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
        return labels
    }

    func catalogDecoration(
        base: [String],
        installed: Bool,
        requiresConfiguration: Bool,
        configured: Bool,
        selectionID: FeatureModelSelectionID
    ) -> CatalogDecoration {
        let usageLocations = usageLocations(for: selectionID)
        var filterTags = base
        if installed {
            filterTags.append(localizedModelCatalog("Installed"))
        }
        if requiresConfiguration && configured {
            filterTags.append(localizedModelCatalog("Configured"))
        }
        if !usageLocations.isEmpty {
            filterTags.append(localizedModelCatalog("In Use"))
        }

        var displayTags = base.filter { $0 != localizedModelCatalog("Multilingual") }
        if let languageSupportTag = primaryLanguageSupportTag(for: selectionID) {
            displayTags.append(languageSupportTag)
        }
        if requiresConfiguration && configured {
            displayTags.append(localizedModelCatalog("Configured"))
        }
        if !usageLocations.isEmpty {
            displayTags.append(localizedModelCatalog("In Use"))
        }

        return CatalogDecoration(
            filterTags: deduplicatedTags(filterTags),
            displayTags: deduplicatedTags(displayTags),
            usageLocations: usageLocations
        )
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
        catalogDecoration(
            base: base,
            installed: false,
            requiresConfiguration: requiresConfiguration,
            configured: configured,
            selectionID: selectionID
        )
        .displayTags
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
        case .stepFunASR:
            if RemoteASRRealtimeSupport.isStepFunRealtimeModel(configuration.model) {
                tags.append(localizedModelCatalog("Realtime"))
            }
            tags.append(contentsOf: [localizedModelCatalog("Accurate"), localizedModelCatalog("Multilingual")])
        }
        return deduplicatedTags(tags)
    }

    private func remoteLLMCatalogTags(for provider: RemoteLLMProvider) -> [String] {
        switch provider {
        case .lmStudio, .ollama, .omlx:
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

import Foundation

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

@MainActor
struct FeatureModelCatalogBuilder {
    let mlxModelManager: MLXModelManager
    let whisperModelManager: WhisperKitModelManager
    let customLLMManager: CustomLLMModelManager
    let featureSettings: FeatureSettings
    let remoteASRProviderConfigurationsRaw: String
    let remoteLLMProviderConfigurationsRaw: String
    let appleIntelligenceAvailable: Bool
    let primaryUserLanguageCode: String?

    func entries(for sheet: FeatureModelSelectorSheet) -> [FeatureModelSelectorEntry] {
        switch sheet {
        case .transcriptionASR, .translationASR, .rewriteASR, .meetingASR:
            return asrEntries()
        case .transcriptionLLM, .rewriteLLM, .meetingSummary:
            return llmEntries(includeAppleIntelligence: true)
        case .translationModel:
            return translationEntries(
                selectedASR: featureSettings.translation.asrSelectionID,
                targetLanguage: featureSettings.translation.targetLanguage
            )
        }
    }

    func asrSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.asrSelection {
        case .dictation:
            return localized("Direct Dictation")
        case .mlx(let repo):
            return mlxModelManager.displayTitle(for: repo)
        case .whisper(let modelID):
            return whisperModelManager.displayTitle(for: modelID)
        case .remote(let provider):
            let configurations = RemoteModelConfigurationStore.loadConfigurations(
                from: remoteASRProviderConfigurationsRaw,
                sensitiveValueLoading: .metadataOnly
            )
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: configurations)
            return configuration.hasUsableModel ? "\(provider.title) · \(configuration.model)" : provider.title
        case .none:
            return localized("Not selected")
        }
    }

    func llmSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.textSelection {
        case .appleIntelligence:
            return localized("Apple Intelligence")
        case .localLLM(let repo):
            return customLLMManager.displayTitle(for: repo)
        case .remoteLLM(let provider):
            let configurations = RemoteModelConfigurationStore.loadConfigurations(
                from: remoteLLMProviderConfigurationsRaw,
                sensitiveValueLoading: .metadataOnly
            )
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: provider, stored: configurations)
            return configuration.hasUsableModel ? "\(provider.title) · \(configuration.model)" : provider.title
        case .none:
            return localized("Not selected")
        }
    }

    func translationSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.translationSelection {
        case .whisperDirectTranslate:
            return localized("Whisper Direct Translate")
        case .localLLM, .remoteLLM:
            return llmSelectionSummary(selectionID)
        case .none:
            return localized("Not selected")
        }
    }

    private func asrEntries() -> [FeatureModelSelectorEntry] {
        var entries = [FeatureModelSelectorEntry]()
        entries.append(
            FeatureModelSelectorEntry(
                selectionID: .dictation,
                title: localized("Direct Dictation"),
                engine: localized("Apple"),
                sizeText: localized("Built-in"),
                ratingText: "3.4",
                filterTags: [localized("Local"), localized("Built-in"), localized("Multilingual"), localized("Installed")],
                displayTags: featureDisplayTags(
                    base: [localized("Local"), localized("Built-in"), localized("Multilingual")],
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: .dictation
                ),
                statusText: localized("Works immediately with no model download."),
                usageLocations: usageLabels(for: .dictation),
                isSelectable: true,
                disabledReason: nil
            )
        )

        entries.append(contentsOf: MLXModelManager.availableModels.map { model in
            let selectionID = FeatureModelSelectionID.mlx(model.id)
            let isInstalled = mlxModelManager.isModelDownloaded(repo: model.id)
            return FeatureModelSelectorEntry(
                selectionID: selectionID,
                title: model.title,
                engine: localized("MLX Audio"),
                sizeText: isInstalled ? mlxModelManager.modelSizeOnDisk(repo: model.id) : mlxModelManager.remoteSizeText(repo: model.id),
                ratingText: model.id.contains("1.7B") || model.id.contains("FireRed") || model.id.localizedCaseInsensitiveContains("cohere") ? "4.8" : "4.3",
                filterTags: featureFilterTags(
                    base: [localized("Local")] + mlxSpeedTags(for: model.id),
                    installed: isInstalled,
                    requiresConfiguration: false,
                    configured: true,
                    usageLabels: usageLabels(for: selectionID)
                ),
                displayTags: featureDisplayTags(
                    base: [localized("Local")] + mlxSpeedTags(for: model.id),
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                statusText: isInstalled ? localized("Installed") : localized("Not installed"),
                usageLocations: usageLabels(for: selectionID),
                isSelectable: isInstalled,
                disabledReason: isInstalled ? nil : localized("Install this model in Model settings first.")
            )
        })

        entries.append(contentsOf: WhisperKitModelManager.availableModels.map { model in
            let selectionID = FeatureModelSelectionID.whisper(model.id)
            let isInstalled = whisperModelManager.isModelDownloaded(id: model.id)
            return FeatureModelSelectorEntry(
                selectionID: selectionID,
                title: model.title,
                engine: localized("Whisper"),
                sizeText: isInstalled ? whisperModelManager.modelSizeOnDisk(id: model.id) : whisperModelManager.remoteSizeText(id: model.id),
                ratingText: model.id == "large-v3" ? "4.9" : (model.id == "medium" ? "4.7" : "4.1"),
                filterTags: featureFilterTags(
                    base: [localized("Local")] + whisperSpeedTags(for: model.id),
                    installed: isInstalled,
                    requiresConfiguration: false,
                    configured: true,
                    usageLabels: usageLabels(for: selectionID)
                ),
                displayTags: featureDisplayTags(
                    base: [localized("Local")] + whisperSpeedTags(for: model.id),
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                statusText: isInstalled ? localized("Installed") : localized("Not installed"),
                usageLocations: usageLabels(for: selectionID),
                isSelectable: isInstalled,
                disabledReason: isInstalled ? nil : localized("Install this model in Model settings first.")
            )
        })

        let remoteConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: remoteASRProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
        entries.append(contentsOf: RemoteASRProvider.allCases.map { provider in
            let selectionID = FeatureModelSelectionID.remoteASR(provider)
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
                provider: provider,
                stored: remoteConfigurations
            )
            return FeatureModelSelectorEntry(
                selectionID: selectionID,
                title: provider.title,
                engine: localized("Remote ASR"),
                sizeText: configuration.hasUsableModel ? configuration.model : localized("Cloud"),
                ratingText: provider == .openAIWhisper ? "4.6" : "4.4",
                filterTags: featureFilterTags(
                    base: [localized("Remote")] + remoteASRTags(for: provider, configuration: configuration),
                    installed: false,
                    requiresConfiguration: true,
                    configured: configuration.isConfigured,
                    usageLabels: usageLabels(for: selectionID)
                ),
                displayTags: featureDisplayTags(
                    base: [localized("Remote")] + remoteASRTags(for: provider, configuration: configuration),
                    requiresConfiguration: true,
                    configured: configuration.isConfigured,
                    selectionID: selectionID
                ),
                statusText: configuration.isConfigured ? localized("Configured") : localized("Not configured"),
                usageLocations: usageLabels(for: selectionID),
                isSelectable: configuration.isConfigured,
                disabledReason: configuration.isConfigured ? nil : localized("Configure this provider in Model settings first.")
            )
        })

        return entries
    }

    private func llmEntries(includeAppleIntelligence: Bool) -> [FeatureModelSelectorEntry] {
        var entries = [FeatureModelSelectorEntry]()
        if includeAppleIntelligence, appleIntelligenceAvailable {
            entries.append(
                FeatureModelSelectorEntry(
                    selectionID: .appleIntelligence,
                    title: localized("Apple Intelligence"),
                    engine: localized("Apple"),
                    sizeText: localized("Built-in"),
                    ratingText: "4.2",
                    filterTags: [localized("Local"), localized("Multilingual"), localized("Installed")] + inUseTags(for: .appleIntelligence),
                    displayTags: featureDisplayTags(
                        base: [localized("Local"), localized("Multilingual")],
                        requiresConfiguration: false,
                        configured: true,
                        selectionID: .appleIntelligence
                    ),
                    statusText: localized("Available on this Mac"),
                    usageLocations: usageLabels(for: .appleIntelligence),
                    isSelectable: true,
                    disabledReason: nil
                )
            )
        }

        entries.append(contentsOf: CustomLLMModelManager.availableModels.map { model in
            let selectionID = FeatureModelSelectionID.localLLM(model.id)
            let isInstalled = customLLMManager.isModelDownloaded(repo: model.id)
            return FeatureModelSelectorEntry(
                selectionID: selectionID,
                title: model.title,
                engine: localized("Local LLM"),
                sizeText: isInstalled ? customLLMManager.modelSizeOnDisk(repo: model.id) : customLLMManager.remoteSizeText(repo: model.id),
                ratingText: model.id.contains("8B") || model.id.contains("9B") ? "4.8" : "4.3",
                filterTags: featureFilterTags(
                    base: [localized("Local")] + llmSpeedTags(for: model.id),
                    installed: isInstalled,
                    requiresConfiguration: false,
                    configured: true,
                    usageLabels: usageLabels(for: selectionID)
                ),
                displayTags: featureDisplayTags(
                    base: [localized("Local")] + llmSpeedTags(for: model.id),
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                statusText: isInstalled ? localized("Installed") : localized("Not installed"),
                usageLocations: usageLabels(for: selectionID),
                isSelectable: isInstalled,
                disabledReason: isInstalled ? nil : localized("Install this model in Model settings first.")
            )
        })

        let remoteConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: remoteLLMProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
        entries.append(contentsOf: RemoteLLMProvider.allCases.map { provider in
            let selectionID = FeatureModelSelectionID.remoteLLM(provider)
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteConfigurations
            )
            let isConfigured = configuration.isConfigured && configuration.hasUsableModel
            return FeatureModelSelectorEntry(
                selectionID: selectionID,
                title: provider.title,
                engine: localized("Remote LLM"),
                sizeText: configuration.hasUsableModel ? configuration.model : localized("Cloud"),
                ratingText: "4.5",
                filterTags: featureFilterTags(
                    base: [localized("Remote")] + remoteLLMTags(for: provider),
                    installed: false,
                    requiresConfiguration: true,
                    configured: isConfigured,
                    usageLabels: usageLabels(for: selectionID)
                ),
                displayTags: featureDisplayTags(
                    base: [localized("Remote")] + remoteLLMTags(for: provider),
                    requiresConfiguration: true,
                    configured: isConfigured,
                    selectionID: selectionID
                ),
                statusText: isConfigured ? localized("Configured") : localized("Not configured"),
                usageLocations: usageLabels(for: selectionID),
                isSelectable: isConfigured,
                disabledReason: isConfigured ? nil : localized("Configure this provider in Model settings first.")
            )
        })

        return entries
    }

    private func translationEntries(
        selectedASR: FeatureModelSelectionID,
        targetLanguage: TranslationTargetLanguage
    ) -> [FeatureModelSelectorEntry] {
        var entries = llmEntries(includeAppleIntelligence: false)
        let whisperSelectable: Bool
        let whisperDisabledReason: String?

        switch selectedASR.asrSelection {
        case .whisper:
            if targetLanguage == .english {
                whisperSelectable = true
                whisperDisabledReason = nil
            } else {
                whisperSelectable = false
                whisperDisabledReason = localized("Whisper direct translation only supports English output.")
            }
        default:
            whisperSelectable = false
            whisperDisabledReason = localized("Whisper direct translation requires Whisper as the translation ASR model.")
        }

        entries.insert(
            FeatureModelSelectorEntry(
                selectionID: .whisperDirectTranslate,
                title: localized("Whisper Direct Translate"),
                engine: localized("Whisper"),
                sizeText: localized("Built-in path"),
                ratingText: "4.0",
                filterTags: featureFilterTags(
                    base: [localized("Local"), localized("Fast"), localized("Multilingual")],
                    installed: false,
                    requiresConfiguration: false,
                    configured: true,
                    usageLabels: usageLabels(for: .whisperDirectTranslate)
                ),
                displayTags: featureDisplayTags(
                    base: [localized("Local"), localized("Fast"), localized("Multilingual")],
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: .whisperDirectTranslate
                ),
                statusText: whisperSelectable ? localized("Ready when Whisper ASR is selected") : localized("Unavailable"),
                usageLocations: usageLabels(for: .whisperDirectTranslate),
                isSelectable: whisperSelectable,
                disabledReason: whisperDisabledReason
            ),
            at: 0
        )
        return entries
    }

    private func usageLabels(for selectionID: FeatureModelSelectionID) -> [String] {
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
        if featureSettings.meeting.asrSelectionID == selectionID ||
            featureSettings.meeting.summaryModelSelectionID == selectionID {
            labels.append(localized("Meeting"))
        }
        return labels
    }

    private func inUseTags(for selectionID: FeatureModelSelectionID) -> [String] {
        usageLabels(for: selectionID).isEmpty ? [] : [localized("In Use")]
    }

    private func featureFilterTags(
        base: [String],
        installed: Bool,
        requiresConfiguration: Bool,
        configured: Bool,
        usageLabels: [String]
    ) -> [String] {
        var tags = base
        if installed {
            tags.append(localized("Installed"))
        }
        if requiresConfiguration && configured {
            tags.append(localized("Configured"))
        }
        if !usageLabels.isEmpty {
            tags.append(localized("In Use"))
        }
        return deduplicatedFeatureTags(tags)
    }

    private func featureDisplayTags(
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
        if !usageLabels(for: selectionID).isEmpty {
            tags.append(localized("In Use"))
        }
        return deduplicatedFeatureTags(tags)
    }

    private func mlxSpeedTags(for repo: String) -> [String] {
        var tags = [String]()
        if mlxSupportsMultilingual(repo) {
            tags.append(localized("Multilingual"))
        }
        if MLXModelManager.isRealtimeCapableModelRepo(repo) {
            tags.append(contentsOf: [localized("Realtime"), localized("Fast")])
            return deduplicatedFeatureTags(tags)
        }
        if repo.contains("0.6B") || repo.contains("Nano") {
            tags.append(localized("Fast"))
        }
        if repo.contains("1.7B") || repo.contains("FireRed") || repo.localizedCaseInsensitiveContains("cohere") {
            tags.append(localized("Accurate"))
        }
        return deduplicatedFeatureTags(tags)
    }

    private func whisperSpeedTags(for modelID: String) -> [String] {
        var tags = [localized("Multilingual")]
        switch modelID {
        case "tiny", "base":
            tags.append(localized("Fast"))
        case "medium", "large-v3":
            tags.append(localized("Accurate"))
        default:
            break
        }
        return deduplicatedFeatureTags(tags)
    }

    private func llmSpeedTags(for repo: String) -> [String] {
        var tags = [String]()
        if repo.contains("1B") || repo.contains("1.5B") || repo.contains("2B") {
            tags.append(localized("Fast"))
        }
        if repo.contains("8B") || repo.contains("9B") {
            tags.append(localized("Accurate"))
        }
        return deduplicatedFeatureTags(tags)
    }

    private func remoteASRTags(
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
        return deduplicatedFeatureTags(tags)
    }

    private func remoteLLMTags(for provider: RemoteLLMProvider) -> [String] {
        switch provider {
        case .lmStudio, .ollama:
            return []
        default:
            return [localized("Accurate")]
        }
    }

    private func mlxSupportsMultilingual(_ repo: String) -> Bool {
        let key = repo.lowercased()
        if key.contains("parakeet") {
            return false
        }
        if key.contains("qwen3-asr")
            || key.contains("voxtral")
            || key.contains("cohere")
            || key.contains("sensevoice")
            || key.contains("granite")
            || key.contains("glm-asr")
            || key.contains("firered") {
            return true
        }
        guard let option = MLXModelManager.availableModels.first(where: { $0.id == repo }) else {
            return false
        }
        return option.description.localizedCaseInsensitiveContains("multilingual")
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

        if key.contains("glm-asr") || key.contains("firered") {
            return ["zh", "en"].contains(baseCode)
        }

        return mlxSupportsMultilingual(repo)
    }

    private func deduplicatedFeatureTags(_ tags: [String]) -> [String] {
        Array(NSOrderedSet(array: tags)) as? [String] ?? tags
    }
}

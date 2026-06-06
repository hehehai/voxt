import AppKit
import SwiftUI

enum MLXConfigurationSummarySupport {
    static func summary(for repo: String, tuning: MLXLocalTuningSettings) -> String {
        let family = MLXModelFamily.family(for: repo)
        switch family {
        case .qwen3ASR:
            let hasContext = tuning.qwenContextBias.isEmpty
                ? AppLocalization.localizedString("Context Off")
                : AppLocalization.localizedString("Context On")
            return AppLocalization.format("%@ · %@", tuning.preset.title, hasContext)
        case .graniteSpeech:
            let hasPrompt = tuning.granitePromptBias.isEmpty
                ? AppLocalization.localizedString("Prompt Off")
                : AppLocalization.localizedString("Prompt On")
            return AppLocalization.format("%@ · %@", tuning.preset.title, hasPrompt)
        case .senseVoice:
            return AppLocalization.localizedString(tuning.senseVoiceUseITN ? "ITN On" : "ITN Off")
        case .cohereTranscribe:
            return tuning.preset.title
        case .generic:
            return tuning.preset.title
        }
    }
}

extension ModelSettingsView {
    func promptBinding(for storage: Binding<String>, kind: AppPromptKind) -> Binding<String> {
        Binding(
            get: {
                AppPromptDefaults.resolvedStoredText(storage.wrappedValue, kind: kind)
            },
            set: { newValue in
                storage.wrappedValue = AppPromptDefaults.canonicalStoredText(newValue, kind: kind)
            }
        )
    }

    var whisperRows: [ModelTableRow] {
        WhisperKitModelManager.availableModels.map { model in
            let snapshot = whisperInstallSnapshot(for: model.id)
            return modelTableRow(
                id: model.id,
                title: AppLocalization.localizedString(model.title),
                snapshot: snapshot
            )
        }
    }

    var remoteASRRows: [ModelTableRow] {
        RemoteASRProvider.allCases.map { provider in
            let config = RemoteModelConfigurationStore.resolvedASRConfiguration(
                provider: provider,
                stored: remoteASRConfigurations
            )
            let isSelected = selectedRemoteASRProvider == provider
            let status = remoteASRStatusText(
                for: provider,
                configuration: config
            )
            return ModelTableRow(
                id: provider.rawValue,
                title: provider.title,
                isActive: isSelected,
                status: status,
                badgeText: hasIssue(for: .remoteASRProvider(provider)) ? AppLocalization.localizedString("Needs Setup") : nil,
                actions: [
                    ModelTableAction(
                        title: selectionActionTitle(isSelected: isSelected),
                        isEnabled: !isSelected
                    ) {
                        useRemoteASRProvider(provider)
                    },
                    ModelTableAction(title: AppLocalization.localizedString("Configure")) {
                        editingASRProvider = provider
                    }
                ]
            )
        }
    }

    var remoteLLMRows: [ModelTableRow] {
        RemoteLLMProvider.allCases.map { provider in
            let isConfigured = RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            let config = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            let status = isConfigured
                ? AppLocalization.format("Configured model: %@", config.model)
                : AppLocalization.localizedString("Not configured")
            return ModelTableRow(
                id: provider.rawValue,
                title: provider.title,
                isActive: selectedRemoteLLMProvider == provider,
                status: status,
                badgeText: remoteLLMBadgeText(for: provider),
                actions: [
                    ModelTableAction(
                        title: selectionActionTitle(isSelected: selectedRemoteLLMProvider == provider),
                        isEnabled: selectedRemoteLLMProvider != provider
                    ) {
                        useRemoteLLMProvider(provider)
                    },
                    ModelTableAction(title: AppLocalization.localizedString("Configure")) {
                        editingLLMProvider = provider
                    }
                ]
            )
        }
    }

    var mlxRows: [ModelTableRow] {
        MLXModelManager.availableModels.map { model in
            let snapshot = mlxInstallSnapshot(for: model.id)
            return modelTableRow(
                id: model.id,
                title: model.title,
                snapshot: snapshot
            )
        }
    }

    var customLLMRows: [ModelTableRow] {
        CustomLLMModelManager.displayModels(including: customLLMRepo).map { model in
            let snapshot = customLLMInstallSnapshot(for: model.id)
            return modelTableRow(
                id: model.id,
                title: model.title,
                snapshot: snapshot
            )
        }
    }

    func hasIssue(for scope: ConfigurationTransferManager.MissingConfigurationIssue.Scope) -> Bool {
        missingConfigurationIssues.contains(where: { $0.scope == scope })
    }

    func remoteLLMBadgeText(for provider: RemoteLLMProvider) -> String? {
        let scopes: [ConfigurationTransferManager.MissingConfigurationIssue.Scope] = [
            .remoteLLMProvider(provider),
            .translationRemoteLLM(provider),
            .rewriteRemoteLLM(provider)
        ]
        return missingConfigurationIssues.contains(where: { scopes.contains($0.scope) }) ? AppLocalization.localizedString("Needs Setup") : nil
    }

    func customLLMBadgeText(for repo: String) -> String? {
        let scopes: [ConfigurationTransferManager.MissingConfigurationIssue.Scope] = [
            .customLLMModel(repo),
            .translationCustomLLM(repo),
            .rewriteCustomLLM(repo)
        ]
        if missingConfigurationIssues.contains(where: { scopes.contains($0.scope) }) {
            return AppLocalization.localizedString("Needs Setup")
        }

        switch CustomLLMModelManager.releaseStatus(for: repo) {
        case .deprecatedSoon:
            return AppLocalization.localizedString("即将下线")
        case .new:
            return nil
        case .standard:
            return nil
        }
    }

    private func selectionActionTitle(isSelected: Bool) -> String {
        AppLocalization.localizedString(isSelected ? "Using" : "Use")
    }

    func useModel(_ repo: String) {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
        modelRepo = canonicalRepo
        mlxModelManager.updateModel(repo: canonicalRepo)
    }

    func useWhisperModel(_ modelID: String) {
        let canonicalModelID = WhisperKitModelManager.canonicalModelID(modelID)
        whisperModelID = canonicalModelID
        whisperModelManager.updateModel(id: canonicalModelID)
    }

    func downloadModel(_ repo: String) {
        Task {
            await mlxModelManager.downloadModel(repo: repo)
        }
    }

    func downloadWhisperModel(_ modelID: String) {
        Task {
            await whisperModelManager.downloadModel(id: modelID)
        }
    }

    func deleteModel(_ repo: String) {
        mlxModelManager.deleteModel(repo: repo)
        if MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(modelRepo) {
            mlxModelManager.checkExistingModel()
        }
    }

    func deleteWhisperModel(_ modelID: String) {
        whisperModelManager.deleteModel(id: modelID)
        if WhisperKitModelManager.canonicalModelID(modelID) == WhisperKitModelManager.canonicalModelID(whisperModelID) {
            whisperModelManager.checkExistingModel()
        }
    }

    func isCurrentModel(_ repo: String) -> Bool {
        MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(modelRepo)
    }

    func isCurrentWhisperModel(_ modelID: String) -> Bool {
        WhisperKitModelManager.canonicalModelID(modelID) == WhisperKitModelManager.canonicalModelID(whisperModelID)
    }

    func isDownloadingModel(_ repo: String) -> Bool {
        mlxInstallSnapshot(for: repo).state == .downloading
    }

    func isPausedModel(_ repo: String) -> Bool {
        mlxInstallSnapshot(for: repo).state == .paused
    }

    func isDownloadingWhisperModel(_ modelID: String) -> Bool {
        whisperInstallSnapshot(for: modelID).state == .downloading
    }

    func isPausedWhisperModel(_ modelID: String) -> Bool {
        whisperInstallSnapshot(for: modelID).state == .paused
    }

    func isAnotherWhisperModelDownloading(_ modelID: String) -> Bool {
        guard let activeDownload = whisperModelManager.activeDownload,
              activeDownload.isPaused == false else { return false }
        return activeDownload.modelID != WhisperKitModelManager.canonicalModelID(modelID)
    }

    func modelStatusText(for repo: String) -> String {
        mlxInstallSnapshot(for: repo).statusText
    }

    func whisperModelStatusText(for modelID: String) -> String {
        whisperInstallSnapshot(for: modelID).statusText
    }

    func useCustomLLM(_ repo: String) {
        customLLMRepo = repo
        customLLMManager.updateModel(repo: repo)
    }

    func downloadCustomLLM(_ repo: String) {
        Task {
            await customLLMManager.downloadModel(repo: repo)
        }
    }

    func deleteCustomLLM(_ repo: String) {
        customLLMManager.deleteModel(repo: repo)
        if repo == customLLMRepo {
            customLLMManager.checkExistingModel()
        }
    }

    func requestDeleteModel(_ repo: String) {
        pendingModelRemovalTarget = .mlx(repo: repo)
    }

    func requestDeleteWhisperModel(_ modelID: String) {
        pendingModelRemovalTarget = .whisper(modelID: modelID)
    }

    func requestDeleteCustomLLM(_ repo: String) {
        pendingModelRemovalTarget = .customLLM(repo: repo)
    }

    func confirmDeleteModel(_ target: LocalModelRemovalTarget) {
        pendingModelRemovalTarget = nil
        uninstallingModelTarget = target

        Task { @MainActor in
            await Task.yield()
            switch target {
            case .mlx(let repo):
                deleteModel(repo)
            case .whisper(let modelID):
                deleteWhisperModel(modelID)
            case .customLLM(let repo):
                deleteCustomLLM(repo)
            }
            uninstallingModelTarget = nil
            refreshCatalogSnapshot()
        }
    }

    func isUninstallingModel(_ repo: String) -> Bool {
        guard case .mlx(let uninstallingRepo) = uninstallingModelTarget else { return false }
        return MLXModelManager.canonicalModelRepo(uninstallingRepo) == MLXModelManager.canonicalModelRepo(repo)
    }

    func isUninstallingWhisperModel(_ modelID: String) -> Bool {
        guard case .whisper(let uninstallingModelID) = uninstallingModelTarget else { return false }
        return WhisperKitModelManager.canonicalModelID(uninstallingModelID) == WhisperKitModelManager.canonicalModelID(modelID)
    }

    func isUninstallingCustomLLM(_ repo: String) -> Bool {
        guard case .customLLM(let uninstallingRepo) = uninstallingModelTarget else { return false }
        return CustomLLMModelManager.canonicalModelRepo(uninstallingRepo) == CustomLLMModelManager.canonicalModelRepo(repo)
    }

    func uninstallConfirmationMessage(for target: LocalModelRemovalTarget) -> String {
        let modelName: String
        switch target {
        case .mlx(let repo):
            modelName = mlxModelManager.displayTitle(for: repo)
        case .whisper(let modelID):
            modelName = whisperModelManager.displayTitle(for: modelID)
        case .customLLM(let repo):
            modelName = customLLMManager.displayTitle(for: repo)
        }
        return AppLocalization.format(
            "Uninstall %@ from this Mac? You can download it again later.",
            modelName
        )
    }

    func isCurrentCustomLLM(_ repo: String) -> Bool {
        CustomLLMModelManager.canonicalModelRepo(repo) == CustomLLMModelManager.canonicalModelRepo(customLLMRepo)
    }

    func isDownloadingCustomLLM(_ repo: String) -> Bool {
        customLLMInstallSnapshot(for: repo).state == .downloading
    }

    func isPausedCustomLLM(_ repo: String) -> Bool {
        customLLMInstallSnapshot(for: repo).state == .paused
    }

    func isAnotherCustomLLMDownloading(_ repo: String) -> Bool {
        ModelDownloadStateRouting.isAnotherCustomLLMDownloadActive(
            repo: repo,
            managerRepo: customLLMManager.currentModelRepo,
            state: customLLMManager.state
        )
    }

    func customLLMStatusText(for repo: String) -> String {
        customLLMInstallSnapshot(for: repo).statusText
    }

    func useRemoteASRProvider(_ provider: RemoteASRProvider) {
        remoteASRSelectedProviderRaw = provider.rawValue
        let resolved = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: provider,
            stored: RemoteModelConfigurationStore.loadConfigurations(from: remoteASRProviderConfigurationsRaw)
        )
        saveRemoteASRConfiguration(resolved)
    }

    func saveRemoteASRConfiguration(_ configuration: RemoteProviderConfiguration) {
        remoteASRProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfiguration(
            configuration,
            updating: remoteASRProviderConfigurationsRaw
        )
        NotificationCenter.default.post(name: .voxtRemoteProviderConfigurationsDidChange, object: nil)
    }

    func remoteASRStatusText(
        for provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> String {
        guard configuration.isConfigured else {
            return AppLocalization.localizedString("Not configured")
        }

        _ = provider
        return ""
    }

    func resolvedASRHintSettings(for target: ASRHintTarget) -> ASRHintSettings {
        ASRHintSettingsStore.resolvedSettings(for: target, rawValue: asrHintSettingsRaw)
    }

    func saveASRHintSettings(_ settings: ASRHintSettings, for target: ASRHintTarget) {
        var updated = ASRHintSettingsStore.load(from: asrHintSettingsRaw)
        updated[target] = ASRHintSettingsStore.sanitized(settings, for: target)
        asrHintSettingsRaw = ASRHintSettingsStore.storageValue(for: updated)
    }

    func asrHintSettingsBinding(for target: ASRHintTarget) -> Binding<ASRHintSettings> {
        Binding(
            get: { resolvedASRHintSettings(for: target) },
            set: { saveASRHintSettings($0, for: target) }
        )
    }

    func resolvedWhisperLocalTuningSettings() -> WhisperLocalTuningSettings {
        WhisperLocalTuningSettingsStore.resolvedSettings(from: whisperLocalASRTuningSettingsRaw)
    }

    func saveWhisperLocalTuningSettings(_ settings: WhisperLocalTuningSettings) {
        whisperLocalASRTuningSettingsRaw = WhisperLocalTuningSettingsStore.storageValue(for: settings)
    }

    func whisperLocalTuningSettingsBinding() -> Binding<WhisperLocalTuningSettings> {
        Binding(
            get: { resolvedWhisperLocalTuningSettings() },
            set: { saveWhisperLocalTuningSettings($0) }
        )
    }

    func resolvedMLXLocalTuningSettings(for repo: String) -> MLXLocalTuningSettings {
        MLXLocalTuningSettingsStore.resolvedSettings(
            for: repo,
            rawValue: mlxLocalASRTuningSettingsRaw
        )
    }

    func saveMLXLocalTuningSettings(_ settings: MLXLocalTuningSettings, for repo: String) {
        mlxLocalASRTuningSettingsRaw = MLXLocalTuningSettingsStore.save(
            settings,
            for: repo,
            rawValue: mlxLocalASRTuningSettingsRaw
        )
    }

    func mlxLocalTuningSettingsBinding(for repo: String) -> Binding<MLXLocalTuningSettings> {
        Binding(
            get: { resolvedMLXLocalTuningSettings(for: repo) },
            set: { saveMLXLocalTuningSettings($0, for: repo) }
        )
    }

    func resolvedCustomLLMGenerationSettings(for repo: String) -> LLMGenerationSettings {
        CustomLLMGenerationSettingsStore.resolvedSettings(
            for: repo,
            rawByRepo: customLLMGenerationSettingsByRepoRaw,
            legacyRaw: customLLMGenerationSettingsRaw
        )
    }

    func saveCustomLLMGenerationSettings(_ settings: LLMGenerationSettings, for repo: String) {
        customLLMGenerationSettingsByRepoRaw = CustomLLMGenerationSettingsStore.save(
            settings,
            for: repo,
            rawByRepo: customLLMGenerationSettingsByRepoRaw
        )
    }

    func customLLMGenerationSettingsBinding(for repo: String) -> Binding<LLMGenerationSettings> {
        Binding(
            get: { resolvedCustomLLMGenerationSettings(for: repo) },
            set: { saveCustomLLMGenerationSettings($0, for: repo) }
        )
    }

    func useRemoteLLMProvider(_ provider: RemoteLLMProvider) {
        remoteLLMSelectedProviderRaw = provider.rawValue
    }

    func saveRemoteLLMConfiguration(_ configuration: RemoteProviderConfiguration) {
        remoteLLMProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfiguration(
            configuration,
            updating: remoteLLMProviderConfigurationsRaw
        )
        NotificationCenter.default.post(name: .voxtRemoteProviderConfigurationsDidChange, object: nil)
    }

    func updateMirrorSetting() {
        let url = useHfMirror ? MLXModelManager.mirrorHubBaseURL : MLXModelManager.defaultHubBaseURL
        mlxModelManager.updateHubBaseURL(url)
        whisperModelManager.updateHubBaseURL(url)
        customLLMManager.updateHubBaseURL(url)
    }

    func refreshModelInstallStateIfNeeded() {
        if case .downloading = mlxModelManager.state {
            // Keep current transient state during active downloads.
        } else if case .paused = mlxModelManager.state {
            // Preserve paused state while download cancellation settles.
        } else if case .loading = mlxModelManager.state {
            // Avoid resetting while model is being loaded.
        } else {
            mlxModelManager.checkExistingModel()
        }

        if case .downloading = whisperModelManager.state {
            // Keep current transient state during active downloads.
        } else if case .paused = whisperModelManager.state {
            // Preserve paused state while download cancellation settles.
        } else if case .loading = whisperModelManager.state {
            // Avoid resetting while model is being loaded.
        } else {
            whisperModelManager.checkExistingModel()
        }

        if case .downloading = customLLMManager.state {
            // Keep current transient state during active downloads.
        } else if case .paused = customLLMManager.state {
            // Preserve paused state while download cancellation settles.
        } else {
            customLLMManager.checkExistingModel()
        }
    }

    func openMLXModelDirectory(_ repo: String) {
        guard let folderURL = mlxModelManager.modelDirectoryURL(repo: repo) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    func openWhisperModelDirectory(_ modelID: String) {
        guard let folderURL = whisperModelManager.modelDirectoryURL(id: modelID) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    func openCustomLLMModelDirectory(_ repo: String) {
        guard let folderURL = customLLMManager.modelDirectoryURL(repo: repo) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    func modelLocalizedDescription(for repo: String) -> LocalizedStringKey {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
        if let model = MLXModelManager.availableModels.first(where: { $0.id == canonicalRepo }) {
            return LocalizedStringKey(model.description)
        }
        return LocalizedStringKey("")
    }

    func whisperModelLocalizedDescription(for modelID: String) -> LocalizedStringKey {
        if let model = WhisperKitModelManager.availableModels.first(where: { $0.id == modelID }) {
            return LocalizedStringKey(model.description)
        }
        return LocalizedStringKey("")
    }

    var whisperConfigurationSummary: String {
        let vad = AppLocalization.localizedString(whisperVADEnabled ? "VAD On" : "VAD Off")
        let timestamps = AppLocalization.localizedString(whisperTimestampsEnabled ? "Timestamps On" : "Timestamps Off")
        let realtime = AppLocalization.localizedString(whisperRealtimeEnabled ? "Realtime On" : "Quality Mode")
        let temperature = String(format: "%.1f", whisperTemperature)
        let tuning = resolvedWhisperLocalTuningSettings()
        return AppLocalization.format(
            "Temperature: %@ · %@ · %@ · %@ · %@",
            temperature,
            vad,
            timestamps,
            realtime,
            tuning.preset.title
        )
    }

    var mlxConfigurationSummary: String {
        let tuning = resolvedMLXLocalTuningSettings(for: modelRepo)
        return MLXConfigurationSummarySupport.summary(for: modelRepo, tuning: tuning)
    }

    var customLLMGenerationSummary: String {
        let settings = resolvedCustomLLMGenerationSettings(for: customLLMRepo)
        var parts = [String]()
        switch settings.thinking.mode {
        case .providerDefault:
            parts.append(AppLocalization.localizedString("Think: Model Default"))
        case .off:
            parts.append(AppLocalization.localizedString("Think: Off"))
        case .on:
            parts.append(AppLocalization.localizedString("Think: On"))
        case .effort, .budget:
            break
        }
        if let maxOutputTokens = settings.maxOutputTokens {
            parts.append(AppLocalization.format("Max Output: %@", String(maxOutputTokens)))
        }
        if let temperature = settings.temperature {
            parts.append(AppLocalization.format("Temperature: %@", String(format: "%.2f", temperature)))
        }
        if let topP = settings.topP {
            parts.append(AppLocalization.format("Top P: %@", String(format: "%.2f", topP)))
        }
        if let repetitionPenalty = settings.repetitionPenalty {
            parts.append(AppLocalization.format("Repetition Penalty: %@", String(format: "%.2f", repetitionPenalty)))
        }
        return parts.isEmpty ? AppLocalization.localizedString("Configuration: Default") : parts.joined(separator: " · ")
    }

    func asrCredentialHint(for provider: RemoteASRProvider) -> String? {
        switch provider {
        case .doubaoASR:
            return AppLocalization.localizedString("Doubao uses App ID + Access Token for streaming API.")
        case .aliyunBailianASR:
            return AppLocalization.localizedString("Aliyun ASR in Voxt uses realtime WebSocket only: Qwen models use /api-ws/v1/realtime, Fun/Paraformer models use /api-ws/v1/inference.")
        case .openAIWhisper, .glmASR, .stepFunASR:
            return nil
        }
    }
}

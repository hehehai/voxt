import AppKit
import SwiftUI

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
            let isDownloaded = whisperModelManager.isModelDownloaded(id: model.id)
            let actions = whisperActions(for: model.id, isDownloaded: isDownloaded)

            return ModelTableRow(
                id: model.id,
                title: AppLocalization.localizedString(model.title),
                isActive: isCurrentWhisperModel(model.id),
                status: whisperModelStatusText(for: model.id),
                badgeText: hasIssue(for: .whisperModel(model.id)) ? AppLocalization.localizedString("Needs Setup") : nil,
                isTitleUnderlined: isDownloaded,
                onTapTitle: isDownloaded ? { openWhisperModelDirectory(model.id) } : nil,
                actions: actions
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
                configuration: config,
                showMeetingSetupDetails: isSelected
            )
            let needsMeetingSetup =
                isSelected &&
                RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(provider, configuration: config) &&
                config.isConfigured &&
                !RemoteASRMeetingConfiguration.hasValidMeetingModel(provider: provider, configuration: config)
            return ModelTableRow(
                id: provider.rawValue,
                title: provider.title,
                isActive: isSelected,
                status: status,
                badgeText: (hasIssue(for: .remoteASRProvider(provider)) || needsMeetingSetup) ? AppLocalization.localizedString("Needs Setup") : nil,
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
            let config = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            let status = config.isConfigured
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
            let isDownloaded = mlxModelManager.isModelDownloaded(repo: model.id)
            let actions = mlxActions(for: model.id, isDownloaded: isDownloaded)

            return ModelTableRow(
                id: model.id,
                title: model.title,
                isActive: isCurrentModel(model.id),
                status: modelStatusText(for: model.id),
                badgeText: hasIssue(for: .mlxModel(model.id)) ? AppLocalization.localizedString("Needs Setup") : nil,
                isTitleUnderlined: isDownloaded,
                onTapTitle: isDownloaded ? { openMLXModelDirectory(model.id) } : nil,
                actions: actions
            )
        }
    }

    var customLLMRows: [ModelTableRow] {
        CustomLLMModelManager.displayModels(including: customLLMRepo).map { model in
            let isDownloaded = customLLMManager.isModelDownloaded(repo: model.id)
            let actions = customLLMActions(for: model.id, isDownloaded: isDownloaded)

            return ModelTableRow(
                id: model.id,
                title: model.title,
                isActive: isCurrentCustomLLM(model.id),
                status: customLLMStatusText(for: model.id),
                badgeText: customLLMBadgeText(for: model.id),
                isTitleUnderlined: isDownloaded,
                onTapTitle: isDownloaded ? { openCustomLLMModelDirectory(model.id) } : nil,
                actions: actions
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
            return AppLocalization.localizedString("New")
        case .standard:
            return nil
        }
    }

    private func whisperActions(for modelID: String, isDownloaded: Bool) -> [ModelTableAction] {
        if isUninstallingWhisperModel(modelID) {
            return [ModelTableAction(title: AppLocalization.localizedString("Uninstalling…"), isEnabled: false) {}]
        }

        if isDownloadingWhisperModel(modelID) {
            return ModelDownloadPresentationSupport.downloadingActions(
                onPause: { whisperModelManager.pauseDownload() },
                onCancel: { whisperModelManager.cancelDownload() }
            )
        }

        if isPausedWhisperModel(modelID) {
            return ModelDownloadPresentationSupport.pausedActions(
                onResume: { downloadWhisperModel(modelID) },
                onCancel: {
                    whisperModelManager.cancelDownload(id: modelID)
                    refreshCatalogSnapshot()
                }
            )
        }

        if isDownloaded {
            return ModelDownloadPresentationSupport.installedActions(
                isCurrent: isCurrentWhisperModel(modelID),
                onUse: { useWhisperModel(modelID) },
                onUninstall: { requestDeleteWhisperModel(modelID) }
            )
        }

        return ModelDownloadPresentationSupport.installActions(
            isEnabled: !isAnotherWhisperModelDownloading(modelID),
            onInstall: { downloadWhisperModel(modelID) }
        )
    }

    private func mlxActions(for repo: String, isDownloaded: Bool) -> [ModelTableAction] {
        if isUninstallingModel(repo) {
            return [ModelTableAction(title: AppLocalization.localizedString("Uninstalling…"), isEnabled: false) {}]
        }

        if isDownloadingModel(repo) {
            return ModelDownloadPresentationSupport.downloadingActions(
                onPause: { mlxModelManager.pauseDownload() },
                onCancel: { mlxModelManager.cancelDownload() }
            )
        }

        if isPausedModel(repo) {
            return ModelDownloadPresentationSupport.pausedActions(
                onResume: { downloadModel(repo) },
                onCancel: {
                    mlxModelManager.cancelDownload(repo: repo)
                    refreshCatalogSnapshot()
                }
            )
        }

        if isDownloaded {
            return ModelDownloadPresentationSupport.installedActions(
                isCurrent: isCurrentModel(repo),
                onUse: { useModel(repo) },
                onUninstall: { requestDeleteModel(repo) }
            )
        }

        return ModelDownloadPresentationSupport.installActions(
            isEnabled: !isAnotherModelDownloading(repo),
            onInstall: { downloadModel(repo) }
        )
    }

    private func customLLMActions(for repo: String, isDownloaded: Bool) -> [ModelTableAction] {
        if isUninstallingCustomLLM(repo) {
            return [ModelTableAction(title: AppLocalization.localizedString("Uninstalling…"), isEnabled: false) {}]
        }

        if isDownloadingCustomLLM(repo) {
            return ModelDownloadPresentationSupport.downloadingActions(
                onPause: { customLLMManager.pauseDownload() },
                onCancel: { customLLMManager.cancelDownload() }
            )
        }

        if isPausedCustomLLM(repo) {
            return ModelDownloadPresentationSupport.pausedActions(
                onResume: { downloadCustomLLM(repo) },
                onCancel: {
                    customLLMManager.cancelDownload(repo: repo)
                    refreshCatalogSnapshot()
                }
            )
        }

        if isDownloaded {
            return ModelDownloadPresentationSupport.installedActions(
                isCurrent: isCurrentCustomLLM(repo),
                onUse: { useCustomLLM(repo) },
                onUninstall: { requestDeleteCustomLLM(repo) }
            )
        }

        return ModelDownloadPresentationSupport.installActions(
            isEnabled: !isAnotherCustomLLMDownloading(repo),
            onInstall: { downloadCustomLLM(repo) }
        )
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
        ModelDownloadStateRouting.isMLXDownloading(
            repo: repo,
            activeRepo: mlxModelManager.activeDownloadRepo,
            state: mlxModelManager.state
        )
    }

    func isPausedModel(_ repo: String) -> Bool {
        ModelDownloadStateRouting.isMLXPaused(
            repo: repo,
            activeRepo: mlxModelManager.activeDownloadRepo,
            state: mlxModelManager.state
        ) || mlxModelManager.hasResumableDownload(repo: repo)
    }

    func isDownloadingWhisperModel(_ modelID: String) -> Bool {
        guard let activeDownload = whisperModelManager.activeDownload else { return false }
        return activeDownload.modelID == WhisperKitModelManager.canonicalModelID(modelID) && !activeDownload.isPaused
    }

    func isPausedWhisperModel(_ modelID: String) -> Bool {
        if let activeDownload = whisperModelManager.activeDownload {
            return activeDownload.modelID == WhisperKitModelManager.canonicalModelID(modelID) && activeDownload.isPaused
        }
        return whisperModelManager.hasResumableDownload(id: modelID)
    }

    func isAnotherModelDownloading(_ repo: String) -> Bool {
        ModelDownloadStateRouting.isAnotherMLXDownloadActive(
            repo: repo,
            activeRepo: mlxModelManager.activeDownloadRepo,
            state: mlxModelManager.state
        )
    }

    func isAnotherWhisperModelDownloading(_ modelID: String) -> Bool {
        guard let activeDownload = whisperModelManager.activeDownload,
              activeDownload.isPaused == false else { return false }
        return activeDownload.modelID != WhisperKitModelManager.canonicalModelID(modelID)
    }

    func modelStatusText(for repo: String) -> String {
        if isUninstallingModel(repo) {
            return AppLocalization.localizedString("Uninstalling…")
        }

        if isDownloadingModel(repo),
           case .downloading(_, let completed, let total, _, _, _) = mlxModelManager.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .downloading(completed: completed, total: total)
            )
        }

        if isPausedModel(repo),
           case .paused(_, let completed, let total, _, _, _) = mlxModelManager.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: completed,
                    total: total,
                    pauseMessage: mlxModelManager.pausedStatusMessage
                )
            )
        }

        if isPausedModel(repo) {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: 0,
                    total: 0,
                    pauseMessage: AppLocalization.localizedString("Paused. Ready to continue.")
                )
            )
        }

        if ModelDownloadStateRouting.isMLXOperationTarget(
            repo: repo,
            activeRepo: mlxModelManager.activeDownloadRepo
        ), case .error(let message) = mlxModelManager.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .idle,
                errorMessage: message
            )
        }

        return ""
    }

    func whisperModelStatusText(for modelID: String) -> String {
        if isUninstallingWhisperModel(modelID) {
            return AppLocalization.localizedString("Uninstalling…")
        }

        let canonicalModelID = WhisperKitModelManager.canonicalModelID(modelID)
        let activeDownload = whisperModelManager.activeDownload?.modelID == canonicalModelID
            ? whisperModelManager.activeDownload
            : nil
        let errorMessage = whisperModelManager.downloadErrorMessage(for: modelID)
            ?? {
                guard isCurrentWhisperModel(modelID), case .error(let message) = whisperModelManager.state else {
                    return nil
                }
                return message
            }()

        if activeDownload == nil, whisperModelManager.hasResumableDownload(id: modelID) {
            return ModelDownloadPresentationSupport.whisperStatusText(
                activeDownload: .init(
                    modelID: canonicalModelID,
                    isPaused: true,
                    progress: 0,
                    completed: 0,
                    total: 0,
                    currentFile: nil,
                    currentFileCompleted: 0,
                    currentFileTotal: 0,
                    completedFiles: 0,
                    totalFiles: 0
                ),
                pauseMessage: AppLocalization.localizedString("Paused. Ready to continue."),
                errorMessage: errorMessage
            )
        }

        return ModelDownloadPresentationSupport.whisperStatusText(
            activeDownload: activeDownload,
            pauseMessage: whisperModelManager.pausedStatusMessage(for: modelID),
            errorMessage: errorMessage
        )
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
        ModelDownloadStateRouting.isCustomLLMDownloading(
            repo: repo,
            managerRepo: customLLMManager.currentModelRepo,
            state: customLLMManager.state
        )
    }

    func isPausedCustomLLM(_ repo: String) -> Bool {
        ModelDownloadStateRouting.isCustomLLMPaused(
            repo: repo,
            managerRepo: customLLMManager.currentModelRepo,
            state: customLLMManager.state
        ) || customLLMManager.hasResumableDownload(repo: repo)
    }

    func isAnotherCustomLLMDownloading(_ repo: String) -> Bool {
        ModelDownloadStateRouting.isAnotherCustomLLMDownloadActive(
            repo: repo,
            managerRepo: customLLMManager.currentModelRepo,
            state: customLLMManager.state
        )
    }

    func customLLMStatusText(for repo: String) -> String {
        if isUninstallingCustomLLM(repo) {
            return AppLocalization.localizedString("Uninstalling…")
        }

        if isDownloadingCustomLLM(repo),
           case .downloading(_, let completed, let total, _, _, _) = customLLMManager.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .downloading(completed: completed, total: total)
            )
        }

        if isPausedCustomLLM(repo),
           case .paused(_, let completed, let total, _, _, _) = customLLMManager.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: completed,
                    total: total,
                    pauseMessage: customLLMManager.pausedStatusMessage
                )
            )
        }

        if isPausedCustomLLM(repo) {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: 0,
                    total: 0,
                    pauseMessage: AppLocalization.localizedString("Paused. Ready to continue.")
                )
            )
        }

        if ModelDownloadStateRouting.isCustomLLMOperationTarget(
            repo: repo,
            managerRepo: customLLMManager.currentModelRepo
        ), case .error(let message) = customLLMManager.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .idle,
                errorMessage: message
            )
        }

        return ""
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
        configuration: RemoteProviderConfiguration,
        showMeetingSetupDetails: Bool = true
    ) -> String {
        guard configuration.isConfigured else {
            return AppLocalization.localizedString("Not configured")
        }

        var lines = [String]()
        if showMeetingSetupDetails,
           RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(provider, configuration: configuration) {
            if !configuration.hasUsableMeetingModel {
                lines.append(RemoteASRMeetingConfiguration.missingMeetingModelStatus(provider: provider))
            }
        }
        return lines.joined(separator: "\n")
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

    func useRemoteLLMProvider(_ provider: RemoteLLMProvider) {
        remoteLLMSelectedProviderRaw = provider.rawValue
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: RemoteModelConfigurationStore.loadConfigurations(from: remoteLLMProviderConfigurationsRaw)
        )
        saveRemoteLLMConfiguration(resolved)
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
        } else if case .loading = mlxModelManager.state {
            // Avoid resetting while model is being loaded.
        } else {
            mlxModelManager.checkExistingModel()
        }

        if case .downloading = whisperModelManager.state {
            // Keep current transient state during active downloads.
        } else if case .loading = whisperModelManager.state {
            // Avoid resetting while model is being loaded.
        } else {
            whisperModelManager.checkExistingModel()
        }

        if case .downloading = customLLMManager.state {
            // Keep current transient state during active downloads.
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
        let resident = AppLocalization.localizedString(whisperKeepResidentLoaded ? "Resident On" : "Resident Off")
        let temperature = String(format: "%.1f", whisperTemperature)
        let tuning = resolvedWhisperLocalTuningSettings()
        return AppLocalization.format(
            "Temperature: %@ · %@ · %@ · %@ · %@ · %@",
            temperature,
            vad,
            timestamps,
            realtime,
            resident,
            tuning.preset.title
        )
    }

    var mlxConfigurationSummary: String {
        let tuning = resolvedMLXLocalTuningSettings(for: modelRepo)
        let family = MLXModelFamily.family(for: modelRepo)
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
            let itn = AppLocalization.localizedString(tuning.senseVoiceUseITN ? "ITN On" : "ITN Off")
            return AppLocalization.format("%@ · %@", tuning.preset.title, itn)
        case .cohereTranscribe:
            return tuning.preset.title
        case .generic:
            return tuning.preset.title
        }
    }

    func asrCredentialHint(for provider: RemoteASRProvider) -> String? {
        switch provider {
        case .doubaoASR:
            return AppLocalization.localizedString("Doubao uses App ID + Access Token for streaming API.")
        case .aliyunBailianASR:
            return AppLocalization.localizedString("Aliyun ASR in Voxt uses realtime WebSocket only: Qwen models use /api-ws/v1/realtime, Fun/Paraformer models use /api-ws/v1/inference.")
        case .openAIWhisper, .glmASR:
            return nil
        }
    }
}

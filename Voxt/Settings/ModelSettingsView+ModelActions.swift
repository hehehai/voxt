import AppKit
import SwiftUI

extension ModelSettingsView {
    var whisperRows: [ModelTableRow] {
        WhisperKitModelManager.availableModels.map { model in
            let isDownloaded = whisperModelManager.isModelDownloaded(id: model.id)
            let actions: [ModelTableAction]
            if isDownloadingWhisperModel(model.id) {
                actions = [
                    ModelTableAction(title: "Cancel") {
                        whisperModelManager.cancelDownload()
                    }
                ]
            } else if isDownloaded {
                actions = [
                    ModelTableAction(
                        title: isCurrentWhisperModel(model.id) ? "Using" : "Use",
                        isEnabled: !isCurrentWhisperModel(model.id)
                    ) {
                        useWhisperModel(model.id)
                    },
                    ModelTableAction(title: "Delete", role: .destructive) {
                        deleteWhisperModel(model.id)
                    }
                ]
            } else {
                actions = [
                    ModelTableAction(title: "Download", isEnabled: !isAnotherWhisperModelDownloading(model.id)) {
                        downloadWhisperModel(model.id)
                    }
                ]
            }

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
                        title: isSelected ? "Using" : "Use",
                        isEnabled: !isSelected
                    ) {
                        useRemoteASRProvider(provider)
                    },
                    ModelTableAction(title: "Configure") {
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
                        title: selectedRemoteLLMProvider == provider ? "Using" : "Use",
                        isEnabled: selectedRemoteLLMProvider != provider
                    ) {
                        useRemoteLLMProvider(provider)
                    },
                    ModelTableAction(title: "Configure") {
                        editingLLMProvider = provider
                    }
                ]
            )
        }
    }

    var mlxRows: [ModelTableRow] {
        MLXModelManager.availableModels.map { model in
            let isDownloaded = mlxModelManager.isModelDownloaded(repo: model.id)
            let actions: [ModelTableAction]
            if isDownloadingModel(model.id) {
                actions = [
                    ModelTableAction(title: "Cancel") {
                        mlxModelManager.cancelDownload()
                    }
                ]
            } else if isDownloaded {
                actions = [
                    ModelTableAction(
                        title: isCurrentModel(model.id) ? "Using" : "Use",
                        isEnabled: !isCurrentModel(model.id)
                    ) {
                        useModel(model.id)
                    },
                    ModelTableAction(title: "Delete", role: .destructive) {
                        deleteModel(model.id)
                    }
                ]
            } else {
                actions = [
                    ModelTableAction(title: "Download", isEnabled: !isAnotherModelDownloading(model.id)) {
                        downloadModel(model.id)
                    }
                ]
            }

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
        CustomLLMModelManager.availableModels.map { model in
            let isDownloaded = customLLMManager.isModelDownloaded(repo: model.id)
            let actions: [ModelTableAction]
            if isDownloadingCustomLLM(model.id) {
                actions = [
                    ModelTableAction(title: "Cancel") {
                        customLLMManager.cancelDownload()
                    }
                ]
            } else if isDownloaded {
                actions = [
                    ModelTableAction(
                        title: isCurrentCustomLLM(model.id) ? "Using" : "Use",
                        isEnabled: !isCurrentCustomLLM(model.id)
                    ) {
                        useCustomLLM(model.id)
                    },
                    ModelTableAction(title: "Delete", role: .destructive) {
                        deleteCustomLLM(model.id)
                    }
                ]
            } else {
                actions = [
                    ModelTableAction(title: "Download", isEnabled: !isAnotherCustomLLMDownloading(model.id)) {
                        downloadCustomLLM(model.id)
                    }
                ]
            }

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
        return missingConfigurationIssues.contains(where: { scopes.contains($0.scope) }) ? AppLocalization.localizedString("Needs Setup") : nil
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
            modelRepo = MLXModelManager.canonicalModelRepo(repo)
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
        guard isCurrentModel(repo) else { return false }
        if case .downloading = mlxModelManager.state {
            return true
        }
        return false
    }

    func isDownloadingWhisperModel(_ modelID: String) -> Bool {
        whisperModelManager.activeDownload?.modelID == WhisperKitModelManager.canonicalModelID(modelID)
    }

    func isAnotherModelDownloading(_ repo: String) -> Bool {
        guard case .downloading = mlxModelManager.state else { return false }
        return !isCurrentModel(repo)
    }

    func isAnotherWhisperModelDownloading(_ modelID: String) -> Bool {
        guard let activeDownloadModelID = whisperModelManager.activeDownload?.modelID else { return false }
        return activeDownloadModelID != WhisperKitModelManager.canonicalModelID(modelID)
    }

    func modelStatusText(for repo: String) -> String {
        if isDownloadingModel(repo),
           case .downloading(_, let completed, let total, _, _, _) = mlxModelManager.state {
            return AppLocalization.format(
                "Downloading %@",
                ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
            )
        }

        if isCurrentModel(repo), case .error(let message) = mlxModelManager.state {
            return "Error: \(message)"
        }

        return ""
    }

    func whisperModelStatusText(for modelID: String) -> String {
        if let activeDownload = whisperModelManager.activeDownload,
           activeDownload.modelID == WhisperKitModelManager.canonicalModelID(modelID) {
            let overallText = AppLocalization.format(
                "Downloading %@",
                ModelDownloadProgressFormatter.progressText(
                    completed: activeDownload.completed,
                    total: activeDownload.total
                )
            )
            let fileText = ModelDownloadProgressFormatter.fileProgressText(
                currentFile: activeDownload.currentFile,
                currentFileCompleted: activeDownload.currentFileCompleted,
                currentFileTotal: activeDownload.currentFileTotal,
                completedFiles: activeDownload.completedFiles,
                totalFiles: activeDownload.totalFiles
            )
            return AppLocalization.format(
                "%@ • %@",
                overallText,
                fileText
            )
        }

        if let message = whisperModelManager.downloadErrorMessage(for: modelID) {
            return "Error: \(message)"
        }

        if isCurrentWhisperModel(modelID), case .error(let message) = whisperModelManager.state {
            return "Error: \(message)"
        }

        return ""
    }

    func useCustomLLM(_ repo: String) {
        customLLMRepo = repo
        customLLMManager.updateModel(repo: repo)
    }

    func downloadCustomLLM(_ repo: String) {
        Task {
            await customLLMManager.downloadModel(repo: repo)
            customLLMRepo = repo
        }
    }

    func deleteCustomLLM(_ repo: String) {
        customLLMManager.deleteModel(repo: repo)
        if repo == customLLMRepo {
            customLLMManager.checkExistingModel()
        }
    }

    func isCurrentCustomLLM(_ repo: String) -> Bool {
        repo == customLLMRepo
    }

    func isDownloadingCustomLLM(_ repo: String) -> Bool {
        guard isCurrentCustomLLM(repo) else { return false }
        if case .downloading = customLLMManager.state {
            return true
        }
        return false
    }

    func isAnotherCustomLLMDownloading(_ repo: String) -> Bool {
        guard case .downloading = customLLMManager.state else { return false }
        return !isCurrentCustomLLM(repo)
    }

    func customLLMStatusText(for repo: String) -> String {
        if isDownloadingCustomLLM(repo),
           case .downloading(_, let completed, let total, _, _, _) = customLLMManager.state {
            return AppLocalization.format(
                "Downloading %@",
                ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
            )
        }

        if isCurrentCustomLLM(repo), case .error(let message) = customLLMManager.state {
            return "Error: \(message)"
        }

        return ""
    }

    func useRemoteASRProvider(_ provider: RemoteASRProvider) {
        remoteASRSelectedProviderRaw = provider.rawValue
        let resolved = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: provider,
            stored: remoteASRConfigurations
        )
        saveRemoteASRConfiguration(resolved)
    }

    func saveRemoteASRConfiguration(_ configuration: RemoteProviderConfiguration) {
        var updated = remoteASRConfigurations
        updated[configuration.providerID] = configuration
        remoteASRProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfigurations(updated)
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

    func useRemoteLLMProvider(_ provider: RemoteLLMProvider) {
        remoteLLMSelectedProviderRaw = provider.rawValue
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: remoteLLMConfigurations
        )
        saveRemoteLLMConfiguration(resolved)
    }

    func saveRemoteLLMConfiguration(_ configuration: RemoteProviderConfiguration) {
        var updated = remoteLLMConfigurations
        updated[configuration.providerID] = configuration
        remoteLLMProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfigurations(updated)
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
        return AppLocalization.format("Temperature: %@ · %@ · %@ · %@ · %@", temperature, vad, timestamps, realtime, resident)
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

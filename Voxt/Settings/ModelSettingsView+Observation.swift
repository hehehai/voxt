import SwiftUI

extension ModelSettingsView {
    var contentWithLifecycle: some View {
        let appeared = AnyView(
            mainContent
                .onAppear(perform: handleOnAppear)
                .onAppear(perform: reloadCachedConfigurationState)
                .onAppear(perform: refreshModelStorageDisplayPath)
                .onAppear(perform: refreshCatalogSnapshot)
        )

        let selectionObserved = AnyView(
            appeared
                .onChange(of: modelRepo) { _, newValue in
                    handleModelRepoChange(newValue)
                }
                .onChange(of: whisperModelID) { _, newValue in
                    handleWhisperModelIDChange(newValue)
                }
                .onChange(of: localModelMemoryOptimizationEnabled) { _, _ in
                    handleWhisperResidencyTriggerChange()
                }
                .onChange(of: engineRaw) { _, _ in
                    handleWhisperResidencyTriggerChange()
                }
                .onChange(of: customLLMRepo) { _, newValue in
                    handleCustomLLMRepoChange(newValue)
                }
        )

        let configurationObserved = AnyView(
            selectionObserved
                .onChange(of: translationModelProviderRaw) { _, _ in
                    handleTranslationProviderChange()
                }
                .onChange(of: rewriteModelProviderRaw) { _, _ in
                    handleRewriteProviderChange()
                }
                .onChange(of: remoteLLMProviderConfigurationsRaw) { _, _ in
                    handleRemoteLLMConfigurationsChange()
                }
                .onChange(of: remoteASRProviderConfigurationsRaw) { _, _ in
                    handleRemoteASRConfigurationsChange()
                }
                .onChange(of: useHfMirror) { _, _ in
                    updateMirrorSetting()
                }
                .onChange(of: modelStorageRootPath) { _, _ in
                    handleModelStorageRootPathChange()
                }
                .onChange(of: featureSettingsRaw) { _, _ in
                    handleFeatureSettingsChange()
                }
                .onChange(of: catalogTab) { _, _ in
                    handleCatalogFilterSelectionChange()
                }
                .onChange(of: selectedTags) { _, _ in
                    handleCatalogFilterSelectionChange()
                }
        )

        let stateObserved = AnyView(
            configurationObserved
                .onChange(of: mlxModelManager.state) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: mlxModelManager.stateByRepo) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: mlxModelManager.pausedStatusMessageByRepo) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: mlxModelManager.activeDownloadRepos) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: whisperModelManager.state) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: whisperModelManager.activeDownload) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: whisperModelManager.pausedStatusMessageByID) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: customLLMManager.state) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: mlxModelManager.remoteSizeTextByRepo) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: whisperModelManager.remoteSizeTextByID) { _, _ in
                    refreshCatalogSnapshot()
                }
                .onChange(of: customLLMManager.remoteSizeTextByRepo) { _, _ in
                    refreshCatalogSnapshot()
                }
        )

        return AnyView(
            stateObserved
                .onReceive(modelStateRefreshTimer) { _ in
                    handleModelStateRefreshTick()
                }
        )
    }

    func handleModelRepoChange(_ newValue: String) {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(newValue)
        if canonicalRepo != newValue {
            modelRepo = canonicalRepo
            return
        }
        mlxModelManager.updateModel(repo: canonicalRepo)
        refreshCatalogSnapshot()
    }

    func handleWhisperModelIDChange(_ newValue: String) {
        let canonicalModelID = WhisperKitModelManager.canonicalModelID(newValue)
        if canonicalModelID != newValue {
            whisperModelID = canonicalModelID
            return
        }
        whisperModelManager.updateModel(id: canonicalModelID)
        refreshCatalogSnapshot()
    }

    func handleWhisperResidencyTriggerChange() {
        mlxModelManager.refreshMemoryOptimizationPolicy()
        customLLMManager.refreshMemoryOptimizationPolicy()
        whisperModelManager.refreshMemoryOptimizationPolicy()
        guard selectedEngine == .whisperKit, !localModelMemoryOptimizationEnabled else { return }
        Task { @MainActor in
            whisperModelManager.beginActiveUse()
            defer { whisperModelManager.endActiveUse() }
            _ = try? await whisperModelManager.loadWhisper()
        }
    }

    func handleCustomLLMRepoChange(_ newValue: String) {
        customLLMManager.updateModel(repo: newValue)
        ensureTranslationModelSelectionConsistency()
        ensureRewriteModelSelectionConsistency()
        refreshCatalogSnapshot()
    }

    func handleTranslationProviderChange() {
        syncTranslationFallbackProvider()
        ensureTranslationModelSelectionConsistency()
        refreshCatalogSnapshot()
    }

    func handleRewriteProviderChange() {
        ensureRewriteModelSelectionConsistency()
        refreshCatalogSnapshot()
    }

    func handleRemoteLLMConfigurationsChange() {
        cachedRemoteLLMConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: remoteLLMProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
        ensureTranslationModelSelectionConsistency()
        ensureRewriteModelSelectionConsistency()
        refreshCatalogSnapshot()
    }

    func handleRemoteASRConfigurationsChange() {
        cachedRemoteASRConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: remoteASRProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
        refreshCatalogSnapshot()
    }

    func handleModelStorageRootPathChange() {
        refreshAllModelStorageRoots()
        refreshModelStorageDisplayPath()
        refreshCatalogSnapshot()
    }

    func handleFeatureSettingsChange() {
        cachedFeatureSettings = FeatureSettingsStore.load(defaults: .standard)
        pruneSelectedTags()
        refreshCatalogSnapshot()
    }

    func handleCatalogFilterSelectionChange() {
        pruneSelectedTags()
        refreshCatalogSnapshot()
    }

    func handleModelStateRefreshTick() {
        guard isActive else { return }
        guard mainWindowState.isVisible else { return }
        guard shouldPollModelState else { return }
        refreshModelInstallStateIfNeeded()
        pruneSelectedTags()
        refreshCatalogSnapshot()
    }
}

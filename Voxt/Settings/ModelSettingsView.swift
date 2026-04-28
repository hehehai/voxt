import SwiftUI
import AppKit
import Combine

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

enum LocalASRConfigurationTarget: Equatable, Identifiable {
    case mlx(repo: String)
    case whisper(modelID: String)

    var id: String {
        switch self {
        case .mlx(let repo):
            return "mlx:\(repo)"
        case .whisper(let modelID):
            return "whisper:\(modelID)"
        }
    }
}

struct ModelSettingsView: View {
    private struct DownloadEndpointCheckResult: Equatable {
        let isReachable: Bool
        let latencyText: String
        let throughputText: String
        let detailText: String
    }

    @AppStorage(AppPreferenceKey.transcriptionEngine) var engineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.enhancementMode) var enhancementModeRaw = EnhancementMode.off.rawValue
    @AppStorage(AppPreferenceKey.enhancementSystemPrompt) var systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
    @AppStorage(AppPreferenceKey.translationSystemPrompt) var translationPrompt = AppPreferenceKey.defaultTranslationPrompt
    @AppStorage(AppPreferenceKey.rewriteSystemPrompt) var rewritePrompt = AppPreferenceKey.defaultRewritePrompt
    @AppStorage(AppPreferenceKey.mlxModelRepo) var modelRepo = MLXModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.whisperModelID) var whisperModelID = WhisperKitModelManager.defaultModelID
    @AppStorage(AppPreferenceKey.whisperTemperature) var whisperTemperature = 0.0
    @AppStorage(AppPreferenceKey.whisperVADEnabled) var whisperVADEnabled = true
    @AppStorage(AppPreferenceKey.whisperTimestampsEnabled) var whisperTimestampsEnabled = false
    @AppStorage(AppPreferenceKey.whisperRealtimeEnabled) var whisperRealtimeEnabled = true
    @AppStorage(AppPreferenceKey.whisperKeepResidentLoaded) var whisperKeepResidentLoaded = true
    @AppStorage(AppPreferenceKey.whisperLocalASRTuningSettings) var whisperLocalASRTuningSettingsRaw = WhisperLocalTuningSettingsStore.defaultStoredValue()
    @AppStorage(AppPreferenceKey.customLLMModelRepo) var customLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationCustomLLMModelRepo) var translationCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.rewriteCustomLLMModelRepo) var rewriteCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationModelProvider) var translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.translationFallbackModelProvider) var translationFallbackModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.rewriteModelProvider) var rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.translationTargetLanguage) var translationTargetLanguageRaw = TranslationTargetLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.remoteASRSelectedProvider) var remoteASRSelectedProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.asrHintSettings) var asrHintSettingsRaw = ASRHintSettingsStore.defaultStoredValue()
    @AppStorage(AppPreferenceKey.mlxLocalASRTuningSettings) var mlxLocalASRTuningSettingsRaw = "{}"
    @AppStorage(AppPreferenceKey.userMainLanguageCodes) var userMainLanguageCodesRaw = UserMainLanguageOption.defaultStoredSelectionValue
    @AppStorage(AppPreferenceKey.remoteLLMSelectedProvider) var remoteLLMSelectedProviderRaw = RemoteLLMProvider.openAI.rawValue
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.translationRemoteLLMProvider) var translationRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.rewriteRemoteLLMProvider) var rewriteRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.useHfMirror) var useHfMirror = false
    @AppStorage(AppPreferenceKey.modelStorageRootPath) var modelStorageRootPath = ""
    @AppStorage(AppPreferenceKey.interfaceLanguage) var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.featureSettings) var featureSettingsRaw = ""

    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var whisperModelManager: WhisperKitModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager
    @ObservedObject var mainWindowState: MainWindowVisibilityState
    let missingConfigurationIssues: [ConfigurationTransferManager.MissingConfigurationIssue]
    let navigationRequest: SettingsNavigationRequest?
    let isActive: Bool

    @State private var catalogTab: ModelCatalogTab = .asr
    @State private var selectedTags = Set<String>()
    @State private var cachedFeatureSettings = FeatureSettingsStore.load()
    @State private var cachedRemoteASRConfigurations = [String: RemoteProviderConfiguration]()
    @State private var cachedRemoteLLMConfigurations = [String: RemoteProviderConfiguration]()
    @State private var modelStorageDisplayPath = ""
    @State private var modelStorageSelectionError: String?
    @State var showMirrorInfo = false
    @State var editingASRProvider: RemoteASRProvider?
    @State var editingLLMProvider: RemoteLLMProvider?
    @State private var activeASRHintTarget: ASRHintTarget?
    @State var activeLocalASRConfigurationTarget: LocalASRConfigurationTarget?
    @State private var isModelDownloadSettingsPresented = false
    @State private var isTestingGlobalDownloadEndpoint = false
    @State private var isTestingChinaDownloadEndpoint = false
    @State private var expandedModelGroupIDs = Set<String>()
    @State private var collapsedModelGroupIDs = Set<String>()
    @State private var globalDownloadEndpointResult: DownloadEndpointCheckResult?
    @State private var chinaDownloadEndpointResult: DownloadEndpointCheckResult?

    let modelStateRefreshTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRaw) ?? .mlxAudio
    }

    var selectedEnhancementMode: EnhancementMode {
        EnhancementMode.resolved(
            storedRawValue: enhancementModeRaw,
            appleIntelligenceAvailable: appleIntelligenceAvailable,
            customLLMAvailable: customEnhancementModelAvailable,
            remoteLLMAvailable: remoteEnhancementModelAvailable
        )
    }

    var selectedRemoteASRProvider: RemoteASRProvider {
        RemoteASRProvider(rawValue: remoteASRSelectedProviderRaw) ?? .openAIWhisper
    }

    var selectedRemoteLLMProvider: RemoteLLMProvider {
        RemoteLLMProvider(rawValue: remoteLLMSelectedProviderRaw) ?? .openAI
    }

    var selectedTranslationModelProvider: TranslationModelProvider {
        TranslationModelProvider(rawValue: translationModelProviderRaw) ?? .customLLM
    }

    var selectedRewriteModelProvider: RewriteModelProvider {
        RewriteModelProvider(rawValue: rewriteModelProviderRaw) ?? .customLLM
    }

    var selectedTranslationFallbackModelProvider: TranslationModelProvider {
        TranslationProviderResolver.sanitizedFallbackProvider(
            TranslationModelProvider(rawValue: translationFallbackModelProviderRaw) ?? .customLLM
        )
    }

    var selectedTranslationTargetLanguage: TranslationTargetLanguage {
        TranslationTargetLanguage(rawValue: translationTargetLanguageRaw) ?? .english
    }

    var remoteASRConfigurations: [String: RemoteProviderConfiguration] {
        cachedRemoteASRConfigurations
    }

    var remoteLLMConfigurations: [String: RemoteProviderConfiguration] {
        cachedRemoteLLMConfigurations
    }

    var selectedUserLanguageCodes: [String] {
        UserMainLanguageOption.storedSelection(from: userMainLanguageCodesRaw)
    }

    var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return TextEnhancer.isAvailable
        }
        return false
    }

    var customEnhancementModelAvailable: Bool {
        customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo)
    }

    var remoteEnhancementModelAvailable: Bool {
        let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: selectedRemoteLLMProvider,
            stored: remoteLLMConfigurations
        )
        return configuration.isConfigured && configuration.hasUsableModel
    }

    private var featureSettings: FeatureSettings {
        cachedFeatureSettings
    }

    private var catalogBuilder: ModelCatalogBuilder {
        ModelCatalogBuilder(
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager,
            customLLMManager: customLLMManager,
            remoteASRConfigurations: remoteASRConfigurations,
            remoteLLMConfigurations: remoteLLMConfigurations,
            featureSettings: featureSettings,
            hasIssue: hasIssue(for:),
            modelStatusText: modelStatusText(for:),
            whisperModelStatusText: whisperModelStatusText(for:),
            customLLMStatusText: customLLMStatusText(for:),
            customLLMBadgeText: customLLMBadgeText(for:),
            remoteASRStatusText: { provider, configuration in
                remoteASRStatusText(for: provider, configuration: configuration)
            },
            remoteLLMBadgeText: remoteLLMBadgeText(for:),
            primaryUserLanguageCode: selectedUserLanguageCodes.first,
            isDownloadingModel: isDownloadingModel,
            isAnotherModelDownloading: isAnotherModelDownloading,
            isDownloadingWhisperModel: isDownloadingWhisperModel,
            isAnotherWhisperModelDownloading: isAnotherWhisperModelDownloading,
            isDownloadingCustomLLM: isDownloadingCustomLLM,
            isAnotherCustomLLMDownloading: isAnotherCustomLLMDownloading,
            downloadModel: downloadModel,
            deleteModel: deleteModel,
            openMLXModelDirectory: openMLXModelDirectory,
            downloadWhisperModel: downloadWhisperModel,
            deleteWhisperModel: deleteWhisperModel,
            openWhisperModelDirectory: openWhisperModelDirectory,
            presentWhisperSettings: {
                activeLocalASRConfigurationTarget = .whisper(modelID: whisperModelID)
            },
            downloadCustomLLM: downloadCustomLLM,
            deleteCustomLLM: deleteCustomLLM,
            openCustomLLMModelDirectory: openCustomLLMModelDirectory,
            configureASRProvider: { editingASRProvider = $0 },
            configureLLMProvider: { editingLLMProvider = $0 },
            showASRHintTarget: { activeASRHintTarget = $0 }
        )
    }

    private var allEntries: [ModelCatalogEntry] {
        switch catalogTab {
        case .asr:
            return prioritizedEntries(catalogBuilder.asrEntries())
        case .llm:
            return prioritizedEntries(catalogBuilder.llmEntries())
        }
    }

    private var locationScopedEntriesForTags: [ModelCatalogEntry] {
        if selectedTags.contains(localized("Local")) {
            return allEntries.filter { $0.filterTags.contains(localized("Local")) }
        }
        if selectedTags.contains(localized("Remote")) {
            return allEntries.filter { $0.filterTags.contains(localized("Remote")) }
        }
        return allEntries
    }

    private var availableTags: [String] {
        let locationTags = Set(allEntries.flatMap(\.filterTags)).intersection(ModelCatalogTag.locationTags)
        let tags = locationTags.union(Set(locationScopedEntriesForTags.flatMap(\.filterTags)))
        return ModelCatalogTag.priority.compactMap { tags.contains($0) ? $0 : nil }
    }

    private var availableTagGroups: [[String]] {
        let available = Set(availableTags)
        var groups = [[String]]()
        let locationGroup = ModelCatalogTag.groups[0].filter { available.contains($0) }
        if !locationGroup.isEmpty {
            groups.append(locationGroup)
        }
        groups.append(
            contentsOf: ModelCatalogTag.groups.dropFirst()
                .map { group in
                    group.filter { available.contains($0) }
                }
                .filter { !$0.isEmpty }
        )
        return groups
    }

    private var filteredEntries: [ModelCatalogEntry] {
        guard !selectedTags.isEmpty else { return allEntries }
        return allEntries.filter { selectedTags.isSubset(of: Set($0.filterTags)) }
    }

    private var displayItems: [ModelCatalogDisplayItem] {
        LocalModelSeriesGrouping.modelCatalogItems(from: filteredEntries)
    }

    private func prioritizedEntries(_ entries: [ModelCatalogEntry]) -> [ModelCatalogEntry] {
        entries.enumerated()
            .sorted { lhs, rhs in
                let lhsInUse = !lhs.element.usageLocations.isEmpty
                let rhsInUse = !rhs.element.usageLocations.isEmpty
                if lhsInUse != rhsInUse {
                    return lhsInUse && !rhsInUse
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private var tagFilterBar: some View {
        Group {
            if !availableTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(availableTagGroups.enumerated()), id: \.offset) { index, group in
                            HStack(spacing: 8) {
                                ForEach(group, id: \.self) { tag in
                                    ModelTagChip(
                                        title: tag,
                                        isSelected: selectedTags.contains(tag),
                                        action: { toggleTag(tag) }
                                    )
                                }
                            }

                            if index < availableTagGroups.count - 1 {
                                Rectangle()
                                    .fill(SettingsUIStyle.subtleBorderColor.opacity(0.95))
                                    .frame(width: 1, height: 20)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var modelCatalogContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if filteredEntries.isEmpty {
                    ModelEmptyStateView()
                } else {
                    ForEach(displayItems) { item in
                        modelCatalogItemView(item)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 430)
    }

    @ViewBuilder
    private func modelCatalogItemView(_ item: ModelCatalogDisplayItem) -> some View {
        switch item {
        case .row(let entry):
            ModelCatalogRow(entry: entry)
        case .group(let group):
            ModelCatalogGroupCard(
                group: group,
                isExpanded: isModelGroupExpanded(group),
                onToggle: { toggleModelGroup(group) }
            )
        }
    }

    private func isModelGroupExpanded(_ group: ModelCatalogGroupSection) -> Bool {
        if expandedModelGroupIDs.contains(group.id) {
            return true
        }
        if collapsedModelGroupIDs.contains(group.id) {
            return false
        }
        return group.defaultExpanded
    }

    private func toggleModelGroup(_ group: ModelCatalogGroupSection) {
        let isExpanded = isModelGroupExpanded(group)
        if group.defaultExpanded {
            if isExpanded {
                collapsedModelGroupIDs.insert(group.id)
            } else {
                collapsedModelGroupIDs.remove(group.id)
            }
            expandedModelGroupIDs.remove(group.id)
            return
        }

        if isExpanded {
            expandedModelGroupIDs.remove(group.id)
        } else {
            expandedModelGroupIDs.insert(group.id)
        }
        collapsedModelGroupIDs.remove(group.id)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            modelTabHeader
            tagFilterBar
            modelCatalogContent
        }
    }

    private var contentWithLifecycle: some View {
        mainContent
        .onAppear(perform: handleOnAppear)
        .onAppear(perform: reloadCachedConfigurationState)
        .onAppear(perform: refreshModelStorageDisplayPath)
        .onChange(of: modelRepo) { _, newValue in
            let canonicalRepo = MLXModelManager.canonicalModelRepo(newValue)
            if canonicalRepo != newValue {
                modelRepo = canonicalRepo
                return
            }
            mlxModelManager.updateModel(repo: canonicalRepo)
        }
        .onChange(of: whisperModelID) { _, newValue in
            let canonicalModelID = WhisperKitModelManager.canonicalModelID(newValue)
            if canonicalModelID != newValue {
                whisperModelID = canonicalModelID
                return
            }
            whisperModelManager.updateModel(id: canonicalModelID)
        }
        .onChange(of: whisperKeepResidentLoaded) { _, _ in
            whisperModelManager.refreshResidencyPolicy()
            guard selectedEngine == .whisperKit, whisperKeepResidentLoaded else { return }
            Task { @MainActor in
                whisperModelManager.beginActiveUse()
                defer { whisperModelManager.endActiveUse() }
                _ = try? await whisperModelManager.loadWhisper()
            }
        }
        .onChange(of: engineRaw) { _, _ in
            whisperModelManager.refreshResidencyPolicy()
            guard selectedEngine == .whisperKit, whisperKeepResidentLoaded else { return }
            Task { @MainActor in
                whisperModelManager.beginActiveUse()
                defer { whisperModelManager.endActiveUse() }
                _ = try? await whisperModelManager.loadWhisper()
            }
        }
        .onChange(of: customLLMRepo) { _, newValue in
            customLLMManager.updateModel(repo: newValue)
            ensureTranslationModelSelectionConsistency()
            ensureRewriteModelSelectionConsistency()
        }
        .onChange(of: translationModelProviderRaw) { _, _ in
            syncTranslationFallbackProvider()
            ensureTranslationModelSelectionConsistency()
        }
        .onChange(of: rewriteModelProviderRaw) { _, _ in
            ensureRewriteModelSelectionConsistency()
        }
        .onChange(of: remoteLLMProviderConfigurationsRaw) { _, _ in
            cachedRemoteLLMConfigurations = RemoteModelConfigurationStore.loadConfigurations(
                from: remoteLLMProviderConfigurationsRaw,
                sensitiveValueLoading: .metadataOnly
            )
            ensureTranslationModelSelectionConsistency()
            ensureRewriteModelSelectionConsistency()
        }
        .onChange(of: remoteASRProviderConfigurationsRaw) { _, _ in
            cachedRemoteASRConfigurations = RemoteModelConfigurationStore.loadConfigurations(
                from: remoteASRProviderConfigurationsRaw,
                sensitiveValueLoading: .metadataOnly
            )
        }
        .onChange(of: useHfMirror) { _, _ in
            updateMirrorSetting()
        }
        .onChange(of: modelStorageRootPath) { _, _ in
            refreshModelStorageDisplayPath()
        }
        .onChange(of: featureSettingsRaw) { _, _ in
            cachedFeatureSettings = FeatureSettingsStore.load(defaults: .standard)
            pruneSelectedTags()
        }
        .onChange(of: catalogTab) { _, _ in
            pruneSelectedTags()
        }
        .onChange(of: selectedTags) { _, _ in
            pruneSelectedTags()
        }
        .onReceive(modelStateRefreshTimer) { _ in
            guard isActive else { return }
            guard mainWindowState.isVisible else { return }
            guard shouldPollModelState else { return }
            refreshModelInstallStateIfNeeded()
            pruneSelectedTags()
        }
    }

    private var contentWithSheets: some View {
        contentWithLifecycle
        .sheet(item: $editingASRProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: asrCredentialHint(for: provider),
                showsDoubaoFields: provider == .doubaoASR,
                testTarget: .asr(provider),
                configuration: RemoteModelConfigurationStore.resolvedASRConfiguration(
                    provider: provider,
                    stored: RemoteModelConfigurationStore.loadConfigurations(from: remoteASRProviderConfigurationsRaw)
                )
            ) { updated in
                saveRemoteASRConfiguration(updated)
            }
        }
        .sheet(item: $editingLLMProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: nil,
                showsDoubaoFields: false,
                testTarget: .llm(provider),
                configuration: RemoteModelConfigurationStore.resolvedLLMConfiguration(
                    provider: provider,
                    stored: RemoteModelConfigurationStore.loadConfigurations(from: remoteLLMProviderConfigurationsRaw)
                )
            ) { updated in
                saveRemoteLLMConfiguration(updated)
            }
        }
        .sheet(item: $activeASRHintTarget) { target in
            ASRHintSettingsSheet(
                target: target,
                userLanguageCodes: selectedUserLanguageCodes,
                mlxModelRepo: target == .mlxAudio ? modelRepo : nil,
                initialSettings: resolvedASRHintSettings(for: target)
            ) { updated in
                saveASRHintSettings(updated, for: target)
            }
        }
        .sheet(item: $activeLocalASRConfigurationTarget) { target in
            localASRConfigurationSheet(for: target)
        }
        .sheet(isPresented: $isModelDownloadSettingsPresented) {
            modelDownloadSettingsSheet
        }
    }

    var body: some View {
        contentWithSheets
        .id(interfaceLanguageRaw)
    }

    private func reloadCachedConfigurationState() {
        cachedFeatureSettings = FeatureSettingsStore.load(defaults: .standard)
        cachedRemoteASRConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: remoteASRProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
        cachedRemoteLLMConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: remoteLLMProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
    }

    private func chooseModelStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = ModelStorageDirectoryManager.resolvedRootURL()
        panel.prompt = String(localized: "Choose")

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        do {
            try ModelStorageDirectoryManager.saveUserSelectedRootURL(selectedURL)
            modelStorageSelectionError = nil
            refreshModelStorageDisplayPath()
        } catch {
            let format = NSLocalizedString("Failed to update model storage path: %@", comment: "")
            modelStorageSelectionError = String(format: format, error.localizedDescription)
        }
    }

    private func refreshModelStorageDisplayPath() {
        let resolved = ModelStorageDirectoryManager.resolvedRootURL().path
        modelStorageDisplayPath = resolved
        if modelStorageRootPath != resolved {
            modelStorageRootPath = resolved
        }
    }

    private func openModelStorageInFinder() {
        Task { @MainActor in
            ModelStorageDirectoryManager.openRootInFinder()
        }
    }

    private func testGlobalDownloadEndpoint() {
        Task {
            await runDownloadEndpointCheck(
                using: MLXModelManager.defaultHubBaseURL,
                isTesting: { isTestingGlobalDownloadEndpoint = $0 },
                setResult: { globalDownloadEndpointResult = $0 }
            )
        }
    }

    private func testChinaDownloadEndpoint() {
        Task {
            await runDownloadEndpointCheck(
                using: MLXModelManager.mirrorHubBaseURL,
                isTesting: { isTestingChinaDownloadEndpoint = $0 },
                setResult: { chinaDownloadEndpointResult = $0 }
            )
        }
    }

    private func runDownloadEndpointCheck(
        using baseURL: URL,
        isTesting: @escaping (Bool) -> Void,
        setResult: @escaping (DownloadEndpointCheckResult) -> Void
    ) async {
        await MainActor.run { isTesting(true) }
        let result = await measureDownloadEndpoint(baseURL: baseURL)
        await MainActor.run {
            setResult(result)
            isTesting(false)
        }
    }

    private func measureDownloadEndpoint(baseURL: URL) async -> DownloadEndpointCheckResult {
        let targetURL = baseURL.appending(path: "robots.txt")
        var request = URLRequest(url: targetURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let startedAt = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
            let bytesPerSecond = Double(data.count) / elapsed

            let latencyText = AppLocalization.format("Latency: %@", String(format: "%.0f ms", elapsed * 1000))
            let throughputText = AppLocalization.format(
                "Speed: %@/s",
                ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file)
            )

            if let httpResponse = response as? HTTPURLResponse, !(200..<400).contains(httpResponse.statusCode) {
                return DownloadEndpointCheckResult(
                    isReachable: false,
                    latencyText: latencyText,
                    throughputText: throughputText,
                    detailText: AppLocalization.format("Request failed (HTTP %@).", String(httpResponse.statusCode))
                )
            }

            return DownloadEndpointCheckResult(
                isReachable: true,
                latencyText: latencyText,
                throughputText: throughputText,
                detailText: AppLocalization.format("Downloaded %@ to verify connectivity.", ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
            )
        } catch {
            return DownloadEndpointCheckResult(
                isReachable: false,
                latencyText: localized("Latency: --"),
                throughputText: localized("Speed: --"),
                detailText: AppLocalization.format("Connection failed: %@", error.localizedDescription)
            )
        }
    }

    private var modelTabHeader: some View {
        HStack(spacing: 10) {
            ModelCatalogTabPicker(selectedTab: $catalogTab)

            Spacer(minLength: 0)

            if !missingConfigurationIssues.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(
                        missingConfigurationIssues.count == 1
                        ? localized("1 model needs setup")
                        : AppLocalization.format("%d models need setup", missingConfigurationIssues.count)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                )
            }

            Text(AppLocalization.format("%d items", filteredEntries.count))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isModelDownloadSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(SettingsCompactIconButtonStyle())
        }
    }

    private var modelDownloadSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Model Download Settings"))
                .font(.title3.weight(.semibold))

            GeneralSettingsCard(title: "Model Storage") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(localized("Storage Path"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: openModelStorageInFinder) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.caption)
                            Text(modelStorageDisplayPath.isEmpty ? ModelStorageDirectoryManager.defaultRootURL.path : modelStorageDisplayPath)
                                .underline()
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "arrow.up.forward.square")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(SettingsInlineSelectorButtonStyle())
                    .help(localized("Open folder"))

                    Button(localized("Choose")) {
                        chooseModelStorageDirectory()
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                }

                Text(localized("New model downloads are stored here. Switching the path will not move existing model files."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let modelStorageSelectionError, !modelStorageSelectionError.isEmpty {
                    Text(modelStorageSelectionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            GeneralSettingsCard(title: "Download Source") {
                Toggle(localized("Use China mirror"), isOn: $useHfMirror)

                Text(localized("Use the China mirror when downloading local models. This only changes the download source for Hugging Face based local models."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                endpointTestRow(
                    title: LocalizedStringKey(localized("Global")),
                    subtitle: "https://huggingface.co",
                    isTesting: isTestingGlobalDownloadEndpoint,
                    result: globalDownloadEndpointResult,
                    actionTitle: LocalizedStringKey(localized("Test")),
                    action: testGlobalDownloadEndpoint
                )

                endpointTestRow(
                    title: LocalizedStringKey(localized("China Mirror")),
                    subtitle: "https://hf-mirror.com",
                    isTesting: isTestingChinaDownloadEndpoint,
                    result: chinaDownloadEndpointResult,
                    actionTitle: LocalizedStringKey(localized("Test")),
                    action: testChinaDownloadEndpoint
                )
            }

            SettingsDialogActionRow {
                Button(localized("Done")) {
                    isModelDownloadSettingsPresented = false
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    @ViewBuilder
    private func endpointTestRow(
        title: LocalizedStringKey,
        subtitle: String,
        isTesting: Bool,
        result: DownloadEndpointCheckResult?,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                if let result {
                    OnboardingPermissionStatusBadge(isGranted: result.isReachable)
                }

                Button(actionTitle, action: action)
                    .buttonStyle(SettingsPillButtonStyle())
                    .disabled(isTesting)
            }

            if let result {
                Text("\(result.latencyText) · \(result.throughputText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.detailText)
                    .font(.caption)
                    .foregroundStyle(
                        result.isReachable
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(Color.orange)
                    )
            }
        }
    }

    private var shouldPollModelState: Bool {
        isModelStatePollingRequired(for: mlxModelManager.state)
        || isWhisperStatePollingRequired(for: whisperModelManager.state)
        || isCustomLLMStatePollingRequired(for: customLLMManager.state)
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            if ModelCatalogTag.exclusiveSelectionTags.contains(tag) {
                selectedTags.subtract(ModelCatalogTag.exclusiveSelectionTags)
            }
            selectedTags.insert(tag)
        }
    }

    private func pruneSelectedTags() {
        selectedTags = selectedTags.intersection(Set(availableTags))
    }

    private func isModelStatePollingRequired(for state: MLXModelManager.ModelState) -> Bool {
        switch state {
        case .downloading, .loading:
            return true
        case .notDownloaded, .downloaded, .ready, .error:
            return false
        }
    }

    private func isWhisperStatePollingRequired(for state: WhisperKitModelManager.ModelState) -> Bool {
        switch state {
        case .downloading, .loading:
            return true
        case .notDownloaded, .downloaded, .ready, .error:
            return false
        }
    }

    private func isCustomLLMStatePollingRequired(for state: CustomLLMModelManager.ModelState) -> Bool {
        switch state {
        case .downloading:
            return true
        case .notDownloaded, .downloaded, .error:
            return false
        }
    }
}

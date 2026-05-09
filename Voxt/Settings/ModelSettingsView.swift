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

enum LocalModelRemovalTarget: Equatable, Identifiable {
    case mlx(repo: String)
    case whisper(modelID: String)
    case customLLM(repo: String)

    var id: String {
        switch self {
        case .mlx(let repo):
            return "mlx:\(MLXModelManager.canonicalModelRepo(repo))"
        case .whisper(let modelID):
            return "whisper:\(WhisperKitModelManager.canonicalModelID(modelID))"
        case .customLLM(let repo):
            return "custom-llm:\(CustomLLMModelManager.canonicalModelRepo(repo))"
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
    @AppStorage(AppPreferenceKey.enhancementSystemPrompt) var systemPrompt = ""
    @AppStorage(AppPreferenceKey.translationSystemPrompt) var translationPrompt = ""
    @AppStorage(AppPreferenceKey.rewriteSystemPrompt) var rewritePrompt = ""
    @AppStorage(AppPreferenceKey.mlxModelRepo) var modelRepo = MLXModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.whisperModelID) var whisperModelID = WhisperKitModelManager.defaultModelID
    @AppStorage(AppPreferenceKey.whisperTemperature) var whisperTemperature = 0.0
    @AppStorage(AppPreferenceKey.whisperVADEnabled) var whisperVADEnabled = true
    @AppStorage(AppPreferenceKey.whisperTimestampsEnabled) var whisperTimestampsEnabled = false
    @AppStorage(AppPreferenceKey.whisperRealtimeEnabled) var whisperRealtimeEnabled = false
    @AppStorage(AppPreferenceKey.localModelMemoryOptimizationEnabled) var localModelMemoryOptimizationEnabled = true
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

    @State var catalogTab: ModelCatalogTab = .asr
    @State var selectedTags = Set<String>()
    @State var cachedFeatureSettings = FeatureSettingsStore.load()
    @State var cachedRemoteASRConfigurations = [String: RemoteProviderConfiguration]()
    @State var cachedRemoteLLMConfigurations = [String: RemoteProviderConfiguration]()
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
    @State var catalogSnapshot = ModelSettingsCatalogSnapshot.empty
    @State var pendingModelRemovalTarget: LocalModelRemovalTarget?
    @State var uninstallingModelTarget: LocalModelRemovalTarget?

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
            isPausedModel: isPausedModel,
            isDownloadingWhisperModel: isDownloadingWhisperModel,
            isPausedWhisperModel: isPausedWhisperModel,
            isAnotherWhisperModelDownloading: isAnotherWhisperModelDownloading,
            isDownloadingCustomLLM: isDownloadingCustomLLM,
            isPausedCustomLLM: isPausedCustomLLM,
            isAnotherCustomLLMDownloading: isAnotherCustomLLMDownloading,
            isUninstallingModel: isUninstallingModel,
            isUninstallingWhisperModel: isUninstallingWhisperModel,
            isUninstallingCustomLLM: isUninstallingCustomLLM,
            downloadModel: downloadModel,
            pauseModelDownload: { mlxModelManager.pauseDownload(repo: $0) },
            cancelModelDownload: {
                mlxModelManager.cancelDownload(repo: $0)
                refreshCatalogSnapshot()
            },
            deleteModel: requestDeleteModel,
            openMLXModelDirectory: openMLXModelDirectory,
            presentMLXSettings: { repo in
                activeLocalASRConfigurationTarget = .mlx(repo: repo)
            },
            downloadWhisperModel: downloadWhisperModel,
            cancelWhisperDownload: {
                whisperModelManager.cancelDownload(id: $0)
                refreshCatalogSnapshot()
            },
            deleteWhisperModel: requestDeleteWhisperModel,
            openWhisperModelDirectory: openWhisperModelDirectory,
            presentWhisperSettings: {
                activeLocalASRConfigurationTarget = .whisper(modelID: whisperModelID)
            },
            downloadCustomLLM: downloadCustomLLM,
            cancelCustomLLMDownload: {
                customLLMManager.cancelDownload(repo: $0)
                refreshCatalogSnapshot()
            },
            deleteCustomLLM: requestDeleteCustomLLM,
            openCustomLLMModelDirectory: openCustomLLMModelDirectory,
            configureASRProvider: { editingASRProvider = $0 },
            configureLLMProvider: { editingLLMProvider = $0 },
            showASRHintTarget: { activeASRHintTarget = $0 }
        )
    }

    private var allEntries: [ModelCatalogEntry] { catalogSnapshot.allEntries }

    private var availableTags: [String] { catalogSnapshot.availableTags }

    private var availableTagGroups: [[String]] { catalogSnapshot.availableTagGroups }

    private var filteredEntries: [ModelCatalogEntry] { catalogSnapshot.filteredEntries }

    private var displayItems: [ModelCatalogDisplayItem] { catalogSnapshot.displayItems }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            modelTabHeader
            tagFilterBar
            modelCatalogContent
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
        .alert(item: $pendingModelRemovalTarget) { target in
            Alert(
                title: Text(AppLocalization.localizedString("Uninstall Model?")),
                message: Text(uninstallConfirmationMessage(for: target)),
                primaryButton: .destructive(Text(AppLocalization.localizedString("Uninstall"))) {
                    confirmDeleteModel(target)
                },
                secondaryButton: .cancel()
            )
        }
    }

    var body: some View {
        contentWithSheets
        .id(interfaceLanguageRaw)
    }

    func reloadCachedConfigurationState() {
        cachedFeatureSettings = FeatureSettingsStore.load(defaults: .standard)
        cachedRemoteASRConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: remoteASRProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
        cachedRemoteLLMConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: remoteLLMProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
        refreshCatalogSnapshot()
    }

    func refreshCatalogSnapshot() {
        let entries = switch catalogTab {
        case .asr:
            catalogBuilder.asrEntries()
        case .llm:
            catalogBuilder.llmEntries()
        }

        catalogSnapshot = ModelSettingsCatalogSnapshotBuilder.build(
            entries: entries,
            selectedTags: selectedTags
        )
    }

    private func chooseModelStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = ModelStorageDirectoryManager.resolvedRootURL()
        panel.prompt = localized("Choose")

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        do {
            try ModelStorageDirectoryManager.saveUserSelectedRootURL(selectedURL)
            modelStorageSelectionError = nil
            refreshAllModelStorageRoots()
            refreshModelStorageDisplayPath()
            refreshCatalogSnapshot()
        } catch {
            let format = NSLocalizedString("Failed to update model storage path: %@", comment: "")
            modelStorageSelectionError = String(format: format, error.localizedDescription)
        }
    }

    func refreshModelStorageDisplayPath() {
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
                Menu {
                    ForEach(missingConfigurationIssueDescriptions, id: \.self) { description in
                        Text(description)
                    }
                } label: {
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
                .menuStyle(.borderlessButton)
                .help(missingConfigurationIssueDescriptions.joined(separator: "\n"))
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

            Button(action: openModelDebugWindow) {
                Text(localized("Debug"))
            }
            .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 12))
        }
    }

    private var modelDownloadSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Model Download Settings"))
                .font(.title3.weight(.semibold))

            GeneralSettingsCard(titleText: localized("Model Storage")) {
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

            GeneralSettingsCard(titleText: localized("Memory")) {
                Toggle(localized("Memory Optimization"), isOn: $localModelMemoryOptimizationEnabled)

                Text(localized("When enabled, Voxt unloads idle local ASR and local LLM models after cooldown to reduce memory usage. Turn it off to keep loaded local models resident for faster reuse."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeneralSettingsCard(titleText: localized("Download Source")) {
                Toggle(localized("Use China mirror"), isOn: $useHfMirror)

                Text(localized("Use the China mirror when downloading local models. This only changes the download source for Hugging Face based local models."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                endpointTestRow(
                    title: localized("Global"),
                    subtitle: "https://huggingface.co",
                    isTesting: isTestingGlobalDownloadEndpoint,
                    result: globalDownloadEndpointResult,
                    actionTitle: localized("Test"),
                    action: testGlobalDownloadEndpoint
                )

                endpointTestRow(
                    title: localized("China Mirror"),
                    subtitle: "https://hf-mirror.com",
                    isTesting: isTestingChinaDownloadEndpoint,
                    result: chinaDownloadEndpointResult,
                    actionTitle: localized("Test"),
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
        title: String,
        subtitle: String,
        isTesting: Bool,
        result: DownloadEndpointCheckResult?,
        actionTitle: String,
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

    var shouldPollModelState: Bool {
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

    func pruneSelectedTags() {
        selectedTags = selectedTags.intersection(Set(availableTags))
    }

    private func isModelStatePollingRequired(for state: MLXModelManager.ModelState) -> Bool {
        switch state {
        case .downloading, .loading:
            return true
        case .notDownloaded, .downloaded, .paused, .ready, .error:
            return false
        }
    }

    private func isWhisperStatePollingRequired(for state: WhisperKitModelManager.ModelState) -> Bool {
        switch state {
        case .downloading, .loading:
            return true
        case .notDownloaded, .downloaded, .paused, .ready, .error:
            return false
        }
    }

    private func isCustomLLMStatePollingRequired(for state: CustomLLMModelManager.ModelState) -> Bool {
        switch state {
        case .downloading:
            return true
        case .notDownloaded, .downloaded, .paused, .error:
            return false
        }
    }

    private func openModelDebugWindow() {
        guard let appDelegate = AppDelegate.shared else { return }
        switch catalogTab {
        case .asr:
            ASRDebugWindowManager.shared.present(appDelegate: appDelegate)
        case .llm:
            LLMDebugWindowManager.shared.present(appDelegate: appDelegate)
        }
    }

    private var missingConfigurationIssueDescriptions: [String] {
        missingConfigurationIssues.map(missingConfigurationIssueDescription(for:))
    }

    private func missingConfigurationIssueDescription(
        for issue: ConfigurationTransferManager.MissingConfigurationIssue
    ) -> String {
        switch issue.scope {
        case .remoteASRProvider(let provider):
            return AppLocalization.format("%@ %@: %@", provider.title, localized("ASR"), issue.message)
        case .remoteLLMProvider(let provider):
            return AppLocalization.format("%@ %@: %@", provider.title, localized("LLM"), issue.message)
        case .mlxModel(let repo):
            return AppLocalization.format("%@ %@: %@", mlxModelManager.displayTitle(for: repo), localized("ASR"), issue.message)
        case .whisperModel(let modelID):
            return AppLocalization.format("%@ %@: %@", whisperModelManager.displayTitle(for: modelID), localized("Whisper"), issue.message)
        case .customLLMModel(let repo):
            return AppLocalization.format("%@ %@: %@", customLLMManager.displayTitle(for: repo), localized("LLM"), issue.message)
        case .translationRemoteLLM(let provider):
            return AppLocalization.format("%@ %@: %@", provider.title, localized("Translation"), issue.message)
        case .rewriteRemoteLLM(let provider):
            return AppLocalization.format("%@ %@: %@", provider.title, localized("Rewrite"), issue.message)
        case .translationCustomLLM(let repo):
            return AppLocalization.format("%@ %@: %@", customLLMManager.displayTitle(for: repo), localized("Translation"), issue.message)
        case .rewriteCustomLLM(let repo):
            return AppLocalization.format("%@ %@: %@", customLLMManager.displayTitle(for: repo), localized("Rewrite"), issue.message)
        }
    }
}

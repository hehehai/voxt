import SwiftUI
import AppKit
import Combine

struct ModelSettingsView: View {
    @AppStorage(AppPreferenceKey.transcriptionEngine) private var engineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.enhancementMode) private var enhancementModeRaw = EnhancementMode.off.rawValue
    @AppStorage(AppPreferenceKey.enhancementSystemPrompt) private var systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
    @AppStorage(AppPreferenceKey.translationSystemPrompt) private var translationPrompt = AppPreferenceKey.defaultTranslationPrompt
    @AppStorage(AppPreferenceKey.mlxModelRepo) private var modelRepo = MLXModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.customLLMModelRepo) private var customLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationCustomLLMModelRepo) private var translationCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationModelProvider) private var translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.remoteASRSelectedProvider) private var remoteASRSelectedProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) private var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.remoteLLMSelectedProvider) private var remoteLLMSelectedProviderRaw = RemoteLLMProvider.openAI.rawValue
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) private var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.translationRemoteLLMProvider) private var translationRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.useHfMirror) private var useHfMirror = false
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager
    @State private var showMirrorInfo = false
    @State private var editingASRProvider: RemoteASRProvider?
    @State private var editingLLMProvider: RemoteLLMProvider?
    private let modelStateRefreshTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    private var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRaw) ?? .mlxAudio
    }

    private var selectedEnhancementMode: EnhancementMode {
        EnhancementMode(rawValue: enhancementModeRaw) ?? .off
    }

    private var selectedRemoteASRProvider: RemoteASRProvider {
        RemoteASRProvider(rawValue: remoteASRSelectedProviderRaw) ?? .openAIWhisper
    }

    private var selectedRemoteLLMProvider: RemoteLLMProvider {
        RemoteLLMProvider(rawValue: remoteLLMSelectedProviderRaw) ?? .openAI
    }

    private var selectedTranslationModelProvider: TranslationModelProvider {
        TranslationModelProvider(rawValue: translationModelProviderRaw) ?? .customLLM
    }

    private var remoteASRConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(from: remoteASRProviderConfigurationsRaw)
    }

    private var remoteLLMConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(from: remoteLLMProviderConfigurationsRaw)
    }

    private var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return TextEnhancer.isAvailable
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Engine")
                        .font(.headline)

                    Picker("Engine", selection: $engineRaw) {
                        ForEach(TranscriptionEngine.allCases) { engine in
                            Text(engine.titleKey).tag(engine.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)

                    Text(selectedEngine.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if selectedEngine == .mlxAudio {
                        mlxModelSection
                    }

                    if selectedEngine == .remote {
                        remoteASRSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text Enhancement")
                        .font(.headline)

                    Picker("Enhancement", selection: $enhancementModeRaw) {
                        Text(EnhancementMode.off.titleKey).tag(EnhancementMode.off.rawValue)
                        Text(EnhancementMode.appleIntelligence.titleKey).tag(EnhancementMode.appleIntelligence.rawValue)
                        Text(EnhancementMode.customLLM.titleKey).tag(EnhancementMode.customLLM.rawValue)
                        Text(EnhancementMode.remoteLLM.titleKey).tag(EnhancementMode.remoteLLM.rawValue)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)

                    if selectedEnhancementMode == .appleIntelligence {
                        appleIntelligenceSection
                    }

                    if selectedEnhancementMode == .customLLM {
                        customLLMSection
                    }

                    if selectedEnhancementMode == .remoteLLM {
                        remoteLLMSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Translation")
                        .font(.headline)

                    Picker("Translation Provider", selection: $translationModelProviderRaw) {
                        ForEach(TranslationModelProvider.allCases) { provider in
                            Text(provider.titleKey).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)

                    HStack(alignment: .center, spacing: 12) {
                        Text(translationModelLabelText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if translationModelOptions.isEmpty {
                            Text("Not available")
                                .foregroundStyle(.tertiary)
                        } else {
                            Picker("Translation Model", selection: translationModelSelectionBinding) {
                                ForEach(translationModelOptions) { option in
                                    Text(option.title).tag(option.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .trailing)
                        }
                    }

                    if translationModelOptions.isEmpty {
                        Text(translationModelEmptyStateText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text("Translation Prompt")
                        .font(.subheadline.weight(.medium))
                    PromptEditorView(text: $translationPrompt)

                    HStack {
                        Text("Use {target_language} placeholder in the prompt for selected target language.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset to Default") {
                            translationPrompt = AppPreferenceKey.defaultTranslationPrompt
                        }
                        .controlSize(.small)
                        .disabled(translationPrompt == AppPreferenceKey.defaultTranslationPrompt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            TranscriptionTestSectionView()
        }
        .onAppear {
            let canonicalRepo = MLXModelManager.canonicalModelRepo(modelRepo)
            if canonicalRepo != modelRepo {
                modelRepo = canonicalRepo
            }
            mlxModelManager.updateModel(repo: canonicalRepo)
            mlxModelManager.prefetchAllModelSizes()

            if customLLMRepo.isEmpty {
                customLLMRepo = CustomLLMModelManager.defaultModelRepo
            }
            if !CustomLLMModelManager.isSupportedModelRepo(customLLMRepo) {
                customLLMRepo = CustomLLMModelManager.defaultModelRepo
            }
            if translationCustomLLMRepo.isEmpty {
                translationCustomLLMRepo = customLLMRepo
            }
            if !CustomLLMModelManager.isSupportedModelRepo(translationCustomLLMRepo) {
                translationCustomLLMRepo = customLLMRepo
            }
            if translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translationPrompt = AppPreferenceKey.defaultTranslationPrompt
            }
            if !TranslationModelProvider.allCases.contains(where: { $0.rawValue == translationModelProviderRaw }) {
                translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
            }
            customLLMManager.updateModel(repo: customLLMRepo)
            customLLMManager.prefetchAllModelSizes()
            if !RemoteASRProvider.allCases.contains(where: { $0.rawValue == remoteASRSelectedProviderRaw }) {
                remoteASRSelectedProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
            }
            if !RemoteLLMProvider.allCases.contains(where: { $0.rawValue == remoteLLMSelectedProviderRaw }) {
                remoteLLMSelectedProviderRaw = RemoteLLMProvider.openAI.rawValue
            }
            ensureTranslationModelSelectionConsistency()
            updateMirrorSetting()
            refreshModelInstallStateIfNeeded()
        }
        .onChange(of: modelRepo) { _, newValue in
            let canonicalRepo = MLXModelManager.canonicalModelRepo(newValue)
            if canonicalRepo != newValue {
                modelRepo = canonicalRepo
                return
            }
            mlxModelManager.updateModel(repo: canonicalRepo)
        }
        .onChange(of: customLLMRepo) { _, newValue in
            customLLMManager.updateModel(repo: newValue)
            ensureTranslationModelSelectionConsistency()
        }
        .onChange(of: translationModelProviderRaw) { _, _ in
            ensureTranslationModelSelectionConsistency()
        }
        .onChange(of: remoteLLMProviderConfigurationsRaw) { _, _ in
            ensureTranslationModelSelectionConsistency()
        }
        .onChange(of: useHfMirror) { _, _ in
            updateMirrorSetting()
        }
        .onReceive(modelStateRefreshTimer) { _ in
            refreshModelInstallStateIfNeeded()
            ensureTranslationModelSelectionConsistency()
        }
        .sheet(item: $editingASRProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: provider == .doubaoASR ? "Doubao uses App ID + Access Token for streaming API." : nil,
                showsDoubaoFields: provider == .doubaoASR,
                testTarget: .asr(provider),
                configuration: RemoteModelConfigurationStore.resolvedASRConfiguration(
                    provider: provider,
                    stored: remoteASRConfigurations
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
                    stored: remoteLLMConfigurations
                )
            ) { updated in
                saveRemoteLLMConfiguration(updated)
            }
        }
        .id(interfaceLanguageRaw)
    }

    @ViewBuilder
    private var mlxModelSection: some View {
        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.subheadline.weight(.medium))

            HStack(alignment: .center, spacing: 12) {
                Picker("Model", selection: $modelRepo) {
                    ForEach(MLXModelManager.availableModels) { model in
                        Text(model.title).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)

                Spacer()

                HStack(spacing: 6) {
                    Toggle("Use China mirror", isOn: $useHfMirror)
                        .toggleStyle(.switch)

                    Button {
                        showMirrorInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showMirrorInfo, arrowEdge: .top) {
                        Text("https://hf-mirror.com/")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
            }

            Text(modelLocalizedDescription(for: modelRepo))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        mlxModelTable

        if case .downloading(let progress, let completed, let total, let currentFile, let completedFiles, let totalFiles) = mlxModelManager.state {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    String(
                        format: NSLocalizedString("Downloading: %d%% • %@", comment: ""),
                        Int(progress * 100),
                        ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(
                    ModelDownloadProgressFormatter.fileProgressText(
                        currentFile: currentFile,
                        completedFiles: completedFiles,
                        totalFiles: totalFiles
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var appleIntelligenceSection: some View {
        Divider()

        if appleIntelligenceAvailable {
            Text("System Prompt")
                .font(.subheadline.weight(.medium))

            PromptEditorView(text: $systemPrompt)

            HStack {
                Text("Customise how Apple Intelligence enhances your transcriptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Default") {
                    systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
                }
                .controlSize(.small)
                .disabled(systemPrompt == AppPreferenceKey.defaultEnhancementPrompt)
            }
        } else {
            Text("Apple Intelligence is not available on this Mac, so system prompt enhancement cannot be used.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var customLLMSection: some View {
        Divider()

        Text("System Prompt")
            .font(.subheadline.weight(.medium))

        PromptEditorView(text: $systemPrompt)

        customLLMModelTable

        if case .downloading(let progress, let completed, let total, let currentFile, let completedFiles, let totalFiles) = customLLMManager.state {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    String(
                        format: NSLocalizedString("Custom LLM downloading: %d%% • %@", comment: ""),
                        Int(progress * 100),
                        ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(
                    ModelDownloadProgressFormatter.fileProgressText(
                        currentFile: currentFile,
                        completedFiles: completedFiles,
                        totalFiles: totalFiles
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var remoteASRSection: some View {
        Divider()

        Text("Remote ASR Providers")
            .font(.subheadline.weight(.medium))

        ModelTableView(title: "Providers", rows: remoteASRRows, maxHeight: 220)
    }

    @ViewBuilder
    private var remoteLLMSection: some View {
        Divider()

        Text("System Prompt")
            .font(.subheadline.weight(.medium))

        PromptEditorView(text: $systemPrompt)

        HStack {
            Text("Configure a remote provider and model, then click Use.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reset to Default") {
                systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
            }
            .controlSize(.small)
            .disabled(systemPrompt == AppPreferenceKey.defaultEnhancementPrompt)
        }

        ModelTableView(title: "Remote LLM Providers", rows: remoteLLMRows, maxHeight: 280)
    }

    private var mlxModelTable: some View {
        ModelTableView(title: "Models", rows: mlxRows)
    }

    private var customLLMModelTable: some View {
        ModelTableView(title: "Custom LLM Models", rows: customLLMRows, maxHeight: 260)
    }

    private var remoteASRRows: [ModelTableRow] {
        RemoteASRProvider.allCases.map { provider in
            let config = RemoteModelConfigurationStore.resolvedASRConfiguration(
                provider: provider,
                stored: remoteASRConfigurations
            )
            let status = config.isConfigured
                ? AppLocalization.format("Configured model: %@", config.model)
                : AppLocalization.localizedString("Not configured")
            return ModelTableRow(
                id: provider.rawValue,
                title: provider.title,
                isActive: selectedRemoteASRProvider == provider,
                status: status,
                actions: [
                    ModelTableAction(
                        title: LocalizedStringKey(selectedRemoteASRProvider == provider ? "Using" : "Use"),
                        isEnabled: selectedRemoteASRProvider != provider
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

    private var remoteLLMRows: [ModelTableRow] {
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
                actions: [
                    ModelTableAction(
                        title: LocalizedStringKey(selectedRemoteLLMProvider == provider ? "Using" : "Use"),
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

    private var installedCustomLLMOptions: [TranslationModelOption] {
        CustomLLMModelManager.availableModels.compactMap { model in
            guard customLLMManager.isModelDownloaded(repo: model.id) else {
                return nil
            }
            return TranslationModelOption(id: model.id, title: model.title)
        }
    }

    private var configuredRemoteLLMOptions: [TranslationModelOption] {
        RemoteLLMProvider.allCases.compactMap { provider in
            guard let config = remoteLLMConfigurations[provider.rawValue] else {
                return nil
            }
            guard config.hasUsableModel else {
                return nil
            }
            return TranslationModelOption(
                id: provider.rawValue,
                title: "\(provider.title) · \(config.model)"
            )
        }
    }

    private var translationModelOptions: [TranslationModelOption] {
        switch selectedTranslationModelProvider {
        case .remoteLLM:
            return configuredRemoteLLMOptions
        case .customLLM:
            return installedCustomLLMOptions
        }
    }

    private var translationModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedTranslationSelection },
            set: { newValue in
                switch selectedTranslationModelProvider {
                case .remoteLLM:
                    translationRemoteLLMProviderRaw = newValue
                case .customLLM:
                    translationCustomLLMRepo = newValue
                }
            }
        )
    }

    private var resolvedTranslationSelection: String {
        let options = translationModelOptions
        guard !options.isEmpty else {
            return currentTranslationSelectionRaw
        }

        if options.contains(where: { $0.id == currentTranslationSelectionRaw }) {
            return currentTranslationSelectionRaw
        }
        return options[0].id
    }

    private var currentTranslationSelectionRaw: String {
        switch selectedTranslationModelProvider {
        case .remoteLLM:
            return translationRemoteLLMProviderRaw
        case .customLLM:
            return translationCustomLLMRepo
        }
    }

    private var translationModelLabelText: String {
        selectedTranslationModelProvider == .remoteLLM ? "Remote LLM Model" : "Custom LLM Model"
    }

    private var translationModelEmptyStateText: String {
        selectedTranslationModelProvider == .remoteLLM
            ? "No configured remote LLM model yet. Configure a provider above."
            : "No installed custom LLM model yet. Install one in the table above."
    }

    private var mlxRows: [ModelTableRow] {
        MLXModelManager.availableModels.map { model in
            let isDownloaded = mlxModelManager.isModelDownloaded(repo: model.id)
            let actions: [ModelTableAction]
            if isDownloadingModel(model.id) {
                actions = [
                    ModelTableAction(title: "Cancel") {
                        mlxModelManager.cancelDownload()
                    }
                ]
            } else if mlxModelManager.isModelDownloaded(repo: model.id) {
                actions = [
                    ModelTableAction(
                        title: LocalizedStringKey(isCurrentModel(model.id) ? "Using" : "Use"),
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
                isTitleUnderlined: isDownloaded,
                onTapTitle: isDownloaded ? { openMLXModelDirectory(model.id) } : nil,
                actions: actions
            )
        }
    }

    private var customLLMRows: [ModelTableRow] {
        CustomLLMModelManager.availableModels.map { model in
            let isDownloaded = customLLMManager.isModelDownloaded(repo: model.id)
            let actions: [ModelTableAction]
            if isDownloadingCustomLLM(model.id) {
                actions = [
                    ModelTableAction(title: "Cancel") {
                        customLLMManager.cancelDownload()
                    }
                ]
            } else if customLLMManager.isModelDownloaded(repo: model.id) {
                actions = [
                    ModelTableAction(
                        title: LocalizedStringKey(isCurrentCustomLLM(model.id) ? "Using" : "Use"),
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
                isTitleUnderlined: isDownloaded,
                onTapTitle: isDownloaded ? { openCustomLLMModelDirectory(model.id) } : nil,
                actions: actions
            )
        }
    }

    private func useModel(_ repo: String) {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
        modelRepo = canonicalRepo
        mlxModelManager.updateModel(repo: canonicalRepo)
    }

    private func downloadModel(_ repo: String) {
        Task {
            await mlxModelManager.downloadModel(repo: repo)
            modelRepo = MLXModelManager.canonicalModelRepo(repo)
        }
    }

    private func deleteModel(_ repo: String) {
        mlxModelManager.deleteModel(repo: repo)
        if MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(modelRepo) {
            mlxModelManager.checkExistingModel()
        }
    }

    private func isCurrentModel(_ repo: String) -> Bool {
        MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(modelRepo)
    }

    private func isDownloadingModel(_ repo: String) -> Bool {
        guard isCurrentModel(repo) else { return false }
        if case .downloading = mlxModelManager.state {
            return true
        }
        return false
    }

    private func isAnotherModelDownloading(_ repo: String) -> Bool {
        guard case .downloading = mlxModelManager.state else { return false }
        return !isCurrentModel(repo)
    }

    private func modelStatusText(for repo: String) -> String {
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

        let installedSize = mlxModelManager.modelSizeOnDisk(repo: repo)
        if mlxModelManager.isModelDownloaded(repo: repo) {
            if installedSize.isEmpty {
                return AppLocalization.localizedString("Installed")
            }
            return AppLocalization.format("Installed (%@)", installedSize)
        }

        let remoteSize = mlxModelManager.remoteSizeText(repo: repo)
        return AppLocalization.format("Not installed (%@)", remoteSize)
    }

    private func useCustomLLM(_ repo: String) {
        customLLMRepo = repo
        customLLMManager.updateModel(repo: repo)
    }

    private func downloadCustomLLM(_ repo: String) {
        Task {
            await customLLMManager.downloadModel(repo: repo)
            customLLMRepo = repo
        }
    }

    private func deleteCustomLLM(_ repo: String) {
        customLLMManager.deleteModel(repo: repo)
        if repo == customLLMRepo {
            customLLMManager.checkExistingModel()
        }
    }

    private func isCurrentCustomLLM(_ repo: String) -> Bool {
        repo == customLLMRepo
    }

    private func isDownloadingCustomLLM(_ repo: String) -> Bool {
        guard isCurrentCustomLLM(repo) else { return false }
        if case .downloading = customLLMManager.state {
            return true
        }
        return false
    }

    private func isAnotherCustomLLMDownloading(_ repo: String) -> Bool {
        guard case .downloading = customLLMManager.state else { return false }
        return !isCurrentCustomLLM(repo)
    }

    private func customLLMStatusText(for repo: String) -> String {
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

        let installedSize = customLLMManager.modelSizeOnDisk(repo: repo)
        if customLLMManager.isModelDownloaded(repo: repo) {
            if installedSize.isEmpty {
                return AppLocalization.localizedString("Installed")
            }
            return AppLocalization.format("Installed (%@)", installedSize)
        }

        let remoteSize = customLLMManager.remoteSizeText(repo: repo)
        return AppLocalization.format("Not installed (%@)", remoteSize)
    }

    private func useRemoteASRProvider(_ provider: RemoteASRProvider) {
        remoteASRSelectedProviderRaw = provider.rawValue
        let resolved = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: provider,
            stored: remoteASRConfigurations
        )
        saveRemoteASRConfiguration(resolved)
    }

    private func saveRemoteASRConfiguration(_ configuration: RemoteProviderConfiguration) {
        var updated = remoteASRConfigurations
        updated[configuration.providerID] = configuration
        remoteASRProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfigurations(updated)
    }

    private func useRemoteLLMProvider(_ provider: RemoteLLMProvider) {
        remoteLLMSelectedProviderRaw = provider.rawValue
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: remoteLLMConfigurations
        )
        saveRemoteLLMConfiguration(resolved)
    }

    private func saveRemoteLLMConfiguration(_ configuration: RemoteProviderConfiguration) {
        var updated = remoteLLMConfigurations
        updated[configuration.providerID] = configuration
        remoteLLMProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfigurations(updated)
    }

    private func ensureTranslationModelSelectionConsistency() {
        switch selectedTranslationModelProvider {
        case .remoteLLM:
            let options = configuredRemoteLLMOptions
            guard let first = options.first else {
                translationRemoteLLMProviderRaw = ""
                return
            }
            if !options.contains(where: { $0.id == translationRemoteLLMProviderRaw }) {
                translationRemoteLLMProviderRaw = first.id
            }
        case .customLLM:
            let options = installedCustomLLMOptions
            if let first = options.first {
                if !options.contains(where: { $0.id == translationCustomLLMRepo }) {
                    translationCustomLLMRepo = first.id
                }
            } else {
                translationCustomLLMRepo = customLLMRepo
            }
        }
    }

    private func updateMirrorSetting() {
        let url = useHfMirror ? MLXModelManager.mirrorHubBaseURL : MLXModelManager.defaultHubBaseURL
        mlxModelManager.updateHubBaseURL(url)
        customLLMManager.updateHubBaseURL(url)
    }

    private func refreshModelInstallStateIfNeeded() {
        if case .downloading = mlxModelManager.state {
            // Keep current transient state during active downloads.
        } else if case .loading = mlxModelManager.state {
            // Avoid resetting while model is being loaded.
        } else {
            mlxModelManager.checkExistingModel()
        }

        if case .downloading = customLLMManager.state {
            // Keep current transient state during active downloads.
        } else {
            customLLMManager.checkExistingModel()
        }
    }

    private func openMLXModelDirectory(_ repo: String) {
        guard let folderURL = mlxModelManager.modelDirectoryURL(repo: repo) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    private func openCustomLLMModelDirectory(_ repo: String) {
        guard let folderURL = customLLMManager.modelDirectoryURL(repo: repo) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    private func modelLocalizedDescription(for repo: String) -> LocalizedStringKey {
        switch MLXModelManager.canonicalModelRepo(repo) {
        case "mlx-community/Qwen3-ASR-0.6B-4bit":
            return "Balanced quality and speed with low memory use."
        case "mlx-community/Qwen3-ASR-1.7B-bf16":
            return "High accuracy flagship model with higher memory usage."
        case "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16":
            return "Realtime-oriented model with larger memory footprint."
        case "mlx-community/parakeet-tdt-0.6b-v3":
            return "Fast, lightweight English STT."
        case "mlx-community/GLM-ASR-Nano-2512-4bit":
            return "Smallest footprint for quick drafts."
        default:
            if let model = MLXModelManager.availableModels.first(where: { $0.id == repo }) {
                return LocalizedStringKey(model.description)
            }
            return LocalizedStringKey("")
        }
    }
}

private struct TranslationModelOption: Identifiable, Hashable {
    let id: String
    let title: String
}

private struct RemoteProviderConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let providerTitle: String
    let credentialHint: String?
    let showsDoubaoFields: Bool
    let testTarget: RemoteProviderTestTarget
    let configuration: RemoteProviderConfiguration
    let onSave: (RemoteProviderConfiguration) -> Void

    @State private var selectedProviderModel = ""
    @State private var customModelID = ""
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var appID = ""
    @State private var accessToken = ""
    @State private var isTestingConnection = false
    @State private var testResultMessage: String?
    @State private var testResultIsSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.format("Configure %@", providerTitle))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Model", selection: providerModelSelectionBinding) {
                    if let llmProvider = llmProviderForPicker {
                        ForEach(llmProvider.latestModelOptions, id: \.self) { option in
                            Text(option.title).tag(option.id)
                        }
                        ForEach(llmProvider.basicModelOptions, id: \.self) { option in
                            Text(option.title).tag(option.id)
                        }
                        ForEach(llmProvider.advancedModelOptions, id: \.self) { option in
                            Text(option.title).tag(option.id)
                        }
                        Text("Custom...").tag(customModelOptionID)
                    } else {
                        ForEach(providerModelOptions, id: \.self) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                if llmProviderForPicker != nil && resolvedSelectionForPicker == customModelOptionID {
                    Text("Custom Model ID (Optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("e.g. doubao-seed-2-0-pro-260215", text: $customModelID)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if !isDoubaoASRTest {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Endpoint (Optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("https://...", text: $endpoint)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SecureField("Paste API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if showsDoubaoFields {
                VStack(alignment: .leading, spacing: 8) {
                    Text("App ID")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("App ID", text: $appID)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Access Token")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SecureField("Paste access token", text: $accessToken)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let credentialHint, !credentialHint.isEmpty {
                Text(credentialHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Test") {
                    testConnection()
                }
                .disabled(isTestingConnection)

                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    let updated = RemoteProviderConfiguration(
                        providerID: configuration.providerID,
                        model: resolvedModelValue(),
                        endpoint: isDoubaoASRTest ? "" : endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                        apiKey: isDoubaoASRTest ? "" : apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
                        accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            if let testResultMessage, !testResultMessage.isEmpty {
                Text(testResultMessage)
                    .font(.caption)
                    .foregroundStyle(testResultIsSuccess ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear {
            configureModelSelection()
            customModelID = configuration.model
            endpoint = configuration.endpoint
            apiKey = configuration.apiKey
            appID = configuration.appID
            accessToken = configuration.accessToken
        }
    }

    private func testConnection() {
        let snapshot = RemoteProviderConfiguration(
            providerID: configuration.providerID,
            model: resolvedModelValue(),
            endpoint: isDoubaoASRTest ? "" : endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: isDoubaoASRTest ? "" : apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        isTestingConnection = true
        testResultMessage = nil
        testResultIsSuccess = false
        VoxtLog.info(
            "Remote provider test started. target=\(testTargetLogName), provider=\(configuration.providerID), model=\(snapshot.model), endpoint=\(sanitizedEndpointForLog(snapshot.endpoint)), hasAPIKey=\(!snapshot.apiKey.isEmpty), hasAppID=\(!snapshot.appID.isEmpty), hasAccessToken=\(!snapshot.accessToken.isEmpty)"
        )

        Task {
            do {
                let message = try await performConnectivityTest(configuration: snapshot)
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = true
                    testResultMessage = message
                    VoxtLog.info(
                        "Remote provider test succeeded. target=\(testTargetLogName), provider=\(configuration.providerID), model=\(snapshot.model), message=\(message)"
                    )
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = false
                    testResultMessage = error.localizedDescription
                    VoxtLog.warning(
                        "Remote provider test failed. target=\(testTargetLogName), provider=\(configuration.providerID), model=\(snapshot.model), error=\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func performConnectivityTest(configuration: RemoteProviderConfiguration) async throws -> String {
        switch testTarget {
        case .asr(let provider):
            return try await testASRProvider(provider, configuration: configuration)
        case .llm(let provider):
            return try await testLLMProvider(provider, configuration: configuration)
        }
    }

    private func testASRProvider(_ provider: RemoteASRProvider, configuration: RemoteProviderConfiguration) async throws -> String {
        switch provider {
        case .doubaoASR:
            let token = configuration.accessToken
            guard !token.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -1, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Doubao Access Token is required for testing.")])
            }
            guard !configuration.appID.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -2, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Doubao App ID is required for testing.")])
            }
            let endpoint = resolvedDoubaoASREndpoint(configuration.endpoint)
            return try await testDoubaoStreamingReachability(
                endpoint: endpoint,
                appID: configuration.appID,
                accessToken: token,
                model: configuration.model
            )
        case .openAIWhisper:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -3, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("OpenAI API Key is required for testing.")])
            }
            let endpoint = resolvedASRTranscriptionEndpoint(
                endpoint: configuration.endpoint,
                defaultValue: "https://api.openai.com/v1/audio/transcriptions"
            )
            return try await testASRMultipartReachability(
                endpoint: endpoint,
                headers: ["Authorization": "Bearer \(configuration.apiKey)"],
                model: configuration.model.isEmpty ? "whisper-1" : configuration.model
            )
        case .glmASR:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -4, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("GLM API Key is required for testing.")])
            }
            let endpoint = resolvedGLMASRTranscriptionEndpoint(
                endpoint: configuration.endpoint,
                defaultValue: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions"
            )
            return try await testASRMultipartReachability(
                endpoint: endpoint,
                headers: ["Authorization": "Bearer \(configuration.apiKey)"],
                model: configuration.model.isEmpty ? "glm-asr-1" : configuration.model
            )
        }
    }

    private func testASRMultipartReachability(
        endpoint: String,
        headers: [String: String],
        model: String
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -20, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid ASR endpoint URL.")])
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = makeASRTestMultipartBody(boundary: boundary, model: model)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream, text/plain", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        logHTTPRequest(
            context: "ASR multipart test",
            request: request,
            bodyPreview: "multipart/form-data body bytes=\(body.count)"
        )

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -21, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        logHTTPResponse(context: "ASR multipart test", response: http, data: data)

        let payload = String(data: data.prefix(200), encoding: .utf8) ?? ""
        if (200...299).contains(http.statusCode) {
            return AppLocalization.format("Connection test succeeded (HTTP %d).", http.statusCode)
        }
        if http.statusCode == 400 || http.statusCode == 422 {
            return AppLocalization.format("Endpoint reachable (HTTP %d). Authentication and routing look valid.", http.statusCode)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NSError(
                domain: "Voxt.Settings",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Server reachable, but authentication failed (HTTP %d). %@", http.statusCode, payload)]
            )
        }
        throw NSError(
            domain: "Voxt.Settings",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Connection failed (HTTP %d). %@", http.statusCode, payload)]
        )
    }

    private func makeASRTestMultipartBody(boundary: String, model: String) -> Data {
        var body = Data()

        func append(_ text: String) {
            body.append(text.data(using: .utf8) ?? Data())
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"test.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(silentTestWavData())
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }

    private func silentTestWavData() -> Data {
        var data = Data()
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let durationMs: UInt32 = 100
        let samples = sampleRate * durationMs / 1000
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataSize = samples * UInt32(channels) * bytesPerSample
        let byteRate = sampleRate * UInt32(channels) * bytesPerSample
        let blockAlign = channels * (bitsPerSample / 8)
        let riffSize = 36 + dataSize

        data.append("RIFF".data(using: .ascii) ?? Data())
        data.append(le32(riffSize))
        data.append("WAVE".data(using: .ascii) ?? Data())
        data.append("fmt ".data(using: .ascii) ?? Data())
        data.append(le32(16))
        data.append(le16(1))
        data.append(le16(channels))
        data.append(le32(sampleRate))
        data.append(le32(byteRate))
        data.append(le16(blockAlign))
        data.append(le16(bitsPerSample))
        data.append("data".data(using: .ascii) ?? Data())
        data.append(le32(dataSize))
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func le16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func resolvedASRTranscriptionEndpoint(endpoint: String, defaultValue: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultValue }
        guard let url = URL(string: trimmed) else { return trimmed }
        let normalizedPath = url.path.lowercased()
        if normalizedPath.hasSuffix("/audio/transcriptions") {
            return trimmed
        }
        if normalizedPath.hasSuffix("/v1") {
            return trimmed + "/audio/transcriptions"
        }
        if normalizedPath.isEmpty || normalizedPath == "/" {
            return trimmed.hasSuffix("/") ? trimmed + "v1/audio/transcriptions" : trimmed + "/v1/audio/transcriptions"
        }
        return trimmed
    }

    private func resolvedGLMASRTranscriptionEndpoint(endpoint: String, defaultValue: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultValue }
        guard let url = URL(string: trimmed) else { return trimmed }
        let normalizedPath = url.path.lowercased()
        if normalizedPath.hasSuffix("/audio/transcriptions") {
            return trimmed
        }
        if normalizedPath.hasSuffix("/models") {
            return replacingPathSuffix(in: trimmed, oldSuffix: "/models", newSuffix: "/audio/transcriptions")
        }
        if normalizedPath.hasSuffix("/v4") {
            return appendingPath(trimmed, suffix: "/audio/transcriptions")
        }
        return trimmed
    }

    private func testLLMProvider(_ provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration) async throws -> String {
        let model = configuration.model.isEmpty ? provider.suggestedModel : configuration.model
        let endpoint = resolvedLLMTestEndpoint(provider: provider, endpoint: configuration.endpoint, model: model)
        var headers: [String: String] = [:]
        switch provider {
        case .anthropic:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -30, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Anthropic API Key is required for testing.")])
            }
            headers["x-api-key"] = configuration.apiKey
            headers["anthropic-version"] = "2023-06-01"
            return try await testAnthropicReachability(endpoint: endpoint, headers: headers, model: model)
        case .google:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -31, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Google API Key is required for testing.")])
            }
            return try await testGoogleReachability(endpoint: endpoint, apiKey: configuration.apiKey)
        case .minimax:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -32, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("MiniMax API Key is required for testing.")])
            }
            headers["Authorization"] = "Bearer \(configuration.apiKey)"
            return try await testMiniMaxReachability(endpoint: endpoint, headers: headers, model: model)
        case .openAI, .ollama, .deepseek, .openrouter, .grok, .zai, .volcengine, .kimi, .lmStudio:
            if !configuration.apiKey.isEmpty {
                headers["Authorization"] = "Bearer \(configuration.apiKey)"
            }
            return try await testOpenAICompatibleReachability(endpoint: endpoint, headers: headers, model: model)
        }
    }

    private func testOpenAICompatibleReachability(
        endpoint: String,
        headers: [String: String],
        model: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "ping"]
            ],
            "stream": false
        ]
        return try await testJSONPOSTReachability(endpoint: endpoint, headers: headers, body: body)
    }

    private func testAnthropicReachability(
        endpoint: String,
        headers: [String: String],
        model: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "ping"]
            ],
            "stream": false
        ]
        return try await testJSONPOSTReachability(endpoint: endpoint, headers: headers, body: body)
    }

    private func testGoogleReachability(
        endpoint: String,
        apiKey: String
    ) async throws -> String {
        guard var components = URLComponents(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -33, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid Google endpoint URL.")])
        }
        let hasKeyQuery = components.queryItems?.contains(where: { $0.name == "key" }) ?? false
        if !hasKeyQuery {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "key", value: apiKey))
            components.queryItems = items
        }
        guard let url = components.url else {
            throw NSError(domain: "Voxt.Settings", code: -34, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid Google endpoint URL.")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": "ping"]]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await sendLLMTestRequest(request, context: "LLM Google test")
    }

    private func testMiniMaxReachability(
        endpoint: String,
        headers: [String: String],
        model: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "ping"]
            ]
        ]
        return try await testJSONPOSTReachability(endpoint: endpoint, headers: headers, body: body)
    }

    private func testJSONPOSTReachability(
        endpoint: String,
        headers: [String: String],
        body: [String: Any]
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -35, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid endpoint URL.")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await sendLLMTestRequest(request, context: "LLM JSON POST test")
    }

    private func sendLLMTestRequest(_ request: URLRequest, context: String) async throws -> String {
        let bodyPreview = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "<empty>"
        logHTTPRequest(context: context, request: request, bodyPreview: bodyPreview)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -36, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        logHTTPResponse(context: context, response: http, data: data)

        let payload = String(data: data.prefix(220), encoding: .utf8) ?? ""
        if (200...299).contains(http.statusCode) {
            return AppLocalization.format("Connection test succeeded (HTTP %d).", http.statusCode)
        }
        if http.statusCode == 400 || http.statusCode == 422 {
            return AppLocalization.format("Endpoint reachable (HTTP %d). Authentication and routing look valid.", http.statusCode)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NSError(
                domain: "Voxt.Settings",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Server reachable, but authentication failed (HTTP %d). %@", http.statusCode, payload)]
            )
        }
        throw NSError(
            domain: "Voxt.Settings",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Connection failed (HTTP %d). %@", http.statusCode, payload)]
        )
    }

    private func testHTTPReachability(
        endpoint: String,
        headers: [String: String]
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -10, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid endpoint URL.")])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        logHTTPRequest(context: "HTTP reachability test", request: request, bodyPreview: "<empty>")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -11, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        logHTTPResponse(context: "HTTP reachability test", response: http, data: data)
        if (200...299).contains(http.statusCode) {
            return AppLocalization.format("Connection test succeeded (HTTP %d).", http.statusCode)
        }
        let payload = String(data: data.prefix(180), encoding: .utf8) ?? ""
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NSError(
                domain: "Voxt.Settings",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Server reachable, but authentication failed (HTTP %d). %@", http.statusCode, payload)]
            )
        }
        throw NSError(
            domain: "Voxt.Settings",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Connection failed (HTTP %d). %@", http.statusCode, payload)]
        )
    }

    private func testWebSocketReachability(
        endpoint: String,
        headers: [String: String]
    ) async throws {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -12, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid WebSocket endpoint URL.")])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        logHTTPRequest(context: "WebSocket reachability test", request: request, bodyPreview: "<websocket ping>")
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    VoxtLog.warning("WebSocket reachability test failed. error=\(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    VoxtLog.info("WebSocket reachability test succeeded.")
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func resolvedDoubaoASREndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel" : trimmed
    }

    private func testDoubaoStreamingReachability(
        endpoint: String,
        appID: String,
        accessToken: String,
        model: String
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -12, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid WebSocket endpoint URL.")])
        }

        let resourceID = normalizedDoubaoResourceID(model)
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        logHTTPRequest(context: "Doubao streaming test", request: request, bodyPreview: "full-request + 0.1s pcm + final packet")

        do {
            let ws = URLSession.shared.webSocketTask(with: request)
            ws.resume()
            defer {
                ws.cancel(with: .goingAway, reason: nil)
            }

            let reqID = UUID().uuidString.lowercased()
            let payloadObject: [String: Any] = [
                "user": [
                    "uid": "voxt-test"
                ],
                "audio": [
                    "format": "pcm",
                    "rate": 16000,
                    "bits": 16,
                    "channel": 1,
                    "language": "zh-CN"
                ],
                "request": [
                    "reqid": reqID,
                    "model_name": "bigmodel",
                    "sequence": 1,
                    "show_utterances": true,
                    "result_type": "single"
                ]
            ]
            let initPayload = try JSONSerialization.data(withJSONObject: payloadObject)
            try await ws.send(.data(buildDoubaoTestPacket(
                messageType: 0x1,
                messageFlags: 0x1,
                serialization: 0x1,
                compression: 0x0,
                sequence: 1,
                payload: initPayload
            )))

            // 0.1s 16k/16bit mono silent PCM for realistic stream validation.
            try await ws.send(.data(buildDoubaoTestPacket(
                messageType: 0x2,
                messageFlags: 0x1,
                serialization: 0x0,
                compression: 0x0,
                sequence: 2,
                payload: Data(count: 3200)
            )))

            try await ws.send(.data(buildDoubaoTestPacket(
                messageType: 0x2,
                messageFlags: 0x2,
                serialization: 0x0,
                compression: 0x0,
                sequence: -2,
                payload: Data()
            )))

            for index in 1...4 {
                let message = try await receiveWebSocketMessage(task: ws, timeoutSeconds: 3)
                guard case .data(let packetData) = message else { continue }
                let parsed = try parseDoubaoTestServerPacket(packetData)
                VoxtLog.info(
                    "Doubao test server packet. index=\(index), type=\(parsed.messageType), bytes=\(packetData.count), hasText=\(parsed.hasText), isFinal=\(parsed.isFinal)"
                )

                if let errorText = parsed.errorText, !errorText.isEmpty {
                    throw NSError(domain: "Voxt.Settings", code: 403, userInfo: [NSLocalizedDescriptionKey: errorText])
                }
                if parsed.hasText || parsed.isFinal || parsed.messageType == 0xB || parsed.messageType == 0x9 {
                    return AppLocalization.localizedString("Connection test succeeded (Doubao WebSocket reachable).")
                }
            }

            throw NSError(
                domain: "Voxt.Settings",
                code: -120,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Connection failed (HTTP %d). %@").replacingOccurrences(of: "%d", with: "0").replacingOccurrences(of: "%@", with: "No valid ASR response packet.")]
            )
        } catch {
            if isWebSocketHandshakeFailure(error),
               let detailedError = await fetchDoubaoHandshakeFailureDetail(
                    endpoint: endpoint,
                    appID: appID,
                    accessToken: accessToken,
                    resourceID: resourceID
               ) {
                throw detailedError
            }
            throw error
        }
    }

    private func receiveWebSocketMessage(
        task: URLSessionWebSocketTask,
        timeoutSeconds: TimeInterval
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await task.receive()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw NSError(
                    domain: "Voxt.Settings",
                    code: -121,
                    userInfo: [NSLocalizedDescriptionKey: "Doubao test timed out waiting for server packet."]
                )
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func isWebSocketHandshakeFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorBadServerResponse
    }

    private func fetchDoubaoHandshakeFailureDetail(
        endpoint: String,
        appID: String,
        accessToken: String,
        resourceID: String
    ) async -> NSError? {
        guard var components = URLComponents(string: endpoint) else {
            return nil
        }
        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }
        guard let probeURL = components.url else {
            return nil
        }

        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return nil
            }
            logHTTPResponse(context: "Doubao handshake probe", response: http, data: data)
            let payload = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if payload.isEmpty {
                return NSError(
                    domain: "Voxt.Settings",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Doubao handshake failed (HTTP %d).", http.statusCode)]
                )
            }
            return NSError(
                domain: "Voxt.Settings",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Doubao handshake failed (HTTP %d): %@", http.statusCode, payload)]
            )
        } catch {
            return nil
        }
    }

    private func buildDoubaoTestPacket(
        messageType: UInt8,
        messageFlags: UInt8,
        serialization: UInt8,
        compression: UInt8,
        sequence: Int32,
        payload: Data
    ) -> Data {
        var data = Data()
        data.append((0x1 << 4) | 0x1)
        data.append((messageType << 4) | messageFlags)
        data.append((serialization << 4) | compression)
        data.append(0x00)
        if messageFlags == 0x1 || messageFlags == 0x2 || messageFlags == 0x3 {
            withUnsafeBytes(of: sequence.bigEndian) { data.append(contentsOf: $0) }
        }
        var length = UInt32(payload.count).bigEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(payload)
        return data
    }

    private func parseDoubaoTestServerPacket(_ data: Data) throws -> (messageType: UInt8, hasText: Bool, isFinal: Bool, errorText: String?) {
        guard data.count >= 8 else {
            return (0, false, false, "Doubao server packet too short.")
        }

        let byte0 = data[0]
        let byte1 = data[1]
        let headerSizeWords = Int(byte0 & 0x0F)
        let headerSizeBytes = max(4, headerSizeWords * 4)
        let messageType = (byte1 >> 4) & 0x0F
        let messageFlags = byte1 & 0x0F

        var cursor = headerSizeBytes

        let hasSequence = (messageFlags & 0x1) != 0 || (messageFlags & 0x2) != 0
        var sequence: Int32?
        if hasSequence {
            guard data.count >= cursor + 4 else {
                return (messageType, false, false, "Invalid Doubao sequence header.")
            }
            let seqData = data.subdata(in: cursor..<(cursor + 4))
            let raw = seqData.reduce(UInt32(0)) { partial, byte in
                (partial << 8) | UInt32(byte)
            }
            sequence = Int32(bitPattern: raw)
            cursor += 4
        }

        guard data.count >= cursor + 4 else {
            return (messageType, false, false, "Invalid Doubao payload header.")
        }
        let payloadSizeData = data.subdata(in: cursor..<(cursor + 4))
        let payloadSize = payloadSizeData.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        cursor += 4
        guard data.count >= cursor + Int(payloadSize) else {
            return (messageType, false, false, "Invalid Doubao payload size.")
        }
        let payload = data.subdata(in: cursor..<(cursor + Int(payloadSize)))
        if messageType == 0xF {
            let errorText = String(data: payload, encoding: .utf8) ?? "Doubao server returned an error packet."
            return (messageType, false, false, errorText)
        }

        guard let object = try? JSONSerialization.jsonObject(with: payload) else {
            return (messageType, false, (sequence ?? 1) < 0, nil)
        }

        let text = extractTextFromJSONObject(object)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let jsonSequence = extractSequence(in: object)
        let isFinal = (jsonSequence ?? sequence ?? 1) < 0
        return (messageType, !text.isEmpty, isFinal, nil)
    }

    private func normalizedDoubaoResourceID(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "volc.bigasr.sauc.duration" : trimmed
    }

    private func extractTextFromJSONObject(_ object: Any) -> String? {
        if let text = object as? String {
            return text
        }
        if let dict = object as? [String: Any] {
            let preferredKeys = ["text", "result_text", "utterance", "transcript", "result", "content"]
            for key in preferredKeys {
                if let value = dict[key], let text = extractTextFromJSONObject(value), !text.isEmpty {
                    return text
                }
            }
            for value in dict.values {
                if let text = extractTextFromJSONObject(value), !text.isEmpty {
                    return text
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let text = extractTextFromJSONObject(item), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func extractSequence(in object: Any) -> Int32? {
        if let value = object as? Int { return Int32(value) }
        if let value = object as? Int32 { return value }
        if let value = object as? Int64 { return Int32(value) }
        if let dict = object as? [String: Any] {
            if let seq = dict["sequence"] {
                return extractSequence(in: seq)
            }
            for nested in dict.values {
                if let seq = extractSequence(in: nested) {
                    return seq
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let seq = extractSequence(in: item) {
                    return seq
                }
            }
        }
        return nil
    }

    private func providerDefaultTestEndpoint(_ provider: RemoteLLMProvider) -> String {
        switch provider {
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .google:
            return "https://generativelanguage.googleapis.com/v1beta/models"
        case .openAI:
            return "https://api.openai.com/v1/models"
        case .ollama:
            return "http://127.0.0.1:11434/api/chat"
        case .deepseek:
            return "https://api.deepseek.com/v1/models"
        case .openrouter:
            return "https://openrouter.ai/api/v1/models"
        case .grok:
            return "https://api.x.ai/v1/models"
        case .zai:
            return "https://open.bigmodel.cn/api/paas/v4/models"
        case .volcengine:
            return "https://ark.cn-beijing.volces.com/api/v3/models"
        case .kimi:
            return "https://api.moonshot.cn/v1/models"
        case .lmStudio:
            return "http://127.0.0.1:1234/v1/models"
        case .minimax:
            return "https://api.minimax.chat/v1/text/chatcompletion_v2"
        }
    }

    private func resolvedLLMTestEndpoint(provider: RemoteLLMProvider, endpoint: String, model: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? providerDefaultTestEndpoint(provider) : trimmed
        guard let url = URL(string: base) else { return base }
        let path = url.path.lowercased()

        switch provider {
        case .anthropic:
            if path.hasSuffix("/v1/messages") { return base }
            if path.hasSuffix("/v1/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/v1/models", newSuffix: "/v1/messages")
            }
            if path.hasSuffix("/v1") { return appendingPath(base, suffix: "/messages") }
            if path.isEmpty || path == "/" { return appendingPath(base, suffix: "/v1/messages") }
            return base
        case .google:
            if path.contains(":generatecontent") { return base }
            if path.hasSuffix("/v1beta/models") || path.hasSuffix("/v1/models") || path.hasSuffix("/models") {
                return appendingPath(base, suffix: "/\(model):generateContent")
            }
            if path.hasSuffix("/v1beta") || path.hasSuffix("/v1") {
                return appendingPath(base, suffix: "/models/\(model):generateContent")
            }
            if path.isEmpty || path == "/" {
                return appendingPath(base, suffix: "/v1beta/models/\(model):generateContent")
            }
            return base
        case .minimax:
            if path.hasSuffix("/v1/text/chatcompletion_v2") || path.hasSuffix("/text/chatcompletion_v2") {
                return base
            }
            if path.hasSuffix("/v1/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/v1/models", newSuffix: "/v1/text/chatcompletion_v2")
            }
            if path.hasSuffix("/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/models", newSuffix: "/text/chatcompletion_v2")
            }
            if path.hasSuffix("/v1") { return appendingPath(base, suffix: "/text/chatcompletion_v2") }
            if path.isEmpty || path == "/" { return appendingPath(base, suffix: "/v1/text/chatcompletion_v2") }
            return base
        case .ollama:
            if path.hasSuffix("/api/chat") || path.hasSuffix("/v1/chat/completions") || path.hasSuffix("/chat/completions") {
                return base
            }
            if path.hasSuffix("/api/tags") {
                return replacingPathSuffix(in: base, oldSuffix: "/api/tags", newSuffix: "/api/chat")
            }
            if path.hasSuffix("/v1/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/v1/models", newSuffix: "/v1/chat/completions")
            }
            if path.hasSuffix("/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/models", newSuffix: "/chat/completions")
            }
            if path.hasSuffix("/v1") { return appendingPath(base, suffix: "/chat/completions") }
            if path.isEmpty || path == "/" { return appendingPath(base, suffix: "/api/chat") }
            return base
        case .openAI, .deepseek, .openrouter, .grok, .zai, .volcengine, .kimi, .lmStudio:
            if path.hasSuffix("/v1/chat/completions") || path.hasSuffix("/chat/completions") {
                return base
            }
            if path.hasSuffix("/v1/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/v1/models", newSuffix: "/v1/chat/completions")
            }
            if path.hasSuffix("/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/models", newSuffix: "/chat/completions")
            }
            if path.hasSuffix("/v1") { return appendingPath(base, suffix: "/chat/completions") }
            if path.isEmpty || path == "/" { return appendingPath(base, suffix: "/v1/chat/completions") }
            return base
        }
    }

    private func replacingPathSuffix(in value: String, oldSuffix: String, newSuffix: String) -> String {
        guard value.lowercased().hasSuffix(oldSuffix) else { return value }
        return String(value.dropLast(oldSuffix.count)) + newSuffix
    }

    private func appendingPath(_ value: String, suffix: String) -> String {
        if value.hasSuffix("/") {
            return value + suffix.dropFirst()
        }
        return value + suffix
    }

    private var testTargetLogName: String {
        switch testTarget {
        case .asr:
            return "asr"
        case .llm:
            return "llm"
        }
    }

    private func sanitizedEndpointForLog(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<default>" : trimmed
    }

    private func logHTTPRequest(context: String, request: URLRequest, bodyPreview: String) {
        let method = request.httpMethod ?? "GET"
        let url = redactedURLString(request.url)
        let headers = redactedHeaders(request.allHTTPHeaderFields ?? [:])
        VoxtLog.info(
            "Network test request. context=\(context), method=\(method), url=\(url), headers=\(headers), body=\(truncateLogText(bodyPreview, limit: 700))"
        )
    }

    private func logHTTPResponse(context: String, response: HTTPURLResponse, data: Data) {
        let url = redactedURLString(response.url)
        let headers = redactedHeaders(response.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
            partialResult[String(describing: pair.key)] = String(describing: pair.value)
        })
        let payload = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        VoxtLog.info(
            "Network test response. context=\(context), status=\(response.statusCode), url=\(url), headers=\(headers), body=\(truncateLogText(payload, limit: 700))"
        )
    }

    private func redactedHeaders(_ headers: [String: String]) -> String {
        let redacted = headers.reduce(into: [String: String]()) { partialResult, pair in
            let key = pair.key
            let lower = key.lowercased()
            if lower == "authorization" || lower == "x-api-key" || lower.contains("token") {
                partialResult[key] = "<redacted>"
            } else {
                partialResult[key] = pair.value
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "\(redacted)"
    }

    private func redactedURLString(_ url: URL?) -> String {
        guard let url else { return "<nil>" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.map { item in
            let lower = item.name.lowercased()
            if lower == "key" || lower == "api_key" || lower.contains("token") {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return components.string ?? url.absoluteString
    }

    private func truncateLogText(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "...(truncated)"
    }

    private var isDoubaoASRTest: Bool {
        if case .asr(let provider) = testTarget {
            return provider == .doubaoASR
        }
        return false
    }

    private let customModelOptionID = "__voxt_custom_model__"

    private var providerModelOptions: [RemoteModelOption] {
        if case .asr(let provider) = testTarget {
            return provider.modelOptions
        }
        if case .llm(let provider) = testTarget {
            return provider.modelOptions
        }
        return [RemoteModelOption(id: configuration.model, title: configuration.model)]
    }

    private var pickerModelOptionIDs: [String] {
        if let llmProvider = llmProviderForPicker {
            return (llmProvider.latestModelOptions + llmProvider.basicModelOptions + llmProvider.advancedModelOptions).map(\.id) + [customModelOptionID]
        }
        return providerModelOptions.map(\.id)
    }

    private var resolvedSelectionForPicker: String {
        let trimmed = selectedProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if pickerModelOptionIDs.contains(trimmed) {
            return trimmed
        }
        let configured = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if pickerModelOptionIDs.contains(configured) {
            return configured
        }
        if llmProviderForPicker != nil {
            return customModelOptionID
        }
        return pickerModelOptionIDs.first ?? trimmed
    }

    private var providerModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedSelectionForPicker },
            set: {
                selectedProviderModel = $0
                if llmProviderForPicker != nil,
                   $0 != customModelOptionID,
                   customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customModelID = $0
                }
            }
        )
    }

    private var llmProviderForPicker: RemoteLLMProvider? {
        if case .llm(let provider) = testTarget {
            return provider
        }
        return nil
    }

    private func configureModelSelection() {
        if llmProviderForPicker != nil {
            let configured = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if pickerModelOptionIDs.contains(configured) {
                selectedProviderModel = configured
            } else {
                selectedProviderModel = customModelOptionID
            }
            return
        }

        if pickerModelOptionIDs.contains(configuration.model) {
            selectedProviderModel = configuration.model
        } else {
            selectedProviderModel = pickerModelOptionIDs.first ?? configuration.model
        }
    }

    private func resolvedModelValue() -> String {
        if let llmProvider = llmProviderForPicker {
            if resolvedSelectionForPicker == customModelOptionID {
                let trimmedCustom = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedCustom.isEmpty ? llmProvider.suggestedModel : trimmedCustom
            }
        }
        return resolvedSelectionForPicker
    }
}

private enum RemoteProviderTestTarget {
    case asr(RemoteASRProvider)
    case llm(RemoteLLMProvider)
}

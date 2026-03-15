import SwiftUI
import AppKit
import Combine

struct ModelSettingsView: View {
    @AppStorage(AppPreferenceKey.transcriptionEngine) private var engineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.enhancementMode) private var enhancementModeRaw = EnhancementMode.off.rawValue
    @AppStorage(AppPreferenceKey.enhancementSystemPrompt) private var systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
    @AppStorage(AppPreferenceKey.translationSystemPrompt) private var translationPrompt = AppPreferenceKey.defaultTranslationPrompt
    @AppStorage(AppPreferenceKey.rewriteSystemPrompt) private var rewritePrompt = AppPreferenceKey.defaultRewritePrompt
    @AppStorage(AppPreferenceKey.mlxModelRepo) private var modelRepo = MLXModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.customLLMModelRepo) private var customLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationCustomLLMModelRepo) private var translationCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.rewriteCustomLLMModelRepo) private var rewriteCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationModelProvider) private var translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.rewriteModelProvider) private var rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.remoteASRSelectedProvider) private var remoteASRSelectedProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) private var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.remoteLLMSelectedProvider) private var remoteLLMSelectedProviderRaw = RemoteLLMProvider.openAI.rawValue
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) private var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.translationRemoteLLMProvider) private var translationRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.rewriteRemoteLLMProvider) private var rewriteRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.useHfMirror) private var useHfMirror = false
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager
    let missingConfigurationIssues: [ConfigurationTransferManager.MissingConfigurationIssue]
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

    private var selectedRewriteModelProvider: RewriteModelProvider {
        RewriteModelProvider(rawValue: rewriteModelProviderRaw) ?? .customLLM
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
                    PromptTemplateVariablesView(
                        variables: [
                            PromptTemplateVariableDescriptor(
                                token: "{{TARGET_LANGUAGE}}",
                                tipKey: "Template tip {{TARGET_LANGUAGE}}"
                            ),
                            PromptTemplateVariableDescriptor(
                                token: "{{SOURCE_TEXT}}",
                                tipKey: "Template tip {{SOURCE_TEXT}}"
                            )
                        ]
                    )

                    HStack {
                        Button("Reset to Default") {
                            translationPrompt = AppPreferenceKey.defaultTranslationPrompt
                        }
                        .controlSize(.small)
                        .disabled(translationPrompt == AppPreferenceKey.defaultTranslationPrompt)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Content Rewrite")
                        .font(.headline)

                    Picker("Content Rewrite Provider", selection: $rewriteModelProviderRaw) {
                        ForEach(RewriteModelProvider.allCases) { provider in
                            Text(provider.titleKey).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)

                    HStack(alignment: .center, spacing: 12) {
                        Text(rewriteModelLabelText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if rewriteModelOptions.isEmpty {
                            Text("Not available")
                                .foregroundStyle(.tertiary)
                        } else {
                            Picker("Content Rewrite Model", selection: rewriteModelSelectionBinding) {
                                ForEach(rewriteModelOptions) { option in
                                    Text(option.title).tag(option.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .trailing)
                        }
                    }

                    if rewriteModelOptions.isEmpty {
                        Text(rewriteModelEmptyStateText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text("Content Rewrite Prompt")
                        .font(.subheadline.weight(.medium))
                    PromptEditorView(text: $rewritePrompt)
                    PromptTemplateVariablesView(
                        variables: [
                            PromptTemplateVariableDescriptor(
                                token: "{{DICTATED_PROMPT}}",
                                tipKey: "Template tip {{DICTATED_PROMPT}}"
                            ),
                            PromptTemplateVariableDescriptor(
                                token: "{{SOURCE_TEXT}}",
                                tipKey: "Template tip {{SOURCE_TEXT}}"
                            )
                        ]
                    )

                    HStack {
                        Button("Reset to Default") {
                            rewritePrompt = AppPreferenceKey.defaultRewritePrompt
                        }
                        .controlSize(.small)
                        .disabled(rewritePrompt == AppPreferenceKey.defaultRewritePrompt)
                        Spacer()
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
            if rewritePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rewritePrompt = AppPreferenceKey.defaultRewritePrompt
            }
            if !TranslationModelProvider.allCases.contains(where: { $0.rawValue == translationModelProviderRaw }) {
                translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
            }
            if !RewriteModelProvider.allCases.contains(where: { $0.rawValue == rewriteModelProviderRaw }) {
                rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
            }
            if rewriteCustomLLMRepo.isEmpty {
                rewriteCustomLLMRepo = customLLMRepo
            }
            if !CustomLLMModelManager.isSupportedModelRepo(rewriteCustomLLMRepo) {
                rewriteCustomLLMRepo = customLLMRepo
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
            ensureRewriteModelSelectionConsistency()
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
            ensureRewriteModelSelectionConsistency()
        }
        .onChange(of: translationModelProviderRaw) { _, _ in
            ensureTranslationModelSelectionConsistency()
        }
        .onChange(of: rewriteModelProviderRaw) { _, _ in
            ensureRewriteModelSelectionConsistency()
        }
        .onChange(of: remoteLLMProviderConfigurationsRaw) { _, _ in
            ensureTranslationModelSelectionConsistency()
            ensureRewriteModelSelectionConsistency()
        }
        .onChange(of: useHfMirror) { _, _ in
            updateMirrorSetting()
        }
        .onReceive(modelStateRefreshTimer) { _ in
            refreshModelInstallStateIfNeeded()
            ensureTranslationModelSelectionConsistency()
            ensureRewriteModelSelectionConsistency()
        }
        .sheet(item: $editingASRProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: asrCredentialHint(for: provider),
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
            PromptTemplateVariablesView(
                variables: [
                    PromptTemplateVariableDescriptor(
                        token: "{{RAW_TRANSCRIPTION}}",
                        tipKey: "Template tip {{RAW_TRANSCRIPTION}}"
                    )
                ]
            )

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
        PromptTemplateVariablesView(
            variables: [
                PromptTemplateVariableDescriptor(
                    token: "{{RAW_TRANSCRIPTION}}",
                    tipKey: "Template tip {{RAW_TRANSCRIPTION}}"
                )
            ]
        )

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
        PromptTemplateVariablesView(
            variables: [
                PromptTemplateVariableDescriptor(
                    token: "{{RAW_TRANSCRIPTION}}",
                    tipKey: "Template tip {{RAW_TRANSCRIPTION}}"
                )
            ]
        )

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
                badgeText: hasIssue(for: .remoteASRProvider(provider)) ? String(localized: "Needs Setup") : nil,
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
                badgeText: remoteLLMBadgeText(for: provider),
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

    private func asrCredentialHint(for provider: RemoteASRProvider) -> String? {
        switch provider {
        case .doubaoASR:
            return "Doubao uses App ID + Access Token for streaming API."
        case .aliyunBailianASR:
            return "Aliyun ASR in Voxt uses realtime WebSocket only: Qwen models use /api-ws/v1/realtime, Fun/Paraformer models use /api-ws/v1/inference."
        case .openAIWhisper, .glmASR:
            return nil
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

    private var rewriteModelOptions: [TranslationModelOption] {
        switch selectedRewriteModelProvider {
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

    private var rewriteModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedRewriteSelection },
            set: { newValue in
                switch selectedRewriteModelProvider {
                case .remoteLLM:
                    rewriteRemoteLLMProviderRaw = newValue
                case .customLLM:
                    rewriteCustomLLMRepo = newValue
                }
            }
        )
    }

    private var resolvedRewriteSelection: String {
        let options = rewriteModelOptions
        guard !options.isEmpty else {
            return currentRewriteSelectionRaw
        }

        if options.contains(where: { $0.id == currentRewriteSelectionRaw }) {
            return currentRewriteSelectionRaw
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

    private var currentRewriteSelectionRaw: String {
        switch selectedRewriteModelProvider {
        case .remoteLLM:
            return rewriteRemoteLLMProviderRaw
        case .customLLM:
            return rewriteCustomLLMRepo
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

    private var rewriteModelLabelText: String {
        selectedRewriteModelProvider == .remoteLLM ? "Remote LLM Model" : "Custom LLM Model"
    }

    private var rewriteModelEmptyStateText: String {
        selectedRewriteModelProvider == .remoteLLM
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
                badgeText: hasIssue(for: .mlxModel(model.id)) ? String(localized: "Needs Setup") : nil,
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
                badgeText: customLLMBadgeText(for: model.id),
                isTitleUnderlined: isDownloaded,
                onTapTitle: isDownloaded ? { openCustomLLMModelDirectory(model.id) } : nil,
                actions: actions
            )
        }
    }

    private func hasIssue(for scope: ConfigurationTransferManager.MissingConfigurationIssue.Scope) -> Bool {
        missingConfigurationIssues.contains(where: { $0.scope == scope })
    }

    private func remoteLLMBadgeText(for provider: RemoteLLMProvider) -> String? {
        let scopes: [ConfigurationTransferManager.MissingConfigurationIssue.Scope] = [
            .remoteLLMProvider(provider),
            .translationRemoteLLM(provider),
            .rewriteRemoteLLM(provider)
        ]
        return missingConfigurationIssues.contains(where: { scopes.contains($0.scope) }) ? String(localized: "Needs Setup") : nil
    }

    private func customLLMBadgeText(for repo: String) -> String? {
        let scopes: [ConfigurationTransferManager.MissingConfigurationIssue.Scope] = [
            .customLLMModel(repo),
            .translationCustomLLM(repo),
            .rewriteCustomLLM(repo)
        ]
        return missingConfigurationIssues.contains(where: { scopes.contains($0.scope) }) ? String(localized: "Needs Setup") : nil
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

    private func ensureRewriteModelSelectionConsistency() {
        switch selectedRewriteModelProvider {
        case .remoteLLM:
            let options = configuredRemoteLLMOptions
            guard let first = options.first else {
                rewriteRemoteLLMProviderRaw = ""
                return
            }
            if !options.contains(where: { $0.id == rewriteRemoteLLMProviderRaw }) {
                rewriteRemoteLLMProviderRaw = first.id
            }
        case .customLLM:
            let options = installedCustomLLMOptions
            if let first = options.first {
                if !options.contains(where: { $0.id == rewriteCustomLLMRepo }) {
                    rewriteCustomLLMRepo = first.id
                }
            } else {
                rewriteCustomLLMRepo = customLLMRepo
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
        let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
        if let model = MLXModelManager.availableModels.first(where: { $0.id == canonicalRepo }) {
            return LocalizedStringKey(model.description)
        }
        return LocalizedStringKey("")
    }
}

private struct TranslationModelOption: Identifiable, Hashable {
    let id: String
    let title: String
}

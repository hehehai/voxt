import SwiftUI

extension ModelSettingsView {
    var translationSettingsCard: some View {
        ModelTaskSettingsCard(
            title: "Translation",
            providerPickerTitle: "Translation Provider",
            providerOptions: translationProviderOptions,
            selectedProviderID: $translationModelProviderRaw,
            modelLabelText: translationModelLabelText,
            modelPickerTitle: "Translation Model",
            modelOptions: translationModelOptions,
            selectedModelBinding: translationModelSelectionBinding,
            emptyStateText: translationModelEmptyStateText,
            promptTitle: "Translation Prompt",
            promptText: $translationPrompt,
            defaultPromptText: AppPreferenceKey.defaultTranslationPrompt,
            variables: ModelSettingsPromptVariables.translation
        )
    }

    var rewriteSettingsCard: some View {
        ModelTaskSettingsCard(
            title: "Content Rewrite",
            providerPickerTitle: "Content Rewrite Provider",
            providerOptions: rewriteProviderOptions,
            selectedProviderID: $rewriteModelProviderRaw,
            modelLabelText: rewriteModelLabelText,
            modelPickerTitle: "Content Rewrite Model",
            modelOptions: rewriteModelOptions,
            selectedModelBinding: rewriteModelSelectionBinding,
            emptyStateText: rewriteModelEmptyStateText,
            promptTitle: "Content Rewrite Prompt",
            promptText: $rewritePrompt,
            defaultPromptText: AppPreferenceKey.defaultRewritePrompt,
            variables: ModelSettingsPromptVariables.rewrite
        )
    }

    @ViewBuilder
    var mlxModelSection: some View {
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

        ModelTableView(title: "Models", rows: mlxRows)

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
    var appleIntelligenceSection: some View {
        Divider()

        if appleIntelligenceAvailable {
            ResettablePromptSection(
                title: "System Prompt",
                text: $systemPrompt,
                defaultText: AppPreferenceKey.defaultEnhancementPrompt,
                variables: ModelSettingsPromptVariables.enhancement
            )

            HStack {
                Text("Customise how Apple Intelligence enhances your transcriptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Apple Intelligence is not available on this Mac, so system prompt enhancement cannot be used.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    var customLLMSection: some View {
        Divider()

        ResettablePromptSection(
            title: "System Prompt",
            text: $systemPrompt,
            defaultText: AppPreferenceKey.defaultEnhancementPrompt,
            variables: ModelSettingsPromptVariables.enhancement
        )

        ModelTableView(title: "Custom LLM Models", rows: customLLMRows, maxHeight: 260)

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
    var remoteASRSection: some View {
        Divider()

        Text("Remote ASR Providers")
            .font(.subheadline.weight(.medium))

        ModelTableView(title: "Providers", rows: remoteASRRows, maxHeight: 220)
    }

    @ViewBuilder
    var remoteLLMSection: some View {
        Divider()

        ResettablePromptSection(
            title: "System Prompt",
            text: $systemPrompt,
            defaultText: AppPreferenceKey.defaultEnhancementPrompt,
            variables: ModelSettingsPromptVariables.enhancement
        )

        HStack {
            Text("Configure a remote provider and model, then click Use.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ModelTableView(title: "Remote LLM Providers", rows: remoteLLMRows, maxHeight: 280)
    }
}

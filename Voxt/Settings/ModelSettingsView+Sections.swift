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
            modelDisplayText: translationModelDisplayText,
            emptyStateText: translationModelEmptyStateText,
            statusMessage: translationProviderStatusMessage,
            statusIsWarning: translationProviderStatusIsWarning,
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
            modelDisplayText: nil,
            emptyStateText: rewriteModelEmptyStateText,
            statusMessage: nil,
            statusIsWarning: false,
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
                SettingsMenuPicker(
                    selection: $modelRepo,
                    options: MLXModelManager.availableModels.map { model in
                        SettingsMenuOption(value: model.id, title: model.title)
                    },
                    selectedTitle: mlxModelManager.displayTitle(for: modelRepo),
                    width: 260
                )

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

        ModelTableView(title: "Models", rows: mlxRows, viewportHeight: 320)

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
    var whisperModelSection: some View {
        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.subheadline.weight(.medium))

            HStack(alignment: .center, spacing: 12) {
                SettingsMenuPicker(
                    selection: whisperModelSelectionBinding,
                    options: WhisperKitModelManager.availableModels.map { model in
                        SettingsMenuOption(value: model.id, title: AppLocalization.localizedString(model.title))
                    },
                    selectedTitle: whisperModelManager.displayTitle(for: whisperModelID),
                    width: 260
                )

                Spacer()

                Button("Configure") {
                    isWhisperConfigPresented = true
                }
                .buttonStyle(SettingsPillButtonStyle())

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

            Text(whisperModelLocalizedDescription(for: whisperModelID))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(whisperConfigurationSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ModelTableView(title: "Whisper Models", rows: whisperRows, viewportHeight: 260)

        if let activeDownload = whisperModelManager.activeDownload {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    String(
                        format: NSLocalizedString("Downloading: %d%% • %@", comment: ""),
                        Int(activeDownload.progress * 100),
                        ModelDownloadProgressFormatter.progressText(
                            completed: activeDownload.completed,
                            total: activeDownload.total
                        )
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

                Text(
                    ModelDownloadProgressFormatter.fileProgressText(
                        currentFile: activeDownload.currentFile,
                        currentFileCompleted: activeDownload.currentFileCompleted,
                        currentFileTotal: activeDownload.currentFileTotal,
                        completedFiles: activeDownload.completedFiles,
                        totalFiles: activeDownload.totalFiles
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    var whisperConfigurationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Whisper Configuration")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Toggle("Enable VAD", isOn: $whisperVADEnabled)
                        .toggleStyle(.switch)
                    Toggle("Enable Timestamps", isOn: $whisperTimestampsEnabled)
                        .toggleStyle(.switch)
                    Toggle("Realtime", isOn: $whisperRealtimeEnabled)
                        .toggleStyle(.switch)
                }

                Toggle("Keep Resident", isOn: $whisperKeepResidentLoaded)
                    .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.1f", whisperTemperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $whisperTemperature, in: 0...1, step: 0.1)
                }
            }

            Text("These settings apply to Whisper transcription sessions. Standard ASR always uses transcribe; Whisper translate is only used by the translation hotkey when Whisper translation is selected. Realtime uses WhisperKit's streaming path; turning it off switches to quality-first partial updates.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("When enabled and Whisper is the selected engine, Voxt preloads Whisper after app launch and keeps it resident in memory for faster first use.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsDialogActionRow {
                Button("Done") {
                    isWhisperConfigPresented = false
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
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

        ModelTableView(title: "Custom LLM Models", rows: customLLMRows, viewportHeight: 260)

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

        ModelTableView(title: "Providers", rows: remoteASRRows, viewportHeight: 220)
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

        ModelTableView(title: "Remote LLM Providers", rows: remoteLLMRows, viewportHeight: 280)
    }
}

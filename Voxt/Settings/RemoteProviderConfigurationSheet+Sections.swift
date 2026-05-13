import SwiftUI

extension RemoteProviderConfigurationSheet {
    private var ollamaOptionsJSONPlaceholder: String {
        """
        {
          "num_ctx": 8192,
          "seed": 42,
          "repeat_penalty": 1.1,
          "stop": ["<|im_end|>"]
        }
        """
    }

    private var ollamaJSONSchemaPlaceholder: String {
        """
        {
          "type": "object",
          "properties": {
            "answer": { "type": "string" }
          },
          "required": ["answer"]
        }
        """
    }

    private var omlxJSONSchemaPlaceholder: String {
        """
        {
          "type": "object",
          "properties": {
            "answer": { "type": "string" }
          },
          "required": ["answer"]
        }
        """
    }

    private var omlxExtraBodyJSONPlaceholder: String {
        """
        {
          "top_k": 40,
          "min_p": 0.05
        }
        """
    }

    var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.localizedString("Model"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SettingsMenuPicker(
                selection: providerModelSelectionBinding,
                options: providerModelMenuOptions,
                selectedTitle: providerModelSelectedTitle,
                width: 240
            )

            if shouldShowCustomProviderModelField {
                Text(AppLocalization.localizedString("Custom Model ID (Optional)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(customProviderModelPlaceholder, text: $customModelID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }
        }
    }

    var endpointAndKeySection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Endpoint (Optional)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(endpointFieldPlaceholder, text: $endpoint)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
                if !endpointPresets.isEmpty {
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(endpointPresets, id: \.id) { preset in
                                Button(preset.title) {
                                    endpoint = preset.url
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(AppLocalization.localizedString("Apply Preset"))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))

                        if !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(AppLocalization.localizedString("Clear")) {
                                endpoint = ""
                            }
                            .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))
                        }

                        Spacer()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(apiKeyFieldTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField(apiKeyFieldPlaceholder, text: $apiKey)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            if let endpointPresetHintText {
                Text(endpointPresetHintText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var doubaoCredentialsSection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("App ID"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.localizedString("App ID"), text: $appID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Access Token"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField(AppLocalization.localizedString("Paste access token"), text: $accessToken)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }
        }
    }

    var doubaoDictionarySection: some View {
        RemoteProviderDoubaoDictionarySection(
            mode: $doubaoDictionaryMode,
            enableRequestHotwords: $doubaoEnableRequestHotwords,
            enableRequestCorrections: $doubaoEnableRequestCorrections
        )
    }

    var openAIChunkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(AppLocalization.localizedString("Chunk Pseudo Realtime Preview"), isOn: $openAIChunkPseudoRealtimeEnabled)
                .toggleStyle(.switch)
            Text(AppLocalization.localizedString("Enable segmented OpenAI ASR preview during recording. This roughly doubles usage."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(AppLocalization.localizedString("Search"), isOn: $searchEnabled)
                .toggleStyle(.switch)

            if let provider = llmProviderForPicker {
                Text(provider.searchToggleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var openAILLMConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.localizedString("OpenAI Options"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Think"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SettingsMenuPicker(
                    selection: $openAIReasoningEffort,
                    options: openAIReasoningEffortMenuOptions,
                    selectedTitle: openAIReasoningEffortSelectedTitle,
                    width: 240
                )
                Text(AppLocalization.localizedString("Maps to OpenAI reasoning.effort. Leave Default to use the model default; unsupported levels may be rejected by some models."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Verbosity"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SettingsMenuPicker(
                    selection: $openAITextVerbosity,
                    options: openAITextVerbosityMenuOptions,
                    selectedTitle: openAITextVerbositySelectedTitle,
                    width: 240
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Max Output Tokens (Optional)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.localizedString("e.g. 4096"), text: $openAIMaxOutputTokensText)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(width: 140, minHeight: 34)
                Text(AppLocalization.localizedString("Overrides Voxt's task token budget for OpenAI Responses, including visible output and reasoning tokens."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var ollamaConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.localizedString("Ollama Options"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Response Format"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SettingsMenuPicker(
                    selection: $ollamaResponseFormat,
                    options: ollamaResponseFormatMenuOptions,
                    selectedTitle: ollamaResponseFormatSelectedTitle,
                    width: 240
                )
            }

            if shouldShowOllamaJSONSchemaField {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.localizedString("JSON Schema"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    placeholderPromptEditor(
                        text: $ollamaJSONSchema,
                        placeholder: ollamaJSONSchemaPlaceholder,
                        height: 96
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Think"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SettingsMenuPicker(
                    selection: $ollamaThinkMode,
                    options: ollamaThinkModeMenuOptions,
                    selectedTitle: ollamaThinkModeSelectedTitle,
                    width: 240
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Keep Alive"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.localizedString("e.g. 5m"), text: $ollamaKeepAlive)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(AppLocalization.localizedString("Logprobs"), isOn: $ollamaLogprobsEnabled)
                    .toggleStyle(.switch)

                if ollamaLogprobsEnabled {
                    Text(AppLocalization.localizedString("Top Logprobs (Optional)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(AppLocalization.localizedString("e.g. 5"), text: $ollamaTopLogprobsText)
                        .textFieldStyle(.plain)
                        .settingsFieldSurface(width: 140, minHeight: 34)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Options JSON"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                placeholderPromptEditor(
                    text: $ollamaOptionsJSON,
                    placeholder: ollamaOptionsJSONPlaceholder,
                    height: 112
                )
                Text(AppLocalization.localizedString("Merged into Ollama native options after Voxt defaults, so matching keys here override temperature, top_p, and num_predict."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var omlxConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.localizedString("oMLX Options"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Response Format"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SettingsMenuPicker(
                    selection: $omlxResponseFormat,
                    options: omlxResponseFormatMenuOptions,
                    selectedTitle: omlxResponseFormatSelectedTitle,
                    width: 240
                )
            }

            if shouldShowOMLXJSONSchemaField {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.localizedString("JSON Schema"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    placeholderPromptEditor(
                        text: $omlxJSONSchema,
                        placeholder: omlxJSONSchemaPlaceholder,
                        height: 96
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(AppLocalization.localizedString("Include Usage In Stream Events"), isOn: $omlxIncludeUsageStreamOptions)
                    .toggleStyle(.switch)
                Text(AppLocalization.localizedString("Adds stream_options.include_usage for OpenAI-compatible streaming responses."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Extra Body JSON"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                placeholderPromptEditor(
                    text: $omlxExtraBodyJSON,
                    placeholder: omlxExtraBodyJSONPlaceholder,
                    height: 112
                )
                Text(AppLocalization.localizedString("Merged into the OpenAI-compatible request after Voxt defaults, so matching keys here override generated values."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var actionSection: some View {
        SettingsDialogActionRow {
            if isTestingConnection {
                ProgressView()
                    .controlSize(.small)
            }
            Button(AppLocalization.localizedString("Test")) {
                testConnection()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .disabled(isTestingConnection)

        } trailing: {
            Button(AppLocalization.localizedString("Cancel")) {
                dismiss()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .keyboardShortcut(.cancelAction)

            Button(AppLocalization.localizedString("Save")) {
                saveConfiguration()
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func placeholderPromptEditor(
        text: Binding<String>,
        placeholder: String,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .settingsPromptEditor(height: height, contentPadding: 6)

            if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineSpacing(4)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
    }
}

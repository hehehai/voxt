import SwiftUI

extension RemoteProviderConfigurationSheet {
    var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SettingsMenuPicker(
                selection: providerModelSelectionBinding,
                options: providerModelMenuOptions,
                selectedTitle: providerModelSelectedTitle,
                width: 240
            )

            if llmProviderForPicker != nil && resolvedSelectionForPicker == customModelOptionID {
                Text("Custom Model ID (Optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. doubao-seed-2-0-pro-260215", text: $customModelID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }
        }
    }

    var endpointAndKeySection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("Endpoint (Optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("https://...", text: $endpoint)
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
                                Text("Apply Preset")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))

                        if !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Clear") {
                                endpoint = ""
                            }
                            .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))
                        }

                        Spacer()
                    }
                    Text("Aliyun API keys are region-specific; use the matching endpoint.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("Paste API key", text: $apiKey)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }
        }
    }

    var meetingModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meeting ASR")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SettingsMenuPicker(
                selection: meetingModelSelectionBinding,
                options: meetingModelMenuOptions,
                selectedTitle: meetingModelSelectedTitle,
                width: 240
            )

            if resolvedMeetingSelectionForPicker == customModelOptionID {
                Text("Custom Meeting Model ID")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. qwen3-asr-flash-filetrans", text: $customMeetingModelID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            Text("Used only for Meeting Notes transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var doubaoCredentialsSection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("App ID")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("App ID", text: $appID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Access Token")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("Paste access token", text: $accessToken)
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
            Toggle("Chunk Pseudo Realtime Preview", isOn: $openAIChunkPseudoRealtimeEnabled)
                .toggleStyle(.switch)
            Text("Enable segmented OpenAI ASR preview during recording. This roughly doubles usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var actionSection: some View {
        SettingsDialogActionRow {
            if isTestingConnection {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Test") {
                testConnection()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .disabled(isTestingConnection)

            if showsMeetingASRSection {
                Button("Test Meeting ASR") {
                    testMeetingConnection()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .disabled(isTestingConnection)
            }
        } trailing: {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                onSave(currentConfigurationSnapshot)
                dismiss()
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }
}

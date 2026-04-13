import SwiftUI

struct DictionaryAdvancedSettingsDialog: View {
    @Binding var dictionaryHighConfidenceCorrectionEnabled: Bool
    @Binding var isPresented: Bool
    let dictionaryRecognitionEnabled: Bool
    let pendingHistoryScanCount: Int
    let localModelOptions: [DictionaryHistoryScanModelOption]
    let remoteModelOptions: [DictionaryHistoryScanModelOption]
    let selectedModelOption: DictionaryHistoryScanModelOption?
    @Binding var selectedModelID: String
    @Binding var draftPrompt: String
    let onRestoreDefaultPrompt: () -> Void
    let onSave: () -> Void

    private var modelOptions: [SettingsMenuOption<String>] {
        (localModelOptions + remoteModelOptions).map { option in
            SettingsMenuOption(value: option.id, title: option.title)
        }
    }

    private var selectedModelTitle: String {
        selectedModelOption?.title ?? modelOptions.first?.title ?? String(localized: "Select Model")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dictionary Advanced Settings")
                .font(.title3.weight(.semibold))

            Toggle("Allow High-Confidence Auto Correction", isOn: $dictionaryHighConfidenceCorrectionEnabled)
                .controlSize(.small)
                .disabled(!dictionaryRecognitionEnabled)

            Text("When enabled, the final output can replace very high-confidence near matches with exact dictionary terms before the text is inserted.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "One-Click Ingest"))
                    .font(.headline)

                Text("Choose the model and prompt used by one-click ingest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(
                    AppLocalization.format(
                        "%d new history records are ready for dictionary ingestion.",
                        pendingHistoryScanCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Model"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    SettingsMenuPicker(
                        selection: $selectedModelID,
                        options: modelOptions,
                        selectedTitle: selectedModelTitle,
                        width: 260
                    )
                    .disabled(modelOptions.isEmpty)

                    if let selectedModelOption, !selectedModelOption.detail.isEmpty {
                        Text(selectedModelOption.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if modelOptions.isEmpty {
                        Text("No configured local or remote model is available for dictionary ingestion. Configure one in Model settings first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "Ingest Prompt"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        Button("Restore Default", action: onRestoreDefaultPrompt)
                            .buttonStyle(SettingsPillButtonStyle())
                    }

                    PromptEditorView(
                        text: $draftPrompt,
                        height: 180,
                        contentPadding: 2
                    )
                }

                Text("One-click ingest scans new history records and writes accepted terms directly into the dictionary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsDialogActionRow {
                Button("Done") {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

import SwiftUI

struct DictionaryAdvancedSettingsDialog: View {
    @Binding var dictionaryHighConfidenceCorrectionEnabled: Bool
    @Binding var isPresented: Bool
    let dictionaryRecognitionEnabled: Bool

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

            HStack {
                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct DictionarySuggestionIngestDialog: View {
    let pendingHistoryScanCount: Int
    let localModelOptions: [DictionaryHistoryScanModelOption]
    let remoteModelOptions: [DictionaryHistoryScanModelOption]
    let selectedModelOption: DictionaryHistoryScanModelOption?
    @Binding var selectedModelID: String
    @Binding var draft: DictionarySuggestionFilterSettings
    @Binding var isPresented: Bool
    let onIngest: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "One-Click Ingest"))
                .font(.title3.weight(.semibold))

            Text(
                AppLocalization.format(
                    "%d new history records will be parsed in batches to extract candidate dictionary terms.",
                    pendingHistoryScanCount
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Model"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker(String(localized: "Model"), selection: $selectedModelID) {
                    ForEach(localModelOptions) { option in
                        Text(option.title).tag(option.id)
                    }

                    if !localModelOptions.isEmpty && !remoteModelOptions.isEmpty {
                        Divider()
                    }

                    ForEach(remoteModelOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                if let selectedModelOption, !selectedModelOption.detail.isEmpty {
                    Text(selectedModelOption.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Ingest Prompt"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                PromptEditorView(
                    text: $draft.prompt,
                    height: 144,
                    contentPadding: 2
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Stepper(value: $draft.batchSize, in: DictionarySuggestionFilterSettings.minimumBatchSize...DictionarySuggestionFilterSettings.maximumBatchSize) {
                    HStack {
                        Text("Batch Size")
                        Spacer()
                        Text("\(draft.batchSize)")
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(
                    value: $draft.maxCandidatesPerBatch,
                    in: DictionarySuggestionFilterSettings.minimumMaxCandidates...DictionarySuggestionFilterSettings.maximumMaxCandidates
                ) {
                    HStack {
                        Text("Max Candidates Per Batch")
                        Spacer()
                        Text("\(draft.maxCandidatesPerBatch)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(String(localized: "Ingest runs with the current draft only. Save stores the prompt and thresholds, then runs ingestion."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button(String(localized: "Ingest"), action: onIngest)
                    .disabled(selectedModelID.isEmpty)

                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedModelID.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 620)
    }
}

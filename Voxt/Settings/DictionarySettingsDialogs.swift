import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct DictionaryAdvancedSettingsDialog: View {
    @Binding var dictionaryAutoLearningEnabled: Bool
    @Binding var automaticLearningPromptDraft: String
    @Binding var dictionaryHighConfidenceCorrectionEnabled: Bool
    @Binding var isPresented: Bool
    let dictionaryRecognitionEnabled: Bool
    let pendingHistoryScanCount: Int
    let localModelOptions: [DictionaryHistoryScanModelOption]
    let remoteModelOptions: [DictionaryHistoryScanModelOption]
    let selectedModelOption: DictionaryHistoryScanModelOption?
    @Binding var selectedModelID: String
    @Binding var draftPrompt: String
    let onRestoreDefaultAutomaticLearningPrompt: () -> Void
    let onRestoreDefaultPrompt: () -> Void
    let onSave: () -> Void

    private var modelOptions: [SettingsMenuOption<String>] {
        (localModelOptions + remoteModelOptions).map { option in
            SettingsMenuOption(value: option.id, title: option.title)
        }
    }

    private var selectedModelTitle: String {
        selectedModelOption?.title ?? modelOptions.first?.title ?? localized("Select Model")
    }

    private let dialogWidth: CGFloat = 520
    private let dialogMaxHeight: CGFloat = 700
    private let contentMaxHeight: CGFloat = 620

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(localized("Dictionary Advanced Settings"))
                        .font(.title3.weight(.semibold))

                    Toggle(localized("Allow High-Confidence Auto Correction"), isOn: $dictionaryHighConfidenceCorrectionEnabled)
                        .controlSize(.small)
                        .toggleStyle(.switch)
                        .disabled(!dictionaryRecognitionEnabled)

                    Text(localized("When enabled, the final output can replace very high-confidence near matches with exact dictionary terms before the text is inserted."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(localized("Auto-Add Corrected Terms"), isOn: $dictionaryAutoLearningEnabled)
                        .controlSize(.small)
                        .toggleStyle(.switch)

                    Text(localized("When enabled, Voxt watches the edited input for a short time after inserting transcription text and can add confirmed corrected terms to the dictionary automatically."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(localized("Correction Listener Prompt"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 8)

                            Button(localized("Restore Default"), action: onRestoreDefaultAutomaticLearningPrompt)
                                .buttonStyle(SettingsPillButtonStyle())
                        }

                        PromptEditorView(
                            text: $automaticLearningPromptDraft,
                            height: 180,
                            contentPadding: 2,
                            variables: [
                                PromptTemplateVariableDescriptor(
                                    token: AppPreferenceKey.automaticDictionaryLearningMainLanguageTemplateVariable,
                                    tipKey: "Template tip {{USER_MAIN_LANGUAGE}}"
                                ),
                                PromptTemplateVariableDescriptor(
                                    token: AppPreferenceKey.automaticDictionaryLearningOtherLanguagesTemplateVariable,
                                    tipKey: "Template tip {{USER_OTHER_LANGUAGES}}"
                                ),
                                PromptTemplateVariableDescriptor(
                                    token: AppPreferenceKey.automaticDictionaryLearningInsertedTextTemplateVariable,
                                    tipKey: "Template tip {{INSERTED}}"
                                ),
                                PromptTemplateVariableDescriptor(
                                    token: AppPreferenceKey.automaticDictionaryLearningBaselineContextTemplateVariable,
                                    tipKey: "Template tip {{BEFORE_CTX}}"
                                ),
                                PromptTemplateVariableDescriptor(
                                    token: AppPreferenceKey.automaticDictionaryLearningFinalContextTemplateVariable,
                                    tipKey: "Template tip {{AFTER_CTX}}"
                                ),
                                PromptTemplateVariableDescriptor(
                                    token: AppPreferenceKey.automaticDictionaryLearningBaselineFragmentTemplateVariable,
                                    tipKey: "Template tip {{BEFORE_EDIT}}"
                                ),
                                PromptTemplateVariableDescriptor(
                                    token: AppPreferenceKey.automaticDictionaryLearningFinalFragmentTemplateVariable,
                                    tipKey: "Template tip {{AFTER_EDIT}}"
                                ),
                                PromptTemplateVariableDescriptor(
                                    token: AppPreferenceKey.automaticDictionaryLearningExistingTermsTemplateVariable,
                                    tipKey: "Template tip {{EXISTING}}"
                                )
                            ]
                        )

                        Text(localized("This prompt is used when Voxt compares inserted text with the user's later correction and asks the LLM which corrected terms are worth adding.")) 
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(localized("One-Click Ingest"))
                            .font(.headline)

                        Text(localized("Choose the model and prompt used by one-click ingest."))
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
                            Text(localized("Model"))
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
                                Text(localized("No configured local or remote model is available for dictionary ingestion. Configure one in Model settings first."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(localized("Ingest Prompt"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 8)

                                Button(localized("Restore Default"), action: onRestoreDefaultPrompt)
                                    .buttonStyle(SettingsPillButtonStyle())
                            }

                            PromptEditorView(
                                text: $draftPrompt,
                                height: 180,
                                contentPadding: 2,
                                variables: [
                                    PromptTemplateVariableDescriptor(
                                        token: "{{USER_MAIN_LANGUAGE}}",
                                        tipKey: "Template tip {{USER_MAIN_LANGUAGE}}"
                                    ),
                                    PromptTemplateVariableDescriptor(
                                        token: "{{USER_OTHER_LANGUAGES}}",
                                        tipKey: "Template tip {{USER_OTHER_LANGUAGES}}"
                                    ),
                                    PromptTemplateVariableDescriptor(
                                        token: "{{HISTORY_RECORDS}}",
                                        tipKey: "Template tip {{HISTORY_RECORDS}}"
                                    )
                                ]
                            )
                        }

                        Text(localized("One-click ingest scans new history records and writes accepted terms directly into the dictionary."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: contentMaxHeight)

            SettingsDialogActionRow {
                Button(localized("Done")) {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: dialogWidth)
        .frame(maxHeight: dialogMaxHeight)
    }
}

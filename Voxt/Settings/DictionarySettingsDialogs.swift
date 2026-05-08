import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct DictionaryAdvancedSettingsDialog: View {
    @Binding var dictionaryAutoLearningEnabled: Bool
    @Binding var automaticLearningPromptDraft: String
    @Binding var dictionaryHighConfidenceCorrectionEnabled: Bool
    @Binding var isPresented: Bool
    let onRestoreDefaultAutomaticLearningPrompt: () -> Void
    let onSave: () -> Void

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

struct DictionaryOneClickIngestDialog: View {
    @Binding var isPresented: Bool
    let pendingHistoryScanCount: Int
    let localModelOptions: [DictionaryHistoryScanModelOption]
    let remoteModelOptions: [DictionaryHistoryScanModelOption]
    @Binding var selectedModelID: String
    @Binding var draftPrompt: String
    let historyScanProgress: DictionaryHistoryScanProgress
    let statusText: String
    let cancellationText: String
    let actionMessage: String?
    let onRestoreDefaultPrompt: () -> Void
    let onSave: () -> Void
    let onStart: () -> Void
    let onCancelRunning: () -> Void

    private let dialogWidth: CGFloat = 560
    private let dialogMaxHeight: CGFloat = 760
    private let contentMaxHeight: CGFloat = 660

    private var modelOptions: [SettingsMenuOption<String>] {
        (localModelOptions + remoteModelOptions).map { option in
            SettingsMenuOption(value: option.id, title: option.title)
        }
    }

    private var selectedModelTitle: String {
        modelOptions.first(where: { $0.value == selectedModelID })?.title ?? modelOptions.first?.title ?? localized("Select Model")
    }

    private var startButtonTitle: String {
        if historyScanProgress.isRunning {
            return historyScanProgress.isCancellationRequested
                ? localized("Canceling...")
                : localized("Cancel Ingest")
        }
        return localized("Start Ingest")
    }

    private var startButtonDisabled: Bool {
        if historyScanProgress.isRunning {
            return historyScanProgress.isCancellationRequested
        }
        return modelOptions.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(localized("One-Click Ingest"))
                        .font(.title3.weight(.semibold))

                    Text(
                        AppLocalization.format(
                            "%d new history records are ready for dictionary ingestion.",
                            pendingHistoryScanCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if historyScanProgress.isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(
                                value: Double(historyScanProgress.processedCount),
                                total: Double(max(historyScanProgress.totalCount, 1))
                            )

                            Text(historyScanProgress.isCancellationRequested ? cancellationText : statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let errorMessage = historyScanProgress.errorMessage,
                              !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let actionMessage, !actionMessage.isEmpty {
                        Text(actionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized("Model"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        SettingsMenuPicker(
                            selection: $selectedModelID,
                            options: modelOptions,
                            selectedTitle: selectedModelTitle,
                            width: 280
                        )
                        .disabled(historyScanProgress.isRunning || modelOptions.isEmpty)

                        if modelOptions.isEmpty {
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
                                .disabled(historyScanProgress.isRunning)
                        }

                        PromptEditorView(
                            text: $draftPrompt,
                            height: 220,
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
                        .disabled(historyScanProgress.isRunning)
                    }

                    Text(localized("One-click ingest scans new history records and writes accepted terms directly into the dictionary."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: contentMaxHeight)

            SettingsDialogActionRow {
                Button(localized("Cancel")) {
                    isPresented = false
                }
                .buttonStyle(SettingsPillButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(localized("Save")) {
                    onSave()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .disabled(historyScanProgress.isRunning)

                Button(startButtonTitle) {
                    if historyScanProgress.isRunning {
                        onCancelRunning()
                    } else {
                        onStart()
                    }
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .disabled(startButtonDisabled)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: dialogWidth)
        .frame(maxHeight: dialogMaxHeight)
    }
}

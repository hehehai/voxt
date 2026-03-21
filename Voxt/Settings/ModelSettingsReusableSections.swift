import SwiftUI

struct ModelSettingsProviderOption: Identifiable {
    let id: String
    let titleKey: LocalizedStringKey
}

enum ModelSettingsPromptVariables {
    static let enhancement = [
        PromptTemplateVariableDescriptor(
            token: AppDelegate.rawTranscriptionTemplateVariable,
            tipKey: "Template tip {{RAW_TRANSCRIPTION}}"
        ),
        PromptTemplateVariableDescriptor(
            token: AppDelegate.userMainLanguageTemplateVariable,
            tipKey: "Template tip {{USER_MAIN_LANGUAGE}}"
        )
    ]

    static let translation = [
        PromptTemplateVariableDescriptor(
            token: "{{TARGET_LANGUAGE}}",
            tipKey: "Template tip {{TARGET_LANGUAGE}}"
        ),
        PromptTemplateVariableDescriptor(
            token: "{{USER_MAIN_LANGUAGE}}",
            tipKey: "Template tip {{USER_MAIN_LANGUAGE}}"
        ),
        PromptTemplateVariableDescriptor(
            token: "{{SOURCE_TEXT}}",
            tipKey: "Template tip {{SOURCE_TEXT}}"
        )
    ]

    static let rewrite = [
        PromptTemplateVariableDescriptor(
            token: "{{DICTATED_PROMPT}}",
            tipKey: "Template tip {{DICTATED_PROMPT}}"
        ),
        PromptTemplateVariableDescriptor(
            token: "{{SOURCE_TEXT}}",
            tipKey: "Template tip {{SOURCE_TEXT}}"
        )
    ]
}

struct ResettablePromptSection: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let defaultText: String
    let variables: [PromptTemplateVariableDescriptor]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Reset to Default") {
                text = defaultText
            }
            .controlSize(.small)
            .disabled(text == defaultText)
        }

        PromptEditorView(text: $text)
        PromptTemplateVariablesView(variables: variables)
    }
}

struct ModelTaskSettingsCard: View {
    let title: LocalizedStringKey
    let providerPickerTitle: LocalizedStringKey
    let providerOptions: [ModelSettingsProviderOption]
    @Binding var selectedProviderID: String
    let modelLabelText: String
    let modelPickerTitle: LocalizedStringKey
    let modelOptions: [TranslationModelOption]
    let selectedModelBinding: Binding<String>
    let modelDisplayText: String?
    let emptyStateText: String
    let statusMessage: String?
    let statusIsWarning: Bool
    let promptTitle: LocalizedStringKey
    @Binding var promptText: String
    let defaultPromptText: String
    let variables: [PromptTemplateVariableDescriptor]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                Picker(providerPickerTitle, selection: $selectedProviderID) {
                    ForEach(providerOptions) { provider in
                        Text(provider.titleKey).tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)

                HStack(alignment: .center, spacing: 12) {
                    Text(modelLabelText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let modelDisplayText {
                        Text(modelDisplayText)
                            .foregroundStyle(.secondary)
                    } else if modelOptions.isEmpty {
                        Text("Not available")
                            .foregroundStyle(.tertiary)
                    } else {
                        Picker(modelPickerTitle, selection: selectedModelBinding) {
                            ForEach(modelOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .id("model-picker-\(selectedProviderID)")
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 280, alignment: .trailing)
                    }
                }

                if modelOptions.isEmpty {
                    Text(emptyStateText)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsWarning ? .orange : .secondary)
                }

                ResettablePromptSection(
                    title: promptTitle,
                    text: $promptText,
                    defaultText: defaultPromptText,
                    variables: variables
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

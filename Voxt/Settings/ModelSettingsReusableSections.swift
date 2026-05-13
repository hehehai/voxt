import SwiftUI

struct ModelSettingsProviderOption: Identifiable {
    let id: String
    let title: String
}

enum ModelSettingsPromptVariables {
    static let enhancement = [
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
        )
    ]

    static let rewrite: [PromptTemplateVariableDescriptor] = []

    static let appEnhancement = [
        PromptTemplateVariableDescriptor(
            token: AppDelegate.userMainLanguageTemplateVariable,
            tipKey: "Template tip {{USER_MAIN_LANGUAGE}}"
        )
    ]
}

enum PromptAuthoringGuidance {
    static let optionalVariablesTitle = AppLocalization.localizedString("Optional variables")

    static let enhancement = AppLocalization.localizedString(
        "Write stable cleanup rules only. Do not paste raw transcription here. Voxt injects the transcription, glossary, and app context automatically."
    )

    static let translation = AppLocalization.localizedString(
        "Write translation rules only. Do not paste source text here. Voxt injects the source text, target language, and glossary automatically."
    )

    static let rewrite = AppLocalization.localizedString(
        "Write rewrite behavior rules only. Do not paste spoken instructions or source text here. Voxt injects both automatically at runtime."
    )

    static let appEnhancement = AppLocalization.localizedString(
        "Recommended: describe only app-specific tone or formatting preferences. Do not paste raw transcription here. Voxt injects the transcription automatically."
    )
}

struct ResettablePromptSection: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let defaultText: String
    let variables: [PromptTemplateVariableDescriptor]
    var guidance: String? = nil
    var variablesTitle: String? = nil
    var promptHeight: CGFloat = 124
    var onTextChange: ((String) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Button(AppLocalization.localizedString("Reset to Default")) {
                text = defaultText
            }
            .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10))
            .disabled(text == defaultText)
        }

        if let guidance, !guidance.isEmpty {
            Text(guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        PromptEditorView(
            text: $text,
            height: promptHeight,
            variables: variables,
            variablesTitle: variablesTitle,
            onTextChange: onTextChange,
            onFocusChange: onFocusChange
        )
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
    let promptGuidance: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                HStack(alignment: .center, spacing: 12) {
                    SettingsMenuPicker(
                        selection: $selectedProviderID,
                        options: providerOptions.map { provider in
                            SettingsMenuOption(value: provider.id, title: provider.title)
                        },
                        selectedTitle: selectedProviderTitle,
                        width: 236
                    )

                    if let modelDisplayText {
                        Text(modelDisplayText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(
                                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                                    .fill(SettingsUIStyle.controlFillColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                                    .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                            )
                    } else if modelOptions.isEmpty {
                        Text(AppLocalization.localizedString("Not available"))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(
                                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                                    .fill(SettingsUIStyle.controlFillColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                                    .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                            )
                    } else {
                        SettingsMenuPicker(
                            selection: selectedModelBinding,
                            options: modelOptions.map { option in
                                SettingsMenuOption(value: option.id, title: option.title)
                            },
                            selectedTitle: selectedModelTitle,
                            width: 260
                        )
                        .id("model-picker-\(selectedProviderID)")
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
                    variables: variables,
                    guidance: promptGuidance,
                    variablesTitle: PromptAuthoringGuidance.optionalVariablesTitle
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private extension ModelTaskSettingsCard {
    var selectedProviderTitle: String {
        providerOptions.first(where: { $0.id == selectedProviderID }).map(\.title)
            ?? selectedProviderID
    }

    var selectedModelTitle: String {
        modelOptions.first(where: { $0.id == selectedModelBinding.wrappedValue })?.title
            ?? selectedModelBinding.wrappedValue
    }
}

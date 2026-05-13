import SwiftUI

struct GroupEditorSheet: View {
    let title: String
    let actionTitle: String
    @Binding var name: String
    @Binding var prompt: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    @State private var selectedPresetID = Self.placeholderPresetID

    private static let placeholderPresetID = "choose-template"

    private struct PromptPreset: Identifiable {
        let id: String
        let title: String
        let prompt: String
    }

    private var presets: [PromptPreset] {
        [
            PromptPreset(
                id: "slack",
                title: AppLocalization.localizedString("Slack / Chat"),
                prompt: AppLocalization.localizedString("Slack / Chat prompt preset")
            ),
            PromptPreset(
                id: "email",
                title: AppLocalization.localizedString("Email"),
                prompt: AppLocalization.localizedString("Email prompt preset")
            ),
            PromptPreset(
                id: "ide",
                title: AppLocalization.localizedString("IDE / Terminal"),
                prompt: AppLocalization.localizedString("IDE / Terminal prompt preset")
            ),
            PromptPreset(
                id: "docs",
                title: AppLocalization.localizedString("Docs / Notes"),
                prompt: AppLocalization.localizedString("Docs / Notes prompt preset")
            )
        ]
    }

    private var presetOptions: [SettingsMenuOption<String>] {
        [
            SettingsMenuOption(
                value: Self.placeholderPresetID,
                title: AppLocalization.localizedString("Choose template...")
            )
        ] + presets.map { preset in
            SettingsMenuOption(value: preset.id, title: preset.title)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.localizedString("Group Name"))
                            .font(.headline)
                        TextField(AppLocalization.localizedString("Enter group name"), text: $name)
                            .textFieldStyle(.plain)
                            .settingsFieldSurface(minHeight: 34)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.localizedString("Prompt"))
                            .font(.headline)
                        Text(PromptAuthoringGuidance.appEnhancement)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppLocalization.localizedString("Starter templates"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            SettingsMenuPicker(
                                selection: $selectedPresetID,
                                options: presetOptions,
                                selectedTitle: AppLocalization.localizedString("Choose template..."),
                                width: 220
                            )
                            .onChange(of: selectedPresetID) { _, newValue in
                                applyPreset(id: newValue)
                            }
                        }

                        PromptEditorView(
                            text: $prompt,
                            height: 160,
                            contentPadding: 8,
                            variables: ModelSettingsPromptVariables.appEnhancement,
                            variablesLayout: .twoColumns,
                            variablesTitle: PromptAuthoringGuidance.optionalVariablesTitle
                        )
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }

            Divider()

            SettingsDialogActionRow {
                Button(AppLocalization.localizedString("Cancel"), action: onCancel)
                    .buttonStyle(SettingsPillButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button(actionTitle, action: onSave)
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
    }

    private func applyPreset(id: String) {
        guard
            id != Self.placeholderPresetID,
            let preset = presets.first(where: { $0.id == id })
        else {
            return
        }

        prompt = preset.prompt
        DispatchQueue.main.async {
            selectedPresetID = Self.placeholderPresetID
        }
    }
}

struct URLBatchEditorSheet: View {
    let title: String
    let actionTitle: String
    @Binding var text: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    @State private var testInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.localizedString("URL Patterns"))
                    .font(.headline)
                PromptEditorView(text: $text, height: 180, contentPadding: 8)

                Text(AppLocalization.localizedString("Enter one wildcard pattern per line. Examples: google.com/*, *.google.com/*, x.*.google.com/*/doc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.localizedString("Pattern Test"))
                        .font(.headline)

                    TextField(AppLocalization.localizedString("Paste a URL or any text to test the patterns above"), text: $testInput)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                                .fill(testFieldFillColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                                .strokeBorder(testFieldBorderColor, lineWidth: 1)
                        )

                    Text(testFeedbackText)
                        .font(.caption)
                        .foregroundStyle(testFeedbackColor)
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 6)

            SettingsDialogActionRow {
                Button(AppLocalization.localizedString("Cancel"), action: onCancel)
                    .buttonStyle(SettingsPillButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button(actionTitle, action: onSave)
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private var normalizedPatterns: [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(AppBranchURLPatternService.normalizedPattern)
            .filter(AppBranchURLPatternService.isValidWildcardURLPattern)
    }

    private var normalizedCandidate: String? {
        AppBranchURLPatternService.normalizedURLForMatching(testInput)
    }

    private var matchedPattern: String? {
        guard let normalizedCandidate else { return nil }
        return normalizedPatterns.first {
            AppBranchURLPatternService.wildcardMatches(pattern: $0, candidate: normalizedCandidate)
        }
    }

    private var testFieldFillColor: Color {
        switch testStatus {
        case .idle:
            return SettingsUIStyle.controlFillColor
        case .matched:
            return Color.green.opacity(0.12)
        case .unmatched:
            return Color.red.opacity(0.10)
        }
    }

    private var testFieldBorderColor: Color {
        switch testStatus {
        case .idle:
            return SettingsUIStyle.subtleBorderColor
        case .matched:
            return Color.green.opacity(0.7)
        case .unmatched:
            return Color.red.opacity(0.7)
        }
    }

    private var testFeedbackColor: Color {
        switch testStatus {
        case .idle:
            return .secondary
        case .matched:
            return Color.green
        case .unmatched:
            return Color.red
        }
    }

    private var testFeedbackText: String {
        if testInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppLocalization.localizedString("Enter a URL or text to verify whether it matches the patterns above.")
        }
        if normalizedPatterns.isEmpty {
            return AppLocalization.localizedString("Add at least one valid wildcard pattern above to test matching.")
        }
        if let matchedPattern {
            return AppLocalization.format("Matched pattern: %@", matchedPattern)
        }
        return AppLocalization.localizedString("No pattern matched.")
    }

    private var testStatus: URLPatternTestStatus {
        guard !testInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .idle }
        guard !normalizedPatterns.isEmpty, normalizedCandidate != nil else { return .idle }
        return matchedPattern == nil ? .unmatched : .matched
    }
}

private enum URLPatternTestStatus {
    case idle
    case matched
    case unmatched
}

struct URLDetailSheet: View {
    let pattern: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.localizedString("URL Detail"))
                .font(.title3.weight(.semibold))

            Text(pattern)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                        .fill(SettingsUIStyle.controlFillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                        .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                )

            SettingsDialogActionRow {
                Button(AppLocalization.localizedString("Close"), action: onClose)
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

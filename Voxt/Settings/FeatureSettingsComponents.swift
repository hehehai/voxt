import SwiftUI
import AppKit

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

private func localizedKey(_ key: String) -> LocalizedStringKey {
    LocalizedStringKey(AppLocalization.localizedString(key))
}

struct FeatureSummaryPill: Identifiable {
    let title: String
    let value: String

    var id: String { "\(title)-\(value)" }
}

struct FeatureHeroCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let pills: [FeatureSummaryPill]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !pills.isEmpty {
                HStack(spacing: 10) {
                    ForEach(pills) { pill in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pill.title.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(pill.value)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                                .fill(SettingsUIStyle.controlFillColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                                .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(18)
        .settingsPanelSurface(cornerRadius: SettingsUIStyle.panelCornerRadius, fillOpacity: 0.88)
    }
}

struct FeatureSettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FeatureSettingSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .fill(SettingsUIStyle.groupedFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
        )
    }
}

struct FeatureToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .fill(SettingsUIStyle.groupedFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
        )
    }
}

struct FeatureInlinePickerRow<PickerContent: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let picker: PickerContent

    init(title: String, detail: String, @ViewBuilder picker: () -> PickerContent) {
        self.title = title
        self.detail = detail
        self.picker = picker()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            picker
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .fill(SettingsUIStyle.groupedFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
        )
    }
}

struct FeatureHintBanner: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

struct FeatureSelectorRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            SettingsSelectionButton(width: 280, action: action) {
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

struct SettingsShortcutCaptureField: View {
    let title: LocalizedStringKey
    let hotkey: HotkeyPreference.Hotkey
    let isRecording: Bool
    let isPendingConfirmation: Bool
    let distinguishModifierSides: Bool
    let onFocus: () -> Void
    let onReset: () -> Void
    let onCancelPending: () -> Void
    let onConfirmPending: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()

            HStack(spacing: 8) {
                Text(
                    isRecording && !isPendingConfirmation
                        ? localized("Listening...")
                        : HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: distinguishModifierSides)
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.9)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                if isPendingConfirmation {
                    Button(localized("Cancel"), action: onCancelPending)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(nsColor: .controlAccentColor).opacity(0.12))
                        )
                    Button(localized("Confirm"), action: onConfirmPending)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(0.18))
                        )
                } else if isRecording {
                    Button(localized("Cancel"), action: onCancelPending)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(nsColor: .controlAccentColor).opacity(0.12))
                        )
                } else {
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(Text(localized("Reset shortcut")))
                }
            }
            .frame(height: 16)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsUIStyle.controlFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocus)
            .frame(width: 320, alignment: .trailing)
        }
    }
}

struct FeaturePromptSection: View {
    let title: String
    @Binding var text: String
    let defaultText: String
    let variables: [PromptTemplateVariableDescriptor]

    var body: some View {
        ResettablePromptSection(
            title: localizedKey(title),
            text: $text,
            defaultText: defaultText,
            variables: variables,
            promptHeight: 168
        )
    }
}

struct FlowTagBadgeStrip: View {
    let tags: [String]

    var body: some View {
        FlexibleTagLayout(tags: tags) { tag in
            Text(tag)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    Capsule()
                        .fill(SettingsUIStyle.subtleFillColor)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                )
        }
    }
}

private struct FlexibleTagLayout<Content: View>: View {
    let tags: [String]
    let content: (String) -> Content

    var body: some View {
        GeometryReader { proxy in
            generateContent(in: proxy)
        }
        .frame(minHeight: 10)
    }

    private func generateContent(in proxy: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(tags, id: \.self) { tag in
                content(tag)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > proxy.size.width {
                            width = 0
                            height -= dimension.height
                        }
                        let result = width
                        width = tag == tags.last ? 0 : width - dimension.width
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if tag == tags.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }
}

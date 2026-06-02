import SwiftUI
import AppKit

struct FeatureToggleRow: View {
    let title: String
    var badgeText: String? = nil
    let detail: String
    @Binding var isOn: Bool
    var isEmbedded = false

    var body: some View {
        FeatureRowScaffold(
            title: title,
            badgeText: badgeText,
            detail: detail,
            isEmbedded: isEmbedded
        ) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct FeatureInlinePickerRow<PickerContent: View>: View {
    let title: String
    let detail: String
    var isEmbedded = false
    @ViewBuilder let picker: PickerContent

    init(title: String, detail: String, isEmbedded: Bool = false, @ViewBuilder picker: () -> PickerContent) {
        self.title = title
        self.detail = detail
        self.isEmbedded = isEmbedded
        self.picker = picker()
    }

    var body: some View {
        FeatureRowScaffold(
            title: title,
            detail: detail,
            isEmbedded: isEmbedded
        ) {
            picker
        }
    }
}

struct FeatureInlineTextFieldRow: View {
    let title: String
    let detail: String
    @Binding var text: String
    let placeholder: String
    let width: CGFloat
    var isEmbedded = false

    var body: some View {
        FeatureRowScaffold(
            title: title,
            detail: detail,
            isEmbedded: isEmbedded
        ) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .settingsFieldSurface(width: width)
                .multilineTextAlignment(.leading)
        }
    }
}

struct FeatureDirectorySelectionRow: View {
    private let pathFieldWidth: CGFloat = 184
    private let actionButtonWidth: CGFloat = 26

    let title: String
    let detail: String
    let path: String
    let buttonTitle: String
    let action: () -> Void
    var isEmbedded = false

    var body: some View {
        FeatureRowScaffold(
            title: title,
            detail: detail,
            spacerMinLength: 12,
            isEmbedded: isEmbedded
        ) {
            HStack(alignment: .center, spacing: 8) {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(width: pathFieldWidth, alignment: .leading)
                    .settingsFieldSurface(width: pathFieldWidth, minHeight: 32)

                Button(action: action) {
                    Text(buttonTitle)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: actionButtonWidth)
                }
                .buttonStyle(SettingsPillButtonStyle())
            }
        }
    }
}

struct FeatureEmbeddedFieldGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(
        spacing: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}

struct FeatureDisclosureSection<Content: View>: View {
    let title: String
    var badgeText: String? = nil
    let detail: String
    let embeddedSpacing: CGFloat = 12
    var onExpand: (() -> Void)? = nil
    @ViewBuilder let content: Content

    @State private var isExpanded: Bool

    init(
        title: String,
        badgeText: String? = nil,
        detail: String = "",
        onExpand: (() -> Void)? = nil,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.badgeText = badgeText
        self.detail = detail
        self.onExpand = onExpand
        self.content = content()
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggleExpanded) {
                FeatureRowScaffold(
                    title: title,
                    badgeText: badgeText,
                    detail: detail,
                    isEmbedded: false
                ) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isExpanded {
                FeatureEmbeddedFieldGroup(spacing: embeddedSpacing) {
                    content
                }
                .clipped()
                .transition(.opacity)
            }
        }
        .clipped()
    }

    private func toggleExpanded() {
        let shouldExpand = !isExpanded
        withAnimation(.easeInOut(duration: 0.16)) {
            isExpanded.toggle()
        }
        guard shouldExpand else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onExpand?()
        }
    }
}

struct FeatureNoteSoundPresetRow<PickerContent: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let picker: PickerContent
    let onTrySound: () -> Void

    init(
        title: String,
        detail: String,
        @ViewBuilder picker: () -> PickerContent,
        onTrySound: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.picker = picker()
        self.onTrySound = onTrySound
    }

    var body: some View {
        FeatureRowScaffold(
            title: title,
            detail: detail,
            spacerMinLength: 12,
            isEmbedded: false
        ) {
            HStack(alignment: .center, spacing: 8) {
                picker

                Button(featureSettingsLocalized("Try Sound"), action: onTrySound)
                    .buttonStyle(SettingsPillButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct FeatureNoteAudioRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Binding var preset: InteractionSoundPreset
    let onTrySound: () -> TimeInterval

    @State private var isPreviewPlaying = false
    @State private var previewToken = UUID()

    var body: some View {
        FeatureRowScaffold(
            title: title,
            detail: detail,
            spacerMinLength: 12,
            isEmbedded: false
        ) {
            HStack(alignment: .center, spacing: 13) {
                if isOn {
                    HStack(spacing: 5) {
                        SettingsMenuPicker(
                            selection: $preset,
                            options: InteractionSoundPreset.allCases.map { preset in
                                SettingsMenuOption(value: preset, title: preset.title)
                            },
                            selectedTitle: preset.title,
                            width: 157.2,
                            allowsCompactWidth: true
                        )

                        Button(action: playPreview) {
                            FeatureSoundPreviewIcon()
                                .foregroundStyle(isPreviewPlaying ? Color.accentColor : Color.primary.opacity(0.86))
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(SettingsCompactIconButtonStyle(size: 34))
                        .help(featureSettingsLocalized("Try Sound"))
                    }
                }

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private func playPreview() {
        let duration = max(onTrySound(), 0.65)
        let token = UUID()
        previewToken = token
        isPreviewPlaying = true

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                guard previewToken == token else { return }
                isPreviewPlaying = false
            }
        }
    }
}

private struct FeatureSoundPreviewIcon: View {
    var body: some View {
        ZStack {
            SVGPathShape(pathData: "M7.96997 22.75C5.34997 22.75 3.21997 20.62 3.21997 18C3.21997 15.38 5.34997 13.25 7.96997 13.25C10.59 13.25 12.72 15.38 12.72 18C12.72 20.62 10.59 22.75 7.96997 22.75ZM7.96997 14.75C6.17997 14.75 4.71997 16.21 4.71997 18C4.71997 19.79 6.17997 21.25 7.96997 21.25C9.75997 21.25 11.22 19.79 11.22 18C11.22 16.21 9.76997 14.75 7.96997 14.75Z")
            SVGPathShape(pathData: "M11.97 18.75C11.56 18.75 11.22 18.41 11.22 18V4C11.22 3.59 11.56 3.25 11.97 3.25C12.38 3.25 12.72 3.59 12.72 4V18C12.72 18.41 12.39 18.75 11.97 18.75Z")
            SVGPathShape(pathData: "M19.13 10.2304C18.8 10.2304 18.45 10.1704 18.11 10.0604L13.69 8.59043C12.31 8.13043 11.23 6.63043 11.23 5.18043V4.00043C11.23 3.03043 11.63 2.19043 12.31 1.69043C13 1.19043 13.92 1.09043 14.84 1.39043L19.26 2.86043C20.64 3.32043 21.72 4.82043 21.72 6.27043V7.44043C21.72 8.41043 21.32 9.25043 20.64 9.75043C20.21 10.0804 19.68 10.2304 19.13 10.2304ZM13.82 2.72043C13.58 2.72043 13.36 2.78043 13.19 2.91043C12.89 3.12043 12.73 3.51043 12.73 4.00043V5.17043C12.73 5.97043 13.4 6.90043 14.16 7.16043L18.58 8.63043C19.04 8.79043 19.47 8.75043 19.76 8.54043C20.06 8.33043 20.22 7.94043 20.22 7.45043V6.28043C20.22 5.48043 19.55 4.55043 18.79 4.29043L14.37 2.82043C14.18 2.75043 13.99 2.72043 13.82 2.72043Z")
        }
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
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.92))
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
    var displayTextOverride: String? = nil
    var isReadOnly: Bool = false
    var modeButtonTitle: String? = nil
    var isModeButtonSelected = false
    var onModeButtonToggle: (() -> Void)? = nil
    var controlWidth: CGFloat = 320
    let onFocus: () -> Void
    let onReset: () -> Void
    let onCancelPending: () -> Void
    let onConfirmPending: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.92))
            Spacer()

            HStack(spacing: 8) {
                if let modeButtonTitle, let onModeButtonToggle {
                    Button(action: onModeButtonToggle) {
                        Text(featureSettingsLocalized(modeButtonTitle))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isModeButtonSelected ? .white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isModeButtonSelected ? Color.accentColor : Color.secondary.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Text(
                    displayTextOverride
                    ?? (isRecording && !isPendingConfirmation
                        ? featureSettingsLocalized("Listening...")
                        : HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: distinguishModifierSides))
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.9)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                if isPendingConfirmation {
                    Button(featureSettingsLocalized("Cancel"), action: onCancelPending)
                        .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 8, height: 24))
                    Button(featureSettingsLocalized("Confirm"), action: onConfirmPending)
                        .buttonStyle(SettingsPrimaryButtonStyle(horizontalPadding: 8, height: 24))
                } else if isRecording {
                    Button(featureSettingsLocalized("Cancel"), action: onCancelPending)
                        .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 8, height: 24))
                } else if !isReadOnly {
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(Text(featureSettingsLocalized("Reset shortcut")))
                }
            }
            .frame(minHeight: 18)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                    .fill(SettingsUIStyle.controlFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                    .strokeBorder(isHovered ? SettingsUIStyle.controlHoverBorderColor : SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .onTapGesture {
                guard !isReadOnly else { return }
                onFocus()
            }
            .frame(width: controlWidth, alignment: .trailing)
        }
    }
}

private struct FeatureRowChromeModifier: ViewModifier {
    let isEmbedded: Bool

    func body(content: Content) -> some View {
        content
    }
}

private struct FeatureRowScaffold<TrailingContent: View>: View {
    let title: String
    let badgeText: String?
    let detail: String
    var spacerMinLength: CGFloat = 0
    let isEmbedded: Bool
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        badgeText: String? = nil,
        detail: String,
        spacerMinLength: CGFloat = 0,
        isEmbedded: Bool,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.badgeText = badgeText
        self.detail = detail
        self.spacerMinLength = spacerMinLength
        self.isEmbedded = isEmbedded
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            FeatureRowLabelStack(title: title, badgeText: badgeText, detail: detail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: spacerMinLength)
            trailingContent
                .fixedSize(horizontal: true, vertical: false)
        }
        .modifier(FeatureRowChromeModifier(isEmbedded: isEmbedded))
    }
}

private struct FeatureRowLabelStack: View {
    let title: String
    let badgeText: String?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.92))

                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.24), lineWidth: 1)
                        )
                }

                Spacer(minLength: 0)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

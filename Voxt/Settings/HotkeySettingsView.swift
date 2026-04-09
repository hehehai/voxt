import SwiftUI
import AppKit
import Carbon

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

private struct HotkeyConflictRule {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let messageKey: String
}

private let hotkeyConflictRules: [HotkeyConflictRule] = [
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.function], messageKey: "May conflict with Globe / input source switching (fn Space). Disable or remap the macOS shortcut if needed."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.command], messageKey: "Conflicts with Spotlight (⌘Space)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.command, .option], messageKey: "Conflicts with Finder search (⌥⌘Space)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Tab), modifiers: [.command], messageKey: "Conflicts with App Switcher (⌘Tab)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command], messageKey: "Conflicts with window switcher (⌘`)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command], messageKey: "Conflicts with Quit (⌘Q)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_H), modifiers: [.command], messageKey: "Conflicts with Hide (⌘H)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_M), modifiers: [.command], messageKey: "Conflicts with Minimise (⌘M)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command], messageKey: "Conflicts with Close (⌘W).")
]

enum HotkeyShortcutKind: String, CaseIterable {
    case transcription
    case translation
    case rewrite
    case meeting

    var titleKey: LocalizedStringKey {
        switch self {
        case .transcription:
            return "Transcription"
        case .translation:
            return "Translation"
        case .rewrite:
            return "Content Rewrite"
        case .meeting:
            return "Meeting"
        }
    }
}

enum HotkeyShortcutVisibility {
    static func visibleKinds(meetingEnabled: Bool) -> [HotkeyShortcutKind] {
        meetingEnabled
            ? [.transcription, .translation, .rewrite, .meeting]
            : [.transcription, .translation, .rewrite]
    }
}

struct HotkeySettingsView: View {
    private enum RecordingField {
        case transcription
        case translation
        case rewrite
        case meeting
    }

    @AppStorage(AppPreferenceKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyPreference.defaultKeyCode)
    @AppStorage(AppPreferenceKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyPreference.defaultModifiers.rawValue)
    @AppStorage(AppPreferenceKey.hotkeySidedModifiers) private var hotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.translationHotkeyKeyCode) private var translationHotkeyKeyCode = Int(HotkeyPreference.defaultTranslationKeyCode)
    @AppStorage(AppPreferenceKey.translationHotkeyModifiers) private var translationHotkeyModifiers = Int(HotkeyPreference.defaultTranslationModifiers.rawValue)
    @AppStorage(AppPreferenceKey.translationHotkeySidedModifiers) private var translationHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.rewriteHotkeyKeyCode) private var rewriteHotkeyKeyCode = Int(HotkeyPreference.defaultRewriteKeyCode)
    @AppStorage(AppPreferenceKey.rewriteHotkeyModifiers) private var rewriteHotkeyModifiers = Int(HotkeyPreference.defaultRewriteModifiers.rawValue)
    @AppStorage(AppPreferenceKey.rewriteHotkeySidedModifiers) private var rewriteHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.meetingHotkeyKeyCode) private var meetingHotkeyKeyCode = Int(HotkeyPreference.defaultMeetingKeyCode)
    @AppStorage(AppPreferenceKey.meetingHotkeyModifiers) private var meetingHotkeyModifiers = Int(HotkeyPreference.defaultMeetingModifiers.rawValue)
    @AppStorage(AppPreferenceKey.meetingHotkeySidedModifiers) private var meetingHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.hotkeyTriggerMode) private var hotkeyTriggerMode = HotkeyPreference.defaultTriggerMode.rawValue
    @AppStorage(AppPreferenceKey.hotkeyDistinguishModifierSides) private var distinguishModifierSides = HotkeyPreference.defaultDistinguishModifierSides
    @AppStorage(AppPreferenceKey.hotkeyPreset) private var hotkeyPreset = HotkeyPreference.defaultPreset.rawValue
    @AppStorage(AppPreferenceKey.escapeKeyCancelsOverlaySession) private var escapeKeyCancelsOverlaySession = true
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.featureSettings) private var featureSettingsRaw = ""

    @State private var recordingField: RecordingField?
    @State private var pendingCapturedField: RecordingField?
    @State private var pendingCapturedHotkey: HotkeyPreference.Hotkey?
    @State private var recorderMessageKey: String?

    private var featureSettings: FeatureSettings {
        FeatureSettingsStore.load(defaults: .standard)
    }

    private var meetingEnabled: Bool {
        featureSettings.meeting.enabled
    }

    private var hotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(hotkeyKeyCode) },
            set: {
                hotkeyKeyCode = Int($0)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var modifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: {
                hotkeyModifiers = Int($0.rawValue)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var currentHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: hotkeyBinding.wrappedValue,
            modifiers: modifierBinding.wrappedValue,
            sidedModifiers: sidedModifierBinding.wrappedValue
        )
    }

    private var sidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: hotkeySidedModifiers).filtered(by: modifierBinding.wrappedValue) },
            set: { hotkeySidedModifiers = $0.filtered(by: modifierBinding.wrappedValue).rawValue }
        )
    }

    private var translationHotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(translationHotkeyKeyCode) },
            set: {
                translationHotkeyKeyCode = Int($0)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var translationModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(translationHotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: {
                translationHotkeyModifiers = Int($0.rawValue)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var currentTranslationHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: translationHotkeyBinding.wrappedValue,
            modifiers: translationModifierBinding.wrappedValue,
            sidedModifiers: translationSidedModifierBinding.wrappedValue
        )
    }

    private var translationSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: translationHotkeySidedModifiers).filtered(by: translationModifierBinding.wrappedValue) },
            set: { translationHotkeySidedModifiers = $0.filtered(by: translationModifierBinding.wrappedValue).rawValue }
        )
    }

    private var rewriteHotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(rewriteHotkeyKeyCode) },
            set: {
                rewriteHotkeyKeyCode = Int($0)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var rewriteModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(rewriteHotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: {
                rewriteHotkeyModifiers = Int($0.rawValue)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var currentRewriteHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: rewriteHotkeyBinding.wrappedValue,
            modifiers: rewriteModifierBinding.wrappedValue,
            sidedModifiers: rewriteSidedModifierBinding.wrappedValue
        )
    }

    private var rewriteSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: rewriteHotkeySidedModifiers).filtered(by: rewriteModifierBinding.wrappedValue) },
            set: { rewriteHotkeySidedModifiers = $0.filtered(by: rewriteModifierBinding.wrappedValue).rawValue }
        )
    }

    private var meetingHotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(meetingHotkeyKeyCode) },
            set: {
                meetingHotkeyKeyCode = Int($0)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var meetingModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(meetingHotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: {
                meetingHotkeyModifiers = Int($0.rawValue)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var currentMeetingHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: meetingHotkeyBinding.wrappedValue,
            modifiers: meetingModifierBinding.wrappedValue,
            sidedModifiers: meetingSidedModifierBinding.wrappedValue
        )
    }

    private var meetingSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: meetingHotkeySidedModifiers).filtered(by: meetingModifierBinding.wrappedValue) },
            set: { meetingHotkeySidedModifiers = $0.filtered(by: meetingModifierBinding.wrappedValue).rawValue }
        )
    }

    private var isRecordingBinding: Binding<Bool> {
        Binding(
            get: { recordingField != nil },
            set: { isRecording in
                if !isRecording {
                    recordingField = nil
                }
            }
        )
    }

    private var triggerModeBinding: Binding<HotkeyPreference.TriggerMode> {
        Binding(
            get: { HotkeyPreference.TriggerMode(rawValue: hotkeyTriggerMode) ?? HotkeyPreference.defaultTriggerMode },
            set: { hotkeyTriggerMode = $0.rawValue }
        )
    }

    private var presetBinding: Binding<HotkeyPreference.Preset> {
        Binding(
            get: { HotkeyPreference.Preset(rawValue: hotkeyPreset) ?? .custom },
            set: { applyPreset($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("Shortcut"))
                        .font(.headline)

                    HStack(alignment: .center, spacing: 12) {
                        Text(localized("Preset"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        SettingsMenuPicker(
                            selection: presetBinding,
                            options: HotkeyPreference.Preset.allCases.map { preset in
                                SettingsMenuOption(value: preset, title: preset.title)
                            },
                            selectedTitle: presetBinding.wrappedValue.title,
                            width: 220
                        )
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Distinguish Left/Right Modifiers"))
                                .foregroundStyle(.secondary)
                            Text(localized("When enabled, Left Shift and Right Shift are treated as different shortcuts."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { distinguishModifierSides },
                                set: { newValue in
                                    distinguishModifierSides = newValue
                                    hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    shortcutInput(
                        titleKey: "Transcription",
                        hotkey: displayedHotkey(for: .transcription, current: currentHotkey),
                        isRecording: recordingField == .transcription,
                        isPendingConfirmation: isPendingConfirmation(for: .transcription),
                        onFocus: { beginRecording(.transcription) },
                        onReset: {
                            hotkeyBinding.wrappedValue = HotkeyPreference.defaultKeyCode
                            modifierBinding.wrappedValue = HotkeyPreference.defaultModifiers
                            sidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    shortcutInput(
                        titleKey: "Translation",
                        hotkey: displayedHotkey(for: .translation, current: currentTranslationHotkey),
                        isRecording: recordingField == .translation,
                        isPendingConfirmation: isPendingConfirmation(for: .translation),
                        onFocus: { beginRecording(.translation) },
                        onReset: {
                            translationHotkeyBinding.wrappedValue = HotkeyPreference.defaultTranslationKeyCode
                            translationModifierBinding.wrappedValue = HotkeyPreference.defaultTranslationModifiers
                            translationSidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    shortcutInput(
                        titleKey: "Content Rewrite",
                        hotkey: displayedHotkey(for: .rewrite, current: currentRewriteHotkey),
                        isRecording: recordingField == .rewrite,
                        isPendingConfirmation: isPendingConfirmation(for: .rewrite),
                        onFocus: { beginRecording(.rewrite) },
                        onReset: {
                            rewriteHotkeyBinding.wrappedValue = HotkeyPreference.defaultRewriteKeyCode
                            rewriteModifierBinding.wrappedValue = HotkeyPreference.defaultRewriteModifiers
                            rewriteSidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    if meetingEnabled {
                        shortcutInput(
                            titleKey: "Meeting",
                            hotkey: displayedHotkey(for: .meeting, current: currentMeetingHotkey),
                            isRecording: recordingField == .meeting,
                            isPendingConfirmation: isPendingConfirmation(for: .meeting),
                            onFocus: { beginRecording(.meeting) },
                            onReset: {
                                meetingHotkeyBinding.wrappedValue = HotkeyPreference.defaultMeetingKeyCode
                                meetingModifierBinding.wrappedValue = HotkeyPreference.defaultMeetingModifiers
                                meetingSidedModifierBinding.wrappedValue = []
                                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                            },
                            onCancelPending: discardPendingCapture,
                            onConfirmPending: confirmPendingCapture
                        )
                    }

                    if recordingField != nil, pendingCapturedField != recordingField {
                        Text(localized("Type your shortcut now. Press Esc to cancel recording."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if pendingCapturedField != nil {
                        Text(localized("Shortcut captured. Press another shortcut to replace it, or choose Confirm / Cancel."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let recorderMessageKey {
                        Text(LocalizedStringKey(recorderMessageKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let conflict = hotkeyConflictMessage(for: currentHotkey) {
                        Text(localizedString("Transcription shortcut: %@", conflict))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let conflict = hotkeyConflictMessage(for: currentTranslationHotkey) {
                        Text(localizedString("Translation shortcut: %@", conflict))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let conflict = hotkeyConflictMessage(for: currentRewriteHotkey) {
                        Text(localizedString("Content rewrite shortcut: %@", conflict))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if meetingEnabled, let conflict = hotkeyConflictMessage(for: currentMeetingHotkey) {
                        Text(localizedString("Meeting notes shortcut: %@", conflict))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if currentHotkey == currentTranslationHotkey {
                        Text(localized("Transcription and translation shortcuts should be different."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if currentHotkey == currentRewriteHotkey {
                        Text(localized("Transcription and content rewrite shortcuts should be different."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if currentTranslationHotkey == currentRewriteHotkey {
                        Text(localized("Translation and content rewrite shortcuts should be different."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if meetingEnabled, currentHotkey == currentMeetingHotkey {
                        Text(localized("Transcription and meeting notes shortcuts should be different."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if meetingEnabled, currentTranslationHotkey == currentMeetingHotkey {
                        Text(localized("Translation and meeting notes shortcuts should be different."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if meetingEnabled, currentRewriteHotkey == currentMeetingHotkey {
                        Text(localized("Content rewrite and meeting notes shortcuts should be different."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HotkeyRecorderView(
                        isRecording: isRecordingBinding,
                        onCapture: { capturedHotkey in
                            guard let field = recordingField else { return }
                            pendingCapturedField = field
                            pendingCapturedHotkey = capturedHotkey
                        },
                        onCancelCapture: {
                            discardPendingCapture()
                            recordingField = nil
                        },
                        onRecorderMessageChange: { messageKey in
                            guard recorderMessageKey != messageKey else { return }
                            DispatchQueue.main.async {
                                recorderMessageKey = messageKey
                            }
                        }
                    )
                    .frame(width: 0, height: 0)

                    HStack(alignment: .center, spacing: 12) {
                        Text(localized("Trigger"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        SettingsMenuPicker(
                            selection: triggerModeBinding,
                            options: HotkeyPreference.TriggerMode.allCases.map { mode in
                                SettingsMenuOption(value: mode, title: mode.title)
                            },
                            selectedTitle: triggerModeBinding.wrappedValue.title,
                            width: 220
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("Cancel Shortcut"))
                        .font(.headline)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Use Esc to Cancel"))
                                .foregroundStyle(.secondary)
                            Text(localized("When enabled, pressing Esc cancels the active overlay session. Turn this off to disable Esc cancellation."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $escapeKeyCancelsOverlaySession)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            VoiceEndCommandSettingsSection()

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Hotkey Tips"))
                        .font(.headline)
                    Text(localized("Use a single key such as fn, or combine it with modifier keys."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localized(meetingEnabled
                        ? "Long Press runs while held. Tap starts and stops with a tap. Meeting also starts and stops with a tap."
                        : "Long Press runs while held. Tap starts and stops with a tap."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localized("If text is selected, the translation shortcut translates and replaces the selection directly."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localized("On macOS, fn shortcuts may conflict with Globe or input source switching. If needed, change that shortcut in System Settings > Keyboard > Keyboard Shortcuts > Input Sources."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .id(interfaceLanguageRaw)
        .id(featureSettingsRaw)
    }

    private func hotkeyConflictMessage(for hotkey: HotkeyPreference.Hotkey) -> String? {
        return hotkeyConflictRules.first {
            hotkey.keyCode == $0.keyCode && hotkey.modifiers == $0.modifiers
        }.map { AppLocalization.localizedString($0.messageKey) }
    }

    private func localizedString(_ formatKey: String, _ argument: String) -> String {
        AppLocalization.format(formatKey, argument)
    }

    private func applyPreset(_ preset: HotkeyPreference.Preset) {
        discardPendingCapture()
        hotkeyPreset = preset.rawValue
        guard let values = HotkeyPreference.presetHotkeys(for: preset) else { return }

        distinguishModifierSides = values.distinguishSides

        hotkeyKeyCode = Int(values.transcription.keyCode)
        hotkeyModifiers = Int(values.transcription.modifiers.rawValue)
        hotkeySidedModifiers = values.transcription.sidedModifiers.rawValue

        translationHotkeyKeyCode = Int(values.translation.keyCode)
        translationHotkeyModifiers = Int(values.translation.modifiers.rawValue)
        translationHotkeySidedModifiers = values.translation.sidedModifiers.rawValue

        rewriteHotkeyKeyCode = Int(values.rewrite.keyCode)
        rewriteHotkeyModifiers = Int(values.rewrite.modifiers.rawValue)
        rewriteHotkeySidedModifiers = values.rewrite.sidedModifiers.rawValue

        meetingHotkeyKeyCode = Int(values.meeting.keyCode)
        meetingHotkeyModifiers = Int(values.meeting.modifiers.rawValue)
        meetingHotkeySidedModifiers = values.meeting.sidedModifiers.rawValue
    }

    @ViewBuilder
    private func shortcutInput(
        titleKey: LocalizedStringKey,
        hotkey: HotkeyPreference.Hotkey,
        isRecording: Bool,
        isPendingConfirmation: Bool,
        onFocus: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onCancelPending: @escaping () -> Void,
        onConfirmPending: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(titleKey)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()

            HStack(spacing: 8) {
                Text(isRecording && !isPendingConfirmation ? localized("Listening...") : HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: distinguishModifierSides))
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

    private func beginRecording(_ field: RecordingField) {
        pendingCapturedField = nil
        pendingCapturedHotkey = nil
        recordingField = field
    }

    private func isPendingConfirmation(for field: RecordingField) -> Bool {
        pendingCapturedField == field && pendingCapturedHotkey != nil
    }

    private func displayedHotkey(for field: RecordingField, current: HotkeyPreference.Hotkey) -> HotkeyPreference.Hotkey {
        guard pendingCapturedField == field, let pendingCapturedHotkey else {
            return current
        }
        return pendingCapturedHotkey
    }

    private func discardPendingCapture() {
        recorderMessageKey = nil
        pendingCapturedField = nil
        pendingCapturedHotkey = nil
        recordingField = nil
    }

    private func confirmPendingCapture() {
        guard let field = pendingCapturedField, let hotkey = pendingCapturedHotkey else { return }

        switch field {
        case .transcription:
            hotkeyBinding.wrappedValue = hotkey.keyCode
            modifierBinding.wrappedValue = hotkey.modifiers
            sidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .translation:
            translationHotkeyBinding.wrappedValue = hotkey.keyCode
            translationModifierBinding.wrappedValue = hotkey.modifiers
            translationSidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .rewrite:
            rewriteHotkeyBinding.wrappedValue = hotkey.keyCode
            rewriteModifierBinding.wrappedValue = hotkey.modifiers
            rewriteSidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .meeting:
            meetingHotkeyBinding.wrappedValue = hotkey.keyCode
            meetingModifierBinding.wrappedValue = hotkey.modifiers
            meetingSidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        }

        hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
        pendingCapturedField = nil
        pendingCapturedHotkey = nil
        recordingField = nil
    }
}

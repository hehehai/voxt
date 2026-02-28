import SwiftUI
import AppKit
import Carbon

private struct HotkeyConflictRule {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let message: String
}

private let hotkeyConflictRules: [HotkeyConflictRule] = [
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.command], message: "Conflicts with Spotlight (⌘Space)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.command, .option], message: "Conflicts with Finder search (⌥⌘Space)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Tab), modifiers: [.command], message: "Conflicts with App Switcher (⌘Tab)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command], message: "Conflicts with window switcher (⌘`)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command], message: "Conflicts with Quit (⌘Q)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_H), modifiers: [.command], message: "Conflicts with Hide (⌘H)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_M), modifiers: [.command], message: "Conflicts with Minimise (⌘M)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command], message: "Conflicts with Close (⌘W).")
]

struct HotkeySettingsView: View {
    private enum RecordingField {
        case transcription
        case translation
    }

    @AppStorage(AppPreferenceKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyPreference.defaultKeyCode)
    @AppStorage(AppPreferenceKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyPreference.defaultModifiers.rawValue)
    @AppStorage(AppPreferenceKey.translationHotkeyKeyCode) private var translationHotkeyKeyCode = Int(HotkeyPreference.defaultTranslationKeyCode)
    @AppStorage(AppPreferenceKey.translationHotkeyModifiers) private var translationHotkeyModifiers = Int(HotkeyPreference.defaultTranslationModifiers.rawValue)
    @AppStorage(AppPreferenceKey.hotkeyTriggerMode) private var hotkeyTriggerMode = HotkeyPreference.defaultTriggerMode.rawValue

    @State private var recordingField: RecordingField?

    private var hotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(hotkeyKeyCode) },
            set: { hotkeyKeyCode = Int($0) }
        )
    }

    private var modifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: { hotkeyModifiers = Int($0.rawValue) }
        )
    }

    private var currentHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: hotkeyBinding.wrappedValue,
            modifiers: modifierBinding.wrappedValue
        )
    }

    private var translationHotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(translationHotkeyKeyCode) },
            set: { translationHotkeyKeyCode = Int($0) }
        )
    }

    private var translationModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(translationHotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: { translationHotkeyModifiers = Int($0.rawValue) }
        )
    }

    private var currentTranslationHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: translationHotkeyBinding.wrappedValue,
            modifiers: translationModifierBinding.wrappedValue
        )
    }

    private var activeKeyCodeBinding: Binding<UInt16> {
        Binding(
            get: {
                switch recordingField {
                case .translation:
                    return UInt16(translationHotkeyKeyCode)
                default:
                    return UInt16(hotkeyKeyCode)
                }
            },
            set: { newValue in
                switch recordingField {
                case .translation:
                    translationHotkeyKeyCode = Int(newValue)
                default:
                    hotkeyKeyCode = Int(newValue)
                }
            }
        )
    }

    private var activeModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: {
                switch recordingField {
                case .translation:
                    return NSEvent.ModifierFlags(rawValue: UInt(translationHotkeyModifiers)).intersection(.hotkeyRelevant)
                default:
                    return NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers)).intersection(.hotkeyRelevant)
                }
            },
            set: { newValue in
                switch recordingField {
                case .translation:
                    translationHotkeyModifiers = Int(newValue.rawValue)
                default:
                    hotkeyModifiers = Int(newValue.rawValue)
                }
            }
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
            get: { HotkeyPreference.TriggerMode(rawValue: hotkeyTriggerMode) ?? .longPress },
            set: { hotkeyTriggerMode = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Shortcut")
                        .font(.headline)

                    shortcutInput(
                        title: "Transcription",
                        hotkey: currentHotkey,
                        isRecording: recordingField == .transcription,
                        onFocus: { recordingField = .transcription },
                        onReset: {
                            hotkeyBinding.wrappedValue = HotkeyPreference.defaultKeyCode
                            modifierBinding.wrappedValue = HotkeyPreference.defaultModifiers
                        }
                    )

                    shortcutInput(
                        title: "Translation",
                        hotkey: currentTranslationHotkey,
                        isRecording: recordingField == .translation,
                        onFocus: { recordingField = .translation },
                        onReset: {
                            translationHotkeyBinding.wrappedValue = HotkeyPreference.defaultTranslationKeyCode
                            translationModifierBinding.wrappedValue = HotkeyPreference.defaultTranslationModifiers
                        }
                    )

                    if recordingField != nil {
                        Text("Type your shortcut now. Press Esc to cancel recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let conflict = hotkeyConflictMessage(for: currentHotkey) {
                        Text("Transcription shortcut: \(conflict)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let conflict = hotkeyConflictMessage(for: currentTranslationHotkey) {
                        Text("Translation shortcut: \(conflict)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if currentHotkey == currentTranslationHotkey {
                        Text("Transcription and translation shortcuts should be different.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HotkeyRecorderView(
                        keyCode: activeKeyCodeBinding,
                        modifiers: activeModifierBinding,
                        isRecording: isRecordingBinding
                    )
                    .frame(width: 0, height: 0)

                    HStack(alignment: .center, spacing: 12) {
                        Text("Trigger")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Trigger", selection: triggerModeBinding) {
                            ForEach(HotkeyPreference.TriggerMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips")
                        .font(.headline)
                    Text("Both actions support custom shortcuts. You can use a single key (such as fn) or a key combination.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
    }

    private func hotkeyConflictMessage(for hotkey: HotkeyPreference.Hotkey) -> String? {
        return hotkeyConflictRules.first {
            hotkey.keyCode == $0.keyCode && hotkey.modifiers == $0.modifiers
        }?.message
    }

    @ViewBuilder
    private func shortcutInput(
        title: String,
        hotkey: HotkeyPreference.Hotkey,
        isRecording: Bool,
        onFocus: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()

            HStack(spacing: 8) {
                Text(isRecording ? "Listening..." : HotkeyPreference.displayString(for: hotkey))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(isRecording ? .primary : .primary)
                Spacer()
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset shortcut")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocus)
            .frame(width: 220, alignment: .trailing)
        }
    }
}

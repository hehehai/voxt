import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct FeatureShortcutCaptureRow: View {
    let title: String
    let detail: String
    @Binding var hotkey: HotkeyPreference.Hotkey
    let defaultHotkey: HotkeyPreference.Hotkey

    @State private var isRecording = false
    @State private var recorderMessage: String?
    @State private var pendingCapturedHotkey: HotkeyPreference.Hotkey?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsShortcutCaptureField(
                title: LocalizedStringKey(title),
                hotkey: pendingCapturedHotkey ?? hotkey,
                isRecording: isRecording,
                isPendingConfirmation: pendingCapturedHotkey != nil,
                distinguishModifierSides: false,
                onFocus: {
                    pendingCapturedHotkey = nil
                    isRecording = true
                },
                onReset: {
                    hotkey = defaultHotkey
                    pendingCapturedHotkey = nil
                    isRecording = false
                    recorderMessage = nil
                },
                onCancelPending: {
                    pendingCapturedHotkey = nil
                    isRecording = false
                    recorderMessage = nil
                },
                onConfirmPending: {
                    if let pendingCapturedHotkey {
                        hotkey = pendingCapturedHotkey
                    }
                    self.pendingCapturedHotkey = nil
                    isRecording = false
                    recorderMessage = nil
                }
            )

            if let recorderMessage, !recorderMessage.isEmpty {
                Text(localized(recorderMessage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if pendingCapturedHotkey != nil {
                Text(localized("Shortcut captured. Press another shortcut to replace it, or choose Confirm / Cancel."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isRecording {
                Text(localized("Type your shortcut now. Press Esc to cancel recording."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HotkeyRecorderView(
                isRecording: $isRecording,
                onCapture: { capturedHotkey in
                    pendingCapturedHotkey = capturedHotkey
                    recorderMessage = nil
                },
                onCancelCapture: {
                    pendingCapturedHotkey = nil
                    isRecording = false
                    recorderMessage = nil
                },
                onRecorderMessageChange: { messageKey in
                    DispatchQueue.main.async {
                        recorderMessage = messageKey
                    }
                }
            )
            .frame(width: 0, height: 0)
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

struct FeatureNoteShortcutRow: View {
    let title: String
    let detail: String
    @Binding var shortcut: TranscriptionNoteTriggerSettings

    var body: some View {
        FeatureShortcutCaptureRow(
            title: title,
            detail: detail,
            hotkey: Binding(
                get: { shortcut.hotkey },
                set: { capturedHotkey in
                    shortcut = TranscriptionNoteTriggerSettings(
                        keyCode: capturedHotkey.keyCode,
                        modifiers: capturedHotkey.modifiers,
                        sidedModifiers: capturedHotkey.sidedModifiers
                    )
                }
            ),
            defaultHotkey: TranscriptionNoteTriggerSettings.defaultShortcut.hotkey
        )
    }
}

struct FeatureContinueShortcutRow: View {
    let title: String
    let detail: String
    @Binding var shortcut: TranscriptionContinueShortcutSettings

    var body: some View {
        FeatureShortcutCaptureRow(
            title: title,
            detail: detail,
            hotkey: Binding(
                get: { shortcut.hotkey },
                set: { capturedHotkey in
                    shortcut = TranscriptionContinueShortcutSettings(
                        keyCode: capturedHotkey.keyCode,
                        modifiers: capturedHotkey.modifiers,
                        sidedModifiers: capturedHotkey.sidedModifiers
                    )
                }
            ),
            defaultHotkey: TranscriptionContinueShortcutSettings.defaultShortcut.hotkey
        )
    }
}

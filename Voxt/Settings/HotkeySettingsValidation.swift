import AppKit
import Carbon
import Foundation

private struct HotkeyConflictRule {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let messageKey: String
}

private let hotkeySettingsConflictRules: [HotkeyConflictRule] = [
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.function], messageKey: "May conflict with Globe / input source switching (fn Space). Disable or remap the macOS shortcut if needed."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.command], messageKey: "Conflicts with Spotlight (⌘Space)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.command, .option], messageKey: "Conflicts with Finder search (⌥⌘Space)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Tab), modifiers: [.command], messageKey: "Conflicts with App Switcher (⌘Tab)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command], messageKey: "Conflicts with window switcher (⌘`)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command], messageKey: "Conflicts with Quit (⌘Q)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_H), modifiers: [.command], messageKey: "Conflicts with Hide (⌘H)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_M), modifiers: [.command], messageKey: "Conflicts with Minimise (⌘M)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command], messageKey: "Conflicts with Close (⌘W)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command], messageKey: "Conflicts with Paste (⌘V).")
]

struct HotkeySettingsValidation {
    struct State {
        let transcriptionHotkey: HotkeyPreference.Hotkey
        let translationHotkey: HotkeyPreference.Hotkey
        let meetingHotkey: HotkeyPreference.Hotkey?
        let rewriteHotkey: HotkeyPreference.Hotkey
        let shouldValidateRewriteHotkey: Bool
        let customPasteHotkey: HotkeyPreference.Hotkey?

        init(
            transcriptionHotkey: HotkeyPreference.Hotkey,
            translationHotkey: HotkeyPreference.Hotkey,
            meetingHotkey: HotkeyPreference.Hotkey? = nil,
            rewriteHotkey: HotkeyPreference.Hotkey,
            shouldValidateRewriteHotkey: Bool,
            customPasteHotkey: HotkeyPreference.Hotkey?
        ) {
            self.transcriptionHotkey = transcriptionHotkey
            self.translationHotkey = translationHotkey
            self.meetingHotkey = meetingHotkey
            self.rewriteHotkey = rewriteHotkey
            self.shouldValidateRewriteHotkey = shouldValidateRewriteHotkey
            self.customPasteHotkey = customPasteHotkey
        }
    }

    struct Message: Identifiable, Equatable {
        let id: String
        let text: String
    }

    static func messages(for state: State) -> [Message] {
        var messages: [Message] = []

        appendConflictMessage(
            for: state.transcriptionHotkey,
            formatKey: "Transcription shortcut: %@",
            id: "conflict.transcription",
            to: &messages
        )
        appendConflictMessage(
            for: state.translationHotkey,
            formatKey: "Translation shortcut: %@",
            id: "conflict.translation",
            to: &messages
        )
        if let meetingHotkey = state.meetingHotkey {
            appendConflictMessage(
                for: meetingHotkey,
                formatKey: "Meeting shortcut: %@",
                id: "conflict.meeting",
                to: &messages
            )
        }
        if state.shouldValidateRewriteHotkey {
            appendConflictMessage(
                for: state.rewriteHotkey,
                formatKey: "Content rewrite shortcut: %@",
                id: "conflict.rewrite",
                to: &messages
            )
        }
        if let customPasteHotkey = state.customPasteHotkey {
            appendConflictMessage(
                for: customPasteHotkey,
                formatKey: "Custom paste shortcut: %@",
                id: "conflict.customPaste",
                to: &messages
            )
        }

        appendEqualityMessage(
            state.transcriptionHotkey == state.translationHotkey,
            id: "duplicate.transcription.translation",
            textKey: "Transcription and translation shortcuts should be different.",
            to: &messages
        )
        if let meetingHotkey = state.meetingHotkey {
            appendEqualityMessage(
                state.transcriptionHotkey == meetingHotkey,
                id: "duplicate.transcription.meeting",
                textKey: "Transcription and meeting shortcuts should be different.",
                to: &messages
            )
            appendEqualityMessage(
                state.translationHotkey == meetingHotkey,
                id: "duplicate.translation.meeting",
                textKey: "Translation and meeting shortcuts should be different.",
                to: &messages
            )
            appendEqualityMessage(
                state.shouldValidateRewriteHotkey && state.rewriteHotkey == meetingHotkey,
                id: "duplicate.rewrite.meeting",
                textKey: "Content rewrite and meeting shortcuts should be different.",
                to: &messages
            )
        }
        appendEqualityMessage(
            state.shouldValidateRewriteHotkey && state.transcriptionHotkey == state.rewriteHotkey,
            id: "duplicate.transcription.rewrite",
            textKey: "Transcription and content rewrite shortcuts should be different.",
            to: &messages
        )
        appendEqualityMessage(
            state.shouldValidateRewriteHotkey && state.translationHotkey == state.rewriteHotkey,
            id: "duplicate.translation.rewrite",
            textKey: "Translation and content rewrite shortcuts should be different.",
            to: &messages
        )

        if let customPasteHotkey = state.customPasteHotkey {
            appendEqualityMessage(
                state.transcriptionHotkey == customPasteHotkey,
                id: "duplicate.transcription.customPaste",
                textKey: "Transcription and custom paste shortcuts should be different.",
                to: &messages
            )
            appendEqualityMessage(
                state.translationHotkey == customPasteHotkey,
                id: "duplicate.translation.customPaste",
                textKey: "Translation and custom paste shortcuts should be different.",
                to: &messages
            )
            if let meetingHotkey = state.meetingHotkey {
                appendEqualityMessage(
                    meetingHotkey == customPasteHotkey,
                    id: "duplicate.meeting.customPaste",
                    textKey: "Meeting and custom paste shortcuts should be different.",
                    to: &messages
                )
            }
            appendEqualityMessage(
                state.shouldValidateRewriteHotkey && state.rewriteHotkey == customPasteHotkey,
                id: "duplicate.rewrite.customPaste",
                textKey: "Content rewrite and custom paste shortcuts should be different.",
                to: &messages
            )
        }

        return messages
    }

    private static func appendConflictMessage(
        for hotkey: HotkeyPreference.Hotkey,
        formatKey: String,
        id: String,
        to messages: inout [Message]
    ) {
        guard let conflictMessage = conflictMessage(for: hotkey) else { return }
        messages.append(.init(id: id, text: AppLocalization.format(formatKey, conflictMessage)))
    }

    private static func appendEqualityMessage(
        _ condition: Bool,
        id: String,
        textKey: String,
        to messages: inout [Message]
    ) {
        guard condition else { return }
        messages.append(.init(id: id, text: AppLocalization.localizedString(textKey)))
    }

    private static func conflictMessage(
        for hotkey: HotkeyPreference.Hotkey
    ) -> String? {
        hotkeySettingsConflictRules.first {
            hotkey.keyCode == $0.keyCode && hotkey.modifiers == $0.modifiers
        }.map { AppLocalization.localizedString($0.messageKey) }
    }
}

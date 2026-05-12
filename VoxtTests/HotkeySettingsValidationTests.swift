import XCTest
import AppKit
import Carbon
@testable import Voxt

final class HotkeySettingsValidationTests: XCTestCase {
    func testDoubleTapWakeSuppressesRewriteSpecificMessages() {
        let transcriptionHotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.function],
            sidedModifiers: []
        )

        let messages = HotkeySettingsValidation.messages(
            for: .init(
                transcriptionHotkey: transcriptionHotkey,
                translationHotkey: HotkeyPreference.Hotkey(
                    keyCode: HotkeyPreference.modifierOnlyKeyCode,
                    modifiers: [.function, .shift],
                    sidedModifiers: []
                ),
                rewriteHotkey: transcriptionHotkey,
                shouldValidateRewriteHotkey: false,
                customPasteHotkey: nil
            )
        )

        XCTAssertFalse(messages.contains {
            $0.text == AppLocalization.localizedString(
                "Transcription and content rewrite shortcuts should be different."
            )
        })
        XCTAssertFalse(messages.contains {
            $0.id == "conflict.rewrite"
        })
    }

    func testDedicatedRewriteIncludesRewriteDuplicateMessage() {
        let transcriptionHotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.function],
            sidedModifiers: []
        )

        let messages = HotkeySettingsValidation.messages(
            for: .init(
                transcriptionHotkey: transcriptionHotkey,
                translationHotkey: HotkeyPreference.Hotkey(
                    keyCode: HotkeyPreference.modifierOnlyKeyCode,
                    modifiers: [.function, .shift],
                    sidedModifiers: []
                ),
                rewriteHotkey: transcriptionHotkey,
                shouldValidateRewriteHotkey: true,
                customPasteHotkey: nil
            )
        )

        XCTAssertTrue(messages.contains {
            $0.text == AppLocalization.localizedString(
                "Transcription and content rewrite shortcuts should be different."
            )
        })
    }

    func testConflictMessageIsReturnedForEnabledCustomPasteShortcut() {
        let customPasteHotkey = HotkeyPreference.Hotkey(
            keyCode: UInt16(kVK_ANSI_V),
            modifiers: [.command],
            sidedModifiers: []
        )

        let messages = HotkeySettingsValidation.messages(
            for: .init(
                transcriptionHotkey: HotkeyPreference.Hotkey(
                    keyCode: HotkeyPreference.modifierOnlyKeyCode,
                    modifiers: [.function],
                    sidedModifiers: []
                ),
                translationHotkey: HotkeyPreference.Hotkey(
                    keyCode: HotkeyPreference.modifierOnlyKeyCode,
                    modifiers: [.function, .shift],
                    sidedModifiers: []
                ),
                rewriteHotkey: HotkeyPreference.Hotkey(
                    keyCode: HotkeyPreference.modifierOnlyKeyCode,
                    modifiers: [.function, .control],
                    sidedModifiers: []
                ),
                shouldValidateRewriteHotkey: true,
                customPasteHotkey: customPasteHotkey
            )
        )

        XCTAssertTrue(messages.contains {
            $0.id == "conflict.customPaste" &&
            $0.text == AppLocalization.format(
                "Custom paste shortcut: %@",
                AppLocalization.localizedString("Conflicts with Paste (⌘V).")
            )
        })
    }
}

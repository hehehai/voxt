// HotkeyRuntimeConfiguration.swift
// Provides Hotkey Runtime Configuration for hotkey handling.

import AppKit
import ApplicationServices
import Foundation

struct HotkeyRuntimeConfiguration {
    let transcriptionHotkey: HotkeyPreference.Hotkey
    let translationHotkey: HotkeyPreference.Hotkey
    let rewriteHotkey: HotkeyPreference.Hotkey
    let meetingHotkey: HotkeyPreference.Hotkey?
    let customPasteHotkey: HotkeyPreference.Hotkey?
    let distinguishModifierSides: Bool
    let triggerMode: HotkeyPreference.TriggerMode
    let rewriteActivationMode: HotkeyPreference.RewriteActivationMode

    static func load(defaults: UserDefaults = .standard) -> HotkeyRuntimeConfiguration {
        let customPasteEnabled = defaults.bool(forKey: AppPreferenceKey.customPasteHotkeyEnabled)

        return HotkeyRuntimeConfiguration(
            transcriptionHotkey: HotkeyPreference.load(),
            translationHotkey: HotkeyPreference.loadTranslation(),
            rewriteHotkey: HotkeyPreference.loadRewrite(),
            meetingHotkey: HotkeyPreference.loadMeeting(),
            customPasteHotkey: customPasteEnabled ? HotkeyPreference.loadCustomPaste() : nil,
            distinguishModifierSides: HotkeyPreference.loadDistinguishModifierSides(),
            triggerMode: HotkeyPreference.loadTriggerMode(defaults: defaults),
            rewriteActivationMode: HotkeyPreference.loadRewriteActivationMode(defaults: defaults)
        )
    }

    var transcriptionFlags: CGEventFlags {
        HotkeyPreference.cgFlags(from: transcriptionHotkey.modifiers)
    }

    var translationFlags: CGEventFlags {
        HotkeyPreference.cgFlags(from: translationHotkey.modifiers)
    }

    var rewriteFlags: CGEventFlags {
        HotkeyPreference.cgFlags(from: rewriteHotkey.modifiers)
    }

    var meetingFlags: CGEventFlags {
        meetingHotkey.map { HotkeyPreference.cgFlags(from: $0.modifiers) } ?? []
    }

    var customPasteFlags: CGEventFlags {
        customPasteHotkey.map { HotkeyPreference.cgFlags(from: $0.modifiers) } ?? []
    }

    var debugBindingsDescription: String {
        let meetingDescription = meetingHotkey.map {
            HotkeyPreference.displayString(for: $0, distinguishModifierSides: distinguishModifierSides)
        } ?? "disabled"
        let customPasteDescription = customPasteHotkey.map {
            HotkeyPreference.displayString(for: $0, distinguishModifierSides: distinguishModifierSides)
        } ?? "disabled"

        return "Hotkey bindings. transcription=\(HotkeyPreference.displayString(for: transcriptionHotkey, distinguishModifierSides: distinguishModifierSides)), translation=\(HotkeyPreference.displayString(for: translationHotkey, distinguishModifierSides: distinguishModifierSides)), rewrite=\(HotkeyPreference.displayString(for: rewriteHotkey, distinguishModifierSides: distinguishModifierSides)), rewriteActivation=\(rewriteActivationMode.rawValue), meeting=\(meetingDescription), customPaste=\(customPasteDescription), trigger=\(triggerMode.rawValue)"
    }
}

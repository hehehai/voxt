import Foundation
import Carbon
import ApplicationServices

struct HotkeyModifierInterpreter {
    static func isModifierOnly(_ hotkey: HotkeyPreference.Hotkey) -> Bool {
        hotkey.keyCode == HotkeyPreference.modifierOnlyKeyCode
    }

    static func isFunctionKeyEvent(_ keyCode: UInt16) -> Bool {
        keyCode == UInt16(kVK_Function)
    }

    static func translationTriggerDown(
        keyCode: UInt16,
        flags: CGEventFlags,
        translationFlags: CGEventFlags
    ) -> Bool {
        let comboIsDown = flags.contains(translationFlags)
        let isFnOnlyHotkey = translationFlags == .maskSecondaryFn
        let fnPressedForModifierHotkey = isFnOnlyHotkey && isFunctionKeyEvent(keyCode)
        return comboIsDown || fnPressedForModifierHotkey
    }

    static func transcriptionTriggerDown(
        keyCode: UInt16,
        flags: CGEventFlags,
        transcriptionFlags: CGEventFlags
    ) -> Bool {
        let comboIsDown = flags.contains(transcriptionFlags)
        let isFnOnlyHotkey = transcriptionFlags == .maskSecondaryFn
        // For fn-only hotkey, some keyboards report keyCode=Function with flags jitter.
        let fnPressedForModifierHotkey = isFnOnlyHotkey && isFunctionKeyEvent(keyCode)
        return comboIsDown || fnPressedForModifierHotkey
    }

    static func shouldDelayTranscriptionTap(
        transcriptionHotkey: HotkeyPreference.Hotkey,
        translationHotkey: HotkeyPreference.Hotkey,
        transcriptionFlags: CGEventFlags,
        translationFlags: CGEventFlags
    ) -> Bool {
        // Only needed for overlap such as transcription=fn and translation=fn+shift.
        guard isModifierOnly(transcriptionHotkey) else { return false }
        guard isModifierOnly(translationHotkey) else { return false }
        guard transcriptionFlags != translationFlags else { return false }
        return translationFlags.contains(transcriptionFlags)
    }
}

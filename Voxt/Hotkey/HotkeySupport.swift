import AppKit
import Carbon
import SwiftUI
import IOKit.hidsystem

struct SidedModifierFlags: OptionSet, Equatable {
    let rawValue: Int

    static let leftShift = SidedModifierFlags(rawValue: 1 << 0)
    static let rightShift = SidedModifierFlags(rawValue: 1 << 1)
    static let leftControl = SidedModifierFlags(rawValue: 1 << 2)
    static let rightControl = SidedModifierFlags(rawValue: 1 << 3)
    static let leftOption = SidedModifierFlags(rawValue: 1 << 4)
    static let rightOption = SidedModifierFlags(rawValue: 1 << 5)
    static let leftCommand = SidedModifierFlags(rawValue: 1 << 6)
    static let rightCommand = SidedModifierFlags(rawValue: 1 << 7)

    static let allShift: SidedModifierFlags = [.leftShift, .rightShift]
    static let allControl: SidedModifierFlags = [.leftControl, .rightControl]
    static let allOption: SidedModifierFlags = [.leftOption, .rightOption]
    static let allCommand: SidedModifierFlags = [.leftCommand, .rightCommand]

    static func toggled(from current: SidedModifierFlags, keyCode: UInt16) -> SidedModifierFlags {
        guard let flag = sidedFlag(for: keyCode) else { return current }
        if current.contains(flag) {
            return current.subtracting(flag)
        }
        return current.union(flag)
    }

    static func updating(from current: SidedModifierFlags, keyCode: UInt16, isPressed: Bool) -> SidedModifierFlags {
        guard let flag = sidedFlag(for: keyCode) else { return current }
        if isPressed {
            return current.union(flag)
        }
        return current.subtracting(flag)
    }

    func filtered(by modifiers: NSEvent.ModifierFlags) -> SidedModifierFlags {
        var filtered: SidedModifierFlags = []
        if modifiers.contains(.shift) {
            filtered.formUnion(intersection(.allShift))
        }
        if modifiers.contains(.control) {
            filtered.formUnion(intersection(.allControl))
        }
        if modifiers.contains(.option) {
            filtered.formUnion(intersection(.allOption))
        }
        if modifiers.contains(.command) {
            filtered.formUnion(intersection(.allCommand))
        }
        return filtered
    }

    func matches(requiredModifiers modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers.contains(.shift), isDisjoint(with: .allShift) { return false }
        if modifiers.contains(.control), isDisjoint(with: .allControl) { return false }
        if modifiers.contains(.option), isDisjoint(with: .allOption) { return false }
        if modifiers.contains(.command), isDisjoint(with: .allCommand) { return false }
        return true
    }

    static func sidedFlag(for keyCode: UInt16) -> SidedModifierFlags? {
        switch Int(keyCode) {
        case kVK_Shift:
            return .leftShift
        case kVK_RightShift:
            return .rightShift
        case kVK_Control:
            return .leftControl
        case kVK_RightControl:
            return .rightControl
        case kVK_Option:
            return .leftOption
        case kVK_RightOption:
            return .rightOption
        case kVK_Command:
            return .leftCommand
        case kVK_RightCommand:
            return .rightCommand
        default:
            return nil
        }
    }

    static func fromModifierKeyCode(_ keyCode: UInt16) -> (modifiers: NSEvent.ModifierFlags, sided: SidedModifierFlags)? {
        switch Int(keyCode) {
        case kVK_Shift:
            return ([.shift], .leftShift)
        case kVK_RightShift:
            return ([.shift], .rightShift)
        case kVK_Control:
            return ([.control], .leftControl)
        case kVK_RightControl:
            return ([.control], .rightControl)
        case kVK_Option:
            return ([.option], .leftOption)
        case kVK_RightOption:
            return ([.option], .rightOption)
        case kVK_Command:
            return ([.command], .leftCommand)
        case kVK_RightCommand:
            return ([.command], .rightCommand)
        case kVK_Function:
            return ([.function], [])
        default:
            return nil
        }
    }

    static func from(eventFlags: CGEventFlags) -> SidedModifierFlags {
        let raw = eventFlags.rawValue
        var sided: SidedModifierFlags = []

        if raw & UInt64(NX_DEVICELSHIFTKEYMASK) != 0 { sided.insert(.leftShift) }
        if raw & UInt64(NX_DEVICERSHIFTKEYMASK) != 0 { sided.insert(.rightShift) }
        if raw & UInt64(NX_DEVICELCTLKEYMASK) != 0 { sided.insert(.leftControl) }
        if raw & UInt64(NX_DEVICERCTLKEYMASK) != 0 { sided.insert(.rightControl) }
        if raw & UInt64(NX_DEVICELALTKEYMASK) != 0 { sided.insert(.leftOption) }
        if raw & UInt64(NX_DEVICERALTKEYMASK) != 0 { sided.insert(.rightOption) }
        if raw & UInt64(NX_DEVICELCMDKEYMASK) != 0 { sided.insert(.leftCommand) }
        if raw & UInt64(NX_DEVICERCMDKEYMASK) != 0 { sided.insert(.rightCommand) }

        return sided
    }

    static func snapshotFromCurrentKeyState(filteredBy modifiers: NSEvent.ModifierFlags) -> SidedModifierFlags {
        var sided: SidedModifierFlags = []

        let keyCodes: [(UInt16, SidedModifierFlags)] = [
            (UInt16(kVK_Shift), .leftShift),
            (UInt16(kVK_RightShift), .rightShift),
            (UInt16(kVK_Control), .leftControl),
            (UInt16(kVK_RightControl), .rightControl),
            (UInt16(kVK_Option), .leftOption),
            (UInt16(kVK_RightOption), .rightOption),
            (UInt16(kVK_Command), .leftCommand),
            (UInt16(kVK_RightCommand), .rightCommand)
        ]

        for (keyCode, flag) in keyCodes {
            if CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode)) {
                sided.insert(flag)
            }
        }

        return sided.filtered(by: modifiers)
    }
}

struct HotkeyPreference {
    enum TriggerMode: String, CaseIterable, Identifiable {
        case longPress
        case tap

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .longPress: return "Long Press (Release to End)"
            case .tap: return "Tap (Press to Toggle)"
            }
        }

        var title: String {
            switch self {
            case .longPress: return AppLocalization.localizedString("Long Press (Release to End)")
            case .tap: return AppLocalization.localizedString("Tap (Press to Toggle)")
            }
        }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case fnCombo
        case commandCombo
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fnCombo:
                return AppLocalization.localizedString("fn Combo")
            case .commandCombo:
                return AppLocalization.localizedString("Command Combo")
            case .custom:
                return AppLocalization.localizedString("Custom")
            }
        }
    }

    struct Hotkey: Equatable {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let sidedModifiers: SidedModifierFlags
    }

    static let modifierOnlyKeyCode: UInt16 = 0xFFFF
    static let defaultKeyCode: UInt16 = modifierOnlyKeyCode
    static let defaultModifiers: NSEvent.ModifierFlags = [.function]
    static let defaultTranslationKeyCode: UInt16 = modifierOnlyKeyCode
    static let defaultTranslationModifiers: NSEvent.ModifierFlags = [.function, .shift]
    static let defaultRewriteKeyCode: UInt16 = modifierOnlyKeyCode
    static let defaultRewriteModifiers: NSEvent.ModifierFlags = [.function, .control]
    static let defaultMeetingKeyCode: UInt16 = modifierOnlyKeyCode
    static let defaultMeetingModifiers: NSEvent.ModifierFlags = [.function, .option]
    static let defaultTriggerMode: TriggerMode = .tap
    static let defaultDistinguishModifierSides = false
    static let defaultPreset: Preset = .fnCombo

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            AppPreferenceKey.hotkeyKeyCode: Int(defaultKeyCode),
            AppPreferenceKey.hotkeyModifiers: Int(defaultModifiers.rawValue),
            AppPreferenceKey.hotkeySidedModifiers: 0,
            AppPreferenceKey.translationHotkeyKeyCode: Int(defaultTranslationKeyCode),
            AppPreferenceKey.translationHotkeyModifiers: Int(defaultTranslationModifiers.rawValue),
            AppPreferenceKey.translationHotkeySidedModifiers: 0,
            AppPreferenceKey.rewriteHotkeyKeyCode: Int(defaultRewriteKeyCode),
            AppPreferenceKey.rewriteHotkeyModifiers: Int(defaultRewriteModifiers.rawValue),
            AppPreferenceKey.rewriteHotkeySidedModifiers: 0,
            AppPreferenceKey.meetingHotkeyKeyCode: Int(defaultMeetingKeyCode),
            AppPreferenceKey.meetingHotkeyModifiers: Int(defaultMeetingModifiers.rawValue),
            AppPreferenceKey.meetingHotkeySidedModifiers: 0,
            AppPreferenceKey.hotkeyTriggerMode: defaultTriggerMode.rawValue,
            AppPreferenceKey.hotkeyDistinguishModifierSides: defaultDistinguishModifierSides,
            AppPreferenceKey.hotkeyPreset: defaultPreset.rawValue
        ])
    }

    static func migrateDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let keyCodeValue = defaults.object(forKey: AppPreferenceKey.hotkeyKeyCode) as? Int,
              let modifiersValue = defaults.object(forKey: AppPreferenceKey.hotkeyModifiers) as? Int
        else {
            return
        }

        let keyCode = UInt16(keyCodeValue)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersValue)).intersection(.hotkeyRelevant)

        if keyCode == modifierOnlyKeyCode && modifiers == [.control, .option] {
            save(keyCode: defaultKeyCode, modifiers: defaultModifiers, sidedModifiers: [])
        }
    }

    static func load() -> Hotkey {
        load(
            keyCodeKey: AppPreferenceKey.hotkeyKeyCode,
            modifiersKey: AppPreferenceKey.hotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.hotkeySidedModifiers,
            defaultKeyCode: defaultKeyCode,
            defaultModifiers: defaultModifiers
        )
    }

    static func save(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sidedModifiers: SidedModifierFlags) {
        UserDefaults.standard.set(Int(keyCode), forKey: AppPreferenceKey.hotkeyKeyCode)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: AppPreferenceKey.hotkeyModifiers)
        UserDefaults.standard.set(sidedModifiers.rawValue, forKey: AppPreferenceKey.hotkeySidedModifiers)
    }

    static func loadTranslation() -> Hotkey {
        load(
            keyCodeKey: AppPreferenceKey.translationHotkeyKeyCode,
            modifiersKey: AppPreferenceKey.translationHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.translationHotkeySidedModifiers,
            defaultKeyCode: defaultTranslationKeyCode,
            defaultModifiers: defaultTranslationModifiers
        )
    }

    static func saveTranslation(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sidedModifiers: SidedModifierFlags) {
        UserDefaults.standard.set(Int(keyCode), forKey: AppPreferenceKey.translationHotkeyKeyCode)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: AppPreferenceKey.translationHotkeyModifiers)
        UserDefaults.standard.set(sidedModifiers.rawValue, forKey: AppPreferenceKey.translationHotkeySidedModifiers)
    }

    static func loadRewrite() -> Hotkey {
        load(
            keyCodeKey: AppPreferenceKey.rewriteHotkeyKeyCode,
            modifiersKey: AppPreferenceKey.rewriteHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.rewriteHotkeySidedModifiers,
            defaultKeyCode: defaultRewriteKeyCode,
            defaultModifiers: defaultRewriteModifiers
        )
    }

    static func saveRewrite(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sidedModifiers: SidedModifierFlags) {
        UserDefaults.standard.set(Int(keyCode), forKey: AppPreferenceKey.rewriteHotkeyKeyCode)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: AppPreferenceKey.rewriteHotkeyModifiers)
        UserDefaults.standard.set(sidedModifiers.rawValue, forKey: AppPreferenceKey.rewriteHotkeySidedModifiers)
    }

    static func loadMeeting() -> Hotkey {
        load(
            keyCodeKey: AppPreferenceKey.meetingHotkeyKeyCode,
            modifiersKey: AppPreferenceKey.meetingHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.meetingHotkeySidedModifiers,
            defaultKeyCode: defaultMeetingKeyCode,
            defaultModifiers: defaultMeetingModifiers
        )
    }

    static func saveMeeting(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sidedModifiers: SidedModifierFlags) {
        UserDefaults.standard.set(Int(keyCode), forKey: AppPreferenceKey.meetingHotkeyKeyCode)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: AppPreferenceKey.meetingHotkeyModifiers)
        UserDefaults.standard.set(sidedModifiers.rawValue, forKey: AppPreferenceKey.meetingHotkeySidedModifiers)
    }

    static func loadTriggerMode() -> TriggerMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.hotkeyTriggerMode)
        return TriggerMode(rawValue: raw ?? "") ?? defaultTriggerMode
    }

    static func saveTriggerMode(_ mode: TriggerMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: AppPreferenceKey.hotkeyTriggerMode)
    }

    static func loadDistinguishModifierSides() -> Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKey.hotkeyDistinguishModifierSides) as? Bool ?? defaultDistinguishModifierSides
    }

    static func loadPreset() -> Preset {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.hotkeyPreset)
        return Preset(rawValue: raw ?? "") ?? defaultPreset
    }

    static func displayString(for hotkey: Hotkey, distinguishModifierSides: Bool) -> String {
        let symbols = modifierSymbols(
            for: hotkey.modifiers,
            sidedModifiers: distinguishModifierSides ? hotkey.sidedModifiers : []
        )
        if hotkey.keyCode == modifierOnlyKeyCode {
            return symbols.isEmpty ? "Unassigned" : symbols
        }
        let key = keyCodeDisplayString(hotkey.keyCode)
        return symbols.isEmpty ? key : "\(symbols) \(key)"
    }

    static func modifierSymbols(
        for modifiers: NSEvent.ModifierFlags,
        sidedModifiers: SidedModifierFlags = []
    ) -> String {
        let usesSides = !sidedModifiers.isEmpty
        var parts: [String] = []
        if modifiers.contains(.control) {
            parts.append(usesSides ? sidedModifierLabel(primary: .leftControl, secondary: .rightControl, sidedModifiers: sidedModifiers, fallback: "Control") : "⌃")
        }
        if modifiers.contains(.option) {
            parts.append(usesSides ? sidedModifierLabel(primary: .leftOption, secondary: .rightOption, sidedModifiers: sidedModifiers, fallback: "Option") : "⌥")
        }
        if modifiers.contains(.shift) {
            parts.append(usesSides ? sidedModifierLabel(primary: .leftShift, secondary: .rightShift, sidedModifiers: sidedModifiers, fallback: "Shift") : "⇧")
        }
        if modifiers.contains(.command) {
            parts.append(usesSides ? sidedModifierLabel(primary: .leftCommand, secondary: .rightCommand, sidedModifiers: sidedModifiers, fallback: "Command") : "⌘")
        }
        if modifiers.contains(.function) {
            parts.append("fn")
        }
        return parts.joined(separator: usesSides ? " + " : "")
    }

    static func presetHotkeys(for preset: Preset) -> (distinguishSides: Bool, transcription: Hotkey, translation: Hotkey, rewrite: Hotkey, meeting: Hotkey)? {
        switch preset {
        case .fnCombo:
            return (
                false,
                Hotkey(keyCode: defaultKeyCode, modifiers: defaultModifiers, sidedModifiers: []),
                Hotkey(keyCode: defaultTranslationKeyCode, modifiers: defaultTranslationModifiers, sidedModifiers: []),
                Hotkey(keyCode: defaultRewriteKeyCode, modifiers: defaultRewriteModifiers, sidedModifiers: []),
                Hotkey(keyCode: defaultMeetingKeyCode, modifiers: defaultMeetingModifiers, sidedModifiers: [])
            )
        case .commandCombo:
            return (
                true,
                Hotkey(keyCode: modifierOnlyKeyCode, modifiers: [.command], sidedModifiers: [.rightCommand]),
                Hotkey(keyCode: modifierOnlyKeyCode, modifiers: [.command, .shift], sidedModifiers: [.rightCommand, .rightShift]),
                Hotkey(keyCode: modifierOnlyKeyCode, modifiers: [.command, .option], sidedModifiers: [.rightCommand, .rightOption]),
                Hotkey(keyCode: UInt16(kVK_ANSI_L), modifiers: [.command], sidedModifiers: [.rightCommand])
            )
        case .custom:
            return nil
        }
    }

    static func hotkeyMatches(
        _ hotkey: Hotkey,
        eventFlags: CGEventFlags,
        sidedModifiers: SidedModifierFlags,
        distinguishModifierSides: Bool
    ) -> Bool {
        let requiredFlags = cgFlags(from: hotkey.modifiers)
        guard eventFlags.contains(requiredFlags) else { return false }
        guard distinguishModifierSides, !hotkey.sidedModifiers.isEmpty else { return true }
        return sidedModifiers.isSuperset(of: hotkey.sidedModifiers) && hotkey.sidedModifiers.matches(requiredModifiers: hotkey.modifiers)
    }

    static func cgFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    static func keyCodeDisplayString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_Tab: return "Tab"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            break
        }

        if let translated = translateKeyCode(keyCode), !translated.isEmpty {
            return translated.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static func load(
        keyCodeKey: String,
        modifiersKey: String,
        sidedModifiersKey: String,
        defaultKeyCode: UInt16,
        defaultModifiers: NSEvent.ModifierFlags
    ) -> Hotkey {
        let defaults = UserDefaults.standard
        let keyCodeValue = defaults.object(forKey: keyCodeKey) as? Int
        let modifiersValue = defaults.object(forKey: modifiersKey) as? Int
        let sidedValue = defaults.object(forKey: sidedModifiersKey) as? Int ?? 0

        let keyCode = UInt16(keyCodeValue ?? Int(defaultKeyCode))
        let modifiersRaw = modifiersValue ?? Int(defaultModifiers.rawValue)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw)).intersection(.hotkeyRelevant)
        let sidedModifiers = SidedModifierFlags(rawValue: sidedValue).filtered(by: modifiers)

        return Hotkey(keyCode: keyCode, modifiers: modifiers, sidedModifiers: sidedModifiers)
    }

    private static func sidedModifierLabel(
        primary: SidedModifierFlags,
        secondary: SidedModifierFlags,
        sidedModifiers: SidedModifierFlags,
        fallback: String
    ) -> String {
        if sidedModifiers.contains(primary), sidedModifiers.contains(secondary) {
            return localizedModifierName(fallback)
        }
        if sidedModifiers.contains(primary) { return AppLocalization.format("Left %@", localizedModifierName(fallback)) }
        if sidedModifiers.contains(secondary) { return AppLocalization.format("Right %@", localizedModifierName(fallback)) }
        return localizedModifierName(fallback)
    }

    private static func localizedModifierName(_ fallback: String) -> String {
        AppLocalization.localizedString(fallback)
    }

    private static func translateKeyCode(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let data = unsafeBitCast(layoutData, to: CFData.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status: OSStatus = (data as Data).withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(kUCKeyTranslateNoDeadKeysBit)
            }

            return UCKeyTranslate(
                base,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

extension NSEvent.ModifierFlags {
    static let hotkeyRelevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
}

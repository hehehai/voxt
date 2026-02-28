import AppKit
import Carbon

struct HotkeyPreference {
    enum TriggerMode: String, CaseIterable, Identifiable {
        case longPress
        case tap

        var id: String { rawValue }

        var title: String {
            switch self {
            case .longPress: return "Long Press (Release to End)"
            case .tap: return "Tap (Press to Toggle)"
            }
        }
    }

    struct Hotkey: Equatable {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
    }

    static let modifierOnlyKeyCode: UInt16 = 0xFFFF
    static let defaultKeyCode: UInt16 = modifierOnlyKeyCode
    static let defaultModifiers: NSEvent.ModifierFlags = [.function]
    static let defaultTranslationKeyCode: UInt16 = modifierOnlyKeyCode
    static let defaultTranslationModifiers: NSEvent.ModifierFlags = [.function, .shift]
    static let defaultTriggerMode: TriggerMode = .longPress

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            AppPreferenceKey.hotkeyKeyCode: Int(defaultKeyCode),
            AppPreferenceKey.hotkeyModifiers: Int(defaultModifiers.rawValue),
            AppPreferenceKey.translationHotkeyKeyCode: Int(defaultTranslationKeyCode),
            AppPreferenceKey.translationHotkeyModifiers: Int(defaultTranslationModifiers.rawValue),
            AppPreferenceKey.hotkeyTriggerMode: defaultTriggerMode.rawValue
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
            save(keyCode: defaultKeyCode, modifiers: defaultModifiers)
        }
    }

    static func load() -> Hotkey {
        let defaults = UserDefaults.standard
        let keyCodeValue = defaults.object(forKey: AppPreferenceKey.hotkeyKeyCode) as? Int
        let modifiersValue = defaults.object(forKey: AppPreferenceKey.hotkeyModifiers) as? Int

        let keyCode = UInt16(keyCodeValue ?? Int(defaultKeyCode))
        let modifiersRaw = modifiersValue ?? Int(defaultModifiers.rawValue)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw)).intersection(.hotkeyRelevant)

        return Hotkey(keyCode: keyCode, modifiers: modifiers)
    }

    static func save(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(Int(keyCode), forKey: AppPreferenceKey.hotkeyKeyCode)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: AppPreferenceKey.hotkeyModifiers)
    }

    static func loadTranslation() -> Hotkey {
        let defaults = UserDefaults.standard
        let keyCodeValue = defaults.object(forKey: AppPreferenceKey.translationHotkeyKeyCode) as? Int
        let modifiersValue = defaults.object(forKey: AppPreferenceKey.translationHotkeyModifiers) as? Int

        let keyCode = UInt16(keyCodeValue ?? Int(defaultTranslationKeyCode))
        let modifiersRaw = modifiersValue ?? Int(defaultTranslationModifiers.rawValue)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw)).intersection(.hotkeyRelevant)

        return Hotkey(keyCode: keyCode, modifiers: modifiers)
    }

    static func saveTranslation(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(Int(keyCode), forKey: AppPreferenceKey.translationHotkeyKeyCode)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: AppPreferenceKey.translationHotkeyModifiers)
    }

    static func loadTriggerMode() -> TriggerMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.hotkeyTriggerMode)
        return TriggerMode(rawValue: raw ?? "") ?? defaultTriggerMode
    }

    static func saveTriggerMode(_ mode: TriggerMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: AppPreferenceKey.hotkeyTriggerMode)
    }

    static func displayString(for hotkey: Hotkey) -> String {
        let symbols = modifierSymbols(for: hotkey.modifiers)
        if hotkey.keyCode == modifierOnlyKeyCode {
            return symbols.isEmpty ? "Unassigned" : symbols
        }
        let key = keyCodeDisplayString(hotkey.keyCode)
        return symbols + key
    }

    static func modifierSymbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        if modifiers.contains(.function) { text += "fn" }
        return text
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

// HotkeySupport.swift
// Provides Hotkey Support for hotkey handling.

import AppKit
import Carbon
import SwiftUI
import IOKit.hidsystem

nonisolated struct SidedModifierFlags: OptionSet, Equatable {
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

nonisolated struct HotkeyPreference {
    enum TriggerBehavior: String, CaseIterable, Identifiable, Codable {
        case tap
        case longPress
        case doubleTap

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tap:
                return AppLocalization.localizedString("Tap")
            case .longPress:
                return AppLocalization.localizedString("Long Press")
            case .doubleTap:
                return AppLocalization.localizedString("Double Tap")
            }
        }

        var legacyTriggerMode: TriggerMode {
            switch self {
            case .longPress:
                return .longPress
            case .tap, .doubleTap:
                return .tap
            }
        }

        init(_ triggerMode: TriggerMode) {
            switch triggerMode {
            case .longPress:
                self = .longPress
            case .tap:
                self = .tap
            }
        }
    }

    struct HotkeyBinding: Identifiable, Equatable, Codable {
        let id: UUID
        var hotkey: Hotkey
        var behavior: TriggerBehavior

        init(
            id: UUID = UUID(),
            hotkey: Hotkey,
            behavior: TriggerBehavior
        ) {
            self.id = id
            self.hotkey = hotkey
            self.behavior = behavior
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case inputType
            case keyCode
            case mouseButtonNumber
            case modifiers
            case sidedModifiers
            case behavior
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            behavior = try container.decodeIfPresent(TriggerBehavior.self, forKey: .behavior) ?? .tap

            let inputType = try container.decodeIfPresent(String.self, forKey: .inputType)
            let keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode) ?? HotkeyPreference.modifierOnlyKeyCode
            let mouseButtonNumber = try container.decodeIfPresent(Int.self, forKey: .mouseButtonNumber)
            let input: Hotkey.Input
            if Hotkey.Input.Kind(rawValue: inputType ?? "") == .mouseButton,
               let mouseButtonNumber,
               mouseButtonNumber >= HotkeyPreference.middleMouseButtonNumber {
                input = .mouseButton(mouseButtonNumber)
            } else {
                input = .keyboard(keyCode)
            }

            let modifiersRaw = try container.decodeIfPresent(UInt.self, forKey: .modifiers) ?? 0
            let modifiers = NSEvent.ModifierFlags(rawValue: modifiersRaw).intersection(.hotkeyRelevant)
            let sidedRaw = try container.decodeIfPresent(Int.self, forKey: .sidedModifiers) ?? 0
            hotkey = HotkeyPreference.canonicalHotkey(
                input: input,
                modifiers: modifiers,
                sidedModifiers: SidedModifierFlags(rawValue: sidedRaw).filtered(by: modifiers)
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(hotkey.input.kind.rawValue, forKey: .inputType)
            switch hotkey.input {
            case .keyboard(let keyCode):
                try container.encode(keyCode, forKey: .keyCode)
            case .mouseButton(let buttonNumber):
                try container.encode(buttonNumber, forKey: .mouseButtonNumber)
            }
            try container.encode(hotkey.modifiers.rawValue, forKey: .modifiers)
            try container.encode(hotkey.sidedModifiers.filtered(by: hotkey.modifiers).rawValue, forKey: .sidedModifiers)
            try container.encode(behavior, forKey: .behavior)
        }
    }

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

    enum RewriteActivationMode: String, CaseIterable, Identifiable {
        case dedicatedHotkey
        case doubleTapTranscriptionHotkey

        var id: String { rawValue }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case fnCombo
        case commandCombo
        case mouseMiddleFnShift
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fnCombo:
                return AppLocalization.localizedString("fn Combo")
            case .commandCombo:
                return AppLocalization.localizedString("Command Combo")
            case .mouseMiddleFnShift:
                return AppLocalization.localizedString("Mouse Middle + fn Shift")
            case .custom:
                return AppLocalization.localizedString("Custom")
            }
        }
    }

    struct Hotkey: Equatable, Codable {
        enum Input: Equatable {
            case keyboard(UInt16)
            case mouseButton(Int)

            enum Kind: String {
                case keyboard
                case mouseButton
            }

            var kind: Kind {
                switch self {
                case .keyboard:
                    return .keyboard
                case .mouseButton:
                    return .mouseButton
                }
            }
        }

        let input: Input
        let modifiers: NSEvent.ModifierFlags
        let sidedModifiers: SidedModifierFlags

        private enum CodingKeys: String, CodingKey {
            case inputType
            case keyCode
            case mouseButtonNumber
            case modifiers
            case sidedModifiers
        }

        init(
            input: Input,
            modifiers: NSEvent.ModifierFlags,
            sidedModifiers: SidedModifierFlags
        ) {
            self.input = input
            self.modifiers = modifiers
            self.sidedModifiers = sidedModifiers
        }

        init(
            keyCode: UInt16,
            modifiers: NSEvent.ModifierFlags,
            sidedModifiers: SidedModifierFlags
        ) {
            self.init(input: .keyboard(keyCode), modifiers: modifiers, sidedModifiers: sidedModifiers)
        }

        init(
            mouseButtonNumber: Int,
            modifiers: NSEvent.ModifierFlags = [],
            sidedModifiers: SidedModifierFlags = []
        ) {
            self.init(input: .mouseButton(mouseButtonNumber), modifiers: modifiers, sidedModifiers: sidedModifiers)
        }

        var keyCode: UInt16 {
            switch input {
            case .keyboard(let keyCode):
                return keyCode
            case .mouseButton:
                return HotkeyPreference.modifierOnlyKeyCode
            }
        }

        var mouseButtonNumber: Int? {
            switch input {
            case .keyboard:
                return nil
            case .mouseButton(let buttonNumber):
                return buttonNumber
            }
        }

        var isMouseButton: Bool {
            mouseButtonNumber != nil
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let inputType = try container.decodeIfPresent(String.self, forKey: .inputType)
            let keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode) ?? HotkeyPreference.modifierOnlyKeyCode
            let mouseButtonNumber = try container.decodeIfPresent(Int.self, forKey: .mouseButtonNumber)
            if Input.Kind(rawValue: inputType ?? "") == .mouseButton,
               let mouseButtonNumber,
               mouseButtonNumber >= HotkeyPreference.middleMouseButtonNumber {
                input = .mouseButton(mouseButtonNumber)
            } else {
                input = .keyboard(keyCode)
            }
            let modifiersRaw = try container.decodeIfPresent(UInt.self, forKey: .modifiers) ?? 0
            modifiers = NSEvent.ModifierFlags(rawValue: modifiersRaw).intersection(.hotkeyRelevant)
            let sidedRaw = try container.decodeIfPresent(Int.self, forKey: .sidedModifiers) ?? 0
            sidedModifiers = SidedModifierFlags(rawValue: sidedRaw).filtered(by: modifiers)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(input.kind.rawValue, forKey: .inputType)
            switch input {
            case .keyboard(let keyCode):
                try container.encode(keyCode, forKey: .keyCode)
            case .mouseButton(let buttonNumber):
                try container.encode(buttonNumber, forKey: .mouseButtonNumber)
            }
            try container.encode(modifiers.rawValue, forKey: .modifiers)
            try container.encode(sidedModifiers.filtered(by: modifiers).rawValue, forKey: .sidedModifiers)
        }
    }

    struct PresetHotkeys: Equatable {
        let distinguishSides: Bool
        let transcription: Hotkey
        let translation: Hotkey
        let rewrite: Hotkey
        let meeting: Hotkey
        let customPaste: Hotkey
        let triggerMode: TriggerMode
        let rewriteActivationMode: RewriteActivationMode

        var transcriptionBindings: [HotkeyBinding] {
            [.init(id: Self.transcriptionBindingID, hotkey: transcription, behavior: TriggerBehavior(triggerMode))]
        }

        var translationBindings: [HotkeyBinding] {
            [.init(id: Self.translationBindingID, hotkey: translation, behavior: TriggerBehavior(triggerMode))]
        }

        var rewriteBindings: [HotkeyBinding] {
            let behavior: TriggerBehavior = rewriteActivationMode == .doubleTapTranscriptionHotkey
                ? .doubleTap
                : TriggerBehavior(triggerMode)
            return [.init(id: Self.rewriteBindingID, hotkey: rewrite, behavior: behavior)]
        }

        var meetingBindings: [HotkeyBinding] {
            [.init(id: Self.meetingBindingID, hotkey: meeting, behavior: TriggerBehavior(triggerMode))]
        }

        private static let transcriptionBindingID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        private static let translationBindingID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        private static let rewriteBindingID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        private static let meetingBindingID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!

        init(
            distinguishSides: Bool,
            transcription: Hotkey,
            translation: Hotkey,
            rewrite: Hotkey,
            meeting: Hotkey,
            customPaste: Hotkey,
            triggerMode: TriggerMode = .tap,
            rewriteActivationMode: RewriteActivationMode = .dedicatedHotkey
        ) {
            self.distinguishSides = distinguishSides
            self.transcription = transcription
            self.translation = translation
            self.rewrite = rewrite
            self.meeting = meeting
            self.customPaste = customPaste
            self.triggerMode = triggerMode
            self.rewriteActivationMode = rewriteActivationMode
        }
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
    static let defaultCustomPasteKeyCode: UInt16 = UInt16(kVK_ANSI_V)
    static let defaultCustomPasteModifiers: NSEvent.ModifierFlags = [.control, .command]
    static let defaultTriggerMode: TriggerMode = .tap
    static let defaultRewriteActivationMode: RewriteActivationMode = .dedicatedHotkey
    static let defaultDistinguishModifierSides = true
    static let defaultPreset: Preset = .fnCombo
    static let middleMouseButtonNumber = 2

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            AppPreferenceKey.hotkeyInputType: Hotkey.Input.Kind.keyboard.rawValue,
            AppPreferenceKey.hotkeyKeyCode: Int(defaultKeyCode),
            AppPreferenceKey.hotkeyMouseButtonNumber: middleMouseButtonNumber,
            AppPreferenceKey.hotkeyModifiers: Int(defaultModifiers.rawValue),
            AppPreferenceKey.hotkeySidedModifiers: 0,
            AppPreferenceKey.translationHotkeyInputType: Hotkey.Input.Kind.keyboard.rawValue,
            AppPreferenceKey.translationHotkeyKeyCode: Int(defaultTranslationKeyCode),
            AppPreferenceKey.translationHotkeyMouseButtonNumber: middleMouseButtonNumber,
            AppPreferenceKey.translationHotkeyModifiers: Int(defaultTranslationModifiers.rawValue),
            AppPreferenceKey.translationHotkeySidedModifiers: 0,
            AppPreferenceKey.rewriteHotkeyInputType: Hotkey.Input.Kind.keyboard.rawValue,
            AppPreferenceKey.rewriteHotkeyKeyCode: Int(defaultRewriteKeyCode),
            AppPreferenceKey.rewriteHotkeyMouseButtonNumber: middleMouseButtonNumber,
            AppPreferenceKey.rewriteHotkeyModifiers: Int(defaultRewriteModifiers.rawValue),
            AppPreferenceKey.rewriteHotkeySidedModifiers: 0,
            AppPreferenceKey.meetingHotkeyInputType: Hotkey.Input.Kind.keyboard.rawValue,
            AppPreferenceKey.meetingHotkeyKeyCode: Int(defaultMeetingKeyCode),
            AppPreferenceKey.meetingHotkeyMouseButtonNumber: middleMouseButtonNumber,
            AppPreferenceKey.meetingHotkeyModifiers: Int(defaultMeetingModifiers.rawValue),
            AppPreferenceKey.meetingHotkeySidedModifiers: 0,
            AppPreferenceKey.customPasteHotkeyInputType: Hotkey.Input.Kind.keyboard.rawValue,
            AppPreferenceKey.customPasteHotkeyKeyCode: Int(defaultCustomPasteKeyCode),
            AppPreferenceKey.customPasteHotkeyMouseButtonNumber: middleMouseButtonNumber,
            AppPreferenceKey.customPasteHotkeyModifiers: Int(defaultCustomPasteModifiers.rawValue),
            AppPreferenceKey.customPasteHotkeySidedModifiers: 0,
            AppPreferenceKey.hotkeyTriggerMode: defaultTriggerMode.rawValue,
            AppPreferenceKey.rewriteHotkeyActivationMode: defaultRewriteActivationMode.rawValue,
            AppPreferenceKey.hotkeyDistinguishModifierSides: defaultDistinguishModifierSides,
            AppPreferenceKey.hotkeyPreset: defaultPreset.rawValue,
            AppPreferenceKey.hotkeyCaptureInProgress: false,
        ])
        migrateHotkeyBindingsIfNeeded()
    }

    static func migrateDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let keyCodeValue = defaults.object(forKey: AppPreferenceKey.hotkeyKeyCode) as? Int,
              let modifiersValue = defaults.object(forKey: AppPreferenceKey.hotkeyModifiers) as? Int
        else {
            syncStoredPresetValuesIfNeeded()
            return
        }

        let keyCode = UInt16(keyCodeValue)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersValue)).intersection(.hotkeyRelevant)

        if keyCode == modifierOnlyKeyCode && modifiers == [.control, .option] {
            save(keyCode: defaultKeyCode, modifiers: defaultModifiers, sidedModifiers: [])
        }

        syncStoredPresetValuesIfNeeded()
        migrateHotkeyBindingsIfNeeded()
    }

    static func migrateHotkeyBindingsIfNeeded(defaults: UserDefaults = .standard) {
        migrateBindingsIfNeeded(
            bindingsKey: AppPreferenceKey.transcriptionHotkeyBindings,
            legacyHotkey: legacyHotkey(
                inputTypeKey: AppPreferenceKey.hotkeyInputType,
                keyCodeKey: AppPreferenceKey.hotkeyKeyCode,
                mouseButtonKey: AppPreferenceKey.hotkeyMouseButtonNumber,
                modifiersKey: AppPreferenceKey.hotkeyModifiers,
                sidedModifiersKey: AppPreferenceKey.hotkeySidedModifiers,
                defaultKeyCode: defaultKeyCode,
                defaultModifiers: defaultModifiers,
                defaults: defaults
            ),
            defaultBehavior: legacyDefaultBehavior(defaults: defaults),
            defaults: defaults
        )
        migrateBindingsIfNeeded(
            bindingsKey: AppPreferenceKey.translationHotkeyBindings,
            legacyHotkey: legacyHotkey(
                inputTypeKey: AppPreferenceKey.translationHotkeyInputType,
                keyCodeKey: AppPreferenceKey.translationHotkeyKeyCode,
                mouseButtonKey: AppPreferenceKey.translationHotkeyMouseButtonNumber,
                modifiersKey: AppPreferenceKey.translationHotkeyModifiers,
                sidedModifiersKey: AppPreferenceKey.translationHotkeySidedModifiers,
                defaultKeyCode: defaultTranslationKeyCode,
                defaultModifiers: defaultTranslationModifiers,
                defaults: defaults
            ),
            defaultBehavior: legacyDefaultBehavior(defaults: defaults),
            defaults: defaults
        )
        migrateBindingsIfNeeded(
            bindingsKey: AppPreferenceKey.meetingHotkeyBindings,
            legacyHotkey: legacyHotkey(
                inputTypeKey: AppPreferenceKey.meetingHotkeyInputType,
                keyCodeKey: AppPreferenceKey.meetingHotkeyKeyCode,
                mouseButtonKey: AppPreferenceKey.meetingHotkeyMouseButtonNumber,
                modifiersKey: AppPreferenceKey.meetingHotkeyModifiers,
                sidedModifiersKey: AppPreferenceKey.meetingHotkeySidedModifiers,
                defaultKeyCode: defaultMeetingKeyCode,
                defaultModifiers: defaultMeetingModifiers,
                defaults: defaults
            ),
            defaultBehavior: legacyDefaultBehavior(defaults: defaults),
            defaults: defaults
        )

        guard defaults.object(forKey: AppPreferenceKey.rewriteHotkeyBindings) == nil else { return }
        let rewriteActivationMode = loadRewriteActivationMode(defaults: defaults)
        let rewriteHotkey = rewriteActivationMode == .doubleTapTranscriptionHotkey
            ? legacyHotkey(
                inputTypeKey: AppPreferenceKey.hotkeyInputType,
                keyCodeKey: AppPreferenceKey.hotkeyKeyCode,
                mouseButtonKey: AppPreferenceKey.hotkeyMouseButtonNumber,
                modifiersKey: AppPreferenceKey.hotkeyModifiers,
                sidedModifiersKey: AppPreferenceKey.hotkeySidedModifiers,
                defaultKeyCode: defaultKeyCode,
                defaultModifiers: defaultModifiers,
                defaults: defaults
            )
            : legacyHotkey(
                inputTypeKey: AppPreferenceKey.rewriteHotkeyInputType,
                keyCodeKey: AppPreferenceKey.rewriteHotkeyKeyCode,
                mouseButtonKey: AppPreferenceKey.rewriteHotkeyMouseButtonNumber,
                modifiersKey: AppPreferenceKey.rewriteHotkeyModifiers,
                sidedModifiersKey: AppPreferenceKey.rewriteHotkeySidedModifiers,
                defaultKeyCode: defaultRewriteKeyCode,
                defaultModifiers: defaultRewriteModifiers,
                defaults: defaults
            )
        let rewriteBehavior: TriggerBehavior = rewriteActivationMode == .doubleTapTranscriptionHotkey
            ? .doubleTap
            : legacyDefaultBehavior(defaults: defaults)
        saveBindings(
            [.init(hotkey: rewriteHotkey, behavior: rewriteBehavior)],
            forKey: AppPreferenceKey.rewriteHotkeyBindings,
            defaults: defaults
        )
    }

    static func loadTranscriptionBindings(defaults: UserDefaults = .standard) -> [HotkeyBinding] {
        loadBindings(
            forKey: AppPreferenceKey.transcriptionHotkeyBindings,
            fallbackHotkey: load(),
            defaults: defaults
        )
    }

    static func loadTranslationBindings(defaults: UserDefaults = .standard) -> [HotkeyBinding] {
        loadBindings(
            forKey: AppPreferenceKey.translationHotkeyBindings,
            fallbackHotkey: loadTranslation(),
            defaults: defaults
        )
    }

    static func loadMeetingBindings(defaults: UserDefaults = .standard) -> [HotkeyBinding] {
        loadBindings(
            forKey: AppPreferenceKey.meetingHotkeyBindings,
            fallbackHotkey: loadMeeting(),
            defaults: defaults
        )
    }

    static func loadRewriteBindings(defaults: UserDefaults = .standard) -> [HotkeyBinding] {
        loadBindings(
            forKey: AppPreferenceKey.rewriteHotkeyBindings,
            fallbackHotkey: loadRewrite(),
            defaults: defaults
        )
    }

    static func saveTranscriptionBindings(_ bindings: [HotkeyBinding], defaults: UserDefaults = .standard) {
        saveBindings(bindings, forKey: AppPreferenceKey.transcriptionHotkeyBindings, defaults: defaults)
        if let first = sanitizedBindings(bindings).first {
            save(first.hotkey, defaults: defaults, syncBindings: false)
        }
    }

    static func saveTranslationBindings(_ bindings: [HotkeyBinding], defaults: UserDefaults = .standard) {
        saveBindings(bindings, forKey: AppPreferenceKey.translationHotkeyBindings, defaults: defaults)
        if let first = sanitizedBindings(bindings).first {
            saveTranslation(first.hotkey, defaults: defaults, syncBindings: false)
        }
    }

    static func saveMeetingBindings(_ bindings: [HotkeyBinding], defaults: UserDefaults = .standard) {
        saveBindings(bindings, forKey: AppPreferenceKey.meetingHotkeyBindings, defaults: defaults)
        if let first = sanitizedBindings(bindings).first {
            saveMeeting(first.hotkey, defaults: defaults, syncBindings: false)
        }
    }

    static func saveRewriteBindings(_ bindings: [HotkeyBinding], defaults: UserDefaults = .standard) {
        saveBindings(bindings, forKey: AppPreferenceKey.rewriteHotkeyBindings, defaults: defaults)
        if let first = sanitizedBindings(bindings).first {
            saveRewrite(first.hotkey, defaults: defaults, syncBindings: false)
        }
    }

    static func load() -> Hotkey {
        if let presetHotkey = resolvedPresetHotkeys()?.transcription {
            return presetHotkey
        }
        return load(
            inputTypeKey: AppPreferenceKey.hotkeyInputType,
            keyCodeKey: AppPreferenceKey.hotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.hotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.hotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.hotkeySidedModifiers,
            defaultKeyCode: defaultKeyCode,
            defaultModifiers: defaultModifiers
        )
    }

    static func save(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sidedModifiers: SidedModifierFlags) {
        save(.init(keyCode: keyCode, modifiers: modifiers, sidedModifiers: sidedModifiers))
    }

    static func save(_ hotkey: Hotkey, defaults: UserDefaults = .standard, syncBindings: Bool = true) {
        save(
            hotkey,
            inputTypeKey: AppPreferenceKey.hotkeyInputType,
            keyCodeKey: AppPreferenceKey.hotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.hotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.hotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.hotkeySidedModifiers,
            defaults: defaults
        )
        if syncBindings {
            saveBindings(
                [.init(hotkey: hotkey, behavior: legacyDefaultBehavior(defaults: defaults))],
                forKey: AppPreferenceKey.transcriptionHotkeyBindings,
                defaults: defaults
            )
        }
    }

    static func loadTranslation() -> Hotkey {
        if let presetHotkey = resolvedPresetHotkeys()?.translation {
            return presetHotkey
        }
        return load(
            inputTypeKey: AppPreferenceKey.translationHotkeyInputType,
            keyCodeKey: AppPreferenceKey.translationHotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.translationHotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.translationHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.translationHotkeySidedModifiers,
            defaultKeyCode: defaultTranslationKeyCode,
            defaultModifiers: defaultTranslationModifiers
        )
    }

    static func saveTranslation(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sidedModifiers: SidedModifierFlags) {
        saveTranslation(.init(keyCode: keyCode, modifiers: modifiers, sidedModifiers: sidedModifiers))
    }

    static func saveTranslation(_ hotkey: Hotkey, defaults: UserDefaults = .standard, syncBindings: Bool = true) {
        save(
            hotkey,
            inputTypeKey: AppPreferenceKey.translationHotkeyInputType,
            keyCodeKey: AppPreferenceKey.translationHotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.translationHotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.translationHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.translationHotkeySidedModifiers,
            defaults: defaults
        )
        if syncBindings {
            saveBindings(
                [.init(hotkey: hotkey, behavior: legacyDefaultBehavior(defaults: defaults))],
                forKey: AppPreferenceKey.translationHotkeyBindings,
                defaults: defaults
            )
        }
    }

    static func loadRewrite() -> Hotkey {
        if let presetHotkey = resolvedPresetHotkeys()?.rewrite {
            return presetHotkey
        }
        return load(
            inputTypeKey: AppPreferenceKey.rewriteHotkeyInputType,
            keyCodeKey: AppPreferenceKey.rewriteHotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.rewriteHotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.rewriteHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.rewriteHotkeySidedModifiers,
            defaultKeyCode: defaultRewriteKeyCode,
            defaultModifiers: defaultRewriteModifiers
        )
    }

    static func saveRewrite(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sidedModifiers: SidedModifierFlags) {
        saveRewrite(.init(keyCode: keyCode, modifiers: modifiers, sidedModifiers: sidedModifiers))
    }

    static func saveRewrite(_ hotkey: Hotkey, defaults: UserDefaults = .standard, syncBindings: Bool = true) {
        save(
            hotkey,
            inputTypeKey: AppPreferenceKey.rewriteHotkeyInputType,
            keyCodeKey: AppPreferenceKey.rewriteHotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.rewriteHotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.rewriteHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.rewriteHotkeySidedModifiers,
            defaults: defaults
        )
        if syncBindings {
            let behavior: TriggerBehavior = loadRewriteActivationMode(defaults: defaults) == .doubleTapTranscriptionHotkey
                ? .doubleTap
                : legacyDefaultBehavior(defaults: defaults)
            saveBindings(
                [.init(hotkey: hotkey, behavior: behavior)],
                forKey: AppPreferenceKey.rewriteHotkeyBindings,
                defaults: defaults
            )
        }
    }

    static func loadMeeting() -> Hotkey {
        if let presetHotkey = resolvedPresetHotkeys()?.meeting {
            return presetHotkey
        }
        return load(
            inputTypeKey: AppPreferenceKey.meetingHotkeyInputType,
            keyCodeKey: AppPreferenceKey.meetingHotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.meetingHotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.meetingHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.meetingHotkeySidedModifiers,
            defaultKeyCode: defaultMeetingKeyCode,
            defaultModifiers: defaultMeetingModifiers
        )
    }

    static func saveMeeting(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sidedModifiers: SidedModifierFlags) {
        saveMeeting(.init(keyCode: keyCode, modifiers: modifiers, sidedModifiers: sidedModifiers))
    }

    static func saveMeeting(_ hotkey: Hotkey, defaults: UserDefaults = .standard, syncBindings: Bool = true) {
        save(
            hotkey,
            inputTypeKey: AppPreferenceKey.meetingHotkeyInputType,
            keyCodeKey: AppPreferenceKey.meetingHotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.meetingHotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.meetingHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.meetingHotkeySidedModifiers,
            defaults: defaults
        )
        if syncBindings {
            saveBindings(
                [.init(hotkey: hotkey, behavior: legacyDefaultBehavior(defaults: defaults))],
                forKey: AppPreferenceKey.meetingHotkeyBindings,
                defaults: defaults
            )
        }
    }

    static func loadCustomPaste() -> Hotkey {
        if let presetHotkey = resolvedPresetHotkeys()?.customPaste {
            return presetHotkey
        }
        return normalizeCustomPasteHotkey(load(
            inputTypeKey: AppPreferenceKey.customPasteHotkeyInputType,
            keyCodeKey: AppPreferenceKey.customPasteHotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.customPasteHotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.customPasteHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.customPasteHotkeySidedModifiers,
            defaultKeyCode: defaultCustomPasteKeyCode,
            defaultModifiers: defaultCustomPasteModifiers
        ))
    }

    static func saveCustomPaste(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sidedModifiers: SidedModifierFlags) {
        saveCustomPaste(.init(keyCode: keyCode, modifiers: modifiers, sidedModifiers: sidedModifiers))
    }

    static func saveCustomPaste(_ hotkey: Hotkey, defaults: UserDefaults = .standard) {
        save(
            hotkey,
            inputTypeKey: AppPreferenceKey.customPasteHotkeyInputType,
            keyCodeKey: AppPreferenceKey.customPasteHotkeyKeyCode,
            mouseButtonKey: AppPreferenceKey.customPasteHotkeyMouseButtonNumber,
            modifiersKey: AppPreferenceKey.customPasteHotkeyModifiers,
            sidedModifiersKey: AppPreferenceKey.customPasteHotkeySidedModifiers,
            defaults: defaults
        )
    }

    static func loadTriggerMode(defaults: UserDefaults = .standard) -> TriggerMode {
        let raw = defaults.string(forKey: AppPreferenceKey.hotkeyTriggerMode)
        let requestedMode = TriggerMode(rawValue: raw ?? "") ?? defaultTriggerMode
        return enforcedTriggerMode(requestedMode, rewriteActivationMode: loadRewriteActivationMode(defaults: defaults))
    }

    static func saveTriggerMode(_ mode: TriggerMode, defaults: UserDefaults = .standard) {
        let enforcedMode = enforcedTriggerMode(mode, rewriteActivationMode: loadRewriteActivationMode(defaults: defaults))
        defaults.set(enforcedMode.rawValue, forKey: AppPreferenceKey.hotkeyTriggerMode)
    }

    static func loadRewriteActivationMode(defaults: UserDefaults = .standard) -> RewriteActivationMode {
        let raw = defaults.string(forKey: AppPreferenceKey.rewriteHotkeyActivationMode)
        return RewriteActivationMode(rawValue: raw ?? "") ?? defaultRewriteActivationMode
    }

    static func saveRewriteActivationMode(_ mode: RewriteActivationMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: AppPreferenceKey.rewriteHotkeyActivationMode)
        let currentTriggerMode = TriggerMode(
            rawValue: defaults.string(forKey: AppPreferenceKey.hotkeyTriggerMode) ?? ""
        ) ?? defaultTriggerMode
        saveTriggerMode(currentTriggerMode, defaults: defaults)
    }

    static func enforcedTriggerMode(
        _ mode: TriggerMode,
        rewriteActivationMode: RewriteActivationMode
    ) -> TriggerMode {
        rewriteActivationMode == .doubleTapTranscriptionHotkey ? .tap : mode
    }

    static func loadDistinguishModifierSides() -> Bool {
        true
    }

    static func loadPreset() -> Preset {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.hotkeyPreset)
        return Preset(rawValue: raw ?? "") ?? defaultPreset
    }

    @discardableResult
    static func applyPreset(_ preset: Preset) -> PresetHotkeys? {
        UserDefaults.standard.set(preset.rawValue, forKey: AppPreferenceKey.hotkeyPreset)
        guard let values = presetHotkeys(for: preset) else { return nil }
        applyPresetHotkeys(values)
        return values
    }

    private static func resolvedPresetHotkeys() -> PresetHotkeys? {
        let preset = loadPreset()
        guard preset != .custom else { return nil }
        return presetHotkeys(for: preset)
    }

    private static func syncStoredPresetValuesIfNeeded() {
        guard let presetValues = resolvedPresetHotkeys() else { return }
        applyPresetHotkeys(presetValues)
    }

    private static func applyPresetHotkeys(_ presetValues: PresetHotkeys) {
        UserDefaults.standard.set(presetValues.distinguishSides, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        save(presetValues.transcription, syncBindings: false)
        saveTranslation(presetValues.translation, syncBindings: false)
        saveRewrite(presetValues.rewrite, syncBindings: false)
        saveMeeting(presetValues.meeting, syncBindings: false)
        saveCustomPaste(presetValues.customPaste)
        saveRewriteActivationMode(presetValues.rewriteActivationMode)
        saveTriggerMode(presetValues.triggerMode)
        saveTranscriptionBindings(presetValues.transcriptionBindings)
        saveTranslationBindings(presetValues.translationBindings)
        saveMeetingBindings(presetValues.meetingBindings)
        saveRewriteBindings(presetValues.rewriteBindings)
    }

    private static func normalizeCustomPasteHotkey(_ hotkey: Hotkey) -> Hotkey {
        guard case .keyboard(let keyCode) = hotkey.input,
              keyCode != modifierOnlyKeyCode
        else { return hotkey }
        return Hotkey(
            input: hotkey.input,
            modifiers: hotkey.modifiers,
            sidedModifiers: []
        )
    }

    static func displayString(for hotkey: Hotkey, distinguishModifierSides: Bool) -> String {
        let symbols = modifierSymbols(
            for: hotkey.modifiers,
            sidedModifiers: distinguishModifierSides ? hotkey.sidedModifiers : []
        )
        if case .keyboard(let keyCode) = hotkey.input, keyCode == modifierOnlyKeyCode {
            return symbols.isEmpty ? "Unassigned" : symbols
        }
        let key = inputDisplayString(hotkey.input)
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

    static func presetHotkeys(for preset: Preset) -> PresetHotkeys? {
        switch preset {
        case .fnCombo:
            return PresetHotkeys(
                distinguishSides: false,
                transcription: Hotkey(keyCode: defaultKeyCode, modifiers: defaultModifiers, sidedModifiers: []),
                translation: Hotkey(keyCode: defaultTranslationKeyCode, modifiers: defaultTranslationModifiers, sidedModifiers: []),
                rewrite: Hotkey(keyCode: defaultRewriteKeyCode, modifiers: defaultRewriteModifiers, sidedModifiers: []),
                meeting: Hotkey(keyCode: defaultMeetingKeyCode, modifiers: defaultMeetingModifiers, sidedModifiers: []),
                customPaste: Hotkey(keyCode: defaultCustomPasteKeyCode, modifiers: defaultCustomPasteModifiers, sidedModifiers: [])
            )
        case .commandCombo:
            return PresetHotkeys(
                distinguishSides: true,
                transcription: Hotkey(keyCode: modifierOnlyKeyCode, modifiers: [.command], sidedModifiers: [.rightCommand]),
                translation: Hotkey(keyCode: modifierOnlyKeyCode, modifiers: [.command, .shift], sidedModifiers: [.rightCommand, .rightShift]),
                rewrite: Hotkey(keyCode: modifierOnlyKeyCode, modifiers: [.command, .option], sidedModifiers: [.rightCommand, .rightOption]),
                meeting: Hotkey(keyCode: UInt16(kVK_ANSI_L), modifiers: [.command], sidedModifiers: [.rightCommand]),
                customPaste: Hotkey(keyCode: defaultCustomPasteKeyCode, modifiers: defaultCustomPasteModifiers, sidedModifiers: [])
            )
        case .mouseMiddleFnShift:
            return PresetHotkeys(
                distinguishSides: false,
                transcription: Hotkey(mouseButtonNumber: middleMouseButtonNumber),
                translation: Hotkey(keyCode: defaultTranslationKeyCode, modifiers: defaultTranslationModifiers, sidedModifiers: []),
                rewrite: Hotkey(mouseButtonNumber: middleMouseButtonNumber),
                meeting: Hotkey(keyCode: defaultMeetingKeyCode, modifiers: defaultMeetingModifiers, sidedModifiers: []),
                customPaste: Hotkey(keyCode: defaultCustomPasteKeyCode, modifiers: defaultCustomPasteModifiers, sidedModifiers: []),
                triggerMode: .tap,
                rewriteActivationMode: .doubleTapTranscriptionHotkey
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

        guard Thread.isMainThread else {
            return "Key \(keyCode)"
        }

        if let translated = translateKeyCode(keyCode), !translated.isEmpty {
            return translated.uppercased()
        }
        return "Key \(keyCode)"
    }

    static func inputDisplayString(_ input: Hotkey.Input) -> String {
        switch input {
        case .keyboard(let keyCode):
            return keyCodeDisplayString(keyCode)
        case .mouseButton(let buttonNumber):
            return mouseButtonDisplayString(buttonNumber)
        }
    }

    static func mouseButtonDisplayString(_ buttonNumber: Int) -> String {
        switch buttonNumber {
        case middleMouseButtonNumber:
            return AppLocalization.localizedString("Mouse Middle Button")
        default:
            return AppLocalization.format("Mouse Button %d", buttonNumber)
        }
    }

    private static func legacyDefaultBehavior(defaults: UserDefaults) -> TriggerBehavior {
        TriggerBehavior(loadTriggerMode(defaults: defaults))
    }

    private static func migrateBindingsIfNeeded(
        bindingsKey: String,
        legacyHotkey: Hotkey,
        defaultBehavior: TriggerBehavior,
        defaults: UserDefaults
    ) {
        guard defaults.object(forKey: bindingsKey) == nil else { return }
        saveBindings(
            [.init(hotkey: legacyHotkey, behavior: defaultBehavior)],
            forKey: bindingsKey,
            defaults: defaults
        )
    }

    private static func loadBindings(
        forKey key: String,
        fallbackHotkey: Hotkey,
        defaults: UserDefaults
    ) -> [HotkeyBinding] {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HotkeyBinding].self, from: data) {
            let sanitized = sanitizedBindings(decoded)
            if !sanitized.isEmpty {
                return sanitized
            }
        }
        let fallback = [HotkeyBinding(hotkey: fallbackHotkey, behavior: legacyDefaultBehavior(defaults: defaults))]
        saveBindings(fallback, forKey: key, defaults: defaults)
        return fallback
    }

    private static func saveBindings(
        _ bindings: [HotkeyBinding],
        forKey key: String,
        defaults: UserDefaults = .standard
    ) {
        let sanitized = sanitizedBindings(bindings)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        defaults.set(data, forKey: key)
    }

    private static func sanitizedBindings(_ bindings: [HotkeyBinding]) -> [HotkeyBinding] {
        let sanitized = bindings.map {
            HotkeyBinding(
                id: $0.id,
                hotkey: canonicalHotkey(
                    input: $0.hotkey.input,
                    modifiers: $0.hotkey.modifiers,
                    sidedModifiers: $0.hotkey.sidedModifiers
                ),
                behavior: $0.behavior
            )
        }
        return sanitized.isEmpty
            ? [.init(hotkey: Hotkey(keyCode: defaultKeyCode, modifiers: defaultModifiers, sidedModifiers: []), behavior: .tap)]
            : sanitized
    }

    private static func legacyHotkey(
        inputTypeKey: String,
        keyCodeKey: String,
        mouseButtonKey: String,
        modifiersKey: String,
        sidedModifiersKey: String,
        defaultKeyCode: UInt16,
        defaultModifiers: NSEvent.ModifierFlags,
        defaults: UserDefaults
    ) -> Hotkey {
        let inputTypeRaw = defaults.string(forKey: inputTypeKey)
        let keyCodeValue = defaults.object(forKey: keyCodeKey) as? Int
        let mouseButtonValue = defaults.object(forKey: mouseButtonKey) as? Int
        let modifiersValue = defaults.object(forKey: modifiersKey) as? Int
        let sidedValue = defaults.object(forKey: sidedModifiersKey) as? Int

        let keyCode = UInt16(keyCodeValue ?? Int(defaultKeyCode))
        let input: Hotkey.Input
        if Hotkey.Input.Kind(rawValue: inputTypeRaw ?? "") == .mouseButton,
           let mouseButtonValue,
           mouseButtonValue >= middleMouseButtonNumber {
            input = .mouseButton(mouseButtonValue)
        } else {
            input = .keyboard(keyCode)
        }
        let modifiersRaw = modifiersValue ?? Int(defaultModifiers.rawValue)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw)).intersection(.hotkeyRelevant)
        let sidedModifiers = migratedLegacySidedModifiers(
            storedRawValue: sidedValue,
            modifiers: modifiers
        )
        return canonicalHotkey(
            input: input,
            modifiers: modifiers,
            sidedModifiers: sidedModifiers
        )
    }

    private static func migratedLegacySidedModifiers(
        storedRawValue: Int?,
        modifiers: NSEvent.ModifierFlags
    ) -> SidedModifierFlags {
        if let storedRawValue, storedRawValue != 0 {
            return SidedModifierFlags(rawValue: storedRawValue).filtered(by: modifiers)
        }

        var sided: SidedModifierFlags = []
        if modifiers.contains(.shift) { sided.insert(.leftShift) }
        if modifiers.contains(.control) { sided.insert(.leftControl) }
        if modifiers.contains(.option) { sided.insert(.leftOption) }
        if modifiers.contains(.command) { sided.insert(.leftCommand) }
        return sided.filtered(by: modifiers)
    }

    private static func load(
        inputTypeKey: String,
        keyCodeKey: String,
        mouseButtonKey: String,
        modifiersKey: String,
        sidedModifiersKey: String,
        defaultKeyCode: UInt16,
        defaultModifiers: NSEvent.ModifierFlags
    ) -> Hotkey {
        let defaults = UserDefaults.standard
        let inputTypeRaw = defaults.string(forKey: inputTypeKey)
        let keyCodeValue = defaults.object(forKey: keyCodeKey) as? Int
        let mouseButtonValue = defaults.object(forKey: mouseButtonKey) as? Int
        let modifiersValue = defaults.object(forKey: modifiersKey) as? Int
        let sidedValue = defaults.object(forKey: sidedModifiersKey) as? Int ?? 0

        let keyCode = UInt16(keyCodeValue ?? Int(defaultKeyCode))
        let input: Hotkey.Input
        if Hotkey.Input.Kind(rawValue: inputTypeRaw ?? "") == .mouseButton,
           let mouseButtonValue,
           mouseButtonValue >= middleMouseButtonNumber {
            input = .mouseButton(mouseButtonValue)
        } else {
            input = .keyboard(keyCode)
        }
        let modifiersRaw = modifiersValue ?? Int(defaultModifiers.rawValue)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw)).intersection(.hotkeyRelevant)
        let sidedModifiers = SidedModifierFlags(rawValue: sidedValue).filtered(by: modifiers)

        return canonicalHotkey(
            input: input,
            modifiers: modifiers,
            sidedModifiers: sidedModifiers
        )
    }

    private static func canonicalHotkey(
        input: Hotkey.Input,
        modifiers: NSEvent.ModifierFlags,
        sidedModifiers: SidedModifierFlags
    ) -> Hotkey {
        guard case .keyboard(let keyCode) = input else {
            return Hotkey(
                input: input,
                modifiers: modifiers,
                sidedModifiers: sidedModifiers.filtered(by: modifiers)
            )
        }
        guard let representedModifier = SidedModifierFlags.fromModifierKeyCode(keyCode),
              modifiers.contains(representedModifier.modifiers)
        else {
            return Hotkey(
                input: input,
                modifiers: modifiers,
                sidedModifiers: sidedModifiers.filtered(by: modifiers)
            )
        }

        return Hotkey(
            keyCode: modifierOnlyKeyCode,
            modifiers: modifiers,
            sidedModifiers: sidedModifiers
                .union(representedModifier.sided)
                .filtered(by: modifiers)
        )
    }

    private static func save(
        _ hotkey: Hotkey,
        inputTypeKey: String,
        keyCodeKey: String,
        mouseButtonKey: String,
        modifiersKey: String,
        sidedModifiersKey: String,
        defaults: UserDefaults
    ) {
        defaults.set(hotkey.input.kind.rawValue, forKey: inputTypeKey)
        switch hotkey.input {
        case .keyboard(let keyCode):
            defaults.set(Int(keyCode), forKey: keyCodeKey)
            defaults.removeObject(forKey: mouseButtonKey)
        case .mouseButton(let buttonNumber):
            defaults.set(buttonNumber, forKey: mouseButtonKey)
        }
        defaults.set(Int(hotkey.modifiers.rawValue), forKey: modifiersKey)
        defaults.set(hotkey.sidedModifiers.filtered(by: hotkey.modifiers).rawValue, forKey: sidedModifiersKey)
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

nonisolated extension NSEvent.ModifierFlags {
    static let hotkeyRelevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
}

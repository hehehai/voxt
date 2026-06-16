// HotkeySettingsView.swift
// Provides Hotkey Settings View for settings screens.

import SwiftUI
import AppKit
import Carbon

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

enum HotkeyShortcutKind: String, CaseIterable {
    case transcription
    case translation
    case meeting
    case rewrite

    var titleKey: LocalizedStringKey {
        switch self {
        case .transcription:
            return "Transcription"
        case .translation:
            return "Translation"
        case .meeting:
            return "Meeting"
        case .rewrite:
            return "Content Rewrite"
        }
    }
}

enum HotkeyShortcutVisibility {
    static func visibleKinds() -> [HotkeyShortcutKind] {
        [.transcription, .translation, .meeting, .rewrite]
    }
}

struct HotkeySettingsView: View {
    private enum RecordingField {
        case transcription
        case translation
        case meeting
        case rewrite
        case customPaste
    }

    @AppStorage(AppPreferenceKey.hotkeyInputType) private var hotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
    @AppStorage(AppPreferenceKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyPreference.defaultKeyCode)
    @AppStorage(AppPreferenceKey.hotkeyMouseButtonNumber) private var hotkeyMouseButtonNumber = HotkeyPreference.middleMouseButtonNumber
    @AppStorage(AppPreferenceKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyPreference.defaultModifiers.rawValue)
    @AppStorage(AppPreferenceKey.hotkeySidedModifiers) private var hotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.translationHotkeyInputType) private var translationHotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
    @AppStorage(AppPreferenceKey.translationHotkeyKeyCode) private var translationHotkeyKeyCode = Int(HotkeyPreference.defaultTranslationKeyCode)
    @AppStorage(AppPreferenceKey.translationHotkeyMouseButtonNumber) private var translationHotkeyMouseButtonNumber = HotkeyPreference.middleMouseButtonNumber
    @AppStorage(AppPreferenceKey.translationHotkeyModifiers) private var translationHotkeyModifiers = Int(HotkeyPreference.defaultTranslationModifiers.rawValue)
    @AppStorage(AppPreferenceKey.translationHotkeySidedModifiers) private var translationHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.meetingHotkeyInputType) private var meetingHotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
    @AppStorage(AppPreferenceKey.meetingHotkeyKeyCode) private var meetingHotkeyKeyCode = Int(HotkeyPreference.defaultMeetingKeyCode)
    @AppStorage(AppPreferenceKey.meetingHotkeyMouseButtonNumber) private var meetingHotkeyMouseButtonNumber = HotkeyPreference.middleMouseButtonNumber
    @AppStorage(AppPreferenceKey.meetingHotkeyModifiers) private var meetingHotkeyModifiers = Int(HotkeyPreference.defaultMeetingModifiers.rawValue)
    @AppStorage(AppPreferenceKey.meetingHotkeySidedModifiers) private var meetingHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.rewriteHotkeyInputType) private var rewriteHotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
    @AppStorage(AppPreferenceKey.rewriteHotkeyKeyCode) private var rewriteHotkeyKeyCode = Int(HotkeyPreference.defaultRewriteKeyCode)
    @AppStorage(AppPreferenceKey.rewriteHotkeyMouseButtonNumber) private var rewriteHotkeyMouseButtonNumber = HotkeyPreference.middleMouseButtonNumber
    @AppStorage(AppPreferenceKey.rewriteHotkeyModifiers) private var rewriteHotkeyModifiers = Int(HotkeyPreference.defaultRewriteModifiers.rawValue)
    @AppStorage(AppPreferenceKey.rewriteHotkeySidedModifiers) private var rewriteHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.rewriteHotkeyActivationMode) private var rewriteHotkeyActivationMode = HotkeyPreference.defaultRewriteActivationMode.rawValue
    @AppStorage(AppPreferenceKey.customPasteHotkeyEnabled) private var customPasteHotkeyEnabled = false
    @AppStorage(AppPreferenceKey.customPasteHotkeyInputType) private var customPasteHotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
    @AppStorage(AppPreferenceKey.customPasteHotkeyKeyCode) private var customPasteHotkeyKeyCode = Int(HotkeyPreference.defaultCustomPasteKeyCode)
    @AppStorage(AppPreferenceKey.customPasteHotkeyMouseButtonNumber) private var customPasteHotkeyMouseButtonNumber = HotkeyPreference.middleMouseButtonNumber
    @AppStorage(AppPreferenceKey.customPasteHotkeyModifiers) private var customPasteHotkeyModifiers = Int(HotkeyPreference.defaultCustomPasteModifiers.rawValue)
    @AppStorage(AppPreferenceKey.customPasteHotkeySidedModifiers) private var customPasteHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.hotkeyTriggerMode) private var hotkeyTriggerMode = HotkeyPreference.defaultTriggerMode.rawValue
    @AppStorage(AppPreferenceKey.hotkeyDistinguishModifierSides) private var distinguishModifierSides = HotkeyPreference.defaultDistinguishModifierSides
    @AppStorage(AppPreferenceKey.hotkeyPreset) private var hotkeyPreset = HotkeyPreference.defaultPreset.rawValue
    @AppStorage(AppPreferenceKey.escapeKeyCancelsOverlaySession) private var escapeKeyCancelsOverlaySession = true
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @State private var recordingField: RecordingField?
    @State private var pendingCapturedField: RecordingField?
    @State private var pendingCapturedHotkey: HotkeyPreference.Hotkey?
    @State private var recorderMessageKey: String?
    @State private var isAdvancedExpanded = false
    @State private var hotkeyToastMessage = ""
    @State private var hotkeyToastDismissTask: Task<Void, Never>?

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
            input: hotkeyInput,
            modifiers: modifierBinding.wrappedValue,
            sidedModifiers: sidedModifierBinding.wrappedValue
        )
    }

    private var hotkeyInput: HotkeyPreference.Hotkey.Input {
        resolvedInput(
            inputType: hotkeyInputType,
            keyCode: hotkeyKeyCode,
            mouseButtonNumber: hotkeyMouseButtonNumber
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
            input: translationHotkeyInput,
            modifiers: translationModifierBinding.wrappedValue,
            sidedModifiers: translationSidedModifierBinding.wrappedValue
        )
    }

    private var translationHotkeyInput: HotkeyPreference.Hotkey.Input {
        resolvedInput(
            inputType: translationHotkeyInputType,
            keyCode: translationHotkeyKeyCode,
            mouseButtonNumber: translationHotkeyMouseButtonNumber
        )
    }

    private var translationSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: translationHotkeySidedModifiers).filtered(by: translationModifierBinding.wrappedValue) },
            set: { translationHotkeySidedModifiers = $0.filtered(by: translationModifierBinding.wrappedValue).rawValue }
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
            input: meetingHotkeyInput,
            modifiers: meetingModifierBinding.wrappedValue,
            sidedModifiers: meetingSidedModifierBinding.wrappedValue
        )
    }

    private var meetingHotkeyInput: HotkeyPreference.Hotkey.Input {
        resolvedInput(
            inputType: meetingHotkeyInputType,
            keyCode: meetingHotkeyKeyCode,
            mouseButtonNumber: meetingHotkeyMouseButtonNumber
        )
    }

    private var meetingSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: meetingHotkeySidedModifiers).filtered(by: meetingModifierBinding.wrappedValue) },
            set: { meetingHotkeySidedModifiers = $0.filtered(by: meetingModifierBinding.wrappedValue).rawValue }
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
            input: rewriteHotkeyInput,
            modifiers: rewriteModifierBinding.wrappedValue,
            sidedModifiers: rewriteSidedModifierBinding.wrappedValue
        )
    }

    private var rewriteHotkeyInput: HotkeyPreference.Hotkey.Input {
        resolvedInput(
            inputType: rewriteHotkeyInputType,
            keyCode: rewriteHotkeyKeyCode,
            mouseButtonNumber: rewriteHotkeyMouseButtonNumber
        )
    }

    private var rewriteSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: rewriteHotkeySidedModifiers).filtered(by: rewriteModifierBinding.wrappedValue) },
            set: { rewriteHotkeySidedModifiers = $0.filtered(by: rewriteModifierBinding.wrappedValue).rawValue }
        )
    }

    private var customPasteHotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(customPasteHotkeyKeyCode) },
            set: { customPasteHotkeyKeyCode = Int($0) }
        )
    }

    private var customPasteModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(customPasteHotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: { customPasteHotkeyModifiers = Int($0.rawValue) }
        )
    }

    private var currentCustomPasteHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            input: customPasteHotkeyInput,
            modifiers: customPasteModifierBinding.wrappedValue,
            sidedModifiers: customPasteSidedModifierBinding.wrappedValue
        )
    }

    private var customPasteHotkeyInput: HotkeyPreference.Hotkey.Input {
        resolvedInput(
            inputType: customPasteHotkeyInputType,
            keyCode: customPasteHotkeyKeyCode,
            mouseButtonNumber: customPasteHotkeyMouseButtonNumber
        )
    }

    private var customPasteSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: customPasteHotkeySidedModifiers).filtered(by: customPasteModifierBinding.wrappedValue) },
            set: { customPasteHotkeySidedModifiers = $0.filtered(by: customPasteModifierBinding.wrappedValue).rawValue }
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
            get: {
                rewriteActivationState.enforcedTriggerMode(
                    from: HotkeyPreference.TriggerMode(rawValue: hotkeyTriggerMode) ?? HotkeyPreference.defaultTriggerMode
                )
            },
            set: {
                hotkeyTriggerMode = rewriteActivationState.enforcedTriggerMode(from: $0).rawValue
            }
        )
    }

    private var rewriteActivationState: HotkeyRewriteActivationState {
        HotkeyRewriteActivationState(rawValue: rewriteHotkeyActivationMode)
    }

    private var isRewriteDoubleTapWakeEnabled: Bool {
        rewriteActivationState.isDoubleTapWakeEnabled
    }

    private var rewriteDoubleTapDisplayText: String {
        rewriteActivationState.displayText(
            for: currentHotkey,
            distinguishModifierSides: distinguishModifierSides
        )
    }

    private var validationMessages: [HotkeySettingsValidation.Message] {
        HotkeySettingsValidation.messages(
            for: .init(
                transcriptionHotkey: currentHotkey,
                translationHotkey: currentTranslationHotkey,
                meetingHotkey: currentMeetingHotkey,
                rewriteHotkey: currentRewriteHotkey,
                shouldValidateRewriteHotkey: !isRewriteDoubleTapWakeEnabled,
                customPasteHotkey: customPasteHotkeyEnabled ? currentCustomPasteHotkey : nil
            )
        )
    }

    private var presetBinding: Binding<HotkeyPreference.Preset> {
        Binding(
            get: { HotkeyPreference.Preset(rawValue: hotkeyPreset) ?? .custom },
            set: { applyPreset($0) }
        )
    }

    private func resolvedInput(
        inputType: String,
        keyCode: Int,
        mouseButtonNumber: Int
    ) -> HotkeyPreference.Hotkey.Input {
        if HotkeyPreference.Hotkey.Input.Kind(rawValue: inputType) == .mouseButton {
            return .mouseButton(mouseButtonNumber)
        }
        return .keyboard(UInt16(keyCode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(localized("Preset"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.92))
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
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.92))
                            Text(localized("Left Shift and Right Shift are treated as different shortcuts."))
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

                    SettingsShortcutCaptureField(
                        title: "Transcription",
                        hotkey: displayedHotkey(for: .transcription, current: currentHotkey),
                        isRecording: recordingField == .transcription,
                        isPendingConfirmation: isPendingConfirmation(for: .transcription),
                        distinguishModifierSides: distinguishModifierSides,
                        onFocus: { beginRecording(.transcription) },
                        onReset: {
                            hotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
                            hotkeyBinding.wrappedValue = HotkeyPreference.defaultKeyCode
                            modifierBinding.wrappedValue = HotkeyPreference.defaultModifiers
                            sidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    SettingsShortcutCaptureField(
                        title: "Translation",
                        hotkey: displayedHotkey(for: .translation, current: currentTranslationHotkey),
                        isRecording: recordingField == .translation,
                        isPendingConfirmation: isPendingConfirmation(for: .translation),
                        distinguishModifierSides: distinguishModifierSides,
                        onFocus: { beginRecording(.translation) },
                        onReset: {
                            translationHotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
                            translationHotkeyBinding.wrappedValue = HotkeyPreference.defaultTranslationKeyCode
                            translationModifierBinding.wrappedValue = HotkeyPreference.defaultTranslationModifiers
                            translationSidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    SettingsShortcutCaptureField(
                        title: "Meeting",
                        hotkey: displayedHotkey(for: .meeting, current: currentMeetingHotkey),
                        isRecording: recordingField == .meeting,
                        isPendingConfirmation: isPendingConfirmation(for: .meeting),
                        distinguishModifierSides: distinguishModifierSides,
                        onFocus: { beginRecording(.meeting) },
                        onReset: {
                            meetingHotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
                            meetingHotkeyBinding.wrappedValue = HotkeyPreference.defaultMeetingKeyCode
                            meetingModifierBinding.wrappedValue = HotkeyPreference.defaultMeetingModifiers
                            meetingSidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    SettingsShortcutCaptureField(
                        title: "Content Rewrite",
                        hotkey: displayedHotkey(for: .rewrite, current: currentRewriteHotkey),
                        isRecording: recordingField == .rewrite,
                        isPendingConfirmation: isPendingConfirmation(for: .rewrite),
                        distinguishModifierSides: distinguishModifierSides,
                        displayTextOverride: isRewriteDoubleTapWakeEnabled ? rewriteDoubleTapDisplayText : nil,
                        isReadOnly: isRewriteDoubleTapWakeEnabled,
                        modeButtonTitle: "Double-tap Wake",
                        isModeButtonSelected: isRewriteDoubleTapWakeEnabled,
                        onModeButtonToggle: toggleRewriteDoubleTapWake,
                        onFocus: { beginRecording(.rewrite) },
                        onReset: {
                            rewriteHotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
                            rewriteHotkeyBinding.wrappedValue = HotkeyPreference.defaultRewriteKeyCode
                            rewriteModifierBinding.wrappedValue = HotkeyPreference.defaultRewriteModifiers
                            rewriteSidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    ForEach(validationMessages) { message in
                        Text(message.text)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HotkeyRecorderView(
                        isRecording: isRecordingBinding,
                        onCapture: { capturedHotkey in
                            guard let field = recordingField else { return }
                            pendingCapturedField = field
                            pendingCapturedHotkey = capturedHotkey
                            showHotkeyToast(localized("Shortcut captured. Press another shortcut to replace it, or choose Confirm / Cancel."))
                        },
                        onCancelCapture: {
                            discardPendingCapture()
                            recordingField = nil
                        },
                        onRecorderMessageChange: { messageKey in
                            guard recorderMessageKey != messageKey else { return }
                            DispatchQueue.main.async {
                                recorderMessageKey = messageKey
                                if let messageKey {
                                    showHotkeyToast(localized(messageKey))
                                }
                            }
                        }
                    )
                    .frame(width: 0, height: 0)

                    GeneralSectionDivider()
                        .padding(.top, 2)

                    HStack(alignment: .center, spacing: 12) {
                        Text(localized("Trigger"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.92))
                        Spacer()
                        SettingsMenuPicker(
                            selection: triggerModeBinding,
                            options: HotkeyPreference.TriggerMode.allCases.map { mode in
                                SettingsMenuOption(value: mode, title: mode.title)
                            },
                            selectedTitle: triggerModeBinding.wrappedValue.title,
                            width: 336
                        )
                        .disabled(isRewriteDoubleTapWakeEnabled)
                    }

                    if customPasteHotkeyEnabled {
                        SettingsShortcutCaptureField(
                            title: "Custom Paste",
                            hotkey: displayedHotkey(for: .customPaste, current: currentCustomPasteHotkey),
                            isRecording: recordingField == .customPaste,
                            isPendingConfirmation: isPendingConfirmation(for: .customPaste),
                            distinguishModifierSides: distinguishModifierSides,
                            onFocus: { beginRecording(.customPaste) },
                            onReset: {
                                customPasteHotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
                                customPasteHotkeyBinding.wrappedValue = HotkeyPreference.defaultCustomPasteKeyCode
                                customPasteModifierBinding.wrappedValue = HotkeyPreference.defaultCustomPasteModifiers
                                customPasteSidedModifierBinding.wrappedValue = []
                            },
                            onCancelPending: discardPendingCapture,
                            onConfirmPending: confirmPendingCapture
                        )
                    }

                    HStack(alignment: .center, spacing: 18) {
                        Text(localized("Use Esc to Cancel"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.92))
                        Spacer()
                        Toggle("", isOn: $escapeKeyCancelsOverlaySession)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GeneralAdvancedCard(isExpanded: $isAdvancedExpanded) {
                VoiceEndCommandSettingsSection()
            }
        }
        .id(interfaceLanguageRaw)
        .overlay(alignment: .top) {
            if !hotkeyToastMessage.isEmpty {
                ModelDebugToast(message: hotkeyToastMessage) {
                    dismissHotkeyToast()
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: hotkeyToastMessage)
        .onChange(of: customPasteHotkeyEnabled) { _, enabled in
            guard !enabled else { return }
            if recordingField == .customPaste || pendingCapturedField == .customPaste {
                discardPendingCapture()
            }
        }
        .onChange(of: rewriteHotkeyActivationMode) { _, _ in
            if isRewriteDoubleTapWakeEnabled {
                hotkeyTriggerMode = HotkeyPreference.TriggerMode.tap.rawValue
                if recordingField == .rewrite || pendingCapturedField == .rewrite {
                    discardPendingCapture()
                }
            }
        }
    }

    private func applyPreset(_ preset: HotkeyPreference.Preset) {
        discardPendingCapture()
        hotkeyPreset = preset.rawValue
        guard let values = HotkeyPreference.applyPreset(preset) else { return }
        distinguishModifierSides = values.distinguishSides
    }

    private func beginRecording(_ field: RecordingField) {
        pendingCapturedField = nil
        pendingCapturedHotkey = nil
        recordingField = field
        showHotkeyToast(localized("Type your shortcut now. Press Esc to cancel recording."))
    }

    private func toggleRewriteDoubleTapWake() {
        discardPendingCapture()
        let nextState = HotkeyRewriteActivationState(
            rawValue: rewriteActivationState.toggledMode.rawValue
        )
        rewriteHotkeyActivationMode = nextState.mode.rawValue
        hotkeyTriggerMode = nextState.enforcedTriggerMode(
            from: HotkeyPreference.TriggerMode(rawValue: hotkeyTriggerMode)
                ?? HotkeyPreference.defaultTriggerMode
        ).rawValue
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
        dismissHotkeyToast()
    }

    private func confirmPendingCapture() {
        guard let field = pendingCapturedField, let hotkey = pendingCapturedHotkey else { return }

        switch field {
        case .transcription:
            assign(hotkey.input, inputType: &hotkeyInputType, keyCode: &hotkeyKeyCode, mouseButtonNumber: &hotkeyMouseButtonNumber)
            modifierBinding.wrappedValue = hotkey.modifiers
            sidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .translation:
            assign(hotkey.input, inputType: &translationHotkeyInputType, keyCode: &translationHotkeyKeyCode, mouseButtonNumber: &translationHotkeyMouseButtonNumber)
            translationModifierBinding.wrappedValue = hotkey.modifiers
            translationSidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .meeting:
            assign(hotkey.input, inputType: &meetingHotkeyInputType, keyCode: &meetingHotkeyKeyCode, mouseButtonNumber: &meetingHotkeyMouseButtonNumber)
            meetingModifierBinding.wrappedValue = hotkey.modifiers
            meetingSidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .rewrite:
            assign(hotkey.input, inputType: &rewriteHotkeyInputType, keyCode: &rewriteHotkeyKeyCode, mouseButtonNumber: &rewriteHotkeyMouseButtonNumber)
            rewriteModifierBinding.wrappedValue = hotkey.modifiers
            rewriteSidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .customPaste:
            assign(hotkey.input, inputType: &customPasteHotkeyInputType, keyCode: &customPasteHotkeyKeyCode, mouseButtonNumber: &customPasteHotkeyMouseButtonNumber)
            customPasteModifierBinding.wrappedValue = hotkey.modifiers
            customPasteSidedModifierBinding.wrappedValue =
                hotkey.keyCode == HotkeyPreference.modifierOnlyKeyCode || hotkey.isMouseButton ? hotkey.sidedModifiers : []
        }

        hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
        pendingCapturedField = nil
        pendingCapturedHotkey = nil
        recordingField = nil
        dismissHotkeyToast()
    }

    private func showHotkeyToast(_ message: String, duration: TimeInterval = 2.2) {
        hotkeyToastDismissTask?.cancel()
        hotkeyToastMessage = message
        hotkeyToastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            hotkeyToastMessage = ""
        }
    }

    private func dismissHotkeyToast() {
        hotkeyToastDismissTask?.cancel()
        hotkeyToastMessage = ""
    }

    private func assign(
        _ input: HotkeyPreference.Hotkey.Input,
        inputType: inout String,
        keyCode: inout Int,
        mouseButtonNumber: inout Int
    ) {
        inputType = input.kind.rawValue
        switch input {
        case .keyboard(let value):
            keyCode = Int(value)
        case .mouseButton(let value):
            mouseButtonNumber = value
        }
    }
}

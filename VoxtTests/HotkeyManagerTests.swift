import XCTest
import AppKit
import Carbon
import ApplicationServices
import IOKit.hidsystem
@testable import Voxt

@MainActor
final class HotkeyManagerTests: XCTestCase {
    private static var retainedManagers: [HotkeyManager] = []
    private let managedDefaultKeys = [
        AppPreferenceKey.hotkeyKeyCode,
        AppPreferenceKey.hotkeyModifiers,
        AppPreferenceKey.hotkeySidedModifiers,
        AppPreferenceKey.translationHotkeyKeyCode,
        AppPreferenceKey.translationHotkeyModifiers,
        AppPreferenceKey.translationHotkeySidedModifiers,
        AppPreferenceKey.rewriteHotkeyKeyCode,
        AppPreferenceKey.rewriteHotkeyModifiers,
        AppPreferenceKey.rewriteHotkeySidedModifiers,
        AppPreferenceKey.meetingHotkeyKeyCode,
        AppPreferenceKey.meetingHotkeyModifiers,
        AppPreferenceKey.meetingHotkeySidedModifiers,
        AppPreferenceKey.customPasteHotkeyEnabled,
        AppPreferenceKey.customPasteHotkeyKeyCode,
        AppPreferenceKey.customPasteHotkeyModifiers,
        AppPreferenceKey.customPasteHotkeySidedModifiers,
        AppPreferenceKey.meetingNotesBetaEnabled,
        AppPreferenceKey.hotkeyTriggerMode,
        AppPreferenceKey.hotkeyDistinguishModifierSides,
        AppPreferenceKey.hotkeyPreset,
        AppPreferenceKey.hotkeyCaptureInProgress
    ]

    private var savedDefaults: [String: Any] = [:]
    private var missingDefaultKeys = Set<String>()

    override func setUp() {
        super.setUp()

        let defaults = UserDefaults.standard
        savedDefaults = [:]
        missingDefaultKeys = []

        for key in managedDefaultKeys {
            if let value = defaults.object(forKey: key) {
                savedDefaults[key] = value
            } else {
                missingDefaultKeys.insert(key)
            }
        }

        managedDefaultKeys.forEach { defaults.removeObject(forKey: $0) }
        HotkeyPreference.registerDefaults()
        defaults.set(false, forKey: AppPreferenceKey.meetingNotesBetaEnabled)
        defaults.set(HotkeyPreference.TriggerMode.tap.rawValue, forKey: AppPreferenceKey.hotkeyTriggerMode)
        defaults.set(false, forKey: AppPreferenceKey.hotkeyCaptureInProgress)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard

        for key in managedDefaultKeys {
            if let value = savedDefaults[key] {
                defaults.set(value, forKey: key)
            } else if missingDefaultKeys.contains(key) {
                defaults.removeObject(forKey: key)
            }
        }

        savedDefaults = [:]
        missingDefaultKeys = []
        super.tearDown()
    }

    private func makeManager() -> HotkeyManager {
        let manager = HotkeyManager()
        Self.retainedManagers.append(manager)
        return manager
    }

    func testStaleFnStateIsResetBeforeFreshTapStartsTranscription() async {
        let manager = makeManager()
        var transcriptionDownCount = 0
        let callbackExpectation = expectation(description: "transcription callback")
        manager.onKeyDown = {
            transcriptionDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingSetTransientState(
            isKeyDown: true,
            hasTranscriptionModifierTapCandidate: true
        )

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskSecondaryFn
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: []
        )
        await fulfillment(of: [callbackExpectation], timeout: 1.0)

        XCTAssertEqual(transcriptionDownCount, 1)
    }

    func testResetTransientStateClearsTransientStateWithoutEmittingCallbacks() {
        let manager = makeManager()
        var transcriptionDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }
        manager.testingSetTransientState(
            isKeyDown: true,
            isTranslationKeyDown: true,
            hasTranscriptionModifierTapCandidate: true,
            hasTranslationModifierTapCandidate: true,
            sawNonModifierKeyDuringFunctionChord: true,
            currentSidedModifiers: .leftShift
        )

        manager.resetTransientState(reason: "unitTest")

        XCTAssertEqual(transcriptionDownCount, 0)
        XCTAssertEqual(
            manager.testingTransientStateSnapshot(),
            .init(
                isKeyDown: false,
                isTranslationKeyDown: false,
                isRewriteKeyDown: false,
                isMeetingKeyDown: false,
                isCustomPasteKeyDown: false,
                hasTranscriptionModifierTapCandidate: false,
                hasTranslationModifierTapCandidate: false,
                hasRewriteModifierTapCandidate: false,
                hasMeetingModifierTapCandidate: false,
                hasCustomPasteModifierTapCandidate: false,
                sawNonModifierKeyDuringFunctionChord: false,
                currentSidedModifiers: []
            )
        )
    }

    func testTranslationComboStillWinsAfterRecoveryReset() async {
        let manager = makeManager()
        var transcriptionDownCount = 0
        var translationDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }
        let callbackExpectation = expectation(description: "translation callback")
        manager.onTranslationKeyDown = {
            translationDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingSetTransientState(
            isRewriteKeyDown: true,
            hasRewriteModifierTapCandidate: true,
            currentSidedModifiers: .rightControl
        )
        manager.resetTransientState(reason: "unitTest")

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Shift),
            flags: .maskShift
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: combinedFlags(.maskShift, .maskSecondaryFn)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskShift
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Shift),
            flags: []
        )
        await fulfillment(of: [callbackExpectation], timeout: 1.0)

        XCTAssertEqual(transcriptionDownCount, 0)
        XCTAssertEqual(translationDownCount, 1)
    }

    func testDefaultTranslationModifierTapEmitsDedicatedCallback() async {
        let manager = makeManager()
        var transcriptionDownCount = 0
        var translationDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }
        let callbackExpectation = expectation(description: "translation callback")
        manager.onTranslationKeyDown = {
            translationDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Shift),
            flags: .maskShift
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: combinedFlags(.maskShift, .maskSecondaryFn)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskShift
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Shift),
            flags: []
        )
        await fulfillment(of: [callbackExpectation], timeout: 1.0)

        XCTAssertEqual(transcriptionDownCount, 0)
        XCTAssertEqual(translationDownCount, 1)
    }

    func testTranslationTapCallbackCanReenterEventHandlingWithoutExclusivityViolation() async {
        let manager = makeManager()
        var translationDownCount = 0
        let callbackExpectation = expectation(description: "translation callback")
        manager.onTranslationKeyDown = {
            translationDownCount += 1
            manager.testingHandleEvent(
                type: .keyDown,
                keyCode: UInt16(kVK_ANSI_V),
                flags: self.combinedFlags(.maskShift, .maskSecondaryFn)
            )
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Shift),
            flags: .maskShift
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: combinedFlags(.maskShift, .maskSecondaryFn)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskShift
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Shift),
            flags: []
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(translationDownCount, 1)
    }

    func testDefaultRewriteModifierTapEmitsDedicatedCallback() async {
        let manager = makeManager()
        var transcriptionDownCount = 0
        var rewriteDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }
        let callbackExpectation = expectation(description: "rewrite callback")
        manager.onRewriteKeyDown = {
            rewriteDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Control),
            flags: .maskControl
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: combinedFlags(.maskControl, .maskSecondaryFn)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskControl
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Control),
            flags: []
        )
        await fulfillment(of: [callbackExpectation], timeout: 1.0)

        XCTAssertEqual(transcriptionDownCount, 0)
        XCTAssertEqual(rewriteDownCount, 1)
    }

    func testDefaultMeetingModifierTapEmitsDedicatedCallback() async {
        UserDefaults.standard.set(true, forKey: AppPreferenceKey.meetingNotesBetaEnabled)

        let manager = makeManager()
        var transcriptionDownCount = 0
        var meetingDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }
        let callbackExpectation = expectation(description: "meeting callback")
        manager.onMeetingKeyDown = {
            meetingDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Option),
            flags: .maskAlternate
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: combinedFlags(.maskAlternate, .maskSecondaryFn)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskAlternate
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Option),
            flags: []
        )
        await fulfillment(of: [callbackExpectation], timeout: 1.0)

        XCTAssertEqual(transcriptionDownCount, 0)
        XCTAssertEqual(meetingDownCount, 1)
    }

    func testDisabledMeetingModeDoesNotEmitMeetingCallback() {
        UserDefaults.standard.set(false, forKey: AppPreferenceKey.meetingNotesBetaEnabled)

        let manager = makeManager()
        var meetingDownCount = 0
        manager.onMeetingKeyDown = {
            meetingDownCount += 1
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Option),
            flags: .maskAlternate
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: combinedFlags(.maskAlternate, .maskSecondaryFn)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskAlternate
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Option),
            flags: []
        )

        XCTAssertEqual(meetingDownCount, 0)
    }

    func testDisabledMeetingModeFnOptionDoesNotFallBackToTranscription() {
        UserDefaults.standard.set(false, forKey: AppPreferenceKey.meetingNotesBetaEnabled)

        let manager = makeManager()
        var transcriptionDownCount = 0
        var meetingDownCount = 0
        manager.onKeyDown = {
            transcriptionDownCount += 1
        }
        manager.onMeetingKeyDown = {
            meetingDownCount += 1
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Option),
            flags: .maskAlternate
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: combinedFlags(.maskAlternate, .maskSecondaryFn)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskAlternate
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Option),
            flags: []
        )

        XCTAssertEqual(transcriptionDownCount, 0)
        XCTAssertEqual(meetingDownCount, 0)
    }

    func testIdleGapRecoveryClearsStaleChordStateBeforeFnRelease() async {
        let manager = makeManager()
        var transcriptionDownCount = 0
        let callbackExpectation = expectation(description: "transcription callback")
        manager.onKeyDown = {
            transcriptionDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingSetTransientState(
            sawNonModifierKeyDuringFunctionChord: true
        )
        manager.testingSetLastEventAt(Date().addingTimeInterval(-5))

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: []
        )
        await fulfillment(of: [callbackExpectation], timeout: 1.0)

        XCTAssertEqual(transcriptionDownCount, 1)
    }

    func testPlainFnTapEmitsSingleTranscriptionCallback() async {
        let manager = makeManager()
        var transcriptionDownCount = 0
        let callbackExpectation = expectation(description: "transcription callback")
        manager.onKeyDown = {
            transcriptionDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskSecondaryFn
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: []
        )
        await fulfillment(of: [callbackExpectation], timeout: 1.0)

        XCTAssertEqual(transcriptionDownCount, 1)
    }

    func testPlainFnTapStillWorksWhenDistinguishingModifierSidesIsEnabledAndPresetIsCustom() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: AppPreferenceKey.hotkeyPreset)

        let manager = makeManager()
        var transcriptionDownCount = 0
        let callbackExpectation = expectation(description: "transcription callback with side distinction enabled")
        manager.onKeyDown = {
            transcriptionDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskSecondaryFn
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: []
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(transcriptionDownCount, 1)
    }

    func testLegacyStoredFunctionKeyHotkeyStillTriggersFnTap() async {
        let defaults = UserDefaults.standard
        defaults.set(Int(UInt16(kVK_Function)), forKey: AppPreferenceKey.hotkeyKeyCode)
        defaults.set(Int(NSEvent.ModifierFlags.function.rawValue), forKey: AppPreferenceKey.hotkeyModifiers)
        defaults.set(0, forKey: AppPreferenceKey.hotkeySidedModifiers)
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: AppPreferenceKey.hotkeyPreset)

        let manager = makeManager()
        var transcriptionDownCount = 0
        let callbackExpectation = expectation(description: "legacy fn transcription callback")
        manager.onKeyDown = {
            transcriptionDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskSecondaryFn
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: []
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(transcriptionDownCount, 1)
    }

    func testModifierOnlyCustomPasteDoesNotBlockFnTapTranscription() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferenceKey.customPasteHotkeyEnabled)
        defaults.set(Int(HotkeyPreference.modifierOnlyKeyCode), forKey: AppPreferenceKey.customPasteHotkeyKeyCode)
        defaults.set(Int(NSEvent.ModifierFlags.command.rawValue), forKey: AppPreferenceKey.customPasteHotkeyModifiers)
        defaults.set(SidedModifierFlags.rightCommand.rawValue, forKey: AppPreferenceKey.customPasteHotkeySidedModifiers)
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: AppPreferenceKey.hotkeyPreset)

        let manager = makeManager()
        var transcriptionDownCount = 0
        let callbackExpectation = expectation(description: "fn transcription callback with modifier-only custom paste enabled")
        manager.onKeyDown = {
            transcriptionDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskSecondaryFn
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: []
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(transcriptionDownCount, 1)
    }

    func testModifierOnlyCustomPasteStillTriggersWithRightCommand() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferenceKey.customPasteHotkeyEnabled)
        defaults.set(Int(HotkeyPreference.modifierOnlyKeyCode), forKey: AppPreferenceKey.customPasteHotkeyKeyCode)
        defaults.set(Int(NSEvent.ModifierFlags.command.rawValue), forKey: AppPreferenceKey.customPasteHotkeyModifiers)
        defaults.set(SidedModifierFlags.rightCommand.rawValue, forKey: AppPreferenceKey.customPasteHotkeySidedModifiers)
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: AppPreferenceKey.hotkeyPreset)

        let manager = makeManager()
        var customPasteDownCount = 0
        let callbackExpectation = expectation(description: "right-command custom paste callback")
        manager.onCustomPasteKeyDown = {
            customPasteDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: commandFlags(for: .rightCommand)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: []
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(customPasteDownCount, 1)
    }

    func testControlCommandVCustomPasteStillTriggersUnderCommandPresetWithRightCommand() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferenceKey.customPasteHotkeyEnabled)
        defaults.set(Int(UInt16(kVK_ANSI_V)), forKey: AppPreferenceKey.customPasteHotkeyKeyCode)
        defaults.set(Int(NSEvent.ModifierFlags([.control, .command]).rawValue), forKey: AppPreferenceKey.customPasteHotkeyModifiers)
        defaults.set(0, forKey: AppPreferenceKey.customPasteHotkeySidedModifiers)
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.commandCombo.rawValue, forKey: AppPreferenceKey.hotkeyPreset)
        HotkeyPreference.save(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.command],
            sidedModifiers: [.rightCommand]
        )

        let manager = makeManager()
        var customPasteDownCount = 0
        let callbackExpectation = expectation(description: "control-command-v custom paste callback under command preset")
        manager.onCustomPasteKeyDown = {
            customPasteDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Control),
            flags: .maskControl
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: commandFlags(for: .rightCommand).union(.maskControl)
        )
        manager.testingHandleEvent(
            type: .keyDown,
            keyCode: UInt16(kVK_ANSI_V),
            flags: commandFlags(for: .rightCommand).union(.maskControl)
        )
        manager.testingHandleEvent(
            type: .keyUp,
            keyCode: UInt16(kVK_ANSI_V),
            flags: commandFlags(for: .rightCommand).union(.maskControl)
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(customPasteDownCount, 1)
    }

    func testCustomPasteChordWinsOverMeetingWhenHotkeysConflict() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferenceKey.customPasteHotkeyEnabled)
        defaults.set(true, forKey: AppPreferenceKey.meetingNotesBetaEnabled)
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: AppPreferenceKey.hotkeyPreset)

        HotkeyPreference.save(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.command],
            sidedModifiers: [.rightCommand]
        )
        HotkeyPreference.saveMeeting(
            keyCode: UInt16(kVK_ANSI_L),
            modifiers: [.command],
            sidedModifiers: [.rightCommand]
        )
        HotkeyPreference.saveCustomPaste(
            keyCode: UInt16(kVK_ANSI_L),
            modifiers: [.command],
            sidedModifiers: []
        )

        let manager = makeManager()
        var customPasteDownCount = 0
        var meetingDownCount = 0
        let callbackExpectation = expectation(description: "custom paste wins conflict with meeting")
        manager.onCustomPasteKeyDown = {
            customPasteDownCount += 1
            callbackExpectation.fulfill()
        }
        manager.onMeetingKeyDown = {
            meetingDownCount += 1
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: commandFlags(for: .rightCommand)
        )
        manager.testingHandleEvent(
            type: .keyDown,
            keyCode: UInt16(kVK_ANSI_L),
            flags: commandFlags(for: .rightCommand)
        )
        manager.testingHandleEvent(
            type: .keyUp,
            keyCode: UInt16(kVK_ANSI_L),
            flags: commandFlags(for: .rightCommand)
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(customPasteDownCount, 1)
        XCTAssertEqual(meetingDownCount, 0)
    }

    func testRightCommandTapRemainsStableAcrossDuplicateFlagsChangedEvents() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: AppPreferenceKey.hotkeyPreset)
        HotkeyPreference.save(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.command],
            sidedModifiers: [.rightCommand]
        )

        let manager = makeManager()
        var transcriptionDownCount = 0
        let callbackExpectation = expectation(description: "two transcription callbacks")
        callbackExpectation.expectedFulfillmentCount = 2
        manager.onKeyDown = {
            transcriptionDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: commandFlags(for: .rightCommand)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: commandFlags(for: .rightCommand)
        )

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: []
        )

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: commandFlags(for: .rightCommand)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: commandFlags(for: .rightCommand)
        )

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: []
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(transcriptionDownCount, 2)
    }

    func testLeftCommandDoesNotTriggerRightCommandTapHotkey() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: AppPreferenceKey.hotkeyPreset)
        HotkeyPreference.save(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.command],
            sidedModifiers: [.rightCommand]
        )

        let manager = makeManager()
        var transcriptionDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Command),
            flags: commandFlags(for: .leftCommand)
        )

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Command),
            flags: []
        )

        XCTAssertEqual(transcriptionDownCount, 0)
    }

    func testCustomRightShiftTapRemainsStableAcrossDuplicateFlagsChangedEvents() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: AppPreferenceKey.hotkeyPreset)
        HotkeyPreference.save(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.shift],
            sidedModifiers: [.rightShift]
        )

        let manager = makeManager()
        var transcriptionDownCount = 0
        let callbackExpectation = expectation(description: "two right-shift callbacks")
        callbackExpectation.expectedFulfillmentCount = 2
        manager.onKeyDown = {
            transcriptionDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightShift),
            flags: shiftFlags(for: .rightShift)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightShift),
            flags: shiftFlags(for: .rightShift)
        )

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightShift),
            flags: []
        )

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightShift),
            flags: shiftFlags(for: .rightShift)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightShift),
            flags: shiftFlags(for: .rightShift)
        )

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightShift),
            flags: []
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(transcriptionDownCount, 2)
    }

    func testIdleGapRecoveryDoesNotSwallowFirstRightCommandTap() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: AppPreferenceKey.hotkeyPreset)
        HotkeyPreference.save(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.command],
            sidedModifiers: [.rightCommand]
        )

        let manager = makeManager()
        var transcriptionDownCount = 0
        let callbackExpectation = expectation(description: "first tap survives idle recovery")
        manager.onKeyDown = {
            transcriptionDownCount += 1
            callbackExpectation.fulfill()
        }

        manager.testingSetTransientState(currentSidedModifiers: .rightCommand)
        manager.testingSetLastEventAt(Date().addingTimeInterval(-5))

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: commandFlags(for: .rightCommand)
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_RightCommand),
            flags: []
        )

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(transcriptionDownCount, 1)
    }

    func testFnTapReleaseIsSuppressedAfterNonModifierChordState() {
        let manager = makeManager()
        var transcriptionDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }

        manager.testingSetTransientState(
            sawNonModifierKeyDuringFunctionChord: true
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: []
        )

        XCTAssertEqual(transcriptionDownCount, 0)
    }

    func testLongPressFnEmitsDownThenUp() async {
        let defaults = UserDefaults.standard
        defaults.set(HotkeyPreference.TriggerMode.longPress.rawValue, forKey: AppPreferenceKey.hotkeyTriggerMode)

        let manager = makeManager()
        var events: [String] = []
        manager.onKeyDown = { events.append("down") }
        manager.onKeyUp = { events.append("up") }

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: .maskSecondaryFn
        )
        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: []
        )

        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(events, ["down", "up"])
    }

    private func combinedFlags(_ flags: CGEventFlags...) -> CGEventFlags {
        flags.reduce([]) { partialResult, next in
            partialResult.union(next)
        }
    }

    private func commandFlags(for side: SidedModifierFlags) -> CGEventFlags {
        switch side {
        case .leftCommand:
            return CGEventFlags(rawValue: UInt64(NX_COMMANDMASK | NX_DEVICELCMDKEYMASK))
        case .rightCommand:
            return CGEventFlags(rawValue: UInt64(NX_COMMANDMASK | NX_DEVICERCMDKEYMASK))
        default:
            XCTFail("Unsupported command side \(side)")
            return []
        }
    }

    private func shiftFlags(for side: SidedModifierFlags) -> CGEventFlags {
        switch side {
        case .leftShift:
            return CGEventFlags(rawValue: UInt64(NX_SHIFTMASK | NX_DEVICELSHIFTKEYMASK))
        case .rightShift:
            return CGEventFlags(rawValue: UInt64(NX_SHIFTMASK | NX_DEVICERSHIFTKEYMASK))
        default:
            XCTFail("Unsupported shift side \(side)")
            return []
        }
    }
}

import XCTest
import Carbon
import ApplicationServices
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
                hasTranscriptionModifierTapCandidate: false,
                hasTranslationModifierTapCandidate: false,
                hasRewriteModifierTapCandidate: false,
                hasMeetingModifierTapCandidate: false,
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
}

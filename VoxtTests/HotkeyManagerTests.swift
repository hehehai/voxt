import XCTest
import Carbon
import ApplicationServices
@testable import Voxt

@MainActor
final class HotkeyManagerTests: XCTestCase {
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

    func testStaleFnStateIsResetBeforeFreshTapStartsTranscription() {
        let manager = HotkeyManager()
        var transcriptionDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }

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

        XCTAssertEqual(transcriptionDownCount, 1)
    }

    func testTapDisabledEventClearsTransientStateWithoutEmittingCallbacks() {
        let manager = HotkeyManager()
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

        manager.testingHandleEvent(
            type: .tapDisabledByTimeout,
            keyCode: UInt16(kVK_Function),
            flags: []
        )

        XCTAssertEqual(transcriptionDownCount, 0)
        XCTAssertEqual(
            manager.testingTransientStateSnapshot(),
            .init(
                isKeyDown: false,
                isTranslationKeyDown: false,
                isRewriteKeyDown: false,
                hasTranscriptionModifierTapCandidate: false,
                hasTranslationModifierTapCandidate: false,
                hasRewriteModifierTapCandidate: false,
                sawNonModifierKeyDuringFunctionChord: false,
                currentSidedModifiers: []
            )
        )
    }

    func testTranslationComboStillWinsAfterRecoveryReset() {
        let manager = HotkeyManager()
        var transcriptionDownCount = 0
        var translationDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }
        manager.onTranslationKeyDown = { translationDownCount += 1 }

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

        XCTAssertEqual(transcriptionDownCount, 0)
        XCTAssertEqual(translationDownCount, 1)
    }

    func testIdleGapRecoveryClearsStaleChordStateBeforeFnRelease() {
        let manager = HotkeyManager()
        var transcriptionDownCount = 0
        manager.onKeyDown = { transcriptionDownCount += 1 }

        manager.testingSetTransientState(
            sawNonModifierKeyDuringFunctionChord: true
        )
        manager.testingSetLastEventAt(Date().addingTimeInterval(-5))

        manager.testingHandleEvent(
            type: .flagsChanged,
            keyCode: UInt16(kVK_Function),
            flags: []
        )

        XCTAssertEqual(transcriptionDownCount, 1)
    }

    private func combinedFlags(_ flags: CGEventFlags...) -> CGEventFlags {
        flags.reduce([]) { partialResult, next in
            partialResult.union(next)
        }
    }
}

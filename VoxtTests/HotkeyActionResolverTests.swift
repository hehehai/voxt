import XCTest
@testable import Voxt

final class HotkeyActionResolverTests: XCTestCase {
    func testTapTranscriptionDownStartsWhenIdle() {
        let actions = HotkeyActionResolver.resolveTranscriptionDown(
            state: makeState(triggerMode: .tap, isSessionActive: false)
        )

        XCTAssertEqual(actions, [.startTranscription])
    }

    func testTapTranscriptionDownStopsWhenActiveAndAllowed() {
        let actions = HotkeyActionResolver.resolveTranscriptionDown(
            state: makeState(triggerMode: .tap, isSessionActive: true, canStopTapSession: true)
        )

        XCTAssertEqual(actions, [.stopRecording])
    }

    func testLongPressTranscriptionDownSchedulesStartWhenIdle() {
        let actions = HotkeyActionResolver.resolveTranscriptionDown(
            state: makeState(triggerMode: .longPress, isSessionActive: false)
        )

        XCTAssertEqual(actions, [.scheduleTranscriptionStart])
    }

    func testLongPressTranscriptionUpCancelsPendingStart() {
        let actions = HotkeyActionResolver.resolveTranscriptionUp(
            state: makeState(
                triggerMode: .longPress,
                isSessionActive: false,
                hasPendingTranscriptionStart: true
            )
        )

        XCTAssertEqual(actions, [.cancelPendingTranscriptionStart])
    }

    func testLongPressTranscriptionUpStopsOnlyActiveTranscriptionSession() {
        let actions = HotkeyActionResolver.resolveTranscriptionUp(
            state: makeState(
                triggerMode: .longPress,
                isSessionActive: true,
                sessionOutputMode: .transcription
            )
        )

        XCTAssertEqual(actions, [.stopRecording])
    }

    func testTranslationDownCancelsPendingAndStartsTranslationWhenIdle() {
        let actions = HotkeyActionResolver.resolveTranslationDown(
            state: makeState(
                triggerMode: .tap,
                isSessionActive: false,
                hasPendingTranscriptionStart: true
            )
        )

        XCTAssertEqual(actions, [.cancelPendingTranscriptionStart, .startTranslation])
    }

    func testTranslationUpIgnoresSelectedTextTranslationFlow() {
        let actions = HotkeyActionResolver.resolveTranslationUp(
            state: makeState(
                triggerMode: .longPress,
                isSessionActive: true,
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true
            )
        )

        XCTAssertEqual(actions, [.ignore])
    }

    private func makeState(
        triggerMode: HotkeyPreference.TriggerMode,
        isSessionActive: Bool,
        sessionOutputMode: AppDelegate.SessionOutputMode = .transcription,
        hasPendingTranscriptionStart: Bool = false,
        isSelectedTextTranslationFlow: Bool = false,
        canStopTapSession: Bool = false
    ) -> HotkeyActionResolver.State {
        HotkeyActionResolver.State(
            triggerMode: triggerMode,
            isSessionActive: isSessionActive,
            sessionOutputMode: sessionOutputMode,
            hasPendingTranscriptionStart: hasPendingTranscriptionStart,
            isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
            canStopTapSession: canStopTapSession
        )
    }
}

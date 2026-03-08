import Foundation

struct HotkeyActionResolver {
    enum Action {
        case ignore
        case stopRecording
        case startTranscription
        case startTranslation
        case scheduleTranscriptionStart
        case cancelPendingTranscriptionStart
    }

    struct State {
        let triggerMode: HotkeyPreference.TriggerMode
        let isSessionActive: Bool
        let sessionOutputMode: AppDelegate.SessionOutputMode
        let hasPendingTranscriptionStart: Bool
        let isSelectedTextTranslationFlow: Bool
        let canStopTapSession: Bool
    }

    static func resolveTranscriptionDown(state: State) -> [Action] {
        switch state.triggerMode {
        case .longPress:
            guard !state.isSessionActive else { return [.ignore] }
            return [.scheduleTranscriptionStart]
        case .tap:
            if state.isSessionActive {
                return state.canStopTapSession ? [.stopRecording] : [.ignore]
            }
            return [.startTranscription]
        }
    }

    static func resolveTranscriptionUp(state: State) -> [Action] {
        guard state.triggerMode == .longPress else { return [.ignore] }
        if state.hasPendingTranscriptionStart {
            return [.cancelPendingTranscriptionStart]
        }
        guard state.isSessionActive, state.sessionOutputMode == .transcription else {
            return [.ignore]
        }
        return [.stopRecording]
    }

    static func resolveTranslationDown(state: State) -> [Action] {
        var actions: [Action] = [.cancelPendingTranscriptionStart]
        guard !state.isSessionActive else {
            actions.append(.ignore)
            return actions
        }

        switch state.triggerMode {
        case .longPress:
            actions.append(.startTranslation)
        case .tap:
            actions.append(.startTranslation)
        }
        return actions
    }

    static func resolveTranslationUp(state: State) -> [Action] {
        guard state.triggerMode == .longPress else { return [.ignore] }
        guard !state.isSelectedTextTranslationFlow else { return [.ignore] }
        guard state.isSessionActive, state.sessionOutputMode == .translation else {
            return [.ignore]
        }
        return [.stopRecording]
    }
}

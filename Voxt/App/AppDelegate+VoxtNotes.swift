import Foundation
import AppKit
import Carbon

extension AppDelegate {
    enum TranscriptionCaptureSessionMode {
        case standard
        case noteSession
    }

    func configureVoxtNoteSessionRuntimeStateForNewRecording() {
        transcriptionCaptureSessionMode = .standard
        liveTranscriptSegmentationState.reset()
        overlayState.setTranscribedTextTransformer { [weak self] rawText in
            self?.resolvedLiveTranscriptDisplayText(from: rawText) ?? rawText
        }
    }

    func resetVoxtNoteSessionRuntimeState() {
        transcriptionCaptureSessionMode = .standard
        liveTranscriptSegmentationState.reset()
        overlayState.setTranscribedTextTransformer(nil)
    }

    func shouldHandleLiveTranscriptNoteShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard !event.isARepeat else { return false }
        guard noteFeatureSettings.enabled else { return false }
        let shortcut = noteFeatureSettings.triggerShortcut.hotkey
        guard event.keyCode == shortcut.keyCode else { return false }
        let modifiers = event.modifierFlags.intersection(.hotkeyRelevant)
        guard modifiers == shortcut.modifiers else { return false }
        guard isSessionActive, sessionOutputMode == .transcription else { return false }
        guard overlayState.displayMode != .answer else { return false }
        return isCurrentTranscriptionCaptureLive
    }

    @discardableResult
    func captureLiveTranscriptNoteIfPossible(reason: String) -> Bool {
        guard noteFeatureSettings.enabled else { return false }
        guard isSessionActive, sessionOutputMode == .transcription else { return false }
        let rawText = currentSessionRawTranscribedText()
        let capturedText = liveTranscriptSegmentationState.freezeCurrentSegment(
            using: rawText,
            markerLabel: voxtNoteBoundaryMarkerLabel()
        )
            ?? overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            VoxtLog.info("Voxt note capture skipped because current transcript tail is empty. reason=\(reason)")
            return false
        }

        transcriptionCaptureSessionMode = .noteSession
        if noteFeatureSettings.soundEnabled {
            interactionSoundPlayer.playNote(preset: noteFeatureSettings.soundPreset)
        }
        appendVoxtNote(text: trimmedText, sessionID: activeRecordingSessionID)
        refreshVoxtNoteTranscriptDisplay()
        VoxtLog.info("Voxt note captured. reason=\(reason), characters=\(trimmedText.count)")
        return true
    }

    @discardableResult
    func captureTrailingVoxtNoteIfNeeded(finalRawText: String) -> Bool {
        guard transcriptionCaptureSessionMode == .noteSession else { return false }
        let trimmedFinalText = finalRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFinalText.isEmpty else { return false }

        let capturedText = liveTranscriptSegmentationState.freezeCurrentSegment(using: trimmedFinalText)
        let trimmedCapturedText = capturedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCapturedText.isEmpty else {
            refreshVoxtNoteTranscriptDisplay()
            return false
        }

        appendVoxtNote(text: trimmedCapturedText, sessionID: activeRecordingSessionID)
        refreshVoxtNoteTranscriptDisplay()
        VoxtLog.info("Voxt note trailing segment captured at session end. characters=\(trimmedCapturedText.count)")
        return true
    }

    func refreshVoxtNoteTranscriptDisplay() {
        overlayState.refreshDisplayedTranscribedText()
    }

    var isCurrentTranscriptionNoteSessionActive: Bool {
        transcriptionCaptureSessionMode == .noteSession
    }

    private var isCurrentTranscriptionCaptureLive: Bool {
        guard recordingStoppedAt == nil else { return false }
        switch transcriptionEngine {
        case .dictation:
            return speechTranscriber.isRecording
        case .mlxAudio:
            return mlxTranscriber?.isRecording == true
        case .whisperKit:
            return whisperTranscriber?.isRecording == true
        case .remote:
            return remoteASRTranscriber.isRecording
        }
    }

    private func resolvedLiveTranscriptDisplayText(from rawText: String) -> String {
        guard isSessionActive, sessionOutputMode == .transcription else {
            return rawText
        }
        guard transcriptionCaptureSessionMode == .noteSession else {
            return rawText
        }
        return liveTranscriptSegmentationState.displayText(for: rawText)
    }

    func currentSessionRawTranscribedText() -> String {
        switch transcriptionEngine {
        case .dictation:
            return speechTranscriber.transcribedText
        case .mlxAudio:
            return mlxTranscriber?.transcribedText ?? ""
        case .whisperKit:
            return whisperTranscriber?.transcribedText ?? ""
        case .remote:
            return remoteASRTranscriber.transcribedText
        }
    }

    private func voxtNoteBoundaryMarkerLabel() -> String {
        guard let recordingStartedAt else { return "00:00" }
        let elapsed = max(0, Int(Date().timeIntervalSince(recordingStartedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

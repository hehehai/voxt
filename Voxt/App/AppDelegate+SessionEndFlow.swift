import AppKit
import Foundation

extension AppDelegate {
    enum SessionEndExecutionDecision: Equatable {
        case execute
        case skipDuplicateInFlight
        case skipAlreadyCompleted
    }

    @MainActor
    private protocol SessionEndStage {
        var name: String { get }
        func run(delegate: AppDelegate)
    }

    private struct HideOverlayStage: SessionEndStage {
        var name: String { "hideOverlay" }

        func run(delegate: AppDelegate) {
            guard delegate.overlayState.displayMode != .answer else { return }
            delegate.overlayWindow.hide(animated: false)
        }
    }

    private struct RestoreSystemAudioStage: SessionEndStage {
        var name: String { "restoreSystemAudio" }

        func run(delegate: AppDelegate) {
            delegate.systemAudioMuteController.restoreSystemAudioIfNeeded()
        }
    }

    private struct PlayEndSoundStage: SessionEndStage {
        var name: String { "playEndSound" }

        func run(delegate: AppDelegate) {
            guard delegate.interactionSoundsEnabled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                delegate.interactionSoundPlayer.playEnd()
            }
        }
    }

    private struct ResetSessionStateStage: SessionEndStage {
        var name: String { "resetSessionState" }

        func run(delegate: AppDelegate) {
            let shouldPreserveTranslationAnswerControls =
                delegate.sessionOutputMode == .translation &&
                delegate.overlayState.displayMode == .answer

            delegate.activeRecordingSessionID = UUID()
            delegate.isSessionActive = false
            delegate.sessionOutputMode = .transcription
            delegate.isSelectedTextTranslationFlow = false
            if !shouldPreserveTranslationAnswerControls {
                delegate.sessionTargetApplicationPID = nil
                delegate.sessionTargetApplicationBundleID = nil
                delegate.selectedTextTranslationHadWritableFocusedInput = false
            }
            delegate.enhancementContextSnapshot = nil
            delegate.rewriteSessionHasSelectedSourceText = false
            delegate.rewriteSessionHadWritableFocusedInput = false
            delegate.rewriteSessionFallbackInjectBundleID = nil
            delegate.sessionTranslationTargetLanguageOverride = nil
            delegate.activeSessionTranslationProviderResolution = nil
            delegate.sessionUsesWhisperDirectTranslation = false
            delegate.resetVoxtNoteSessionRuntimeState()
            if !shouldPreserveTranslationAnswerControls {
                delegate.overlayState.configureSessionTranslationTargetLanguage(nil, allowsSwitching: false)
            }
            delegate.overlayState.isCompleting = false
            if delegate.overlayState.displayMode != .answer {
                delegate.overlayState.reset()
            }
            delegate.pendingSessionFinishTask = nil
        }
    }

    private struct ReleaseResidualCaptureStage: SessionEndStage {
        var name: String { "releaseResidualCapture" }

        func run(delegate: AppDelegate) {
            delegate.releaseResidualRecordingResources(reason: "session-end-pipeline")
        }
    }

    nonisolated static func sessionEndExecutionDecision(
        requestedSessionID: UUID,
        currentEndingSessionID: UUID?,
        lastCompletedSessionEndSessionID: UUID?
    ) -> SessionEndExecutionDecision {
        if currentEndingSessionID == requestedSessionID {
            return .skipDuplicateInFlight
        }
        if lastCompletedSessionEndSessionID == requestedSessionID {
            return .skipAlreadyCompleted
        }
        return .execute
    }

    private func beginSessionEndExecution(for sessionID: UUID, trigger: String) -> Bool {
        let decision = Self.sessionEndExecutionDecision(
            requestedSessionID: sessionID,
            currentEndingSessionID: currentEndingSessionID,
            lastCompletedSessionEndSessionID: lastCompletedSessionEndSessionID
        )
        switch decision {
        case .execute:
            currentEndingSessionID = sessionID
            return true
        case .skipDuplicateInFlight:
            VoxtLog.info(
                "Session end pipeline ignored because the same session is already ending. sessionID=\(sessionID.uuidString), trigger=\(trigger)"
            )
            return false
        case .skipAlreadyCompleted:
            VoxtLog.info(
                "Session end pipeline ignored because the same session has already ended. sessionID=\(sessionID.uuidString), trigger=\(trigger)"
            )
            return false
        }
    }

    private func completeSessionEndExecution(for sessionID: UUID) {
        if currentEndingSessionID == sessionID {
            currentEndingSessionID = nil
        }
        lastCompletedSessionEndSessionID = sessionID
    }

    @MainActor
    func executeSessionEndPipeline(for sessionID: UUID, trigger: String) {
        guard beginSessionEndExecution(for: sessionID, trigger: trigger) else { return }
        defer {
            completeSessionEndExecution(for: sessionID)
        }

        VoxtLog.info(
            "Session end pipeline started. sessionID=\(sessionID.uuidString), trigger=\(trigger), displayMode=\(overlayState.displayMode), overlayVisible=\(overlayWindow.isVisible)"
        )
        let stages: [any SessionEndStage] = [
            HideOverlayStage(),
            RestoreSystemAudioStage(),
            PlayEndSoundStage(),
            ResetSessionStateStage(),
            ReleaseResidualCaptureStage()
        ]
        for stage in stages {
            stage.run(delegate: self)
        }
        VoxtLog.info(
            "Session end pipeline completed. sessionID=\(sessionID.uuidString), overlayVisible=\(overlayWindow.isVisible)"
        )
    }
}

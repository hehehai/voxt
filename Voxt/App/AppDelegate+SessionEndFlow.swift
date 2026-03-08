import Foundation

extension AppDelegate {
    private protocol SessionEndStage {
        var name: String { get }
        func run(delegate: AppDelegate)
    }

    private struct HideOverlayStage: SessionEndStage {
        var name: String { "hideOverlay" }

        func run(delegate: AppDelegate) {
            delegate.overlayWindow.hide()
        }
    }

    private struct PlayEndSoundStage: SessionEndStage {
        var name: String { "playEndSound" }

        func run(delegate: AppDelegate) {
            if delegate.interactionSoundsEnabled {
                delegate.interactionSoundPlayer.playEnd()
            }
        }
    }

    private struct ResetSessionStateStage: SessionEndStage {
        var name: String { "resetSessionState" }

        func run(delegate: AppDelegate) {
            delegate.isSessionActive = false
            delegate.sessionOutputMode = .transcription
            delegate.isSelectedTextTranslationFlow = false
            delegate.enhancementContextSnapshot = nil
            delegate.overlayState.isCompleting = false
            delegate.pendingSessionFinishTask = nil
        }
    }

    func executeSessionEndPipeline() {
        let stages: [any SessionEndStage] = [
            HideOverlayStage(),
            PlayEndSoundStage(),
            ResetSessionStateStage()
        ]
        for stage in stages {
            stage.run(delegate: self)
        }
    }
}

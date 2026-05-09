import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Speech

extension AppDelegate {
    enum StopRecordingFallbackDecision: Equatable {
        case finishNow
        case extendGrace(seconds: TimeInterval)
    }

    private struct LocalEngineFinalizationState: Equatable {
        let shouldDeferFallback: Bool
        let description: String
    }

    nonisolated static func stopRecordingFallbackDecision(
        transcriptionEngine: TranscriptionEngine,
        isLocalEngineFinalizing: Bool,
        transcriptionResultReceived: Bool,
        isExtendedGrace: Bool
    ) -> StopRecordingFallbackDecision {
        switch transcriptionEngine {
        case .whisperKit, .mlxAudio:
            break
        case .dictation, .remote:
            return .finishNow
        }
        guard isLocalEngineFinalizing else { return .finishNow }
        guard !transcriptionResultReceived else { return .finishNow }
        guard !isExtendedGrace else { return .finishNow }
        return .extendGrace(seconds: 12)
    }

    private func currentLocalEngineFinalizationState() -> LocalEngineFinalizationState {
        let whisperFinalizing = whisperTranscriber?.isFinalizingTranscription == true
        let mlxFinalizing = mlxTranscriber?.isFinalizingTranscription == true
        let resultReceived = transcriptionResultReceivedAt != nil

        switch transcriptionEngine {
        case .whisperKit:
            let shouldDefer = whisperFinalizing && !resultReceived
            return LocalEngineFinalizationState(
                shouldDeferFallback: shouldDefer,
                description: "whisper=\(whisperFinalizing), mlx=\(mlxFinalizing)"
            )
        case .mlxAudio:
            let shouldDefer = mlxFinalizing && !resultReceived
            return LocalEngineFinalizationState(
                shouldDeferFallback: shouldDefer,
                description: "whisper=\(whisperFinalizing), mlx=\(mlxFinalizing)"
            )
        case .dictation, .remote:
            return LocalEngineFinalizationState(
                shouldDeferFallback: false,
                description: "whisper=\(whisperFinalizing), mlx=\(mlxFinalizing)"
            )
        }
    }

    private func armStopRecordingFallback(
        timeoutSeconds: TimeInterval,
        isExtendedGrace: Bool = false
    ) {
        let armedSessionID = activeRecordingSessionID
        stopRecordingFallbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(timeoutSeconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard self.isSessionActive, self.activeRecordingSessionID == armedSessionID else { return }

            let finalizationState = self.currentLocalEngineFinalizationState()
            let fallbackDecision = Self.stopRecordingFallbackDecision(
                transcriptionEngine: self.transcriptionEngine,
                isLocalEngineFinalizing: finalizationState.shouldDeferFallback,
                transcriptionResultReceived: self.transcriptionResultReceivedAt != nil,
                isExtendedGrace: isExtendedGrace
            )
            if case .extendGrace(let graceSeconds) = fallbackDecision {
                VoxtLog.warning(
                    """
                    Stop recording fallback reached while local finalization is still running; extending grace. sessionID=\(armedSessionID.uuidString), engine=\(self.transcriptionEngine.rawValue), output=\(RecordingSessionSupport.outputLabel(for: self.sessionOutputMode)), finalizing=\(finalizationState.description)
                    """
                )
                self.armStopRecordingFallback(timeoutSeconds: graceSeconds, isExtendedGrace: true)
                return
            }

            VoxtLog.warning(
                """
                Stop recording fallback triggered; forcing session finish. sessionID=\(self.activeRecordingSessionID.uuidString), engine=\(self.transcriptionEngine.rawValue), output=\(RecordingSessionSupport.outputLabel(for: self.sessionOutputMode)), resultReceived=\(self.transcriptionResultReceivedAt != nil), endingSessionID=\(self.currentEndingSessionID?.uuidString ?? "nil"), finalizing=\(finalizationState.description)
                """
            )
            if self.transcriptionEngine == .remote {
                self.remoteASRTranscriber.discardPendingSessionOutput()
            }
            self.finishSession(after: 0)
        }
    }

    func continueRewriteConversation() {
        guard overlayState.canContinueRewriteAnswer else { return }
        overlayState.beginRewriteConversationIfNeeded()
        beginRecording(outputMode: .rewrite)
    }

    func releaseResidualRecordingResources(
        reason: String,
        preservePendingHistoryAudio: Bool = false
    ) {
        let speechWasRecording = speechTranscriber.isRecording
        let mlxWasRecording = mlxTranscriber?.isRecording == true
        let whisperWasRecording = whisperTranscriber?.isRecording == true
        let remoteWasRecording = remoteASRTranscriber.isRecording
        let hadPendingWhisperStartup = pendingWhisperStartupTask != nil

        if speechWasRecording || mlxWasRecording || whisperWasRecording || remoteWasRecording || hadPendingWhisperStartup {
            VoxtLog.warning(
                """
                Releasing residual recording resources. reason=\(reason), speech=\(speechWasRecording), mlx=\(mlxWasRecording), whisper=\(whisperWasRecording), remote=\(remoteWasRecording), pendingWhisperStartup=\(hadPendingWhisperStartup)
                """
            )
        }

        pendingWhisperStartupTask?.cancel()
        pendingWhisperStartupTask = nil
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil

        speechTranscriber.stopRecording()
        mlxTranscriber?.stopRecording()
        whisperTranscriber?.stopRecording()
        remoteASRTranscriber.discardPendingSessionOutput()
        if preservePendingHistoryAudio {
            VoxtLog.info("Preserving pending history audio during residual resource release. reason=\(reason)", verbose: true)
        } else {
            discardPendingCompletedHistoryAudio()
        }

        overlayState.isRecording = false
        overlayState.audioLevel = 0
    }

    func toggleRewriteConversationRecording() {
        guard overlayState.isRewriteConversationActive else { return }
        if isSessionActive {
            endRecording()
        } else {
            beginRecording(outputMode: .rewrite)
        }
    }

    func beginRecording(outputMode: SessionOutputMode) {
        VoxtLog.info(
            "Begin recording requested. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), isSessionActive=\(isSessionActive), isMeetingActive=\(meetingSessionCoordinator.isActive)"
        )
        pendingAutomaticDictionaryLearningTask?.cancel()
        guard !meetingSessionCoordinator.isActive else {
            VoxtLog.info(
                "Begin recording ignored because Meeting Notes is active. output=\(RecordingSessionSupport.outputLabel(for: outputMode))"
            )
            showOverlayStatus(
                String(localized: "Meeting Notes is currently active. Close it before starting another recording."),
                clearAfter: 2.2
            )
            return
        }
        guard !isSessionActive else {
            VoxtLog.info(
                "Begin recording ignored because a session is already active. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), activeOutput=\(RecordingSessionSupport.outputLabel(for: sessionOutputMode))"
            )
            return
        }
        releaseResidualRecordingResources(reason: "begin-recording")
        prepareLegacySettingsForSession(outputMode: outputMode)
        synchronizeRuntimeASRStateForSession(outputMode: outputMode)
        let localASRStartContext = currentLocalASRStartContext()
        let startDecision = RecordingStartPlanner.resolve(
            selectedEngine: transcriptionEngine,
            selectedMLXRepo: localASRStartContext.selectedMLXRepo,
            activeMLXDownloadRepo: localASRStartContext.activeMLXDownloadRepo,
            isSelectedMLXModelDownloaded: localASRStartContext.isSelectedMLXModelDownloaded,
            mlxModelState: localASRStartContext.mlxModelState,
            selectedWhisperModelID: localASRStartContext.selectedWhisperModelID,
            activeWhisperDownloadModelID: localASRStartContext.activeWhisperDownloadModelID,
            isSelectedWhisperModelDownloaded: localASRStartContext.isSelectedWhisperModelDownloaded,
            whisperModelState: localASRStartContext.whisperModelState
        )
        guard case .start(let recordingEngine) = startDecision else {
            if case .blocked(let reason) = startDecision {
                VoxtLog.warning("Recording start blocked: \(reason.logDescription)")
                showOverlayReminder(reason.userMessage)
            }
            return
        }
        guard preflightPermissionsForRecording(engine: recordingEngine) else {
            VoxtLog.info(
                "Begin recording blocked by preflight permissions. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), engine=\(recordingEngine.rawValue)"
            )
            return
        }

        cancelPendingFinishTasks()
        overlayState.isCompleting = false
        setEnhancingState(false)
        recordingStartedAt = Date()
        recordingStoppedAt = nil
        transcriptionProcessingStartedAt = nil
        transcriptionResultReceivedAt = nil
        didCommitSessionOutput = false
        isSessionCancellationRequested = false
        activeRecordingSessionID = UUID()
        currentEndingSessionID = nil
        lastCompletedSessionEndSessionID = nil
        sessionOutputMode = outputMode
        enhancementContextSnapshot = nil
        rewriteSessionHasSelectedSourceText = false
        resetSessionTranslationState()
        configureVoxtNoteSessionRuntimeStateForNewRecording()
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmostApplication?.bundleIdentifier
        let sessionTargetBundleID = RecordingSessionSupport.fallbackInjectBundleID(
            from: frontmostBundleID,
            ownBundleID: Bundle.main.bundleIdentifier
        )
        sessionTargetApplicationBundleID = sessionTargetBundleID
        sessionTargetApplicationPID = sessionTargetBundleID == nil ? nil : frontmostApplication?.processIdentifier
        let isContinuingRewriteConversation = outputMode == .rewrite && overlayState.isRewriteConversationActive
        rewriteSessionHadWritableFocusedInput = isContinuingRewriteConversation
            ? false
            : (outputMode == .rewrite ? hasWritableFocusedTextInput() : false)
        rewriteSessionFallbackInjectBundleID = outputMode == .rewrite ? sessionTargetBundleID : nil
        resetVoiceEndCommandState()

        VoxtLog.info(
            "Recording started. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), engine=\(recordingEngine.rawValue)"
        )
        if outputMode == .rewrite {
            VoxtLog.info(
                "Rewrite focused input check at session start. hasWritableFocusedInput=\(rewriteSessionHadWritableFocusedInput)"
            )
            VoxtLog.info(
                "Rewrite fallback inject target at session start. frontmostBundleID=\(frontmostBundleID ?? "nil"), fallbackBundleID=\(rewriteSessionFallbackInjectBundleID ?? "nil")"
            )
        }

        applyPreferredInputDevice()
        if isContinuingRewriteConversation {
            overlayState.clearPendingConversationUserPrompt()
            overlayState.statusMessage = ""
            overlayState.sessionIconMode = .rewrite
            overlayState.answerTitle = ""
            overlayState.answerContent = ""
            overlayState.isStreamingAnswer = false
            overlayState.isRecording = false
            overlayState.isEnhancing = false
            overlayState.isRequesting = false
            overlayState.isCompleting = false
            overlayState.audioLevel = 0
            overlayState.transcribedText = ""
            overlayState.displayMode = .answer
        } else {
            overlayState.reset()
            overlayState.statusMessage = ""
            overlayState.presentRecording(iconMode: RecordingSessionSupport.overlayIconMode(for: outputMode))
        }
        if outputMode == .translation {
            prepareMicrophoneTranslationSessionState()
        }

        isSessionActive = true
        pendingSystemAudioMuteTask?.cancel()
        pendingSystemAudioMuteTask = nil

        if muteSystemAudioWhileRecording {
            _ = systemAudioMuteController.muteSystemAudioIfNeeded()
        }
        if interactionSoundsEnabled {
            interactionSoundPlayer.playStart()
        }

        startRecordingCapture(using: recordingEngine)
    }

    func endRecording() {
        guard isSessionActive else { return }
        guard recordingStoppedAt == nil else {
            VoxtLog.hotkey("Recording stop ignored: session is already stopping.")
            return
        }
        VoxtLog.info("Recording stop requested.")

        if pendingWhisperStartupTask != nil, whisperTranscriber?.isRecording != true {
            pendingWhisperStartupTask?.cancel()
            pendingWhisperStartupTask = nil
            resetSessionAfterFailedStart()
            return
        }

        cancelActiveRecordingTasks()
        pendingSystemAudioMuteTask?.cancel()
        pendingSystemAudioMuteTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        recordingStoppedAt = Date()
        if transcriptionProcessingStartedAt == nil {
            transcriptionProcessingStartedAt = recordingStoppedAt
        }
        overlayState.presentProcessing(iconMode: RecordingSessionSupport.overlayIconMode(for: sessionOutputMode))
        voiceEndCommandState.lastDetectedCommand = false
        enhancementContextSnapshot = captureEnhancementContextSnapshot()
        stopActiveRecordingTranscriber()

        // Safety fallback: some engine/device combinations may occasionally fail to
        // report completion. Ensure the session/UI can always recover.
        let fallbackTimeoutSeconds = RecordingSessionSupport.stopRecordingFallbackTimeoutSeconds(
            transcriptionEngine: transcriptionEngine,
            remoteProvider: remoteASRSelectedProvider
        )
        armStopRecordingFallback(timeoutSeconds: fallbackTimeoutSeconds)
    }

    func cancelActiveRecordingSession() {
        guard isSessionActive else { return }
        VoxtLog.info("Recording cancelled by Escape key.")

        if pendingWhisperStartupTask != nil, whisperTranscriber?.isRecording != true {
            pendingWhisperStartupTask?.cancel()
            pendingWhisperStartupTask = nil
            resetSessionAfterFailedStart()
            return
        }

        let cancelledSessionID = activeRecordingSessionID
        activeRecordingSessionID = UUID()
        isSessionCancellationRequested = true
        didCommitSessionOutput = true
        sessionTargetApplicationPID = nil
        sessionTargetApplicationBundleID = nil

        cancelSessionControlTasks()
        pendingSystemAudioMuteTask?.cancel()
        pendingSystemAudioMuteTask = nil
        recordingStoppedAt = Date()
        overlayState.isCompleting = false
        overlayState.statusMessage = ""
        setEnhancingState(false)
        resetVoiceEndCommandState()
        stopActiveRecordingTranscriber()

        VoxtLog.info("Cancelled session invalidated. sessionID=\(cancelledSessionID.uuidString)", verbose: true)
        executeSessionEndPipeline(for: cancelledSessionID, trigger: "cancel")
    }

    func finishSession(after delay: TimeInterval? = nil) {
        cancelSessionControlTasks()

        let resolvedDelay = delay ?? sessionFinishDelay
        let finishingSessionID = activeRecordingSessionID
        VoxtLog.info("Finish session scheduled. delayMs=\(Int(resolvedDelay * 1000)), displayMode=\(overlayState.displayMode), isRecording=\(overlayState.isRecording), isEnhancing=\(overlayState.isEnhancing), isRequesting=\(overlayState.isRequesting)", verbose: true)
        overlayState.isCompleting = resolvedDelay > 0
        if overlayState.displayMode != .answer {
            overlayState.isEnhancing = false
            overlayState.isRequesting = false
        }
        pendingSessionFinishTask = Task { [weak self] in
            guard let self else { return }

            if resolvedDelay > 0 {
                do {
                    try await Task.sleep(for: .seconds(resolvedDelay))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            guard self.activeRecordingSessionID == finishingSessionID else {
                VoxtLog.info(
                    "Finish session ignored because session ID changed before execution. scheduledSessionID=\(finishingSessionID.uuidString), currentSessionID=\(self.activeRecordingSessionID.uuidString)"
                )
                return
            }
            VoxtLog.info("Finish session executing now. displayMode=\(self.overlayState.displayMode)", verbose: true)
            self.executeSessionEndPipeline(for: finishingSessionID, trigger: "finish")
        }
    }
}

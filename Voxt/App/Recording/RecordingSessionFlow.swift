// RecordingSessionFlow.swift
// Provides Recording Session Flow for recording session routing.

import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Speech

extension AppDelegate {
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
        let sherpaWasRecording = sherpaOnnxTranscriber?.isRecording == true
        let remoteWasRecording = remoteASRTranscriber.isRecording

        if speechWasRecording || mlxWasRecording || sherpaWasRecording || remoteWasRecording {
            VoxtLog.asrWarning(
                """
                Releasing residual recording resources. reason=\(reason), speech=\(speechWasRecording), mlx=\(mlxWasRecording), sherpa=\(sherpaWasRecording), remote=\(remoteWasRecording)
                """
            )
        }

        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil

        speechTranscriber.stopRecording()
        mlxTranscriber?.stopRecording()
        sherpaOnnxTranscriber?.stopRecording()
        remoteASRTranscriber.discardPendingSessionOutput()
        if preservePendingHistoryAudio {
            VoxtLog.asr("Preserving pending history audio during residual resource release. reason=\(reason)", verbose: true)
        } else {
            discardPendingCompletedHistoryAudio()
        }

        overlayState.isRecording = false
        overlayState.isRewriteConversationTurnInProgress = false
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
        let transcriptionHotkeyStartBehavior = outputMode == .transcription
            ? pendingTranscriptionHotkeyStartBehavior
            : nil
        if outputMode == .transcription {
            pendingTranscriptionHotkeyStartBehavior = nil
        }

        recordingRequestedAt = Date()
        VoxtLog.asr(
            "Begin recording requested. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), isSessionActive=\(isSessionActive)"
        )
        guard !blockNonMeetingRecordingWhileMeetingIsActive(
            source: "beginRecording:\(RecordingSessionSupport.outputLabel(for: outputMode))"
        ) else {
            return
        }
        pendingAutomaticDictionaryLearningTask?.cancel()
        guard !isSessionActive else {
            VoxtLog.asr(
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
            selectedSherpaModelID: localASRStartContext.selectedSherpaModelID,
            activeSherpaDownloadModelID: localASRStartContext.activeSherpaDownloadModelID,
            isSelectedSherpaModelDownloaded: localASRStartContext.isSelectedSherpaModelDownloaded,
            sherpaModelState: localASRStartContext.sherpaModelState
        )
        guard case .start(let recordingEngine) = startDecision else {
            if case .blocked(let reason) = startDecision {
                VoxtLog.asrWarning("Recording start blocked: \(reason.logDescription)")
                showOverlayReminder(reason.userMessage, autoHideAfter: reason.reminderDuration)
            }
            return
        }
        guard preflightPermissionsForRecording(engine: recordingEngine) else {
            VoxtLog.asr(
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
        firstLiveASRPartialReceivedAt = nil
        sessionFinalOutputDeliveredAt = nil
        sessionLLMExecutionTimings = []
        localVADObservedFramesInCurrentSession = false
        localVADObservedSpeechInCurrentSession = false
        didCommitSessionOutput = false
        isSessionCancellationRequested = false
        activeRecordingSessionID = UUID()
        invalidateActiveLLMRequest()
        pendingOutputReplacementTransaction = nil
        currentEndingSessionID = nil
        lastCompletedSessionEndSessionID = nil
        sessionOutputMode = outputMode
        enhancementContextSnapshot = nil
        rewriteSessionHasSelectedSourceText = false
        resetSessionTranslationState()
        configureVoxtNoteSessionRuntimeStateForNewRecording()
        configureTranscriptionCapturePipelineForCurrentSession()
        prewarmLLMForUpcomingSession(outputMode: outputMode)
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

        VoxtLog.asr(
            "Recording started. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), engine=\(recordingEngine.rawValue), pipeline=\(transcriptionCapturePipeline.rawValue)"
        )
        if outputMode == .rewrite {
            VoxtLog.asr(
                "Rewrite focused input check at session start. hasWritableFocusedInput=\(rewriteSessionHadWritableFocusedInput)"
            )
            VoxtLog.asr(
                "Rewrite fallback inject target at session start. frontmostBundleID=\(frontmostBundleID ?? "nil"), fallbackBundleID=\(rewriteSessionFallbackInjectBundleID ?? "nil")"
            )
        }

        applyPreferredInputDevice()
        if isContinuingRewriteConversation {
            overlayState.clearPendingConversationUserPrompt()
            overlayState.statusMessage = ""
            overlayState.sessionIconMode = .rewrite
            overlayState.isRewriteConversationTurnInProgress = true
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
        let shouldEnableCommonStopKey = outputMode == .translation ||
            outputMode == .rewrite ||
            transcriptionHotkeyStartBehavior == .tap ||
            transcriptionHotkeyStartBehavior == .doubleTap
        hotkeyManager.setCommonStopKeyEnabled(shouldEnableCommonStopKey)
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
        let stoppingSessionID = activeRecordingSessionID
        VoxtLog.asr("Recording stop requested.")

        hotkeyManager.setCommonStopKeyEnabled(false)
        pendingSystemAudioMuteTask?.cancel()
        pendingSystemAudioMuteTask = nil
        recordingStoppedAt = Date()
        if transcriptionProcessingStartedAt == nil {
            transcriptionProcessingStartedAt = recordingStoppedAt
        }
        prewarmLLMForPendingPostASRProcessing(outputMode: sessionOutputMode)
        overlayState.presentProcessing(iconMode: RecordingSessionSupport.overlayIconMode(for: sessionOutputMode))
        voiceEndCommandState.lastDetectedCommand = false
        enhancementContextSnapshot = captureEnhancementContextSnapshot()
        stopActiveRecordingTranscriberAfterPendingVADFlush(sessionID: stoppingSessionID)
    }

    func cancelActiveRecordingSession() {
        guard isSessionActive else { return }
        VoxtLog.asr("Recording cancelled by Escape key.")

        let cancelledSessionID = activeRecordingSessionID
        hotkeyManager.setCommonStopKeyEnabled(false)
        activeRecordingSessionID = UUID()
        invalidateActiveLLMRequest()
        pendingOutputReplacementTransaction = nil
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

        VoxtLog.asr("Cancelled session invalidated. sessionID=\(cancelledSessionID.uuidString)", verbose: true)
        executeSessionEndPipeline(for: cancelledSessionID, trigger: "cancel")
    }

    func finishSession(after delay: TimeInterval? = nil) {
        cancelSessionControlTasks()

        let resolvedDelay = delay ?? sessionFinishDelay
        let finishingSessionID = activeRecordingSessionID
        VoxtLog.asr("Finish session scheduled. delayMs=\(Int(resolvedDelay * 1000)), displayMode=\(overlayState.displayMode), isRecording=\(overlayState.isRecording), isEnhancing=\(overlayState.isEnhancing), isRequesting=\(overlayState.isRequesting)", verbose: true)
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
                VoxtLog.asr(
                    "Finish session ignored because session ID changed before execution. scheduledSessionID=\(finishingSessionID.uuidString), currentSessionID=\(self.activeRecordingSessionID.uuidString)"
                )
                return
            }
            VoxtLog.asr("Finish session executing now. displayMode=\(self.overlayState.displayMode)", verbose: true)
            self.executeSessionEndPipeline(for: finishingSessionID, trigger: "finish")
        }
    }
}

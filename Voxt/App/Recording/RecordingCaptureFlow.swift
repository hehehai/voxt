// RecordingCaptureFlow.swift
// Provides Recording Capture Flow for recording session routing.

import Foundation
import AVFoundation
import Speech

extension AppDelegate {
    private var isMLXReady: Bool {
        switch mlxModelManager.state {
        case .downloaded, .ready, .loading:
            return true
        default:
            return false
        }
    }

    func startSherpaOnnxRecordingSession() {
        Task { [weak self] in
            guard let self else { return }
            let sherpa = self.sherpaOnnxTranscriber ?? SherpaOnnxTranscriber(modelManager: self.sherpaOnnxModelManager)
            self.sherpaOnnxTranscriber = sherpa
            sherpa.dictionaryEntryProvider = { [weak self] in
                guard let self else { return [] }
                return self.dictionaryStore.activeEntriesForRemoteRequest(
                    activeGroupID: self.activeDictionaryGroupID(),
                    limit: DictionaryEntryCollection.asrPromptTermLimit
                )
            }
            let granted = await sherpa.requestPermissions()
            guard granted else {
                self.handleRecordingPermissionDenied()
                return
            }

            self.overlayState.statusMessage = ""
            let sessionID = self.activeRecordingSessionID
            sherpa.transcribedText = ""
            sherpa.setPreferredInputDevice(self.selectedInputDeviceID)
            sherpa.onTranscriptionFinished = { [weak self] text in
                self?.stashPendingCompletedHistoryAudioArchive(self?.sherpaOnnxTranscriber?.consumeCompletedAudioArchiveURL())
                self?.processTranscription(text, sessionID: sessionID)
            }
            sherpa.onStartFailure = { [weak self] message in
                guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                self.handleRecordingStartFailure(message, autoHideAfter: 3.6)
            }
            self.overlayState.bind(to: sherpa)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition
            )
            sherpa.startRecording()
            guard sherpa.isRecording else {
                let failureMessage = sherpa.consumePendingRuntimeFailureMessage()
                    ?? String(localized: "Sherpa ONNX failed to start recording.")
                self.handleRecordingStartFailure(failureMessage)
                return
            }
        }
    }

    func startMLXRecordingSession() {
        let mlx = mlxTranscriber ?? MLXTranscriber(modelManager: mlxModelManager)
        mlxTranscriber = mlx
        mlx.dictionaryEntryProvider = { [weak self] in
            guard let self else { return [] }
            return self.dictionaryStore.activeEntriesForRemoteRequest(
                activeGroupID: self.activeDictionaryGroupID(),
                limit: DictionaryEntryCollection.asrPromptTermLimit
            )
        }
        let sessionID = activeRecordingSessionID
        overlayState.statusMessage = ""
        mlx.transcribedText = ""
        mlx.sessionAllowsRealtimeTextDisplay = transcriptionCapturePipeline.usesLiveDisplay
        mlx.setPreferredInputDevice(selectedInputDeviceID)
        mlx.onPartialTranscription = { [weak self] text in
            self?.handleLiveASRPartialTranscription(text, sessionID: sessionID)
        }
        mlx.onTranscriptionFinished = { [weak self] text in
            self?.stashPendingCompletedHistoryAudioArchive(self?.mlxTranscriber?.consumeCompletedAudioArchiveURL())
            self?.processTranscription(text, sessionID: sessionID)
        }
        overlayState.bind(to: mlx)
        overlayWindow.show(
            state: overlayState,
            position: overlayPosition
        )
        Task { [weak self] in
            guard let self else { return }
            if let startFailureMessage = await mlx.startRecordingSession() {
                guard self.shouldHandleCallbacks(for: sessionID), self.isSessionActive else { return }
                VoxtLog.asrWarning("MLX recording session did not enter recording state. reason=\(startFailureMessage)")
                self.handleRecordingStartFailure(startFailureMessage)
                return
            }
            // Recording started, but the user may have released/cancelled the hotkey while the
            // engine was starting. If the session is no longer current, stop the stray capture.
            guard self.shouldHandleCallbacks(for: sessionID),
                  self.isSessionActive,
                  !self.isSessionCancellationRequested,
                  self.recordingStoppedAt == nil
            else {
                mlx.stopRecording()
                return
            }
        }
    }

    func startSpeechRecordingSession() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.speechTranscriber.requestPermissions()
            guard granted else {
                self.handleRecordingPermissionDenied()
                return
            }

            self.overlayState.statusMessage = ""
            let sessionID = self.activeRecordingSessionID
            self.speechTranscriber.transcribedText = ""
            self.speechTranscriber.sessionReportsPartialResultsOverride = self.transcriptionCapturePipeline.usesLiveDisplay
            self.speechTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.stashPendingCompletedHistoryAudioArchive(self?.speechTranscriber.consumeCompletedAudioArchiveURL())
                self?.processTranscription(text, sessionID: sessionID)
            }
            self.speechTranscriber.startRecording()
            guard self.speechTranscriber.isRecording else {
                let failureMessage = self.speechTranscriber.lastStartFailureMessage
                    ?? String(localized: "Direct Dictation failed to start recording.")
                VoxtLog.asrWarning("Speech recording session did not enter recording state. reason=\(failureMessage)")
                self.handleRecordingStartFailure(failureMessage)
                return
            }

            self.overlayState.bind(to: self.speechTranscriber)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition
            )
        }
    }

    func startRemoteRecordingSession() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.remoteASRTranscriber.requestPermissions()
            guard granted else {
                self.handleRecordingPermissionDenied()
                return
            }

            self.overlayState.statusMessage = ""
            let sessionID = self.activeRecordingSessionID
            self.remoteASRTranscriber.dictionaryEntryProvider = { [weak self] in
                guard let self else { return [] }
                return self.dictionaryStore.activeEntriesForRemoteRequest(
                    activeGroupID: self.activeDictionaryGroupID(),
                    limit: DictionaryEntryCollection.asrPromptTermLimit
                )
            }
            self.remoteASRTranscriber.transcribedText = ""
            self.remoteASRTranscriber.sessionAllowsRealtimeTextDisplay = self.transcriptionCapturePipeline.usesLiveDisplay
            self.remoteASRTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.stashPendingCompletedHistoryAudioArchive(self?.remoteASRTranscriber.consumeCompletedAudioArchiveURL())
                self?.processTranscription(text, sessionID: sessionID)
            }
            self.remoteASRTranscriber.onStartFailure = { [weak self] message in
                guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                self.handleRecordingStartFailure(message, autoHideAfter: 3.6)
            }
            self.remoteASRTranscriber.onRuntimeFailure = { [weak self] message in
                guard let self, self.shouldHandleCallbacks(for: sessionID), self.isSessionActive else { return }
                self.showOverlayStatus(message, clearAfter: 4.8)
            }
            self.overlayState.bind(to: self.remoteASRTranscriber)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition
            )
            self.remoteASRTranscriber.startRecording()
        }
    }

    func startRecordingCapture(using engine: TranscriptionEngine) {
        switch engine {
        case .mlxAudio:
            startMLXRecordingSession()
        case .sherpaOnnx:
            startSherpaOnnxRecordingSession()
        case .remote:
            startRemoteRecordingSession()
        case .dictation:
            startSpeechRecordingSession()
        }

        startSilenceMonitoringIfNeeded()
    }

    func resetSessionAfterFailedStart() {
        cancelSessionControlTasks()
        systemAudioMuteController.restoreSystemAudioIfNeeded()
        if transcriptionEngine == .remote {
            remoteASRTranscriber.discardPendingSessionOutput()
        }
        discardPendingCompletedHistoryAudio()
        isSessionActive = false
        isSessionCancellationRequested = false
        didCommitSessionOutput = false
        activeRecordingSessionID = UUID()
        invalidateActiveLLMRequest()
        currentEndingSessionID = nil
        lastCompletedSessionEndSessionID = nil
        sessionOutputMode = .transcription
        recordingRequestedAt = nil
        recordingStartedAt = nil
        recordingStoppedAt = nil
        transcriptionProcessingStartedAt = nil
        transcriptionResultReceivedAt = nil
        firstLiveASRPartialReceivedAt = nil
        sessionFinalOutputDeliveredAt = nil
        sessionLLMExecutionTimings = []
        transcriptionCapturePipeline = .liveDisplay
        isSelectedTextTranslationFlow = false
        sessionTargetApplicationPID = nil
        sessionTargetApplicationBundleID = nil
        enhancementContextSnapshot = nil
        lastEnhancementPromptContext = nil
        selectedTextTranslationHadWritableFocusedInput = false
        rewriteSessionHasSelectedSourceText = false
        rewriteSessionHadWritableFocusedInput = false
        resetVoiceEndCommandState()
        resetSessionTranslationState()
        resetVoxtNoteSessionRuntimeState()
        overlayState.reset()
        overlayWindow.hide()
    }

    func preflightPermissionsForRecording(engine: TranscriptionEngine) -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            VoxtLog.asrWarning("Recording blocked: microphone permission not granted.")
            showOverlayReminder(
                String(localized: "Microphone permission is required. Enable it in Settings > Permissions.")
            )
            return false
        }

        if engine == .dictation && SFSpeechRecognizer.authorizationStatus() != .authorized {
            VoxtLog.asrWarning("Recording blocked: speech recognition permission not granted for Direct Dictation.")
            showOverlayReminder(
                String(localized: "Speech Recognition permission is required for Direct Dictation. Enable it in Settings > Permissions.")
            )
            return false
        }

        if !AccessibilityPermissionManager.isTrusted() {
            VoxtLog.asrWarning("Recording start proceeding without accessibility trust. Injection may be unavailable.")
            showOverlayStatus(
                String(localized: "Please enable required permissions in Settings > Permissions."),
                clearAfter: 2.2
            )
        }

        return true
    }

    func applyPreferredInputDevice() {
        speechTranscriber.setPreferredInputDevice(selectedInputDeviceID)
        mlxTranscriber?.setPreferredInputDevice(selectedInputDeviceID)
        sherpaOnnxTranscriber?.setPreferredInputDevice(selectedInputDeviceID)
        remoteASRTranscriber.setPreferredInputDevice(selectedInputDeviceID)
    }

    func handlePreferredInputDeviceChange(
        previousUID: String?,
        newUID: String?,
        reason: String
    ) {
        applyPreferredInputDevice()

        guard previousUID != newUID else { return }

        guard let currentDevice = microphoneResolvedState.activeDevice else {
            if isSessionActive {
                showOverlayReminder(String(localized: "No available microphone devices."))
                finishSession(after: 0)
            }
            return
        }

        guard isSessionActive else { return }

        let sessionKind = RecordingSessionSupport.outputLabel(for: sessionOutputMode)
        let remoteDebugState = remoteASRTranscriber.activeRealtimeDebugSummary() ?? "none"
        VoxtLog.asrWarning(
            """
            Preferred input device changed during recording. reason=\(reason), previousUID=\(previousUID ?? "none"), newUID=\(newUID ?? "none"), engine=\(transcriptionEngine.rawValue), output=\(sessionKind), remoteState=\(remoteDebugState)
            """
        )

        do {
            try restartCurrentRecordingCaptureForPreferredInputDevice()
            showOverlayStatus(
                AppLocalization.format("Switched microphone to %@.", currentDevice.name),
                clearAfter: 1.8
            )
            VoxtLog.asrWarning(
                "Preferred input device change applied during recording. reason=\(reason), newUID=\(newUID ?? "none"), engine=\(transcriptionEngine.rawValue), output=\(sessionKind)"
            )
        } catch {
            VoxtLog.asrError("Recording microphone switch failed: \(error.localizedDescription). reason=\(reason)")
            showOverlayReminder(
                AppLocalization.format("Failed to switch microphone to %@.", currentDevice.name)
            )
            finishSession(after: 0)
        }
    }

    func stopActiveRecordingTranscriber() {
        if transcriptionEngine == .mlxAudio {
            mlxTranscriber?.stopRecording()
        } else if transcriptionEngine == .sherpaOnnx {
            sherpaOnnxTranscriber?.stopRecording()
        } else if transcriptionEngine == .remote {
            remoteASRTranscriber.stopRecording()
        } else {
            speechTranscriber.stopRecording()
        }
    }

    func updateActiveRecordingTranscriberTranscribedText(_ text: String) {
        switch transcriptionEngine {
        case .remote:
            remoteASRTranscriber.transcribedText = text
        case .mlxAudio:
            mlxTranscriber?.transcribedText = text
        case .sherpaOnnx:
            sherpaOnnxTranscriber?.transcribedText = text
        case .dictation:
            speechTranscriber.transcribedText = text
        }
    }

    func consumeActiveRecordingRuntimeFailureMessage() -> String? {
        switch transcriptionEngine {
        case .mlxAudio:
            return mlxTranscriber?.consumePendingRuntimeFailureMessage()
        case .sherpaOnnx:
            return sherpaOnnxTranscriber?.consumePendingRuntimeFailureMessage()
        case .remote, .dictation:
            return nil
        }
    }

    func setActiveRecordingTranscriberEnhancingState(_ isEnhancing: Bool) {
        switch transcriptionEngine {
        case .mlxAudio:
            mlxTranscriber?.isEnhancing = isEnhancing
        case .sherpaOnnx:
            sherpaOnnxTranscriber?.isEnhancing = isEnhancing
        case .remote:
            remoteASRTranscriber.isEnhancing = isEnhancing
        case .dictation:
            speechTranscriber.isEnhancing = isEnhancing
        }
    }

    func cancelPendingFinishTasks() {
        pendingSessionFinishTask?.cancel()
        pendingSessionFinishTask = nil
    }

    func cancelActiveRecordingTasks() {
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
    }

    func cancelSessionControlTasks() {
        cancelPendingFinishTasks()
        cancelActiveRecordingTasks()
    }

    private func handleRecordingPermissionDenied() {
        handleRecordingStartFailure(
            String(localized: "Please enable required permissions in Settings > Permissions.")
        )
    }

    private func handleRecordingStartFailure(
        _ message: String,
        autoHideAfter seconds: TimeInterval = 2.4
    ) {
        releaseResidualRecordingResources(reason: "recording-start-failure")
        showOverlayReminder(message, autoHideAfter: seconds)
        resetSessionAfterFailedStart()
    }

    private func restartCurrentRecordingCaptureForPreferredInputDevice() throws {
        if transcriptionEngine == .mlxAudio {
            try mlxTranscriber?.restartCaptureForPreferredInputDevice()
            return
        }

        if transcriptionEngine == .remote {
            try remoteASRTranscriber.restartCaptureForPreferredInputDevice()
            return
        }

        if transcriptionEngine == .sherpaOnnx {
            try sherpaOnnxTranscriber?.restartCaptureForPreferredInputDevice()
            return
        }

        try speechTranscriber.restartCaptureForPreferredInputDevice()
    }

    func startSilenceMonitoringIfNeeded() {
        cancelActiveRecordingTasks()

        resetSilenceMonitoringState()

        silenceMonitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isSessionActive {
                guard self.overlayState.isRecording else {
                    do {
                        try await Task.sleep(for: .milliseconds(200))
                    } catch {
                        return
                    }
                    continue
                }

                let level = self.overlayState.audioLevel
                if level > self.silenceAudioLevelThreshold {
                    self.lastSignificantAudioAt = Date()
                    self.didTriggerPauseTranscription = false
                    self.didTriggerPauseLLM = false
                    self.pauseLLMTask?.cancel()
                    self.pauseLLMTask = nil
                    self.setEnhancingState(false)
                } else {
                    let silentDuration = Date().timeIntervalSince(self.lastSignificantAudioAt)

                    if self.transcriptionEngine == .mlxAudio,
                       silentDuration >= 2.0,
                       !self.didTriggerPauseTranscription {
                        self.didTriggerPauseTranscription = true
                        self.mlxTranscriber?.forceIntermediateTranscription()
                    }

                }

                if self.shouldStopRecordingForVoiceEndCommand() {
                    self.triggerVoiceEndCommandStop()
                    return
                }

                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
            }
        }
    }

    private func resetSilenceMonitoringState() {
        lastSignificantAudioAt = Date()
        didTriggerPauseTranscription = false
        didTriggerPauseLLM = false
        voiceEndCommandState.lastDetectedCommand = false
    }

    private func triggerVoiceEndCommandStop() {
        voiceEndCommandState.didAutoStop = true
        voiceEndCommandState.lastDetectedCommand = false
        VoxtLog.hotkey("Voice end command triggered stop after trailing silence.")
        endRecording()
    }

}

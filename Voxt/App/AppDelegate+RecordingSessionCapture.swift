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

    var isWhisperReady: Bool {
        switch whisperModelManager.state {
        case .downloaded, .ready, .loading:
            return true
        default:
            return false
        }
    }

    func startMLXRecordingSession() {
        let mlx = mlxTranscriber ?? MLXTranscriber(modelManager: mlxModelManager)
        mlxTranscriber = mlx
        mlx.dictionaryEntryProvider = { [weak self] in
            guard let self else { return [] }
            return self.dictionaryStore.activeEntriesForRemoteRequest(
                activeGroupID: self.activeDictionaryGroupID()
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
        mlx.startRecording()
        guard mlx.isRecording else {
            VoxtLog.warning("MLX recording session did not enter recording state.")
            resetSessionAfterFailedStart()
            return
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
                VoxtLog.warning("Speech recording session did not enter recording state. reason=\(failureMessage)")
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

    func startWhisperRecordingSession() {
        let whisper = whisperTranscriber ?? WhisperKitTranscriber(modelManager: whisperModelManager)
        whisperTranscriber = whisper
        whisper.dictionaryEntryProvider = { [weak self] in
            guard let self else { return [] }
            return self.dictionaryStore.activeEntriesForRemoteRequest(
                activeGroupID: self.activeDictionaryGroupID()
            )
        }
        let sessionID = activeRecordingSessionID
        let needsModelInitialization = !whisperModelManager.isCurrentModelLoaded

        overlayState.statusMessage = ""
        overlayState.isModelInitializing = needsModelInitialization
        overlayState.initializingEngine = needsModelInitialization ? .whisperKit : nil
        whisper.transcribedText = ""
        whisper.sessionAllowsRealtimeTextDisplay = transcriptionCapturePipeline.usesLiveDisplay
        whisper.isModelInitializing = needsModelInitialization
        whisper.setPreferredInputDevice(selectedInputDeviceID)
        whisper.onPartialTranscription = { [weak self] text in
            self?.handleLiveASRPartialTranscription(text, sessionID: sessionID)
        }
        whisper.onTranscriptionFinished = { [weak self] text in
            self?.stashPendingCompletedHistoryAudioArchive(self?.whisperTranscriber?.consumeCompletedAudioArchiveURL())
            self?.processTranscription(text, sessionID: sessionID)
        }
        overlayState.bind(to: whisper)
        overlayWindow.show(
            state: overlayState,
            position: overlayPosition
        )

        pendingWhisperStartupTask?.cancel()
        pendingWhisperStartupTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.pendingWhisperStartupTask?.isCancelled != false {
                    self.pendingWhisperStartupTask = nil
                } else if !self.shouldHandleCallbacks(for: sessionID) || !self.isSessionActive {
                    self.pendingWhisperStartupTask = nil
                }
            }
            let granted = await whisper.requestPermissions()
            guard self.shouldContinueWhisperStartup(for: sessionID) else { return }
            guard granted else {
                self.handleRecordingPermissionDenied()
                return
            }

            let useWhisperDirectTranslation = self.shouldUseWhisperDirectTranslationForCurrentSession()
            let failureMessage = await whisper.prepareSession(
                outputMode: self.sessionOutputMode,
                useBuiltInTranslationTask: useWhisperDirectTranslation
            )
            guard self.shouldContinueWhisperStartup(for: sessionID) else { return }
            if let failureMessage {
                self.handleRecordingStartFailure(failureMessage)
                return
            }

            self.sessionUsesWhisperDirectTranslation = useWhisperDirectTranslation
            if let startFailureMessage = await whisper.startRecordingSession() {
                guard self.shouldContinueWhisperStartup(for: sessionID) else { return }
                VoxtLog.warning("Whisper recording session did not enter recording state. reason=\(startFailureMessage)")
                self.handleRecordingStartFailure(startFailureMessage)
                return
            }
            self.pendingWhisperStartupTask = nil
            guard self.shouldContinueWhisperStartup(for: sessionID) else {
                whisper.stopRecording()
                return
            }
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
        case .whisperKit:
            startWhisperRecordingSession()
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
            VoxtLog.warning("Recording blocked: microphone permission not granted.")
            showOverlayReminder(
                String(localized: "Microphone permission is required. Enable it in Settings > Permissions.")
            )
            return false
        }

        if engine == .dictation && SFSpeechRecognizer.authorizationStatus() != .authorized {
            VoxtLog.warning("Recording blocked: speech recognition permission not granted for Direct Dictation.")
            showOverlayReminder(
                String(localized: "Speech Recognition permission is required for Direct Dictation. Enable it in Settings > Permissions.")
            )
            return false
        }

        if !AccessibilityPermissionManager.isTrusted() {
            VoxtLog.warning("Recording start proceeding without accessibility trust. Injection may be unavailable.")
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
        whisperTranscriber?.setPreferredInputDevice(selectedInputDeviceID)
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
        VoxtLog.warning(
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
            VoxtLog.warning(
                "Preferred input device change applied during recording. reason=\(reason), newUID=\(newUID ?? "none"), engine=\(transcriptionEngine.rawValue), output=\(sessionKind)"
            )
        } catch {
            VoxtLog.error("Recording microphone switch failed: \(error.localizedDescription). reason=\(reason)")
            showOverlayReminder(
                AppLocalization.format("Failed to switch microphone to %@.", currentDevice.name)
            )
            finishSession(after: 0)
        }
    }

    func stopActiveRecordingTranscriber() {
        if transcriptionEngine == .mlxAudio {
            mlxTranscriber?.stopRecording()
        } else if transcriptionEngine == .whisperKit, isWhisperReady {
            if let whisperTranscriber {
                VoxtLog.info(
                    "Issuing Whisper stop. \(whisperTranscriber.debugCaptureStopSummary())",
                    verbose: true
                )
            }
            whisperTranscriber?.stopRecording()
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
        case .whisperKit:
            whisperTranscriber?.transcribedText = text
        case .dictation:
            speechTranscriber.transcribedText = text
        }
    }

    func setActiveRecordingTranscriberEnhancingState(_ isEnhancing: Bool) {
        switch transcriptionEngine {
        case .mlxAudio:
            mlxTranscriber?.isEnhancing = isEnhancing
        case .whisperKit:
            whisperTranscriber?.isEnhancing = isEnhancing
        case .remote:
            remoteASRTranscriber.isEnhancing = isEnhancing
        case .dictation:
            speechTranscriber.isEnhancing = isEnhancing
        }
    }

    func cancelPendingFinishTasks() {
        pendingSessionFinishTask?.cancel()
        pendingSessionFinishTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
    }

    func cancelActiveRecordingTasks() {
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
        pendingWhisperStartupTask?.cancel()
        pendingWhisperStartupTask = nil
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
        showOverlayReminder(message, autoHideAfter: seconds)
        resetSessionAfterFailedStart()
    }

    private func restartCurrentRecordingCaptureForPreferredInputDevice() throws {
        if transcriptionEngine == .mlxAudio {
            try mlxTranscriber?.restartCaptureForPreferredInputDevice()
            return
        }

        if transcriptionEngine == .whisperKit {
            try whisperTranscriber?.restartCaptureForPreferredInputDevice()
            return
        }

        if transcriptionEngine == .remote {
            try remoteASRTranscriber.restartCaptureForPreferredInputDevice()
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

                    if self.transcriptionEngine == .whisperKit,
                       !self.whisperRealtimeEnabled,
                       silentDuration >= 2.0,
                       !self.didTriggerPauseTranscription {
                        self.didTriggerPauseTranscription = true
                        self.whisperTranscriber?.forceIntermediateTranscription()
                    }

                    if (self.transcriptionEngine == .mlxAudio || self.transcriptionEngine == .whisperKit),
                       silentDuration >= 4.0,
                       !self.didTriggerPauseLLM {
                        self.didTriggerPauseLLM = true
                        self.startPauseLLMIfNeeded()
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

    private func shouldUseWhisperDirectTranslationForCurrentSession() -> Bool {
        activeSessionTranslationProviderResolution?.usesWhisperDirectTranslation == true
    }

    private func triggerVoiceEndCommandStop() {
        voiceEndCommandState.didAutoStop = true
        voiceEndCommandState.lastDetectedCommand = false
        VoxtLog.hotkey("Voice end command triggered stop after trailing silence.")
        endRecording()
    }

    private func shouldContinueWhisperStartup(for sessionID: UUID) -> Bool {
        shouldHandleCallbacks(for: sessionID)
            && isSessionActive
            && !isSessionCancellationRequested
            && recordingStoppedAt == nil
    }
}

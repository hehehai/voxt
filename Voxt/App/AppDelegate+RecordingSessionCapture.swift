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
        VoxtLog.tempModel(
            "AppDelegate startMLXRecordingSession enter. sessionID=\(activeRecordingSessionID.uuidString), pipeline=\(transcriptionCapturePipeline.rawValue), summary=\(activeRecordingCaptureDebugSummary())"
        )
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
        mlx.setPreferredInputDevice(activeRecordingInputDeviceSnapshot?.id ?? selectedInputDeviceID)
        mlx.onCaptureInputDeviceResolved = { [weak self] device in
            self?.syncActiveRecordingInputDeviceSnapshot(with: device, source: "mlx")
        }
        mlx.onCaptureFormatResolved = { [weak self] format in
            self?.recordActiveRecordingInputFormat(format, source: "mlx")
        }
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
        VoxtLog.tempModel("AppDelegate startMLXRecordingSession before mlx.startRecording(). summary=\(activeRecordingCaptureDebugSummary())")
        mlx.startRecording()
        VoxtLog.tempModel("AppDelegate startMLXRecordingSession after mlx.startRecording(). summary=\(activeRecordingCaptureDebugSummary())")
        guard mlx.isRecording else {
            let failureMessage = mlx.lastStartFailureMessage
                ?? String(localized: "MLX failed to start recording.")
            VoxtLog.warning("MLX recording session did not enter recording state. reason=\(failureMessage)")
            VoxtLog.tempModel("AppDelegate startMLXRecordingSession guard mlx.isRecording failed. summary=\(activeRecordingCaptureDebugSummary())")
            handleRecordingStartFailure(failureMessage, autoHideAfter: 3.6)
            return
        }
        VoxtLog.tempModel("AppDelegate startMLXRecordingSession completed. summary=\(activeRecordingCaptureDebugSummary())")
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
            self.speechTranscriber.onCaptureFormatResolved = { [weak self] format in
                self?.recordActiveRecordingInputFormat(format, source: "speech")
            }
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
                activeGroupID: self.activeDictionaryGroupID(),
                limit: DictionaryEntryCollection.asrPromptTermLimit
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
        whisper.setPreferredInputDevice(activeRecordingInputDeviceSnapshot?.id ?? selectedInputDeviceID)
        whisper.onCaptureFormatResolved = { [weak self] format in
            self?.recordActiveRecordingInputFormat(format, source: "whisper")
        }
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
        if let captureStartFailure = whisper.startRecordingCapture() {
            handleRecordingStartFailure(captureStartFailure)
            return
        }

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
            VoxtLog.tempModel(
                "AppDelegate startRemoteRecordingSession enter. sessionID=\(self.activeRecordingSessionID.uuidString), pipeline=\(self.transcriptionCapturePipeline.rawValue), summary=\(self.activeRecordingCaptureDebugSummary())"
            )
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
            self.remoteASRTranscriber.onCaptureFormatResolved = { [weak self] format in
                self?.recordActiveRecordingInputFormat(format, source: "remote")
            }
            self.remoteASRTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.stashPendingCompletedHistoryAudioArchive(self?.remoteASRTranscriber.consumeCompletedAudioArchiveURL())
                self?.processTranscription(text, sessionID: sessionID)
            }
            self.remoteASRTranscriber.onStartFailure = { [weak self] message in
                guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                VoxtLog.tempModel("AppDelegate remote onStartFailure. message=\(message), summary=\(self.activeRecordingCaptureDebugSummary())")
                self.handleRecordingStartFailure(message, autoHideAfter: 3.6)
            }
            self.remoteASRTranscriber.onRuntimeFailure = { [weak self] message in
                guard let self, self.shouldHandleCallbacks(for: sessionID), self.isSessionActive else { return }
                VoxtLog.tempModel("AppDelegate remote onRuntimeFailure. message=\(message), summary=\(self.activeRecordingCaptureDebugSummary())")
                self.showOverlayStatus(message, clearAfter: 4.8)
            }
            self.overlayState.bind(to: self.remoteASRTranscriber)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition
            )
            VoxtLog.tempModel("AppDelegate startRemoteRecordingSession before remote.startRecording(). summary=\(self.activeRecordingCaptureDebugSummary())")
            self.remoteASRTranscriber.startRecording()
            VoxtLog.tempModel("AppDelegate startRemoteRecordingSession after remote.startRecording(). summary=\(self.activeRecordingCaptureDebugSummary())")
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

    func resetSessionAfterFailedStart(hideOverlay: Bool = true) {
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
        if hideOverlay {
            overlayWindow.hide()
        }
        clearRecordingInputDeviceSnapshot(reason: "failed-start")
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
        let deviceID = activeRecordingInputDeviceSnapshot?.id ?? selectedInputDeviceID
        speechTranscriber.setPreferredInputDevice(deviceID)
        mlxTranscriber?.setPreferredInputDevice(deviceID)
        whisperTranscriber?.setPreferredInputDevice(deviceID)
        remoteASRTranscriber.setPreferredInputDevice(deviceID)
    }

    func freezeRecordingInputDeviceSnapshotForSession() {
        guard let activeDevice = microphoneResolvedState.activeDevice else {
            activeRecordingInputDeviceSnapshot = nil
            activeRecordingInputDeviceDirtyChanges.removeAll(keepingCapacity: false)
            stopObservingActiveRecordingInputDevice()
            VoxtLog.warning("Recording input device snapshot unavailable at session start.")
            return
        }

        let snapshot = RecordingInputDeviceSnapshot(device: activeDevice)
        activeRecordingInputDeviceSnapshot = snapshot
        activeRecordingInputDeviceDirtyChanges.removeAll(keepingCapacity: false)
        startObservingActiveRecordingInputDevice(snapshot)
        VoxtLog.model(
            "Recording input device frozen. uid=\(snapshot.uid), id=\(snapshot.id), name=\(snapshot.name)"
        )
    }

    func clearRecordingInputDeviceSnapshot(reason: String) {
        if let snapshot = activeRecordingInputDeviceSnapshot {
            VoxtLog.info(
                "Recording input device snapshot cleared. reason=\(reason), uid=\(snapshot.uid), id=\(snapshot.id)",
                verbose: true
            )
        }
        activeRecordingInputDeviceSnapshot = nil
        activeRecordingInputDeviceDirtyChanges.removeAll(keepingCapacity: false)
        pendingInputDeviceRecoveryTask?.cancel()
        pendingInputDeviceRecoveryTask = nil
        stopObservingActiveRecordingInputDevice()
    }

    func recordActiveRecordingInputFormat(
        _ format: RecordingAudioFormatSnapshot,
        source: String
    ) {
        guard var snapshot = activeRecordingInputDeviceSnapshot else { return }
        guard snapshot.initialFormat == nil else { return }
        snapshot = snapshot.withInitialFormat(format)
        activeRecordingInputDeviceSnapshot = snapshot
        VoxtLog.model(
            "Recording input format frozen. source=\(source), uid=\(snapshot.uid), id=\(snapshot.id), sampleRate=\(Int(format.sampleRate)), channels=\(format.channelCount), format=\(format.commonFormatRawValue), interleaved=\(format.isInterleaved)"
        )
    }

    func syncActiveRecordingInputDeviceSnapshot(with device: AudioInputDevice, source: String) {
        let previousSnapshot = activeRecordingInputDeviceSnapshot
        let updatedSnapshot: RecordingInputDeviceSnapshot
        if let previousSnapshot {
            updatedSnapshot = previousSnapshot.replacingDevice(device)
        } else {
            updatedSnapshot = RecordingInputDeviceSnapshot(device: device)
        }

        activeRecordingInputDeviceSnapshot = updatedSnapshot
        if previousSnapshot?.id != updatedSnapshot.id || previousSnapshot?.uid != updatedSnapshot.uid {
            startObservingActiveRecordingInputDevice(updatedSnapshot)
            VoxtLog.model(
                "Recording input device synchronized to active capture route. source=\(source), uid=\(updatedSnapshot.uid), id=\(updatedSnapshot.id), name=\(updatedSnapshot.name)"
            )
        }
    }

    func startObservingActiveRecordingInputDevice(_ snapshot: RecordingInputDeviceSnapshot) {
        stopObservingActiveRecordingInputDevice()
        activeRecordingInputDeviceObserver = AudioInputDeviceRuntimeObserver(
            deviceID: snapshot.id,
            uid: snapshot.uid
        ) { [weak self] change in
            Task { @MainActor [weak self] in
                self?.handleActiveRecordingInputDeviceRuntimeChange(change)
            }
        }
    }

    private func stopObservingActiveRecordingInputDevice() {
        activeRecordingInputDeviceObserver = nil
    }

    private func handleActiveRecordingInputDeviceRuntimeChange(_ change: RecordingInputDeviceRuntimeChange) {
        guard isSessionActive, recordingStoppedAt == nil else { return }
        guard let snapshot = activeRecordingInputDeviceSnapshot else { return }

        activeRecordingInputDeviceDirtyChanges.append(change)
        VoxtLog.model(
            "Recording input device marked dirty. change=\(change.description), uid=\(snapshot.uid), id=\(snapshot.id), captureState=\(activeRecordingCaptureDebugSummary())"
        )

        guard change.requiresCaptureRecovery else { return }
        scheduleActiveRecordingInputRecovery(reason: "device-\(change.description)")
    }

    func scheduleActiveRecordingInputRecovery(reason: String) {
        pendingInputDeviceRecoveryTask?.cancel()
        pendingInputDeviceRecoveryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            await MainActor.run {
                self?.recoverActiveRecordingInputDeviceIfNeeded(reason: reason)
            }
        }
    }

    func recoverActiveRecordingInputDeviceIfNeeded(reason: String) {
        guard isSessionActive, recordingStoppedAt == nil else { return }
        guard let snapshot = activeRecordingInputDeviceSnapshot else { return }
        guard !activeRecordingCaptureStartupInProgress() else {
            scheduleActiveRecordingInputRecovery(reason: reason)
            return
        }

        let devices = AudioInputDeviceManager.snapshotAvailableInputDevices()
        guard let refreshedDevice = devices.first(where: { $0.uid == snapshot.uid }) else {
            VoxtLog.warning(
                "Recording input device disappeared during active session. reason=\(reason), uid=\(snapshot.uid), name=\(snapshot.name)"
            )
            showOverlayReminder(
                AppLocalization.format("Microphone %@ is no longer available.", snapshot.name)
            )
            finishSession(after: 0)
            return
        }

        let refreshedSnapshot = snapshot.replacingDevice(refreshedDevice)
        activeRecordingInputDeviceSnapshot = refreshedSnapshot
        if refreshedSnapshot.id != snapshot.id {
            startObservingActiveRecordingInputDevice(refreshedSnapshot)
        }
        applyPreferredInputDevice()

        do {
            try restartCurrentRecordingCapturePreservingRoute()
            activeRecordingInputDeviceDirtyChanges.removeAll(keepingCapacity: false)
            VoxtLog.model(
                "Recording input recovery completed. reason=\(reason), uid=\(refreshedSnapshot.uid), previousID=\(snapshot.id), currentID=\(refreshedSnapshot.id), captureState=\(activeRecordingCaptureDebugSummary())"
            )
        } catch {
            VoxtLog.error("Recording input recovery failed: \(error.localizedDescription). reason=\(reason)")
            showOverlayReminder(
                AppLocalization.format("Failed to recover microphone %@.", refreshedSnapshot.name)
            )
            finishSession(after: 0)
        }
    }

    func handlePreferredInputDeviceChange(
        previousUID: String?,
        newUID: String?,
        reason: String
    ) {
        VoxtLog.tempModel(
            "AppDelegate handlePreferredInputDeviceChange enter. reason=\(reason), previousUID=\(previousUID ?? "none"), newUID=\(newUID ?? "none"), summary=\(activeRecordingCaptureDebugSummary())"
        )
        guard previousUID != newUID else {
            applyPreferredInputDevice()
            return
        }

        if isSessionActive, recordingStoppedAt == nil {
            let sessionKind = RecordingSessionSupport.outputLabel(for: sessionOutputMode)
            let captureDebugState = activeRecordingCaptureDebugSummary()
            VoxtLog.model(
                """
                Deferring preferred input device change until the next recording. reason=\(reason), previousUID=\(previousUID ?? "none"), newUID=\(newUID ?? "none"), engine=\(transcriptionEngine.rawValue), output=\(sessionKind), captureState=\(captureDebugState)
                """
            )
            VoxtLog.tempModel(
                "AppDelegate handlePreferredInputDeviceChange deferred during active recording. reason=\(reason), previousUID=\(previousUID ?? "none"), newUID=\(newUID ?? "none"), summary=\(activeRecordingCaptureDebugSummary())"
            )
            showOverlayStatus(
                String(localized: "Microphone change will apply on the next recording."),
                clearAfter: 1.8
            )
            return
        }

        applyPreferredInputDevice()
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
        releaseResidualRecordingResources(reason: "recording-start-failure")
        resetSessionAfterFailedStart(hideOverlay: false)
        showOverlayReminder(message, autoHideAfter: seconds)
    }

    private func restartCurrentRecordingCaptureForPreferredInputDevice() throws {
        VoxtLog.tempModel("AppDelegate restartCurrentRecordingCaptureForPreferredInputDevice enter. engine=\(transcriptionEngine.rawValue), summary=\(activeRecordingCaptureDebugSummary())")
        if transcriptionEngine == .mlxAudio {
            try mlxTranscriber?.restartCaptureForPreferredInputDevice()
            VoxtLog.tempModel("AppDelegate restartCurrentRecordingCaptureForPreferredInputDevice completed for MLX. summary=\(activeRecordingCaptureDebugSummary())")
            return
        }

        if transcriptionEngine == .whisperKit {
            try whisperTranscriber?.restartCaptureForPreferredInputDevice()
            VoxtLog.tempModel("AppDelegate restartCurrentRecordingCaptureForPreferredInputDevice completed for Whisper. summary=\(activeRecordingCaptureDebugSummary())")
            return
        }

        if transcriptionEngine == .remote {
            try remoteASRTranscriber.restartCaptureForPreferredInputDevice()
            VoxtLog.tempModel("AppDelegate restartCurrentRecordingCaptureForPreferredInputDevice completed for Remote. summary=\(activeRecordingCaptureDebugSummary())")
            return
        }

        try speechTranscriber.restartCaptureForPreferredInputDevice()
        VoxtLog.tempModel("AppDelegate restartCurrentRecordingCaptureForPreferredInputDevice completed for Speech. summary=\(activeRecordingCaptureDebugSummary())")
    }

    private func restartCurrentRecordingCapturePreservingRoute() throws {
        VoxtLog.tempModel("AppDelegate restartCurrentRecordingCapturePreservingRoute enter. engine=\(transcriptionEngine.rawValue), summary=\(activeRecordingCaptureDebugSummary())")
        if transcriptionEngine == .mlxAudio {
            try mlxTranscriber?.restartCapturePreservingCurrentRoute()
            VoxtLog.tempModel("AppDelegate restartCurrentRecordingCapturePreservingRoute completed for MLX. summary=\(activeRecordingCaptureDebugSummary())")
            return
        }

        try restartCurrentRecordingCaptureForPreferredInputDevice()
    }

    func activeRecordingCaptureDebugSummary() -> String {
        let mlxSummary = mlxTranscriber?.temporaryCaptureDebugSummary() ?? "mlx{uninitialized}"
        let whisperSummary: String
        if let whisperTranscriber {
            whisperSummary = "whisper{recording=\(whisperTranscriber.isRecording), modelInitializing=\(whisperTranscriber.isModelInitializing), \(whisperTranscriber.debugCaptureStopSummary())}"
        } else {
            whisperSummary = "whisper{uninitialized}"
        }
        let remoteSummary = remoteASRTranscriber.temporaryCaptureDebugSummary()
        let speechSummary = "speech{recording=\(speechTranscriber.isRecording)}"
        let currentSummary: String
        switch transcriptionEngine {
        case .mlxAudio:
            currentSummary = mlxSummary
        case .whisperKit:
            currentSummary = whisperSummary
        case .remote:
            currentSummary = remoteSummary
        case .dictation:
            currentSummary = speechSummary
        }
        return """
        engine=\(transcriptionEngine.rawValue), current=\(currentSummary), mlx=\(mlxSummary), whisper=\(whisperSummary), remote=\(remoteSummary), speech=\(speechSummary)
        """
    }

    func activeRecordingCaptureStartupInProgress() -> Bool {
        switch transcriptionEngine {
        case .mlxAudio:
            guard let mlxTranscriber else { return false }
            return mlxTranscriber.isModelInitializing && !mlxTranscriber.isRecording
        case .whisperKit:
            guard let whisperTranscriber else { return false }
            return whisperTranscriber.isModelInitializing && !whisperTranscriber.isRecording
        case .remote, .dictation:
            return false
        }
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

import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Speech

extension AppDelegate {
    func beginRecording(outputMode: SessionOutputMode) {
        guard !meetingSessionCoordinator.isActive else {
            showOverlayStatus(
                String(localized: "Meeting Notes is currently active. Close it before starting another recording."),
                clearAfter: 2.2
            )
            return
        }
        guard !isSessionActive else { return }
        let startDecision = RecordingStartPlanner.resolve(
            selectedEngine: transcriptionEngine,
            mlxModelState: mlxModelManager.state,
            whisperModelState: whisperModelManager.state
        )
        guard case .start(let recordingEngine) = startDecision else {
            if case .blocked(let reason) = startDecision {
                VoxtLog.warning("Recording start blocked: \(reason.logDescription)")
                showOverlayReminder(reason.userMessage)
            }
            return
        }
        guard preflightPermissionsForRecording(engine: recordingEngine) else { return }

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
        sessionOutputMode = outputMode
        enhancementContextSnapshot = nil
        rewriteSessionHasSelectedSourceText = false
        sessionUsesWhisperDirectTranslation = false
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmostApplication?.bundleIdentifier
        let sessionTargetBundleID = fallbackInjectBundleID(from: frontmostBundleID)
        sessionTargetApplicationBundleID = sessionTargetBundleID
        sessionTargetApplicationPID = sessionTargetBundleID == nil ? nil : frontmostApplication?.processIdentifier
        rewriteSessionHadWritableFocusedInput = outputMode == .rewrite ? hasWritableFocusedTextInput() : false
        rewriteSessionFallbackInjectBundleID = outputMode == .rewrite ? sessionTargetBundleID : nil
        resetVoiceEndCommandState()

        VoxtLog.info(
            "Recording started. output=\(sessionOutputLabel(for: outputMode)), engine=\(recordingEngine.rawValue)"
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
        overlayState.reset()
        overlayState.statusMessage = ""
        overlayState.presentRecording(iconMode: overlayIconMode(for: outputMode))

        isSessionActive = true
        pendingSystemAudioMuteTask?.cancel()
        pendingSystemAudioMuteTask = nil

        let startCapture = { [weak self] in
            guard let self else { return }
            if recordingEngine == .mlxAudio {
                self.startMLXRecordingSession()
            } else if recordingEngine == .whisperKit {
                self.startWhisperRecordingSession()
            } else if recordingEngine == .remote {
                self.startRemoteRecordingSession()
            } else {
                self.startSpeechRecordingSession()
            }

            self.startSilenceMonitoringIfNeeded()
        }

        if muteSystemAudioWhileRecording {
            _ = systemAudioMuteController.muteSystemAudioIfNeeded()
        }
        if interactionSoundsEnabled {
            interactionSoundPlayer.playStart()
        }

        startCapture()
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
        overlayState.presentProcessing(iconMode: overlayIconMode(for: sessionOutputMode))
        voiceEndCommandState.lastDetectedCommand = false
        enhancementContextSnapshot = captureEnhancementContextSnapshot()
        stopActiveRecordingTranscriber()

        // Safety fallback: some engine/device combinations may occasionally fail to
        // report completion. Ensure the session/UI can always recover.
        let fallbackTimeoutSeconds = stopRecordingFallbackTimeoutSeconds()
        stopRecordingFallbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(fallbackTimeoutSeconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard self.isSessionActive else { return }
            VoxtLog.warning("Stop recording fallback triggered; forcing session finish.")
            self.finishSession(after: 0)
        }
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
        sessionUsesWhisperDirectTranslation = false
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
        executeSessionEndPipeline()
    }

    func processTranscription(_ rawText: String) {
        processTranscription(rawText, sessionID: activeRecordingSessionID)
    }

    func processTranscription(_ rawText: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        if didCommitSessionOutput {
            VoxtLog.info("Ignoring transcription callback because current session output has already been committed.")
            return
        }

        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil

        transcriptionResultReceivedAt = Date()
        let displayText = normalizedTranscriptionDisplayText(rawText)
        let text = sanitizedFinalTranscriptionText(displayText)
        guard !text.isEmpty else {
            VoxtLog.info("Transcription result is empty; finishing session.")
            setEnhancingState(false)
            finishSession(after: 0)
            return
        }

        overlayState.transcribedText = text
        if transcriptionEngine == .remote {
            remoteASRTranscriber.transcribedText = text
        } else if transcriptionEngine == .mlxAudio {
            mlxTranscriber?.transcribedText = text
        } else if transcriptionEngine == .whisperKit {
            whisperTranscriber?.transcribedText = text
        } else {
            speechTranscriber.transcribedText = text
        }

        VoxtLog.info("Transcription result received. characters=\(text.count), output=\(sessionOutputMode == .translation ? "translation" : "transcription")")
        VoxtLog.info("Transcription result output mode resolved as \(sessionOutputLabel(for: sessionOutputMode)).", verbose: true)
        VoxtLog.info("Enhancement mode=\(enhancementMode.rawValue), appEnhancementEnabled=\(appEnhancementEnabled)")

        if sessionOutputMode == .translation {
            if sessionUsesWhisperDirectTranslation {
                processWhisperTranslatedTranscription(text, sessionID: sessionID)
                return
            }
            processTranslatedTranscription(text, sessionID: sessionID)
            return
        }

        if sessionOutputMode == .rewrite {
            processRewriteTranscription(text, sessionID: sessionID)
            return
        }

        processStandardTranscription(text, sessionID: sessionID)
    }

    private func sessionOutputLabel(for outputMode: SessionOutputMode) -> String {
        switch outputMode {
        case .transcription:
            return "transcription"
        case .translation:
            return "translation"
        case .rewrite:
            return "rewrite"
        }
    }

    private func overlayIconMode(for outputMode: SessionOutputMode) -> OverlaySessionIconMode {
        switch outputMode {
        case .transcription:
            return .transcription
        case .translation:
            return .translation
        case .rewrite:
            return .rewrite
        }
    }

    private func fallbackInjectBundleID(from bundleID: String?) -> String? {
        guard let bundleID,
              let ownBundleID = Bundle.main.bundleIdentifier,
              bundleID != ownBundleID
        else {
            return nil
        }
        return bundleID
    }

    func startPauseLLMIfNeeded() {
        runPauseEnhancementIfNeeded()
    }

    func finishSession(after delay: TimeInterval = 0) {
        cancelSessionControlTasks()

        let resolvedDelay = delay > 0 ? delay : sessionFinishDelay
        overlayState.isCompleting = resolvedDelay > 0
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
            self.executeSessionEndPipeline()
        }
    }

    func showOverlayStatus(_ message: String, clearAfter seconds: TimeInterval = 2.4) {
        overlayStatusClearTask?.cancel()
        overlayState.statusMessage = message
        overlayState.presentRecording(iconMode: overlayIconMode(for: sessionOutputMode))
        overlayStatusClearTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            if self.overlayState.statusMessage == message {
                self.overlayState.statusMessage = ""
            }
            self.overlayStatusClearTask = nil
        }
    }

    func showOverlayReminder(_ message: String, autoHideAfter seconds: TimeInterval = 2.4) {
        overlayReminderTask?.cancel()
        overlayStatusClearTask?.cancel()
        overlayState.reset()
        overlayState.statusMessage = message
        overlayState.presentRecording(iconMode: overlayIconMode(for: sessionOutputMode))
        overlayWindow.show(state: overlayState, position: overlayPosition)

        overlayReminderTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self.overlayWindow.hide()
            self.overlayState.reset()
            self.overlayReminderTask = nil
        }
    }

    func setEnhancingState(_ isEnhancing: Bool) {
        overlayState.isEnhancing = isEnhancing
        if overlayState.displayMode != .answer {
            overlayState.displayMode = isEnhancing ? .processing : .recording
        }
        if transcriptionEngine == .mlxAudio {
            mlxTranscriber?.isEnhancing = isEnhancing
        } else if transcriptionEngine == .whisperKit {
            whisperTranscriber?.isEnhancing = isEnhancing
        } else if transcriptionEngine == .remote {
            remoteASRTranscriber.isEnhancing = isEnhancing
        } else {
            speechTranscriber.isEnhancing = isEnhancing
        }
    }

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

    private func startMLXRecordingSession() {
        let mlx = mlxTranscriber ?? MLXTranscriber(modelManager: mlxModelManager)
        mlxTranscriber = mlx
        let sessionID = activeRecordingSessionID
        overlayState.statusMessage = ""
        mlx.transcribedText = ""
        mlx.setPreferredInputDevice(selectedInputDeviceID)
        mlx.onTranscriptionFinished = { [weak self] text in
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

    private func startSpeechRecordingSession() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.speechTranscriber.requestPermissions()
            guard granted else {
                self.showOverlayReminder(
                    String(localized: "Please enable required permissions in Settings > Permissions.")
                )
                self.resetSessionAfterFailedStart()
                return
            }

            self.overlayState.statusMessage = ""
            let sessionID = self.activeRecordingSessionID
            self.speechTranscriber.transcribedText = ""
            self.speechTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.processTranscription(text, sessionID: sessionID)
            }
            self.speechTranscriber.startRecording()
            guard self.speechTranscriber.isRecording else {
                let failureMessage = self.speechTranscriber.lastStartFailureMessage
                    ?? String(localized: "Direct Dictation failed to start recording.")
                VoxtLog.warning("Speech recording session did not enter recording state. reason=\(failureMessage)")
                self.showOverlayReminder(failureMessage)
                self.resetSessionAfterFailedStart()
                return
            }

            self.overlayState.bind(to: self.speechTranscriber)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition
            )
        }
    }

    private func startWhisperRecordingSession() {
        let whisper = whisperTranscriber ?? WhisperKitTranscriber(modelManager: whisperModelManager)
        whisperTranscriber = whisper
        let sessionID = activeRecordingSessionID
        let needsModelInitialization = !whisperModelManager.isCurrentModelLoaded

        overlayState.statusMessage = ""
        overlayState.isModelInitializing = needsModelInitialization
        overlayState.initializingEngine = needsModelInitialization ? .whisperKit : nil
        whisper.transcribedText = ""
        whisper.isModelInitializing = needsModelInitialization
        whisper.setPreferredInputDevice(selectedInputDeviceID)
        whisper.onPartialTranscription = { [weak self] text in
            guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
            self.overlayState.transcribedText = text
        }
        whisper.onTranscriptionFinished = { [weak self] text in
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
                self.showOverlayReminder(
                    String(localized: "Please enable required permissions in Settings > Permissions.")
                )
                self.resetSessionAfterFailedStart()
                return
            }

            let useWhisperDirectTranslation = self.shouldUseWhisperDirectTranslationForCurrentSession()
            let failureMessage = await whisper.prepareSession(
                outputMode: self.sessionOutputMode,
                useBuiltInTranslationTask: useWhisperDirectTranslation
            )
            guard self.shouldContinueWhisperStartup(for: sessionID) else { return }
            if let failureMessage {
                self.showOverlayReminder(failureMessage)
                self.resetSessionAfterFailedStart()
                return
            }

            self.sessionUsesWhisperDirectTranslation = useWhisperDirectTranslation
            if let startFailureMessage = await whisper.startRecordingSession() {
                guard self.shouldContinueWhisperStartup(for: sessionID) else { return }
                VoxtLog.warning("Whisper recording session did not enter recording state. reason=\(startFailureMessage)")
                self.showOverlayReminder(startFailureMessage)
                self.resetSessionAfterFailedStart()
                return
            }
            self.pendingWhisperStartupTask = nil
            guard self.shouldContinueWhisperStartup(for: sessionID) else {
                whisper.stopRecording()
                return
            }
        }
    }

    private func startRemoteRecordingSession() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.remoteASRTranscriber.requestPermissions()
            guard granted else {
                self.showOverlayReminder(
                    String(localized: "Please enable required permissions in Settings > Permissions.")
                )
                self.resetSessionAfterFailedStart()
                return
            }

            self.overlayState.statusMessage = ""
            let sessionID = self.activeRecordingSessionID
            self.remoteASRTranscriber.transcribedText = ""
            self.remoteASRTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.processTranscription(text, sessionID: sessionID)
            }
            self.overlayState.bind(to: self.remoteASRTranscriber)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition
            )
            self.remoteASRTranscriber.startRecording()
        }
    }

    private func resetSessionAfterFailedStart() {
        cancelSessionControlTasks()
        systemAudioMuteController.restoreSystemAudioIfNeeded()
        isSessionActive = false
        isSessionCancellationRequested = false
        didCommitSessionOutput = false
        activeRecordingSessionID = UUID()
        sessionOutputMode = .transcription
        sessionUsesWhisperDirectTranslation = false
        recordingStartedAt = nil
        recordingStoppedAt = nil
        transcriptionProcessingStartedAt = nil
        transcriptionResultReceivedAt = nil
        isSelectedTextTranslationFlow = false
        sessionTargetApplicationPID = nil
        sessionTargetApplicationBundleID = nil
        enhancementContextSnapshot = nil
        lastEnhancementPromptContext = nil
        rewriteSessionHasSelectedSourceText = false
        rewriteSessionHadWritableFocusedInput = false
        resetVoiceEndCommandState()
        overlayState.reset()
        overlayWindow.hide()
    }

    private func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func preflightPermissionsForRecording(engine: TranscriptionEngine) -> Bool {
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
            showOverlayStatus(
                String(localized: "Please enable required permissions in Settings > Permissions."),
                clearAfter: 2.2
            )
        }

        return true
    }

    private func normalizedTranscriptionDisplayText(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let extractedText: String
        if transcriptionEngine == .remote, remoteASRSelectedProvider == .openAIWhisper {
            guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
                  (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
                extractedText = trimmed
                let normalized = ChineseScriptNormalizer.normalize(extractedText, preferredMainLanguage: userMainLanguage)
                return normalized
            }

            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let extracted = extractTranscriptionTextValue(from: object),
                  !extracted.isEmpty else {
                extractedText = trimmed
                let normalized = ChineseScriptNormalizer.normalize(extractedText, preferredMainLanguage: userMainLanguage)
                return normalized
            }
            extractedText = extracted
        } else {
            extractedText = trimmed
        }

        let normalized = ChineseScriptNormalizer.normalize(extractedText, preferredMainLanguage: userMainLanguage)
        if normalized != extractedText {
            VoxtLog.info(
                "Normalized Chinese script variant for ASR output. preferred=\(userMainLanguage.code), chars=\(normalized.count)",
                verbose: true
            )
        }
        return normalized
    }

    private func stopRecordingFallbackTimeoutSeconds() -> TimeInterval {
        guard transcriptionEngine == .remote else { return 8 }
        switch remoteASRSelectedProvider {
        case .openAIWhisper, .glmASR:
            // File-upload ASR can legitimately take longer than realtime providers.
            return 60
        case .doubaoASR, .aliyunBailianASR:
            return 8
        }
    }

    private func extractTranscriptionTextValue(from object: Any) -> String? {
        if let text = object as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let dict = object as? [String: Any] {
            let preferredKeys = ["text", "transcript", "result_text", "utterance", "content", "data"]
            for key in preferredKeys {
                if let value = dict[key],
                   let extracted = extractTranscriptionTextValue(from: value),
                   !extracted.isEmpty {
                    return extracted
                }
            }

            for value in dict.values {
                if let extracted = extractTranscriptionTextValue(from: value),
                   !extracted.isEmpty {
                    return extracted
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for item in array {
                if let extracted = extractTranscriptionTextValue(from: item),
                   !extracted.isEmpty {
                    return extracted
                }
            }
        }

        return nil
    }

    private func applyPreferredInputDevice() {
        speechTranscriber.setPreferredInputDevice(selectedInputDeviceID)
        mlxTranscriber?.setPreferredInputDevice(selectedInputDeviceID)
        whisperTranscriber?.setPreferredInputDevice(selectedInputDeviceID)
    }

    private func startSilenceMonitoringIfNeeded() {
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

    private func stopActiveRecordingTranscriber() {
        if transcriptionEngine == .mlxAudio, isMLXReady {
            mlxTranscriber?.stopRecording()
        } else if transcriptionEngine == .whisperKit, isWhisperReady {
            whisperTranscriber?.stopRecording()
        } else if transcriptionEngine == .remote {
            remoteASRTranscriber.stopRecording()
        } else {
            speechTranscriber.stopRecording()
        }
    }

    private func resetSilenceMonitoringState() {
        lastSignificantAudioAt = Date()
        didTriggerPauseTranscription = false
        didTriggerPauseLLM = false
        voiceEndCommandState.lastDetectedCommand = false
    }

    private func shouldUseWhisperDirectTranslationForCurrentSession() -> Bool {
        TranslationProviderResolver.resolve(
            selectedProvider: translationModelProvider,
            fallbackProvider: translationFallbackModelProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: translationTargetLanguage,
            isSelectedTextTranslation: false,
            whisperModelState: whisperModelManager.state
        ).usesWhisperDirectTranslation
    }

    private func triggerVoiceEndCommandStop() {
        voiceEndCommandState.didAutoStop = true
        voiceEndCommandState.lastDetectedCommand = false
        VoxtLog.hotkey("Voice end command triggered stop after trailing silence.")
        endRecording()
    }

    private func cancelPendingFinishTasks() {
        pendingSessionFinishTask?.cancel()
        pendingSessionFinishTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
    }

    private func cancelActiveRecordingTasks() {
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
        pendingWhisperStartupTask?.cancel()
        pendingWhisperStartupTask = nil
    }

    private func cancelSessionControlTasks() {
        cancelPendingFinishTasks()
        cancelActiveRecordingTasks()
    }

    private func shouldContinueWhisperStartup(for sessionID: UUID) -> Bool {
        shouldHandleCallbacks(for: sessionID)
            && isSessionActive
            && !isSessionCancellationRequested
            && recordingStoppedAt == nil
    }
}

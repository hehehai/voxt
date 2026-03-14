import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Speech

extension AppDelegate {
    func beginRecording(outputMode: SessionOutputMode) {
        guard !isSessionActive else { return }
        guard preflightPermissionsForRecording() else { return }

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
        assistantActionHistory = []
        assistantStructuredHistory = []
        assistantActionStatuses = []
        assistantLastDiagnosis = nil
        resetVoiceEndCommandState()
        captureOverlayAnchorScreenIfNeeded()

        VoxtLog.info(
            "Recording started. output=\(sessionOutputLabel(for: outputMode)), engine=\(transcriptionEngine.rawValue)"
        )

        applyPreferredInputDevice()
        overlayState.displayMode = outputMode == .assistant ? .statusOnly : .transcriptionText
        overlayState.actionItems = []
        if outputMode == .assistant {
            overlayState.actionItems = [String(localized: "Listening for assistant task…")]
            overlayState.statusMessage = ""
        } else {
            overlayState.statusMessage = ""
        }

        if transcriptionEngine == .mlxAudio {
            switch mlxModelManager.state {
            case .notDownloaded:
                VoxtLog.warning("MLX Audio model not downloaded, falling back to Direct Dictation")
                showOverlayStatus(
                    String(localized: "MLX model is not downloaded. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
            case .error:
                VoxtLog.warning("MLX Audio model error, falling back to Direct Dictation")
                showOverlayStatus(
                    String(localized: "MLX model is unavailable. Open Settings > Model to fix it."),
                    clearAfter: 2.5
                )
            default:
                break
            }
        }

        isSessionActive = true
        if interactionSoundsEnabled {
            interactionSoundPlayer.playStart()
        }

        if transcriptionEngine == .mlxAudio, isMLXReady {
            startMLXRecordingSession()
        } else if transcriptionEngine == .remote {
            startRemoteRecordingSession()
        } else {
            startSpeechRecordingSession()
        }

        startSilenceMonitoringIfNeeded()
    }

    func endRecording() {
        guard isSessionActive else { return }
        guard recordingStoppedAt == nil else {
            VoxtLog.hotkey("Recording stop ignored: session is already stopping.")
            return
        }
        VoxtLog.info("Recording stop requested.")

        cancelActiveRecordingTasks()
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        recordingStoppedAt = Date()
        if transcriptionProcessingStartedAt == nil {
            transcriptionProcessingStartedAt = recordingStoppedAt
        }
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

        let cancelledSessionID = activeRecordingSessionID
        activeRecordingSessionID = UUID()
        isSessionCancellationRequested = true
        didCommitSessionOutput = true

        cancelSessionControlTasks()
        recordingStoppedAt = Date()
        overlayState.isCompleting = false
        overlayState.statusMessage = ""
        overlayState.actionItems = []
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
        } else {
            speechTranscriber.transcribedText = text
        }

        VoxtLog.info("Transcription result received. characters=\(text.count), output=\(sessionOutputLabel(for: sessionOutputMode))")
        VoxtLog.info("Transcription result output mode resolved as \(sessionOutputLabel(for: sessionOutputMode)).", verbose: true)
        VoxtLog.info("Enhancement mode=\(enhancementMode.rawValue), appEnhancementEnabled=\(appEnhancementEnabled)")

        if sessionOutputMode == .translation {
            processTranslatedTranscription(text, sessionID: sessionID)
            return
        }

        if sessionOutputMode == .rewrite {
            processRewriteTranscription(text, sessionID: sessionID)
            return
        }

        if sessionOutputMode == .assistant {
            processAssistantTranscription(text, sessionID: sessionID)
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
        case .assistant:
            return "assistant"
        }
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
        overlayState.actionItems = []
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
        overlayWindow.show(
            state: overlayState,
            position: overlayPosition,
            preferredScreen: currentPreferredOverlayScreen()
        )

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
        if transcriptionEngine == .mlxAudio {
            mlxTranscriber?.isEnhancing = isEnhancing
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

    private func startMLXRecordingSession() {
        let mlx = mlxTranscriber ?? MLXTranscriber(modelManager: mlxModelManager)
        mlxTranscriber = mlx
        let sessionID = activeRecordingSessionID
        overlayState.statusMessage = ""
        mlx.setPreferredInputDevice(selectedInputDeviceID)
        mlx.onTranscriptionFinished = { [weak self] text in
            self?.processTranscription(text, sessionID: sessionID)
        }
        overlayState.bind(to: mlx)
        overlayWindow.show(
            state: overlayState,
            position: overlayPosition,
            preferredScreen: currentPreferredOverlayScreen()
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
            self.speechTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.processTranscription(text, sessionID: sessionID)
            }
            self.overlayState.bind(to: self.speechTranscriber)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition,
                preferredScreen: self.currentPreferredOverlayScreen()
            )
            self.speechTranscriber.startRecording()
            guard self.speechTranscriber.isRecording else {
                VoxtLog.warning("Speech recording session did not enter recording state.")
                self.resetSessionAfterFailedStart()
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
            self.remoteASRTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.processTranscription(text, sessionID: sessionID)
            }
            self.overlayState.bind(to: self.remoteASRTranscriber)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition,
                preferredScreen: self.currentPreferredOverlayScreen()
            )
            self.remoteASRTranscriber.startRecording()
        }
    }

    private func resetSessionAfterFailedStart() {
        cancelSessionControlTasks()
        isSessionActive = false
        isSessionCancellationRequested = false
        didCommitSessionOutput = false
        activeRecordingSessionID = UUID()
        sessionOutputMode = .transcription
        recordingStartedAt = nil
        recordingStoppedAt = nil
        transcriptionProcessingStartedAt = nil
        transcriptionResultReceivedAt = nil
        isSelectedTextTranslationFlow = false
        enhancementContextSnapshot = nil
        lastEnhancementPromptContext = nil
        assistantActionStatuses.removeAll()
        resetVoiceEndCommandState()
        clearOverlayAnchorScreen()
        overlayState.reset()
        overlayWindow.hide()
    }

    private func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func preflightPermissionsForRecording() -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            VoxtLog.warning("Recording blocked: microphone permission not granted.")
            showOverlayReminder(
                String(localized: "Microphone permission is required. Enable it in Settings > Permissions.")
            )
            return false
        }

        if transcriptionEngine == .dictation && SFSpeechRecognizer.authorizationStatus() != .authorized {
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

        guard transcriptionEngine == .remote, remoteASRSelectedProvider == .openAIWhisper else {
            return trimmed
        }

        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
              (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
            return trimmed
        }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let extracted = extractTranscriptionTextValue(from: object),
              !extracted.isEmpty else {
            return trimmed
        }
        return extracted
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

                    if self.transcriptionEngine == .mlxAudio,
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
    }

    private func cancelSessionControlTasks() {
        cancelPendingFinishTasks()
        cancelActiveRecordingTasks()
    }
}

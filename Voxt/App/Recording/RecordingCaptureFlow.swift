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
        let localVADMode = LocalVADMode.stored()
        let localVADGatePolicy = ASRVoiceActivityRuntimePolicy.localGatePolicy(
            transcriptionEngine: .mlxAudio,
            mode: localVADMode
        )
        mlx.configureVoiceActivityFinalizationFiltering(enabled: localVADGatePolicy.isEnabled)
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
            self.remoteASRTranscriber.voiceActivityUseCase = self.voiceActivityUseCase
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

    func stopActiveRecordingTranscriberAfterPendingVADFlush(sessionID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            guard self.activeRecordingSessionID == sessionID else { return }

            let monitorTask = self.silenceMonitorTask
            self.silenceMonitorTask?.cancel()
            self.silenceMonitorTask = nil
            self.pauseLLMTask?.cancel()
            self.pauseLLMTask = nil
            await monitorTask?.value

            guard self.activeRecordingSessionID == sessionID else { return }
            await self.flushPendingRecordingVoiceActivityFramesBeforeStop()
            self.stopActiveRecordingTranscriber()
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
        let localVADMode = LocalVADMode.stored()
        let localVADGatePolicy = ASRVoiceActivityRuntimePolicy.localGatePolicy(
            transcriptionEngine: transcriptionEngine,
            mode: localVADMode
        )
        let localVADGateActive = localVADGatePolicy.isEnabled
        VoxtLog.asr(
            "Recording local VAD gate \(localVADGateActive ? "enabled" : "disabled"). mode=\(localVADMode.rawValue), output=\(RecordingSessionSupport.outputLabel(for: sessionOutputMode))",
            verbose: true
        )

        prepareRecordingVoiceActivityProcessing(
            mode: localVADMode,
            useCase: voiceActivityUseCase
        )

        silenceMonitorTask = Task { [weak self] in
            guard let self else { return }
            var observedSpeechEnd = false
            while !Task.isCancelled, self.isSessionActive {
                guard self.overlayState.isRecording else {
                    self.recordingVoiceActivitySegmenter?.reset()
                    await self.recordingVoiceActivityFrameDecider?.reset()
                    observedSpeechEnd = false
                    do {
                        try await Task.sleep(for: .milliseconds(200))
                    } catch {
                        return
                    }
                    continue
                }

                let level = self.overlayState.audioLevel
                let voiceActivityResult = await self.processPendingRecordingVoiceActivityFrames(
                    localVADGateActive: localVADGateActive,
                    level: level,
                    logEvents: true
                )
                let vadEvents = voiceActivityResult.events
                let sawSpeechFrame = voiceActivityResult.sawSpeechFrame
                let sawVoiceActivityFrame = voiceActivityResult.sawVoiceActivityFrame
                let shouldUseLevelTiming = ASRVoiceActivityRuntimePolicy.shouldUseLevelTiming(
                    localVADGateActive: localVADGateActive,
                    hasVoiceActivityFrames: sawVoiceActivityFrame
                )
                if !localVADGateActive {
                    self.recordingVoiceActivitySegmenter?.reset()
                    observedSpeechEnd = false
                }
                if vadEvents.contains(where: { event in
                    if case .speechEnded = event { return true }
                    return false
                }) {
                    observedSpeechEnd = true
                }
                if sawVoiceActivityFrame {
                    self.localVADObservedFramesInCurrentSession = true
                }
                if sawSpeechFrame {
                    self.localVADObservedSpeechInCurrentSession = true
                }
                if sawSpeechFrame || (shouldUseLevelTiming && level > self.silenceAudioLevelThreshold) {
                    observedSpeechEnd = false
                    self.lastSignificantAudioAt = Date()
                    self.didTriggerPauseTranscription = false
                    self.didTriggerPauseLLM = false
                    self.pauseLLMTask?.cancel()
                    self.pauseLLMTask = nil
                    self.setEnhancingState(false)
                } else if sawVoiceActivityFrame || shouldUseLevelTiming {
                    let silentDuration = Date().timeIntervalSince(self.lastSignificantAudioAt)

                    if ASRLocalIntermediateGatePolicy.shouldTriggerIntermediateTranscription(
                        transcriptionEngine: self.transcriptionEngine,
                        localVADGateActive: localVADGateActive,
                        silentDuration: silentDuration,
                        didTriggerPauseTranscription: self.didTriggerPauseTranscription,
                        observedSpeechEnd: observedSpeechEnd
                    ) {
                        self.didTriggerPauseTranscription = true
                        observedSpeechEnd = false
                        VoxtLog.asr(
                            "Recording VAD triggered intermediate transcription after trailing silence. silentDurationSec=\(String(format: "%.3f", silentDuration))",
                            verbose: true
                        )
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
        localVADObservedFramesInCurrentSession = false
        localVADObservedSpeechInCurrentSession = false
        recordingVoiceActivityFrameDecider = nil
        recordingVoiceActivitySegmenter = nil
        recordingVoiceActivityMode = nil
        recordingVoiceActivityUseCase = nil
        voiceEndCommandState.lastDetectedCommand = false
    }

    private var voiceActivityUseCase: ASRVoiceActivityUseCase {
        switch sessionOutputMode {
        case .transcription:
            return .transcription
        case .translation:
            return .translation
        case .rewrite:
            return .rewrite
        }
    }

    private func triggerVoiceEndCommandStop() {
        voiceEndCommandState.didAutoStop = true
        voiceEndCommandState.lastDetectedCommand = false
        VoxtLog.hotkey("Voice end command triggered stop after trailing silence.")
        endRecording()
    }

    private func prepareRecordingVoiceActivityProcessing(
        mode: LocalVADMode,
        useCase: ASRVoiceActivityUseCase
    ) {
        recordingVoiceActivityMode = mode
        recordingVoiceActivityUseCase = useCase
        recordingVoiceActivityFrameDecider = RecordingVoiceActivityFrameDecider(
            mode: mode,
            useCase: useCase,
            energyThreshold: silenceAudioLevelThreshold
        )
        recordingVoiceActivitySegmenter = ASRVoiceActivitySegmenter(
            configuration: ASRVoiceActivityConfiguration.profile(for: useCase)
        )
    }

    func flushPendingRecordingVoiceActivityFramesBeforeStop() async {
        guard transcriptionEngine == .mlxAudio else { return }
        let localVADMode = LocalVADMode.stored()
        let localVADGatePolicy = ASRVoiceActivityRuntimePolicy.localGatePolicy(
            transcriptionEngine: transcriptionEngine,
            mode: localVADMode
        )
        guard localVADGatePolicy.isEnabled else { return }

        if recordingVoiceActivityFrameDecider == nil || recordingVoiceActivitySegmenter == nil {
            prepareRecordingVoiceActivityProcessing(
                mode: localVADMode,
                useCase: voiceActivityUseCase
            )
        }

        let result = await processPendingRecordingVoiceActivityFrames(
            localVADGateActive: true,
            level: overlayState.audioLevel,
            logEvents: true
        )
        if result.sawVoiceActivityFrame {
            VoxtLog.asr(
                "Recording VAD stop flush processed pending frames. speech=\(result.sawSpeechFrame), events=\(result.events.count)",
                verbose: true
            )
        }
        mlxTranscriber?.finishVoiceActivityFinalizationFiltering()
    }

    private func processPendingRecordingVoiceActivityFrames(
        localVADGateActive: Bool,
        level: Float,
        logEvents: Bool
    ) async -> RecordingVoiceActivityDrainResult {
        guard localVADGateActive,
              let mlxTranscriber,
              let frameDecider = recordingVoiceActivityFrameDecider
        else {
            recordingVoiceActivitySegmenter?.reset()
            return .empty
        }

        let frames = mlxTranscriber.consumeVoiceActivityFrames()
        guard !frames.isEmpty else { return .empty }

        if recordingVoiceActivitySegmenter == nil {
            recordingVoiceActivitySegmenter = ASRVoiceActivitySegmenter(
                configuration: ASRVoiceActivityConfiguration.profile(for: voiceActivityUseCase)
            )
        }
        var segmenter = recordingVoiceActivitySegmenter ?? ASRVoiceActivitySegmenter(
            configuration: ASRVoiceActivityConfiguration.profile(for: voiceActivityUseCase)
        )
        var events: [ASRVoiceActivityEvent] = []
        var sawSpeechFrame = false
        var sawVoiceActivityFrame = false

        for frame in frames {
            guard let result = await frameDecider.decision(for: frame) else {
                continue
            }
            sawVoiceActivityFrame = true
            let segmenterResult = segmenter.appendWithResolvedSpeechState(result.decision)
            if segmenterResult.isSpeech {
                sawSpeechFrame = true
            }
            mlxTranscriber.appendVoiceActivityFinalizationFrame(
                frame,
                isSpeech: segmenterResult.isSpeech
            )
            if logEvents {
                for event in segmenterResult.events {
                    VoxtLog.asr(
                        "Recording VAD event. \(event.telemetrySummary), source=\(result.source.telemetryName), level=\(String(format: "%.3f", frame.level ?? level)), probability=\(result.probabilityText), threshold=\(String(format: "%.3f", silenceAudioLevelThreshold))",
                        verbose: true
                    )
                }
            }
            events.append(contentsOf: segmenterResult.events)
        }

        recordingVoiceActivitySegmenter = segmenter
        if sawVoiceActivityFrame {
            localVADObservedFramesInCurrentSession = true
        }
        if sawSpeechFrame {
            localVADObservedSpeechInCurrentSession = true
        }
        return RecordingVoiceActivityDrainResult(
            events: events,
            sawSpeechFrame: sawSpeechFrame,
            sawVoiceActivityFrame: sawVoiceActivityFrame
        )
    }

}

private struct RecordingVoiceActivityDrainResult: Sendable {
    let events: [ASRVoiceActivityEvent]
    let sawSpeechFrame: Bool
    let sawVoiceActivityFrame: Bool

    static let empty = RecordingVoiceActivityDrainResult(
        events: [],
        sawSpeechFrame: false,
        sawVoiceActivityFrame: false
    )
}

struct RecordingVoiceActivityDecisionResult: Sendable {
    let decision: ASRVoiceActivityFrameDecision
    let source: Source

    enum Source: Sendable {
        case energy
        case silero
        case fallbackEnergy

        var telemetryName: String {
            switch self {
            case .energy:
                return "energy"
            case .silero:
                return "silero"
            case .fallbackEnergy:
                return "fallback-energy"
            }
        }
    }

    var probabilityText: String {
        decision.probability.map { String(format: "%.3f", $0) } ?? "nil"
    }
}

actor RecordingVoiceActivityFrameDecider {
    private let mode: LocalVADMode
    private let useCase: ASRVoiceActivityUseCase
    private let energyBackend: ASREnergyVoiceActivityBackend
    private let sileroThreshold: Float
    private let sileroDetector = ASRSileroStreamingVoiceActivityDetector()
    private var sileroFallbackWarningLogged = false

    init(
        mode: LocalVADMode,
        useCase: ASRVoiceActivityUseCase,
        energyThreshold: Float
    ) {
        self.mode = mode
        self.useCase = useCase
        self.energyBackend = ASREnergyVoiceActivityBackend(threshold: energyThreshold)
        self.sileroThreshold = ASRVoiceActivityConfiguration.profile(for: useCase).onsetProbabilityThreshold
    }

    func reset() async {
        await sileroDetector.reset()
        sileroFallbackWarningLogged = false
    }

    func decision(for frame: ASRVoiceActivityAudioFrame) async -> RecordingVoiceActivityDecisionResult? {
        switch ASRVoiceActivityRuntimePolicy.effectiveBackend(mode: mode, useCase: useCase) {
        case .off:
            return nil
        case .energy:
            return await energyDecision(for: frame, source: .energy)
        case .mlxSilero:
            if let sileroDecision = await sileroDecision(for: frame) {
                return sileroDecision
            }
            return await energyDecision(for: frame, source: .fallbackEnergy)
        }
    }

    private func sileroDecision(for frame: ASRVoiceActivityAudioFrame) async -> RecordingVoiceActivityDecisionResult? {
        do {
            if let probability = try await sileroDetector.probability(
                samples: frame.samples,
                sampleRate: frame.sampleRate,
                streamID: "recording-\(useCase.rawValue)"
            ) {
                return RecordingVoiceActivityDecisionResult(
                    decision: ASRVoiceActivityFrameDecision(
                        startSeconds: frame.startSeconds,
                        endSeconds: frame.endSeconds,
                        isSpeech: probability >= sileroThreshold,
                        probability: probability
                    ),
                    source: .silero
                )
            }
        } catch {
            if shouldLogSileroFallback(error) {
                VoxtLog.asrWarning("Recording Silero VAD failed; falling back to energy VAD. error=\(error.localizedDescription)")
                sileroFallbackWarningLogged = true
            }
            await sileroDetector.reset()
        }
        return nil
    }

    private func energyDecision(
        for frame: ASRVoiceActivityAudioFrame,
        source: RecordingVoiceActivityDecisionResult.Source
    ) async -> RecordingVoiceActivityDecisionResult? {
        guard let decision = try? await energyBackend.decision(for: frame) else {
            return nil
        }
        return RecordingVoiceActivityDecisionResult(decision: decision, source: source)
    }

    private func shouldLogSileroFallback(_ error: Error) -> Bool {
        if let modelError = error as? MeetingVADModelError {
            switch modelError {
            case .modelNotDownloaded, .runtimeUnavailable:
                return false
            }
        }
        return !sileroFallbackWarningLogged
    }
}

// MeetingSessionCoordinator.swift
// Provides Meeting Session Coordinator for meeting session behavior.

import Foundation
import AVFoundation
import WhisperKit

@MainActor
final class MeetingSessionCoordinator {
    let overlayState = MeetingOverlayState()

    var onSessionFinished: (@MainActor (MeetingSessionResult) -> Void)?

    private let whisperModelManager: WhisperKitModelManager
    private let mlxModelManager: MLXModelManager
    private let microphoneCapture = MeetingMicrophoneCapture()
    private let systemAudioCapture = MeetingSystemAudioCapture()
    private static let micSpeechThreshold: Float = 0.012
    private static let systemSpeechThreshold: Float = 0.025
    private var micAccumulator = MeetingChunkAccumulator(speaker: .me, speechThreshold: micSpeechThreshold, profile: .quality)
    private var systemAccumulator = MeetingChunkAccumulator(speaker: .them, speechThreshold: systemSpeechThreshold, profile: .quality)
    private let voiceActivityDetector = MeetingVoiceActivityDetector()
    private var whisper: WhisperKit?
    private var transcriber: (any MeetingSegmentTranscribing)?
    private var liveSessionFactory: (any MeetingLiveSessionFactory)?
    private var liveSessions: [MeetingSpeaker: any MeetingLiveTranscribingSession] = [:]
    private var liveAudioPrebuffers: [MeetingSpeaker: MeetingLiveAudioPrebuffer] = [:]
    private var activeLocalEngine: TranscriptionEngine?
    private var activeEngineContext: MeetingASREngineContext?
    private var isStopping = false
    private var stopFinalizationTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var accumulatedRecordingDuration: TimeInterval = 0
    private var preferredInputDeviceIDProvider: () -> AudioDeviceID?
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    private var completedPendingTaskIDs = Set<UUID>()
    private var pendingChunks: [BufferedMeetingChunk] = []
    private var translationTasks: [UUID: Task<Void, Never>] = [:]
    private var microphoneStartupWatchdogTask: Task<Void, Never>?
    private var microphoneStartupRetryCount = 0
    private var micLevel: Float = 0
    private var systemLevel: Float = 0
    private var loggedInitialBufferSpeakers = Set<MeetingSpeaker>()
    private var loggedChunkSpeakers = Set<MeetingSpeaker>()
    private var loggedSampleExtractionFailureSpeakers = Set<MeetingSpeaker>()
    private let audioArchive = MeetingAudioArchive()
    private let realtimeTranslationTargetLanguageProvider: @MainActor () -> TranslationTargetLanguage?
    private let realtimeTranslationHandler: @MainActor (String, TranslationTargetLanguage) async throws -> String
    private var isStarting = false

    init(
        whisperModelManager: WhisperKitModelManager,
        mlxModelManager: MLXModelManager,
        preferredInputDeviceIDProvider: @escaping () -> AudioDeviceID?,
        realtimeTranslationTargetLanguageProvider: @escaping @MainActor () -> TranslationTargetLanguage?,
        realtimeTranslationHandler: @escaping @MainActor (String, TranslationTargetLanguage) async throws -> String
    ) {
        self.whisperModelManager = whisperModelManager
        self.mlxModelManager = mlxModelManager
        self.preferredInputDeviceIDProvider = preferredInputDeviceIDProvider
        self.realtimeTranslationTargetLanguageProvider = realtimeTranslationTargetLanguageProvider
        self.realtimeTranslationHandler = realtimeTranslationHandler
        self.liveAudioPrebuffers = [
            .me: MeetingLiveAudioPrebuffer(maxDuration: 1.0),
            .them: MeetingLiveAudioPrebuffer(maxDuration: 1.0)
        ]
    }

    var isActive: Bool {
        isStarting || overlayState.isPresented || overlayState.isRecording || overlayState.isPaused || activeLocalEngine != nil || isStopping
    }

    var isStartingUp: Bool {
        isStarting
    }

    func prepareForStart() {
        guard !isActive else { return }
        cleanupSessionState(shouldLogCaptureStop: false)
        let engineContext = resolvedEngineContext()
        activeEngineContext = engineContext
        reconfigureAccumulators(for: engineContext.chunkingProfile)
        overlayState.reset()
        overlayState.isPresented = true
        overlayState.isCollapsed = UserDefaults.standard.object(forKey: AppPreferenceKey.meetingOverlayCollapsed) as? Bool ?? false
        overlayState.captureMode = MeetingCaptureMode.stored()
        overlayState.realtimeTranslateEnabled = UserDefaults.standard.object(forKey: AppPreferenceKey.meetingRealtimeTranslateEnabled) as? Bool ?? false
        overlayState.audioLevel = 0
        overlayState.waveformState.reset()
        overlayState.waveformState.setActive(!engineContext.needsModelInitialization)
        overlayState.isRecording = !engineContext.needsModelInitialization
        overlayState.isModelInitializing = engineContext.needsModelInitialization
        isStarting = true
    }

    func cancelPendingStart() {
        guard isStarting else { return }
        cleanupSessionState(shouldLogCaptureStop: false)
        resetSessionPresentationState()
        overlayState.reset()
    }

    func start() async -> String? {
        if !isStarting {
            guard !overlayState.isPresented else { return nil }
            prepareForStart()
        }

        do {
            try Task.checkCancellation()
            let engineContext = activeEngineContext ?? resolvedEngineContext()
            activeEngineContext = engineContext
            VoxtLog.meeting(
                "Meeting start configuration. source=\(engineContext.historyModelDescription), mode=\(String(describing: engineContext.resolvedMode))",
                verbose: true
            )
            let transcriber = try await makeTranscriber(for: engineContext)
            try Task.checkCancellation()
            self.transcriber = transcriber
            try await startLiveSessionsIfNeeded(for: engineContext)
            try Task.checkCancellation()
            try startCaptures()
            try Task.checkCancellation()
            recordingStartedAt = Date()
            await drainPendingChunksIfNeeded()
            try Task.checkCancellation()
        } catch is CancellationError {
            cleanupSessionState(shouldLogCaptureStop: false)
            resetSessionPresentationState()
            overlayState.reset()
            return nil
        } catch {
            cleanupSessionState()
            resetSessionPresentationState()
            overlayState.reset()
            return error.localizedDescription
        }

        isStarting = false
        overlayState.isModelInitializing = false
        overlayState.isRecording = true
        overlayState.isPaused = false
        overlayState.waveformState.setActive(true)
        return nil
    }

    func pause() async {
        guard overlayState.isPresented, overlayState.isRecording, !isStopping else { return }
        overlayState.isRecording = false
        overlayState.isPaused = true
        overlayState.audioLevel = 0
        overlayState.waveformState.setActive(false)
        finalizeCurrentRecordingSlice()
        stopCaptures()
        await flushPendingAudio()
        await finishLiveSessionsIfNeeded()
    }

    func resume() async -> String? {
        guard overlayState.isPresented, overlayState.isPaused, !overlayState.isRecording, !isStopping else {
            return nil
        }
        do {
            if let context = activeEngineContext, context.resolvedMode.usesLiveSessions {
                try await startLiveSessionsIfNeeded(for: context)
            }
            try startCaptures()
            recordingStartedAt = Date()
            overlayState.isPaused = false
            overlayState.isRecording = true
            overlayState.waveformState.reset()
            overlayState.waveformState.setActive(true)
            return nil
        } catch {
            overlayState.audioLevel = 0
            overlayState.waveformState.setActive(false)
            return error.localizedDescription
        }
    }

    @discardableResult
    func stop(shouldFlushPendingAudio: Bool = true) -> Task<Void, Never>? {
        guard isActive else { return nil }
        if isStopping {
            return stopFinalizationTask
        }
        isStopping = true
        let visibleSnapshotSegments = finalizedSegments(from: overlayState.segments)
        overlayState.isRecording = false
        overlayState.isPaused = false
        overlayState.isModelInitializing = false
        overlayState.isFinalizing = shouldFlushPendingAudio
        overlayState.audioLevel = 0
        overlayState.waveformState.setActive(false)

        finalizeCurrentRecordingSlice()
        stopCaptures()

        let finalizationTask = Task { [weak self] in
            guard let self else { return }
            if shouldFlushPendingAudio {
                await self.flushPendingAudio()
                await self.finishLiveSessionsIfNeeded()
            } else {
                await self.transcriber?.cancelPendingWork()
                self.discardPendingAudioWork()
                await self.cancelLiveSessionsIfNeeded()
            }
            await MainActor.run {
                self.cancelTranslationTasks()
                self.clearPendingTranslationState()
            }

            let duration = max(self.accumulatedRecordingDuration, 0)
            let captureMode = await MainActor.run { self.overlayState.captureMode }
            let archivedAudioURL = shouldFlushPendingAudio ? (try? await self.persistMeetingAudioArchive()) : nil
            let finalSegmentsBeforeSpeakerAnalysis = await MainActor.run {
                self.finalizedSegments(from: self.overlayState.segments)
            }
            let finalTranscriptionDescriptors = shouldFlushPendingAudio ? await self.audioArchive.finalTranscriptionAssetDescriptors() : []
            let speakerAnalysisDescriptors = shouldFlushPendingAudio ? await self.audioArchive.analysisAssetDescriptors(for: captureMode) : []
            let finalTranscriptSegments = await self.optimizedFinalTranscriptSegments(
                fallbackSegments: finalSegmentsBeforeSpeakerAnalysis,
                finalTranscriptionDescriptors: finalTranscriptionDescriptors,
                shouldFlushPendingAudio: shouldFlushPendingAudio
            )
            let speechValidatedFinalTranscriptSegments = await self.speechValidatedFinalSegments(
                finalTranscriptSegments,
                captureMode: captureMode
            )
            let speakerAnalysisOptions = MeetingSpeakerDiarizationOptions.fromPreferences()
            let finalSegments: [MeetingTranscriptSegment]
            if captureMode.capabilities.allowsSpeakerFeatures {
                finalSegments = await MeetingSpeakerAnalysisPipeline.analyzedSegments(
                    from: speechValidatedFinalTranscriptSegments,
                    descriptors: speakerAnalysisDescriptors,
                    loadAsset: { descriptor in
                        await self.audioArchive.loadAsset(descriptor)
                    },
                    options: speakerAnalysisOptions
                )
            } else {
                finalSegments = MeetingTranscriptPostProcessor.process(speechValidatedFinalTranscriptSegments)
            }
            let sortedFinalSegments = finalSegments.sorted { lhs, rhs in
                if lhs.startSeconds == rhs.startSeconds {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.startSeconds < rhs.startSeconds
            }
            let speechValidatedVisibleSnapshotSegments = shouldFlushPendingAudio
                ? await self.speechValidatedFinalSegments(visibleSnapshotSegments, captureMode: captureMode)
                : visibleSnapshotSegments
            await MainActor.run {
                self.overlayState.segments = sortedFinalSegments
            }
            let result = MeetingSessionResult(
                captureMode: captureMode,
                transcriptionEngine: self.activeEngineContext?.engine ?? self.resolvedTranscriptionEngine(),
                transcriptionModelDescription: self.activeEngineContext?.historyModelDescription ?? self.fallbackHistoryModelDescription(),
                segments: sortedFinalSegments,
                visibleSnapshotSegments: speechValidatedVisibleSnapshotSegments.sorted { lhs, rhs in
                    if lhs.startSeconds == rhs.startSeconds {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.startSeconds < rhs.startSeconds
                },
                audioDurationSeconds: duration,
                archivedAudioURL: archivedAudioURL
            )

            await MainActor.run {
                VoxtLog.meeting(
                    "Meeting session finished. visibleSegments=\(visibleSnapshotSegments.count), persistedSegments=\(result.persistedSegments.count), duration=\(String(format: "%.2f", duration))s"
                )
            }
            self.cleanupSessionState()
            self.resetSessionPresentationState()
            self.overlayState.reset()
            self.onSessionFinished?(result)
            self.stopFinalizationTask = nil
        }
        stopFinalizationTask = finalizationTask
        return finalizationTask
    }

    func setCollapsed(_ isCollapsed: Bool) {
        overlayState.isCollapsed = isCollapsed
        UserDefaults.standard.set(isCollapsed, forKey: AppPreferenceKey.meetingOverlayCollapsed)
    }

    func setRealtimeTranslateEnabled(_ isEnabled: Bool) {
        overlayState.realtimeTranslateEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: AppPreferenceKey.meetingRealtimeTranslateEnabled)
        if isEnabled {
            translateEligibleSegmentsIfNeeded()
        } else {
            cancelTranslationTasks()
            clearPendingTranslationState()
        }
    }

    func setCaptureMode(_ mode: MeetingCaptureMode) async -> String? {
        guard overlayState.captureMode != mode else { return nil }
        let previousMode = overlayState.captureMode
        overlayState.captureMode = mode
        mode.persist()
        VoxtLog.meeting("Meeting capture mode changed. previous=\(previousMode.rawValue), current=\(mode.rawValue)")

        if !mode.usesMicrophone {
            micLevel = 0
            loggedInitialBufferSpeakers.remove(.me)
            microphoneStartupWatchdogTask?.cancel()
            microphoneStartupWatchdogTask = nil
        }
        if !mode.usesSystemAudio {
            systemLevel = 0
            loggedInitialBufferSpeakers.remove(.them)
        }
        guard overlayState.isRecording, !isStarting, !isStopping else {
            return nil
        }

        finalizeCurrentRecordingSlice()
        stopCaptures()
        await flushPendingAudio()
        await finishLiveSessionsIfNeeded()

        do {
            if let context = activeEngineContext, context.resolvedMode.usesLiveSessions {
                try await startLiveSessionsIfNeeded(for: context)
            }
            try startCaptures()
            recordingStartedAt = Date()
            overlayState.waveformState.reset()
            overlayState.waveformState.setActive(true)
            return nil
        } catch {
            overlayState.isRecording = false
            overlayState.isPaused = true
            overlayState.audioLevel = 0
            overlayState.waveformState.setActive(false)
            return error.localizedDescription
        }
    }

    var canExport: Bool {
        overlayState.isPaused && !overlayState.segments.isEmpty
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer, level: Float, speaker: MeetingSpeaker) {
        guard overlayState.isRecording || isStarting else { return }
        guard overlayState.captureMode.includes(speaker: speaker) else { return }
        let sampleRate = buffer.format.sampleRate
        let bufferEndSeconds = currentTimelineOffsetSeconds()
        if speaker == .me {
            micLevel = level
            if loggedInitialBufferSpeakers.contains(.me) == false {
                microphoneStartupWatchdogTask?.cancel()
                microphoneStartupWatchdogTask = nil
            }
        } else {
            systemLevel = level
        }
        let displayLevel = min(
            1,
            (micLevel * 0.76) +
            (systemLevel * 0.42) +
            max(micLevel * 0.16, systemLevel * 0.1)
        )
        if overlayState.isModelInitializing {
            overlayState.audioLevel = 0
            overlayState.waveformState.ingest(level: 0)
        } else {
            overlayState.audioLevel = displayLevel
            overlayState.waveformState.ingest(level: displayLevel)
        }

        if !loggedInitialBufferSpeakers.contains(speaker) {
            loggedInitialBufferSpeakers.insert(speaker)
            VoxtLog.meeting(
                "Meeting audio buffer received. speaker=\(speaker.rawValue), level=\(String(format: "%.3f", level)), sampleRate=\(Int(buffer.format.sampleRate)), channels=\(buffer.format.channelCount), format=\(buffer.format.commonFormat.rawValue)",
                verbose: true
            )
        }

        guard let samples = Self.extractMonoSamples(from: buffer) else {
            if !loggedSampleExtractionFailureSpeakers.contains(speaker) {
                loggedSampleExtractionFailureSpeakers.insert(speaker)
                VoxtLog.meetingWarning(
                    "Meeting audio sample extraction failed. speaker=\(speaker.rawValue), interleaved=\(buffer.format.isInterleaved), sampleRate=\(Int(buffer.format.sampleRate)), channels=\(buffer.format.channelCount), format=\(buffer.format.commonFormat.rawValue)"
                )
            }
            return
        }

        let bufferDuration = Double(samples.count) / sampleRate
        let bufferStartSeconds = max(bufferEndSeconds - bufferDuration, 0)

        let taskID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.markPendingTaskCompleted(taskID)
                }
            }
            await self.audioArchive.append(
                samples: samples,
                sampleRate: sampleRate,
                speaker: speaker,
                startSeconds: bufferStartSeconds
            )
            if await MainActor.run(body: { self.usesLiveSessionPath }) {
                await MainActor.run {
                    self.liveAudioPrebuffers[speaker, default: MeetingLiveAudioPrebuffer(maxDuration: 1.0)]
                        .append(samples: samples, sampleRate: sampleRate)
                }
                let hadLiveSession = await MainActor.run { self.liveSessions[speaker] != nil }
                if hadLiveSession,
                   let liveSession = await MainActor.run(body: { self.liveSessions[speaker] }) {
                    await liveSession.append(samples: samples, sampleRate: sampleRate)
                } else if await MainActor.run(body: { self.shouldReconnectLiveSession(for: speaker, level: level) }),
                          let _ = await self.ensureLiveSession(for: speaker) {}
                return
            }
            if let liveSession = await MainActor.run(body: { self.liveSessions[speaker] }) {
                await liveSession.append(samples: samples, sampleRate: sampleRate)
                return
            }
            let voiceActivity = await self.voiceActivityDetector.activity(
                samples: samples,
                sampleRate: sampleRate,
                speaker: speaker,
                fallbackLevel: level,
                fallbackThreshold: Self.speechThreshold(for: speaker)
            )
            let chunk: BufferedMeetingChunk?
            if speaker == .me {
                chunk = await self.micAccumulator.append(
                    samples: samples,
                    sampleRate: sampleRate,
                    level: level,
                    voiceActivityIsSpeech: voiceActivity.isSpeech,
                    bufferEndSeconds: bufferEndSeconds
                )
            } else {
                chunk = await self.systemAccumulator.append(
                    samples: samples,
                    sampleRate: sampleRate,
                    level: level,
                    voiceActivityIsSpeech: voiceActivity.isSpeech,
                    bufferEndSeconds: bufferEndSeconds
                )
            }
            guard let chunk else { return }
            await MainActor.run {
                if !self.loggedChunkSpeakers.contains(speaker) {
                    self.loggedChunkSpeakers.insert(speaker)
                    VoxtLog.meeting(
                        "Meeting audio chunk ready. speaker=\(speaker.rawValue), duration=\(String(format: "%.2f", chunk.endSeconds - chunk.startSeconds))s, sampleCount=\(chunk.samples.count)",
                        verbose: true
                    )
                }
            }
            await self.enqueue(chunk: chunk)
        }
        pendingTasks[taskID] = task
        pruneCompletedTasks()
    }

    private func shouldReconnectLiveSession(for speaker: MeetingSpeaker, level: Float) -> Bool {
        guard usesLiveSessionPath,
              overlayState.captureMode.includes(speaker: speaker),
              !isStopping,
              overlayState.isPresented,
              !overlayState.isPaused,
              overlayState.isRecording || isStarting,
              liveSessions[speaker] == nil
        else {
            return false
        }

        let speechLevelThreshold: Float = (speaker == .me) ? 0.08 : 0.11
        return level >= speechLevelThreshold
    }

    private static func speechThreshold(for speaker: MeetingSpeaker) -> Float {
        speaker == .me ? micSpeechThreshold : systemSpeechThreshold
    }

    private func enqueue(chunk: BufferedMeetingChunk) async {
        guard let transcriber else {
            pendingChunks.append(chunk)
            return
        }
        if let segment = await transcriber.transcribe(chunk: chunk) {
            await MainActor.run { [weak self] in
                guard let self, self.overlayState.isPresented else { return }
                self.applyTranscriptEvent(chunk.isFinal ? .final(segment) : .partial(segment))
            }
        }
    }

    private func drainPendingChunksIfNeeded() async {
        guard transcriber != nil, !pendingChunks.isEmpty else { return }
        let chunks = pendingChunks.sorted(by: { lhs, rhs in
            if lhs.startSeconds == rhs.startSeconds {
                return lhs.speaker.rawValue < rhs.speaker.rawValue
            }
            return lhs.startSeconds < rhs.startSeconds
        })
        pendingChunks.removeAll()
        for chunk in chunks {
            await enqueue(chunk: chunk)
        }
    }

    private func pruneCompletedTasks() {
        for taskID in completedPendingTaskIDs {
            pendingTasks[taskID] = nil
        }
        completedPendingTaskIDs.removeAll()
        pendingTasks = pendingTasks.filter { !$0.value.isCancelled }
    }

    private func markPendingTaskCompleted(_ taskID: UUID) {
        if pendingTasks.removeValue(forKey: taskID) == nil {
            completedPendingTaskIDs.insert(taskID)
        }
    }

    private func cleanupSessionState(shouldLogCaptureStop: Bool = true) {
        stopCaptures(shouldLog: shouldLogCaptureStop)
        Task {
            await self.transcriber?.cancelPendingWork()
            await self.cancelLiveSessionsIfNeeded()
        }
        cancelTranslationTasks()
        micLevel = 0
        systemLevel = 0
        loggedInitialBufferSpeakers.removeAll()
        loggedChunkSpeakers.removeAll()
        loggedSampleExtractionFailureSpeakers.removeAll()
        recordingStartedAt = nil
        accumulatedRecordingDuration = 0
        completedPendingTaskIDs.removeAll()
        pendingChunks.removeAll()
        Task {
            await voiceActivityDetector.reset()
        }
        microphoneStartupWatchdogTask?.cancel()
        microphoneStartupWatchdogTask = nil
        microphoneStartupRetryCount = 0
        liveAudioPrebuffers = [
            .me: MeetingLiveAudioPrebuffer(maxDuration: 1.0),
            .them: MeetingLiveAudioPrebuffer(maxDuration: 1.0)
        ]
        isStarting = false
        isStopping = false
        releaseActiveLocalEngine()
        whisper = nil
        transcriber = nil
        liveSessionFactory = nil
        activeEngineContext = nil
        overlayState.isModelInitializing = false
        overlayState.isFinalizing = false
        Task {
            await audioArchive.reset()
        }
    }

    private func resetSessionPresentationState() {
        UserDefaults.standard.set(false, forKey: AppPreferenceKey.meetingOverlayCollapsed)
        UserDefaults.standard.set(false, forKey: AppPreferenceKey.meetingRealtimeTranslateEnabled)
    }

    private func startCaptures() throws {
        let captureMode = overlayState.captureMode
        VoxtLog.meeting("Meeting capture start requested. captureMode=\(captureMode.rawValue)", verbose: true)
        microphoneStartupRetryCount = 0
        loggedInitialBufferSpeakers.remove(.me)
        loggedInitialBufferSpeakers.remove(.them)
        loggedSampleExtractionFailureSpeakers.remove(.me)
        loggedSampleExtractionFailureSpeakers.remove(.them)

        let resolvedInputDeviceID: AudioDeviceID?
        if captureMode.usesMicrophone {
            let availableDevices = AudioInputDeviceManager.snapshotAvailableInputDevices()
            resolvedInputDeviceID = AudioInputDeviceManager.resolvedInputDeviceID(
                from: availableDevices,
                preferredID: preferredInputDeviceIDProvider()
            )
            if let preferredInputDeviceID = preferredInputDeviceIDProvider(),
               preferredInputDeviceID != resolvedInputDeviceID {
                VoxtLog.meeting(
                    "Meeting microphone input device fallback applied. preferred=\(preferredInputDeviceID), resolved=\(resolvedInputDeviceID.map(String.init(describing:)) ?? "default")"
                )
            }
            microphoneCapture.setPreferredInputDevice(resolvedInputDeviceID)
            try startMicrophoneCapture(with: resolvedInputDeviceID)
        } else {
            resolvedInputDeviceID = nil
        }

        if captureMode.usesSystemAudio {
            do {
                try systemAudioCapture.start { [weak self] buffer, level in
                    Task { @MainActor [weak self] in
                        self?.handleBuffer(buffer, level: level, speaker: .them)
                    }
                }
            } catch {
                if captureMode.usesMicrophone {
                    microphoneCapture.stop()
                }
                throw error
            }
        }

        if captureMode.usesMicrophone {
            scheduleMicrophoneStartupWatchdog(with: resolvedInputDeviceID)
        }
    }

    private func stopCaptures(shouldLog: Bool = true) {
        if shouldLog {
            VoxtLog.meeting("Meeting capture stop requested.", verbose: true)
        }
        microphoneStartupWatchdogTask?.cancel()
        microphoneStartupWatchdogTask = nil
        microphoneCapture.stop()
        systemAudioCapture.stop()
    }

    private func startMicrophoneCapture(with deviceID: AudioDeviceID?) throws {
        microphoneCapture.setPreferredInputDevice(deviceID)
        try microphoneCapture.start { [weak self] buffer, level in
            Task { @MainActor [weak self] in
                self?.handleBuffer(buffer, level: level, speaker: .me)
            }
        }
    }

    private func scheduleMicrophoneStartupWatchdog(with deviceID: AudioDeviceID?) {
        microphoneStartupWatchdogTask?.cancel()
        microphoneStartupWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(1200))
            } catch {
                return
            }

            guard !Task.isCancelled,
                  (self.overlayState.isRecording || self.isStarting),
                  self.overlayState.isPresented,
                  !self.loggedInitialBufferSpeakers.contains(.me),
                  self.microphoneStartupRetryCount < 1
            else {
                return
            }

            self.microphoneStartupRetryCount += 1
            let retryDeviceID: AudioDeviceID? = self.microphoneStartupRetryCount == 1 ? AudioDeviceID(kAudioObjectUnknown) : deviceID
            let modeDescription = (retryDeviceID == nil || retryDeviceID == AudioDeviceID(kAudioObjectUnknown)) ? "default-input" : "preferred-input"
            VoxtLog.meetingWarning("Meeting microphone startup watchdog restarting capture after missing initial callback. mode=\(modeDescription)")
            do {
                self.microphoneCapture.stop()
                try self.startMicrophoneCapture(with: retryDeviceID == AudioDeviceID(kAudioObjectUnknown) ? nil : retryDeviceID)
                self.scheduleMicrophoneStartupWatchdog(with: retryDeviceID == AudioDeviceID(kAudioObjectUnknown) ? nil : retryDeviceID)
            } catch {
                VoxtLog.meetingWarning("Meeting microphone watchdog restart failed: \(error.localizedDescription)")
            }
        }
    }

    func switchMicrophoneInput(to deviceID: AudioDeviceID?) throws {
        guard overlayState.captureMode.usesMicrophone else { return }
        microphoneStartupWatchdogTask?.cancel()
        microphoneCapture.stop()
        microphoneCapture.setPreferredInputDevice(deviceID)
        try startMicrophoneCapture(with: deviceID)
        scheduleMicrophoneStartupWatchdog(with: deviceID)
    }

    private func finalizeCurrentRecordingSlice() {
        if let recordingStartedAt {
            accumulatedRecordingDuration += max(Date().timeIntervalSince(recordingStartedAt), 0)
        }
        recordingStartedAt = nil
    }

    private func flushPendingAudio() async {
        let activeTasks = Array(pendingTasks.values)
        pendingTasks.removeAll()
        for task in activeTasks {
            await task.value
        }
        completedPendingTaskIDs.removeAll()

        guard liveSessions.isEmpty else { return }

        let timelineEndSeconds = currentTimelineOffsetSeconds()
        if let micChunk = await micAccumulator.finish(at: timelineEndSeconds) {
            await enqueue(chunk: micChunk)
        }
        if let systemChunk = await systemAccumulator.finish(at: timelineEndSeconds) {
            await enqueue(chunk: systemChunk)
        }
    }

    private func discardPendingAudioWork() {
        pendingTasks.values.forEach { $0.cancel() }
        pendingTasks.removeAll()
        completedPendingTaskIDs.removeAll()
        pendingChunks.removeAll()
    }

    private func flushPendingTranslations() async {
        let activeTasks = Array(translationTasks.values)
        for task in activeTasks {
            await task.value
        }
    }

    private func persistMeetingAudioArchive() async throws -> URL? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Voxt-Meeting-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let didExport = try await audioArchive.exportWAV(to: tempURL)
        return didExport ? tempURL : nil
    }

    private func shouldTranslate(segment: MeetingTranscriptSegment) -> Bool {
        overlayState.realtimeTranslateEnabled &&
        segment.speaker == .them &&
        realtimeTranslationTargetLanguageProvider() != nil
    }

    private func translateEligibleSegmentsIfNeeded() {
        for segment in overlayState.segments where segment.speaker == .them {
            let needsTranslation =
                segment.isTranslationPending ||
                (segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            guard needsTranslation else { continue }
            queueRealtimeTranslation(
                for: segment.isTranslationPending
                    ? segment
                    : segment.updatingTranslation(translatedText: segment.translatedText, isTranslationPending: true)
            )
        }
        overlayState.segments = overlayState.segments.map { segment in
            guard overlayState.realtimeTranslateEnabled,
                  segment.speaker == .them,
                  (segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            else {
                return segment
            }
            return segment.updatingTranslation(translatedText: segment.translatedText, isTranslationPending: true)
        }
    }

    private func queueRealtimeTranslation(for segment: MeetingTranscriptSegment) {
        guard overlayState.realtimeTranslateEnabled,
              segment.speaker == .them,
              translationTasks[segment.id] == nil,
              let targetLanguage = realtimeTranslationTargetLanguageProvider()
        else {
            return
        }

        updateSegment(segment.id) { current in
            current.updatingTranslation(
                translatedText: current.translatedText,
                isTranslationPending: true
            )
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.translationTasks[segment.id] = nil }

            do {
                let translatedText = try await self.realtimeTranslationHandler(segment.text, targetLanguage)
                let trimmed = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                self.updateSegment(segment.id) { current in
                    current.updatingTranslation(
                        translatedText: trimmed.isEmpty ? nil : trimmed,
                        isTranslationPending: false
                    )
                }
            } catch {
                VoxtLog.meetingWarning("Meeting realtime translation failed: \(error)")
                self.updateSegment(segment.id) { current in
                    current.updatingTranslation(
                        translatedText: current.translatedText,
                        isTranslationPending: false
                    )
                }
            }
        }
        translationTasks[segment.id] = task
    }

    private func cancelTranslationTask(for segmentID: UUID) {
        translationTasks[segmentID]?.cancel()
        translationTasks[segmentID] = nil
    }

    private func cancelTranslationTasks() {
        for task in translationTasks.values {
            task.cancel()
        }
        translationTasks.removeAll()
    }

    private func clearPendingTranslationState() {
        overlayState.segments = overlayState.segments.map { segment in
            guard segment.isTranslationPending else { return segment }
            return segment.updatingTranslation(
                translatedText: segment.translatedText,
                isTranslationPending: false
            )
        }
    }

    private func finalizedSegments(from segments: [MeetingTranscriptSegment]) -> [MeetingTranscriptSegment] {
        segments.map { segment in
            guard segment.isTranslationPending else { return segment }
            return segment.updatingTranslation(
                translatedText: segment.translatedText,
                isTranslationPending: false
            )
        }
    }

    private func updateSegment(
        _ segmentID: UUID,
        transform: (MeetingTranscriptSegment) -> MeetingTranscriptSegment
    ) {
        guard let index = overlayState.segments.firstIndex(where: { $0.id == segmentID }) else { return }
        overlayState.segments[index] = transform(overlayState.segments[index])
    }

    private func applyTranscriptEvent(_ event: MeetingTranscriptEvent) {
        switch event {
        case .failed(let speaker, let message):
            VoxtLog.meetingError("Meeting live transcription failed. speaker=\(speaker.rawValue), detail=\(message)")
            liveSessions[speaker] = nil
            return
        case .finished(let speaker):
            liveSessions[speaker] = nil
            return
        case .partial, .final:
            break
        }

        var finalizedSegmentsForTranslation: [MeetingTranscriptSegment] = []
        for normalizedEvent in normalizedTranscriptEvents(for: event) {
            let result = MeetingTranscriptAssembler.apply(normalizedEvent, to: overlayState.segments)
            for segmentID in result.supersededSegmentIDs {
                cancelTranslationTask(for: segmentID)
            }
            overlayState.segments = result.segments

            guard let finalizedSegmentID = result.finalizedSegmentID,
                  let finalizedSegment = overlayState.segments.first(where: { $0.id == finalizedSegmentID }),
                  shouldTranslate(segment: finalizedSegment)
            else {
                continue
            }

            let translationReadySegment = finalizedSegment.updatingTranslation(
                translatedText: finalizedSegment.translatedText,
                isTranslationPending: true
            )
            updateSegment(finalizedSegmentID) { _ in translationReadySegment }
            finalizedSegmentsForTranslation.append(translationReadySegment)
        }

        for segment in finalizedSegmentsForTranslation {
            queueRealtimeTranslation(for: segment)
        }
    }

    private func normalizedTranscriptEvents(for event: MeetingTranscriptEvent) -> [MeetingTranscriptEvent] {
        let event = meetingDisplayNormalizedEvent(event)
        guard case .final(let segment) = event else {
            return [event]
        }
        if let mergedEvent = liveOverlayMergedShortFinalEvent(for: segment) {
            return [mergedEvent]
        }
        let readableSegments = MeetingTranscriptPostProcessor.process(
            [segment],
            options: .liveOverlay
        )
        guard readableSegments.count > 1 else {
            return [event]
        }
        return readableSegments.map(MeetingTranscriptEvent.final)
    }

    private func inferredAudioSource(for speaker: MeetingSpeaker) -> TranscriptAudioSource {
        switch speaker {
        case .me:
            return .microphone
        case .them:
            return .systemAudio
        }
    }

    private func meetingDisplayNormalizedEvent(_ event: MeetingTranscriptEvent) -> MeetingTranscriptEvent {
        guard overlayState.captureMode == .meeting else { return event }

        func normalizedSegment(_ segment: MeetingTranscriptSegment) -> MeetingTranscriptSegment {
            return segment.updatingSpeakerAnalysis(
                speaker: segment.speaker,
                speakerID: nil,
                speakerDisplayName: nil,
                audioSource: segment.audioSource,
                speakerConfidence: nil
            )
        }

        switch event {
        case .partial(let segment):
            return .partial(normalizedSegment(segment))
        case .final(let segment):
            return .final(normalizedSegment(segment))
        case .failed, .finished:
            return event
        }
    }

    private func liveOverlayMergedShortFinalEvent(for segment: MeetingTranscriptSegment) -> MeetingTranscriptEvent? {
        let options = MeetingTranscriptPostProcessor.Options.liveOverlay
        guard let previous = overlayState.segments.last,
              previous.id != segment.id,
              previous.speakerIdentityKey == segment.speakerIdentityKey
        else {
            return nil
        }

        let previousEnd = previous.endSeconds ?? previous.startSeconds
        let segmentEnd = segment.endSeconds ?? segment.startSeconds
        let gap = segment.startSeconds - previousEnd
        guard segment.startSeconds >= previous.startSeconds,
              gap >= -0.05,
              gap <= options.maxSameSpeakerMergeGapSeconds
        else {
            return nil
        }

        let previousText = MeetingTranscriptTextPostProcessor.normalizedFinalText(previous.text)
        let segmentText = MeetingTranscriptTextPostProcessor.normalizedFinalText(segment.text)
        guard !previousText.isEmpty, !segmentText.isEmpty else { return nil }

        let mergedText = MeetingTranscriptTextPostProcessor.mergedTextRemovingOverlap(previousText, segmentText)
        let shouldMergeShortFragment =
            previousText.count < options.minSegmentTextCharacters ||
            segmentText.count < options.minSegmentTextCharacters
        guard shouldMergeShortFragment,
              mergedText.count <= options.maxSegmentTextCharacters,
              max(previousEnd, segmentEnd) - previous.startSeconds <= options.maxMergedDurationSeconds
        else {
            return nil
        }

        let merged = MeetingTranscriptSegment(
            id: previous.id,
            speaker: previous.speaker,
            speakerID: previous.speakerID ?? segment.speakerID,
            speakerDisplayName: previous.speakerDisplayName ?? segment.speakerDisplayName,
            audioSource: previous.audioSource ?? segment.audioSource,
            speakerConfidence: [previous.speakerConfidence, segment.speakerConfidence]
                .compactMap { $0 }
                .max(),
            startSeconds: previous.startSeconds,
            endSeconds: max(previousEnd, segmentEnd),
            text: mergedText,
            translatedText: nil,
            isTranslationPending: false,
            preventsAdjacentMerge: true
        )
        return .final(merged)
    }

    private func reconfigureAccumulators(for profile: MeetingChunkingProfile) {
        micAccumulator = MeetingChunkAccumulator(speaker: .me, speechThreshold: Self.micSpeechThreshold, profile: profile)
        systemAccumulator = MeetingChunkAccumulator(speaker: .them, speechThreshold: Self.systemSpeechThreshold, profile: profile)
        Task {
            await voiceActivityDetector.refreshFromPreferences()
            await voiceActivityDetector.reset()
        }
    }

    private func optimizedFinalTranscriptSegments(
        fallbackSegments: [MeetingTranscriptSegment],
        finalTranscriptionDescriptors: [MeetingAudioAssetDescriptor],
        shouldFlushPendingAudio: Bool
    ) async -> [MeetingTranscriptSegment] {
        guard shouldFlushPendingAudio,
              MeetingFinalTranscriptOptimization.isEnabled(),
              !finalTranscriptionDescriptors.isEmpty,
              let transcriber
        else {
            return MeetingTranscriptPostProcessor.process(fallbackSegments)
        }

        let optimizedSegments = await MeetingFinalTranscriptionPass.transcribe(
            descriptors: finalTranscriptionDescriptors,
            loadAsset: { descriptor in
                await self.audioArchive.loadAsset(descriptor)
            },
            transcriber: transcriber
        )
        guard !optimizedSegments.isEmpty else {
            VoxtLog.meeting("Meeting final transcript optimization produced no segments; falling back to realtime transcript.", verbose: true)
            return MeetingTranscriptPostProcessor.process(fallbackSegments)
        }
        VoxtLog.meeting(
            "Meeting final transcript optimization succeeded. realtimeSegments=\(fallbackSegments.count), optimizedSegments=\(optimizedSegments.count)",
            verbose: true
        )
        return optimizedSegments
    }

    private func speechValidatedFinalSegments(
        _ segments: [MeetingTranscriptSegment],
        captureMode: MeetingCaptureMode
    ) async -> [MeetingTranscriptSegment] {
        guard !segments.isEmpty else { return [] }
        await voiceActivityDetector.reset()
        defer {
            Task {
                await voiceActivityDetector.reset()
            }
        }

        var output: [MeetingTranscriptSegment] = []
        for segment in segments.sorted(by: { lhs, rhs in
            if lhs.startSeconds == rhs.startSeconds {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startSeconds < rhs.startSeconds
        }) {
            if await hasSpeechEvidence(for: segment, captureMode: captureMode) {
                output.append(segment)
            } else {
                VoxtLog.meeting(
                    "Meeting final segment dropped by VAD validation. speaker=\(segment.speaker.rawValue), start=\(String(format: "%.2f", segment.startSeconds)), end=\(String(format: "%.2f", segment.endSeconds ?? segment.startSeconds)), textChars=\(segment.text.count)",
                    verbose: true
                )
            }
        }
        return output
    }

    private func hasSpeechEvidence(
        for segment: MeetingTranscriptSegment,
        captureMode: MeetingCaptureMode
    ) async -> Bool {
        let source = segment.audioSource ?? inferredAudioSource(for: segment.speaker)
        guard captureMode.includes(speaker: source.defaultSpeaker) else { return true }
        let segmentEndSeconds = max(segment.endSeconds ?? segment.startSeconds, segment.startSeconds)
        guard segmentEndSeconds > segment.startSeconds else { return true }
        guard let asset = await audioArchive.loadAssetWindow(
            source: source,
            startSeconds: segment.startSeconds,
            endSeconds: segmentEndSeconds,
            paddingSeconds: 0.12
        ) else {
            return false
        }

        let speaker = source.defaultSpeaker
        let fallbackLevel = AudioLevelMeter.normalizedLevel(
            fromSamples: asset.samples,
            noiseGate: 0.002,
            gain: 12
        )
        let decision = await voiceActivityDetector.activity(
            samples: asset.samples,
            sampleRate: asset.sampleRate,
            speaker: speaker,
            fallbackLevel: fallbackLevel,
            fallbackThreshold: Self.speechThreshold(for: speaker)
        )
        return decision.isSpeech
    }

    private func resolvedTranscriptionEngine() -> TranscriptionEngine {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.transcriptionEngine) ?? ""
        return TranscriptionEngine(rawValue: raw) ?? .mlxAudio
    }

    private func resolvedEngineContext() -> MeetingASREngineContext {
        let transcriptionEngine = resolvedTranscriptionEngine()
        let remoteSelection = resolvedRemoteASRSelection()
        let whisperRealtimeEnabled = UserDefaults.standard.object(forKey: AppPreferenceKey.whisperRealtimeEnabled) as? Bool ?? false

        let automaticContext = MeetingASRSupport.resolveContext(
            transcriptionEngine: transcriptionEngine,
            whisperModelState: whisperModelManager.state,
            whisperCurrentModelID: whisperModelManager.currentModelID,
            whisperRealtimeEnabled: whisperRealtimeEnabled,
            whisperIsCurrentModelLoaded: whisperModelManager.isCurrentModelLoaded,
            whisperDisplayTitle: whisperModelManager.displayTitle(for:),
            mlxModelState: mlxModelManager.state,
            mlxCurrentModelRepo: mlxModelManager.currentModelRepo,
            mlxIsCurrentModelLoaded: mlxModelManager.isCurrentModelLoaded,
            mlxDisplayTitle: mlxModelManager.displayTitle(for:),
            remoteProvider: remoteSelection.provider,
            remoteConfiguration: remoteSelection.configuration
        )
        let chunkingMode = MeetingChunkingMode.stored()
        return automaticContext.resolvingChunkingMode(chunkingMode)
    }

    private func makeTranscriber(for context: MeetingASREngineContext) async throws -> any MeetingSegmentTranscribing {
        liveSessionFactory = nil
        switch context.engine {
        case .whisperKit:
            whisperModelManager.beginActiveUse()
            activeLocalEngine = .whisperKit
            let whisper = try await whisperModelManager.loadWhisper()
            self.whisper = whisper
            let hintSettings = ASRHintSettingsStore.resolvedSettings(
                for: .whisperKit,
                rawValue: UserDefaults.standard.string(forKey: AppPreferenceKey.asrHintSettings)
            )
            let hintPayload = resolvedMeetingHintPayload(settings: hintSettings)
            return MeetingWhisperSegmentTranscriber(
                whisper: whisper,
                mainLanguage: resolvedMeetingMainLanguage(),
                temperature: Float(UserDefaults.standard.double(forKey: AppPreferenceKey.whisperTemperature)),
                hintPayload: hintPayload
            )
        case .mlxAudio:
            mlxModelManager.beginActiveUse()
            activeLocalEngine = .mlxAudio
            return MeetingMLXSegmentTranscriber(modelManager: mlxModelManager)
        case .remote:
            if context.resolvedMode.usesLiveSessions {
                let remoteSelection = resolvedRemoteASRSelection()
                let hintSettings = ASRHintSettingsStore.resolvedSettings(
                    for: .whisperKit,
                    rawValue: UserDefaults.standard.string(forKey: AppPreferenceKey.asrHintSettings)
                )
                liveSessionFactory = MeetingRemoteLiveSessionFactory(
                    provider: remoteSelection.provider,
                    configuration: remoteSelection.configuration,
                    hintPayload: resolvedMeetingHintPayload(settings: hintSettings)
                )
            }
            return MeetingRemoteASRSegmentTranscriber()
        case .dictation:
            throw NSError(
                domain: "Voxt.Meeting",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Direct Dictation is not supported for Meeting Notes."]
            )
        }
    }

    private func startLiveSessionsIfNeeded(for context: MeetingASREngineContext) async throws {
        guard context.resolvedMode.usesLiveSessions, let liveSessionFactory else { return }
        liveSessions.removeAll()
        let timelineOffsetSeconds = currentTimelineOffsetSeconds()

        for speaker in activeCaptureSpeakers {
            let session = try liveSessionFactory.makeSession(for: speaker, timelineOffsetSeconds: timelineOffsetSeconds)
            liveSessions[speaker] = session
            try await session.start(timelineOffsetSeconds: timelineOffsetSeconds) { [weak self] event in
                self?.applyTranscriptEvent(event)
            }
        }
    }

    private func finishLiveSessionsIfNeeded() async {
        let sessions = liveSessions.values
        liveSessions.removeAll()
        for session in sessions {
            await session.finish()
        }
    }

    private func cancelLiveSessionsIfNeeded() async {
        let sessions = liveSessions.values
        liveSessions.removeAll()
        for session in sessions {
            await session.cancel()
        }
    }

    private func releaseActiveLocalEngine() {
        guard let activeLocalEngine else { return }
        switch activeLocalEngine {
        case .whisperKit:
            whisperModelManager.endActiveUse()
        case .mlxAudio:
            mlxModelManager.endActiveUse()
        case .dictation, .remote:
            break
        }
        self.activeLocalEngine = nil
    }

    private func fallbackHistoryModelDescription() -> String {
        resolvedEngineContext().historyModelDescription
    }

    private func resolvedMeetingMainLanguage() -> UserMainLanguageOption {
        let storedCodes = UserDefaults.standard.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        let selectedOptions = UserMainLanguageOption.storedSelection(from: storedCodes)
        if let firstCode = selectedOptions.first,
           let option = UserMainLanguageOption.option(for: firstCode) {
            return option
        }
        return UserMainLanguageOption.fallbackOption()
    }

    private func resolvedMeetingHintPayload(settings: ASRHintSettings) -> ResolvedASRHintPayload {
        let storedCodes = UserDefaults.standard.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        let userLanguageCodes = UserMainLanguageOption.storedSelection(from: storedCodes)
        return ASRHintResolver.resolve(
            target: .whisperKit,
            settings: settings,
            userLanguageCodes: userLanguageCodes
        )
    }

    private func resolvedRemoteASRSelection() -> (provider: RemoteASRProvider, configuration: RemoteProviderConfiguration) {
        let provider = RemoteASRProvider(
            rawValue: UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? ""
        ) ?? .openAIWhisper
        let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: provider,
            stored: RemoteModelConfigurationStore.loadConfigurations(
                from: UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
            )
        )
        return (provider, configuration)
    }

    private static func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        AudioLevelMeter.monoSamples(from: buffer)
    }

    private var usesLiveSessionPath: Bool {
        activeEngineContext?.resolvedMode.usesLiveSessions == true || liveSessionFactory != nil
    }

    private var activeCaptureSpeakers: [MeetingSpeaker] {
        var speakers: [MeetingSpeaker] = []
        if overlayState.captureMode.usesMicrophone {
            speakers.append(.me)
        }
        if overlayState.captureMode.usesSystemAudio {
            speakers.append(.them)
        }
        return speakers
    }

    private func ensureLiveSession(for speaker: MeetingSpeaker) async -> (any MeetingLiveTranscribingSession)? {
        if let session = liveSessions[speaker] {
            return session
        }
        guard usesLiveSessionPath,
              overlayState.captureMode.includes(speaker: speaker),
              let liveSessionFactory,
              overlayState.isPresented,
              !overlayState.isPaused,
              (overlayState.isRecording || isStarting),
              !isStopping
        else {
            return nil
        }

        do {
            let prebufferFrames = liveAudioPrebuffers[speaker]?.snapshot() ?? []
            let prebufferDuration = prebufferFrames.reduce(0) { $0 + $1.duration }
            let timelineOffsetSeconds = max(currentTimelineOffsetSeconds() - prebufferDuration, 0)
            let session = try liveSessionFactory.makeSession(for: speaker, timelineOffsetSeconds: timelineOffsetSeconds)
            liveSessions[speaker] = session
            try await session.start(timelineOffsetSeconds: timelineOffsetSeconds) { [weak self] event in
                self?.applyTranscriptEvent(event)
            }
            await flushLivePrebuffer(prebufferFrames, to: session)
            return session
        } catch {
            liveSessions[speaker] = nil
            VoxtLog.meetingWarning("Meeting live session reconnect failed. speaker=\(speaker.rawValue), detail=\(error.localizedDescription)")
            return nil
        }
    }

    private func flushLivePrebuffer(
        _ frames: [MeetingLiveAudioPrebuffer.Frame],
        to session: any MeetingLiveTranscribingSession
    ) async {
        for frame in frames {
            await session.append(samples: frame.samples, sampleRate: frame.sampleRate)
        }
    }

    private func currentTimelineOffsetSeconds() -> TimeInterval {
        let activeSlice = recordingStartedAt.map { max(Date().timeIntervalSince($0), 0) } ?? 0
        return accumulatedRecordingDuration + activeSlice
    }
}

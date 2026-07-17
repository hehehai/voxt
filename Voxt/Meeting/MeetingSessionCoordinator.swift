// MeetingSessionCoordinator.swift
// Provides Meeting Session Coordinator for meeting session behavior.

import Foundation
import AVFoundation

@MainActor
final class MeetingSessionCoordinator {
    let overlayState = MeetingOverlayState()

    var onSessionFinished: (@MainActor (MeetingSessionResult) -> Bool)?

    private let mlxModelManager: MLXModelManager
    private let sherpaOnnxModelManager: SherpaOnnxModelManager
    private let microphoneCapture = MeetingMicrophoneCapture()
    private let systemAudioCapture = MeetingSystemAudioCapture()
    private static let micSpeechThreshold: Float = 0.012
    private static let systemSpeechThreshold: Float = 0.025
    private static let localLiveSessionSilenceSeconds: TimeInterval = 0.75
    private static let localLivePrebufferSeconds: TimeInterval = 0.5
    private static let localLivePendingAudioSeconds: TimeInterval = 1.25
    private static let remoteLivePrebufferSeconds: TimeInterval = 1.0
    private static let waveformPublishIntervalSeconds: TimeInterval = 1.0 / 20.0
    private var micAccumulator = MeetingChunkAccumulator(speaker: .me, speechThreshold: micSpeechThreshold, profile: .quality)
    private var systemAccumulator = MeetingChunkAccumulator(speaker: .them, speechThreshold: systemSpeechThreshold, profile: .quality)
    private let voiceActivityDetector = MeetingVoiceActivityDetector()
    private let offlineVoiceActivityDetector = MeetingOfflineVoiceActivityDetector()
    private let audioAnalysisScheduler = MeetingAudioAnalysisScheduler()
    private let orderedLiveAudioScheduler = MeetingOrderedLiveAudioScheduler()
    private var transcriber: (any MeetingSegmentTranscribing)?
    private var liveSessionFactory: (any MeetingLiveSessionFactory)?
    private var liveSessions: [MeetingSpeaker: any MeetingLiveTranscribingSession] = [:]
    private var liveSessionTokens: [MeetingSpeaker: UUID] = [:]
    private var liveAudioPrebuffers: [MeetingSpeaker: MeetingLiveAudioPrebuffer] = [:]
    private var localLiveVoiceActivityGates: [MeetingSpeaker: MeetingLocalLiveVoiceActivityGate] = [:]
    private var localLivePendingAudio: [MeetingSpeaker: MeetingLiveAudioPrebuffer] = [:]
    private var activeLocalEngine: TranscriptionEngine?
    private var activeEngineContext: MeetingASREngineContext?
    private var isStopping = false
    private var stopFinalizationTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var accumulatedRecordingDuration: TimeInterval = 0
    private(set) var hasCapturedAudio = false
    private var preferredInputDeviceIDProvider: () -> AudioDeviceID?
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    private var completedPendingTaskIDs = Set<UUID>()
    private var pendingChunks: [BufferedMeetingChunk] = []
    private let realtimeTranslationScheduler = MeetingRealtimeTranslationScheduler()
    private var microphoneStartupWatchdogTask: Task<Void, Never>?
    private var microphoneStartupRetryCount = 0
    private var micLevel: Float = 0
    private var systemLevel: Float = 0
    private var captureTimeline = MeetingCaptureTimelineTracker()
    private var lastWaveformPublishUptime: TimeInterval = 0
    private var loggedInitialBufferSpeakers = Set<MeetingSpeaker>()
    private var loggedChunkSpeakers = Set<MeetingSpeaker>()
    private var loggedSampleExtractionFailureSpeakers = Set<MeetingSpeaker>()
    private var hasLoggedAudioAnalysisOverload = false
    private var hasLoggedTranslationOverload = false
    private let audioArchive = MeetingAudioArchive()
    private let memoryPressureMonitor = MeetingMemoryPressureMonitor()
    private let realtimeTranslationTargetLanguageProvider: @MainActor () -> TranslationTargetLanguage?
    private let realtimeTranslationHandler: @MainActor (String, TranslationTargetLanguage) -> MeetingTranslationOperation
    private var isStarting = false
    private var isReconfiguringCaptureMode = false

    init(
        mlxModelManager: MLXModelManager,
        sherpaOnnxModelManager: SherpaOnnxModelManager,
        preferredInputDeviceIDProvider: @escaping () -> AudioDeviceID?,
        realtimeTranslationTargetLanguageProvider: @escaping @MainActor () -> TranslationTargetLanguage?,
        realtimeTranslationHandler: @escaping @MainActor (String, TranslationTargetLanguage) -> MeetingTranslationOperation
    ) {
        self.mlxModelManager = mlxModelManager
        self.sherpaOnnxModelManager = sherpaOnnxModelManager
        self.preferredInputDeviceIDProvider = preferredInputDeviceIDProvider
        self.realtimeTranslationTargetLanguageProvider = realtimeTranslationTargetLanguageProvider
        self.realtimeTranslationHandler = realtimeTranslationHandler
        memoryPressureMonitor.start { isConstrained in
            Task {
                await MeetingLocalInferenceCoordinator.shared.setMemoryPressureConstrained(isConstrained)
            }
        }
        self.liveAudioPrebuffers = Self.makeLiveAudioPrebuffers(
            maxDuration: Self.remoteLivePrebufferSeconds
        )
    }

    var isActive: Bool {
        isStarting || overlayState.isPresented || overlayState.isRecording || overlayState.isPaused || activeLocalEngine != nil || isStopping
    }

    var isStartingUp: Bool {
        isStarting
    }

    func releaseIdleVADResources() async {
        guard !isActive else { return }
        await voiceActivityDetector.releaseResources()
        await offlineVoiceActivityDetector.releaseResources()
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
        overlayState.waveformState.reset()
        overlayState.waveformState.setActive(!engineContext.needsModelInitialization)
        overlayState.isRecording = !engineContext.needsModelInitialization
        overlayState.isModelInitializing = engineContext.needsModelInitialization
        isStarting = true
        Task { await MeetingLocalInferenceCoordinator.shared.setRecordingActive(true) }
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
        await MeetingLocalInferenceCoordinator.shared.setRecordingActive(true)
        return nil
    }

    func pause() async {
        guard overlayState.isPresented, overlayState.isRecording, !isStopping else { return }
        overlayState.isRecording = false
        overlayState.isPaused = true
        overlayState.waveformState.setActive(false)
        finalizeCurrentRecordingSlice()
        stopCaptures()
        await MeetingLocalInferenceCoordinator.shared.setRecordingActive(false)
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
            await MeetingLocalInferenceCoordinator.shared.setRecordingActive(true)
            return nil
        } catch {
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
        overlayState.waveformState.setActive(false)

        finalizeCurrentRecordingSlice()
        stopCaptures()
        Task { await MeetingLocalInferenceCoordinator.shared.setRecordingActive(false) }
        let finalizationSessionID = UUID()

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
            if shouldFlushPendingAudio {
                await MeetingFinalizationCheckpointStore.shared.save(
                    MeetingFinalizationCheckpoint(
                        sessionID: finalizationSessionID,
                        updatedAt: Date(),
                        stage: .captured,
                        captureMode: captureMode,
                        transcriptionEngineRawValue: (self.activeEngineContext?.engine ?? self.resolvedTranscriptionEngine()).rawValue,
                        transcriptionModelDescription: self.activeEngineContext?.historyModelDescription ?? self.fallbackHistoryModelDescription(),
                        segments: finalSegmentsBeforeSpeakerAnalysis,
                        visibleSnapshotSegments: visibleSnapshotSegments,
                        audioDurationSeconds: duration,
                        archivedAudioPath: archivedAudioURL?.path
                    )
                )
            }
            let finalTranscriptionDescriptors = shouldFlushPendingAudio ? await self.audioArchive.finalTranscriptionAssetDescriptors() : []
            let speakerAnalysisDescriptors = shouldFlushPendingAudio ? await self.audioArchive.analysisAssetDescriptors(for: captureMode) : []
            let finalVADPolicy = MeetingFinalSpeechValidator.vadPolicy(
                transcriptionEngine: self.activeEngineContext?.engine ?? self.resolvedTranscriptionEngine(),
                mlxModelRepo: self.activeEngineContext?.mlxModelRepo ?? self.mlxModelManager.currentModelRepo
            )
            let finalTranscriptSegments = await self.optimizedFinalTranscriptSegments(
                fallbackSegments: finalSegmentsBeforeSpeakerAnalysis,
                finalTranscriptionDescriptors: finalTranscriptionDescriptors,
                shouldFlushPendingAudio: shouldFlushPendingAudio
            )
            let finalSpeechEvidence = await self.finalSpeechEvidence(
                descriptors: finalTranscriptionDescriptors,
                captureMode: captureMode,
                policy: finalVADPolicy,
                shouldValidate: shouldFlushPendingAudio
            )
            let speechValidatedFinalTranscriptSegments = MeetingFinalSpeechValidator.validatedSegments(
                finalTranscriptSegments,
                policy: finalVADPolicy,
                evidence: finalSpeechEvidence
            )
            if shouldFlushPendingAudio {
                await MeetingFinalizationCheckpointStore.shared.save(
                    MeetingFinalizationCheckpoint(
                        sessionID: finalizationSessionID,
                        updatedAt: Date(),
                        stage: .finalTranscript,
                        captureMode: captureMode,
                        transcriptionEngineRawValue: (self.activeEngineContext?.engine ?? self.resolvedTranscriptionEngine()).rawValue,
                        transcriptionModelDescription: self.activeEngineContext?.historyModelDescription ?? self.fallbackHistoryModelDescription(),
                        segments: speechValidatedFinalTranscriptSegments,
                        visibleSnapshotSegments: visibleSnapshotSegments,
                        audioDurationSeconds: duration,
                        archivedAudioPath: archivedAudioURL?.path
                    )
                )
            }
            let speakerAnalysisOptions = MeetingSpeakerDiarizationOptions.fromPreferences()
            let finalSegments: [MeetingTranscriptSegment]
            if captureMode.capabilities.allowsSpeakerFeatures {
                do {
                    finalSegments = try await MeetingLocalInferenceCoordinator.shared.withPermit(.speakerAnalysis) {
                        await MeetingSpeakerAnalysisPipeline.analyzedSegmentsPreservingStructuredSpeakerData(
                            from: speechValidatedFinalTranscriptSegments,
                            descriptors: speakerAnalysisDescriptors,
                            loadAsset: { descriptor in
                                await self.audioArchive.loadAsset(descriptor)
                            },
                            options: speakerAnalysisOptions
                        )
                    }
                } catch {
                    VoxtLog.meetingWarning("Meeting speaker analysis skipped by device safety policy: \(error.localizedDescription)")
                    finalSegments = MeetingTranscriptPostProcessor.process(speechValidatedFinalTranscriptSegments)
                }
            } else {
                finalSegments = MeetingTranscriptPostProcessor.process(speechValidatedFinalTranscriptSegments)
            }
            let sortedFinalSegments = finalSegments.sorted { lhs, rhs in
                if lhs.startSeconds == rhs.startSeconds {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.startSeconds < rhs.startSeconds
            }
            let speechValidatedVisibleSnapshotSegments = MeetingFinalSpeechValidator.validatedSegments(
                visibleSnapshotSegments,
                policy: finalVADPolicy,
                evidence: shouldFlushPendingAudio ? finalSpeechEvidence : nil
            )
            await MainActor.run {
                self.overlayState.segments = sortedFinalSegments
            }
            if shouldFlushPendingAudio {
                await MeetingFinalizationCheckpointStore.shared.save(
                    MeetingFinalizationCheckpoint(
                        sessionID: finalizationSessionID,
                        updatedAt: Date(),
                        stage: .speakerAnalysis,
                        captureMode: captureMode,
                        transcriptionEngineRawValue: (self.activeEngineContext?.engine ?? self.resolvedTranscriptionEngine()).rawValue,
                        transcriptionModelDescription: self.activeEngineContext?.historyModelDescription ?? self.fallbackHistoryModelDescription(),
                        segments: sortedFinalSegments,
                        visibleSnapshotSegments: visibleSnapshotSegments,
                        audioDurationSeconds: duration,
                        archivedAudioPath: archivedAudioURL?.path
                    )
                )
            }
            let result = MeetingSessionResult(
                recoverySessionID: shouldFlushPendingAudio ? finalizationSessionID : nil,
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

            if shouldFlushPendingAudio {
                let archiveStatistics = await self.audioArchive.currentIOStatistics()
                let analysisStatistics = await self.audioAnalysisScheduler.currentStatistics()
                let liveAnalysisStatistics = await self.orderedLiveAudioScheduler.currentStatistics()
                let inferenceStatistics = await MeetingLocalInferenceCoordinator.shared.currentStatistics()
                let translationStatistics = self.realtimeTranslationScheduler.currentStatistics()
                await MainActor.run {
                    VoxtLog.meeting(
                        "Meeting audio archive I/O summary. appends=\(archiveStatistics.appendCount), resamples=\(archiveStatistics.resampleCount), writes=\(archiveStatistics.writeOperationCount), writeHandleOpens=\(archiveStatistics.writeHandleOpenCount), writtenBytes=\(archiveStatistics.writtenByteCount), reads=\(archiveStatistics.readOperationCount), readHandleOpens=\(archiveStatistics.readHandleOpenCount), readBytes=\(archiveStatistics.readByteCount)",
                        verbose: true
                    )
                    VoxtLog.meeting(
                        "Meeting audio analysis summary. submittedFrames=\(analysisStatistics.submittedFrameCount), mergedFrames=\(analysisStatistics.mergedFrameCount), processedBatches=\(analysisStatistics.processedBatchCount), overloadedFrames=\(analysisStatistics.overloadedFrameCount), peakPendingAudioSeconds=\(String(format: "%.2f", analysisStatistics.peakPendingAudioSeconds))",
                        verbose: true
                    )
                    VoxtLog.meeting(
                        "Meeting ordered live audio summary. submittedFrames=\(liveAnalysisStatistics.submittedFrameCount), processedFrames=\(liveAnalysisStatistics.processedBatchCount), overloadedFrames=\(liveAnalysisStatistics.overloadedFrameCount), peakPendingAudioSeconds=\(String(format: "%.2f", liveAnalysisStatistics.peakPendingAudioSeconds))",
                        verbose: true
                    )
                    VoxtLog.meeting(
                        "Meeting realtime translation summary. submitted=\(translationStatistics.submittedCount), completed=\(translationStatistics.completedCount), failed=\(translationStatistics.failedCount), cancelled=\(translationStatistics.cancelledCount), overloaded=\(translationStatistics.overloadedCount), peakScheduled=\(translationStatistics.peakScheduledCount), batches=\(translationStatistics.inferenceBatchCount), peakBatch=\(translationStatistics.peakBatchSize)",
                        verbose: true
                    )
                    VoxtLog.meeting(
                        "Meeting local inference summary. submitted=\(inferenceStatistics.submittedCount), completed=\(inferenceStatistics.completedCount), cancelled=\(inferenceStatistics.cancelledCount), overloaded=\(inferenceStatistics.overloadedCount), thermalDeferrals=\(inferenceStatistics.thermalDeferralCount), memoryDeferrals=\(inferenceStatistics.memoryDeferralCount), peakQueued=\(inferenceStatistics.peakQueuedCount), totalWaitMs=\(inferenceStatistics.totalWaitMilliseconds)",
                        verbose: true
                    )
                    self.realtimeTranslationScheduler.resetStatistics()
                }
                await self.audioAnalysisScheduler.resetStatistics()
                await self.orderedLiveAudioScheduler.resetStatistics()
                await MeetingLocalInferenceCoordinator.shared.resetStatistics()
            }

            await MainActor.run {
                VoxtLog.meeting(
                    "Meeting session finished. visibleSegments=\(visibleSnapshotSegments.count), persistedSegments=\(result.persistedSegments.count), duration=\(String(format: "%.2f", duration))s"
                )
            }
            self.cleanupSessionState()
            self.resetSessionPresentationState()
            self.overlayState.reset()
            let didSafelyHandleResult = self.onSessionFinished?(result) ?? false
            if shouldFlushPendingAudio, didSafelyHandleResult {
                await MeetingFinalizationCheckpointStore.shared.clear(sessionID: finalizationSessionID)
            }
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
        let sourceTransition = previousMode.sourceTransition(to: mode)
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
        isReconfiguringCaptureMode = true
        stopCaptureSources(for: sourceTransition)
        await flushPendingAudio()
        await finishLiveSessionsIfNeeded()

        do {
            if let context = activeEngineContext, context.resolvedMode.usesLiveSessions {
                try await startLiveSessionsIfNeeded(for: context)
            }
            try startCaptureSources(for: sourceTransition)
            recordingStartedAt = Date()
            overlayState.waveformState.reset()
            overlayState.waveformState.setActive(true)
            isReconfiguringCaptureMode = false
            return nil
        } catch {
            await cancelLiveSessionsIfNeeded()
            stopCaptures()
            isReconfiguringCaptureMode = false
            overlayState.isRecording = false
            overlayState.isPaused = true
            overlayState.waveformState.setActive(false)
            return error.localizedDescription
        }
    }

    var canExport: Bool {
        overlayState.isPaused && !overlayState.segments.isEmpty
    }

    private func handleSamples(
        _ samples: [Float],
        sampleRate: Double,
        level: Float,
        speaker: MeetingSpeaker,
        captureGeneration: UInt64
    ) {
        guard overlayState.isRecording || isStarting else { return }
        guard !isReconfiguringCaptureMode else { return }
        guard overlayState.captureMode.includes(speaker: speaker) else { return }
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
        publishWaveformLevel(overlayState.isModelInitializing ? 0 : displayLevel)

        if !loggedInitialBufferSpeakers.contains(speaker) {
            loggedInitialBufferSpeakers.insert(speaker)
            VoxtLog.meeting(
                "Meeting audio buffer received. speaker=\(speaker.rawValue), level=\(String(format: "%.3f", level)), sampleRate=\(Int(sampleRate)), sampleCount=\(samples.count)",
                verbose: true
            )
        }

        guard !samples.isEmpty else { return }
        hasCapturedAudio = true

        let bufferDuration = Double(samples.count) / sampleRate
        let fallbackEndSeconds = currentTimelineOffsetSeconds()
        guard let timelineRange = captureTimeline.nextRange(
            for: speaker,
            generation: captureGeneration,
            durationSeconds: bufferDuration,
            fallbackEndSeconds: fallbackEndSeconds
        ) else { return }
        let bufferStartSeconds = timelineRange.lowerBound
        let bufferEndSeconds = timelineRange.upperBound

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
            if let safetyMessage = await self.audioArchive.consumeSafetyFailureMessage() {
                await MainActor.run {
                    self.overlayState.safetyMessage = safetyMessage
                    _ = self.stop(shouldFlushPendingAudio: true)
                }
                return
            }
            let frame = MeetingAudioAnalysisFrame(
                samples: samples,
                sampleRate: sampleRate,
                level: level,
                speaker: speaker,
                startSeconds: bufferStartSeconds,
                endSeconds: bufferEndSeconds
            )
            if await MainActor.run(body: { self.usesLiveSessionPath }) {
                let submission = await self.orderedLiveAudioScheduler.submit(frame) { [weak self] frame in
                    await self?.processAudioAnalysisFrame(frame)
                }
                if case .overloaded(let pendingAudioSeconds) = submission {
                    self.logAudioAnalysisOverloadIfNeeded(
                        pendingAudioSeconds: pendingAudioSeconds
                    )
                }
            } else {
                let submission = await self.audioAnalysisScheduler.submit(frame) { [weak self] frame in
                    await self?.processAudioAnalysisFrame(frame)
                }
                if case .overloaded(let pendingAudioSeconds) = submission {
                    self.logAudioAnalysisOverloadIfNeeded(
                        pendingAudioSeconds: pendingAudioSeconds
                    )
                }
            }
        }
        pendingTasks[taskID] = task
        pruneCompletedTasks()
    }

    private func logAudioAnalysisOverloadIfNeeded(pendingAudioSeconds: TimeInterval) {
        guard !hasLoggedAudioAnalysisOverload else { return }
        hasLoggedAudioAnalysisOverload = true
        VoxtLog.meetingWarning(
            "Meeting realtime audio analysis reached its 10-second safety bound; archived audio remains complete and the overloaded realtime frame was skipped. pendingAudioSeconds=\(String(format: "%.2f", pendingAudioSeconds))"
        )
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

    private func processAudioAnalysisFrame(_ frame: MeetingAudioAnalysisFrame) async {
        if usesLiveSessionPath {
            if activeEngineContext?.resolvedMode.usesLocalVoiceActivityGate == true {
                await processLocalLiveAudioAnalysisFrame(frame)
                return
            }
            liveAudioPrebuffers[frame.speaker, default: MeetingLiveAudioPrebuffer(maxDuration: 1.0)]
                .append(samples: frame.samples, sampleRate: frame.sampleRate)
            if let liveSession = liveSessions[frame.speaker] {
                await liveSession.append(samples: frame.samples, sampleRate: frame.sampleRate)
            } else if shouldReconnectLiveSession(for: frame.speaker, level: frame.level),
                      let _ = await ensureLiveSession(for: frame.speaker) {}
            return
        }
        if let liveSession = liveSessions[frame.speaker] {
            await liveSession.append(samples: frame.samples, sampleRate: frame.sampleRate)
            return
        }

        let voiceActivity = await voiceActivityDetector.activity(
            samples: frame.samples,
            sampleRate: frame.sampleRate,
            speaker: frame.speaker,
            fallbackLevel: frame.level,
            fallbackThreshold: Self.speechThreshold(for: frame.speaker),
            serverVADActive: serverVADActive
        )
        let chunk: BufferedMeetingChunk?
        if frame.speaker == .me {
            chunk = await micAccumulator.append(
                samples: frame.samples,
                sampleRate: frame.sampleRate,
                level: frame.level,
                voiceActivityIsSpeech: voiceActivity.isSpeech,
                bufferEndSeconds: frame.endSeconds
            )
        } else {
            chunk = await systemAccumulator.append(
                samples: frame.samples,
                sampleRate: frame.sampleRate,
                level: frame.level,
                voiceActivityIsSpeech: voiceActivity.isSpeech,
                bufferEndSeconds: frame.endSeconds
            )
        }
        guard let chunk else { return }
        if !loggedChunkSpeakers.contains(frame.speaker) {
            loggedChunkSpeakers.insert(frame.speaker)
            VoxtLog.meeting(
                "Meeting audio chunk ready. speaker=\(frame.speaker.rawValue), duration=\(String(format: "%.2f", chunk.endSeconds - chunk.startSeconds))s, sampleCount=\(chunk.samples.count)",
                verbose: true
            )
        }
        await enqueue(chunk: chunk)
    }

    private func processLocalLiveAudioAnalysisFrame(_ frame: MeetingAudioAnalysisFrame) async {
        let voiceActivity = await voiceActivityDetector.activity(
            samples: frame.samples,
            sampleRate: frame.sampleRate,
            speaker: frame.speaker,
            fallbackLevel: frame.level,
            fallbackThreshold: Self.speechThreshold(for: frame.speaker)
        )

        var gate = localLiveVoiceActivityGates[frame.speaker] ?? MeetingLocalLiveVoiceActivityGate()
        let action = gate.consume(
            isSpeech: voiceActivity.isSpeech,
            frameDuration: frame.durationSeconds,
            hasActiveSession: liveSessions[frame.speaker] != nil,
            endpointSilence: Self.localLiveSessionSilenceSeconds
        )
        localLiveVoiceActivityGates[frame.speaker] = gate

        switch action {
        case .append:
            if let liveSession = liveSessions[frame.speaker] {
                await flushLocalLivePendingAudio(
                    for: frame.speaker,
                    to: liveSession,
                    replacingWithSilence: false
                )
                await liveSession.append(samples: frame.samples, sampleRate: frame.sampleRate)
            }
        case .start:
            liveAudioPrebuffers[
                frame.speaker,
                default: MeetingLiveAudioPrebuffer(maxDuration: Self.localLivePrebufferSeconds)
            ].append(samples: frame.samples, sampleRate: frame.sampleRate)
            _ = await ensureLiveSession(
                for: frame.speaker,
                timelineEndSeconds: frame.endSeconds
            )
        case .buffer:
            // VAD confirms speech after its acoustic onset. Keep a short raw tail so
            // the first phoneme is available when the following frame starts a session.
            liveAudioPrebuffers[
                frame.speaker,
                default: MeetingLiveAudioPrebuffer(maxDuration: Self.localLivePrebufferSeconds)
            ].append(samples: frame.samples, sampleRate: frame.sampleRate)
        case .hold:
            // Delay ambiguous in-session audio. Resume flushes it unchanged; a stable
            // endpoint converts it to silence before the session is finalized.
            localLivePendingAudio[
                frame.speaker,
                default: MeetingLiveAudioPrebuffer(maxDuration: Self.localLivePendingAudioSeconds)
            ].append(samples: frame.samples, sampleRate: frame.sampleRate)
        case .finish:
            localLivePendingAudio[
                frame.speaker,
                default: MeetingLiveAudioPrebuffer(maxDuration: Self.localLivePendingAudioSeconds)
            ].append(samples: frame.samples, sampleRate: frame.sampleRate)
            await finishLiveSession(for: frame.speaker)
        }
    }

    private static func speechThreshold(for speaker: MeetingSpeaker) -> Float {
        speaker == .me ? micSpeechThreshold : systemSpeechThreshold
    }

    private func enqueue(chunk: BufferedMeetingChunk) async {
        guard let transcriber else {
            pendingChunks.append(chunk)
            return
        }
        let segments = await transcriber.transcribeSegments(chunk: chunk)
        if !segments.isEmpty {
            await MainActor.run { [weak self] in
                guard let self, self.overlayState.isPresented else { return }
                for segment in segments {
                    self.applyTranscriptEvent(chunk.isFinal ? .final(segment) : .partial(segment))
                }
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
        captureTimeline.resetCursors()
        lastWaveformPublishUptime = 0
        loggedInitialBufferSpeakers.removeAll()
        loggedChunkSpeakers.removeAll()
        loggedSampleExtractionFailureSpeakers.removeAll()
        hasLoggedAudioAnalysisOverload = false
        recordingStartedAt = nil
        accumulatedRecordingDuration = 0
        hasCapturedAudio = false
        completedPendingTaskIDs.removeAll()
        pendingChunks.removeAll()
        Task {
            await voiceActivityDetector.reset()
            await audioAnalysisScheduler.cancel()
            await orderedLiveAudioScheduler.cancel()
            await MeetingLocalInferenceCoordinator.shared.setRecordingActive(false)
        }
        microphoneStartupWatchdogTask?.cancel()
        microphoneStartupWatchdogTask = nil
        microphoneStartupRetryCount = 0
        liveAudioPrebuffers = Self.makeLiveAudioPrebuffers(
            maxDuration: Self.remoteLivePrebufferSeconds
        )
        localLiveVoiceActivityGates.removeAll(keepingCapacity: false)
        localLivePendingAudio.removeAll(keepingCapacity: false)
        isStarting = false
        isStopping = false
        releaseActiveLocalEngine()
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

    private func publishWaveformLevel(_ level: Float) {
        let now = ProcessInfo.processInfo.systemUptime
        guard lastWaveformPublishUptime == 0 ||
                now - lastWaveformPublishUptime >= Self.waveformPublishIntervalSeconds
        else {
            return
        }
        lastWaveformPublishUptime = now
        overlayState.waveformState.ingest(level: level)
    }

    private func startCaptures() throws {
        let captureMode = overlayState.captureMode
        VoxtLog.meeting("Meeting capture start requested. captureMode=\(captureMode.rawValue)", verbose: true)
        microphoneStartupRetryCount = 0
        loggedInitialBufferSpeakers.remove(.me)
        loggedInitialBufferSpeakers.remove(.them)
        loggedSampleExtractionFailureSpeakers.remove(.me)
        loggedSampleExtractionFailureSpeakers.remove(.them)
        captureTimeline.resetCursors()

        let resolvedInputDeviceID = captureMode.usesMicrophone
            ? try startConfiguredMicrophoneCapture(scheduleWatchdog: false)
            : nil

        if captureMode.usesSystemAudio {
            do {
                try startSystemAudioCapture()
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

    private func stopCaptureSources(for transition: MeetingCaptureSourceTransition) {
        if transition.stopsMicrophone {
            microphoneStartupWatchdogTask?.cancel()
            microphoneStartupWatchdogTask = nil
            microphoneCapture.stop()
        }
        if transition.stopsSystemAudio {
            systemAudioCapture.stop()
        }
    }

    private func startCaptureSources(for transition: MeetingCaptureSourceTransition) throws {
        if transition.startsMicrophone {
            _ = try startConfiguredMicrophoneCapture()
        }
        if transition.startsSystemAudio {
            try startSystemAudioCapture()
        }
    }

    private func startConfiguredMicrophoneCapture(
        scheduleWatchdog: Bool = true
    ) throws -> AudioDeviceID? {
        let availableDevices = AudioInputDeviceManager.snapshotAvailableInputDevices()
        let preferredInputDeviceID = preferredInputDeviceIDProvider()
        let resolvedInputDeviceID = AudioInputDeviceManager.resolvedInputDeviceID(
            from: availableDevices,
            preferredID: preferredInputDeviceID
        )
        if let preferredInputDeviceID, preferredInputDeviceID != resolvedInputDeviceID {
            VoxtLog.meeting(
                "Meeting microphone input device fallback applied. preferred=\(preferredInputDeviceID), resolved=\(resolvedInputDeviceID.map(String.init(describing:)) ?? "default")"
            )
        }
        try startMicrophoneCapture(with: resolvedInputDeviceID)
        if scheduleWatchdog {
            scheduleMicrophoneStartupWatchdog(with: resolvedInputDeviceID)
        }
        return resolvedInputDeviceID
    }

    private func startSystemAudioCapture() throws {
        let generation = beginCaptureEpoch(for: .them)
        try systemAudioCapture.start { [weak self] buffer, level in
            let sampleRate = buffer.format.sampleRate
            guard let samples = Self.extractMonoSamples(from: buffer) else {
                let format = buffer.format
                let isInterleaved = format.isInterleaved
                let channelCount = format.channelCount
                let commonFormatRawValue = Int(format.commonFormat.rawValue)
                Task { @MainActor [weak self] in
                    self?.logSampleExtractionFailureIfNeeded(
                        isInterleaved: isInterleaved,
                        sampleRate: sampleRate,
                        channelCount: channelCount,
                        commonFormatRawValue: commonFormatRawValue,
                        speaker: .them
                    )
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.handleSamples(
                    samples,
                    sampleRate: sampleRate,
                    level: level,
                    speaker: .them,
                    captureGeneration: generation
                )
            }
        }
        captureTimeline.anchorEpoch(
            for: .them,
            generation: generation,
            minimumStartSeconds: currentTimelineOffsetSeconds()
        )
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
        let generation = beginCaptureEpoch(for: .me)
        try microphoneCapture.start { [weak self] buffer, level in
            let sampleRate = buffer.format.sampleRate
            guard let samples = Self.extractMonoSamples(from: buffer) else {
                let format = buffer.format
                let isInterleaved = format.isInterleaved
                let channelCount = format.channelCount
                let commonFormatRawValue = Int(format.commonFormat.rawValue)
                Task { @MainActor [weak self] in
                    self?.logSampleExtractionFailureIfNeeded(
                        isInterleaved: isInterleaved,
                        sampleRate: sampleRate,
                        channelCount: channelCount,
                        commonFormatRawValue: commonFormatRawValue,
                        speaker: .me
                    )
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.handleSamples(
                    samples,
                    sampleRate: sampleRate,
                    level: level,
                    speaker: .me,
                    captureGeneration: generation
                )
            }
        }
        captureTimeline.anchorEpoch(
            for: .me,
            generation: generation,
            minimumStartSeconds: currentTimelineOffsetSeconds()
        )
    }

    private func beginCaptureEpoch(for speaker: MeetingSpeaker) -> UInt64 {
        captureTimeline.beginEpoch(for: speaker)
    }

    private func logSampleExtractionFailureIfNeeded(
        isInterleaved: Bool,
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        commonFormatRawValue: Int,
        speaker: MeetingSpeaker
    ) {
        guard !loggedSampleExtractionFailureSpeakers.contains(speaker) else { return }
        loggedSampleExtractionFailureSpeakers.insert(speaker)
        VoxtLog.meetingWarning(
            "Meeting audio sample extraction failed. speaker=\(speaker.rawValue), interleaved=\(isInterleaved), sampleRate=\(Int(sampleRate)), channels=\(channelCount), format=\(commonFormatRawValue)"
        )
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
        await orderedLiveAudioScheduler.flush()
        await audioAnalysisScheduler.flush()

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
        Task {
            await audioAnalysisScheduler.cancel()
            await orderedLiveAudioScheduler.cancel()
        }
    }

    private func flushPendingTranslations() async {
        await realtimeTranslationScheduler.flush()
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

        let operation = realtimeTranslationHandler(segment.text, targetLanguage)
        let submission = realtimeTranslationScheduler.submit(
            segmentID: segment.id,
            sourceText: segment.text,
            targetLanguage: targetLanguage,
            operation: operation
        ) { [weak self] result in
            guard let self else { return }
            guard let current = self.overlayState.segments.first(where: { $0.id == segment.id }),
                  current.text.trimmingCharacters(in: .whitespacesAndNewlines) ==
                    segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                self.queueOutstandingRealtimeTranslationsIfNeeded()
                return
            }
            switch result {
            case .success(let translatedText):
                let trimmed = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                self.updateSegment(segment.id) { current in
                    current.updatingTranslation(
                        translatedText: trimmed.isEmpty ? nil : trimmed,
                        isTranslationPending: false
                    )
                }
            case .failure(let error):
                VoxtLog.meetingWarning("Meeting realtime translation failed: \(error)")
                self.updateSegment(segment.id) { current in
                    current.updatingTranslation(
                        translatedText: current.translatedText,
                        isTranslationPending: false
                    )
                }
            }
            self.queueOutstandingRealtimeTranslationsIfNeeded()
        }

        if submission == .overloaded, !hasLoggedTranslationOverload {
            hasLoggedTranslationOverload = true
            VoxtLog.meetingWarning(
                "Meeting realtime translation reached its 9-segment safety bound; pending finalized segments will be retried as capacity becomes available."
            )
        }
    }

    private func cancelTranslationTask(for segmentID: UUID) {
        realtimeTranslationScheduler.cancel(segmentID: segmentID)
    }

    private func cancelTranslationTasks() {
        realtimeTranslationScheduler.cancelAll()
        hasLoggedTranslationOverload = false
    }

    private func queueOutstandingRealtimeTranslationsIfNeeded() {
        guard overlayState.realtimeTranslateEnabled else { return }
        for segment in overlayState.segments where
            segment.speaker == .them &&
            segment.isTranslationPending &&
            (segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        {
            queueRealtimeTranslation(for: segment)
        }
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

    private func applyTranscriptEvent(
        _ event: MeetingTranscriptEvent,
        sessionToken: UUID? = nil
    ) {
        switch event {
        case .failed(let speaker, let message):
            VoxtLog.meetingError("Meeting live transcription failed. speaker=\(speaker.rawValue), detail=\(message)")
            clearLiveSession(for: speaker, matching: sessionToken)
            return
        case .finished(let speaker):
            clearLiveSession(for: speaker, matching: sessionToken)
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

    private func clearLiveSession(for speaker: MeetingSpeaker, matching sessionToken: UUID?) {
        guard let sessionToken else {
            liveSessions[speaker] = nil
            liveSessionTokens[speaker] = nil
            localLivePendingAudio[speaker] = nil
            return
        }
        guard liveSessionTokens[speaker] == sessionToken else { return }
        liveSessions[speaker] = nil
        liveSessionTokens[speaker] = nil
        localLivePendingAudio[speaker] = nil
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

        let optimizedSegments: [MeetingTranscriptSegment]
        do {
            optimizedSegments = try await MeetingFinalTranscriptionPass.transcribe(
                descriptors: finalTranscriptionDescriptors,
                loadAsset: { descriptor in
                    await self.audioArchive.loadAsset(descriptor)
                },
                transcriber: transcriber
            )
        } catch {
            VoxtLog.meetingWarning(
                "Meeting final transcript optimization failed; falling back to realtime transcript. error=\(error.localizedDescription)"
            )
            return MeetingTranscriptPostProcessor.process(fallbackSegments)
        }
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

    private func finalSpeechEvidence(
        descriptors: [MeetingAudioAssetDescriptor],
        captureMode: MeetingCaptureMode,
        policy: MLXVADPolicy,
        shouldValidate: Bool
    ) async -> MeetingFinalSpeechEvidence? {
        guard shouldValidate, !descriptors.isEmpty else { return nil }
        guard policy.usesExternalFinalSpeechValidation else {
            VoxtLog.meeting(
                "Meeting final external VAD skipped because the model owns speech validation. policy=\(String(describing: policy))",
                verbose: true
            )
            return nil
        }
        guard !serverVADActive else {
            VoxtLog.meeting("Meeting final external VAD skipped because server VAD is active.", verbose: true)
            return nil
        }

        var evidence = MeetingFinalSpeechEvidence()
        var evaluatedAssetCount = 0
        for descriptor in descriptors {
            let speaker = descriptor.source.defaultSpeaker
            guard captureMode.includes(speaker: speaker) else { continue }
            guard let asset = await audioArchive.loadVoiceActivityAsset(descriptor) else {
                VoxtLog.meetingWarning(
                    "Meeting final VAD asset unavailable; transcript coverage remains unvalidated. source=\(descriptor.source.rawValue), start=\(String(format: "%.2f", descriptor.sessionStartOffset))"
                )
                continue
            }
            guard let speechRanges = await offlineVoiceActivityDetector.speechRanges(
                samples: asset.samples,
                sampleRate: asset.sampleRate,
                fallbackThreshold: Self.speechThreshold(for: speaker)
            ) else {
                continue
            }
            evidence.record(
                source: asset.source,
                assetStartSeconds: asset.sessionStartOffset,
                assetDurationSeconds: asset.durationSeconds,
                speechRanges: speechRanges
            )
            evaluatedAssetCount += 1
        }
        guard evaluatedAssetCount > 0 else { return nil }
        return evidence
    }

    private func resolvedTranscriptionEngine() -> TranscriptionEngine {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.transcriptionEngine) ?? ""
        return TranscriptionEngine.resolved(rawValue: raw)
    }

    private func resolvedEngineContext() -> MeetingASREngineContext {
        let transcriptionEngine = resolvedTranscriptionEngine()
        let remoteSelection = resolvedRemoteASRSelection()

        let automaticContext = MeetingASRSupport.resolveContext(
            transcriptionEngine: transcriptionEngine,
            mlxModelState: mlxModelManager.state,
            mlxCurrentModelRepo: mlxModelManager.currentModelRepo,
            mlxIsCurrentModelLoaded: mlxModelManager.isCurrentModelLoaded,
            mlxDisplayTitle: mlxModelManager.displayTitle(for:),
            sherpaModelID: sherpaOnnxModelManager.selectedModelID,
            sherpaDisplayTitle: sherpaOnnxModelManager.displayTitle(for:),
            remoteProvider: remoteSelection.provider,
            remoteConfiguration: remoteSelection.configuration
        )
        let chunkingMode = MeetingChunkingMode.stored()
        return automaticContext.resolvingChunkingMode(chunkingMode)
    }

    private func makeTranscriber(for context: MeetingASREngineContext) async throws -> any MeetingSegmentTranscribing {
        liveSessionFactory = nil
        switch context.engine {
        case .mlxAudio:
            mlxModelManager.beginActiveUse()
            activeLocalEngine = .mlxAudio
            if case .liveLocal = context.resolvedMode {
                liveSessionFactory = MeetingMLXNativeLiveSessionFactory(modelManager: mlxModelManager)
            }
            return MeetingMLXSegmentTranscriber(modelManager: mlxModelManager)
        case .remote:
            if context.resolvedMode.usesLiveSessions {
                let remoteSelection = resolvedRemoteASRSelection()
                let hintTarget = ASRHintTarget.from(
                    engine: .remote,
                    remoteProvider: remoteSelection.provider
                )
                let hintSettings = ASRHintSettingsStore.resolvedSettings(
                    for: hintTarget,
                    rawValue: UserDefaults.standard.string(forKey: AppPreferenceKey.asrHintSettings)
                )
                liveSessionFactory = MeetingRemoteLiveSessionFactory(
                    provider: remoteSelection.provider,
                    configuration: remoteSelection.configuration,
                    hintPayload: resolvedMeetingHintPayload(target: hintTarget, settings: hintSettings)
                )
            }
            return MeetingRemoteASRSegmentTranscriber()
        case .sherpaOnnx:
            if let modelID = context.sherpaModelID {
                sherpaOnnxModelManager.updateModel(id: modelID)
            }
            activeLocalEngine = .sherpaOnnx
            return MeetingSherpaOnnxSegmentTranscriber(modelManager: sherpaOnnxModelManager)
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
        liveSessionTokens.removeAll()
        localLiveVoiceActivityGates.removeAll(keepingCapacity: false)
        localLivePendingAudio.removeAll(keepingCapacity: false)

        if context.resolvedMode.usesLocalVoiceActivityGate {
            liveAudioPrebuffers = Self.makeLiveAudioPrebuffers(
                maxDuration: Self.localLivePrebufferSeconds
            )
            return
        }

        liveAudioPrebuffers = Self.makeLiveAudioPrebuffers(
            maxDuration: Self.remoteLivePrebufferSeconds
        )
        let timelineOffsetSeconds = currentTimelineOffsetSeconds()

        for speaker in activeCaptureSpeakers {
            let session = try liveSessionFactory.makeSession(for: speaker, timelineOffsetSeconds: timelineOffsetSeconds)
            let sessionToken = UUID()
            liveSessions[speaker] = session
            liveSessionTokens[speaker] = sessionToken
            try await session.start(timelineOffsetSeconds: timelineOffsetSeconds) { [weak self] event in
                self?.applyTranscriptEvent(event, sessionToken: sessionToken)
            }
        }
    }

    private func finishLiveSessionsIfNeeded() async {
        let sessions = liveSessions
        liveSessions.removeAll()
        liveSessionTokens.removeAll()
        for (speaker, session) in sessions {
            await flushLocalLivePendingAudio(
                for: speaker,
                to: session,
                replacingWithSilence: true
            )
            await session.finish()
        }
        localLivePendingAudio.removeAll(keepingCapacity: false)
    }

    private func finishLiveSession(for speaker: MeetingSpeaker) async {
        guard let session = liveSessions.removeValue(forKey: speaker) else { return }
        let sessionToken = liveSessionTokens[speaker]
        await flushLocalLivePendingAudio(
            for: speaker,
            to: session,
            replacingWithSilence: true
        )
        await session.finish()
        if liveSessionTokens[speaker] == sessionToken {
            liveSessionTokens[speaker] = nil
        }
    }

    private func cancelLiveSessionsIfNeeded() async {
        let sessions = liveSessions.values
        liveSessions.removeAll()
        liveSessionTokens.removeAll()
        localLivePendingAudio.removeAll(keepingCapacity: false)
        for session in sessions {
            await session.cancel()
        }
    }

    private func releaseActiveLocalEngine() {
        guard let activeLocalEngine else { return }
        switch activeLocalEngine {
        case .mlxAudio:
            mlxModelManager.endActiveUse()
        case .dictation, .sherpaOnnx, .remote:
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

    private func resolvedMeetingHintPayload(
        target: ASRHintTarget,
        settings: ASRHintSettings
    ) -> ResolvedASRHintPayload {
        let storedCodes = UserDefaults.standard.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        let userLanguageCodes = UserMainLanguageOption.storedSelection(from: storedCodes)
        return ASRHintResolver.resolve(
            target: target,
            settings: settings,
            userLanguageCodes: userLanguageCodes
        )
    }

    private func resolvedRemoteASRSelection() -> (provider: RemoteASRProvider, configuration: RemoteProviderConfiguration) {
        let provider = RemoteASRProvider(
            rawValue: UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? ""
        ) ?? .openAIWhisper
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        let stored = RemoteModelConfigurationStore.loadConfiguration(
            providerID: provider.rawValue,
            from: raw
        ).map { [provider.rawValue: $0] } ?? [:]
        let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: provider,
            stored: stored
        )
        return (provider, configuration)
    }

    private nonisolated static func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        AudioLevelMeter.monoSamples(from: buffer)
    }

    private var usesLiveSessionPath: Bool {
        activeEngineContext?.resolvedMode.usesLiveSessions == true || liveSessionFactory != nil
    }

    private var serverVADActive: Bool {
        guard let resolvedMode = activeEngineContext?.resolvedMode else { return false }
        if case .liveRemote = resolvedMode {
            return true
        }
        return false
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

    private func ensureLiveSession(
        for speaker: MeetingSpeaker,
        timelineEndSeconds: TimeInterval? = nil
    ) async -> (any MeetingLiveTranscribingSession)? {
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

        let sessionToken = UUID()
        do {
            let prebufferFrames = liveAudioPrebuffers[speaker]?.snapshot() ?? []
            let prebufferDuration = prebufferFrames.reduce(0) { $0 + $1.duration }
            let timelineOffsetSeconds = max(
                (timelineEndSeconds ?? currentTimelineOffsetSeconds()) - prebufferDuration,
                0
            )
            let session = try liveSessionFactory.makeSession(for: speaker, timelineOffsetSeconds: timelineOffsetSeconds)
            liveSessions[speaker] = session
            liveSessionTokens[speaker] = sessionToken
            try await session.start(timelineOffsetSeconds: timelineOffsetSeconds) { [weak self] event in
                self?.applyTranscriptEvent(event, sessionToken: sessionToken)
            }
            await flushLivePrebuffer(prebufferFrames, to: session)
            liveAudioPrebuffers[speaker]?.removeAll()
            return session
        } catch {
            clearLiveSession(for: speaker, matching: sessionToken)
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

    private func flushLocalLivePendingAudio(
        for speaker: MeetingSpeaker,
        to session: any MeetingLiveTranscribingSession,
        replacingWithSilence: Bool
    ) async {
        guard var pendingAudio = localLivePendingAudio.removeValue(forKey: speaker) else { return }
        let frames = pendingAudio.drain(replacingWithSilence: replacingWithSilence)
        await flushLivePrebuffer(frames, to: session)
    }

    private func currentTimelineOffsetSeconds() -> TimeInterval {
        let activeSlice = recordingStartedAt.map { max(Date().timeIntervalSince($0), 0) } ?? 0
        return accumulatedRecordingDuration + activeSlice
    }

    private static func makeLiveAudioPrebuffers(
        maxDuration: TimeInterval
    ) -> [MeetingSpeaker: MeetingLiveAudioPrebuffer] {
        [
            .me: MeetingLiveAudioPrebuffer(maxDuration: maxDuration),
            .them: MeetingLiveAudioPrebuffer(maxDuration: maxDuration)
        ]
    }

}

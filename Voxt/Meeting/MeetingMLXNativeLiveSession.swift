// MeetingMLXNativeLiveSession.swift
// Reuses visible MLX models' native streaming state for local meeting transcription.

import Foundation
import MLXAudioSTT

@MainActor
struct MeetingMLXNativeLiveSessionFactory: MeetingLiveSessionFactory {
    let modelManager: MLXModelManager

    func makeSession(
        for speaker: MeetingSpeaker,
        timelineOffsetSeconds: TimeInterval
    ) throws -> any MeetingLiveTranscribingSession {
        MeetingMLXNativeLiveSession(
            speaker: speaker,
            timelineOffsetSeconds: timelineOffsetSeconds,
            modelManager: modelManager
        )
    }
}

private actor MeetingMLXNativeFeedScheduler {
    private static let sampleRate = 16_000.0
    private static let maximumPendingSamples = Int(sampleRate * 10)

    private let session: any MLXNativeStreamingSession
    private var pendingSamples: [Float] = []
    private var pendingOffset = 0
    private var drainTask: Task<Void, Never>?
    private var isStopping = false

    init(session: any MLXNativeStreamingSession) {
        self.session = session
    }

    func submit(samples: [Float], sampleRate: Double) -> Bool {
        guard !samples.isEmpty, !isStopping else { return true }
        let prepared = ASRVoiceActivitySampleRateConverter.resample(
            samples: samples,
            from: sampleRate,
            to: Self.sampleRate
        )
        guard !prepared.isEmpty else { return true }
        let pendingCount = pendingSamples.count - pendingOffset
        guard pendingCount + prepared.count <= Self.maximumPendingSamples else {
            return false
        }
        pendingSamples.append(contentsOf: prepared)
        startDrainIfNeeded()
        return true
    }

    func finish() async {
        isStopping = true
        while let drainTask {
            await drainTask.value
        }
        await feedRemainingSamples()
        session.stop()
    }

    func cancel() {
        isStopping = true
        pendingSamples.removeAll(keepingCapacity: false)
        pendingOffset = 0
        drainTask?.cancel()
        session.cancel()
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        defer {
            drainTask = nil
            compact(force: true)
            if pendingOffset < pendingSamples.count, !isStopping {
                startDrainIfNeeded()
            }
        }
        while !Task.isCancelled, pendingOffset < pendingSamples.count {
            let end = min(pendingOffset + Int(Self.sampleRate / 5), pendingSamples.count)
            let chunk = Array(pendingSamples[pendingOffset..<end])
            try? await MeetingLocalInferenceCoordinator.shared.withPermit(.liveASRFeed) { [session] in
                session.feedAudio(samples: chunk)
            }
            pendingOffset = end
            compact(force: false)
        }
    }

    private func feedRemainingSamples() async {
        guard pendingOffset < pendingSamples.count else { return }
        let remaining = Array(pendingSamples[pendingOffset...])
        try? await MeetingLocalInferenceCoordinator.shared.withPermit(.liveASRFeed) { [session] in
            session.feedAudio(samples: remaining)
        }
        pendingSamples.removeAll(keepingCapacity: false)
        pendingOffset = 0
    }

    private func compact(force: Bool) {
        guard pendingOffset > 0,
              force || (pendingOffset >= 16_000 && pendingOffset * 2 >= pendingSamples.count)
        else {
            return
        }
        pendingSamples.removeFirst(pendingOffset)
        pendingOffset = 0
    }
}

@MainActor
private final class MeetingMLXNativeLiveSession: MeetingLiveTranscribingSession {
    private static let silenceFinalizeSeconds: TimeInterval = 0.75
    private static let maximumLiveSegmentSeconds: TimeInterval = 8

    let speaker: MeetingSpeaker
    private let modelManager: MLXModelManager
    private let streamingTranscriber: MLXTranscriber

    private(set) var state: MeetingLiveSessionState = .connecting
    private var eventHandler: (@MainActor (MeetingTranscriptEvent) -> Void)?
    private var configuration: MLXMeetingNativeStreamingConfiguration?
    private var feedScheduler: MeetingMLXNativeFeedScheduler?
    private var eventTask: Task<Void, Never>?
    private var timelineOffsetSeconds: TimeInterval
    private var totalAudioSeconds: TimeInterval = 0
    private var currentSegmentID = UUID()
    private var currentSegmentStartSeconds: TimeInterval
    private var committedCumulativeText = ""
    private var latestCumulativeText = ""
    private var latestVisibleSegmentText = ""
    private var silenceDurationSeconds: TimeInterval = 0
    private var hasLoggedFeedOverload = false
    private var isCancelled = false
    private var defersSilenceFinalization = false
    private var didEmitStructuredEndedSegments = false

    init(
        speaker: MeetingSpeaker,
        timelineOffsetSeconds: TimeInterval,
        modelManager: MLXModelManager
    ) {
        self.speaker = speaker
        self.timelineOffsetSeconds = timelineOffsetSeconds
        self.currentSegmentStartSeconds = timelineOffsetSeconds
        self.modelManager = modelManager
        self.streamingTranscriber = MLXTranscriber(
            modelManager: modelManager,
            transcriptionPurpose: .meeting
        )
    }

    func start(
        timelineOffsetSeconds: TimeInterval,
        eventHandler: @escaping @MainActor (MeetingTranscriptEvent) -> Void
    ) async throws {
        self.timelineOffsetSeconds = timelineOffsetSeconds
        self.currentSegmentStartSeconds = timelineOffsetSeconds
        self.eventHandler = eventHandler
        state = .connecting

        let configuration = try await streamingTranscriber.makeMeetingNativeStreamingConfiguration()
        guard configuration.liveMode != .nativeVoxtralLive else {
            throw NSError(
                domain: "Voxt.Meeting.NativeMLX",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Hidden support models are excluded from meeting optimization."]
            )
        }
        self.configuration = configuration
        defersSilenceFinalization = MeetingNativeLiveSegmentationPolicy.shouldDeferSilenceFinalization(
            timingGranularity: MLXModelCatalog.capability(for: modelManager.currentModelRepo).timingGranularity
        )
        didEmitStructuredEndedSegments = false
        let feedScheduler = MeetingMLXNativeFeedScheduler(session: configuration.session)
        self.feedScheduler = feedScheduler
        state = .active

        eventTask = Task { @MainActor [weak self, session = configuration.session] in
            for await event in session.events {
                guard !Task.isCancelled, let self else { return }
                self.handle(event)
            }
        }
        VoxtLog.meeting(
            "Meeting native MLX streaming session started. repo=\(modelManager.currentModelRepo), speaker=\(speaker.rawValue), offset=\(String(format: "%.2f", timelineOffsetSeconds))",
            verbose: true
        )
    }

    func append(samples: [Float], sampleRate: Double) async {
        guard state == .active, !isCancelled, !samples.isEmpty else { return }
        let duration = Double(samples.count) / max(sampleRate, 1)
        totalAudioSeconds += duration

        let level = AudioLevelMeter.normalizedLevel(fromSamples: samples)
        let threshold: Float = speaker == .me ? 0.012 : 0.025
        if level >= threshold {
            silenceDurationSeconds = 0
        } else {
            silenceDurationSeconds += duration
        }

        if let feedScheduler {
            let accepted = await feedScheduler.submit(samples: samples, sampleRate: sampleRate)
            if !accepted, !hasLoggedFeedOverload {
                hasLoggedFeedOverload = true
                VoxtLog.meetingWarning(
                    "Meeting native MLX feed reached its 10-second safety bound. speaker=\(speaker.rawValue), repo=\(modelManager.currentModelRepo)"
                )
            }
        }

        let currentEnd = timelineOffsetSeconds + totalAudioSeconds
        // Keep one partial when the model can emit reliable timestamps on `.ended`
        // (for example Nemotron sentence segments). Silence-splitting would otherwise
        // publish text-only finals that duplicate or fight those timestamps.
        if !defersSilenceFinalization,
           MeetingNativeLiveSegmentationPolicy.shouldFinalizeBeforeStreamEnd(
            // MOSS provisional windows can rewrite already visible words when the
            // final window gains more context. Keep one partial segment until ended.
            streamCanReviseEarlierText: configuration?.mossVisibleOutputMode != nil,
            silenceDuration: silenceDurationSeconds,
            segmentDuration: currentEnd - currentSegmentStartSeconds,
            silenceThreshold: Self.silenceFinalizeSeconds,
            maximumSegmentDuration: Self.maximumLiveSegmentSeconds
           )
        {
            finalizeVisibleSegment(at: currentEnd)
        }
    }

    func finish() async {
        guard state != .stopping else { return }
        state = .stopping
        await feedScheduler?.finish()
        if let eventTask {
            await eventTask.value
        }
        if !didEmitStructuredEndedSegments {
            finalizeVisibleSegment(at: timelineOffsetSeconds + totalAudioSeconds)
        }
        eventHandler?(.finished(speaker: speaker))
        release()
    }

    func cancel() async {
        guard !isCancelled else { return }
        isCancelled = true
        state = .stopping
        await feedScheduler?.cancel()
        eventTask?.cancel()
        eventHandler?(.finished(speaker: speaker))
        release()
    }

    private func handle(_ event: TranscriptionEvent) {
        switch event {
        case .displayUpdate(let confirmedText, let provisionalText):
            let cumulative = visibleCumulativeText(
                confirmedText: confirmedText,
                provisionalText: provisionalText
            )
            publishPartial(cumulative: cumulative)
        case .confirmed, .provisional:
            // displayUpdate carries the coherent cumulative confirmed + provisional view.
            break
        case .ended(let output):
            let cumulative = visibleFinalText(output.text)
            if finalizeWithEndedOutputIfPossible(output, cumulativeText: cumulative) {
                return
            }
            publishPartial(cumulative: cumulative)
            finalizeVisibleSegment(at: timelineOffsetSeconds + totalAudioSeconds)
        case .failed(let failure):
            state = .failed
            eventHandler?(.failed(speaker: speaker, message: failure.localizedDescription))
        case .stats:
            break
        }
    }

    private func visibleCumulativeText(confirmedText: String, provisionalText: String) -> String {
        guard let configuration else { return (confirmedText + provisionalText).trimmingCharacters(in: .whitespacesAndNewlines) }
        if configuration.qwenUsesAutomaticLanguageProtocol {
            let parts = MLXTranscriptionPlanning.qwenStreamingVisibleTextParts(
                confirmedText: confirmedText,
                provisionalText: provisionalText
            )
            return (parts.confirmedText + parts.provisionalText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let combined = confirmedText + provisionalText
        if let outputMode = configuration.mossVisibleOutputMode {
            return MossASRTranscriptRendering.renderedText(combined, outputMode: outputMode)
        }
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleFinalText(_ text: String) -> String {
        guard let configuration else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if configuration.qwenUsesAutomaticLanguageProtocol {
            return MLXTranscriptionPlanning.qwenStreamingVisibleText(
                text,
                suppressIncompleteWindowHeader: false
            )
        }
        if let outputMode = configuration.mossVisibleOutputMode {
            return MossASRTranscriptRendering.renderedText(text, outputMode: outputMode)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func publishPartial(cumulative: String) {
        let normalized = cumulative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        latestCumulativeText = normalized
        let visible = Self.uncommittedSuffix(
            cumulative: normalized,
            committed: committedCumulativeText
        )
        guard !visible.isEmpty, visible != latestVisibleSegmentText else { return }
        latestVisibleSegmentText = visible
        eventHandler?(
            .partial(
                segment(text: visible, endSeconds: timelineOffsetSeconds + totalAudioSeconds)
            )
        )
    }

    private func finalizeVisibleSegment(at endSeconds: TimeInterval) {
        let text = latestVisibleSegmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            currentSegmentStartSeconds = endSeconds
            return
        }
        eventHandler?(.final(segment(text: text, endSeconds: endSeconds)))
        committedCumulativeText = latestCumulativeText
        latestVisibleSegmentText = ""
        currentSegmentID = UUID()
        currentSegmentStartSeconds = endSeconds
        silenceDurationSeconds = 0
    }

    @discardableResult
    private func finalizeWithEndedOutputIfPossible(_ output: STTOutput, cumulativeText: String) -> Bool {
        guard defersSilenceFinalization,
              let segments = output.segments,
              !segments.isEmpty
        else {
            return false
        }

        let capability = MLXModelCatalog.capability(for: modelManager.currentModelRepo)
        let structured = MeetingNativeLiveStructuredFinalization.meetingSegments(
            from: segments,
            timingGranularity: capability.timingGranularity,
            modelFamily: capability.family,
            timelineOffsetSeconds: timelineOffsetSeconds,
            speaker: speaker,
            audioSource: speaker == .me ? .microphone : .systemAudio
        )
        guard !structured.isEmpty else { return false }

        // Drop the in-flight text-only partial; model timestamps replace it.
        latestVisibleSegmentText = ""
        for item in structured {
            eventHandler?(.final(item))
        }
        latestCumulativeText = cumulativeText
        committedCumulativeText = cumulativeText
        currentSegmentID = UUID()
        currentSegmentStartSeconds = timelineOffsetSeconds + totalAudioSeconds
        silenceDurationSeconds = 0
        didEmitStructuredEndedSegments = true
        VoxtLog.meeting(
            "Meeting native MLX ended with structured segments. speaker=\(speaker.rawValue), segmentCount=\(structured.count), timing=\(String(describing: capability.timingGranularity)), language=\(output.language ?? "nil")",
            verbose: true
        )
        return true
    }

    private func segment(text: String, endSeconds: TimeInterval) -> MeetingTranscriptSegment {
        MeetingTranscriptSegment(
            id: currentSegmentID,
            speaker: speaker,
            audioSource: speaker == .me ? .microphone : .systemAudio,
            startSeconds: currentSegmentStartSeconds,
            endSeconds: max(endSeconds, currentSegmentStartSeconds),
            text: text,
            preventsAdjacentMerge: true
        )
    }

    private func release() {
        eventTask?.cancel()
        eventTask = nil
        feedScheduler = nil
        configuration = nil
        eventHandler = nil
    }

    private nonisolated static func uncommittedSuffix(cumulative: String, committed: String) -> String {
        guard !committed.isEmpty else { return cumulative }
        if cumulative.hasPrefix(committed) {
            return String(cumulative.dropFirst(committed.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let committedCharacters = Array(committed)
        let cumulativeCharacters = Array(cumulative)
        let maximumOverlap = min(committedCharacters.count, cumulativeCharacters.count)
        for overlap in stride(from: maximumOverlap, through: 1, by: -1) {
            if committedCharacters.suffix(overlap).elementsEqual(cumulativeCharacters.prefix(overlap)) {
                return String(cumulativeCharacters.dropFirst(overlap))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return cumulative
    }
}

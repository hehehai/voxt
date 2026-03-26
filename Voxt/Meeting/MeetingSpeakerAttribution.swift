import Foundation
import FluidAudio

enum MeetingDiarizationVariant: String, CaseIterable, Identifiable, Sendable {
    case ami
    case callhome
    case dihard3

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .ami:
            return "AMI (In-person, 4 speakers)"
        case .callhome:
            return "CALLHOME (Phone, 7 speakers)"
        case .dihard3:
            return "DIHARD III (General, 10 speakers)"
        }
    }

    var lsEENDVariant: LSEENDVariant {
        switch self {
        case .ami:
            return .ami
        case .callhome:
            return .callhome
        case .dihard3:
            return .dihard3
        }
    }
}

protocol MeetingSpeakerAttributing: Sendable {
    func feedSystemAudio(samples: [Float], sampleRate: Double) async
    func attributedSpeaker(
        for originalSpeaker: MeetingSpeaker,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval?
    ) async -> MeetingSpeaker
    func finalizeSession() async
    func resetSession() async
}

struct MeetingDiarizationSegment: Sendable {
    let startTime: Float
    let endTime: Float
}

struct MeetingDiarizationSpeakerTimeline: Sendable {
    let index: Int
    let isActive: Bool
    let segments: [MeetingDiarizationSegment]
}

actor MeetingDiarizationManager: MeetingSpeakerAttributing {
    private nonisolated(unsafe) let diarizer = LSEENDDiarizer()
    private let minimumProcessingBatchSeconds: TimeInterval = 0.45
    private let maximumProcessingBatchSeconds: TimeInterval = 1.25
    private let attributionPaddingSeconds: TimeInterval = 0.3
    private let minimumAttributionWindowSeconds: TimeInterval = 0.6
    private let nearestSpeakerFallbackGapSeconds: TimeInterval = 0.75
    private var isInitialized = false
    private var processingBatchSeconds: TimeInterval = 0.5
    private var pendingProcessingDurationSeconds: TimeInterval = 0

    func load(variant: MeetingDiarizationVariant) async throws {
        try await diarizer.initialize(variant: variant.lsEENDVariant)
        isInitialized = true
        processingBatchSeconds = Self.processingBatchSeconds(
            streamingLatencySeconds: diarizer.streamingLatencySeconds,
            minimumBatchSeconds: minimumProcessingBatchSeconds,
            maximumBatchSeconds: maximumProcessingBatchSeconds
        )
        let variantRawValue = variant.rawValue
        let targetSampleRate = diarizer.targetSampleRate ?? 0
        let streamingLatency = diarizer.streamingLatencySeconds ?? 0
        let processBatch = processingBatchSeconds
        await MainActor.run {
            VoxtLog.info(
                "Meeting diarization initialized. variant=\(variantRawValue), targetSampleRate=\(targetSampleRate), streamingLatency=\(String(format: "%.2f", streamingLatency)), processBatch=\(String(format: "%.2f", processBatch))",
                verbose: true
            )
        }
    }

    func feedSystemAudio(samples: [Float], sampleRate: Double) async {
        guard isInitialized, !samples.isEmpty, sampleRate > 0 else { return }
        do {
            try diarizer.addAudio(samples, sourceSampleRate: sampleRate)
            pendingProcessingDurationSeconds += Double(samples.count) / sampleRate
            try processBufferedAudioIfNeeded(force: false)
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                VoxtLog.warning("Meeting diarization audio feed failed: \(message)")
            }
        }
    }

    func attributedSpeaker(
        for originalSpeaker: MeetingSpeaker,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval?
    ) async -> MeetingSpeaker {
        guard isInitialized, originalSpeaker.isRemote else { return originalSpeaker }

        let timeline = diarizer.timeline
        let speakers = timeline.speakers
        guard !speakers.isEmpty else { return originalSpeaker }

        let speakerTimelines = speakers.map { index, speaker in
            MeetingDiarizationSpeakerTimeline(
                index: index,
                isActive: speaker.hasSegments,
                segments: (speaker.finalizedSegments + speaker.tentativeSegments).map {
                    MeetingDiarizationSegment(startTime: $0.startTime, endTime: $0.endTime)
                }
            )
        }

        return Self.attributedSpeaker(
            for: originalSpeaker,
            speakerTimelines: speakerTimelines,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            attributionPaddingSeconds: attributionPaddingSeconds,
            minimumAttributionWindowSeconds: minimumAttributionWindowSeconds,
            nearestSpeakerFallbackGapSeconds: nearestSpeakerFallbackGapSeconds
        )
    }

    func finalizeSession() async {
        guard isInitialized else { return }
        try? processBufferedAudioIfNeeded(force: true)
        _ = try? diarizer.finalizeSession()
        pendingProcessingDurationSeconds = 0
    }

    func resetSession() async {
        guard isInitialized else { return }
        diarizer.reset()
        pendingProcessingDurationSeconds = 0
    }

    nonisolated static func attributedSpeaker(
        for originalSpeaker: MeetingSpeaker,
        speakerTimelines: [MeetingDiarizationSpeakerTimeline],
        startSeconds: TimeInterval,
        endSeconds: TimeInterval?,
        attributionPaddingSeconds: TimeInterval = 0.3,
        minimumAttributionWindowSeconds: TimeInterval = 0.6,
        nearestSpeakerFallbackGapSeconds: TimeInterval = 0.75
    ) -> MeetingSpeaker {
        guard originalSpeaker.isRemote, !speakerTimelines.isEmpty else { return originalSpeaker }

        let baseStart = max(startSeconds, 0)
        let baseEnd = max(endSeconds ?? (baseStart + minimumAttributionWindowSeconds), baseStart + minimumAttributionWindowSeconds)
        let queryStart = Float(max(baseStart - attributionPaddingSeconds, 0))
        let queryEnd = Float(max(baseEnd + attributionPaddingSeconds, baseStart + minimumAttributionWindowSeconds))
        guard queryEnd > queryStart else { return originalSpeaker }

        var bestSpeakerIndex: Int?
        var bestOverlap: Float = 0
        var nearestSpeakerIndex: Int?
        var nearestDistance: Float = .greatestFiniteMagnitude

        for speakerTimeline in speakerTimelines {
            var overlap: Float = 0
            for segment in speakerTimeline.segments {
                let overlapStart = max(segment.startTime, queryStart)
                let overlapEnd = min(segment.endTime, queryEnd)
                if overlapEnd > overlapStart {
                    overlap += overlapEnd - overlapStart
                } else {
                    let distance = temporalDistance(from: segment, toWindowStart: queryStart, windowEnd: queryEnd)
                    if distance < nearestDistance {
                        nearestDistance = distance
                        nearestSpeakerIndex = speakerTimeline.index
                    }
                }
            }

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeakerIndex = speakerTimeline.index
            }
        }

        let resolvedSpeakerIndex: Int
        if let bestSpeakerIndex, bestOverlap > 0 {
            resolvedSpeakerIndex = bestSpeakerIndex
        } else if let nearestSpeakerIndex, nearestDistance <= Float(nearestSpeakerFallbackGapSeconds) {
            resolvedSpeakerIndex = nearestSpeakerIndex
        } else {
            return originalSpeaker
        }

        let activeSpeakerCount = speakerTimelines.filter(\.isActive).count
        guard activeSpeakerCount > 1 else {
            return .them
        }

        return .remote(resolvedSpeakerIndex + 1)
    }

    private func processBufferedAudioIfNeeded(force: Bool) throws {
        guard isInitialized else { return }
        guard force || pendingProcessingDurationSeconds >= processingBatchSeconds else { return }
        _ = try diarizer.process()
        pendingProcessingDurationSeconds = 0
    }

    private nonisolated static func processingBatchSeconds(
        streamingLatencySeconds: TimeInterval?,
        minimumBatchSeconds: TimeInterval,
        maximumBatchSeconds: TimeInterval
    ) -> TimeInterval {
        let latencyDrivenBatch = (streamingLatencySeconds ?? minimumBatchSeconds) * 0.5
        return min(max(latencyDrivenBatch, minimumBatchSeconds), maximumBatchSeconds)
    }

    private nonisolated static func temporalDistance(
        from segment: MeetingDiarizationSegment,
        toWindowStart windowStart: Float,
        windowEnd: Float
    ) -> Float {
        if segment.endTime < windowStart {
            return windowStart - segment.endTime
        }
        if segment.startTime > windowEnd {
            return segment.startTime - windowEnd
        }
        return 0
    }
}

import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

struct MeetingAudioAsset: Sendable {
    let source: TranscriptAudioSource
    let samples: [Float]
    let sampleRate: Double
    let sessionStartOffset: TimeInterval

    var durationSeconds: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(samples.count) / sampleRate
    }
}

struct MeetingSpeakerTurn: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let source: TranscriptAudioSource
    let speakerID: String
    let displayName: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let confidence: Double?

    init(
        id: UUID = UUID(),
        source: TranscriptAudioSource,
        speakerID: String,
        displayName: String,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        confidence: Double? = nil
    ) {
        self.id = id
        self.source = source
        self.speakerID = speakerID
        self.displayName = displayName
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.confidence = confidence
    }
}

enum MeetingSpeakerDiarizationSensitivity: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case stable
    case balanced
    case sensitive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return AppLocalization.localizedString("Stable")
        case .balanced:
            return AppLocalization.localizedString("Balanced")
        case .sensitive:
            return AppLocalization.localizedString("Sensitive")
        }
    }

    var detail: String {
        switch self {
        case .stable:
            return AppLocalization.localizedString("Prefer fewer false speaker switches.")
        case .balanced:
            return AppLocalization.localizedString("Balance speaker recall and label stability.")
        case .sensitive:
            return AppLocalization.localizedString("Detect shorter speaker turns with a higher risk of extra speaker labels.")
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> MeetingSpeakerDiarizationSensitivity {
        let rawValue = defaults.string(forKey: AppPreferenceKey.meetingSpeakerDiarizationSensitivity) ?? ""
        return MeetingSpeakerDiarizationSensitivity(rawValue: rawValue) ?? .balanced
    }

    var minimumSpeakerConfidence: Double {
        switch self {
        case .stable:
            return 0.42
        case .balanced:
            return 0.28
        case .sensitive:
            return 0.18
        }
    }

    var smootherOptions: MeetingSpeakerTurnSmoother.Options {
        switch self {
        case .stable:
            return .init(minimumTurnDurationSeconds: 1.0, sameSpeakerMergeGapSeconds: 1.4)
        case .balanced:
            return .init(minimumTurnDurationSeconds: 0.75, sameSpeakerMergeGapSeconds: 1.0)
        case .sensitive:
            return .init(minimumTurnDurationSeconds: 0.35, sameSpeakerMergeGapSeconds: 0.5)
        }
    }

    var transcriptAssemblyOptions: MeetingSpeakerTranscriptAssembler.Options {
        switch self {
        case .stable:
            return .init(
                dominantSpeakerOverlapRatio: 0.94,
                minimumTurnOverlapSeconds: 0.22,
                minimumSecondarySpeakerOverlapSeconds: 1.0,
                minimumSecondarySpeakerOverlapRatio: 0.12,
                splitsSegmentsOnSpeakerBoundaries: true
            )
        case .balanced:
            return .init(
                dominantSpeakerOverlapRatio: 0.88,
                minimumTurnOverlapSeconds: 0.12,
                minimumSecondarySpeakerOverlapSeconds: 0.6,
                minimumSecondarySpeakerOverlapRatio: 0.08,
                splitsSegmentsOnSpeakerBoundaries: true
            )
        case .sensitive:
            return .init(
                dominantSpeakerOverlapRatio: 0.72,
                minimumTurnOverlapSeconds: 0.08,
                minimumSecondarySpeakerOverlapSeconds: 0.35,
                minimumSecondarySpeakerOverlapRatio: 0.04,
                splitsSegmentsOnSpeakerBoundaries: true
            )
        }
    }

    var fluidAudioClusteringThreshold: Float {
        switch self {
        case .stable:
            return 0.70
        case .balanced:
            return 0.58
        case .sensitive:
            return 0.48
        }
    }

    var fluidAudioMinimumSpeechDuration: Float {
        switch self {
        case .stable:
            return 1.0
        case .balanced:
            return 0.65
        case .sensitive:
            return 0.35
        }
    }

    var fluidAudioMinimumEmbeddingUpdateDuration: Float {
        switch self {
        case .stable:
            return 2.0
        case .balanced:
            return 1.4
        case .sensitive:
            return 0.9
        }
    }

    var fluidAudioMinimumActiveFramesCount: Float {
        switch self {
        case .stable:
            return 10.0
        case .balanced:
            return 7.0
        case .sensitive:
            return 4.0
        }
    }

    var fluidAudioMinimumSilenceGap: Float {
        switch self {
        case .stable:
            return 1.0
        case .balanced:
            return 0.8
        case .sensitive:
            return 0.5
        }
    }
}

struct MeetingSpeakerDiarizationOptions: Equatable, Sendable {
    var minimumAudioDurationSeconds: TimeInterval
    var minimumSpeakerConfidence: Double
    var smoothing: MeetingSpeakerTurnSmoother.Options
    var transcriptAssembly: MeetingSpeakerTranscriptAssembler.Options
    var sensitivity: MeetingSpeakerDiarizationSensitivity
    var debugLoggingEnabled: Bool

    nonisolated init(
        minimumAudioDurationSeconds: TimeInterval = 2.0,
        sensitivity: MeetingSpeakerDiarizationSensitivity = .balanced,
        minimumSpeakerConfidence: Double? = nil,
        smoothing: MeetingSpeakerTurnSmoother.Options? = nil,
        transcriptAssembly: MeetingSpeakerTranscriptAssembler.Options? = nil,
        debugLoggingEnabled: Bool = false
    ) {
        self.minimumAudioDurationSeconds = minimumAudioDurationSeconds
        self.sensitivity = sensitivity
        self.minimumSpeakerConfidence = minimumSpeakerConfidence ?? sensitivity.minimumSpeakerConfidence
        self.smoothing = smoothing ?? sensitivity.smootherOptions
        self.transcriptAssembly = transcriptAssembly ?? sensitivity.transcriptAssemblyOptions
        self.debugLoggingEnabled = debugLoggingEnabled
    }

    static func fromPreferences(defaults: UserDefaults = .standard) -> MeetingSpeakerDiarizationOptions {
        MeetingSpeakerDiarizationOptions(
            sensitivity: MeetingSpeakerDiarizationSensitivity.stored(in: defaults),
            debugLoggingEnabled: defaults.bool(forKey: AppPreferenceKey.meetingSpeakerDiarizationDebugEnabled)
        )
    }
}

protocol MeetingSpeakerDiarizationEngine: Sendable {
    func diarize(
        asset: MeetingAudioAsset,
        options: MeetingSpeakerDiarizationOptions
    ) async throws -> [MeetingSpeakerTurn]
}

enum MeetingSpeakerAnalysisPipeline {
    static func analyzedSegments(
        from segments: [MeetingTranscriptSegment],
        assets: [MeetingAudioAsset],
        options: MeetingSpeakerDiarizationOptions = MeetingSpeakerDiarizationOptions(),
        engine: (any MeetingSpeakerDiarizationEngine)? = MeetingSpeakerDiarizationEngineFactory.makeDefault()
    ) async -> [MeetingTranscriptSegment] {
        guard !segments.isEmpty, !assets.isEmpty, let engine else {
            return segments
        }

        do {
            var turns: [MeetingSpeakerTurn] = []
            logDebug(
                "Meeting speaker analysis started. segments=\(segments.count), assets=\(assets.count), sensitivity=\(options.sensitivity.rawValue)",
                options: options
            )
            for asset in assets where asset.durationSeconds >= options.minimumAudioDurationSeconds {
                let assetTurns = try await engine.diarize(asset: asset, options: options)
                logDebug(
                    "Meeting speaker analysis asset raw turns. source=\(asset.source.rawValue), duration=\(String(format: "%.2f", asset.durationSeconds)), rawTurns=\(assetTurns.count), rawSpeakers=\(speakerCount(assetTurns))",
                    options: options
                )
                turns.append(contentsOf: assetTurns)
            }
            let rawTurns = turns
            turns = confidenceFilteredTurns(from: turns, options: options)
            let confidenceFilteredTurns = turns
            turns = MeetingSpeakerTurnSmoother.smooth(turns, options: options.smoothing)
            let smoothedTurns = turns
            turns = MeetingSpeakerTurnLabeler.label(turns)
            logDebug(
                "Meeting speaker analysis pipeline summary. rawTurns=\(rawTurns.count), rawSpeakers=\(speakerCount(rawTurns)), confidenceFilteredTurns=\(confidenceFilteredTurns.count), confidenceFilteredSpeakers=\(speakerCount(confidenceFilteredTurns)), smoothedTurns=\(smoothedTurns.count), smoothedSpeakers=\(speakerCount(smoothedTurns)), confidenceThreshold=\(String(format: "%.2f", options.minimumSpeakerConfidence))",
                options: options
            )
            guard !turns.isEmpty else { return segments }
            let assembled = MeetingSpeakerTranscriptAssembler.assemble(
                segments: segments,
                speakerTurns: turns,
                options: options.transcriptAssembly
            )
            let readableSegments = MeetingTranscriptPostProcessor.process(assembled)
            logDebug(
                "Meeting speaker analysis assembly summary. inputSegments=\(segments.count), assembledSegments=\(assembled.count), readableSegments=\(readableSegments.count), outputSpeakers=\(segmentSpeakerCount(readableSegments))",
                options: options
            )
            return readableSegments
        } catch {
            VoxtLog.warning("Meeting speaker analysis failed: \(error.localizedDescription)")
            return segments
        }
    }

    private static func logDebug(_ message: @autoclosure () -> String, options: MeetingSpeakerDiarizationOptions) {
        guard options.debugLoggingEnabled else { return }
        VoxtLog.info(message())
    }

    private static func confidenceFilteredTurns(
        from turns: [MeetingSpeakerTurn],
        options: MeetingSpeakerDiarizationOptions
    ) -> [MeetingSpeakerTurn] {
        guard options.minimumSpeakerConfidence > 0 else { return turns }

        let filteredTurns = turns.filter { turn in
            guard let confidence = turn.confidence else { return true }
            return confidence >= options.minimumSpeakerConfidence
        }

        guard !filteredTurns.isEmpty else { return turns }

        let rawSpeakerCount = speakerCount(turns)
        guard rawSpeakerCount > 1 else { return filteredTurns }

        let filteredSpeakerCount = speakerCount(filteredTurns)
        guard filteredSpeakerCount < min(rawSpeakerCount, 2) else { return filteredTurns }

        logDebug(
            "Meeting speaker confidence filter would collapse speakers; preserving raw turns. rawSpeakers=\(rawSpeakerCount), filteredSpeakers=\(filteredSpeakerCount), threshold=\(String(format: "%.2f", options.minimumSpeakerConfidence))",
            options: options
        )
        return turns
    }

    private static func speakerCount(_ turns: [MeetingSpeakerTurn]) -> Int {
        Set(turns.map { "\($0.source.rawValue):\($0.speakerID)" }).count
    }

    private static func segmentSpeakerCount(_ segments: [MeetingTranscriptSegment]) -> Int {
        Set(segments.compactMap { segment in
            let trimmedID = segment.speakerID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmedID.isEmpty ? nil : trimmedID
        }).count
    }
}

enum MeetingSpeakerDiarizationEngineFactory {
    #if canImport(FluidAudio)
    private static let sharedFluidAudioEngine = FluidAudioMeetingSpeakerDiarizationEngine()
    #endif

    nonisolated static func makeDefault() -> (any MeetingSpeakerDiarizationEngine)? {
        #if canImport(FluidAudio)
        return sharedFluidAudioEngine
        #else
        return nil
        #endif
    }
}

#if canImport(FluidAudio)
actor FluidAudioMeetingSpeakerDiarizationEngine: MeetingSpeakerDiarizationEngine {
    private var diarizer: DiarizerManager?
    private var preparedConfiguration: FluidAudioDiarizerRuntimeConfiguration?

    func diarize(
        asset: MeetingAudioAsset,
        options: MeetingSpeakerDiarizationOptions
    ) async throws -> [MeetingSpeakerTurn] {
        let manager = try await preparedDiarizer(options: options)
        let result = try manager.performCompleteDiarization(
            asset.samples,
            sampleRate: Int(asset.sampleRate.rounded()),
            atTime: asset.sessionStartOffset
        )
        return result.segments.map { segment in
                MeetingSpeakerTurn(
                    source: asset.source,
                    speakerID: segment.speakerId,
                    displayName: segment.speakerId,
                    startSeconds: TimeInterval(segment.startTimeSeconds),
                    endSeconds: TimeInterval(segment.endTimeSeconds),
                    confidence: Double(segment.qualityScore)
                )
            }
    }

    private func preparedDiarizer(options: MeetingSpeakerDiarizationOptions) async throws -> DiarizerManager {
        let configuration = FluidAudioDiarizerRuntimeConfiguration(options: options)
        if let diarizer, preparedConfiguration == configuration {
            return diarizer
        }

        let models = try await DiarizerModels.downloadIfNeeded()
        let manager = DiarizerManager(config: configuration.diarizerConfig)
        manager.initialize(models: models)

        if let existing = diarizer, preparedConfiguration == configuration {
            return existing
        }
        diarizer = manager
        preparedConfiguration = configuration
        return manager
    }

    private struct FluidAudioDiarizerRuntimeConfiguration: Equatable {
        let clusteringThreshold: Float
        let minSpeechDuration: Float
        let minEmbeddingUpdateDuration: Float
        let minSilenceGap: Float
        let minActiveFramesCount: Float

        init(options: MeetingSpeakerDiarizationOptions) {
            clusteringThreshold = options.sensitivity.fluidAudioClusteringThreshold
            minSpeechDuration = options.sensitivity.fluidAudioMinimumSpeechDuration
            minEmbeddingUpdateDuration = options.sensitivity.fluidAudioMinimumEmbeddingUpdateDuration
            minSilenceGap = options.sensitivity.fluidAudioMinimumSilenceGap
            minActiveFramesCount = options.sensitivity.fluidAudioMinimumActiveFramesCount
        }

        var diarizerConfig: DiarizerConfig {
            DiarizerConfig(
                clusteringThreshold: clusteringThreshold,
                minSpeechDuration: minSpeechDuration,
                minEmbeddingUpdateDuration: minEmbeddingUpdateDuration,
                minSilenceGap: minSilenceGap,
                numClusters: -1,
                minActiveFramesCount: minActiveFramesCount,
                debugMode: false,
                chunkDuration: 10.0,
                chunkOverlap: 0.0
            )
        }
    }
}
#endif

enum MeetingSpeakerTurnLabeler {
    static func label(
        _ turns: [MeetingSpeakerTurn]
    ) -> [MeetingSpeakerTurn] {
        var orderedKeys: [String] = []
        var seen = Set<String>()
        for turn in turns.sorted(by: speakerSort) {
            let key = speakerIdentityKey(for: turn)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            orderedKeys.append(key)
        }

        let nameByKey = Dictionary(uniqueKeysWithValues: orderedKeys.enumerated().map { index, key in
            (key, AppLocalization.format("Speaker %d", index + 1))
        })

        return turns.map { turn in
            let key = speakerIdentityKey(for: turn)
            return MeetingSpeakerTurn(
                id: turn.id,
                source: turn.source,
                speakerID: turn.speakerID,
                displayName: nameByKey[key] ?? turn.displayName,
                startSeconds: turn.startSeconds,
                endSeconds: turn.endSeconds,
                confidence: turn.confidence
            )
        }
    }

    private static func speakerIdentityKey(for turn: MeetingSpeakerTurn) -> String {
        switch turn.source {
        case .mixed:
            return turn.speakerID
        case .microphone, .systemAudio:
            return "\(turn.source.rawValue):\(turn.speakerID)"
        }
    }

    private static func speakerSort(_ lhs: MeetingSpeakerTurn, _ rhs: MeetingSpeakerTurn) -> Bool {
        if lhs.startSeconds == rhs.startSeconds {
            if lhs.source == rhs.source {
                return lhs.speakerID < rhs.speakerID
            }
            return lhs.source.rawValue < rhs.source.rawValue
        }
        return lhs.startSeconds < rhs.startSeconds
    }
}

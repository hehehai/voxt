// MeetingSpeakerDiarizationEngines.swift
// Provides Meeting Speaker Diarization Engines for meeting speaker analysis.

import Foundation
import MLX
import MLXAudioVAD

#if canImport(FluidAudio)
import FluidAudio
#endif

protocol MeetingSpeakerDiarizationEngine: Sendable {
    func diarize(
        asset: MeetingAudioAsset,
        options: MeetingSpeakerDiarizationOptions
    ) async throws -> [MeetingSpeakerTurn]
}

enum MeetingSpeakerDiarizationEngineFactory {
    #if canImport(FluidAudio)
    nonisolated private static let sharedFluidAudioEngine = FluidAudioMeetingSpeakerDiarizationEngine()
    #endif
    nonisolated private static let sharedSortformerEngine = SortformerMeetingSpeakerDiarizationEngine()

    nonisolated static func makeDefault(defaults: UserDefaults = .standard) -> (any MeetingSpeakerDiarizationEngine)? {
        switch MeetingDiarizationMode.stored(in: defaults) {
        case .offlineVBx:
            #if canImport(FluidAudio)
            return sharedFluidAudioEngine
            #else
            return sharedSortformerEngine
            #endif
        case .sortformerV2:
            return sharedSortformerEngine
        }
    }
}

actor SortformerMeetingSpeakerDiarizationEngine: MeetingSpeakerDiarizationEngine {
    private var model: SortformerModel?

    func diarize(
        asset: MeetingAudioAsset,
        options _: MeetingSpeakerDiarizationOptions
    ) async throws -> [MeetingSpeakerTurn] {
        let model = try await loadModelIfAvailable()
        let prepared = MeetingAudioSampleRateConverter.resample(
            samples: asset.samples,
            from: asset.sampleRate,
            to: 16_000
        )
        guard !prepared.isEmpty else { return [] }

        let state = model.initStreamingState()
        let (output, _) = try await model.feed(
            chunk: MLXArray(prepared),
            state: state,
            sampleRate: 16_000,
            threshold: 0.5,
            minDuration: 0.25,
            mergeGap: 0.18
        )

        return output.segments.map { item in
            MeetingSpeakerTurn(
                source: asset.source,
                speakerID: "sortformer-\(item.speaker)",
                displayName: MeetingSpeakerDisplayNameFormatter.displayName(ordinal: item.speaker + 1),
                startSeconds: asset.sessionStartOffset + TimeInterval(item.start),
                endSeconds: asset.sessionStartOffset + TimeInterval(item.end),
                confidence: nil
            )
        }
        .filter { $0.endSeconds > $0.startSeconds }
    }

    private func loadModelIfAvailable() async throws -> SortformerModel {
        if let model {
            return model
        }
        let directory = await MainActor.run {
            MeetingSortformerModelStorage.modelDirectory(requireValid: true)
        }
        guard let directory else {
            throw MeetingVADModelError.modelNotDownloaded
        }
        let loaded = try SortformerModel.fromModelDirectory(directory)
        model = loaded
        return loaded
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
        if #available(macOS 14.0, *) {
            do {
                return try await diarizeOffline(asset: asset, options: options)
            } catch {
                VoxtLog.warning("Meeting offline speaker analysis failed; falling back to streaming diarizer: \(error.localizedDescription)")
            }
        }
        return try await diarizeStreaming(asset: asset, options: options)
    }

    private func diarizeStreaming(
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

    @available(macOS 14.0, *)
    private func diarizeOffline(
        asset: MeetingAudioAsset,
        options: MeetingSpeakerDiarizationOptions
    ) async throws -> [MeetingSpeakerTurn] {
        let configuration = FluidAudioOfflineDiarizerRuntimeConfiguration(options: options)
        let manager = OfflineDiarizerManager(config: configuration.diarizerConfig)
        try await manager.prepareModels(directory: MeetingOfflineVBxModelStorage.writeRootDirectory())
        let result = try await manager.process(audio: asset.samples)
        return result.segments.map { segment in
            MeetingSpeakerTurn(
                source: asset.source,
                speakerID: segment.speakerId,
                displayName: segment.speakerId,
                startSeconds: asset.sessionStartOffset + TimeInterval(segment.startTimeSeconds),
                endSeconds: asset.sessionStartOffset + TimeInterval(segment.endTimeSeconds),
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

    @available(macOS 14.0, *)
    private struct FluidAudioOfflineDiarizerRuntimeConfiguration: Equatable {
        let clusteringThreshold: Double
        let minSegmentDuration: Double
        let speakerCountHint: MeetingSpeakerCountHint

        init(options: MeetingSpeakerDiarizationOptions) {
            clusteringThreshold = options.sensitivity.fluidAudioOfflineClusteringThreshold
            minSegmentDuration = options.sensitivity.fluidAudioOfflineMinimumSegmentDuration
            speakerCountHint = options.speakerCountHint
        }

        var diarizerConfig: OfflineDiarizerConfig {
            var config = OfflineDiarizerConfig.default
            config.clusteringThreshold = clusteringThreshold
            config.minSegmentDuration = minSegmentDuration
            let bounds = speakerCountHint.offlineSpeakerBounds
            if bounds.min != nil || bounds.max != nil {
                config = config.withSpeakers(min: bounds.min, max: bounds.max)
            }
            return config
        }
    }
}
#endif

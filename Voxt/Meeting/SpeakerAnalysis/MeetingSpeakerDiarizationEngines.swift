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

    func diarizeSession(
        descriptors: [MeetingAudioAssetDescriptor],
        loadAsset: @escaping @Sendable (MeetingAudioAssetDescriptor) async -> MeetingAudioAsset?,
        continuousAudioURL: URL?,
        options: MeetingSpeakerDiarizationOptions,
        progress: (@Sendable (Double) async -> Void)?
    ) async throws -> [MeetingSpeakerTurn]
}

extension MeetingSpeakerDiarizationEngine {
    func diarizeSession(
        descriptors: [MeetingAudioAssetDescriptor],
        loadAsset: @escaping @Sendable (MeetingAudioAssetDescriptor) async -> MeetingAudioAsset?,
        continuousAudioURL _: URL?,
        options: MeetingSpeakerDiarizationOptions,
        progress: (@Sendable (Double) async -> Void)?
    ) async throws -> [MeetingSpeakerTurn] {
        var turns: [MeetingSpeakerTurn] = []
        let descriptorCount = max(descriptors.count, 1)
        await progress?(0)
        for (index, descriptor) in descriptors.enumerated() {
            try Task.checkCancellation()
            if let asset = await loadAsset(descriptor) {
                turns.append(contentsOf: try await diarize(asset: asset, options: options))
            }
            await progress?(Double(index + 1) / Double(descriptorCount))
        }
        return turns
    }
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
        let prepared = ASRVoiceActivitySampleRateConverter.resample(
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

    func diarizeSession(
        descriptors: [MeetingAudioAssetDescriptor],
        loadAsset: @escaping @Sendable (MeetingAudioAssetDescriptor) async -> MeetingAudioAsset?,
        continuousAudioURL _: URL?,
        options _: MeetingSpeakerDiarizationOptions,
        progress: (@Sendable (Double) async -> Void)?
    ) async throws -> [MeetingSpeakerTurn] {
        let model = try await loadModelIfAvailable()
        var state = model.initStreamingState()
        var streamBaseOffset = descriptors.first?.sessionStartOffset ?? 0
        var previousDescriptor: MeetingAudioAssetDescriptor?
        var turns: [MeetingSpeakerTurn] = []
        let descriptorCount = max(descriptors.count, 1)
        await progress?(0)

        for (index, descriptor) in descriptors.enumerated() {
            try Task.checkCancellation()
            if let previousDescriptor {
                let expectedStart = previousDescriptor.sessionStartOffset + previousDescriptor.durationSeconds
                let isContinuous = descriptor.source == previousDescriptor.source
                    && abs(descriptor.sessionStartOffset - expectedStart) < 0.05
                if !isContinuous {
                    state = model.initStreamingState()
                    streamBaseOffset = descriptor.sessionStartOffset
                }
            }
            previousDescriptor = descriptor

            guard let asset = await loadAsset(descriptor) else {
                await progress?(Double(index + 1) / Double(descriptorCount))
                continue
            }
            let prepared = ASRVoiceActivitySampleRateConverter.resample(
                samples: asset.samples,
                from: asset.sampleRate,
                to: 16_000
            )
            guard !prepared.isEmpty else {
                await progress?(Double(index + 1) / Double(descriptorCount))
                continue
            }

            let (output, newState) = try await model.feed(
                chunk: MLXArray(prepared),
                state: state,
                sampleRate: 16_000,
                threshold: 0.5,
                minDuration: 0.25,
                mergeGap: 0.18
            )
            state = newState
            turns.append(contentsOf: output.segments.compactMap { item in
                let turn = MeetingSpeakerTurn(
                    source: asset.source,
                    speakerID: "sortformer-\(item.speaker)",
                    displayName: MeetingSpeakerDisplayNameFormatter.displayName(ordinal: item.speaker + 1),
                    startSeconds: streamBaseOffset + TimeInterval(item.start),
                    endSeconds: streamBaseOffset + TimeInterval(item.end),
                    confidence: nil
                )
                return turn.endSeconds > turn.startSeconds ? turn : nil
            })
            await progress?(Double(index + 1) / Double(descriptorCount))
        }
        return turns
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
                VoxtLog.meetingWarning("Meeting offline speaker analysis failed; falling back to streaming diarizer: \(error.localizedDescription)")
            }
        }
        return try await diarizeStreaming(asset: asset, options: options)
    }

    func diarizeSession(
        descriptors: [MeetingAudioAssetDescriptor],
        loadAsset: @escaping @Sendable (MeetingAudioAssetDescriptor) async -> MeetingAudioAsset?,
        continuousAudioURL: URL?,
        options: MeetingSpeakerDiarizationOptions,
        progress: (@Sendable (Double) async -> Void)?
    ) async throws -> [MeetingSpeakerTurn] {
        guard #available(macOS 14.0, *),
              let continuousAudioURL,
              let firstDescriptor = descriptors.first
        else {
            var turns: [MeetingSpeakerTurn] = []
            let descriptorCount = max(descriptors.count, 1)
            await progress?(0)
            for (index, descriptor) in descriptors.enumerated() {
                try Task.checkCancellation()
                if let asset = await loadAsset(descriptor) {
                    turns.append(contentsOf: try await diarize(asset: asset, options: options))
                }
                await progress?(Double(index + 1) / Double(descriptorCount))
            }
            return turns
        }

        let configuration = FluidAudioOfflineDiarizerRuntimeConfiguration(options: options)
        let manager = OfflineDiarizerManager(config: configuration.diarizerConfig)
        try await manager.prepareModels(directory: MeetingOfflineVBxModelStorage.writeRootDirectory())
        await progress?(0)
        let progressStream = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let progressTask = Task {
            for await fraction in progressStream.stream {
                await progress?(fraction)
            }
        }
        let result: DiarizationResult
        do {
            result = try await manager.process(continuousAudioURL) { completed, total in
                guard total > 0 else { return }
                progressStream.continuation.yield(Double(completed) / Double(total))
            }
            progressStream.continuation.yield(1)
            progressStream.continuation.finish()
            await progressTask.value
        } catch {
            progressStream.continuation.finish()
            progressTask.cancel()
            throw error
        }
        let sessionStartOffset = firstDescriptor.sessionStartOffset
        return result.segments.map { segment in
            MeetingSpeakerTurn(
                source: firstDescriptor.source,
                speakerID: segment.speakerId,
                displayName: segment.speakerId,
                startSeconds: sessionStartOffset + TimeInterval(segment.startTimeSeconds),
                endSeconds: sessionStartOffset + TimeInterval(segment.endTimeSeconds),
                confidence: Double(segment.qualityScore)
            )
        }
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

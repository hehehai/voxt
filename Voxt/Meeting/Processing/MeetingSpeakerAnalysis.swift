// MeetingSpeakerAnalysis.swift
// Provides Meeting Speaker Analysis for meeting transcript processing.

import Foundation

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
                "Meeting speaker analysis started. segments=\(segments.count), assets=\(assets.count), sensitivity=\(options.sensitivity.rawValue), speakerCountHint=\(options.speakerCountHint.rawValue)",
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
            return assembledSegments(from: segments, turns: turns, options: options)
        } catch {
            VoxtLog.warning("Meeting speaker analysis failed: \(error.localizedDescription)")
            return segments
        }
    }

    static func analyzedSegments(
        from segments: [MeetingTranscriptSegment],
        descriptors: [MeetingAudioAssetDescriptor],
        loadAsset: @escaping @Sendable (MeetingAudioAssetDescriptor) async -> MeetingAudioAsset?,
        options: MeetingSpeakerDiarizationOptions = MeetingSpeakerDiarizationOptions(),
        engine: (any MeetingSpeakerDiarizationEngine)? = MeetingSpeakerDiarizationEngineFactory.makeDefault()
    ) async -> [MeetingTranscriptSegment] {
        guard !segments.isEmpty, !descriptors.isEmpty, let engine else {
            return segments
        }

        do {
            var turns: [MeetingSpeakerTurn] = []
            logDebug(
                "Meeting speaker analysis started. segments=\(segments.count), assets=\(descriptors.count), sensitivity=\(options.sensitivity.rawValue), speakerCountHint=\(options.speakerCountHint.rawValue)",
                options: options
            )
            for descriptor in descriptors where descriptor.durationSeconds >= options.minimumAudioDurationSeconds {
                guard let asset = await loadAsset(descriptor) else { continue }
                let assetTurns = try await engine.diarize(asset: asset, options: options)
                logDebug(
                    "Meeting speaker analysis asset raw turns. source=\(asset.source.rawValue), duration=\(String(format: "%.2f", asset.durationSeconds)), rawTurns=\(assetTurns.count), rawSpeakers=\(speakerCount(assetTurns))",
                    options: options
                )
                turns.append(contentsOf: assetTurns)
            }
            return assembledSegments(from: segments, turns: turns, options: options)
        } catch {
            VoxtLog.warning("Meeting speaker analysis failed: \(error.localizedDescription)")
            return segments
        }
    }

    private static func assembledSegments(
        from segments: [MeetingTranscriptSegment],
        turns: [MeetingSpeakerTurn],
        options: MeetingSpeakerDiarizationOptions
    ) -> [MeetingTranscriptSegment] {
        let rawTurns = turns
        var turns = confidenceFilteredTurns(from: turns, options: options)
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

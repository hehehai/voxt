import Foundation

enum MeetingSpeakerTranscriptAssembler {
    struct Options: Equatable, Sendable {
        var dominantSpeakerOverlapRatio: Double = 0.6
        var minimumTurnOverlapSeconds: TimeInterval = 0.08
        var minimumSecondarySpeakerOverlapSeconds: TimeInterval = 0.45
        var minimumSecondarySpeakerOverlapRatio: Double = 0.04
        var maximumNearestSpeakerTurnGapSeconds: TimeInterval = 1.25
        var sameSpeakerSplitMergeGapSeconds: TimeInterval = 1.0
        var splitsSegmentsOnSpeakerBoundaries = false

        nonisolated init(
            dominantSpeakerOverlapRatio: Double = 0.6,
            minimumTurnOverlapSeconds: TimeInterval = 0.08,
            minimumSecondarySpeakerOverlapSeconds: TimeInterval = 0.45,
            minimumSecondarySpeakerOverlapRatio: Double = 0.04,
            maximumNearestSpeakerTurnGapSeconds: TimeInterval = 1.25,
            sameSpeakerSplitMergeGapSeconds: TimeInterval = 1.0,
            splitsSegmentsOnSpeakerBoundaries: Bool = false
        ) {
            self.dominantSpeakerOverlapRatio = dominantSpeakerOverlapRatio
            self.minimumTurnOverlapSeconds = minimumTurnOverlapSeconds
            self.minimumSecondarySpeakerOverlapSeconds = minimumSecondarySpeakerOverlapSeconds
            self.minimumSecondarySpeakerOverlapRatio = minimumSecondarySpeakerOverlapRatio
            self.maximumNearestSpeakerTurnGapSeconds = maximumNearestSpeakerTurnGapSeconds
            self.sameSpeakerSplitMergeGapSeconds = sameSpeakerSplitMergeGapSeconds
            self.splitsSegmentsOnSpeakerBoundaries = splitsSegmentsOnSpeakerBoundaries
        }
    }

    static func assemble(
        segments: [MeetingTranscriptSegment],
        speakerTurns: [MeetingSpeakerTurn],
        options: Options = Options()
    ) -> [MeetingTranscriptSegment] {
        guard !segments.isEmpty, !speakerTurns.isEmpty else { return segments }
        let sortedTurns = speakerTurns
            .filter { $0.endSeconds > $0.startSeconds }
            .sorted { lhs, rhs in
                if lhs.startSeconds == rhs.startSeconds {
                    return lhs.speakerID < rhs.speakerID
                }
                return lhs.startSeconds < rhs.startSeconds
            }
        guard !sortedTurns.isEmpty else { return segments }

        return segments.flatMap { segment in
            assembledSegments(for: segment, speakerTurns: sortedTurns, options: options)
        }
        .sorted { lhs, rhs in
            if lhs.startSeconds == rhs.startSeconds {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startSeconds < rhs.startSeconds
        }
    }

    private static func assembledSegments(
        for segment: MeetingTranscriptSegment,
        speakerTurns: [MeetingSpeakerTurn],
        options: Options
    ) -> [MeetingTranscriptSegment] {
        guard let segmentEnd = segment.endSeconds,
              segmentEnd > segment.startSeconds
        else {
            return [segment]
        }

        let source = segment.audioSource ?? inferredAudioSource(for: segment.speaker)
        let segmentDuration = max(segmentEnd - segment.startSeconds, 0.001)
        let overlappingTurns = speakerTurns.compactMap { turn -> (turn: MeetingSpeakerTurn, overlap: TimeInterval)? in
            guard turn.source == .mixed || turn.source == source else { return nil }
            let overlap = overlapDuration(
                startA: segment.startSeconds,
                endA: segmentEnd,
                startB: turn.startSeconds,
                endB: turn.endSeconds
            )
            guard overlap >= options.minimumTurnOverlapSeconds else { return nil }
            return (turn, overlap)
        }

        guard !overlappingTurns.isEmpty else {
            if let nearestTurn = nearestCompatibleTurn(
                to: segment,
                segmentEnd: segmentEnd,
                source: source,
                speakerTurns: speakerTurns,
                maximumGap: options.maximumNearestSpeakerTurnGapSeconds
            ) {
                return [segment.applyingSpeakerTurn(nearestTurn)]
            }
            return [
                segment.updatingSpeakerAnalysis(
                    speakerID: segment.speakerID,
                    speakerDisplayName: segment.speakerDisplayName,
                    audioSource: source,
                    speakerConfidence: segment.speakerConfidence
                )
            ]
        }

        if let dominant = overlappingTurns.max(by: { $0.overlap < $1.overlap }) {
            let hasMeaningfulSecondarySpeaker = hasMeaningfulSecondarySpeaker(
                in: overlappingTurns,
                dominantSpeakerID: dominant.turn.speakerID,
                segmentDuration: segmentDuration,
                options: options
            )
            if !options.splitsSegmentsOnSpeakerBoundaries
                || (dominant.overlap / segmentDuration >= options.dominantSpeakerOverlapRatio
                    && !hasMeaningfulSecondarySpeaker) {
                return [segment.applyingSpeakerTurn(dominant.turn)]
            }
        }

        let boundedTurns = coalescedBoundedTurns(
            overlappingTurns
                .map { item in
                    BoundedSpeakerTurn(
                        turn: item.turn,
                        startSeconds: max(segment.startSeconds, item.turn.startSeconds),
                        endSeconds: min(segmentEnd, item.turn.endSeconds)
                    )
                }
                .filter { $0.endSeconds - $0.startSeconds >= options.minimumTurnOverlapSeconds }
                .sorted { $0.startSeconds < $1.startSeconds },
            options: options
        )

        guard boundedTurns.count > 1 else {
            return [segment.applyingSpeakerTurn(overlappingTurns[0].turn)]
        }

        let splitTexts = splitText(
            segment.text,
            proportionalDurations: boundedTurns.map { $0.endSeconds - $0.startSeconds }
        )
        guard splitTexts.count == boundedTurns.count else {
            return [segment.applyingSpeakerTurn(overlappingTurns[0].turn)]
        }

        return zip(boundedTurns, splitTexts).compactMap { boundedTurn, text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let resolvedSpeaker = resolvedSpeaker(
                for: boundedTurn.turn,
                fallbackSpeaker: segment.speaker
            )
            let resolvedAudioSource = resolvedAudioSource(
                for: boundedTurn.turn,
                fallbackAudioSource: source
            )
            return TranscriptSegment(
                id: UUID(),
                speaker: resolvedSpeaker,
                speakerID: boundedTurn.turn.speakerID,
                speakerDisplayName: boundedTurn.turn.displayName,
                audioSource: resolvedAudioSource,
                speakerConfidence: boundedTurn.turn.confidence,
                startSeconds: boundedTurn.startSeconds,
                endSeconds: boundedTurn.endSeconds,
                text: trimmed,
                translatedText: nil,
                isTranslationPending: false,
                preventsAdjacentMerge: false
            )
        }
    }

    private struct BoundedSpeakerTurn {
        let turn: MeetingSpeakerTurn
        let startSeconds: TimeInterval
        let endSeconds: TimeInterval
    }

    private static func coalescedBoundedTurns(
        _ turns: [BoundedSpeakerTurn],
        options: Options
    ) -> [BoundedSpeakerTurn] {
        guard !turns.isEmpty else { return [] }

        var output: [BoundedSpeakerTurn] = []
        for turn in turns {
            guard let previous = output.last else {
                output.append(turn)
                continue
            }

            let gap = turn.startSeconds - previous.endSeconds
            if isSameSpeaker(previous.turn, turn.turn),
               gap <= options.sameSpeakerSplitMergeGapSeconds {
                output[output.count - 1] = mergedBoundedTurn(previous, turn)
            } else {
                output.append(turn)
            }
        }
        return output
    }

    private static func isSameSpeaker(_ lhs: MeetingSpeakerTurn, _ rhs: MeetingSpeakerTurn) -> Bool {
        lhs.source == rhs.source && lhs.speakerID == rhs.speakerID
    }

    private static func mergedBoundedTurn(
        _ lhs: BoundedSpeakerTurn,
        _ rhs: BoundedSpeakerTurn
    ) -> BoundedSpeakerTurn {
        let mergedTurn = MeetingSpeakerTurn(
            id: lhs.turn.id,
            source: lhs.turn.source,
            speakerID: lhs.turn.speakerID,
            displayName: lhs.turn.displayName,
            startSeconds: min(lhs.turn.startSeconds, rhs.turn.startSeconds),
            endSeconds: max(lhs.turn.endSeconds, rhs.turn.endSeconds),
            confidence: [lhs.turn.confidence, rhs.turn.confidence].compactMap { $0 }.max()
        )
        return BoundedSpeakerTurn(
            turn: mergedTurn,
            startSeconds: min(lhs.startSeconds, rhs.startSeconds),
            endSeconds: max(lhs.endSeconds, rhs.endSeconds)
        )
    }

    private static func inferredAudioSource(for speaker: MeetingSpeaker) -> TranscriptAudioSource {
        switch speaker {
        case .me:
            return .microphone
        case .them:
            return .systemAudio
        }
    }

    private static func resolvedSpeaker(
        for turn: MeetingSpeakerTurn,
        fallbackSpeaker: MeetingSpeaker
    ) -> MeetingSpeaker {
        turn.source == .mixed ? fallbackSpeaker : turn.source.defaultSpeaker
    }

    private static func resolvedAudioSource(
        for turn: MeetingSpeakerTurn,
        fallbackAudioSource: TranscriptAudioSource
    ) -> TranscriptAudioSource {
        turn.source == .mixed ? fallbackAudioSource : turn.source
    }

    private static func overlapDuration(
        startA: TimeInterval,
        endA: TimeInterval,
        startB: TimeInterval,
        endB: TimeInterval
    ) -> TimeInterval {
        max(0, min(endA, endB) - max(startA, startB))
    }

    private static func nearestCompatibleTurn(
        to segment: MeetingTranscriptSegment,
        segmentEnd: TimeInterval,
        source: TranscriptAudioSource,
        speakerTurns: [MeetingSpeakerTurn],
        maximumGap: TimeInterval
    ) -> MeetingSpeakerTurn? {
        guard maximumGap > 0 else { return nil }
        return speakerTurns
            .filter { turn in
                guard turn.endSeconds > turn.startSeconds else { return false }
                return turn.source == .mixed || turn.source == source
            }
            .compactMap { turn -> (turn: MeetingSpeakerTurn, gap: TimeInterval)? in
                let gap: TimeInterval
                if turn.endSeconds <= segment.startSeconds {
                    gap = segment.startSeconds - turn.endSeconds
                } else if turn.startSeconds >= segmentEnd {
                    gap = turn.startSeconds - segmentEnd
                } else {
                    gap = 0
                }
                guard gap <= maximumGap else { return nil }
                return (turn, gap)
            }
            .min { lhs, rhs in
                if lhs.gap == rhs.gap {
                    let lhsDistance = abs(lhs.turn.startSeconds - segment.startSeconds)
                    let rhsDistance = abs(rhs.turn.startSeconds - segment.startSeconds)
                    return lhsDistance < rhsDistance
                }
                return lhs.gap < rhs.gap
            }?
            .turn
    }

    private static func hasMeaningfulSecondarySpeaker(
        in overlappingTurns: [(turn: MeetingSpeakerTurn, overlap: TimeInterval)],
        dominantSpeakerID: String,
        segmentDuration: TimeInterval,
        options: Options
    ) -> Bool {
        overlappingTurns.contains { item in
            guard item.turn.speakerID != dominantSpeakerID else { return false }
            return item.overlap >= options.minimumSecondarySpeakerOverlapSeconds
                && item.overlap / max(segmentDuration, 0.001) >= options.minimumSecondarySpeakerOverlapRatio
        }
    }

    private static func splitText(_ text: String, proportionalDurations: [TimeInterval]) -> [String] {
        let count = proportionalDurations.count
        guard count > 1 else { return [text] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(repeating: "", count: count) }

        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count >= count {
            return splitUnits(words, weights: proportionalDurations).map { $0.joined(separator: " ") }
        }

        let characters = trimmed.map(String.init)
        return splitCharacterUnitsAtReadableBoundaries(characters, weights: proportionalDurations)
    }

    private static func splitCharacterUnitsAtReadableBoundaries(
        _ characters: [String],
        weights: [TimeInterval]
    ) -> [String] {
        let count = weights.count
        guard count > 0 else { return [] }
        guard count > 1, !characters.isEmpty else { return [characters.joined()] }

        let normalizedWeights = normalizedSplitWeights(weights)
        let totalCharacterCount = characters.count
        var output: [String] = []
        output.reserveCapacity(count)

        var start = 0
        var cumulativeWeight = 0.0
        for index in 0..<(count - 1) {
            cumulativeWeight += normalizedWeights[index]
            let remainingBuckets = count - index - 1
            let idealBoundary = Int((Double(totalCharacterCount) * cumulativeWeight).rounded())
            let minimumBoundary = start + 1
            let maximumBoundary = max(minimumBoundary, totalCharacterCount - remainingBuckets)
            let window = max(8, totalCharacterCount / max(count * 3, 1))
            let lowerBound = max(minimumBoundary, idealBoundary - window)
            let upperBound = min(maximumBoundary, idealBoundary + window)
            let boundary = readableBoundary(
                in: characters,
                ideal: min(max(idealBoundary, minimumBoundary), maximumBoundary),
                lowerBound: lowerBound,
                upperBound: upperBound
            )
            output.append(characters[start..<boundary].joined())
            start = boundary
        }
        output.append(characters[start..<totalCharacterCount].joined())

        return output.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func readableBoundary(
        in characters: [String],
        ideal: Int,
        lowerBound: Int,
        upperBound: Int
    ) -> Int {
        let hardBreaks = Set("。！？!?；;")
        let softBreaks = Set("，,、 ")
        let candidates = Array(lowerBound...upperBound)
        if let hard = nearestBoundary(in: characters, candidates: candidates, breaks: hardBreaks, ideal: ideal) {
            return hard
        }
        if let soft = nearestBoundary(in: characters, candidates: candidates, breaks: softBreaks, ideal: ideal) {
            return soft
        }
        return ideal
    }

    private static func nearestBoundary(
        in characters: [String],
        candidates: [Int],
        breaks: Set<Character>,
        ideal: Int
    ) -> Int? {
        candidates
            .filter { boundary in
                guard boundary > 0, boundary <= characters.count else { return false }
                guard let previous = characters[boundary - 1].first else { return false }
                return breaks.contains(previous)
            }
            .min { lhs, rhs in
                abs(lhs - ideal) < abs(rhs - ideal)
            }
    }

    private static func splitUnits(_ units: [String], weights: [TimeInterval]) -> [[String]] {
        let count = weights.count
        guard count > 0 else { return [] }
        guard !units.isEmpty else { return Array(repeating: [], count: count) }

        let normalizedWeights = normalizedSplitWeights(weights)
        var output: [[String]] = []
        output.reserveCapacity(count)
        var cursor = 0
        for index in 0..<count {
            let remainingUnits = units.count - cursor
            let remainingBuckets = count - index
            let remainingWeight = normalizedWeights[index...].reduce(0, +)
            let proportionalCount: Int
            if remainingBuckets == 1 || remainingWeight <= 0 {
                proportionalCount = remainingUnits
            } else {
                proportionalCount = Int((Double(remainingUnits) * normalizedWeights[index] / remainingWeight).rounded())
            }
            let bucketCount = max(min(proportionalCount, remainingUnits - (remainingBuckets - 1)), 1)
            let end = min(cursor + bucketCount, units.count)
            output.append(Array(units[cursor..<end]))
            cursor = end
        }
        return output
    }

    private static func normalizedSplitWeights(_ weights: [TimeInterval]) -> [Double] {
        let normalized = weights.map { max($0, 0.001) }
        let total = normalized.reduce(0, +)
        guard total > 0 else { return Array(repeating: 1, count: weights.count) }
        return normalized.map { $0 / total }
    }
}

private extension TranscriptSegment {
    func applyingSpeakerTurn(_ turn: MeetingSpeakerTurn) -> TranscriptSegment {
        let fallbackAudioSource = audioSource ?? (speaker == .me ? .microphone : .systemAudio)
        return updatingSpeakerAnalysis(
            speaker: turn.source == .mixed ? speaker : turn.source.defaultSpeaker,
            speakerID: turn.speakerID,
            speakerDisplayName: turn.displayName,
            audioSource: turn.source == .mixed ? fallbackAudioSource : turn.source,
            speakerConfidence: turn.confidence
        )
    }
}

import Foundation

enum TranscriptSegmentEvent: Sendable, Equatable {
    case partial(TranscriptSegment)
    case final(TranscriptSegment)
    case failed(speaker: TranscriptSpeaker, message: String)
    case finished(speaker: TranscriptSpeaker)
}

struct TranscriptAssemblyResult: Equatable {
    let segments: [TranscriptSegment]
    let affectedSegmentID: UUID?
    let finalizedSegmentID: UUID?
    let supersededSegmentIDs: [UUID]
}

enum TranscriptAssembler {
    static func apply(
        _ event: TranscriptSegmentEvent,
        to segments: [TranscriptSegment]
    ) -> TranscriptAssemblyResult {
        switch event {
        case .failed, .finished:
            return TranscriptAssemblyResult(
                segments: segments,
                affectedSegmentID: nil,
                finalizedSegmentID: nil,
                supersededSegmentIDs: []
            )
        case .partial(let segment):
            return upsert(
                segment,
                isFinal: false,
                into: segments
            )
        case .final(let segment):
            return upsert(
                segment,
                isFinal: true,
                into: segments
            )
        }
    }

    private static func upsert(
        _ segment: TranscriptSegment,
        isFinal: Bool,
        into existingSegments: [TranscriptSegment]
    ) -> TranscriptAssemblyResult {
        var segments = existingSegments

        if let existingIndex = segments.firstIndex(where: { $0.id == segment.id }) {
            let existing = segments[existingIndex]
            let existingTranslatedText = existing.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let preservesTranslatedText = existingTranslatedText?.isEmpty == false
            let textChanged =
                existing.text.trimmingCharacters(in: .whitespacesAndNewlines) !=
                segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            segments[existingIndex] = TranscriptSegment(
                id: existing.id,
                speaker: segment.speaker,
                startSeconds: existing.startSeconds,
                endSeconds: segment.endSeconds,
                text: segment.text,
                translatedText: preservesTranslatedText ? existing.translatedText : nil,
                isTranslationPending: existing.isTranslationPending || (preservesTranslatedText && textChanged),
                preventsAdjacentMerge: existing.preventsAdjacentMerge || segment.preventsAdjacentMerge
            )
            return finalizeIfNeeded(at: existingIndex, isFinal: isFinal, in: segments)
        }

        segments.append(segment)
        segments.sort { lhs, rhs in
            if lhs.startSeconds == rhs.startSeconds {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startSeconds < rhs.startSeconds
        }

        guard let insertedIndex = segments.firstIndex(where: { $0.id == segment.id }) else {
            return TranscriptAssemblyResult(
                segments: segments,
                affectedSegmentID: nil,
                finalizedSegmentID: nil,
                supersededSegmentIDs: []
            )
        }

        return finalizeIfNeeded(at: insertedIndex, isFinal: isFinal, in: segments)
    }

    private static func finalizeIfNeeded(
        at index: Int,
        isFinal: Bool,
        in segments: [TranscriptSegment]
    ) -> TranscriptAssemblyResult {
        guard segments.indices.contains(index) else {
            return TranscriptAssemblyResult(
                segments: segments,
                affectedSegmentID: nil,
                finalizedSegmentID: nil,
                supersededSegmentIDs: []
            )
        }

        guard isFinal else {
            var updatedSegments = segments
            updatedSegments[index] = updatedSegments[index].updatingTranslation(
                translatedText: nil,
                isTranslationPending: false
            )
            return TranscriptAssemblyResult(
                segments: updatedSegments,
                affectedSegmentID: updatedSegments[index].id,
                finalizedSegmentID: nil,
                supersededSegmentIDs: []
            )
        }

        var updatedSegments = segments
        var finalizedID = updatedSegments[index].id
        var supersededIDs: [UUID] = []
        if index > 0,
           let merged = TranscriptFormatter.mergedAdjacentSegment(
                previous: updatedSegments[index - 1],
                next: updatedSegments[index]
           ) {
            supersededIDs = [updatedSegments[index - 1].id, updatedSegments[index].id]
            updatedSegments[index - 1] = merged
            updatedSegments.remove(at: index)
            finalizedID = merged.id
        }

        return TranscriptAssemblyResult(
            segments: updatedSegments,
            affectedSegmentID: finalizedID,
            finalizedSegmentID: finalizedID,
            supersededSegmentIDs: supersededIDs
        )
    }
}

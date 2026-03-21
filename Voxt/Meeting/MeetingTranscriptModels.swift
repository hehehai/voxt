import Foundation

enum MeetingSpeaker: String, Codable, Hashable {
    case me
    case them

    nonisolated var displayTitle: String {
        switch self {
        case .me:
            return "我"
        case .them:
            return "them"
        }
    }
}

struct MeetingTranscriptSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let speaker: MeetingSpeaker
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval?
    let text: String
    let translatedText: String?
    let isTranslationPending: Bool

    init(
        id: UUID = UUID(),
        speaker: MeetingSpeaker,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval?,
        text: String,
        translatedText: String? = nil,
        isTranslationPending: Bool = false
    ) {
        self.id = id
        self.speaker = speaker
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.translatedText = translatedText
        self.isTranslationPending = isTranslationPending
    }

    func updatingTranslation(
        translatedText: String?,
        isTranslationPending: Bool
    ) -> MeetingTranscriptSegment {
        MeetingTranscriptSegment(
            id: id,
            speaker: speaker,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            text: text,
            translatedText: translatedText,
            isTranslationPending: isTranslationPending
        )
    }
}

enum MeetingTranscriptFormatter {
    nonisolated static func meaningfulSegments(for segments: [MeetingTranscriptSegment]) -> [MeetingTranscriptSegment] {
        segments.filter { segment in
            let hasOriginalText = !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasTranslatedText = !(segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return hasOriginalText || hasTranslatedText
        }
    }

    nonisolated static func mergedSegmentsForPersistence(
        primarySegments: [MeetingTranscriptSegment],
        fallbackSegments: [MeetingTranscriptSegment]
    ) -> [MeetingTranscriptSegment] {
        var mergedByID: [UUID: MeetingTranscriptSegment] = [:]

        for segment in meaningfulSegments(for: fallbackSegments) {
            mergedByID[segment.id] = segment
        }

        for segment in meaningfulSegments(for: primarySegments) {
            if let existing = mergedByID[segment.id] {
                mergedByID[segment.id] = mergedSegment(preferred: segment, fallback: existing)
            } else {
                mergedByID[segment.id] = segment
            }
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.startSeconds == rhs.startSeconds {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startSeconds < rhs.startSeconds
        }
    }

    nonisolated static func timestampString(for seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainder = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    nonisolated static func copyString(for segment: MeetingTranscriptSegment) -> String {
        exportString(for: segment)
    }

    nonisolated static func joinedText(for segments: [MeetingTranscriptSegment]) -> String {
        segments
            .map(exportString(for:))
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func exportString(for segment: MeetingTranscriptSegment) -> String {
        var lines = ["\(timestampString(for: segment.startSeconds)) \(segment.speaker.displayTitle) \(segment.text)"]
        if let translatedText = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !translatedText.isEmpty {
            lines.append("   -> \(translatedText)")
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated static func mergedSegment(
        preferred: MeetingTranscriptSegment,
        fallback: MeetingTranscriptSegment
    ) -> MeetingTranscriptSegment {
        let preferredText = preferred.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackText = fallback.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = preferred.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTranslatedText = fallback.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines)

        return MeetingTranscriptSegment(
            id: preferred.id,
            speaker: preferred.speaker,
            startSeconds: preferred.startSeconds,
            endSeconds: preferred.endSeconds ?? fallback.endSeconds,
            text: preferredText.isEmpty ? fallbackText : preferredText,
            translatedText: (translatedText?.isEmpty == false ? translatedText : fallbackTranslatedText),
            isTranslationPending: preferred.isTranslationPending && (translatedText?.isEmpty ?? true)
        )
    }
}

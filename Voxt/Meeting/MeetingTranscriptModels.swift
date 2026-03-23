import Foundation

enum MeetingSpeaker: String, Codable, Hashable, Sendable {
    case me
    case them

    nonisolated var displayTitle: String {
        switch self {
        case .me:
            return "Me"
        case .them:
            return "Them"
        }
    }
}

struct MeetingTranscriptSegment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let speaker: MeetingSpeaker
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval?
    let text: String
    let translatedText: String?
    let isTranslationPending: Bool
    let preventsAdjacentMerge: Bool

    nonisolated init(
        id: UUID = UUID(),
        speaker: MeetingSpeaker,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval?,
        text: String,
        translatedText: String? = nil,
        isTranslationPending: Bool = false,
        preventsAdjacentMerge: Bool = false
    ) {
        self.id = id
        self.speaker = speaker
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.translatedText = translatedText
        self.isTranslationPending = isTranslationPending
        self.preventsAdjacentMerge = preventsAdjacentMerge
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
            isTranslationPending: isTranslationPending,
            preventsAdjacentMerge: preventsAdjacentMerge
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case speaker
        case startSeconds
        case endSeconds
        case text
        case translatedText
        case isTranslationPending
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        speaker = try container.decode(MeetingSpeaker.self, forKey: .speaker)
        startSeconds = try container.decode(TimeInterval.self, forKey: .startSeconds)
        endSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .endSeconds)
        text = try container.decode(String.self, forKey: .text)
        translatedText = try container.decodeIfPresent(String.self, forKey: .translatedText)
        isTranslationPending = try container.decodeIfPresent(Bool.self, forKey: .isTranslationPending) ?? false
        preventsAdjacentMerge = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(speaker, forKey: .speaker)
        try container.encode(startSeconds, forKey: .startSeconds)
        try container.encodeIfPresent(endSeconds, forKey: .endSeconds)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(translatedText, forKey: .translatedText)
        try container.encode(isTranslationPending, forKey: .isTranslationPending)
    }
}

enum MeetingTranscriptFormatter {
    nonisolated static func meaningfulSegments(for segments: [MeetingTranscriptSegment]) -> [MeetingTranscriptSegment] {
        segments.filter { segment in
            let hasOriginalText = isMeaningfulText(segment.text)
            let hasTranslatedText = isMeaningfulText(segment.translatedText)
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

        let sorted = mergedByID.values.sorted { lhs, rhs in
            if lhs.startSeconds == rhs.startSeconds {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startSeconds < rhs.startSeconds
        }
        return mergedAdjacentSegments(in: sorted)
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
            .map { exportString(for: $0) }
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

    nonisolated static func mergedAdjacentSegment(
        previous: MeetingTranscriptSegment,
        next: MeetingTranscriptSegment
    ) -> MeetingTranscriptSegment? {
        guard !previous.preventsAdjacentMerge, !next.preventsAdjacentMerge else { return nil }
        guard previous.speaker == next.speaker else { return nil }
        guard next.startSeconds >= previous.startSeconds else { return nil }
        let previousEnd = previous.endSeconds ?? previous.startSeconds
        guard next.startSeconds - previousEnd <= 2.0 else { return nil }

        return MeetingTranscriptSegment(
            id: previous.id,
            speaker: previous.speaker,
            startSeconds: previous.startSeconds,
            endSeconds: max(previousEnd, next.endSeconds ?? next.startSeconds),
            text: mergedText(previous.text, next.text),
            translatedText: nil,
            isTranslationPending: false,
            preventsAdjacentMerge: false
        )
    }

    private nonisolated static func mergedAdjacentSegments(
        in segments: [MeetingTranscriptSegment]
    ) -> [MeetingTranscriptSegment] {
        var merged: [MeetingTranscriptSegment] = []
        for segment in segments {
            if let last = merged.last,
               let mergedSegment = mergedAdjacentSegment(previous: last, next: segment) {
                merged[merged.count - 1] = mergedSegment
            } else {
                merged.append(segment)
            }
        }
        return merged
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
            isTranslationPending: preferred.isTranslationPending && (translatedText?.isEmpty ?? true),
            preventsAdjacentMerge: preferred.preventsAdjacentMerge || fallback.preventsAdjacentMerge
        )
    }

    private nonisolated static func mergedText(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }

        let leftLast = left.unicodeScalars.last
        let rightFirst = right.unicodeScalars.first
        let separator = needsInlineSeparator(leftLast: leftLast, rightFirst: rightFirst) ? " " : ""
        return left + separator + right
    }

    private nonisolated static func needsInlineSeparator(
        leftLast: UnicodeScalar?,
        rightFirst: UnicodeScalar?
    ) -> Bool {
        guard let leftLast, let rightFirst else { return true }
        let punctuationScalars = CharacterSet(charactersIn: " \t\n\r,.!?;:，。！？；：、)]}\"'》】）")
        if punctuationScalars.contains(leftLast) || punctuationScalars.contains(rightFirst) {
            return false
        }
        let alphanumerics = CharacterSet.alphanumerics
        return alphanumerics.contains(leftLast) && alphanumerics.contains(rightFirst)
    }

    private nonisolated static func isMeaningfulText(_ value: String?) -> Bool {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return false
        }
        let uuidPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#
        if trimmed.range(of: uuidPattern, options: .regularExpression) != nil {
            return false
        }
        return true
    }
}

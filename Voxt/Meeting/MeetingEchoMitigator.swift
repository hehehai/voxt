import Foundation

struct MeetingEchoMitigator: Sendable {
    let comparisonWindowSeconds: TimeInterval = 4
    private let exactDuplicateGapThreshold: TimeInterval = 1.5
    private let fuzzyDuplicateGapThreshold: TimeInterval = 2.0

    func mitigate(
        _ segment: MeetingTranscriptSegment,
        against existingSegments: [MeetingTranscriptSegment]
    ) -> MeetingTranscriptSegment? {
        guard segment.speaker.isRemote else { return segment }

        let recentSegments = existingSegments
            .filter { existing in
                existing.id != segment.id &&
                existing.endSeconds ?? existing.startSeconds <= segment.endSeconds ?? segment.startSeconds &&
                (segment.startSeconds - (existing.endSeconds ?? existing.startSeconds)) <= comparisonWindowSeconds
            }
            .suffix(8)

        var candidate = segment
        for existing in recentSegments.reversed() {
            guard let updated = resolve(candidate: candidate, recent: existing) else {
                return nil
            }
            candidate = updated
        }

        let trimmed = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return candidate.updatingText(trimmed)
    }

    private func resolve(
        candidate: MeetingTranscriptSegment,
        recent: MeetingTranscriptSegment
    ) -> MeetingTranscriptSegment? {
        let candidateText = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentText = recent.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidateText.isEmpty, !recentText.isEmpty else { return candidate }

        let candidateCanonical = canonical(candidateText)
        let recentCanonical = canonical(recentText)
        guard !candidateCanonical.isEmpty, !recentCanonical.isEmpty else { return candidate }
        let candidateTokens = tokenSpans(in: candidateText)
        let recentTokens = tokenSpans(in: recentText)

        let gap = candidate.startSeconds - (recent.endSeconds ?? recent.startSeconds)
        if candidateCanonical == recentCanonical,
           gap <= exactDuplicateGapThreshold {
            return nil
        }

        if recent.speaker == .me {
            if let trimmedPrefix = trimmingPrefix(candidateText, duplicate: recentText),
               !canonical(trimmedPrefix).isEmpty {
                return candidate.updatingText(trimmedPrefix)
            }
            if let trimmedSuffix = trimmingSuffix(candidateText, duplicate: recentText),
               !canonical(trimmedSuffix).isEmpty {
                return candidate.updatingText(trimmedSuffix)
            }
            if let trimmedTokenPrefix = trimmingTokenPrefix(candidateText, duplicate: recentText),
               !canonical(trimmedTokenPrefix).isEmpty {
                return candidate.updatingText(trimmedTokenPrefix)
            }
            if let trimmedTokenSuffix = trimmingTokenSuffix(candidateText, duplicate: recentText),
               !canonical(trimmedTokenSuffix).isEmpty {
                return candidate.updatingText(trimmedTokenSuffix)
            }
        }

        if recentCanonical.contains(candidateCanonical),
           candidateCanonical.count <= 18,
           gap <= exactDuplicateGapThreshold {
            return nil
        }

        let tokenOverlap = tokenOverlapScore(lhs: candidateTokens, rhs: recentTokens)
        let canonicalSimilarity = similarityScore(lhs: candidateCanonical, rhs: recentCanonical)
        if recent.speaker == .me,
           tokenOverlap >= 0.85,
           min(candidateTokens.count, recentTokens.count) >= 2,
           gap <= fuzzyDuplicateGapThreshold {
            return nil
        }

        if canonicalSimilarity >= 0.94,
           min(candidateCanonical.count, recentCanonical.count) >= 16,
           gap <= exactDuplicateGapThreshold {
            return nil
        }

        return candidate
    }

    private func trimmingPrefix(_ text: String, duplicate: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDuplicate = duplicate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count > trimmedDuplicate.count,
              trimmedText.localizedLowercase.hasPrefix(trimmedDuplicate.localizedLowercase)
        else {
            return nil
        }

        let suffixStart = trimmedText.index(trimmedText.startIndex, offsetBy: trimmedDuplicate.count)
        let suffix = String(trimmedText[suffixStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? nil : suffix
    }

    private func trimmingSuffix(_ text: String, duplicate: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDuplicate = duplicate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count > trimmedDuplicate.count,
              trimmedText.localizedLowercase.hasSuffix(trimmedDuplicate.localizedLowercase)
        else {
            return nil
        }

        let prefixEnd = trimmedText.index(trimmedText.endIndex, offsetBy: -trimmedDuplicate.count)
        let prefix = String(trimmedText[..<prefixEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? nil : prefix
    }

    private func trimmingTokenPrefix(_ text: String, duplicate: String) -> String? {
        let textTokens = tokenSpans(in: text)
        let duplicateTokens = tokenSpans(in: duplicate)
        guard !textTokens.isEmpty, !duplicateTokens.isEmpty else { return nil }
        guard textTokens.count > duplicateTokens.count else { return nil }

        let matchedCount = sharedPrefixTokenCount(lhs: textTokens, rhs: duplicateTokens)
        guard matchedCount == duplicateTokens.count else { return nil }

        let cutIndex = textTokens[matchedCount - 1].range.upperBound
        let suffix = String(text[cutIndex...]).trimmingCharacters(in: trimCharacterSet)
        return suffix.isEmpty ? nil : suffix
    }

    private func trimmingTokenSuffix(_ text: String, duplicate: String) -> String? {
        let textTokens = tokenSpans(in: text)
        let duplicateTokens = tokenSpans(in: duplicate)
        guard !textTokens.isEmpty, !duplicateTokens.isEmpty else { return nil }
        guard textTokens.count > duplicateTokens.count else { return nil }

        let matchedCount = sharedSuffixTokenCount(lhs: textTokens, rhs: duplicateTokens)
        guard matchedCount == duplicateTokens.count else { return nil }

        let cutIndex = textTokens[textTokens.count - matchedCount].range.lowerBound
        let prefix = String(text[..<cutIndex]).trimmingCharacters(in: trimCharacterSet)
        return prefix.isEmpty ? nil : prefix
    }

    private func canonical(_ text: String) -> String {
        let disallowed = CharacterSet.alphanumerics.inverted
        return text.unicodeScalars
            .filter { !disallowed.contains($0) }
            .map { CharacterSet.uppercaseLetters.contains($0) ? String($0).lowercased() : String($0) }
            .joined()
    }

    private var trimCharacterSet: CharacterSet {
        CharacterSet.whitespacesAndNewlines.union(CharacterSet.punctuationCharacters)
    }

    private func tokenSpans(in text: String) -> [TokenSpan] {
        var spans: [TokenSpan] = []
        var currentTokenStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let isTokenCharacter = character.unicodeScalars.allSatisfy {
                CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
            }

            if isTokenCharacter {
                currentTokenStart = currentTokenStart ?? index
            } else if let tokenStart = currentTokenStart {
                let range = tokenStart..<index
                spans.append(TokenSpan(value: text[range].lowercased(), range: range))
                currentTokenStart = nil
            }

            index = text.index(after: index)
        }

        if let tokenStart = currentTokenStart {
            let range = tokenStart..<text.endIndex
            spans.append(TokenSpan(value: text[range].lowercased(), range: range))
        }

        return spans
    }

    private func sharedPrefixTokenCount(lhs: [TokenSpan], rhs: [TokenSpan]) -> Int {
        let count = min(lhs.count, rhs.count)
        var matched = 0
        while matched < count, lhs[matched].value == rhs[matched].value {
            matched += 1
        }
        return matched
    }

    private func sharedSuffixTokenCount(lhs: [TokenSpan], rhs: [TokenSpan]) -> Int {
        let count = min(lhs.count, rhs.count)
        var matched = 0
        while matched < count,
              lhs[lhs.count - 1 - matched].value == rhs[rhs.count - 1 - matched].value {
            matched += 1
        }
        return matched
    }

    private func tokenOverlapScore(lhs: [TokenSpan], rhs: [TokenSpan]) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }

        var rhsCounts: [String: Int] = [:]
        rhs.forEach { rhsCounts[$0.value, default: 0] += 1 }

        var intersection = 0
        for token in lhs {
            let count = rhsCounts[token.value, default: 0]
            guard count > 0 else { continue }
            intersection += 1
            rhsCounts[token.value] = count - 1
        }

        return Double(intersection) / Double(min(lhs.count, rhs.count))
    }

    private func similarityScore(lhs: String, rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let lhsBigrams = characterBigrams(in: lhs)
        let rhsBigrams = characterBigrams(in: rhs)
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else {
            return lhs == rhs ? 1 : 0
        }
        let intersection = lhsBigrams.intersection(rhsBigrams).count
        let total = lhsBigrams.count + rhsBigrams.count
        guard total > 0 else { return 0 }
        return Double(intersection * 2) / Double(total)
    }

    private func characterBigrams(in text: String) -> Set<String> {
        let characters = Array(text)
        guard characters.count >= 2 else {
            return text.isEmpty ? [] : [text]
        }

        var bigrams = Set<String>()
        for index in 0..<(characters.count - 1) {
            bigrams.insert(String(characters[index...index + 1]))
        }
        return bigrams
    }
}

private struct TokenSpan {
    let value: String
    let range: Range<String.Index>
}

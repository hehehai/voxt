import Foundation
import Combine

enum DictionaryEntrySource: String, Codable, CaseIterable {
    case manual
    case auto

    var titleKey: String {
        switch self {
        case .manual:
            return "Manual"
        case .auto:
            return "Automatic"
        }
    }
}

enum DictionaryEntryStatus: String, Codable {
    case active
    case disabled
}

enum DictionaryVariantConfidence: String, Codable {
    case high
    case medium
    case low
}

enum DictionaryFilter: String, CaseIterable, Identifiable {
    case all
    case autoAdded
    case manualAdded

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all:
            return "All"
        case .autoAdded:
            return "Automatic"
        case .manualAdded:
            return "Manual"
        }
    }
}

struct ObservedVariant: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var normalizedText: String
    var count: Int
    var lastSeenAt: Date
    var confidence: DictionaryVariantConfidence

    init(
        id: UUID = UUID(),
        text: String,
        normalizedText: String,
        count: Int = 1,
        lastSeenAt: Date = Date(),
        confidence: DictionaryVariantConfidence
    ) {
        self.id = id
        self.text = text
        self.normalizedText = normalizedText
        self.count = count
        self.lastSeenAt = lastSeenAt
        self.confidence = confidence
    }
}

struct DictionaryReplacementTerm: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var normalizedText: String

    init(
        id: UUID = UUID(),
        text: String,
        normalizedText: String
    ) {
        self.id = id
        self.text = text
        self.normalizedText = normalizedText
    }
}

struct DictionaryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var term: String
    var normalizedTerm: String
    var groupID: UUID?
    var groupNameSnapshot: String?
    var source: DictionaryEntrySource
    var createdAt: Date
    var updatedAt: Date
    var lastMatchedAt: Date?
    var matchCount: Int
    var status: DictionaryEntryStatus
    var observedVariants: [ObservedVariant]
    var replacementTerms: [DictionaryReplacementTerm]

    enum CodingKeys: String, CodingKey {
        case id
        case term
        case normalizedTerm
        case groupID
        case groupNameSnapshot
        case source
        case createdAt
        case updatedAt
        case lastMatchedAt
        case matchCount
        case status
        case observedVariants
        case replacementTerms
    }

    init(
        id: UUID = UUID(),
        term: String,
        normalizedTerm: String,
        groupID: UUID? = nil,
        groupNameSnapshot: String? = nil,
        source: DictionaryEntrySource,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastMatchedAt: Date? = nil,
        matchCount: Int = 0,
        status: DictionaryEntryStatus = .active,
        observedVariants: [ObservedVariant] = [],
        replacementTerms: [DictionaryReplacementTerm] = []
    ) {
        self.id = id
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.groupID = groupID
        self.groupNameSnapshot = groupNameSnapshot
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMatchedAt = lastMatchedAt
        self.matchCount = matchCount
        self.status = status
        self.observedVariants = observedVariants
        self.replacementTerms = replacementTerms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        term = try container.decode(String.self, forKey: .term)
        normalizedTerm = try container.decode(String.self, forKey: .normalizedTerm)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        groupNameSnapshot = try container.decodeIfPresent(String.self, forKey: .groupNameSnapshot)
        source = try container.decode(DictionaryEntrySource.self, forKey: .source)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastMatchedAt = try container.decodeIfPresent(Date.self, forKey: .lastMatchedAt)
        matchCount = try container.decodeIfPresent(Int.self, forKey: .matchCount) ?? 0
        status = try container.decodeIfPresent(DictionaryEntryStatus.self, forKey: .status) ?? .active
        observedVariants = try container.decodeIfPresent([ObservedVariant].self, forKey: .observedVariants) ?? []
        replacementTerms = try container.decodeIfPresent([DictionaryReplacementTerm].self, forKey: .replacementTerms) ?? []
    }

    var matchKeys: [String] {
        [normalizedTerm] + replacementTerms.map(\.normalizedText)
    }

    func visibleMatchKeys(blockedKeys: Set<String>) -> [String] {
        if groupID == nil {
            return matchKeys.filter { !blockedKeys.contains($0) }
        }
        return matchKeys
    }
}

enum DictionaryMatchSource: String, Hashable {
    case term
    case replacementTerm
    case observedVariant
}

enum DictionaryMatchReason: String, Codable {
    case exactTerm
    case exactVariant
    case exactWindow
    case fuzzyWindow
}

struct DictionaryMatchCandidate: Identifiable, Hashable {
    let entryID: UUID
    let term: String
    let matchedText: String
    let normalizedMatchedText: String
    let score: Double
    let reason: DictionaryMatchReason
    let source: DictionaryMatchSource
    let matchRange: NSRange?

    var id: String {
        let location = matchRange?.location ?? -1
        let length = matchRange?.length ?? 0
        return "\(entryID.uuidString)|\(normalizedMatchedText)|\(reason.rawValue)|\(source.rawValue)|\(location)|\(length)"
    }

    var allowsAutomaticReplacement: Bool {
        if source == .replacementTerm {
            return true
        }

        switch reason {
        case .exactVariant:
            return true
        case .exactWindow:
            return score >= 0.985
        case .fuzzyWindow:
            return score >= 0.97 && normalizedMatchedText.count >= 5
        case .exactTerm:
            return false
        }
    }

    var shouldPersistObservedVariant: Bool {
        source != .replacementTerm && reason != .exactTerm
    }
}

struct DictionaryPromptContext {
    let entries: [DictionaryEntry]
    let candidates: [DictionaryMatchCandidate]

    var isEmpty: Bool {
        entries.isEmpty || candidates.isEmpty
    }

    func glossaryText(limit: Int = 12) -> String {
        guard !isEmpty else { return "" }

        var seen = Set<UUID>()
        var lines: [String] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard let entry = entries.first(where: { $0.id == candidate.entryID }) else { continue }
            guard seen.insert(entry.id).inserted else { continue }
            lines.append("- \(entry.term)")
            if lines.count >= limit {
                break
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct DictionaryCorrectionResult {
    let text: String
    let candidates: [DictionaryMatchCandidate]
    let correctedTerms: [String]
}

struct DictionaryImportResult: Equatable {
    let addedCount: Int
    let skippedCount: Int
}

enum DictionaryStoreError: LocalizedError {
    case emptyTerm
    case duplicateTerm
    case replacementMatchesDictionaryTerm
    case duplicateReplacementTerm(String)

    var errorDescription: String? {
        switch self {
        case .emptyTerm:
            return AppLocalization.localizedString("Dictionary term cannot be empty.")
        case .duplicateTerm:
            return AppLocalization.localizedString("This term already exists in the dictionary.")
        case .replacementMatchesDictionaryTerm:
            return AppLocalization.localizedString("Replacement match term cannot be the same as the dictionary term.")
        case .duplicateReplacementTerm(let term):
            return AppLocalization.format(
                "This replacement match term already exists in the dictionary: %@.",
                term
            )
        }
    }
}

private struct DictionaryToken {
    let raw: String
    let normalized: String
    let range: NSRange
}

private struct DictionaryScriptProfile {
    var containsLatin = false
    var containsDigit = false
    var containsHan = false
    var containsKana = false
    var containsHangul = false

    var containsCJKLike: Bool {
        containsHan || containsKana || containsHangul
    }

    var isLatinLike: Bool {
        (containsLatin || containsDigit) && !containsCJKLike
    }

    var isMixedScript: Bool {
        containsCJKLike && (containsLatin || containsDigit)
    }
}

private struct DictionaryNormalizedMapping {
    var text: String
    var sourceRanges: [NSRange]
}

private enum DictionaryMatchVariantSource {
    case term
    case replacementTerm
    case observedVariant

    var source: DictionaryMatchSource {
        switch self {
        case .term:
            return .term
        case .replacementTerm:
            return .replacementTerm
        case .observedVariant:
            return .observedVariant
        }
    }

    var allowsFuzzyMatch: Bool {
        self != .replacementTerm
    }
}

private struct DictionaryMatchVariant {
    let text: String
    let normalizedText: String
    let source: DictionaryMatchVariantSource
}

private struct DictionaryPreparedEntryInput {
    let display: String
    let normalized: String
    let replacementTerms: [DictionaryReplacementTerm]
}

private func dictionaryIsWordScalar(_ scalar: UnicodeScalar) -> Bool {
    CharacterSet.alphanumerics.contains(scalar)
        || dictionaryIsHanLike(scalar)
        || dictionaryIsKana(scalar)
        || dictionaryIsHangul(scalar)
}

private func dictionaryIsHanLike(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x4E00...0x9FFF,
         0x3400...0x4DBF,
         0x20000...0x2A6DF,
         0x2A700...0x2B73F,
         0x2B740...0x2B81F,
         0x2B820...0x2CEAF:
        return true
    default:
        return false
    }
}

private func dictionaryIsKana(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x309F,
         0x30A0...0x30FF,
         0x31F0...0x31FF,
         0xFF66...0xFF9F:
        return true
    default:
        return false
    }
}

private func dictionaryIsHangul(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x1100...0x11FF,
         0x3130...0x318F,
         0xA960...0xA97F,
         0xAC00...0xD7AF,
         0xD7B0...0xD7FF:
        return true
    default:
        return false
    }
}

private func dictionaryScriptProfile(for text: String) -> DictionaryScriptProfile {
    var profile = DictionaryScriptProfile()
    for scalar in text.unicodeScalars {
        if CharacterSet.decimalDigits.contains(scalar) {
            profile.containsDigit = true
        } else if CharacterSet.letters.contains(scalar),
                  !dictionaryIsHanLike(scalar),
                  !dictionaryIsKana(scalar),
                  !dictionaryIsHangul(scalar) {
            profile.containsLatin = true
        }

        if dictionaryIsHanLike(scalar) {
            profile.containsHan = true
        }
        if dictionaryIsKana(scalar) {
            profile.containsKana = true
        }
        if dictionaryIsHangul(scalar) {
            profile.containsHangul = true
        }
    }
    return profile
}

private func dictionaryNormalizedMapping(for text: String) -> DictionaryNormalizedMapping {
    var output = ""
    var sourceRanges: [NSRange] = []
    var previousWasWhitespace = false
    var index = text.startIndex

    while index < text.endIndex {
        let nextIndex = text.index(after: index)
        let fragment = String(text[index..<nextIndex]).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        let sourceRange = NSRange(index..<nextIndex, in: text)

        for scalar in fragment.unicodeScalars {
            if dictionaryIsWordScalar(scalar) {
                output.unicodeScalars.append(scalar)
                sourceRanges.append(sourceRange)
                previousWasWhitespace = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar)
                        || CharacterSet.punctuationCharacters.contains(scalar)
                        || CharacterSet.symbols.contains(scalar) {
                if !previousWasWhitespace && !output.isEmpty {
                    output.append(" ")
                    sourceRanges.append(sourceRange)
                    previousWasWhitespace = true
                }
            }
        }

        index = nextIndex
    }

    while output.first == " " {
        output.removeFirst()
        sourceRanges.removeFirst()
    }

    while output.last == " " {
        output.removeLast()
        sourceRanges.removeLast()
    }

    return DictionaryNormalizedMapping(text: output, sourceRanges: sourceRanges)
}

private func dictionaryExactNormalizedMatchRanges(
    in text: String,
    normalizedNeedle: String,
    requireTokenBoundaries: Bool
) -> [NSRange] {
    guard !normalizedNeedle.isEmpty else { return [] }
    let mapping = dictionaryNormalizedMapping(for: text)
    guard !mapping.text.isEmpty, !mapping.sourceRanges.isEmpty else { return [] }

    var matches: [NSRange] = []
    var searchStart = mapping.text.startIndex

    while searchStart < mapping.text.endIndex,
          let matchRange = mapping.text.range(
            of: normalizedNeedle,
            options: [],
            range: searchStart..<mapping.text.endIndex
          ) {
        let lowerIsBoundary =
            matchRange.lowerBound == mapping.text.startIndex
            || mapping.text[mapping.text.index(before: matchRange.lowerBound)] == " "
        let upperIsBoundary =
            matchRange.upperBound == mapping.text.endIndex
            || mapping.text[matchRange.upperBound] == " "

        if !requireTokenBoundaries || (lowerIsBoundary && upperIsBoundary) {
            let lowerOffset = mapping.text.distance(from: mapping.text.startIndex, to: matchRange.lowerBound)
            let upperOffset = mapping.text.distance(from: mapping.text.startIndex, to: matchRange.upperBound)

            if lowerOffset < mapping.sourceRanges.count, upperOffset > lowerOffset {
                let startRange = mapping.sourceRanges[lowerOffset]
                let endRange = mapping.sourceRanges[upperOffset - 1]
                let combined = NSRange(
                    location: startRange.location,
                    length: (endRange.location + endRange.length) - startRange.location
                )
                if !matches.contains(combined) {
                    matches.append(combined)
                }
            }
        }

        if matchRange.lowerBound < mapping.text.endIndex {
            searchStart = mapping.text.index(after: matchRange.lowerBound)
        } else {
            break
        }
    }

    return matches
}

struct DictionaryMatcher {
    let entries: [DictionaryEntry]
    let blockedGlobalMatchKeys: Set<String>

    func promptContext(for text: String) -> DictionaryPromptContext {
        let candidates = recallCandidates(in: text)
        return DictionaryPromptContext(entries: entries, candidates: candidates)
    }

    func recallCandidates(in text: String) -> [DictionaryMatchCandidate] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let rawTokens = tokenize(text)
        var bestByID: [String: DictionaryMatchCandidate] = [:]

        for entry in entries where entry.status == .active {
            for variant in matchVariants(for: entry) {
                guard !shouldBlock(variant: variant, entry: entry) else { continue }

                for candidate in exactCandidates(for: entry, variant: variant, text: text) {
                    let key = candidate.id
                    if let existing = bestByID[key], existing.score >= candidate.score {
                        continue
                    }
                    bestByID[key] = candidate
                }

                guard variant.source.allowsFuzzyMatch,
                      let candidate = bestFuzzyCandidate(
                        for: entry,
                        variant: variant,
                        text: text,
                        rawTokens: rawTokens
                      ) else {
                    continue
                }

                let key = candidate.id
                if let existing = bestByID[key], existing.score >= candidate.score {
                    continue
                }
                bestByID[key] = candidate
            }
        }

        return bestByID.values.sorted {
            if $0.score == $1.score {
                if ($0.matchRange?.location ?? 0) == ($1.matchRange?.location ?? 0) {
                    return $0.term < $1.term
                }
                return ($0.matchRange?.location ?? 0) < ($1.matchRange?.location ?? 0)
            }
            return $0.score > $1.score
        }
    }

    func applyCorrections(to text: String, automaticReplacementEnabled: Bool) -> DictionaryCorrectionResult {
        let candidates = recallCandidates(in: text)
        let replacementCandidates = candidates
            .filter { shouldApplyReplacement(for: $0, automaticReplacementEnabled: automaticReplacementEnabled) }
            .sorted(by: replacementSortComparator)

        guard !replacementCandidates.isEmpty else {
            return DictionaryCorrectionResult(text: text, candidates: candidates, correctedTerms: [])
        }

        let output = NSMutableString(string: text)
        var correctedTerms: [String] = []
        var appliedRanges: [NSRange] = []

        for candidate in replacementCandidates {
            guard let matchRange = candidate.matchRange, matchRange.length > 0 else { continue }
            guard candidate.matchedText.trimmingCharacters(in: .whitespacesAndNewlines) != candidate.term else { continue }
            guard !appliedRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) else { continue }

            output.replaceCharacters(in: matchRange, with: candidate.term)
            correctedTerms.append(candidate.term)
            appliedRanges.append(matchRange)
        }

        return DictionaryCorrectionResult(
            text: output as String,
            candidates: candidates,
            correctedTerms: correctedTerms
        )
    }

    private func shouldApplyReplacement(
        for candidate: DictionaryMatchCandidate,
        automaticReplacementEnabled: Bool
    ) -> Bool {
        if candidate.source == .replacementTerm {
            return true
        }
        guard automaticReplacementEnabled else { return false }
        return candidate.allowsAutomaticReplacement
    }

    private func replacementSortComparator(
        lhs: DictionaryMatchCandidate,
        rhs: DictionaryMatchCandidate
    ) -> Bool {
        let lhsLocation = lhs.matchRange?.location ?? -1
        let rhsLocation = rhs.matchRange?.location ?? -1
        if lhsLocation != rhsLocation {
            return lhsLocation > rhsLocation
        }

        let lhsPriority = replacementPriority(for: lhs)
        let rhsPriority = replacementPriority(for: rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority > rhsPriority
        }

        let lhsLength = lhs.matchRange?.length ?? 0
        let rhsLength = rhs.matchRange?.length ?? 0
        if lhsLength != rhsLength {
            return lhsLength > rhsLength
        }

        return lhs.score > rhs.score
    }

    private func replacementPriority(for candidate: DictionaryMatchCandidate) -> Int {
        if candidate.source == .replacementTerm {
            return 4
        }

        switch candidate.reason {
        case .exactVariant:
            return 3
        case .exactWindow:
            return 2
        case .fuzzyWindow:
            return 1
        case .exactTerm:
            return 0
        }
    }

    private func matchVariants(for entry: DictionaryEntry) -> [DictionaryMatchVariant] {
        var variants = [
            DictionaryMatchVariant(
                text: entry.term,
                normalizedText: entry.normalizedTerm,
                source: .term
            )
        ]

        variants.append(
            contentsOf: entry.replacementTerms.map {
                DictionaryMatchVariant(
                    text: $0.text,
                    normalizedText: $0.normalizedText,
                    source: .replacementTerm
                )
            }
        )

        variants.append(
            contentsOf: entry.observedVariants.map {
                DictionaryMatchVariant(
                    text: $0.text,
                    normalizedText: $0.normalizedText,
                    source: .observedVariant
                )
            }
        )

        return variants
    }

    private func shouldBlock(variant: DictionaryMatchVariant, entry: DictionaryEntry) -> Bool {
        guard entry.groupID == nil else { return false }
        return blockedGlobalMatchKeys.contains(variant.normalizedText)
    }

    private func exactCandidates(
        for entry: DictionaryEntry,
        variant: DictionaryMatchVariant,
        text: String
    ) -> [DictionaryMatchCandidate] {
        guard !variant.normalizedText.isEmpty else { return [] }
        let profile = dictionaryScriptProfile(for: variant.text)
        let requireTokenBoundaries = !profile.containsCJKLike || profile.containsLatin || profile.containsDigit
        let ranges = dictionaryExactNormalizedMatchRanges(
            in: text,
            normalizedNeedle: variant.normalizedText,
            requireTokenBoundaries: requireTokenBoundaries
        )
        let fullText = text as NSString

        return ranges.map { range in
            let matchedText = fullText.substring(with: range)
            let reason = exactReason(for: entry, variant: variant, matchedText: matchedText)
            return DictionaryMatchCandidate(
                entryID: entry.id,
                term: entry.term,
                matchedText: matchedText,
                normalizedMatchedText: variant.normalizedText,
                score: reason == .exactTerm ? 1.0 : 0.995,
                reason: reason,
                source: variant.source.source,
                matchRange: range
            )
        }
    }

    private func exactReason(
        for entry: DictionaryEntry,
        variant: DictionaryMatchVariant,
        matchedText: String
    ) -> DictionaryMatchReason {
        switch variant.source {
        case .replacementTerm, .observedVariant:
            return .exactVariant
        case .term:
            return matchedText == entry.term ? .exactTerm : .exactWindow
        }
    }

    private func bestFuzzyCandidate(
        for entry: DictionaryEntry,
        variant: DictionaryMatchVariant,
        text: String,
        rawTokens: [DictionaryToken]
    ) -> DictionaryMatchCandidate? {
        guard !variant.normalizedText.isEmpty else { return nil }
        let scriptProfile = dictionaryScriptProfile(for: variant.text)
        guard allowsFuzzyMatch(for: scriptProfile) else { return nil }

        let variantTokenCount = max(1, tokenize(variant.text).count)
        let windowSizes = Array(
            Set([
                variantTokenCount,
                max(1, variantTokenCount - 1),
                variantTokenCount + 1
            ])
        ).sorted()
        var best: DictionaryMatchCandidate?

        for windowSize in windowSizes {
            guard windowSize <= rawTokens.count else { continue }
            for start in 0...(rawTokens.count - windowSize) {
                let window = Array(rawTokens[start..<(start + windowSize)])
                let rawWindow = (text as NSString).substring(
                    with: NSRange(
                        location: window[0].range.location,
                        length: (window[window.count - 1].range.location + window[window.count - 1].range.length) - window[0].range.location
                    )
                )
                let normalizedWindow = window.map(\.normalized).joined(separator: " ")
                guard !normalizedWindow.isEmpty else { continue }
                guard normalizedWindow != variant.normalizedText else { continue }

                let distance = levenshteinDistance(lhs: normalizedWindow, rhs: variant.normalizedText)
                let maxLength = max(normalizedWindow.count, variant.normalizedText.count)
                guard maxLength >= minimumFuzzyLength(for: scriptProfile) else { continue }
                let threshold = fuzzyThreshold(for: scriptProfile, maxLength: maxLength)
                guard distance <= threshold else { continue }

                let score = 1.0 - (Double(distance) / Double(maxLength))
                guard score >= minimumFuzzyScore(for: scriptProfile) else { continue }

                let candidate = DictionaryMatchCandidate(
                    entryID: entry.id,
                    term: entry.term,
                    matchedText: rawWindow,
                    normalizedMatchedText: normalizedWindow,
                    score: score,
                    reason: .fuzzyWindow,
                    source: variant.source.source,
                    matchRange: NSRange(
                        location: window[0].range.location,
                        length: (window[window.count - 1].range.location + window[window.count - 1].range.length) - window[0].range.location
                    )
                )

                if best == nil || best!.score < candidate.score {
                    best = candidate
                }
            }
        }

        return best
    }

    private func tokenize(_ text: String) -> [DictionaryToken] {
        var tokens: [DictionaryToken] = []
        var currentStart: String.Index?
        var current = ""

        func flush(until endIndex: String.Index) {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            defer {
                current = ""
                currentStart = nil
            }

            guard let start = currentStart, !trimmed.isEmpty else { return }
            let normalized = DictionaryStore.normalizeTerm(trimmed)
            guard !normalized.isEmpty else { return }

            tokens.append(
                DictionaryToken(
                    raw: trimmed,
                    normalized: normalized,
                    range: NSRange(start..<endIndex, in: text)
                )
            )
        }

        var index = text.startIndex
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let scalar = text[index].unicodeScalars.first

            if let scalar, dictionaryIsWordScalar(scalar) {
                if currentStart == nil {
                    currentStart = index
                }
                current.append(text[index])
            } else {
                flush(until: index)
            }

            index = nextIndex
        }

        flush(until: text.endIndex)
        return tokens
    }

    private func allowsFuzzyMatch(for profile: DictionaryScriptProfile) -> Bool {
        profile.isLatinLike || profile.isMixedScript
    }

    private func minimumFuzzyLength(for profile: DictionaryScriptProfile) -> Int {
        profile.isMixedScript ? 5 : 4
    }

    private func minimumFuzzyScore(for profile: DictionaryScriptProfile) -> Double {
        profile.isMixedScript ? 0.96 : 0.90
    }

    private func fuzzyThreshold(for profile: DictionaryScriptProfile, maxLength: Int) -> Int {
        if profile.isMixedScript {
            return maxLength >= 10 ? 2 : 1
        }
        return max(1, min(2, maxLength / 6))
    }

    private func levenshteinDistance(lhs: String, rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        guard !lhsChars.isEmpty else { return rhsChars.count }
        guard !rhsChars.isEmpty else { return lhsChars.count }

        var previous = Array(0...rhsChars.count)
        for (i, lhsChar) in lhsChars.enumerated() {
            var current = [i + 1]
            for (j, rhsChar) in rhsChars.enumerated() {
                let cost = lhsChar == rhsChar ? 0 : 1
                current.append(
                    min(
                        current[j] + 1,
                        previous[j + 1] + 1,
                        previous[j] + cost
                    )
                )
            }
            previous = current
        }
        return previous[rhsChars.count]
    }
}

@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry] = []

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default

    init() {
        reload()
    }

    func reload() {
        do {
            let url = try dictionaryFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                entries = []
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            entries = sortEntries(decoded)
        } catch {
            entries = []
        }
    }

    func filteredEntries(for filter: DictionaryFilter) -> [DictionaryEntry] {
        switch filter {
        case .all:
            return entries
        case .autoAdded:
            return entries.filter { $0.source == .auto }
        case .manualAdded:
            return entries.filter { $0.source == .manual }
        }
    }

    func createManualEntry(
        term: String,
        replacementTerms: [String] = [],
        groupID: UUID?,
        groupNameSnapshot: String?
    ) throws {
        try createEntry(
            term: term,
            replacementTerms: replacementTerms,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot,
            source: .manual
        )
    }

    func createAutoEntry(
        term: String,
        replacementTerms: [String] = [],
        groupID: UUID?,
        groupNameSnapshot: String?
    ) throws {
        try createEntry(
            term: term,
            replacementTerms: replacementTerms,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot,
            source: .auto
        )
    }

    private func createEntry(
        term: String,
        replacementTerms: [String],
        groupID: UUID?,
        groupNameSnapshot: String?,
        source: DictionaryEntrySource
    ) throws {
        let prepared = try prepareEntryInput(
            term: term,
            replacementTerms: replacementTerms,
            groupID: groupID
        )
        let now = Date()
        let entry = DictionaryEntry(
            term: prepared.display,
            normalizedTerm: prepared.normalized,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot,
            source: source,
            createdAt: now,
            updatedAt: now,
            replacementTerms: prepared.replacementTerms
        )
        entries.insert(entry, at: 0)
        entries = sortEntries(entries)
        persist()
    }

    func updateEntry(
        id: UUID,
        term: String,
        replacementTerms: [String] = [],
        groupID: UUID?,
        groupNameSnapshot: String?
    ) throws {
        let prepared = try prepareEntryInput(
            term: term,
            replacementTerms: replacementTerms,
            groupID: groupID,
            excluding: id
        )
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].term = prepared.display
        entries[index].normalizedTerm = prepared.normalized
        entries[index].groupID = groupID
        entries[index].groupNameSnapshot = groupNameSnapshot
        entries[index].replacementTerms = prepared.replacementTerms
        entries[index].updatedAt = Date()

        let reservedKeys = Set([prepared.normalized] + prepared.replacementTerms.map(\.normalizedText))
        entries[index].observedVariants.removeAll { reservedKeys.contains($0.normalizedText) }
        entries = sortEntries(entries)
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        entries = []
        persist()
    }

    func exportTransferJSONString() throws -> String {
        try DictionaryTransferManager.exportJSONString(entries: entries)
    }

    func importTransferJSONString(_ json: String) throws -> DictionaryImportResult {
        let payload = try DictionaryTransferManager.importPayload(from: json)
        return importTransferEntries(payload.entries)
    }

    func makeMatcherIfEnabled(activeGroupID: UUID?) -> DictionaryMatcher? {
        guard defaults.bool(forKey: AppPreferenceKey.dictionaryRecognitionEnabled) else { return nil }
        let configuration = matcherConfiguration(for: activeGroupID)
        guard !configuration.entries.isEmpty else { return nil }
        return DictionaryMatcher(
            entries: configuration.entries,
            blockedGlobalMatchKeys: configuration.blockedGlobalMatchKeys
        )
    }

    func correctionContext(for text: String, activeGroupID: UUID?) -> DictionaryCorrectionResult? {
        guard let matcher = makeMatcherIfEnabled(activeGroupID: activeGroupID) else { return nil }
        return matcher.applyCorrections(
            to: text,
            automaticReplacementEnabled: defaults.bool(forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled)
        )
    }

    func matchContext(for text: String, activeGroupID: UUID?) -> DictionaryCorrectionResult? {
        guard let matcher = makeMatcherIfEnabled(activeGroupID: activeGroupID) else { return nil }
        let candidates = matcher.recallCandidates(in: text)
        guard !candidates.isEmpty else { return nil }
        return DictionaryCorrectionResult(text: text, candidates: candidates, correctedTerms: [])
    }

    func glossaryContext(for text: String, activeGroupID: UUID?) -> DictionaryPromptContext? {
        guard let matcher = makeMatcherIfEnabled(activeGroupID: activeGroupID) else { return nil }
        let context = matcher.promptContext(for: text)
        return context.isEmpty ? nil : context
    }

    func hasEntry(normalizedTerm: String, activeGroupID: UUID?) -> Bool {
        let normalized = normalizedTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let configuration = matcherConfiguration(for: activeGroupID)
        return configuration.entries.contains { entry in
            entry.visibleMatchKeys(blockedKeys: configuration.blockedGlobalMatchKeys).contains(normalized)
        }
    }

    func activeEntriesForRemoteRequest(activeGroupID: UUID?) -> [DictionaryEntry] {
        guard defaults.bool(forKey: AppPreferenceKey.dictionaryRecognitionEnabled) else { return [] }
        return matcherConfiguration(for: activeGroupID).entries.filter { $0.status == .active }
    }

    func activeEntriesAcrossAllScopesForRemoteSync() -> [DictionaryEntry] {
        guard defaults.bool(forKey: AppPreferenceKey.dictionaryRecognitionEnabled) else { return [] }
        return entries.filter { $0.status == .active }
    }

    func recordMatches(_ candidates: [DictionaryMatchCandidate]) {
        recordCandidates(candidates)
        guard !candidates.isEmpty else { return }
        entries = sortEntries(entries)
        persist()
    }

    static func normalizeTerm(_ input: String) -> String {
        let folded = input.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        var output = ""
        var previousWasWhitespace = false

        for scalar in folded.unicodeScalars {
            if dictionaryIsWordScalar(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasWhitespace = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar)
                        || CharacterSet.punctuationCharacters.contains(scalar)
                        || CharacterSet.symbols.contains(scalar) {
                if !previousWasWhitespace && !output.isEmpty {
                    output.append(" ")
                    previousWasWhitespace = true
                }
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matcherConfiguration(for activeGroupID: UUID?) -> (entries: [DictionaryEntry], blockedGlobalMatchKeys: Set<String>) {
        let globals = entries.filter { $0.status == .active && $0.groupID == nil }
        guard let activeGroupID else {
            return (globals, [])
        }

        let scoped = entries.filter { $0.status == .active && $0.groupID == activeGroupID }
        let blockedKeys = Set(scoped.flatMap(\.matchKeys))
        return (scoped + globals, blockedKeys)
    }

    private func prepareEntryInput(
        term: String,
        replacementTerms: [String],
        groupID: UUID?,
        excluding excludedID: UUID? = nil,
        existingEntries: [DictionaryEntry]? = nil
    ) throws -> DictionaryPreparedEntryInput {
        let display = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalizeTerm(display)
        guard !display.isEmpty, !normalized.isEmpty else {
            throw DictionaryStoreError.emptyTerm
        }

        let comparisonEntries = existingEntries ?? entries

        if comparisonEntries.contains(where: {
            $0.groupID == groupID && $0.id != excludedID && $0.normalizedTerm == normalized
        }) {
            throw DictionaryStoreError.duplicateTerm
        }

        var preparedReplacementTerms: [DictionaryReplacementTerm] = []
        var seenReplacementKeys = Set<String>()

        for rawValue in replacementTerms {
            let displayValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = Self.normalizeTerm(displayValue)
            guard !displayValue.isEmpty, !normalizedValue.isEmpty else { continue }

            if normalizedValue == normalized {
                throw DictionaryStoreError.replacementMatchesDictionaryTerm
            }

            guard seenReplacementKeys.insert(normalizedValue).inserted else { continue }

            if comparisonEntries.contains(where: {
                $0.groupID == groupID
                    && $0.id != excludedID
                    && $0.matchKeys.contains(normalizedValue)
            }) {
                throw DictionaryStoreError.duplicateReplacementTerm(displayValue)
            }

            preparedReplacementTerms.append(
                DictionaryReplacementTerm(
                    text: displayValue,
                    normalizedText: normalizedValue
                )
            )
        }

        if comparisonEntries.contains(where: {
            $0.groupID == groupID
                && $0.id != excludedID
                && $0.replacementTerms.contains(where: { $0.normalizedText == normalized })
        }) {
            throw DictionaryStoreError.duplicateTerm
        }

        return DictionaryPreparedEntryInput(
            display: display,
            normalized: normalized,
            replacementTerms: preparedReplacementTerms
        )
    }

    private func importTransferEntries(_ transferEntries: [DictionaryTransferManager.Entry]) -> DictionaryImportResult {
        var mergedEntries = entries
        var addedCount = 0
        var skippedCount = 0

        for transferEntry in transferEntries {
            do {
                let prepared = try prepareEntryInput(
                    term: transferEntry.term,
                    replacementTerms: transferEntry.replacementTerms,
                    groupID: transferEntry.groupID,
                    existingEntries: mergedEntries
                )
                let now = Date()
                mergedEntries.append(
                    DictionaryEntry(
                        term: prepared.display,
                        normalizedTerm: prepared.normalized,
                        groupID: transferEntry.groupID,
                        groupNameSnapshot: transferEntry.groupNameSnapshot,
                        source: .manual,
                        createdAt: now,
                        updatedAt: now,
                        replacementTerms: prepared.replacementTerms
                    )
                )
                addedCount += 1
            } catch {
                skippedCount += 1
            }
        }

        entries = sortEntries(mergedEntries)
        persist()
        return DictionaryImportResult(addedCount: addedCount, skippedCount: skippedCount)
    }

    private func recordCandidates(_ candidates: [DictionaryMatchCandidate]) {
        guard !candidates.isEmpty else { return }
        let now = Date()
        let grouped = Dictionary(grouping: candidates, by: \.entryID)

        for (entryID, matches) in grouped {
            guard let index = entries.firstIndex(where: { $0.id == entryID }) else { continue }
            entries[index].lastMatchedAt = now
            entries[index].matchCount += matches.count
            entries[index].updatedAt = now

            for candidate in matches where candidate.shouldPersistObservedVariant {
                let normalizedReservedKeys = Set(
                    [entries[index].normalizedTerm] + entries[index].replacementTerms.map(\.normalizedText)
                )
                guard !normalizedReservedKeys.contains(candidate.normalizedMatchedText) else { continue }
                upsertVariant(
                    into: &entries[index],
                    text: candidate.matchedText,
                    normalizedText: candidate.normalizedMatchedText,
                    confidence: confidence(for: candidate)
                )
            }
        }
    }

    private func upsertVariant(
        into entry: inout DictionaryEntry,
        text: String,
        normalizedText: String,
        confidence: DictionaryVariantConfidence
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let variantIndex = entry.observedVariants.firstIndex(where: { $0.normalizedText == normalizedText }) {
            entry.observedVariants[variantIndex].count += 1
            entry.observedVariants[variantIndex].lastSeenAt = Date()
            entry.observedVariants[variantIndex].confidence = higherConfidence(
                lhs: entry.observedVariants[variantIndex].confidence,
                rhs: confidence
            )
        } else {
            entry.observedVariants.append(
                ObservedVariant(
                    text: text,
                    normalizedText: normalizedText,
                    confidence: confidence
                )
            )
            entry.observedVariants.sort { $0.count > $1.count }
        }
    }

    private func confidence(for candidate: DictionaryMatchCandidate) -> DictionaryVariantConfidence {
        if candidate.score >= 0.985 {
            return .high
        }
        if candidate.score >= 0.92 {
            return .medium
        }
        return .low
    }

    private func higherConfidence(lhs: DictionaryVariantConfidence, rhs: DictionaryVariantConfidence) -> DictionaryVariantConfidence {
        let rank: [DictionaryVariantConfidence: Int] = [
            .low: 0,
            .medium: 1,
            .high: 2
        ]
        return (rank[lhs] ?? 0) >= (rank[rhs] ?? 0) ? lhs : rhs
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            let url = try dictionaryFileURL()
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }

    private func dictionaryFileURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary.json")
    }

    private func sortEntries(_ values: [DictionaryEntry]) -> [DictionaryEntry] {
        values.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
}

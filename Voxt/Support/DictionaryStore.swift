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

    nonisolated var id: String {
        let location = matchRange?.location ?? -1
        let length = matchRange?.length ?? 0
        return "\(entryID.uuidString)|\(normalizedMatchedText)|\(reason.rawValue)|\(source.rawValue)|\(location)|\(length)"
    }

    nonisolated var allowsAutomaticReplacement: Bool {
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

    nonisolated var shouldPersistObservedVariant: Bool {
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

private struct DictionaryPreparedEntryInput {
    let display: String
    let normalized: String
    let replacementTerms: [DictionaryReplacementTerm]
}
@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry] = []

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private var reloadGeneration = 0
    private let persistenceCoordinator = AsyncJSONPersistenceCoordinator(
        label: "com.voxt.dictionary.persistence"
    )

    init() {
        reload()
    }

    func reload() {
        do {
            let url = try dictionaryFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                applyReloadedEntries([])
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            applyReloadedEntries(decoded)
        } catch {
            applyReloadedEntries([])
        }
    }

    func reloadAsync() {
        reloadGeneration += 1
        let generation = reloadGeneration

        let url: URL?
        do {
            url = try dictionaryFileURL()
        } catch {
            applyReloadedEntries([])
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self, url] in
            let decodedEntries: [DictionaryEntry]
            if let url, FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    decodedEntries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
                } catch {
                    decodedEntries = []
                }
            } else {
                decodedEntries = []
            }

            DispatchQueue.main.async {
                guard let self, generation == self.reloadGeneration else { return }
                self.applyReloadedEntries(decodedEntries)
            }
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

    nonisolated static func normalizeTerm(_ input: String) -> String {
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
            let url = try dictionaryFileURL()
            persistenceCoordinator.scheduleWrite(entries, to: url)
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

    private func applyReloadedEntries(_ decodedEntries: [DictionaryEntry]) {
        entries = sortEntries(decodedEntries)
    }
}

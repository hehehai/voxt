// DictionarySuggestionStore.swift
// Owns explicit history-scan progress/settings and legacy suggestion-file compatibility.

import Foundation
import Combine

@MainActor
final class DictionarySuggestionStore: ObservableObject {
    @Published private(set) var suggestions: [DictionarySuggestion] = []
    @Published private(set) var historyScanProgress = DictionaryHistoryScanProgress()
    @Published private(set) var filterSettings = DictionarySuggestionFilterSettings.defaultValue

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let legacySuggestionsURL: URL?
    private var reloadGeneration = 0
    private let evidenceLimit = 3

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        legacySuggestionsURL: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.legacySuggestionsURL = legacySuggestionsURL
        reload()
    }

    func reload() {
        filterSettings = loadFilterSettings()
        do {
            let url = try suggestionsFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                applyReloadedSuggestions([])
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([DictionarySuggestion].self, from: data)
            applyReloadedSuggestions(decoded)
        } catch {
            applyReloadedSuggestions([])
        }
    }

    func reloadAsync() {
        reloadGeneration += 1
        let generation = reloadGeneration
        filterSettings = loadFilterSettings()

        let url: URL?
        do {
            url = try suggestionsFileURL()
        } catch {
            applyReloadedSuggestions([])
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self, url] in
            let decodedSuggestions: [DictionarySuggestion]
            if let url, FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    decodedSuggestions = try JSONDecoder().decode([DictionarySuggestion].self, from: data)
                } catch {
                    decodedSuggestions = []
                }
            } else {
                decodedSuggestions = []
            }

            DispatchQueue.main.async {
                guard let self, generation == self.reloadGeneration else { return }
                self.applyReloadedSuggestions(decodedSuggestions)
            }
        }
    }

    func saveFilterSettings(_ settings: DictionarySuggestionFilterSettings) {
        let sanitized = settings.sanitized()
        filterSettings = sanitized
        let persisted = DictionarySuggestionFilterSettings(
            prompt: DictionarySuggestionFilterSettings.canonicalStoredPrompt(sanitized.prompt),
            batchSize: sanitized.batchSize,
            maxCandidatesPerBatch: sanitized.maxCandidatesPerBatch
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        defaults.set(data, forKey: AppPreferenceKey.dictionarySuggestionFilterSettings)
    }

    var historyScanCheckpoint: DictionaryHistoryScanCheckpoint? {
        guard let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint),
              let checkpoint = try? JSONDecoder().decode(DictionaryHistoryScanCheckpoint.self, from: data)
        else {
            return nil
        }
        return checkpoint
    }

    func pendingHistoryEntries(in historyStore: TranscriptionHistoryStore) -> [TranscriptionHistoryEntry] {
        historyStore.pendingDictionaryHistoryEntries(after: historyScanCheckpoint)
    }

    func beginHistoryScan(totalCount: Int) {
        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: true,
            isCancellationRequested: false,
            processedCount: 0,
            totalCount: totalCount,
            newSuggestionCount: 0,
            duplicateCount: 0,
            lastProcessedCount: historyScanProgress.lastProcessedCount,
            lastNewSuggestionCount: historyScanProgress.lastNewSuggestionCount,
            lastDuplicateCount: historyScanProgress.lastDuplicateCount,
            lastRunAt: historyScanProgress.lastRunAt,
            errorMessage: nil
        )
    }

    func updateHistoryScan(processedCount: Int, newSuggestionCount: Int, duplicateCount: Int) {
        historyScanProgress.processedCount = processedCount
        historyScanProgress.newSuggestionCount = newSuggestionCount
        historyScanProgress.duplicateCount = duplicateCount
    }

    func requestHistoryScanCancellation() {
        guard historyScanProgress.isRunning else { return }
        historyScanProgress.isCancellationRequested = true
    }

    func finishHistoryScan(
        processedCount: Int,
        newSuggestionCount: Int,
        duplicateCount: Int,
        checkpointEntry: TranscriptionHistoryEntry?
    ) {
        if let checkpointEntry {
            persistHistoryScanCheckpoint(
                DictionaryHistoryScanCheckpoint(
                    lastProcessedAt: checkpointEntry.createdAt,
                    lastHistoryEntryID: checkpointEntry.id
                )
            )
        }

        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: false,
            isCancellationRequested: false,
            processedCount: processedCount,
            totalCount: processedCount,
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            lastProcessedCount: processedCount,
            lastNewSuggestionCount: newSuggestionCount,
            lastDuplicateCount: duplicateCount,
            lastRunAt: Date(),
            errorMessage: nil
        )
    }

    func advanceHistoryScanCheckpoint(to entry: TranscriptionHistoryEntry) {
        persistHistoryScanCheckpoint(
            DictionaryHistoryScanCheckpoint(
                lastProcessedAt: entry.createdAt,
                lastHistoryEntryID: entry.id
            )
        )
    }

    func failHistoryScan(
        processedCount: Int,
        totalCount: Int,
        newSuggestionCount: Int,
        duplicateCount: Int,
        errorMessage: String
    ) {
        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: false,
            isCancellationRequested: false,
            processedCount: processedCount,
            totalCount: totalCount,
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            lastProcessedCount: historyScanProgress.lastProcessedCount,
            lastNewSuggestionCount: historyScanProgress.lastNewSuggestionCount,
            lastDuplicateCount: historyScanProgress.lastDuplicateCount,
            lastRunAt: historyScanProgress.lastRunAt,
            errorMessage: errorMessage
        )
    }

    func cancelHistoryScan(
        processedCount: Int,
        totalCount: Int,
        newSuggestionCount: Int,
        duplicateCount: Int,
        message: String
    ) {
        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: false,
            isCancellationRequested: false,
            processedCount: processedCount,
            totalCount: totalCount,
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            lastProcessedCount: processedCount,
            lastNewSuggestionCount: newSuggestionCount,
            lastDuplicateCount: duplicateCount,
            lastRunAt: Date(),
            errorMessage: message
        )
    }

    func applyHistoryScanCandidates(
        _ candidates: [DictionaryHistoryScanCandidate],
        dictionaryStore: DictionaryStore
    ) -> DictionaryHistoryScanApplyResult {
        guard !candidates.isEmpty else {
            return DictionaryHistoryScanApplyResult(
                newSuggestionCount: 0,
                duplicateCount: 0
            )
        }

        var newSuggestionCount = 0
        var duplicateCount = 0

        for candidate in candidates {
            let normalized = DictionaryStore.normalizeTerm(candidate.term)
            guard !normalized.isEmpty else { continue }
            guard !dictionaryStore.hasEntry(normalizedTerm: normalized, activeGroupID: candidate.groupID) else {
                duplicateCount += 1
                continue
            }

            do {
                let category = dictionaryStore.ensureCategory(
                    id: candidate.groupID,
                    name: candidate.groupNameSnapshot
                )
                try dictionaryStore.createAutoEntry(
                    term: candidate.term,
                    categoryID: category.id,
                    categoryNameSnapshot: category.name,
                    groupID: candidate.groupID,
                    groupNameSnapshot: candidate.groupNameSnapshot
                )
                newSuggestionCount += 1
            } catch {
                if dictionaryStore.hasEntry(normalizedTerm: normalized, activeGroupID: candidate.groupID) {
                    duplicateCount += 1
                }
            }
        }

        return DictionaryHistoryScanApplyResult(
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount
        )
    }

    private func loadFilterSettings() -> DictionarySuggestionFilterSettings {
        guard
            let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionFilterSettings),
            let decoded = try? JSONDecoder().decode(DictionarySuggestionFilterSettings.self, from: data)
        else {
            return .defaultValue
        }
        return decoded.sanitized()
    }

    private func deduplicatedSuggestions(_ items: [DictionarySuggestion]) -> [DictionarySuggestion] {
        var mergedByKey: [String: DictionarySuggestion] = [:]
        var keyOrder: [String] = []

        for item in items {
            let key = suggestionKey(normalizedTerm: item.normalizedTerm, groupID: item.groupID)
            if var existing = mergedByKey[key] {
                existing = mergeSuggestion(existing, with: item)
                mergedByKey[key] = existing
            } else {
                mergedByKey[key] = item
                keyOrder.append(key)
            }
        }

        return keyOrder
            .compactMap { mergedByKey[$0] }
            .sorted {
                if $0.lastSeenAt == $1.lastSeenAt {
                    return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
                }
                return $0.lastSeenAt > $1.lastSeenAt
            }
    }

    private func mergeSuggestion(_ lhs: DictionarySuggestion, with rhs: DictionarySuggestion) -> DictionarySuggestion {
        let newer = rhs.lastSeenAt >= lhs.lastSeenAt ? rhs : lhs
        let older = rhs.lastSeenAt >= lhs.lastSeenAt ? lhs : rhs

        var merged = older
        merged.term = newer.term
        merged.normalizedTerm = newer.normalizedTerm
        merged.sourceContext = newer.sourceContext
        merged.status = mergedStatus(lhs.status, rhs.status)
        merged.firstSeenAt = min(lhs.firstSeenAt, rhs.firstSeenAt)
        merged.lastSeenAt = max(lhs.lastSeenAt, rhs.lastSeenAt)
        merged.seenCount = max(lhs.seenCount, 0) + max(rhs.seenCount, 0)
        merged.lastHistoryEntryID = newer.lastHistoryEntryID ?? older.lastHistoryEntryID
        merged.groupID = newer.groupID ?? older.groupID
        merged.groupNameSnapshot = newer.groupNameSnapshot ?? older.groupNameSnapshot
        merged.evidenceSamples = mergedEvidenceSamples(primary: newer.evidenceSamples, secondary: older.evidenceSamples)
        return merged
    }

    private func mergedStatus(
        _ lhs: DictionarySuggestionStatus,
        _ rhs: DictionarySuggestionStatus
    ) -> DictionarySuggestionStatus {
        func rank(for status: DictionarySuggestionStatus) -> Int {
            switch status {
            case .pending:
                return 0
            case .dismissed:
                return 1
            case .added:
                return 2
            }
        }

        return rank(for: rhs) >= rank(for: lhs) ? rhs : lhs
    }

    private func mergedEvidenceSamples(primary: [String], secondary: [String]) -> [String] {
        var merged: [String] = []
        for sample in primary + secondary {
            let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !merged.contains(trimmed) else { continue }
            merged.append(trimmed)
            if merged.count >= evidenceLimit {
                break
            }
        }
        return merged
    }

    private func suggestionKey(normalizedTerm: String, groupID: UUID?) -> String {
        "\(normalizedTerm)|\(groupID?.uuidString ?? "global")"
    }

    private func applyReloadedSuggestions(_ decodedSuggestions: [DictionarySuggestion]) {
        let deduplicated = deduplicatedSuggestions(decodedSuggestions)
        suggestions = deduplicated
        if decodedSuggestions != deduplicated {
            persist()
        }
    }

    private func persist() {
        do {
            let normalizedSuggestions = deduplicatedSuggestions(suggestions)
            suggestions = normalizedSuggestions
            let data = try JSONEncoder().encode(normalizedSuggestions)
            let url = try suggestionsFileURL()
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }

    private func suggestionsFileURL() throws -> URL {
        if let legacySuggestionsURL { return legacySuggestionsURL }
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary-suggestions.json")
    }

    private func persistHistoryScanCheckpoint(_ checkpoint: DictionaryHistoryScanCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        defaults.set(data, forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
    }
}

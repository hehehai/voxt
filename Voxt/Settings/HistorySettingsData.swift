import Foundation

enum HistoryContentEmptyState: Equatable {
    case none
    case noNotes
    case noHistory
    case noEntriesInCategory

    var localizedKey: String? {
        switch self {
        case .none:
            return nil
        case .noNotes:
            return "No notes yet."
        case .noHistory:
            return "No history yet."
        case .noEntriesInCategory:
            return "No entries in this category yet."
        }
    }
}

enum HistorySettingsData {
    static func filteredEntries(
        for filter: HistoryFilterTab,
        allEntries: [TranscriptionHistoryEntry]
    ) -> [TranscriptionHistoryEntry] {
        switch filter {
        case .transcription:
            return allEntries.filter { $0.kind == .normal }
        case .translation:
            return allEntries.filter { $0.kind == .translation }
        case .rewrite:
            return allEntries.filter { $0.kind == .rewrite }
        case .meeting:
            return allEntries.filter { $0.kind == .meeting }
        case .note:
            return []
        }
    }

    static func visibleEntries<T>(
        from items: [T],
        visibleLimit: Int
    ) -> [T] {
        Array(items.prefix(max(0, visibleLimit)))
    }

    static func hasMoreItems<T>(
        in items: [T],
        visibleLimit: Int
    ) -> Bool {
        visibleLimit < items.count
    }

    static func nextVisibleLimit(
        currentLimit: Int,
        pageSize: Int,
        totalCount: Int
    ) -> Int {
        min(currentLimit + pageSize, totalCount)
    }

    static func normalizedVisibleLimit(
        currentLimit: Int,
        pageSize: Int,
        totalCount: Int
    ) -> Int {
        min(max(currentLimit, pageSize), max(totalCount, pageSize))
    }

    static func emptyState(
        selectedFilter: HistoryFilterTab,
        allEntries: [TranscriptionHistoryEntry],
        filteredEntries: [TranscriptionHistoryEntry],
        notes: [VoxtNoteItem]
    ) -> HistoryContentEmptyState {
        if selectedFilter == .note {
            return notes.isEmpty ? .noNotes : .none
        }
        if allEntries.isEmpty {
            return .noHistory
        }
        return filteredEntries.isEmpty ? .noEntriesInCategory : .none
    }
}

import SwiftUI

struct HistorySettingsView: View {
    private static let pageSize = 40

    @AppStorage(AppPreferenceKey.historyCleanupEnabled) private var historyCleanupEnabled = true
    @AppStorage(AppPreferenceKey.historyRetentionPeriod) private var historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var noteStore: VoxtNoteStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    let navigationRequest: SettingsNavigationRequest?
    @State private var copiedEntryID: UUID?
    @State private var copiedNoteID: UUID?
    @State private var selectedFilter: HistoryFilterTab = .transcription
    @State private var visibleItemLimit = pageSize

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        HistoryRetentionPeriod(rawValue: historyRetentionPeriodRaw) ?? .ninetyDays
    }

    private var allEntries: [TranscriptionHistoryEntry] {
        historyStore.allHistoryEntries
    }

    private var filteredEntries: [TranscriptionHistoryEntry] {
        allEntries.filter { selectedFilter.matches($0) }
    }

    private var allNotes: [VoxtNoteItem] {
        noteStore.items
    }

    private var visibleNotes: [VoxtNoteItem] {
        Array(allNotes.prefix(visibleItemLimit))
    }

    private var visibleEntries: [TranscriptionHistoryEntry] {
        Array(filteredEntries.prefix(visibleItemLimit))
    }

    private var hasMoreFilteredEntries: Bool {
        visibleItemLimit < filteredEntries.count
    }

    private var hasMoreVisibleNotes: Bool {
        visibleItemLimit < allNotes.count
    }

    private var isNoteTabSelected: Bool {
        selectedFilter == .note
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                Toggle(String(localized: "History Cleanup"), isOn: $historyCleanupEnabled)
                                Spacer(minLength: 12)
                                if historyCleanupEnabled {
                                    Text(String(localized: "Retention"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    SettingsMenuPicker(
                                        selection: $historyRetentionPeriodRaw,
                                        options: HistoryRetentionPeriod.allCases.map { option in
                                            SettingsMenuOption(value: option.rawValue, title: option.title)
                                        },
                                        selectedTitle: historyRetentionPeriod.title,
                                        width: 160
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .settingsNavigationAnchor(.historySettings)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                HistoryFilterTabPicker(selectedTab: $selectedFilter)
                                Spacer(minLength: 12)
                                Button(String(localized: "Clean All"), role: .destructive) {
                                    copiedEntryID = nil
                                    copiedNoteID = nil
                                    resetVisibleItemLimit()
                                    if isNoteTabSelected {
                                        noteStore.clearAll()
                                    } else {
                                        historyStore.clearAll()
                                    }
                                }
                                .buttonStyle(SettingsPillButtonStyle())
                                .disabled(isNoteTabSelected ? allNotes.isEmpty : allEntries.isEmpty)
                            }

                            if isNoteTabSelected && allNotes.isEmpty {
                                Text(String(localized: "No notes yet."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !isNoteTabSelected && allEntries.isEmpty {
                                Text(String(localized: "No history yet."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !isNoteTabSelected && filteredEntries.isEmpty {
                                Text(String(localized: "No entries in this category yet."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if isNoteTabSelected {
                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(visibleNotes) { item in
                                            NoteHistoryRow(
                                                item: item,
                                                isCopied: copiedNoteID == item.id,
                                                onCopy: {
                                                    copyStringToPasteboard(item.text)
                                                    copiedNoteID = item.id
                                                    Task {
                                                        try? await Task.sleep(for: .seconds(1.2))
                                                        if copiedNoteID == item.id {
                                                            copiedNoteID = nil
                                                        }
                                                    }
                                                },
                                                onToggleCompletion: {
                                                    _ = noteStore.updateCompletion(!item.isCompleted, for: item.id)
                                                },
                                                onDelete: {
                                                    copiedNoteID = nil
                                                    noteStore.delete(id: item.id)
                                                }
                                            )
                                            .onAppear {
                                                if item.id == visibleNotes.last?.id {
                                                    loadNextPageIfNeeded()
                                                }
                                            }
                                        }

                                        if hasMoreVisibleNotes {
                                            Button(String(localized: "Load More")) {
                                                loadNextPageIfNeeded()
                                            }
                                            .buttonStyle(SettingsPillButtonStyle())
                                            .padding(.top, 4)
                                        }
                                    }
                                }
                                .frame(maxHeight: .infinity, alignment: .top)
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(visibleEntries) { entry in
                                            HistoryRow(
                                                entry: entry,
                                                meetingAudioURL: historyStore.meetingAudioURL(for: entry),
                                                isCopied: copiedEntryID == entry.id,
                                                onCopy: {
                                                    copyStringToPasteboard(entry.text)
                                                    copiedEntryID = entry.id
                                                    Task {
                                                        try? await Task.sleep(for: .seconds(1.2))
                                                        if copiedEntryID == entry.id {
                                                            copiedEntryID = nil
                                                        }
                                                    }
                                                },
                                                onDelete: {
                                                    copiedEntryID = nil
                                                    historyStore.delete(id: entry.id)
                                                }
                                            )
                                            .onAppear {
                                                if entry.id == visibleEntries.last?.id {
                                                    loadNextPageIfNeeded()
                                                }
                                            }
                                        }

                                        if hasMoreFilteredEntries {
                                            Button(String(localized: "Load More")) {
                                                loadNextPageIfNeeded()
                                            }
                                            .buttonStyle(SettingsPillButtonStyle())
                                            .padding(.top, 4)
                                        }
                                    }
                                }
                                .frame(maxHeight: .infinity, alignment: .top)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .settingsNavigationAnchor(.historyEntries)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .onAppear {
                scrollToNavigationTargetIfNeeded(using: proxy)
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                scrollToNavigationTargetIfNeeded(using: proxy)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            if !HistoryRetentionPeriod.allCases.contains(where: { $0.rawValue == historyRetentionPeriodRaw }) {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
            }
            resetVisibleItemLimit()
            historyStore.reloadAsync()
        }
        .onChange(of: historyCleanupEnabled) { _, _ in
            resetVisibleItemLimit()
            historyStore.reloadAsync()
        }
        .onChange(of: historyRetentionPeriodRaw) { _, newValue in
            if !HistoryRetentionPeriod.allCases.contains(where: { $0.rawValue == newValue }) {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
            }
            resetVisibleItemLimit()
            historyStore.reloadAsync()
        }
        .onChange(of: selectedFilter) { _, _ in
            resetVisibleItemLimit()
        }
        .onReceive(historyStore.$entries) { _ in
            visibleItemLimit = min(max(visibleItemLimit, Self.pageSize), max(filteredEntries.count, Self.pageSize))
        }
        .onReceive(noteStore.$items) { _ in
            visibleItemLimit = min(max(visibleItemLimit, Self.pageSize), max(allNotes.count, Self.pageSize))
        }
    }

    private func scrollToNavigationTargetIfNeeded(using proxy: ScrollViewProxy) {
        guard let navigationRequest,
              navigationRequest.target.tab == .history,
              let section = navigationRequest.target.section
        else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(section.rawValue, anchor: .top)
            }
        }
    }

    private func resetVisibleItemLimit() {
        visibleItemLimit = Self.pageSize
    }

    private func loadNextPageIfNeeded() {
        if isNoteTabSelected {
            guard hasMoreVisibleNotes else { return }
            visibleItemLimit = min(visibleItemLimit + Self.pageSize, allNotes.count)
            return
        }

        guard hasMoreFilteredEntries else { return }
        visibleItemLimit = min(visibleItemLimit + Self.pageSize, filteredEntries.count)
    }
}

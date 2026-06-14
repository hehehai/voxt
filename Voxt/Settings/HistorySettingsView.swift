import SwiftUI
import AppKit

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

private enum HistoryBulkDeletionTarget: Identifiable {
    case history
    case notes

    var id: String {
        switch self {
        case .history:
            return "history"
        case .notes:
            return "notes"
        }
    }
}

private enum HistoryListItem: Identifiable {
    case dayHeader(Date)
    case entry(TranscriptionHistoryEntry)

    var id: String {
        switch self {
        case .dayHeader(let date):
            return "day-\(date.timeIntervalSince1970)"
        case .entry(let entry):
            return "entry-\(entry.id.uuidString)"
        }
    }
}

private enum HistoryNoteListItem: Identifiable {
    case dayHeader(Date)
    case note(VoxtNoteItem)

    var id: String {
        switch self {
        case .dayHeader(let date):
            return "note-day-\(date.timeIntervalSince1970)"
        case .note(let note):
            return "note-\(note.id.uuidString)"
        }
    }
}

struct HistorySettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(AppPreferenceKey.historyCleanupEnabled) private var historyCleanupEnabled = true
    @AppStorage(AppPreferenceKey.historyRetentionPeriod) private var historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
    @AppStorage(AppPreferenceKey.historyAudioStorageEnabled) private var historyAudioStorageEnabled = false

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var noteStore: VoxtNoteStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    let navigationRequest: SettingsNavigationRequest?
    @State private var copyToastMessage = ""
    @State private var copyToastDismissTask: Task<Void, Never>?
    @State private var copiedEntryID: UUID?
    @State private var copiedNoteID: UUID?
    @State private var selectedFilter: HistoryFilterTab = .transcription
    @State private var isHistoryAudioSettingsPresented = false
    @State private var historyAudioStorageDisplayPath = ""
    @State private var historyAudioStorageSelectionError: String?
    @State private var historyAudioExportResultMessage: String?
    @State private var historyAudioStorageStats = HistoryAudioStorageStats(storedFileCount: 0, totalBytes: 0)
    @State private var pendingBulkDeletionTarget: HistoryBulkDeletionTarget?
    @State private var selectedHistoryInfoEntry: TranscriptionHistoryEntry?
    @State private var historySearchText = ""
    @State private var showHistorySearchDialog = false
    @State private var visibleHistoryEntries: [TranscriptionHistoryEntry] = []
    @State private var totalHistoryEntryCount = 0
    @State private var isLoadingHistoryEntries = false
    @State private var historyPageGeneration = 0
    @State private var historyAudioStatsGeneration = 0
    @State private var suppressedStoreHistoryReloadCount = 0

    private let historyPageSize = 80
    private let historyRowHeight: CGFloat = 74
    private let historyRowSpacing: CGFloat = 2
    private let historyRowVerticalInset: CGFloat = 4

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        HistoryRetentionPeriod(rawValue: historyRetentionPeriodRaw) ?? .ninetyDays
    }

    private var allNotes: [VoxtNoteItem] {
        HistorySettingsData.searchNotes(noteStore.items, query: historySearchText)
    }

    private var visibleNotes: [VoxtNoteItem] {
        allNotes
    }

    private var noteListItems: [HistoryNoteListItem] {
        var items: [HistoryNoteListItem] = []
        var currentDay: Date?
        let calendar = Calendar.current

        for note in visibleNotes {
            let day = calendar.startOfDay(for: note.createdAt)
            if currentDay != day {
                items.append(.dayHeader(day))
                currentDay = day
            }
            items.append(.note(note))
        }

        return items
    }

    private var visibleEntries: [TranscriptionHistoryEntry] {
        visibleHistoryEntries
    }

    private var historyListItems: [HistoryListItem] {
        var items: [HistoryListItem] = []
        var currentDay: Date?
        let calendar = Calendar.current

        for entry in visibleEntries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if currentDay != day {
                items.append(.dayHeader(day))
                currentDay = day
            }
            items.append(.entry(entry))
        }

        return items
    }

    private var historyListTotalCount: Int {
        historyListItems.count + max(0, totalHistoryEntryCount - visibleEntries.count)
    }

    private var isNoteTabSelected: Bool {
        selectedFilter == .note
    }

    private var isSearchActive: Bool {
        !historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyState: HistoryContentEmptyState {
        if selectedFilter == .note {
            return allNotes.isEmpty ? .noNotes : .none
        }
        return totalHistoryEntryCount == 0 ? .noEntriesInCategory : .none
    }

    private var emptyStateTitle: String {
        if isSearchActive {
            return localized("No matching results")
        }

        switch selectedFilter {
        case .transcription:
            return localized("No transcription history yet")
        case .translation:
            return localized("No translation history yet")
        case .transcript:
            return localized("No meeting transcripts yet")
        case .rewrite:
            return localized("No rewrite history yet")
        case .note:
            return localized("No notes yet")
        }
    }

    private var emptyStateMessage: String {
        if isSearchActive {
            return localized("Try another keyword or clear the search filter.")
        }

        let distinguishSides = HotkeyPreference.loadDistinguishModifierSides()
        switch selectedFilter {
        case .transcription:
            return AppLocalization.format(
                "Press %@ to start dictation. Completed results will appear here.",
                HotkeyPreference.displayString(for: HotkeyPreference.load(), distinguishModifierSides: distinguishSides)
            )
        case .translation:
            return AppLocalization.format(
                "Press %@ to try voice translation. Completed results will appear here.",
                HotkeyPreference.displayString(for: HotkeyPreference.loadTranslation(), distinguishModifierSides: distinguishSides)
            )
        case .transcript:
            return AppLocalization.format(
                "Press %@ to start Meeting Mode. Saved transcripts will appear here.",
                HotkeyPreference.displayString(for: HotkeyPreference.loadMeeting(), distinguishModifierSides: distinguishSides)
            )
        case .rewrite:
            return AppLocalization.format(
                "Press %@ to rewrite selected text or spoken instructions.",
                HotkeyPreference.displayString(for: HotkeyPreference.loadRewrite(), distinguishModifierSides: distinguishSides)
            )
        case .note:
            return localized("Capture key points during recording, then review notes here.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        HistoryFilterTabPicker(selectedTab: $selectedFilter)
                        Spacer(minLength: 12)
                        Button {
                            showHistorySearchDialog = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(SettingsCompactIconButtonStyle())
                        .help(localized("Search History"))
                        Button {
                            pendingBulkDeletionTarget = isNoteTabSelected ? .notes : .history
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(SettingsCompactIconButtonStyle(tone: .destructive))
                        .help(localized("Delete All"))
                        .disabled(isNoteTabSelected ? allNotes.isEmpty : totalHistoryEntryCount == 0)
                        Button {
                            historyAudioStorageSelectionError = nil
                            historyAudioExportResultMessage = nil
                            isHistoryAudioSettingsPresented = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(SettingsCompactIconButtonStyle())
                    }

                    if isSearchActive {
                        HStack(spacing: 8) {
                            Text(AppLocalization.format("Filtered by \"%@\"", historySearchText))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button(localized("Clear")) {
                                historySearchText = ""
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if emptyState != .none {
                        SettingsEmptyStateView(
                            illustration: .history,
                            title: emptyStateTitle,
                            message: emptyStateMessage
                        )
                    } else if isNoteTabSelected {
                        notesList
                    } else {
                        historyList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.vertical, 8)
            }
            .settingsNavigationAnchor(.historySettings)
            .settingsNavigationAnchor(.historyEntries)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if !copyToastMessage.isEmpty {
                ModelDebugToast(message: copyToastMessage) {
                    dismissCopyToast()
                }
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: copyToastMessage)
        .sheet(isPresented: $isHistoryAudioSettingsPresented) {
            HistoryAudioSettingsSheet(
                historyCleanupEnabled: $historyCleanupEnabled,
                historyRetentionPeriodRaw: $historyRetentionPeriodRaw,
                historyAudioStorageEnabled: $historyAudioStorageEnabled,
                historyAudioStorageDisplayPath: $historyAudioStorageDisplayPath,
                historyAudioStorageSelectionError: $historyAudioStorageSelectionError,
                historyAudioExportResultMessage: $historyAudioExportResultMessage,
                isPresented: $isHistoryAudioSettingsPresented,
                historyRetentionPeriod: historyRetentionPeriod,
                historyAudioStorageStatsSummary: historyAudioStorageStatsSummary,
                onOpenHistoryAudioStorageInFinder: openHistoryAudioStorageInFinder,
                onChooseHistoryAudioStorageDirectory: chooseHistoryAudioStorageDirectory,
                onExportAllHistoryAudio: exportAllHistoryAudio
            )
        }
        .sheet(item: $selectedHistoryInfoEntry) { entry in
            HistoryDetailSheetContent(
                entry: entry,
                audioURL: historyStore.audioURL(for: entry),
                locale: locale
            )
            .frame(minWidth: 520, idealWidth: 620, minHeight: 480, idealHeight: 640)
        }
        .sheet(isPresented: $showHistorySearchDialog) {
            SettingsSearchDialog(
                title: localized("Search History"),
                placeholder: localized("Search text, title, app, or dictionary terms"),
                query: $historySearchText,
                isPresented: $showHistorySearchDialog
            )
        }
        .alert(item: $pendingBulkDeletionTarget) { target in
            Alert(
                title: Text(bulkDeletionTitle(for: target)),
                message: Text(bulkDeletionMessage(for: target)),
                primaryButton: .destructive(Text(localized("Delete"))) {
                    confirmBulkDeletion(target)
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            if !HistoryRetentionPeriod.allCases.contains(where: { $0.rawValue == historyRetentionPeriodRaw }) {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
            }
            refreshHistoryAudioStorageDisplayPath()
            refreshHistoryAudioStorageStats()
            reloadHistoryEntries(reset: true)
        }
        .onChange(of: selectedFilter) { _, _ in
            reloadHistoryEntries(reset: true)
        }
        .onChange(of: historySearchText) { _, _ in
            reloadHistoryEntries(reset: true)
        }
        .onChange(of: historyCleanupEnabled) { _, _ in
            applyRetentionPolicyAndReload()
        }
        .onChange(of: historyRetentionPeriodRaw) { _, newValue in
            if !HistoryRetentionPeriod.allCases.contains(where: { $0.rawValue == newValue }) {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
            }
            applyRetentionPolicyAndReload()
        }
        .onReceive(historyStore.$entries) { _ in
            if suppressedStoreHistoryReloadCount > 0 {
                suppressedStoreHistoryReloadCount -= 1
                return
            }
            refreshHistoryAudioStorageStats()
            reloadHistoryEntries(reset: true)
        }
        .onDisappear {
            dismissCopyToast()
        }
    }

    private var notesList: some View {
        let items = noteListItems
        return PagedVerticalList(
            items: items,
            totalCount: items.count,
            rowHeight: historyRowHeight,
            rowSpacing: historyRowSpacing,
            rowHeightForItem: noteRowHeight(for:),
            isLoading: false,
            onLoadMore: {}
        ) { item in
            switch item {
            case .dayHeader(let date):
                HistoryDayHeader(date: date)
            case .note(let note):
                NoteHistoryRow(
                    item: note,
                    onCopy: {
                        copyStringToPasteboard(note.text)
                        copiedNoteID = note.id
                        showCopyToast()
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            if copiedNoteID == note.id {
                                copiedNoteID = nil
                            }
                        }
                    },
                    onToggleCompletion: {
                        _ = noteStore.updateCompletion(!note.isCompleted, for: note.id)
                    },
                    onDelete: {
                        copiedNoteID = nil
                        noteStore.delete(id: note.id)
                    }
                )
                .padding(.vertical, historyRowVerticalInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var historyList: some View {
        let items = historyListItems
        let list = PagedVerticalList(
            items: items,
            totalCount: historyListTotalCount,
            rowHeight: historyRowHeight,
            rowSpacing: historyRowSpacing,
            rowHeightForItem: historyRowHeight(for:),
            isLoading: isLoadingHistoryEntries,
            onLoadMore: { reloadHistoryEntries(reset: false) }
        ) { item in
            switch item {
            case .dayHeader(let date):
                HistoryDayHeader(date: date)
            case .entry(let entry):
                HistoryRow(
                    entry: entry,
                    audioURL: historyStore.audioURL(for: entry),
                    isCompact: false,
                    onCopy: {
                        copyStringToPasteboard(
                            HistoryCorrectionPresentation.correctedText(
                                for: entry.text,
                                snapshots: entry.dictionaryCorrectionSnapshots
                            )
                        )
                        copiedEntryID = entry.id
                        showCopyToast()
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            if copiedEntryID == entry.id {
                                copiedEntryID = nil
                            }
                        }
                    },
                    onShowInfo: {
                        showHistoryDetail(for: entry)
                    },
                    onDelete: { deleteHistoryEntry(entry) }
                )
                .padding(.vertical, historyRowVerticalInset)
            }
        }

        list.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func historyRowHeight(for item: HistoryListItem) -> CGFloat {
        switch item {
        case .dayHeader:
            return 32
        case .entry:
            return historyRowHeight
        }
    }

    private func noteRowHeight(for item: HistoryNoteListItem) -> CGFloat {
        switch item {
        case .dayHeader:
            return 32
        case .note:
            return historyRowHeight
        }
    }

    private var historySearchListHeight: CGFloat {
        let visibleRowCount = max(1, min(visibleEntries.count, 5))
        let rowsHeight = CGFloat(visibleRowCount) * historyRowHeight
            + CGFloat(max(0, visibleRowCount - 1)) * historyRowSpacing
        let footerHeight: CGFloat = (isLoadingHistoryEntries || visibleEntries.count < totalHistoryEntryCount) ? 40 : 0
        return min(max(rowsHeight + footerHeight, historyRowHeight), 360)
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

    private func confirmBulkDeletion(_ target: HistoryBulkDeletionTarget) {
        copiedEntryID = nil
        copiedNoteID = nil
        dismissCopyToast()
        switch target {
        case .history:
            historyStore.clearAll()
            reloadHistoryEntries(reset: true)
        case .notes:
            noteStore.clearAll()
        }
    }

    private func reloadHistoryEntries(reset: Bool) {
        guard !isNoteTabSelected else {
            visibleHistoryEntries = []
            totalHistoryEntryCount = 0
            isLoadingHistoryEntries = false
            return
        }

        let offset = reset ? 0 : visibleHistoryEntries.count
        guard reset || offset < totalHistoryEntryCount else { return }
        guard reset || !isLoadingHistoryEntries else { return }

        loadHistoryEntries(offset: offset, limit: historyPageSize, reset: reset)
    }

    private func loadHistoryEntries(offset: Int, limit: Int, reset: Bool) {
        historyPageGeneration += 1
        let generation = historyPageGeneration
        let kind = selectedHistoryKind
        let query = historySearchText
        isLoadingHistoryEntries = true

        historyStore.loadEntries(
            kind: kind,
            query: query,
            limit: limit,
            offset: offset
        ) { count, page in
            guard generation == historyPageGeneration else { return }
            totalHistoryEntryCount = count
            visibleHistoryEntries = reset ? page : visibleHistoryEntries + page
            isLoadingHistoryEntries = false
        }
    }

    private func deleteHistoryEntry(_ entry: TranscriptionHistoryEntry) {
        copiedEntryID = nil
        if selectedHistoryInfoEntry?.id == entry.id {
            selectedHistoryInfoEntry = nil
        }

        suppressedStoreHistoryReloadCount += 1
        guard historyStore.delete(id: entry.id) else {
            suppressedStoreHistoryReloadCount = max(0, suppressedStoreHistoryReloadCount - 1)
            return
        }
        refreshHistoryAudioStorageStats()

        guard let removedIndex = visibleHistoryEntries.firstIndex(where: { $0.id == entry.id }) else {
            reloadHistoryEntries(reset: true)
            return
        }

        visibleHistoryEntries.remove(at: removedIndex)
        totalHistoryEntryCount = max(0, totalHistoryEntryCount - 1)

        guard visibleHistoryEntries.count < totalHistoryEntryCount else { return }
        loadHistoryEntries(offset: visibleHistoryEntries.count, limit: 1, reset: false)
    }

    private func applyRetentionPolicyAndReload() {
        historyStore.updateRetentionPolicy()
        reloadHistoryEntries(reset: true)
        refreshHistoryAudioStorageStats()
    }

    private var selectedHistoryKind: TranscriptionHistoryKind? {
        switch selectedFilter {
        case .transcription:
            return .normal
        case .translation:
            return .translation
        case .transcript:
            return .transcript
        case .rewrite:
            return .rewrite
        case .note:
            return nil
        }
    }

    private func bulkDeletionTitle(for target: HistoryBulkDeletionTarget) -> String {
        switch target {
        case .history:
            return localized("Delete All History?")
        case .notes:
            return localized("Delete All Notes?")
        }
    }

    private func bulkDeletionMessage(for target: HistoryBulkDeletionTarget) -> String {
        switch target {
        case .history:
            return localized("This will permanently delete all history entries.")
        case .notes:
            return localized("This will permanently delete all notes.")
        }
    }

    private func openHistoryAudioStorageInFinder() {
        HistoryAudioStorageDirectoryManager.openRootInFinder()
    }

    private func chooseHistoryAudioStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = HistoryAudioStorageDirectoryManager.resolvedRootURL()

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        do {
            try HistoryAudioStorageDirectoryManager.saveUserSelectedRootURL(selectedURL)
            historyAudioStorageSelectionError = nil
            refreshHistoryAudioStorageDisplayPath()
        } catch {
            historyAudioStorageSelectionError = AppLocalization.format(
                "Failed to update history audio storage path: %@",
                error.localizedDescription
            )
        }
    }

    private func refreshHistoryAudioStorageDisplayPath() {
        historyAudioStorageDisplayPath = HistoryAudioStorageDirectoryManager.resolvedRootURL().path
    }

    private func refreshHistoryAudioStorageStats() {
        historyAudioStatsGeneration += 1
        let generation = historyAudioStatsGeneration
        historyStore.currentAudioArchiveStorageStats { stats in
            guard generation == historyAudioStatsGeneration else { return }
            historyAudioStorageStats = stats
        }
    }

    private var historyAudioStorageStatsSummary: String {
        AppLocalization.format(
            "Saved audio: %d files · %@",
            historyAudioStorageStats.storedFileCount,
            formattedByteCount(historyAudioStorageStats.totalBytes)
        )
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    private func exportAllHistoryAudio() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let summary = try historyStore.exportAllAudioArchives(to: destinationURL)
            historyAudioExportResultMessage = AppLocalization.format(
                "Exported %d audio files. Skipped %d. Failed %d.",
                summary.exportedCount,
                summary.skippedCount,
                summary.failedCount
            )
        } catch {
            historyAudioExportResultMessage = AppLocalization.format(
                "Audio export failed: %@",
                error.localizedDescription
            )
        }
        refreshHistoryAudioStorageStats()
    }

    private func showHistoryDetail(for entry: TranscriptionHistoryEntry) {
        guard entry.kind == .transcript, let appDelegate = AppDelegate.shared else {
            selectedHistoryInfoEntry = entry
            return
        }
        appDelegate.showMeetingDetailWindow(for: entry)
    }

    private func showCopyToast() {
        showCopyToast(localized("Copied to clipboard"))
    }

    private func showCopyToast(_ message: String, duration: TimeInterval = 2.2) {
        copyToastDismissTask?.cancel()
        copyToastMessage = message
        copyToastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            copyToastMessage = ""
        }
    }

    private func dismissCopyToast() {
        copyToastDismissTask?.cancel()
        copyToastMessage = ""
    }
}

// HistorySettingsView.swift
// Provides History Settings View for history settings.

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
                            SettingsSearchIconView()
                        }
                        .buttonStyle(SettingsCompactIconButtonStyle())
                        .help(localized("Search History"))
                        Button {
                            pendingBulkDeletionTarget = isNoteTabSelected ? .notes : .history
                        } label: {
                            HistoryActionIcon(kind: .delete)
                        }
                        .buttonStyle(HistoryToolbarDeleteButtonStyle())
                        .help(localized("Delete All"))
                        .disabled(isNoteTabSelected ? allNotes.isEmpty : totalHistoryEntryCount == 0)
                        Button {
                            historyAudioStorageSelectionError = nil
                            historyAudioExportResultMessage = nil
                            isHistoryAudioSettingsPresented = true
                        } label: {
                            HistoryToolbarSettingsIcon(size: 16)
                        }
                        .buttonStyle(SettingsCompactIconButtonStyle())
                        .help(localized("History Audio Settings"))
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
            applyNavigationTarget(navigationRequest?.target)
            if !HistoryRetentionPeriod.allCases.contains(where: { $0.rawValue == historyRetentionPeriodRaw }) {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
            }
            refreshHistoryAudioStorageDisplayPath()
            refreshHistoryAudioStorageStats()
            reloadHistoryEntries(reset: true)
        }
        .onChange(of: navigationRequest?.id) { _, _ in
            applyNavigationTarget(navigationRequest?.target)
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

    private func applyNavigationTarget(_ target: SettingsNavigationTarget?) {
        guard target?.tab == .history,
              let historyFilter = target?.historyFilter
        else {
            return
        }

        selectedFilter = historyFilter
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

private struct HistoryToolbarDeleteButtonStyle: ButtonStyle {
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        HistoryToolbarDeleteButtonBody(configuration: configuration, size: size)
    }
}

private struct HistoryToolbarDeleteButtonBody: View {
    let configuration: HistoryToolbarDeleteButtonStyle.Configuration
    let size: CGFloat
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if configuration.isPressed {
            return .red.opacity(0.16)
        }
        if isHovered {
            return .red.opacity(0.13)
        }
        return SettingsUIStyle.subtleFillColor
    }

    private var stroke: Color {
        if configuration.isPressed || isHovered {
            return .red.opacity(isHovered ? 0.30 : 0.22)
        }
        return SettingsUIStyle.subtleBorderColor
    }
}

private struct HistoryToolbarSettingsIcon: View {
    var color: Color = .secondary
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            SVGPathShape(pathData: "M12 15.75C9.93 15.75 8.25 14.07 8.25 12C8.25 9.93 9.93 8.25 12 8.25C14.07 8.25 15.75 9.93 15.75 12C15.75 14.07 14.07 15.75 12 15.75ZM12 9.75C10.76 9.75 9.75 10.76 9.75 12C9.75 13.24 10.76 14.25 12 14.25C13.24 14.25 14.25 13.24 14.25 12C14.25 10.76 13.24 9.75 12 9.75Z")
                .fill(color)
            SVGPathShape(pathData: "M15.21 22.1903C15 22.1903 14.79 22.1603 14.58 22.1103C13.96 21.9403 13.44 21.5503 13.11 21.0003L12.99 20.8003C12.4 19.7803 11.59 19.7803 11 20.8003L10.89 20.9903C10.56 21.5503 10.04 21.9503 9.42 22.1103C8.79 22.2803 8.14 22.1903 7.59 21.8603L5.87 20.8703C5.26 20.5203 4.82 19.9503 4.63 19.2603C4.45 18.5703 4.54 17.8603 4.89 17.2503C5.18 16.7403 5.26 16.2803 5.09 15.9903C4.92 15.7003 4.49 15.5303 3.9 15.5303C2.44 15.5303 1.25 14.3403 1.25 12.8803V11.1203C1.25 9.66029 2.44 8.47029 3.9 8.47029C4.49 8.47029 4.92 8.30029 5.09 8.01029C5.26 7.72029 5.19 7.26029 4.89 6.75029C4.54 6.14029 4.45 5.42029 4.63 4.74029C4.81 4.05029 5.25 3.48029 5.87 3.13029L7.6 2.14029C8.73 1.47029 10.22 1.86029 10.9 3.01029L11.02 3.21029C11.61 4.23029 12.42 4.23029 13.01 3.21029L13.12 3.02029C13.8 1.86029 15.29 1.47029 16.43 2.15029L18.15 3.14029C18.76 3.49029 19.2 4.06029 19.39 4.75029C19.57 5.44029 19.48 6.15029 19.13 6.76029C18.84 7.27029 18.76 7.73029 18.93 8.02029C19.1 8.31029 19.53 8.48029 20.12 8.48029C21.58 8.48029 22.77 9.67029 22.77 11.1303V12.8903C22.77 14.3503 21.58 15.5403 20.12 15.5403C19.53 15.5403 19.1 15.7103 18.93 16.0003C18.76 16.2903 18.83 16.7503 19.13 17.2603C19.48 17.8703 19.58 18.5903 19.39 19.2703C19.21 19.9603 18.77 20.5303 18.15 20.8803L16.42 21.8703C16.04 22.0803 15.63 22.1903 15.21 22.1903ZM12 18.4903C12.89 18.4903 13.72 19.0503 14.29 20.0403L14.4 20.2303C14.52 20.4403 14.72 20.5903 14.96 20.6503C15.2 20.7103 15.44 20.6803 15.64 20.5603L17.37 19.5603C17.63 19.4103 17.83 19.1603 17.91 18.8603C17.99 18.5603 17.95 18.2503 17.8 17.9903C17.23 17.0103 17.16 16.0003 17.6 15.2303C18.04 14.4603 18.95 14.0203 20.09 14.0203C20.73 14.0203 21.24 13.5103 21.24 12.8703V11.1103C21.24 10.4803 20.73 9.96029 20.09 9.96029C18.95 9.96029 18.04 9.52029 17.6 8.75029C17.16 7.98029 17.23 6.97029 17.8 5.99029C17.95 5.73029 17.99 5.42029 17.91 5.12029C17.83 4.82029 17.64 4.58029 17.38 4.42029L15.65 3.43029C15.22 3.17029 14.65 3.32029 14.39 3.76029L14.28 3.95029C13.71 4.94029 12.88 5.50029 11.99 5.50029C11.1 5.50029 10.27 4.94029 9.7 3.95029L9.59 3.75029C9.34 3.33029 8.78 3.18029 8.35 3.43029L6.62 4.43029C6.36 4.58029 6.16 4.83029 6.08 5.13029C6 5.43029 6.04 5.74029 6.19 6.00029C6.76 6.98029 6.83 7.99029 6.39 8.76029C5.95 9.53029 5.04 9.97029 3.9 9.97029C3.26 9.97029 2.75 10.4803 2.75 11.1203V12.8803C2.75 13.5103 3.26 14.0303 3.9 14.0303C5.04 14.0303 5.95 14.4703 6.39 15.2403C6.83 16.0103 6.76 17.0203 6.19 18.0003C6.04 18.2603 6 18.5703 6.08 18.8703C6.16 19.1703 6.35 19.4103 6.61 19.5703L8.34 20.5603C8.55 20.6903 8.8 20.7203 9.03 20.6603C9.27 20.6003 9.47 20.4403 9.6 20.2303L9.71 20.0403C10.28 19.0603 11.11 18.4903 12 18.4903Z")
                .fill(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

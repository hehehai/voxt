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

struct HistorySettingsView: View {
    private static let pageSize = 40

    @Environment(\.locale) private var locale
    @AppStorage(AppPreferenceKey.historyCleanupEnabled) private var historyCleanupEnabled = true
    @AppStorage(AppPreferenceKey.historyRetentionPeriod) private var historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
    @AppStorage(AppPreferenceKey.historyAudioStorageEnabled) private var historyAudioStorageEnabled = false

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var noteStore: VoxtNoteStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    let navigationRequest: SettingsNavigationRequest?
    @State private var copiedEntryID: UUID?
    @State private var copiedNoteID: UUID?
    @State private var selectedFilter: HistoryFilterTab = .transcription
    @State private var visibleItemLimit = pageSize
    @State private var isHistoryAudioSettingsPresented = false
    @State private var historyAudioStorageDisplayPath = ""
    @State private var historyAudioStorageSelectionError: String?
    @State private var historyAudioExportResultMessage: String?
    @State private var historyAudioStorageStats = HistoryAudioStorageStats(storedFileCount: 0, totalBytes: 0)
    @State private var pendingBulkDeletionTarget: HistoryBulkDeletionTarget?
    @State private var selectedHistoryInfoEntry: TranscriptionHistoryEntry?

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        HistoryRetentionPeriod(rawValue: historyRetentionPeriodRaw) ?? .ninetyDays
    }

    private var filteredEntries: [TranscriptionHistoryEntry] {
        switch selectedFilter {
        case .transcription:
            historyStore.historyEntries(for: .normal)
        case .translation:
            historyStore.historyEntries(for: .translation)
        case .rewrite:
            historyStore.historyEntries(for: .rewrite)
        case .meeting:
            historyStore.historyEntries(for: .meeting)
        case .note:
            []
        }
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
                                HistoryFilterTabPicker(selectedTab: $selectedFilter)
                                Spacer(minLength: 12)
                                Button {
                                    pendingBulkDeletionTarget = isNoteTabSelected ? .notes : .history
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(SettingsCompactIconButtonStyle(tone: .destructive))
                                .help(localized("Delete All"))
                                .disabled(isNoteTabSelected ? allNotes.isEmpty : historyStore.allHistoryEntries.isEmpty)
                                Button {
                                    historyAudioStorageSelectionError = nil
                                    historyAudioExportResultMessage = nil
                                    isHistoryAudioSettingsPresented = true
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                                .buttonStyle(SettingsCompactIconButtonStyle())
                            }

                            if isNoteTabSelected && allNotes.isEmpty {
                                Text(localized("No notes yet."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !isNoteTabSelected && historyStore.allHistoryEntries.isEmpty {
                                Text(localized("No history yet."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !isNoteTabSelected && filteredEntries.isEmpty {
                                Text(localized("No entries in this category yet."))
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
                                            Button(localized("Load More")) {
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
                                                audioURL: historyStore.audioURL(for: entry),
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
                                                onShowInfo: {
                                                    selectedHistoryInfoEntry = entry
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
                                            Button(localized("Load More")) {
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
                    .settingsNavigationAnchor(.historySettings)
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
        .sheet(isPresented: $isHistoryAudioSettingsPresented) {
            historyAudioSettingsSheet
        }
        .sheet(item: $selectedHistoryInfoEntry) { entry in
            HistoryDetailSheetContent(
                entry: entry,
                audioURL: historyStore.audioURL(for: entry),
                locale: locale
            )
            .frame(minWidth: 520, idealWidth: 620, minHeight: 480, idealHeight: 640)
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
            resetVisibleItemLimit()
            refreshHistoryAudioStorageDisplayPath()
            refreshHistoryAudioStorageStats()
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
            refreshHistoryAudioStorageStats()
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

    private func confirmBulkDeletion(_ target: HistoryBulkDeletionTarget) {
        copiedEntryID = nil
        copiedNoteID = nil
        resetVisibleItemLimit()
        switch target {
        case .history:
            historyStore.clearAll()
        case .notes:
            noteStore.clearAll()
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

    private func loadNextPageIfNeeded() {
        if isNoteTabSelected {
            guard hasMoreVisibleNotes else { return }
            visibleItemLimit = min(visibleItemLimit + Self.pageSize, allNotes.count)
            return
        }

        guard hasMoreFilteredEntries else { return }
        visibleItemLimit = min(visibleItemLimit + Self.pageSize, filteredEntries.count)
    }

    private var historyAudioSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("History Settings"))
                .font(.title3.weight(.semibold))

            GeneralSettingsCard(titleText: localized("Cleanup")) {
                Toggle(localized("History Cleanup"), isOn: $historyCleanupEnabled)

                if historyCleanupEnabled {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(localized("Retention"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        SettingsMenuPicker(
                            selection: $historyRetentionPeriodRaw,
                            options: HistoryRetentionPeriod.allCases.map { option in
                                SettingsMenuOption(value: option.rawValue, title: option.title)
                            },
                            selectedTitle: historyRetentionPeriod.title,
                            width: 160
                        )
                    }
                } else {
                    Text(localized("When disabled, Voxt keeps history entries until you delete them manually."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeneralSettingsCard(titleText: localized("Audio Storage")) {
                Toggle(localized("Save history audio"), isOn: $historyAudioStorageEnabled)

                if historyAudioStorageEnabled {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(localized("Storage Path"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: openHistoryAudioStorageInFinder) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.caption)
                                Text(
                                    historyAudioStorageDisplayPath.isEmpty
                                    ? HistoryAudioStorageDirectoryManager.defaultRootURL.path
                                    : historyAudioStorageDisplayPath
                                )
                                    .underline()
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .multilineTextAlignment(.trailing)
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(SettingsInlineSelectorButtonStyle())
                        .help(localized("Open folder"))

                        Button(localized("Choose")) {
                            chooseHistoryAudioStorageDirectory()
                        }
                        .buttonStyle(SettingsPillButtonStyle())
                    }

                    Text(localized("New history audio is stored here. Switching the path will not move existing audio files."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let historyAudioStorageSelectionError, !historyAudioStorageSelectionError.isEmpty {
                        Text(historyAudioStorageSelectionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text(localized("When disabled, history items will not keep audio files."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if historyAudioStorageEnabled {
                GeneralSettingsCard(titleText: localized("Export")) {
                    HStack(spacing: 10) {
                        Button(localized("Export Audio")) {
                            exportAllHistoryAudio()
                        }
                        .buttonStyle(SettingsPillButtonStyle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(historyAudioStorageStatsSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(localized("Copies every saved history audio file into a folder you choose."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let historyAudioExportResultMessage, !historyAudioExportResultMessage.isEmpty {
                        Text(historyAudioExportResultMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsDialogActionRow {
                Button(localized("Done")) {
                    isHistoryAudioSettingsPresented = false
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
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
        historyAudioStorageStats = historyStore.currentAudioArchiveStorageStats()
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
}

private struct HistoryDetailSheetContent: View {
    @Environment(\.dismiss) private var dismiss

    let entry: TranscriptionHistoryEntry
    let audioURL: URL?
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(localized("History Details"))
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 12)

                Button(localized("Close")) {
                    dismiss()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            TranscriptionDetailContentView(
                entry: entry,
                audioURL: audioURL,
                locale: locale,
                style: .window
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

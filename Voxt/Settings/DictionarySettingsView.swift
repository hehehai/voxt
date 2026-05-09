import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct DictionarySettingsView: View {
    @AppStorage(AppPreferenceKey.dictionaryAutoLearningEnabled) private var dictionaryAutoLearningEnabled = true
    @AppStorage(AppPreferenceKey.dictionaryAutoLearningPrompt) private var storedAutomaticLearningPrompt = ""
    @AppStorage(AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled) private var dictionaryHighConfidenceCorrectionEnabled = true
    @AppStorage(AppPreferenceKey.dictionarySuggestionIngestModelOptionID) private var preferredHistoryScanModelID = ""

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    let availableHistoryScanModels: () -> [DictionaryHistoryScanModelOption]
    let onIngestSuggestionsFromHistory: (DictionaryHistoryScanRequest, Bool) -> Void
    let onCancelIngestSuggestionsFromHistory: () -> Void
    let navigationRequest: SettingsNavigationRequest?

    @State private var selectedFilter: DictionaryFilter = .all
    @State private var dialog: DictionaryDialog?
    @State private var availableGroups: [AppBranchGroup] = []
    @State private var availableGroupNamesByID: [UUID: String] = [:]
    @State private var showDictionaryAdvancedSettings = false
    @State private var showDictionaryIngestDialog = false
    @State private var showClearAllConfirmation = false
    @State private var suggestionFilterDraft = DictionarySuggestionFilterSettings.defaultValue
    @State private var automaticLearningPromptDraft = AppPromptDefaults.text(for: .dictionaryAutoLearning)
    @State private var historyScanModelOptions: [DictionaryHistoryScanModelOption] = []
    @State private var selectedHistoryScanModelID = ""
    @State private var dictionaryTransferMessage: String?
    @State private var suggestionActionMessage: String?
    @State private var pendingHistoryScanCount = 0
    @State private var visibleEntryLimit = Self.dictionaryPageSize

    private static let dictionaryPageSize = 80

    private var visibleEntries: [DictionaryEntry] {
        dictionaryStore.filteredEntries(for: selectedFilter)
    }

    private var pagedVisibleEntries: [DictionaryEntry] {
        Array(visibleEntries.prefix(visibleEntryLimit))
    }

    private var hasMoreVisibleEntries: Bool {
        visibleEntryLimit < visibleEntries.count
    }

    private var localHistoryScanModelOptions: [DictionaryHistoryScanModelOption] {
        historyScanModelOptions.filter { $0.source == .local }
    }

    private var remoteHistoryScanModelOptions: [DictionaryHistoryScanModelOption] {
        historyScanModelOptions.filter { $0.source == .remote }
    }

    private var selectedHistoryScanModelOption: DictionaryHistoryScanModelOption? {
        historyScanModelOptions.first(where: { $0.id == selectedHistoryScanModelID })
    }

    private var historyScanProgress: DictionaryHistoryScanProgress {
        dictionarySuggestionStore.historyScanProgress
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard
                        .settingsNavigationAnchor(.dictionarySettings)
                    dictionaryListCard
                        .settingsNavigationAnchor(.dictionaryEntries)
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
        .sheet(item: $dialog) { currentDialog in
            dialogView(for: currentDialog)
        }
        .sheet(isPresented: $showDictionaryAdvancedSettings) {
            DictionaryAdvancedSettingsDialog(
                dictionaryAutoLearningEnabled: $dictionaryAutoLearningEnabled,
                automaticLearningPromptDraft: $automaticLearningPromptDraft,
                dictionaryHighConfidenceCorrectionEnabled: $dictionaryHighConfidenceCorrectionEnabled,
                isPresented: $showDictionaryAdvancedSettings,
                onRestoreDefaultAutomaticLearningPrompt: restoreAutomaticLearningPromptToDefault,
                onSave: saveDictionaryAdvancedSettings
            )
        }
        .sheet(isPresented: $showDictionaryIngestDialog) {
            DictionaryOneClickIngestDialog(
                isPresented: $showDictionaryIngestDialog,
                pendingHistoryScanCount: pendingHistoryScanCount,
                localModelOptions: localHistoryScanModelOptions,
                remoteModelOptions: remoteHistoryScanModelOptions,
                selectedModelID: $selectedHistoryScanModelID,
                draftPrompt: $suggestionFilterDraft.prompt,
                historyScanProgress: historyScanProgress,
                statusText: historyScanStatusText,
                cancellationText: historyScanCancellationText,
                actionMessage: suggestionActionMessage,
                onRestoreDefaultPrompt: restoreSuggestionIngestPromptToDefault,
                onSave: saveSuggestionIngestSettings,
                onStart: startSuggestionIngestFromDialog,
                onCancelRunning: requestSuggestionIngestCancellation
            )
        }
        .onAppear(perform: reloadContentAsync)
        .onReceive(NotificationCenter.default.publisher(for: .voxtConfigurationDidImport)) { _ in
            reloadContentAsync()
        }
        .onChange(of: selectedFilter) { _, _ in
            resetVisibleEntryLimit()
        }
        .onChange(of: dictionaryStore.entries.count) { _, _ in
            resetVisibleEntryLimit()
        }
        .alert(localized("Delete All Dictionary Terms?"), isPresented: $showClearAllConfirmation) {
            Button(localized("Delete"), role: .destructive) {
                dictionaryStore.clearAll()
            }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("This will permanently delete all dictionary terms."))
        }
    }

    private func scrollToNavigationTargetIfNeeded(using proxy: ScrollViewProxy) {
        guard let navigationRequest,
              navigationRequest.target.tab == .dictionary,
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

    private func resetVisibleEntryLimit() {
        visibleEntryLimit = Self.dictionaryPageSize
    }

    private func loadNextDictionaryPageIfNeeded() {
        guard hasMoreVisibleEntries else { return }
        visibleEntryLimit = min(visibleEntryLimit + Self.dictionaryPageSize, visibleEntries.count)
    }

    private func refreshPendingHistoryScanCountAsync() {
        let historyEntries = historyStore.allHistoryEntries
        let checkpoint = dictionarySuggestionStore.historyScanCheckpoint

        DispatchQueue.global(qos: .utility).async {
            let count = DictionarySuggestionStore.pendingHistoryEntryCount(
                in: historyEntries,
                checkpoint: checkpoint
            )

            DispatchQueue.main.async {
                pendingHistoryScanCount = count
            }
        }
    }

    private var settingsCard: some View {
        DictionarySettingsHeaderCard(
            historyScanProgress: historyScanProgress,
            suggestionActionMessage: suggestionActionMessage,
            onOpenIngest: openDictionaryIngestDialog,
            onOpenSettings: openDictionaryAdvancedSettings,
            onImport: importDictionary,
            onExport: exportDictionary,
            historyScanSummaryText: historyScanSummaryText(lastRunAt:)
        )
    }

    private var dictionaryListCard: some View {
        DictionaryEntriesCard(
            selectedFilter: $selectedFilter,
            pagedVisibleEntries: pagedVisibleEntries,
            visibleEntries: visibleEntries,
            hasMoreVisibleEntries: hasMoreVisibleEntries,
            dictionaryTransferMessage: dictionaryTransferMessage,
            scopeLabel: scopeLabel(for:),
            scopeIsMissing: { entry in
                entry.groupID != nil && groupName(for: entry.groupID) == nil
            },
            onCreate: { dialog = .create },
            onClearAll: { showClearAllConfirmation = true },
            onEdit: { entry in dialog = .edit(entry) },
            onDelete: { entry in dictionaryStore.delete(id: entry.id) },
            onLoadMore: loadNextDictionaryPageIfNeeded
        )
    }

    @ViewBuilder
    private func dialogView(for dialog: DictionaryDialog) -> some View {
        DictionaryTermDialogView(
            dialog: dialog,
            availableGroups: availableGroups,
            onCancel: {
                self.dialog = nil
            },
            onSave: { term, replacementTerms, selectedGroupID in
                try save(
                    dialog: dialog,
                    term: term,
                    replacementTerms: replacementTerms,
                    selectedGroupID: selectedGroupID
                )
                self.dialog = nil
            }
        )
    }

    private func save(
        dialog: DictionaryDialog,
        term: String,
        replacementTerms: [String],
        selectedGroupID: UUID?
    ) throws {
        switch dialog {
        case .create:
            try dictionaryStore.createManualEntry(
                term: term,
                replacementTerms: replacementTerms,
                groupID: selectedGroupID,
                groupNameSnapshot: selectedGroupName(for: selectedGroupID)
            )
        case .edit(let entry):
            try dictionaryStore.updateEntry(
                id: entry.id,
                term: term,
                replacementTerms: replacementTerms,
                groupID: selectedGroupID,
                groupNameSnapshot: selectedGroupName(for: selectedGroupID) ?? entry.groupNameSnapshot
            )
        }
    }

    private func reloadContentAsync() {
        dictionaryStore.reloadAsync()
        dictionarySuggestionStore.reloadAsync()
        refreshLocalContentState()
    }

    private func refreshLocalContentState() {
        reloadGroups()
        resetVisibleEntryLimit()
        historyScanModelOptions = availableHistoryScanModels()
        automaticLearningPromptDraft = AppPromptDefaults.resolvedStoredText(
            storedAutomaticLearningPrompt,
            kind: .dictionaryAutoLearning
        )
        suggestionFilterDraft = dictionarySuggestionStore.filterSettings
        selectedHistoryScanModelID = resolvedDefaultHistoryScanModelID(from: historyScanModelOptions)
    }

    private func openDictionaryAdvancedSettings() {
        automaticLearningPromptDraft = AppPromptDefaults.resolvedStoredText(
            storedAutomaticLearningPrompt,
            kind: .dictionaryAutoLearning
        )
        showDictionaryAdvancedSettings = true
    }

    private func openDictionaryIngestDialog() {
        let options = availableHistoryScanModels()
        historyScanModelOptions = options
        suggestionFilterDraft = dictionarySuggestionStore.filterSettings
        selectedHistoryScanModelID = resolvedDefaultHistoryScanModelID(from: options)
        refreshPendingHistoryScanCountAsync()
        showDictionaryIngestDialog = true
    }

    private func requestSuggestionIngestCancellation() {
        suggestionActionMessage = nil
        onCancelIngestSuggestionsFromHistory()
    }

    private func runSuggestionIngest() {
        let options = availableHistoryScanModels()
        guard !options.isEmpty else {
            suggestionActionMessage = AppLocalization.localizedString(
                "No configured local or remote model is available for dictionary ingestion. Configure one in Model settings first."
            )
            return
        }

        historyScanModelOptions = options
        if !options.contains(where: { $0.id == selectedHistoryScanModelID }) {
            selectedHistoryScanModelID = resolvedDefaultHistoryScanModelID(from: options)
        }
        guard !selectedHistoryScanModelID.isEmpty else { return }

        suggestionActionMessage = nil
        saveSuggestionIngestSettings()
        onIngestSuggestionsFromHistory(
            DictionaryHistoryScanRequest(
                modelOptionID: selectedHistoryScanModelID,
                filterSettings: DictionarySuggestionFilterSettings(
                    prompt: suggestionFilterDraft.prompt,
                    batchSize: dictionarySuggestionStore.filterSettings.batchSize,
                    maxCandidatesPerBatch: dictionarySuggestionStore.filterSettings.maxCandidatesPerBatch
                ).sanitized()
            ),
            true
        )
    }

    private func startSuggestionIngestFromDialog() {
        saveSuggestionIngestSettings()
        runSuggestionIngest()
    }

    private func saveDictionaryAdvancedSettings() {
        let resolvedAutomaticLearningPrompt = AppPromptDefaults.resolvedStoredText(
            automaticLearningPromptDraft,
            kind: .dictionaryAutoLearning
        )
        automaticLearningPromptDraft = resolvedAutomaticLearningPrompt
        storedAutomaticLearningPrompt = AppPromptDefaults.canonicalStoredText(
            resolvedAutomaticLearningPrompt,
            kind: .dictionaryAutoLearning
        )
    }

    private func saveSuggestionIngestSettings() {
        let sanitized = DictionarySuggestionFilterSettings(
            prompt: suggestionFilterDraft.prompt,
            batchSize: dictionarySuggestionStore.filterSettings.batchSize,
            maxCandidatesPerBatch: dictionarySuggestionStore.filterSettings.maxCandidatesPerBatch
        ).sanitized()
        suggestionFilterDraft = sanitized
        dictionarySuggestionStore.saveFilterSettings(sanitized)

        if historyScanModelOptions.contains(where: { $0.id == selectedHistoryScanModelID }) {
            preferredHistoryScanModelID = selectedHistoryScanModelID
        }
    }

    private func restoreSuggestionIngestPromptToDefault() {
        suggestionFilterDraft.prompt = DictionarySuggestionFilterSettings.defaultPrompt
    }

    private func restoreAutomaticLearningPromptToDefault() {
        automaticLearningPromptDraft = AppPromptDefaults.text(for: .dictionaryAutoLearning)
    }

    private func resolvedDefaultHistoryScanModelID(from options: [DictionaryHistoryScanModelOption]) -> String {
        if options.contains(where: { $0.id == preferredHistoryScanModelID }) {
            return preferredHistoryScanModelID
        }
        if options.contains(where: { $0.id == selectedHistoryScanModelID }) {
            return selectedHistoryScanModelID
        }
        return options.first?.id ?? ""
    }

    private func exportDictionary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = localized("Voxt-Dictionary.json")
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try dictionaryStore.exportTransferJSONString()
            try text.write(to: url, atomically: true, encoding: .utf8)
            dictionaryTransferMessage = localized("Dictionary exported successfully.")
        } catch {
            dictionaryTransferMessage = AppLocalization.format(
                "Dictionary export failed: %@",
                error.localizedDescription
            )
        }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = try dictionaryStore.importTransferJSONString(text)
            refreshLocalContentState()
            dictionaryTransferMessage = AppLocalization.format(
                "Imported %d terms and skipped %d duplicates.",
                result.addedCount,
                result.skippedCount
            )
        } catch {
            dictionaryTransferMessage = AppLocalization.format(
                "Dictionary import failed: %@",
                error.localizedDescription
            )
        }
    }

    private func reloadGroups() {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.appBranchGroups),
              let groups = try? JSONDecoder().decode([AppBranchGroup].self, from: data)
        else {
            availableGroups = []
            availableGroupNamesByID = [:]
            return
        }
        let sortedGroups = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        availableGroups = sortedGroups
        availableGroupNamesByID = Dictionary(uniqueKeysWithValues: sortedGroups.map { ($0.id, $0.name) })
    }

    private func selectedGroupName(for selectedGroupID: UUID?) -> String? {
        guard let selectedGroupID else { return nil }
        return groupName(for: selectedGroupID)
    }

    private func groupName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return availableGroupNamesByID[id]
    }

    private func scopeLabel(for entry: DictionaryEntry) -> String {
        guard let groupID = entry.groupID else {
            return AppLocalization.localizedString("Global")
        }
        return groupName(for: groupID) ?? entry.groupNameSnapshot ?? AppLocalization.localizedString("Missing Group")
    }

    private func suggestionScopeLabel(for suggestion: DictionarySuggestion) -> String {
        guard let groupID = suggestion.groupID else {
            return AppLocalization.localizedString("Global")
        }
        return groupName(for: groupID) ?? suggestion.groupNameSnapshot ?? AppLocalization.localizedString("Missing Group")
    }

    private var historyScanStatusText: String {
        AppLocalization.format(
            "Scanned %d of %d history records. Added %d dictionary terms, skipped %d duplicates.",
            historyScanProgress.processedCount,
            historyScanProgress.totalCount,
            historyScanProgress.newSuggestionCount,
            historyScanProgress.duplicateCount
        )
    }

    private var historyScanCancellationText: String {
        AppLocalization.localizedString("Cancel requested. Stopping after the current batch.")
    }

    private func historyScanSummaryText(lastRunAt: Date) -> String {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        let timeText = relative.localizedString(for: lastRunAt, relativeTo: Date())
        let progress = historyScanProgress
        return AppLocalization.format(
            "Last scan %@ processed %d history records and added %d dictionary terms.",
            timeText,
            progress.lastProcessedCount,
            progress.lastNewSuggestionCount
        )
    }
}

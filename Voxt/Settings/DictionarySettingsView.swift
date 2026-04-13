import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

struct DictionarySettingsView: View {
    @AppStorage(AppPreferenceKey.dictionaryRecognitionEnabled) private var dictionaryRecognitionEnabled = true
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
    @State private var draftTerm = ""
    @State private var draftReplacementTermInput = ""
    @State private var draftReplacementTerms: [String] = []
    @State private var selectedGroupID: UUID?
    @State private var errorMessage: String?
    @State private var availableGroups: [AppBranchGroup] = []
    @State private var showDictionaryInfo = false
    @State private var showDictionaryAdvancedSettings = false
    @State private var suggestionFilterDraft = DictionarySuggestionFilterSettings.defaultValue
    @State private var historyScanModelOptions: [DictionaryHistoryScanModelOption] = []
    @State private var selectedHistoryScanModelID = ""
    @State private var dictionaryTransferMessage: String?
    @State private var suggestionActionMessage: String?

    private var visibleEntries: [DictionaryEntry] {
        dictionaryStore.filteredEntries(for: selectedFilter)
    }

    private var pendingHistoryScanCount: Int {
        dictionarySuggestionStore.pendingHistoryEntries(in: historyStore).count
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

    private var oneClickIngestButtonTitle: String {
        if historyScanProgress.isRunning {
            return historyScanProgress.isCancellationRequested
                ? String(localized: "Canceling...")
                : String(localized: "Cancel Ingest")
        }
        return String(localized: "One-Click Ingest")
    }

    private var oneClickIngestButtonDisabled: Bool {
        if historyScanProgress.isRunning {
            return historyScanProgress.isCancellationRequested
        }
        return pendingHistoryScanCount == 0
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
                dictionaryHighConfidenceCorrectionEnabled: $dictionaryHighConfidenceCorrectionEnabled,
                isPresented: $showDictionaryAdvancedSettings,
                dictionaryRecognitionEnabled: dictionaryRecognitionEnabled,
                pendingHistoryScanCount: pendingHistoryScanCount,
                localModelOptions: localHistoryScanModelOptions,
                remoteModelOptions: remoteHistoryScanModelOptions,
                selectedModelOption: selectedHistoryScanModelOption,
                selectedModelID: $selectedHistoryScanModelID,
                draftPrompt: $suggestionFilterDraft.prompt,
                onRestoreDefaultPrompt: restoreSuggestionIngestPromptToDefault,
                onSave: saveSuggestionIngestSettings
            )
        }
        .onAppear(perform: reloadContent)
        .onReceive(NotificationCenter.default.publisher(for: .voxtConfigurationDidImport)) { _ in
            reloadContent()
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

    private var settingsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    Toggle("Enable Dictionary", isOn: $dictionaryRecognitionEnabled)
                        .controlSize(.small)

                    Button {
                        openDictionaryAdvancedSettings()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Dictionary Advanced Settings"))

                    Button {
                        showDictionaryInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDictionaryInfo, arrowEdge: .top) {
                        Text("Dictionary recognition injects matched terms into prompts and can correct high-confidence near matches before output.")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(width: 300, alignment: .leading)
                    }

                    Spacer(minLength: 12)

                    Button(oneClickIngestButtonTitle) {
                        handleOneClickIngestButton()
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                    .disabled(oneClickIngestButtonDisabled)

                    Divider()
                        .frame(height: 16)

                    Button("Import") {
                        importDictionary()
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Button("Export") {
                        exportDictionary()
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                }

                if historyScanProgress.isRunning {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(
                            value: Double(historyScanProgress.processedCount),
                            total: Double(max(historyScanProgress.totalCount, 1))
                        )
                        Text(historyScanProgress.isCancellationRequested ? historyScanCancellationText : historyScanStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = historyScanProgress.errorMessage,
                          !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let lastRunAt = historyScanProgress.lastRunAt {
                    Text(historyScanSummaryText(lastRunAt: lastRunAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if pendingHistoryScanCount > 0 {
                    Text(
                        AppLocalization.format(
                            "%d new history records are ready for dictionary ingestion.",
                            pendingHistoryScanCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let suggestionActionMessage, !suggestionActionMessage.isEmpty {
                    Text(suggestionActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dictionaryListCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DictionaryFilterPicker(selectedFilter: $selectedFilter)

                    Spacer(minLength: 12)

                    Button("Create") {
                        draftTerm = ""
                        draftReplacementTermInput = ""
                        draftReplacementTerms = []
                        selectedGroupID = nil
                        errorMessage = nil
                        dialog = .create
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Button("Clean All", role: .destructive) {
                        dictionaryStore.clearAll()
                    }
                    .buttonStyle(SettingsStatusButtonStyle(tint: .red))
                    .disabled(dictionaryStore.entries.isEmpty)
                }

                if visibleEntries.isEmpty {
                    Text("No dictionary terms yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(visibleEntries) { entry in
                                DictionaryRow(
                                    entry: entry,
                                    scopeLabel: scopeLabel(for: entry),
                                    scopeIsMissing: entry.groupID != nil && groupName(for: entry.groupID) == nil,
                                    onEdit: {
                                        draftTerm = entry.term
                                        draftReplacementTermInput = ""
                                        draftReplacementTerms = entry.replacementTerms.map(\.text)
                                        selectedGroupID = entry.groupID
                                        errorMessage = nil
                                        dialog = .edit(entry)
                                    },
                                    onDelete: {
                                        dictionaryStore.delete(id: entry.id)
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }

                if let dictionaryTransferMessage, !dictionaryTransferMessage.isEmpty {
                    Text(dictionaryTransferMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func dialogView(for dialog: DictionaryDialog) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(dialog.title)
                .font(.title3.weight(.semibold))

            TextField(String(localized: "Dictionary Term"), text: $draftTerm)
                .textFieldStyle(.plain)
                .settingsFieldSurface()

            SettingsMenuPicker(
                selection: $selectedGroupID,
                options: dictionaryGroupOptions,
                selectedTitle: selectedDictionaryGroupTitle,
                width: 240
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Replacement Match Terms")
                        .font(.caption.weight(.semibold))

                    Text(" (Optional. Without them, Voxt still uses normal dictionary matching and high-confidence correction.)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField(String(localized: "Replacement Match Term"), text: $draftReplacementTermInput)
                        .textFieldStyle(.plain)
                        .settingsFieldSurface()
                        .onSubmit(addDraftReplacementTerm)

                    Button("Add") {
                        addDraftReplacementTerm()
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                    .disabled(draftReplacementTermInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Add phrases that should always resolve to this dictionary term.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if draftReplacementTerms.isEmpty {
                    Text("No replacement match terms.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DictionaryEditableTagList(values: draftReplacementTerms) { value in
                        removeDraftReplacementTerm(value)
                    }
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            SettingsDialogActionRow {
                Button("Cancel") {
                    self.dialog = nil
                }
                .buttonStyle(SettingsPillButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(dialog.confirmButtonTitle) {
                    save(dialog: dialog)
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var dictionaryGroupOptions: [SettingsMenuOption<UUID?>] {
        var options: [SettingsMenuOption<UUID?>] = [
            SettingsMenuOption(value: nil, title: String(localized: "Global"))
        ]
        if let selectedGroupID, groupName(for: selectedGroupID) == nil {
            options.append(SettingsMenuOption(value: selectedGroupID, title: String(localized: "Missing Group")))
        }
        options.append(contentsOf: availableGroups.map { group in
            SettingsMenuOption(value: Optional(group.id), title: group.name)
        })
        return options
    }

    private var selectedDictionaryGroupTitle: String {
        if let selectedGroupID {
            return groupName(for: selectedGroupID) ?? String(localized: "Missing Group")
        }
        return String(localized: "Global")
    }

    private func save(dialog: DictionaryDialog) {
        do {
            switch dialog {
            case .create:
                try dictionaryStore.createManualEntry(
                    term: draftTerm,
                    replacementTerms: draftReplacementTerms,
                    groupID: selectedGroupID,
                    groupNameSnapshot: selectedGroupName()
                )
            case .edit(let entry):
                try dictionaryStore.updateEntry(
                    id: entry.id,
                    term: draftTerm,
                    replacementTerms: draftReplacementTerms,
                    groupID: selectedGroupID,
                    groupNameSnapshot: selectedGroupName() ?? entry.groupNameSnapshot
                )
            }
            self.dialog = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addDraftReplacementTerm() {
        let display = draftReplacementTermInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = DictionaryStore.normalizeTerm(display)
        guard !display.isEmpty, !normalized.isEmpty else {
            errorMessage = AppLocalization.localizedString("Replacement match term cannot be empty.")
            return
        }

        if normalized == DictionaryStore.normalizeTerm(draftTerm) {
            errorMessage = AppLocalization.localizedString("Replacement match term cannot be the same as the dictionary term.")
            return
        }

        if draftReplacementTerms.contains(where: { DictionaryStore.normalizeTerm($0) == normalized }) {
            draftReplacementTermInput = ""
            return
        }

        draftReplacementTerms.append(display)
        draftReplacementTerms.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        draftReplacementTermInput = ""
        errorMessage = nil
    }

    private func removeDraftReplacementTerm(_ value: String) {
        let normalized = DictionaryStore.normalizeTerm(value)
        draftReplacementTerms.removeAll { DictionaryStore.normalizeTerm($0) == normalized }
        errorMessage = nil
    }

    private func reloadContent() {
        dictionaryStore.reload()
        dictionarySuggestionStore.reload()
        reloadGroups()
        historyScanModelOptions = availableHistoryScanModels()
        suggestionFilterDraft = dictionarySuggestionStore.filterSettings
        selectedHistoryScanModelID = resolvedDefaultHistoryScanModelID(from: historyScanModelOptions)
    }

    private func openDictionaryAdvancedSettings() {
        let options = availableHistoryScanModels()
        historyScanModelOptions = options
        suggestionFilterDraft = dictionarySuggestionStore.filterSettings
        selectedHistoryScanModelID = resolvedDefaultHistoryScanModelID(from: options)
        showDictionaryAdvancedSettings = true
    }

    private func handleOneClickIngestButton() {
        if historyScanProgress.isRunning {
            requestSuggestionIngestCancellation()
        } else {
            runSuggestionIngest()
        }
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
        panel.nameFieldStringValue = "Voxt-Dictionary.json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try dictionaryStore.exportTransferJSONString()
            try text.write(to: url, atomically: true, encoding: .utf8)
            dictionaryTransferMessage = String(localized: "Dictionary exported successfully.")
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
            reloadContent()
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
            return
        }
        availableGroups = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func selectedGroupName() -> String? {
        guard let selectedGroupID else { return nil }
        return groupName(for: selectedGroupID)
    }

    private func groupName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return availableGroups.first(where: { $0.id == id })?.name
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
        if pendingHistoryScanCount > 0 {
            return AppLocalization.format(
                "Last scan %@ processed %d history records and added %d dictionary terms. %d new history records are waiting.",
                timeText,
                progress.lastProcessedCount,
                progress.lastNewSuggestionCount,
                pendingHistoryScanCount
            )
        }
        return AppLocalization.format(
            "Last scan %@ processed %d history records and added %d dictionary terms.",
            timeText,
            progress.lastProcessedCount,
            progress.lastNewSuggestionCount
        )
    }
}

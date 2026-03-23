import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

struct DictionarySettingsView: View {
    @AppStorage(AppPreferenceKey.dictionaryRecognitionEnabled) private var dictionaryRecognitionEnabled = true
    @AppStorage(AppPreferenceKey.dictionaryAutoLearningEnabled) private var dictionaryAutoLearningEnabled = true
    @AppStorage(AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled) private var dictionaryHighConfidenceCorrectionEnabled = true
    @AppStorage(AppPreferenceKey.dictionarySuggestionIngestModelOptionID) private var preferredHistoryScanModelID = ""

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    let availableHistoryScanModels: () -> [DictionaryHistoryScanModelOption]
    let onIngestSuggestionsFromHistory: (DictionaryHistoryScanRequest, Bool) -> Void
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
    @State private var showSuggestionIngestDialog = false
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
                dictionaryRecognitionEnabled: dictionaryRecognitionEnabled
            )
        }
        .sheet(isPresented: $showSuggestionIngestDialog) {
            DictionarySuggestionIngestDialog(
                pendingHistoryScanCount: pendingHistoryScanCount,
                localModelOptions: localHistoryScanModelOptions,
                remoteModelOptions: remoteHistoryScanModelOptions,
                selectedModelOption: selectedHistoryScanModelOption,
                selectedModelID: $selectedHistoryScanModelID,
                draftPrompt: $suggestionFilterDraft.prompt,
                isPresented: $showSuggestionIngestDialog,
                onIngest: runSuggestionIngest
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
                        showDictionaryAdvancedSettings = true
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

                    Spacer(minLength: 12)

                    Toggle("Auto Ingest", isOn: $dictionaryAutoLearningEnabled)
                        .controlSize(.small)

                    Button(dictionarySuggestionStore.historyScanProgress.isRunning ? String(localized: "Scanning...") : String(localized: "One-Click Ingest")) {
                        presentSuggestionIngestDialog()
                    }
                    .controlSize(.small)
                    .disabled(dictionarySuggestionStore.historyScanProgress.isRunning || pendingHistoryScanCount == 0)

                    Divider()
                        .frame(height: 16)

                    Button("Import") {
                        importDictionary()
                    }
                    .controlSize(.small)

                    Button("Export") {
                        exportDictionary()
                    }
                    .controlSize(.small)
                }

                Text("When enabled, new history records are scanned automatically and the extracted terms are written directly into the dictionary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if dictionarySuggestionStore.historyScanProgress.isRunning {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(
                            value: Double(dictionarySuggestionStore.historyScanProgress.processedCount),
                            total: Double(max(dictionarySuggestionStore.historyScanProgress.totalCount, 1))
                        )
                        Text(historyScanStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = dictionarySuggestionStore.historyScanProgress.errorMessage,
                          !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let lastRunAt = dictionarySuggestionStore.historyScanProgress.lastRunAt {
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

                    Button("Clean All", role: .destructive) {
                        dictionaryStore.clearAll()
                    }
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
                .textFieldStyle(.roundedBorder)

            Picker("Group", selection: $selectedGroupID) {
                Text("Global").tag(Optional<UUID>.none)
                if let selectedGroupID, groupName(for: selectedGroupID) == nil {
                    Text("Missing Group").tag(Optional(selectedGroupID))
                }
                ForEach(availableGroups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
            .pickerStyle(.menu)

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
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addDraftReplacementTerm)

                    Button("Add") {
                        addDraftReplacementTerm()
                    }
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

            HStack {
                Spacer()
                Button("Cancel") {
                    self.dialog = nil
                }
                Button(dialog.confirmButtonTitle) {
                    save(dialog: dialog)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
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
        selectedHistoryScanModelID = resolvedDefaultHistoryScanModelID(from: historyScanModelOptions)
    }

    private func presentSuggestionIngestDialog() {
        let options = availableHistoryScanModels()
        guard !options.isEmpty else {
            suggestionActionMessage = AppLocalization.localizedString(
                "No configured local or remote model is available for dictionary ingestion. Configure one in Model settings first."
            )
            return
        }

        historyScanModelOptions = options
        suggestionFilterDraft = dictionarySuggestionStore.filterSettings
        selectedHistoryScanModelID = resolvedDefaultHistoryScanModelID(from: options)
        suggestionActionMessage = nil
        showSuggestionIngestDialog = true
    }

    private func runSuggestionIngest() {
        guard !selectedHistoryScanModelID.isEmpty else { return }
        suggestionActionMessage = nil
        preferredHistoryScanModelID = selectedHistoryScanModelID
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
        showSuggestionIngestDialog = false
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
            dictionarySuggestionStore.historyScanProgress.processedCount,
            dictionarySuggestionStore.historyScanProgress.totalCount,
            dictionarySuggestionStore.historyScanProgress.newSuggestionCount,
            dictionarySuggestionStore.historyScanProgress.duplicateCount
        )
    }

    private func historyScanSummaryText(lastRunAt: Date) -> String {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        let timeText = relative.localizedString(for: lastRunAt, relativeTo: Date())
        let progress = dictionarySuggestionStore.historyScanProgress
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

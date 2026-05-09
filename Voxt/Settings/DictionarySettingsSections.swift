import SwiftUI

struct DictionarySettingsHeaderCard: View {
    let historyScanProgress: DictionaryHistoryScanProgress
    let suggestionActionMessage: String?
    let onOpenIngest: () -> Void
    let onOpenSettings: () -> Void
    let onImport: () -> Void
    let onExport: () -> Void
    let historyScanSummaryText: (Date) -> String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    Button(AppLocalization.localizedString("One-Click Ingest")) {
                        onOpenIngest()
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Spacer(minLength: 12)

                    Button {
                        onOpenSettings()
                    } label: {
                        Text(AppLocalization.localizedString("Settings"))
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                    .help(AppLocalization.localizedString("Dictionary Advanced Settings"))

                    DictionaryHeaderActionMenuButton(
                        actions: [
                            DictionaryHeaderMenuAction(title: AppLocalization.localizedString("Import"), handler: onImport),
                            DictionaryHeaderMenuAction(title: AppLocalization.localizedString("Export"), handler: onExport)
                        ]
                    )
                    .frame(width: 28, height: 28)
                    .help(AppLocalization.localizedString("More"))
                }

                DictionarySettingsHeaderStatus(
                    historyScanProgress: historyScanProgress,
                    suggestionActionMessage: suggestionActionMessage,
                    historyScanSummaryText: historyScanSummaryText
                )
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DictionarySettingsHeaderStatus: View {
    let historyScanProgress: DictionaryHistoryScanProgress
    let suggestionActionMessage: String?
    let historyScanSummaryText: (Date) -> String

    var body: some View {
        if let errorMessage = historyScanProgress.errorMessage,
           !errorMessage.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(AppLocalization.localizedString("Review the ingest prompt in One-Click Ingest, then try again."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let lastRunAt = historyScanProgress.lastRunAt {
            Text(historyScanSummaryText(lastRunAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let suggestionActionMessage, !suggestionActionMessage.isEmpty {
            Text(suggestionActionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DictionaryEntriesCard: View {
    @Binding var selectedFilter: DictionaryFilter
    let pagedVisibleEntries: [DictionaryEntry]
    let visibleEntries: [DictionaryEntry]
    let hasMoreVisibleEntries: Bool
    let dictionaryTransferMessage: String?
    let scopeLabel: (DictionaryEntry) -> String
    let scopeIsMissing: (DictionaryEntry) -> Bool
    let onCreate: () -> Void
    let onClearAll: () -> Void
    let onEdit: (DictionaryEntry) -> Void
    let onDelete: (DictionaryEntry) -> Void
    let onLoadMore: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DictionaryFilterPicker(selectedFilter: $selectedFilter)

                    Spacer(minLength: 12)

                    Button(AppLocalization.localizedString("Create")) {
                        onCreate()
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Button(AppLocalization.localizedString("Clean All"), role: .destructive) {
                        onClearAll()
                    }
                    .buttonStyle(SettingsStatusButtonStyle(tint: .red))
                    .disabled(visibleEntries.isEmpty)
                }

                if visibleEntries.isEmpty {
                    Text(AppLocalization.localizedString("No dictionary terms yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(pagedVisibleEntries) { entry in
                                DictionaryRow(
                                    entry: entry,
                                    scopeLabel: scopeLabel(entry),
                                    scopeIsMissing: scopeIsMissing(entry),
                                    onEdit: { onEdit(entry) },
                                    onDelete: { onDelete(entry) }
                                )
                                .onAppear {
                                    if entry.id == pagedVisibleEntries.last?.id {
                                        onLoadMore()
                                    }
                                }
                            }

                            if hasMoreVisibleEntries {
                                Button(AppLocalization.localizedString("Load More")) {
                                    onLoadMore()
                                }
                                .buttonStyle(SettingsPillButtonStyle())
                                .padding(.top, 4)
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
}


import SwiftUI
import AppKit

struct HistorySettingsView: View {
    @AppStorage(AppPreferenceKey.historyEnabled) private var historyEnabled = false
    @AppStorage(AppPreferenceKey.historyRetentionPeriod) private var historyRetentionPeriodRaw = HistoryRetentionPeriod.thirtyDays.rawValue

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @State private var copiedEntryID: UUID?
    @State private var showRetentionInfo = false

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        HistoryRetentionPeriod(rawValue: historyRetentionPeriodRaw) ?? .thirtyDays
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Toggle("Enable Transcription History", isOn: $historyEnabled)
                        Spacer(minLength: 12)
                        HStack(spacing: 4) {
                            Text("Retention")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button {
                                showRetentionInfo.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showRetentionInfo, arrowEdge: .top) {
                                Text(AppLocalization.localizedString("History older than the selected retention time is automatically deleted."))
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(width: 280, alignment: .leading)
                            }
                        }
                        Picker("Retention", selection: $historyRetentionPeriodRaw) {
                            ForEach(HistoryRetentionPeriod.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(!historyEnabled)
                    }

                    Text("When enabled, each completed transcription result will be saved in local history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            HistoryListSection(
                historyEnabled: historyEnabled,
                entries: historyStore.entries,
                hasMore: historyStore.hasMore,
                copiedEntryID: copiedEntryID,
                onClearAll: clearAllHistory,
                onCopy: copyEntry,
                onDelete: deleteEntry,
                onLoadNextPage: historyStore.loadNextPage
            )
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            if HistoryRetentionPeriod(rawValue: historyRetentionPeriodRaw) == nil {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.thirtyDays.rawValue
            }
            historyStore.reload()
            historyStore.updateRetentionPolicy()
        }
        .onChange(of: historyEnabled) { _, _ in
            historyStore.updateRetentionPolicy()
            historyStore.reload()
        }
        .onChange(of: historyRetentionPeriodRaw) { _, newValue in
            if HistoryRetentionPeriod(rawValue: newValue) == nil {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.thirtyDays.rawValue
            }
            historyStore.updateRetentionPolicy()
            historyStore.reload()
        }
    }

    private func clearAllHistory() {
        copiedEntryID = nil
        historyStore.clearAll()
    }

    private func copyEntry(_ entry: TranscriptionHistoryEntry) {
        copyToPasteboard(entry.text)
        copiedEntryID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedEntryID == entry.id {
                copiedEntryID = nil
            }
        }
    }

    private func deleteEntry(_ id: UUID) {
        historyStore.delete(id: id)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

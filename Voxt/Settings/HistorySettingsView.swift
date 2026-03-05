import SwiftUI
import AppKit

struct HistorySettingsView: View {
    @AppStorage(AppPreferenceKey.historyEnabled) private var historyEnabled = false

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @State private var copiedEntryID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Transcription History", isOn: $historyEnabled)
                    Text("When enabled, each completed transcription result will be saved in local history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("History")
                            .font(.headline)
                        Spacer()
                        Button("Clean All", role: .destructive) {
                            copiedEntryID = nil
                            historyStore.clearAll()
                        }
                        .controlSize(.small)
                        .disabled(!historyEnabled || historyStore.entries.isEmpty)
                    }

                    if !historyEnabled {
                        Text("History is currently disabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if historyStore.entries.isEmpty {
                        Text("No history yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(historyStore.entries) { entry in
                                    HistoryRow(
                                        entry: entry,
                                        isCopied: copiedEntryID == entry.id,
                                        onCopy: {
                                            copyToPasteboard(entry.text)
                                            copiedEntryID = entry.id
                                            Task {
                                                try? await Task.sleep(for: .seconds(1.2))
                                                if copiedEntryID == entry.id {
                                                    copiedEntryID = nil
                                                }
                                            }
                                        },
                                        onDelete: {
                                            historyStore.delete(id: entry.id)
                                        }
                                    )
                                    .onAppear {
                                        if entry.id == historyStore.entries.last?.id {
                                            historyStore.loadNextPage()
                                        }
                                    }
                                }

                                if historyStore.hasMore {
                                    Button("Load More") {
                                        historyStore.loadNextPage()
                                    }
                                    .controlSize(.small)
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
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            historyStore.reload()
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct HistoryRow: View {
    @Environment(\.locale) private var locale

    let entry: TranscriptionHistoryEntry
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var showModelInfo = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    HStack(spacing: 6) {
                        historyBadge
                        Text(metadataText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCopied {
                Text("Copied")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button {
                showModelInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showModelInfo, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcription Details")
                        .font(.headline)
                    detailLine(labelKey: "Engine", value: entry.transcriptionEngine)
                    detailLine(labelKey: "Model", value: entry.transcriptionModel)
                    detailLine(labelKey: "Enhancement", value: entry.enhancementMode)
                    detailLine(labelKey: "Enhancer Model", value: entry.enhancementModel)
                    detailLine(
                        labelKey: "Transcription Processing",
                        value: formattedDuration(entry.transcriptionProcessingDurationSeconds) ?? String(localized: "N/A")
                    )
                    detailLine(
                        labelKey: "LLM Duration",
                        value: formattedDuration(entry.llmDurationSeconds) ?? String(localized: "N/A")
                    )
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .frame(width: 340)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func detailLine(labelKey: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(labelKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private var metadataText: String {
        let dateText = entry.createdAt.formatted(
            .dateTime
                .locale(locale)
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
        guard let audioDuration = formattedDuration(entry.audioDurationSeconds) else {
            return dateText
        }
        let format = NSLocalizedString("%@ · Audio: %@", comment: "")
        return String(format: format, locale: locale, dateText, audioDuration)
    }

    private var historyBadge: some View {
        Group {
            if entry.isTranslation {
                Text("Translation")
            } else {
                Text("Normal")
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(entry.isTranslation ? Color.blue.opacity(0.16) : Color.gray.opacity(0.16))
        )
        .foregroundStyle(entry.isTranslation ? Color.blue : Color.secondary)
    }

    private func formattedDuration(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        if seconds < 1 {
            let format = NSLocalizedString("%d ms", comment: "")
            return String(format: format, locale: locale, Int(seconds * 1000))
        }
        if seconds < 60 {
            let format = NSLocalizedString("%.1f s", comment: "")
            return String(format: format, locale: locale, seconds)
        }
        let minutes = Int(seconds) / 60
        let remain = Int(seconds) % 60
        let format = NSLocalizedString("%dm %ds", comment: "")
        return String(format: format, locale: locale, minutes, remain)
    }
}

import SwiftUI
import AppKit

private enum HistoryFilterTab: String, CaseIterable, Identifiable {
    case all
    case transcription
    case translation
    case rewrite
    case meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .transcription:
            return String(localized: "转录")
        case .translation:
            return String(localized: "翻译")
        case .rewrite:
            return String(localized: "转写")
        case .meeting:
            return String(localized: "会议")
        }
    }

    func matches(_ entry: TranscriptionHistoryEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .transcription:
            return entry.kind == .normal
        case .translation:
            return entry.kind == .translation
        case .rewrite:
            return entry.kind == .rewrite
        case .meeting:
            return entry.kind == .meeting
        }
    }
}

struct HistorySettingsView: View {
    @AppStorage(AppPreferenceKey.historyEnabled) private var historyEnabled = false
    @AppStorage(AppPreferenceKey.historyRetentionPeriod) private var historyRetentionPeriodRaw = HistoryRetentionPeriod.thirtyDays.rawValue

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    @State private var copiedEntryID: UUID?
    @State private var showRetentionInfo = false
    @State private var selectedFilter: HistoryFilterTab = .all

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        HistoryRetentionPeriod(rawValue: historyRetentionPeriodRaw) ?? .thirtyDays
    }

    private var filteredEntries: [TranscriptionHistoryEntry] {
        historyStore.entries.filter { selectedFilter.matches($0) }
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

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        HistoryFilterTabPicker(selectedTab: $selectedFilter)
                        Spacer(minLength: 12)
                        Button("Clean All", role: .destructive) {
                            copiedEntryID = nil
                            historyStore.clearAll()
                        }
                        .controlSize(.small)
                        .disabled(historyStore.entries.isEmpty)
                    }

                    if historyStore.entries.isEmpty && !historyEnabled {
                        Text("History is currently disabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if historyStore.entries.isEmpty {
                        Text("No history yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if filteredEntries.isEmpty {
                        Text("No entries in this category yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredEntries) { entry in
                                    HistoryRow(
                                        entry: entry,
                                        meetingAudioURL: historyStore.meetingAudioURL(for: entry),
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
                                        if entry.id == filteredEntries.last?.id {
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

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct HistoryFilterTabPicker: View {
    @Binding var selectedTab: HistoryFilterTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilterTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedTab == tab ? Color.accentColor.opacity(0.14) : .clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selectedTab == tab ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
                }
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct HistoryRow: View {
    @Environment(\.locale) private var locale

    let entry: TranscriptionHistoryEntry
    let meetingAudioURL: URL?
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
                        Spacer(minLength: 8)
                        if hasDictionaryActivity {
                            HStack(spacing: 6) {
                                if !entry.dictionaryHitTerms.isEmpty {
                                    activityChip(
                                        label: AppLocalization.format("Dictionary %d", entry.dictionaryHitTerms.count),
                                        color: .secondary
                                    )
                                }
                                if !entry.dictionaryCorrectedTerms.isEmpty {
                                    activityChip(
                                        label: AppLocalization.format("Corrected %d", entry.dictionaryCorrectedTerms.count),
                                        color: .blue
                                    )
                                }
                            }
                        }
                    }

                    if !entry.dictionaryHitTerms.isEmpty {
                        Text("\(String(localized: "Matched dictionary terms")): \(matchedTermsPreview)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        showModelInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showModelInfo, arrowEdge: .trailing) {
                        HistoryInfoPopover(entry: entry, locale: locale, hasDictionaryActivity: hasDictionaryActivity)
                    }

                    if entry.kind == .meeting {
                        Button(String(localized: "详情")) {
                            MeetingDetailWindowManager.shared.presentHistoryMeeting(
                                entry: entry,
                                audioURL: meetingAudioURL,
                                translationHandler: { @MainActor text, targetLanguage in
                                    guard let appDelegate = NSApp.delegate as? AppDelegate else { return text }
                                    return try await appDelegate.translateMeetingRealtimeText(text, targetLanguage: targetLanguage)
                                }
                            )
                        }
                        .controlSize(.small)
                    }

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }

                if isCopied {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
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

    private var hasDictionaryActivity: Bool {
        !entry.dictionaryHitTerms.isEmpty ||
        !entry.dictionaryCorrectedTerms.isEmpty
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
            if entry.kind == .translation {
                Text("Translation")
            } else if entry.kind == .rewrite {
                Text("Rewrite")
            } else if entry.kind == .meeting {
                Text("Meeting")
            } else {
                Text("Normal")
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(historyBadgeColor.opacity(0.16))
        )
        .foregroundStyle(historyBadgeColor)
    }

    private var historyBadgeColor: Color {
        switch entry.kind {
        case .normal:
            return .secondary
        case .translation:
            return .blue
        case .rewrite:
            return .orange
        case .meeting:
            return .green
        }
    }

    private func activityChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .foregroundStyle(color)
    }

    private var matchedTermsPreview: String {
        let previewTerms = Array(entry.dictionaryHitTerms.prefix(3))
        let base = previewTerms.joined(separator: ", ")
        let remainingCount = entry.dictionaryHitTerms.count - previewTerms.count
        guard remainingCount > 0 else { return base }
        return "\(base) +\(remainingCount)"
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

private struct HistoryInfoPopover: View {
    let entry: TranscriptionHistoryEntry
    let locale: Locale
    let hasDictionaryActivity: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Transcription Details")
                    .font(.headline)
                detailLine(labelKey: "Engine", value: entry.transcriptionEngine)
                detailLine(labelKey: "Model", value: entry.transcriptionModel)
                optionalDetailLine(labelKey: "Remote ASR Provider", value: entry.remoteASRProvider)
                optionalDetailLine(labelKey: "Remote ASR Model", value: entry.remoteASRModel)
                optionalDetailLine(labelKey: "Remote ASR Endpoint", value: entry.remoteASREndpoint)
                detailLine(labelKey: "Enhancement", value: entry.enhancementMode)
                detailLine(labelKey: "Enhancer Model", value: entry.enhancementModel)
                optionalDetailLine(labelKey: "Remote LLM Provider", value: entry.remoteLLMProvider)
                optionalDetailLine(labelKey: "Remote LLM Model", value: entry.remoteLLMModel)
                optionalDetailLine(labelKey: "Remote LLM Endpoint", value: entry.remoteLLMEndpoint)
                optionalDetailLine(labelKey: "Focused App", value: entry.focusedAppName)
                optionalDetailLine(labelKey: "App Group", value: entry.matchedAppGroupName)
                optionalDetailLine(labelKey: "URL Group", value: entry.matchedURLGroupName)
                optionalDetailLine(
                    labelKey: "ASR Processing",
                    value: formattedDuration(entry.transcriptionProcessingDurationSeconds)
                )
                optionalDetailLine(
                    labelKey: "LLM Duration",
                    value: formattedDuration(entry.llmDurationSeconds)
                )

                if let whisperWordTimings = entry.whisperWordTimings,
                   !whisperWordTimings.isEmpty {
                    Divider()
                        .padding(.vertical, 2)
                    Text("Whisper Timestamps")
                        .font(.headline)

                    ForEach(Array(whisperWordTimings.enumerated()), id: \.offset) { _, timing in
                        detailLine(
                            labelKey: LocalizedStringKey(timeRangeLabel(for: timing)),
                            value: timing.word
                        )
                    }
                }

                if let meetingSegments = entry.meetingSegments,
                   !meetingSegments.isEmpty {
                    Divider()
                        .padding(.vertical, 2)
                    Text("Meeting Segments")
                        .font(.headline)

                    ForEach(meetingSegments) { segment in
                        detailLine(
                            labelKey: LocalizedStringKey(
                                "\(MeetingTranscriptFormatter.timestampString(for: segment.startSeconds)) · \(segment.speaker.displayTitle)"
                            ),
                            value: segment.text
                        )
                    }
                }

                if hasDictionaryActivity {
                    Divider()
                        .padding(.vertical, 2)
                    Text("Dictionary")
                        .font(.headline)

                    if !entry.dictionaryHitTerms.isEmpty {
                        termSection(title: "Matched dictionary terms", values: entry.dictionaryHitTerms)
                    }
                    if !entry.dictionaryCorrectedTerms.isEmpty {
                        termSection(title: "Corrected terms", values: entry.dictionaryCorrectedTerms)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(width: 360, alignment: .leading)
        }
        .frame(maxHeight: 460)
    }

    private func termSection(title: LocalizedStringKey, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.subheadline)
            }
        }
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

    @ViewBuilder
    private func optionalDetailLine(labelKey: LocalizedStringKey, value: String?) -> some View {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            detailLine(labelKey: labelKey, value: trimmed)
        }
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

    private func timeRangeLabel(for timing: WhisperHistoryWordTiming) -> String {
        String(
            format: NSLocalizedString("%.2fs → %.2fs", comment: ""),
            locale: locale,
            timing.startSeconds,
            timing.endSeconds
        )
    }
}

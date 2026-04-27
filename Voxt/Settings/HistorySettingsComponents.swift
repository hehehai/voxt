import SwiftUI
import AppKit

enum HistoryFilterTab: String, CaseIterable, Identifiable {
    case all
    case transcription
    case translation
    case rewrite
    case meeting
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .transcription:
            return String(localized: "Transcription")
        case .translation:
            return String(localized: "Translation")
        case .rewrite:
            return String(localized: "Rewrite")
        case .meeting:
            return String(localized: "Meeting")
        case .note:
            return String(localized: "Notes")
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
        case .note:
            return false
        }
    }
}

struct HistoryFilterTabPicker: View {
    @Binding var selectedTab: HistoryFilterTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilterTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(SettingsSegmentedButtonStyle(isSelected: selectedTab == tab))
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}

struct HistoryRow: View {
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
                        HistoryInfoPopover(entry: entry, locale: locale)
                    }

                    if supportsDetail {
                        Button(String(localized: "Detail")) {
                            openDetailWindow()
                        }
                        .buttonStyle(SettingsPillButtonStyle())
                    }

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }

                if isCopied {
                    Text(String(localized: "Copied"))
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

    private var supportsDetail: Bool {
        TranscriptionHistoryConversationSupport.supportsDetail(for: entry.kind)
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
                Text(String(localized: "Translation"))
            } else if entry.kind == .rewrite {
                Text(String(localized: "Rewrite"))
            } else if entry.kind == .meeting {
                Text(String(localized: "Meeting"))
            } else {
                Text(String(localized: "Transcription"))
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

    private func openDetailWindow() {
        guard supportsDetail else { return }

        if entry.kind == .meeting {
            guard let appDelegate = AppDelegate.shared else {
                VoxtLog.warning("History detail open skipped: AppDelegate.shared was unavailable.")
                return
            }
            MeetingDetailWindowManager.shared.presentHistoryMeeting(
                entry: entry,
                audioURL: meetingAudioURL,
                initialSummarySettings: appDelegate.currentMeetingSummarySettingsSnapshot(),
                summaryModelOptionsProvider: { @MainActor in
                    appDelegate.meetingSummaryModelOptions()
                },
                summarySettingsProvider: { @MainActor in
                    appDelegate.currentMeetingSummarySettingsSnapshot()
                },
                translationHandler: { @MainActor text, targetLanguage in
                    return try await appDelegate.translateMeetingRealtimeText(text, targetLanguage: targetLanguage)
                },
                summaryStatusProvider: { @MainActor settings in
                    return appDelegate.meetingSummaryProviderStatus(settings: settings)
                },
                summaryGenerator: { @MainActor transcript, settings in
                    return try await appDelegate.generateMeetingSummary(transcript: transcript, settings: settings)
                },
                summaryPersistence: { @MainActor entryID, summary in
                    return appDelegate.persistMeetingSummary(summary, for: entryID)
                },
                summaryChatAnswerer: { @MainActor transcript, summary, history, question, settings in
                    return try await appDelegate.answerMeetingSummaryFollowUp(
                        transcript: transcript,
                        summary: summary,
                        history: history,
                        question: question,
                        settings: settings
                    )
                },
                summaryChatPersistence: { @MainActor entryID, messages in
                    return appDelegate.persistMeetingSummaryChatMessages(messages, for: entryID)
                }
            )
            return
        }

        guard let appDelegate = AppDelegate.shared else {
            VoxtLog.warning("Transcription detail open skipped: AppDelegate.shared was unavailable.")
            return
        }
        appDelegate.showTranscriptionDetailWindow(for: entry)
    }
}

private struct HistoryInfoPopover: View {
    let entry: TranscriptionHistoryEntry
    let locale: Locale

    var body: some View {
        TranscriptionDetailContentView(
            entry: entry,
            locale: locale,
            style: .popover
        )
        .frame(maxHeight: 460)
    }
}

struct NoteHistoryRow: View {
    let item: VoxtNoteItem
    let isCopied: Bool
    let onCopy: () -> Void
    let onToggleCompletion: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(RelativeNoteTimestampFormatter.noteHistoryTimestamp(for: item.createdAt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        noteStatusBadge
                    }

                    Text(item.text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    Button(action: onToggleCompletion) {
                        Image(systemName: item.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }

                if isCopied {
                    Text(String(localized: "Copied"))
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

    private var noteStatusBadge: some View {
        Text(item.isCompleted ? AppLocalization.localizedString("Completed") : AppLocalization.localizedString("Incomplete"))
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill((item.isCompleted ? Color.green : Color.orange).opacity(0.16))
            )
            .foregroundStyle(item.isCompleted ? Color.green : Color.orange)
    }
}

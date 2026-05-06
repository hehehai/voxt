import SwiftUI

enum TranscriptionDetailPresentationStyle {
    case popover
    case window
}

struct TranscriptionDetailContentView: View {
    let entry: TranscriptionHistoryEntry
    let audioURL: URL?
    let locale: Locale
    let style: TranscriptionDetailPresentationStyle

    @StateObject private var playbackController: HistoryAudioPlaybackController

    init(
        entry: TranscriptionHistoryEntry,
        audioURL: URL?,
        locale: Locale,
        style: TranscriptionDetailPresentationStyle
    ) {
        self.entry = entry
        self.audioURL = audioURL
        self.locale = locale
        self.style = style
        _playbackController = StateObject(wrappedValue: HistoryAudioPlaybackController(audioURL: audioURL))
    }

    private var preferredContentWidth: CGFloat? {
        style == .popover ? 360 : nil
    }

    private var stackSpacing: CGFloat {
        style == .popover ? 10 : 14
    }

    private var contentPadding: CGFloat {
        style == .popover ? 8 : 18
    }

    private var sectionSpacing: CGFloat {
        style == .popover ? 8 : 10
    }

    private var sectionTitleFont: Font {
        style == .popover ? .headline : .system(size: 15, weight: .semibold)
    }

    private var sectionCardFill: Color {
        style == .popover
            ? Color.clear
            : Color(nsColor: .controlBackgroundColor).opacity(0.78)
    }

    private var hasDictionaryActivity: Bool {
        !entry.dictionaryHitTerms.isEmpty ||
        !entry.dictionaryCorrectedTerms.isEmpty ||
        !entry.dictionarySuggestedTerms.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: stackSpacing) {
                detailSection(title: String(localized: "Text")) {
                    Text(entry.text)
                        .font(.system(size: style == .popover ? 13 : 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                detailSection(title: String(localized: "Metadata")) {
                    detailLine(label: String(localized: "Type"), value: historyKindTitle(entry.kind))
                    detailLine(label: String(localized: "Created At"), value: formattedDate(entry.createdAt))
                    detailLine(label: String(localized: "Engine"), value: entry.transcriptionEngine)
                    detailLine(label: String(localized: "Model"), value: entry.transcriptionModel)
                    detailLine(label: modeMetadataLabel(for: entry.kind), value: entry.enhancementMode)
                    detailLine(label: modelMetadataLabel(for: entry.kind), value: entry.enhancementModel)
                    optionalDetailLine(label: String(localized: "Audio Duration"), value: formattedDuration(entry.audioDurationSeconds))
                    optionalDetailLine(label: String(localized: "ASR Processing"), value: formattedDuration(entry.transcriptionProcessingDurationSeconds))
                    optionalDetailLine(label: String(localized: "LLM Duration"), value: formattedDuration(entry.llmDurationSeconds))
                    optionalDetailLine(label: String(localized: "Remote ASR Provider"), value: entry.remoteASRProvider)
                    optionalDetailLine(label: String(localized: "Remote ASR Model"), value: entry.remoteASRModel)
                    optionalDetailLine(label: String(localized: "Remote ASR Endpoint"), value: entry.remoteASREndpoint)
                    optionalDetailLine(label: String(localized: "Remote LLM Provider"), value: entry.remoteLLMProvider)
                    optionalDetailLine(label: String(localized: "Remote LLM Model"), value: entry.remoteLLMModel)
                    optionalDetailLine(label: String(localized: "Remote LLM Endpoint"), value: entry.remoteLLMEndpoint)
                    optionalDetailLine(label: String(localized: "Focused App"), value: entry.focusedAppName)
                    optionalDetailLine(label: String(localized: "Focused App Bundle ID"), value: entry.focusedAppBundleID)
                    optionalDetailLine(label: String(localized: "Matched Group"), value: entry.matchedGroupName)
                    optionalDetailLine(label: String(localized: "App Group"), value: entry.matchedAppGroupName)
                    optionalDetailLine(label: String(localized: "URL Group"), value: entry.matchedURLGroupName)
                }

                if playbackController.isAvailable {
                    detailSection(title: String(localized: "Audio")) {
                        HistoryAudioPlayerView(
                            controller: playbackController,
                            compact: style == .popover
                        )
                    }
                }

                if let whisperWordTimings = entry.whisperWordTimings,
                   !whisperWordTimings.isEmpty {
                    detailSection(title: String(localized: "Whisper Timestamps")) {
                        ForEach(Array(whisperWordTimings.enumerated()), id: \.offset) { _, timing in
                            detailLine(
                                label: timeRangeLabel(for: timing),
                                value: timing.word
                            )
                        }
                    }
                }

                if let meetingSegments = entry.meetingSegments,
                   !meetingSegments.isEmpty {
                    detailSection(title: String(localized: "Meeting Segments")) {
                        ForEach(meetingSegments) { segment in
                            detailLine(
                                label: "\(MeetingTranscriptFormatter.timestampString(for: segment.startSeconds)) · \(segment.speaker.displayTitle)",
                                value: segment.text
                            )
                        }
                    }
                }

                if hasDictionaryActivity {
                    detailSection(title: String(localized: "Dictionary")) {
                        if !entry.dictionaryHitTerms.isEmpty {
                            detailTagGroup(
                                title: String(localized: "Matched dictionary terms"),
                                values: entry.dictionaryHitTerms
                            )
                        }
                        if !entry.dictionaryCorrectedTerms.isEmpty {
                            detailTagGroup(
                                title: String(localized: "Corrected terms"),
                                values: entry.dictionaryCorrectedTerms
                            )
                        }
                        if !entry.dictionarySuggestedTerms.isEmpty {
                            detailTagGroup(
                                title: String(localized: "Suggested terms"),
                                values: entry.dictionarySuggestedTerms.map(\.term)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, contentPadding)
            .padding(.vertical, style == .popover ? 10 : 18)
            .frame(width: preferredContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: audioURL?.path) { _, _ in
            playbackController.loadAudio(audioURL)
        }
    }

    @ViewBuilder
    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text(title)
                .font(sectionTitleFont)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(style == .popover ? 0 : 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(sectionCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style == .popover ? Color.clear : Color(nsColor: .quaternaryLabelColor).opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func detailLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func optionalDetailLine(label: String, value: String?) -> some View {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            detailLine(label: label, value: trimmed)
        }
    }

    private func detailTagGroup(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(values.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func historyKindTitle(_ kind: TranscriptionHistoryKind) -> String {
        switch kind {
        case .normal:
            return String(localized: "Transcription")
        case .translation:
            return String(localized: "Translation")
        case .rewrite:
            return String(localized: "Rewrite")
        case .meeting:
            return String(localized: "Meeting")
        }
    }

    private func modeMetadataLabel(for kind: TranscriptionHistoryKind) -> String {
        switch kind {
        case .normal:
            return String(localized: "Enhancement")
        case .translation:
            return String(localized: "Translation Mode")
        case .rewrite:
            return String(localized: "Rewrite Mode")
        case .meeting:
            return String(localized: "Summary Mode")
        }
    }

    private func modelMetadataLabel(for kind: TranscriptionHistoryKind) -> String {
        switch kind {
        case .normal:
            return String(localized: "Enhancer Model")
        case .translation:
            return String(localized: "Translation Model")
        case .rewrite:
            return String(localized: "Rewrite Model")
        case .meeting:
            return String(localized: "Summary Model")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(locale)
                .year()
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
                .second()
        )
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

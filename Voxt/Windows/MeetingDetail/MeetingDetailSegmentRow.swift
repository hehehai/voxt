// MeetingDetailSegmentRow.swift
// Segment and speaker-header rows for meeting detail transcript lists.

import SwiftUI

struct MeetingDetailSegmentRow: View, Equatable {
    let segment: MeetingTranscriptSegment
    let speakerTitle: String
    let isActive: Bool
    let showsTranslation: Bool
    let isSearchMatch: Bool

    @State private var isHovered = false
    @State private var didCopy = false
    @State private var copyFeedbackToken = UUID()

    static func == (lhs: MeetingDetailSegmentRow, rhs: MeetingDetailSegmentRow) -> Bool {
        lhs.segment == rhs.segment
            && lhs.speakerTitle == rhs.speakerTitle
            && lhs.isActive == rhs.isActive
            && lhs.showsTranslation == rhs.showsTranslation
            && lhs.isSearchMatch == rhs.isSearchMatch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(MeetingTranscriptFormatter.timestampString(for: segment.startSeconds))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(speakerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        segment.speaker == .me
                            ? Color(red: 0.16, green: 0.47, blue: 0.88)
                            : Color(red: 0.12, green: 0.58, blue: 0.32)
                    )

                Spacer(minLength: 8)
            }

            Text(segment.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.94))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if showsTranslation,
               let translatedText = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !translatedText.isEmpty {
                Text(translatedText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else if showsTranslation, segment.isTranslationPending {
                Text(AppLocalization.localizedString("Translating…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered || didCopy {
                Button(action: copySegmentText) {
                    Group {
                        if didCopy {
                            CopySuccessIconView(color: Color.accentColor)
                        } else {
                            CopyIconView(color: .secondary)
                        }
                    }
                    .frame(width: 13, height: 13)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHovered ? 0.08 : 0.05))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(AppLocalization.localizedString("Copy"))
                .accessibilityLabel(AppLocalization.localizedString("Copy"))
                .padding(.top, 10)
                .padding(.trailing, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private func copySegmentText() {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        copyStringToPasteboard(trimmed)
        copyFeedbackToken = UUID()
        let token = copyFeedbackToken
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard token == copyFeedbackToken else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                didCopy = false
            }
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return speakerAccentColor.opacity(0.16)
        }
        if isSearchMatch {
            return Color.orange.opacity(0.12)
        }
        return speakerAccentColor.opacity(0.06)
    }

    private var borderColor: Color {
        if isActive {
            return speakerAccentColor.opacity(0.32)
        }
        if isSearchMatch {
            return Color.orange.opacity(0.28)
        }
        return speakerAccentColor.opacity(0.16)
    }

    private var speakerAccentColor: Color {
        segment.speaker == .me
            ? Color(red: 0.16, green: 0.47, blue: 0.88)
            : Color(red: 0.12, green: 0.58, blue: 0.32)
    }
}

struct MeetingDetailSpeakerHeaderRow: View, Equatable {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text(AppLocalization.format("%d", count))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(MeetingDetailUIStyle.mutedFillColor)
                )

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

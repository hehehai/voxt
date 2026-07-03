// HistorySettingsComponents.swift
// Provides History Settings Components for history settings.

import SwiftUI
import AppKit

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

enum HistoryFilterTab: String, CaseIterable, Hashable, Identifiable {
    case transcription
    case translation
    case transcript
    case rewrite
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcription:
            return localized("Transcription")
        case .translation:
            return localized("Translation")
        case .transcript:
            return localized("Meeting")
        case .rewrite:
            return localized("Rewrite")
        case .note:
            return localized("Notes")
        }
    }

    func matches(_ entry: TranscriptionHistoryEntry) -> Bool {
        switch self {
        case .transcription:
            return entry.kind == .normal
        case .translation:
            return entry.kind == .translation
        case .transcript:
            return entry.kind == .transcript
        case .rewrite:
            return entry.kind == .rewrite
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
                        .padding(.horizontal, 4)
                }
                .buttonStyle(SettingsSegmentedButtonStyle(isSelected: selectedTab == tab))
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}

struct HistoryDayHeader: View {
    @Environment(\.locale) private var locale
    let date: Date

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        let title = isToday ? localized("Today") : date.formatted(
            .dateTime
                .locale(locale)
                .year()
                .month(.defaultDigits)
                .day()
        )

        Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, 2)
        .padding(.bottom, 5)
    }
}

struct HistoryRow: View {
    @Environment(\.locale) private var locale
    @State private var isHovered = false

    let entry: TranscriptionHistoryEntry
    let audioURL: URL?
    let isCompact: Bool
    let onCopy: () -> Void
    let onShowInfo: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(timeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)
                    .padding(.top, 1)

                Button(action: onCopy) {
                    Text(displayText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .help(localized("Copy"))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 6) {
                Button(action: onShowInfo) {
                    HistoryActionIcon(kind: .detail)
                }
                .buttonStyle(SettingsCompactIconButtonStyle(size: 26))

                Button(role: .destructive, action: onDelete) {
                    HistoryActionIcon(kind: .delete)
                }
                .buttonStyle(SettingsCompactIconButtonStyle(size: 26))
            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .frame(width: 58)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 9.5)
        .padding(.vertical, isCompact ? 5 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HistoryRowStyle.cornerRadius, style: .continuous)
                .fill(HistoryRowStyle.fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HistoryRowStyle.cornerRadius, style: .continuous)
                .strokeBorder(isHovered ? HistoryRowStyle.hoverBorderColor : HistoryRowStyle.borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var displayText: String {
        HistoryCorrectionPresentation.correctedText(
            for: entry.text,
            snapshots: entry.dictionaryCorrectionSnapshots
        )
    }

    private var timeText: String {
        entry.createdAt.formatted(
            .dateTime
                .locale(locale)
                .hour()
                .minute()
        )
    }
}

enum HistoryActionIconKind {
    case detail
    case delete
}

struct HistoryActionIcon: View {
    let kind: HistoryActionIconKind

    var body: some View {
        ZStack {
            switch kind {
            case .detail:
                detailIcon
            case .delete:
                deleteIcon
            }
        }
        .frame(width: 17, height: 17)
        .contentShape(Rectangle())
    }

    private var detailIcon: some View {
        ZStack {
            fillPath("M15 12.9492H8C7.59 12.9492 7.25 12.6092 7.25 12.1992C7.25 11.7892 7.59 11.4492 8 11.4492H15C15.41 11.4492 15.75 11.7892 15.75 12.1992C15.75 12.6092 15.41 12.9492 15 12.9492Z")
            fillPath("M12.38 16.9492H8C7.59 16.9492 7.25 16.6092 7.25 16.1992C7.25 15.7892 7.59 15.4492 8 15.4492H12.38C12.79 15.4492 13.13 15.7892 13.13 16.1992C13.13 16.6092 12.79 16.9492 12.38 16.9492Z")
            fillPath("M14 6.75H10C9.04 6.75 7.25 6.75 7.25 4C7.25 1.25 9.04 1.25 10 1.25H14C14.96 1.25 16.75 1.25 16.75 4C16.75 4.96 16.75 6.75 14 6.75ZM10 2.75C9.01 2.75 8.75 2.75 8.75 4C9.01 5.25 9.01 5.25 10 5.25H14C15.25 5.25 15.25 4.99 15.25 4C15.25 2.75 14.99 2.75 14 2.75H10Z")
            fillPath("M15 22.7504H9C3.38 22.7504 2.25 20.1704 2.25 16.0004V10.0004C2.25 5.44042 3.9 3.49042 7.96 3.28042C8.36 3.26042 8.73 3.57042 8.75 3.99042C8.77 4.41042 8.45 4.75042 8.04 4.77042C5.2 4.93042 3.75 5.78042 3.75 10.0004V16.0004C3.75 19.7004 4.48 21.2504 9 21.2504H15C19.52 21.2504 20.25 19.7004 20.25 16.0004V10.0004C20.25 5.78042 18.8 4.93042 15.96 4.77042C15.55 4.75042 15.23 4.39042 15.25 3.98042C15.27 3.57042 15.63 3.25042 16.04 3.27042C20.1 3.49042 21.75 5.44042 21.75 9.99042V15.9904C21.75 20.1704 20.62 22.7504 15 22.7504Z")
        }
    }

    private var deleteIcon: some View {
        ZStack {
            fillPath("M20.9999 6.73046C20.9799 6.73046 20.9499 6.73046 20.9199 6.73046C15.6299 6.20046 10.3499 6.00046 5.11992 6.53046L3.07992 6.73046C2.65992 6.77046 2.28992 6.47046 2.24992 6.05046C2.20992 5.63046 2.50992 5.27046 2.91992 5.23046L4.95992 5.03046C10.2799 4.49046 15.6699 4.70046 21.0699 5.23046C21.4799 5.27046 21.7799 5.64046 21.7399 6.05046C21.7099 6.44046 21.3799 6.73046 20.9999 6.73046Z")
            fillPath("M8.50001 5.72C8.46001 5.72 8.42001 5.72 8.37001 5.71C7.97001 5.64 7.69001 5.25 7.76001 4.85L7.98001 3.54C8.14001 2.58 8.36001 1.25 10.69 1.25H13.31C15.65 1.25 15.87 2.63 16.02 3.55L16.24 4.85C16.31 5.26 16.03 5.65 15.63 5.71C15.22 5.78 14.83 5.5 14.77 5.1L14.55 3.8C14.41 2.93 14.38 2.76 13.32 2.76H10.7C9.64001 2.76 9.62001 2.9 9.47001 3.79L9.24001 5.09C9.18001 5.46 8.86001 5.72 8.50001 5.72Z")
            fillPath("M15.2099 22.7496H8.7899C5.2999 22.7496 5.1599 20.8196 5.0499 19.2596L4.3999 9.18959C4.3699 8.77959 4.6899 8.41959 5.0999 8.38959C5.5199 8.36959 5.8699 8.67959 5.8999 9.08959L6.5499 19.1596C6.6599 20.6796 6.6999 21.2496 8.7899 21.2496H15.2099C17.3099 21.2496 17.3499 20.6796 17.4499 19.1596L18.0999 9.08959C18.1299 8.67959 18.4899 8.36959 18.8999 8.38959C19.3099 8.41959 19.6299 8.76959 19.5999 9.18959L18.9499 19.2596C18.8399 20.8196 18.6999 22.7496 15.2099 22.7496Z")
            fillPath("M13.6601 17.25H10.3301C9.92008 17.25 9.58008 16.91 9.58008 16.5C9.58008 16.09 9.92008 15.75 10.3301 15.75H13.6601C14.0701 15.75 14.4101 16.09 14.4101 16.5C14.4101 16.91 14.0701 17.25 13.6601 17.25Z")
            fillPath("M14.5 13.25H9.5C9.09 13.25 8.75 12.91 8.75 12.5C8.75 12.09 9.09 11.75 9.5 11.75H14.5C14.91 11.75 15.25 12.09 15.25 12.5C15.25 12.91 14.91 13.25 14.5 13.25Z")
        }
    }

    private func strokePath(_ pathData: String, opacity: Double = 1) -> some View {
        SVGPathShape(pathData: pathData)
            .stroke(
                HistoryRowStyle.actionIconColor.opacity(opacity),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
    }

    private func fillPath(_ pathData: String) -> some View {
        SVGPathShape(pathData: pathData)
            .fill(HistoryRowStyle.actionIconColor)
    }
}

private enum HistoryRowStyle {
    static let cornerRadius: CGFloat = 12

    static var fillColor: Color {
        Color(nsColor: dynamicColor(
            light: NSColor(calibratedWhite: 0.972, alpha: 1),
            dark: NSColor(calibratedWhite: 0.155, alpha: 1)
        ))
    }

    static var borderColor: Color {
        Color(nsColor: dynamicColor(
            light: NSColor.black.withAlphaComponent(0.035),
            dark: NSColor.white.withAlphaComponent(0.055)
        ))
    }

    static var hoverBorderColor: Color {
        Color(nsColor: dynamicColor(
            light: NSColor.black.withAlphaComponent(0.075),
            dark: NSColor.white.withAlphaComponent(0.105)
        ))
    }

    static var actionIconColor: Color {
        Color(nsColor: dynamicColor(
            light: NSColor.black,
            dark: NSColor.white.withAlphaComponent(0.92)
        ))
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return dark
            default:
                return light
            }
        }
    }
}

struct NoteHistoryRow: View {
    @Environment(\.locale) private var locale
    @State private var isHovered = false

    let item: VoxtNoteItem
    let onCopy: () -> Void
    let onToggleCompletion: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(timeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)
                    .padding(.top, 1)

                Button(action: onCopy) {
                    Text(displayText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .help(localized("Copy"))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 6) {
                Button(action: onToggleCompletion) {
                    Image(systemName: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
                }
                .buttonStyle(SettingsCompactIconButtonStyle(size: 26))

                Button(role: .destructive, action: onDelete) {
                    HistoryActionIcon(kind: .delete)
                }
                .buttonStyle(SettingsCompactIconButtonStyle(size: 26))
            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .frame(width: 58)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 9.5)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HistoryRowStyle.cornerRadius, style: .continuous)
                .fill(HistoryRowStyle.fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HistoryRowStyle.cornerRadius, style: .continuous)
                .strokeBorder(isHovered ? HistoryRowStyle.hoverBorderColor : HistoryRowStyle.borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var displayText: String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return text
        }
        if text.isEmpty || title == text {
            return title
        }
        return "\(title)\n\(text)"
    }

    private var timeText: String {
        item.createdAt.formatted(
            .dateTime
                .locale(locale)
                .hour()
                .minute()
        )
    }
}

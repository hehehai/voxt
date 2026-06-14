import SwiftUI
import AppKit

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

enum HistoryFilterTab: String, CaseIterable, Identifiable {
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
        Text(
            date.formatted(
                .dateTime
                    .locale(locale)
                    .year()
                    .month(.defaultDigits)
                    .day()
            )
        )
        .font(.system(size: 14, weight: .bold))
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
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
                .buttonStyle(SettingsCompactIconButtonStyle(tone: .destructive, size: 26))
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

private enum HistoryActionIconKind {
    case detail
    case delete
}

private struct HistoryActionIcon: View {
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
        .foregroundStyle(.primary.opacity(0.82))
        .contentShape(Rectangle())
    }

    private var detailIcon: some View {
        ZStack {
            strokePath("M10.97 20.02C15.94 20.02 19.97 15.99 19.97 11.02C19.97 6.05002 15.94 2.02002 10.97 2.02002C5.99997 2.02002 1.96997 6.04002 1.96997 11.02C1.96997 16 5.99997 20.02 10.97 20.02Z")
            strokePath("M18.8699 20.48C19.1499 22.14 20.3299 22.48 21.4599 21.24C22.4899 20.1 22.0999 18.98 20.5699 18.75C19.4399 18.57 18.6799 19.34 18.8699 20.48Z", opacity: 0.4)
            strokePath("M7.96997 9.52002H13.97", opacity: 0.4)
            strokePath("M7.96997 12.52H10.97", opacity: 0.4)
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
                Color.primary.opacity(0.82 * opacity),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
    }

    private func fillPath(_ pathData: String) -> some View {
        SVGPathShape(pathData: pathData)
            .fill(Color.primary.opacity(0.82))
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
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
                .buttonStyle(SettingsCompactIconButtonStyle(tone: .destructive, size: 26))
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

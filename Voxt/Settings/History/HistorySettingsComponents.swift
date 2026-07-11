// HistorySettingsComponents.swift
// Provides History Settings Components for history settings.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

struct HistoryNoteStatusFilterSelect: View {
    @Binding var selection: Set<VoxtNoteStatus>
    @State private var isPresented = false

    private let statuses: [VoxtNoteStatus] = [.todo, .inProgress, .done, .backlog]

    var body: some View {
        SettingsSelectionButton(width: 136, height: 32) {
            isPresented = true
        } label: {
            Text(selectionSummary)
                .lineLimit(1)
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                filterRow(
                    title: localized("All statuses"),
                    isSelected: selection == Set(statuses)
                ) {
                    selection = Set(statuses)
                }

                Divider()
                    .padding(.vertical, 2)

                ForEach(statuses) { status in
                    filterRow(
                        title: status.title,
                        isSelected: selection.contains(status)
                    ) {
                        selection = HistorySettingsData.toggledNoteStatuses(selection, status: status)
                    }
                }
            }
            .padding(8)
            .frame(width: 190)
        }
        .accessibilityLabel(localized("Status"))
    }

    private var selectionSummary: String {
        if selection == Set(statuses) {
            return localized("All statuses")
        }
        if selection.count == 1, let status = selection.first {
            return status.title
        }
        return AppLocalization.format("%d statuses", selection.count)
    }

    private func filterRow(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if isSelected {
                        Image(systemName: "checkmark")
                    } else {
                        Color.clear
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12, height: 12)
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Color.accentColor.opacity(isSelected ? 0.09 : 0),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum HistoryNoteViewMode: String, CaseIterable, Identifiable {
    case list
    case linearCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list:
            return localized("List View")
        case .linearCard:
            return localized("Linear Card View")
        }
    }
}

struct HistoryNoteViewPicker: View {
    @Binding var selection: HistoryNoteViewMode

    var body: some View {
        Button {
            selection = selection == .list ? .linearCard : .list
        } label: {
            AppSVGIcon(
                kind: selection == .list ? .listView : .linearView,
                size: 16
            )
        }
        .buttonStyle(SettingsCompactIconButtonStyle())
        .help(nextModeTitle)
        .accessibilityLabel(localized("Note View"))
        .accessibilityValue(selection.title)
    }

    private var nextModeTitle: String {
        selection == .list
            ? localized("Linear Card View")
            : localized("List View")
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
        let corrected = HistoryCorrectionPresentation.correctedText(
            for: entry.text,
            snapshots: entry.dictionaryCorrectionSnapshots
        )
        if !corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return corrected
        }
        return entry.displayTitle ?? entry.meetingCaptureMode?.title ?? localized("Recording")
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
        AppSVGIcon(
            kind: kind == .detail ? .viewDetails : .delete,
            color: HistoryRowStyle.actionIconColor,
            size: 17
        )
        .contentShape(Rectangle())
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

    static var linearCardFillColor: Color {
        Color(nsColor: dynamicColor(
            light: NSColor.white,
            dark: NSColor(calibratedWhite: 0.165, alpha: 1)
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

struct NoteHistorySectionHeader: View {
    let status: VoxtNoteStatus
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if status == .backlog {
                    VoxtNoteStatusMark(status: .backlog, priority: .none, size: 12)
                } else {
                    Image(systemName: statusSystemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
            }
                .frame(width: 18, height: 18)
                .background(statusColor.opacity(0.10), in: Circle())

            Text("\(status.title) · \(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusSystemImage: String {
        switch status {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark"
        case .backlog: return "clock"
        }
    }

    private var statusColor: Color {
        switch status {
        case .todo: return .blue
        case .inProgress: return .orange
        case .done: return .green
        case .backlog: return .secondary
        }
    }
}

struct NoteHistoryMoreButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(localized("More"))
        .accessibilityLabel(localized("More"))
    }
}

private struct NoteHistoryFooterActionIcon: View {
    enum Kind {
        case copy
        case edit
        case more
        case confirm
    }

    let kind: Kind
    var forcedHover: Bool? = nil
    @State private var isHovered = false

    private var showsHover: Bool {
        forcedHover ?? isHovered
    }

    var body: some View {
        icon
            .frame(width: 14, height: 14)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(showsHover ? 0.07 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        showsHover ? SettingsUIStyle.subtleBorderColor : .clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: showsHover)
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .copy:
            AppSVGIcon(kind: .copy, size: 14)
        case .edit:
            AppSVGIcon(kind: .edit, size: 14)
        case .more:
            AppSVGIcon(kind: .more, size: 14)
        case .confirm:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct NoteHistoryFooterMenuButton<MenuContent: View>: View {
    let menuContent: MenuContent
    @State private var isHovered = false

    init(@ViewBuilder menuContent: () -> MenuContent) {
        self.menuContent = menuContent()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            Color.clear
                .frame(width: 22, height: 22)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
        .overlay {
            NoteHistoryFooterActionIcon(kind: .more, forcedHover: isHovered)
                .allowsHitTesting(false)
        }
        .onHover { isHovered = $0 }
        .help(localized("Note actions"))
    }
}

enum NoteHistoryRowLayout: Equatable {
    case list
    case linearCard
}

struct NoteHistoryRow: View {
    @Environment(\.locale) private var locale
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var isDetailPresented = false
    @State private var draftTitle = ""
    @State private var isEditingDetail = false
    @State private var detailTitle = ""
    @State private var detailContent = ""
    @FocusState private var isRenameFocused: Bool

    let item: VoxtNoteItem
    let layout: NoteHistoryRowLayout
    let contentLineLimit: Int
    let fixedHeight: CGFloat?
    let onCopy: () -> Void
    let onDoubleClick: () -> Void
    let onSetStatus: (VoxtNoteStatus) -> Void
    let onSetPriority: (VoxtNotePriority) -> Void
    let onRename: (String) -> Void
    let onUpdateDetails: (String, String) -> Bool
    let onReorder: (UUID) -> Bool
    let onDelete: () -> Void

    var body: some View {
        rowContent
            .padding(layout == .linearCard ? 10 : 0)
            .padding(.horizontal, layout == .list ? 9.5 : 0)
            .padding(.vertical, layout == .list ? 4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: fixedHeight)
            .background(
                RoundedRectangle(cornerRadius: HistoryRowStyle.cornerRadius, style: .continuous)
                    .fill(rowFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HistoryRowStyle.cornerRadius, style: .continuous)
                    .strokeBorder(isHovered ? HistoryRowStyle.hoverBorderColor : HistoryRowStyle.borderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !isRenaming else { return }
                onDoubleClick()
            }
            .help(item.text)
            .onDrag {
                VoxtNoteDragPayload(text: item.text, noteID: item.id).itemProvider()
            } preview: {
                dragPreview
            }
            .onDrop(of: [UTType.utf8PlainText], isTargeted: nil, perform: acceptDrop)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
            .onChange(of: item.id) { _, _ in
                isRenaming = false
                isDetailPresented = false
                isEditingDetail = false
                draftTitle = ""
                detailTitle = ""
                detailContent = ""
            }
            .popover(isPresented: $isDetailPresented, arrowEdge: .trailing) {
                noteDetail
            }
    }

    @ViewBuilder
    private var rowContent: some View {
        switch layout {
        case .list:
            HStack(alignment: .center, spacing: 10) {
                noteBodyContent(showTimeInTitle: true)
                trailingAction
            }
        case .linearCard:
            VStack(alignment: .leading, spacing: 8) {
                noteBodyContent(showTimeInTitle: false)
                linearFooter
            }
        }
    }

    private func noteBodyContent(showTimeInTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if isRenaming {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(localized("Note title"), text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($isRenameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand(perform: cancelRename)

                    if showTimeInTitle {
                        noteTimeLabel
                    }
                }

                noteContentPreview
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(item.status == .done ? .secondary : .primary)
                            .strikethrough(item.status == .done, color: .secondary)
                            .lineLimit(layout == .linearCard ? 2 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if showTimeInTitle {
                            noteTimeLabel
                        }
                    }

                    noteContentPreview
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: showDetail)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(localized("Open note details"))
            }

            if item.priority != .none {
                metadataChip(item.priority.title, color: priorityColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowFillColor: Color {
        layout == .linearCard ? HistoryRowStyle.linearCardFillColor : HistoryRowStyle.fillColor
    }

    private var linearFooter: some View {
        HStack(alignment: .center, spacing: 8) {
            noteTimeLabel

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button(action: onCopy) {
                    NoteHistoryFooterActionIcon(kind: .copy)
                }
                .buttonStyle(.plain)
                .help(localized("Copy"))

                if isRenaming {
                    Button(action: commitRename) {
                        NoteHistoryFooterActionIcon(kind: .confirm)
                    }
                    .buttonStyle(.plain)
                    .help(localized("Save title"))
                } else {
                    Button(action: showEditableDetail) {
                        NoteHistoryFooterActionIcon(kind: .edit)
                    }
                    .buttonStyle(.plain)
                    .help(localized("Edit"))
                }

                NoteHistoryFooterMenuButton {
                    linearMoreActions
                }
            }
        }
    }

    private var noteContentPreview: some View {
        Text(item.text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineLimit(contentLineLimit)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private var noteTimeLabel: some View {
        Text(timeText)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var trailingAction: some View {
        if isRenaming {
            Button(action: commitRename) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localized("Save title"))
        } else {
            AppSVGMenuButton(icon: .more) {
                noteActions
            }
            .opacity(isHovered ? 1 : 0.38)
            .help(localized("Note actions"))
        }
    }

    @ViewBuilder
    private var noteActions: some View {
        Button {
            showDetail()
        } label: {
            AppSVGMenuLabel(title: localized("View note…"), icon: .viewDetails)
        }

        Button {
            beginRenaming()
        } label: {
            AppSVGMenuLabel(title: localized("Edit title…"), icon: .edit)
        }

        Button {
            onCopy()
        } label: {
            AppSVGMenuLabel(title: localized("Copy"), icon: .copy)
        }

        Menu(localized("Priority")) {
            ForEach(VoxtNotePriority.allCases.reversed(), id: \.self) { priority in
                Button {
                    onSetPriority(priority)
                } label: {
                    menuLabel(priority.title, selected: priority == item.priority)
                }
            }
        }

        Menu(localized("Move to")) {
            ForEach(VoxtNoteStatus.moveMenuOrder) { status in
                Button {
                    onSetStatus(status)
                } label: {
                    menuLabel(status.title, selected: status == item.status)
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            AppSVGMenuLabel(title: localized("Delete"), icon: .delete, color: .red)
        }
    }

    @ViewBuilder
    private var linearMoreActions: some View {
        Button {
            showDetail()
        } label: {
            AppSVGMenuLabel(title: localized("View note…"), icon: .viewDetails)
        }

        Button {
            beginRenaming()
        } label: {
            AppSVGMenuLabel(title: localized("Edit title…"), icon: .edit)
        }

        Menu(localized("Priority")) {
            ForEach(VoxtNotePriority.allCases.reversed(), id: \.self) { priority in
                Button {
                    onSetPriority(priority)
                } label: {
                    menuLabel(priority.title, selected: priority == item.priority)
                }
            }
        }

        Menu(localized("Move to")) {
            ForEach(VoxtNoteStatus.moveMenuOrder) { status in
                Button {
                    onSetStatus(status)
                } label: {
                    menuLabel(status.title, selected: status == item.status)
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            AppSVGMenuLabel(title: localized("Delete"), icon: .delete, color: .red)
        }
    }

    private var dragPreview: some View {
        HStack(spacing: 7) {
            Image(systemName: statusSystemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor)
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let noteID = providers
            .compactMap(\.suggestedName)
            .compactMap(UUID.init(uuidString:))
            .first
        else {
            return false
        }
        return onReorder(noteID)
    }

    private var noteDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    if isEditingDetail {
                        TextField(localized("Note title"), text: $detailTitle)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .settingsFieldSurface(minHeight: 32)
                    } else {
                        Text(item.title)
                            .font(.headline)
                            .textSelection(.enabled)
                    }
                    HStack(spacing: 6) {
                        metadataChip(item.status.title, color: statusColor)
                        if item.priority != .none {
                            metadataChip(item.priority.title, color: priorityColor)
                        }
                    }
                }
                Spacer(minLength: 12)
                Button {
                    isDetailPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("Close"))
            }

            Divider()

            if isEditingDetail {
                TextEditor(text: $detailContent)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        SettingsUIStyle.controlFillColor,
                        in: RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                            .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                    )
            } else {
                ScrollView {
                    Text(item.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isEditingDetail {
                    Button(localized("Cancel"), action: cancelDetailEditing)
                    Button(localized("Save"), action: saveDetailEditing)
                        .disabled(!canSaveDetail)
                } else {
                    Button(localized("Edit"), action: beginDetailEditing)
                    Button(localized("Copy"), action: onCopy)
                }
            }
        }
        .padding(16)
        .frame(width: 400, height: 320)
    }

    private var statusSystemImage: String {
        switch item.status {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark"
        case .backlog: return "clock"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .todo: return .blue
        case .inProgress: return .orange
        case .done: return .green
        case .backlog: return .secondary
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .none: return .secondary
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    private var timeText: String {
        item.updatedAt.formatted(
            .dateTime
                .locale(locale)
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }

    private func metadataChip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(color.opacity(0.08), in: Capsule(style: .continuous))
    }

    private func menuLabel(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func beginRenaming() {
        draftTitle = item.title
        isRenaming = true
        DispatchQueue.main.async { isRenameFocused = true }
    }

    private func showDetail() {
        guard !isRenaming else { return }
        detailTitle = item.title
        detailContent = item.text
        isEditingDetail = false
        isDetailPresented = true
    }

    private func showEditableDetail() {
        guard !isRenaming else { return }
        detailTitle = item.title
        detailContent = item.text
        isEditingDetail = true
        isDetailPresented = true
    }

    private var canSaveDetail: Bool {
        !detailTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !detailContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginDetailEditing() {
        detailTitle = item.title
        detailContent = item.text
        isEditingDetail = true
    }

    private func cancelDetailEditing() {
        detailTitle = item.title
        detailContent = item.text
        isEditingDetail = false
    }

    private func saveDetailEditing() {
        guard canSaveDetail,
              onUpdateDetails(detailTitle, detailContent)
        else {
            return
        }
        isEditingDetail = false
    }

    private func cancelRename() {
        isRenaming = false
        draftTitle = ""
    }

    private func commitRename() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            cancelRename()
            return
        }
        onRename(title)
        cancelRename()
    }
}

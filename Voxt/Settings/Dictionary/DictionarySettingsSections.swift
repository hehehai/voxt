// DictionarySettingsSections.swift
// Provides Dictionary Settings Sections for dictionary settings.

import SwiftUI
import AppKit

struct DictionaryEntriesCard: View {
    @Binding var selectedTab: DictionaryEntriesTab
    @Binding var selectedHotwordCategoryID: UUID?
    let hotwordSections: [(category: DictionaryCategory, entries: [DictionaryEntry])]
    let replacementEntries: [DictionaryEntry]
    let searchText: String
    let isLoadingEntries: Bool
    let onSearch: () -> Void
    let onClearSearch: () -> Void
    let onCreate: () -> Void
    let onCreateCategory: () -> Void
    let onOpenIngest: () -> Void
    let onOpenSettings: () -> Void
    let onImport: () -> Void
    let onExport: () -> Void
    let onCreateInCategory: (DictionaryCategory) -> Void
    let onEditCategory: (DictionaryCategory) -> Void
    let onDeleteCategory: (DictionaryCategory) -> Void
    let onEdit: (DictionaryEntry) -> Void
    let onDelete: (DictionaryEntry) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                toolbar

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Text(AppLocalization.format("Filtered by \"%@\"", searchText))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(AppLocalization.localizedString("Clear")) {
                            onClearSearch()
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isContentEmpty && !isLoadingEntries {
                    SettingsEmptyStateView(
                        illustration: .dictionary,
                        title: emptyStateTitle,
                        message: emptyStateMessage
                    )
                } else {
                    ScrollView {
                        content
                        .padding(.vertical, 2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .top)
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var toolbar: some View {
        if selectedTab == .hotwords, let selectedHotwordSection {
            HStack(spacing: 8) {
                Button {
                    selectedHotwordCategoryID = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(SettingsCompactIconButtonStyle(size: 30))
                .accessibilityLabel(AppLocalization.localizedString("Back"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedHotwordSection.category.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    Text(AppLocalization.format("%d terms", selectedHotwordSection.entries.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                DictionaryHeaderIconButton(
                    accessibilityLabel: AppLocalization.localizedString("Search Current Category"),
                    action: onSearch
                ) {
                    SettingsSearchIconView()
                }

                DictionaryHeaderIconButton(
                    accessibilityLabel: AppLocalization.localizedString("Create Hot Word in This Category"),
                    action: { onCreateInCategory(selectedHotwordSection.category) }
                ) {
                    DictionaryActionIcon(kind: .createTerm, size: 15)
                }

                DictionaryHeaderIconButton(
                    accessibilityLabel: AppLocalization.localizedString("Edit Dictionary Category"),
                    action: { onEditCategory(selectedHotwordSection.category) }
                ) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }

                DictionaryHeaderIconButton(
                    accessibilityLabel: AppLocalization.localizedString("Delete Dictionary Category"),
                    action: {
                        if !selectedHotwordSection.category.isDefault {
                            onDeleteCategory(selectedHotwordSection.category)
                        }
                    }
                ) {
                    DictionaryActionIcon(kind: .deleteCategory, size: 15)
                }
            }
        } else {
            HStack {
                DictionaryEntriesTabPicker(selectedTab: $selectedTab)

                Spacer(minLength: 12)

                DictionaryHeaderIconButton(
                    accessibilityLabel: searchAccessibilityLabel,
                    action: onSearch
                ) {
                    SettingsSearchIconView()
                }

                if selectedTab == .hotwords {
                    DictionaryHeaderIconButton(
                        accessibilityLabel: AppLocalization.localizedString("Create Category"),
                        action: onCreateCategory
                    ) {
                        DictionaryActionIcon(kind: .createCategory, size: 15)
                    }
                }

                DictionaryHeaderIconButton(
                    accessibilityLabel: createTermAccessibilityLabel,
                    action: onCreate
                ) {
                    DictionaryActionIcon(kind: .createTerm, size: 15)
                }

                Rectangle()
                    .fill(SettingsUIStyle.subtleBorderColor)
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 4)

                DictionaryHeaderIconButton(
                    accessibilityLabel: AppLocalization.localizedString("One-Click Ingest"),
                    action: onOpenIngest
                ) {
                    SettingsOneClickIngestIconView(size: 15)
                }

                DictionaryHeaderIconButton(
                    accessibilityLabel: AppLocalization.localizedString("Dictionary Advanced Settings"),
                    action: onOpenSettings
                ) {
                    SettingsSparkleSettingsIconView(size: 15)
                }

                DictionaryHeaderActionMenuButton(
                    actions: [
                        DictionaryHeaderMenuAction(
                            title: AppLocalization.localizedString("Import"),
                            handler: onImport
                        ),
                        DictionaryHeaderMenuAction(
                            title: AppLocalization.localizedString("Export"),
                            handler: onExport
                        )
                    ],
                    accessibilityLabel: AppLocalization.localizedString("More")
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .hotwords:
            if let selectedHotwordSection {
                HotwordCategoryDetail(
                    entries: selectedHotwordSection.entries,
                    onEditEntry: onEdit,
                    onDeleteEntry: onDelete
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 10, alignment: .top)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(displayedHotwordSections, id: \.category.id) { section in
                        HotwordCategoryCard(
                            category: section.category,
                            entries: section.entries,
                            onOpen: { selectedHotwordCategoryID = section.category.id }
                        )
                    }
                }
            }
        case .replacements:
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 8, alignment: .top)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(replacementEntries) { entry in
                    DictionaryReplacementRow(
                        entry: entry,
                        onEdit: { onEdit(entry) },
                        onDelete: { onDelete(entry) }
                    )
                }
            }
        }
    }

    private var displayedHotwordSections: [(category: DictionaryCategory, entries: [DictionaryEntry])] {
        guard isSearchActive else { return hotwordSections }
        return hotwordSections.filter { !$0.entries.isEmpty }
    }

    private var selectedHotwordSection: (category: DictionaryCategory, entries: [DictionaryEntry])? {
        guard let selectedHotwordCategoryID else { return nil }
        return hotwordSections.first(where: { $0.category.id == selectedHotwordCategoryID })
    }

    private var isContentEmpty: Bool {
        switch selectedTab {
        case .hotwords:
            if selectedHotwordSection != nil {
                return false
            }
            return displayedHotwordSections.allSatisfy { $0.entries.isEmpty }
        case .replacements:
            return replacementEntries.isEmpty
        }
    }

    private var createTermAccessibilityLabel: String {
        switch selectedTab {
        case .hotwords:
            return AppLocalization.localizedString("Create Hot Word")
        case .replacements:
            return AppLocalization.localizedString("Create Replacement Term")
        }
    }

    private var searchAccessibilityLabel: String {
        switch selectedTab {
        case .hotwords:
            return AppLocalization.localizedString("Search Hot Words")
        case .replacements:
            return AppLocalization.localizedString("Search Replacement Terms")
        }
    }

    private var emptyStateTitle: String {
        if !isSearchActive {
            switch selectedTab {
            case .hotwords:
                return AppLocalization.localizedString("No hot words yet")
            case .replacements:
                return AppLocalization.localizedString("No replacement terms yet")
            }
        }
        return AppLocalization.localizedString("No matching dictionary terms")
    }

    private var emptyStateMessage: String {
        if !isSearchActive {
            switch selectedTab {
            case .hotwords:
                return AppLocalization.localizedString("Create a hot word to help Voxt recognize names, jargon, and product words.")
            case .replacements:
                return AppLocalization.localizedString("Create a replacement term to normalize final transcription results.")
            }
        }
        return AppLocalization.localizedString("Try another keyword or clear the search filter.")
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

}

private struct HotwordCategoryCard: View {
    let category: DictionaryCategory
    let entries: [DictionaryEntry]
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)

                Text(AppLocalization.format("%d terms", entries.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .contentShape(Rectangle())
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
        .brightness(isHovering ? 0.035 : 0)
        .overlay {
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isHovering ? 0.42 : 0), lineWidth: 1)
        }
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onOpen)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct HotwordCategoryDetail: View {
    let entries: [DictionaryEntry]
    let onEditEntry: (DictionaryEntry) -> Void
    let onDeleteEntry: (DictionaryEntry) -> Void

    var body: some View {
        Group {
            if entries.isEmpty {
                Text(AppLocalization.localizedString("No dictionary terms yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 8, alignment: .top)],
                    alignment: .leading,
                    spacing: 8
                ) {
                ForEach(entries) { entry in
                    DictionaryRow(
                        entry: entry,
                        onEdit: { onEditEntry(entry) },
                        onDelete: { onDeleteEntry(entry) }
                    )
                }
                }
            }
        }
    }
}

private struct DictionaryReplacementRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isDeleteHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.term)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)

                Text(scopeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 28)
            }

            Text(replacementText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
        .brightness(isHovering ? 0.035 : 0)
        .overlay {
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isHovering ? 0.42 : 0), lineWidth: 1)
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onTapGesture(perform: onEdit)
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isDeleteHovering ? Color.red : Color.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(isDeleteHovering ? 0.12 : 0))
                    )
            }
            .buttonStyle(.plain)
            .help(AppLocalization.localizedString("Delete"))
            .onHover { isDeleteHovering = $0 }
            .padding(6)
        }
    }

    private var replacementText: String {
        entry.replacementTerms.map(\.text).joined(separator: ", ")
    }

    private var scopeText: String {
        guard entry.groupID != nil else {
            return AppLocalization.localizedString("Global")
        }
        return entry.groupNameSnapshot ?? AppLocalization.localizedString("Missing Group")
    }
}

private struct DictionaryHeaderIcon: View {
    enum Kind {
        case oneClickIngest
        case settings
    }

    let kind: Kind
    var size: CGFloat = 17

    var body: some View {
        Group {
            switch kind {
            case .oneClickIngest:
                DictionaryOneClickIngestIconShape()
                    .fill(Color.secondary)
            case .settings:
                DictionaryHeaderSettingsIcon()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct DictionaryOneClickIngestIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: rect.midX - 12 * scale,
            ty: rect.midY - 12 * scale
        )

        var path = Path()
        addSparkle(to: &path)
        addCornerStroke(to: &path)
        addWandStroke(to: &path)
        addIngestTool(to: &path)
        return path.applying(transform)
    }

    private func addSparkle(to path: inout Path) {
        path.move(to: CGPoint(x: 4.7201, y: 12.46))
        path.addCurve(to: CGPoint(x: 3.8901, y: 11.79), control1: CGPoint(x: 4.3201, y: 12.46), control2: CGPoint(x: 3.9801, y: 12.19))
        path.addLine(to: CGPoint(x: 3.6801, y: 10.87))
        path.addCurve(to: CGPoint(x: 2.9001, y: 10.09), control1: CGPoint(x: 3.5901, y: 10.48), control2: CGPoint(x: 3.2801, y: 10.17))
        path.addLine(to: CGPoint(x: 1.9601, y: 9.87))
        path.addCurve(to: CGPoint(x: 1.3101, y: 9.05), control1: CGPoint(x: 1.5801, y: 9.79), control2: CGPoint(x: 1.3101, y: 9.45))
        path.addCurve(to: CGPoint(x: 1.9801, y: 8.22), control1: CGPoint(x: 1.3101, y: 8.65), control2: CGPoint(x: 1.5801, y: 8.31))
        path.addLine(to: CGPoint(x: 2.9001, y: 8.01))
        path.addCurve(to: CGPoint(x: 3.6801, y: 7.23), control1: CGPoint(x: 3.2901, y: 7.92), control2: CGPoint(x: 3.6001, y: 7.61))
        path.addLine(to: CGPoint(x: 3.9001, y: 6.29))
        path.addCurve(to: CGPoint(x: 4.7201, y: 5.64), control1: CGPoint(x: 3.9801, y: 5.91), control2: CGPoint(x: 4.3201, y: 5.64))
        path.addCurve(to: CGPoint(x: 5.5501, y: 6.31), control1: CGPoint(x: 5.1201, y: 5.64), control2: CGPoint(x: 5.4601, y: 5.92))
        path.addLine(to: CGPoint(x: 5.7601, y: 7.23))
        path.addCurve(to: CGPoint(x: 6.5401, y: 8.01), control1: CGPoint(x: 5.8501, y: 7.62), control2: CGPoint(x: 6.1601, y: 7.93))
        path.addLine(to: CGPoint(x: 7.4801, y: 8.23))
        path.addCurve(to: CGPoint(x: 8.1301, y: 9.06), control1: CGPoint(x: 7.8601, y: 8.31), control2: CGPoint(x: 8.1301, y: 8.65))
        path.addCurve(to: CGPoint(x: 7.4701, y: 9.88), control1: CGPoint(x: 8.1301, y: 9.46), control2: CGPoint(x: 7.8601, y: 9.80))
        path.addLine(to: CGPoint(x: 6.5401, y: 10.09))
        path.addCurve(to: CGPoint(x: 5.7601, y: 10.87), control1: CGPoint(x: 6.1501, y: 10.18), control2: CGPoint(x: 5.8401, y: 10.49))
        path.addLine(to: CGPoint(x: 5.5401, y: 11.81))
        path.addCurve(to: CGPoint(x: 4.7201, y: 12.46), control1: CGPoint(x: 5.4601, y: 12.19), control2: CGPoint(x: 5.1201, y: 12.46))
        path.closeSubpath()
        path.move(to: CGPoint(x: 4.1601, y: 9.06))
        path.addCurve(to: CGPoint(x: 4.7301, y: 9.63), control1: CGPoint(x: 4.3801, y: 9.22), control2: CGPoint(x: 4.5701, y: 9.41))
        path.addCurve(to: CGPoint(x: 5.3001, y: 9.06), control1: CGPoint(x: 4.8901, y: 9.41), control2: CGPoint(x: 5.0801, y: 9.22))
        path.addCurve(to: CGPoint(x: 4.7301, y: 8.49), control1: CGPoint(x: 5.0801, y: 8.90), control2: CGPoint(x: 4.8901, y: 8.71))
        path.addCurve(to: CGPoint(x: 4.1601, y: 9.06), control1: CGPoint(x: 4.5701, y: 8.71), control2: CGPoint(x: 4.3801, y: 8.90))
        path.closeSubpath()
    }

    private func addCornerStroke(to path: inout Path) {
        path.move(to: CGPoint(x: 19.8301, y: 8.12))
        path.addCurve(to: CGPoint(x: 19.3001, y: 7.9), control1: CGPoint(x: 19.6401, y: 8.12), control2: CGPoint(x: 19.4501, y: 8.05))
        path.addCurve(to: CGPoint(x: 19.3001, y: 6.84), control1: CGPoint(x: 19.0101, y: 7.61), control2: CGPoint(x: 19.0101, y: 7.13))
        path.addLine(to: CGPoint(x: 20.6501, y: 5.49))
        path.addCurve(to: CGPoint(x: 20.6501, y: 4.09), control1: CGPoint(x: 21.0401, y: 5.10), control2: CGPoint(x: 21.0401, y: 4.48))
        path.addCurve(to: CGPoint(x: 19.2501, y: 4.09), control1: CGPoint(x: 20.2601, y: 3.70), control2: CGPoint(x: 19.6401, y: 3.70))
        path.addLine(to: CGPoint(x: 17.9001, y: 5.44))
        path.addCurve(to: CGPoint(x: 16.8401, y: 5.44), control1: CGPoint(x: 17.6101, y: 5.73), control2: CGPoint(x: 17.1301, y: 5.73))
        path.addCurve(to: CGPoint(x: 16.8401, y: 4.38), control1: CGPoint(x: 16.5501, y: 5.15), control2: CGPoint(x: 16.5501, y: 4.67))
        path.addLine(to: CGPoint(x: 18.1901, y: 3.03))
        path.addCurve(to: CGPoint(x: 21.7101, y: 3.03), control1: CGPoint(x: 19.1601, y: 2.06), control2: CGPoint(x: 20.7401, y: 2.06))
        path.addCurve(to: CGPoint(x: 21.7101, y: 6.55), control1: CGPoint(x: 22.6801, y: 4.00), control2: CGPoint(x: 22.6801, y: 5.58))
        path.addLine(to: CGPoint(x: 20.3601, y: 7.90))
        path.addCurve(to: CGPoint(x: 19.8301, y: 8.12), control1: CGPoint(x: 20.2101, y: 8.05), control2: CGPoint(x: 20.0201, y: 8.12))
        path.closeSubpath()
    }

    private func addWandStroke(to path: inout Path) {
        path.move(to: CGPoint(x: 4.6001, y: 22.7401))
        path.addCurve(to: CGPoint(x: 2.7701, y: 21.9801), control1: CGPoint(x: 3.9401, y: 22.7401), control2: CGPoint(x: 3.2701, y: 22.4901))
        path.addCurve(to: CGPoint(x: 2.7701, y: 18.3201), control1: CGPoint(x: 1.7601, y: 20.9701), control2: CGPoint(x: 1.7601, y: 19.3301))
        path.addLine(to: CGPoint(x: 10.3601, y: 10.7301))
        path.addCurve(to: CGPoint(x: 11.4201, y: 10.7301), control1: CGPoint(x: 10.6501, y: 10.4401), control2: CGPoint(x: 11.1301, y: 10.4401))
        path.addCurve(to: CGPoint(x: 11.4201, y: 11.7901), control1: CGPoint(x: 11.7101, y: 11.0201), control2: CGPoint(x: 11.7101, y: 11.5001))
        path.addLine(to: CGPoint(x: 3.8301, y: 19.3801))
        path.addCurve(to: CGPoint(x: 3.8301, y: 20.9201), control1: CGPoint(x: 3.4101, y: 19.8001), control2: CGPoint(x: 3.4101, y: 20.5001))
        path.addCurve(to: CGPoint(x: 5.3701, y: 20.9201), control1: CGPoint(x: 4.2501, y: 21.3401), control2: CGPoint(x: 4.9401, y: 21.3401))
        path.addLine(to: CGPoint(x: 12.9601, y: 13.3301))
        path.addCurve(to: CGPoint(x: 14.0201, y: 13.3301), control1: CGPoint(x: 13.2501, y: 13.0401), control2: CGPoint(x: 13.7301, y: 13.0401))
        path.addCurve(to: CGPoint(x: 14.0201, y: 14.3901), control1: CGPoint(x: 14.3101, y: 13.6201), control2: CGPoint(x: 14.3101, y: 14.1001))
        path.addLine(to: CGPoint(x: 6.4301, y: 21.9801))
        path.addCurve(to: CGPoint(x: 4.6001, y: 22.7401), control1: CGPoint(x: 5.9301, y: 22.4801), control2: CGPoint(x: 5.2601, y: 22.7401))
        path.closeSubpath()
    }

    private func addIngestTool(to path: inout Path) {
        path.move(to: CGPoint(x: 21.6301, y: 18.52))
        path.addCurve(to: CGPoint(x: 20.3501, y: 17.99), control1: CGPoint(x: 21.1501, y: 18.52), control2: CGPoint(x: 20.6901, y: 18.34))
        path.addLine(to: CGPoint(x: 16.3601, y: 14.0))
        path.addLine(to: CGPoint(x: 15.7401, y: 14.62))
        path.addCurve(to: CGPoint(x: 13.2001, y: 14.62), control1: CGPoint(x: 15.1201, y: 15.28), control2: CGPoint(x: 13.8901, y: 15.31))
        path.addLine(to: CGPoint(x: 10.1601, y: 11.58))
        path.addCurve(to: CGPoint(x: 10.1601, y: 9.03), control1: CGPoint(x: 9.4601, y: 10.88), control2: CGPoint(x: 9.4601, y: 9.73))
        path.addLine(to: CGPoint(x: 10.7701, y: 8.42))
        path.addLine(to: CGPoint(x: 6.7701, y: 4.42))
        path.addCurve(to: CGPoint(x: 6.3301, y: 2.56), control1: CGPoint(x: 6.2801, y: 3.95), control2: CGPoint(x: 6.1101, y: 3.21))
        path.addCurve(to: CGPoint(x: 7.7901, y: 1.34), control1: CGPoint(x: 6.5501, y: 1.91), control2: CGPoint(x: 7.1101, y: 1.44))
        path.addCurve(to: CGPoint(x: 13.8601, y: 3.36), control1: CGPoint(x: 10.0101, y: 1.02), control2: CGPoint(x: 12.2701, y: 1.77))
        path.addLine(to: CGPoint(x: 14.8401, y: 4.34))
        path.addLine(to: CGPoint(x: 15.0801, y: 4.10))
        path.addCurve(to: CGPoint(x: 17.6301, y: 4.10), control1: CGPoint(x: 15.7801, y: 3.40), control2: CGPoint(x: 16.9301, y: 3.40))
        path.addLine(to: CGPoint(x: 20.6701, y: 7.14))
        path.addCurve(to: CGPoint(x: 20.6701, y: 9.68), control1: CGPoint(x: 21.3701, y: 7.81), control2: CGPoint(x: 21.3701, y: 8.98))
        path.addLine(to: CGPoint(x: 20.4301, y: 9.92))
        path.addLine(to: CGPoint(x: 21.4101, y: 10.90))
        path.addCurve(to: CGPoint(x: 23.4301, y: 16.97), control1: CGPoint(x: 23.0001, y: 12.49), control2: CGPoint(x: 23.7501, y: 14.75))
        path.addCurve(to: CGPoint(x: 22.2101, y: 18.43), control1: CGPoint(x: 23.3301, y: 17.65), control2: CGPoint(x: 22.8601, y: 18.21))
        path.addCurve(to: CGPoint(x: 21.6301, y: 18.52), control1: CGPoint(x: 22.0201, y: 18.49), control2: CGPoint(x: 21.8201, y: 18.52))
        path.closeSubpath()

        path.move(to: CGPoint(x: 16.3601, y: 12.19))
        path.addCurve(to: CGPoint(x: 16.8801, y: 12.40), control1: CGPoint(x: 16.5501, y: 12.19), control2: CGPoint(x: 16.7401, y: 12.26))
        path.addLine(to: CGPoint(x: 21.4101, y: 16.93))
        path.addCurve(to: CGPoint(x: 21.9401, y: 16.76), control1: CGPoint(x: 21.6501, y: 17.17), control2: CGPoint(x: 21.9001, y: 17.07))
        path.addCurve(to: CGPoint(x: 20.3401, y: 11.97), control1: CGPoint(x: 22.1901, y: 15.02), control2: CGPoint(x: 21.6001, y: 13.22))
        path.addLine(to: CGPoint(x: 18.8301, y: 10.46))
        path.addCurve(to: CGPoint(x: 18.8301, y: 9.40), control1: CGPoint(x: 18.5401, y: 10.17), control2: CGPoint(x: 18.5401, y: 9.69))
        path.addLine(to: CGPoint(x: 19.6001, y: 8.63))
        path.addCurve(to: CGPoint(x: 19.6101, y: 8.22), control1: CGPoint(x: 19.7201, y: 8.51), control2: CGPoint(x: 19.7201, y: 8.33))
        path.addLine(to: CGPoint(x: 16.5601, y: 5.17))
        path.addCurve(to: CGPoint(x: 16.1301, y: 5.17), control1: CGPoint(x: 16.4401, y: 5.05), control2: CGPoint(x: 16.2501, y: 5.05))
        path.addLine(to: CGPoint(x: 15.3601, y: 5.94))
        path.addCurve(to: CGPoint(x: 14.3001, y: 5.94), control1: CGPoint(x: 15.0801, y: 6.22), control2: CGPoint(x: 14.5801, y: 6.22))
        path.addLine(to: CGPoint(x: 12.7901, y: 4.43))
        path.addCurve(to: CGPoint(x: 8.0001, y: 2.83), control1: CGPoint(x: 11.5301, y: 3.17), control2: CGPoint(x: 9.7401, y: 2.58))
        path.addCurve(to: CGPoint(x: 7.8101, y: 3.36), control1: CGPoint(x: 7.6901, y: 2.88), control2: CGPoint(x: 7.5801, y: 3.14))
        path.addLine(to: CGPoint(x: 12.3501, y: 7.90))
        path.addCurve(to: CGPoint(x: 12.3501, y: 8.96), control1: CGPoint(x: 12.6401, y: 8.19), control2: CGPoint(x: 12.6401, y: 8.67))
        path.addLine(to: CGPoint(x: 11.2101, y: 10.10))
        path.addCurve(to: CGPoint(x: 11.2101, y: 10.53), control1: CGPoint(x: 11.0901, y: 10.22), control2: CGPoint(x: 11.0901, y: 10.41))
        path.addLine(to: CGPoint(x: 14.2501, y: 13.57))
        path.addCurve(to: CGPoint(x: 14.6601, y: 13.58), control1: CGPoint(x: 14.3701, y: 13.69), control2: CGPoint(x: 14.5601, y: 13.68))
        path.addLine(to: CGPoint(x: 15.7601, y: 12.48))
        path.addCurve(to: CGPoint(x: 16.3601, y: 12.19), control1: CGPoint(x: 15.9201, y: 12.29), control2: CGPoint(x: 16.1301, y: 12.19))
        path.closeSubpath()
    }
}

private struct DictionaryHeaderSettingsIcon: View {
    var body: some View {
        ZStack {
            DictionaryHeaderSettingsIconShape(part: .leftPanel)
                .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            DictionaryHeaderSettingsIconShape(part: .rightPanel)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            DictionaryHeaderSettingsIconShape(part: .divider)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            DictionaryHeaderSettingsIconShape(part: .dots)
                .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct DictionaryHeaderSettingsIconShape: Shape {
    enum Part {
        case leftPanel
        case rightPanel
        case divider
        case dots
    }

    let part: Part

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: rect.midX - 12 * scale,
            ty: rect.midY - 12 * scale
        )
        var path = Path()
        switch part {
        case .leftPanel:
            path.move(to: CGPoint(x: 11.02, y: 19.5))
            path.addLine(to: CGPoint(x: 7.5, y: 19.5))
            path.addCurve(to: CGPoint(x: 5.84, y: 19.41), control1: CGPoint(x: 6.88, y: 19.5), control2: CGPoint(x: 6.33, y: 19.48))
            path.addCurve(to: CGPoint(x: 2.5, y: 14.5), control1: CGPoint(x: 3.21, y: 19.12), control2: CGPoint(x: 2.5, y: 17.88))
            path.addLine(to: CGPoint(x: 2.5, y: 9.5))
            path.addCurve(to: CGPoint(x: 5.84, y: 4.59), control1: CGPoint(x: 2.5, y: 6.12), control2: CGPoint(x: 3.21, y: 4.88))
            path.addCurve(to: CGPoint(x: 7.5, y: 4.5), control1: CGPoint(x: 6.33, y: 4.52), control2: CGPoint(x: 6.88, y: 4.5))
            path.addLine(to: CGPoint(x: 10.96, y: 4.5))
        case .rightPanel:
            path.move(to: CGPoint(x: 15.02, y: 4.5))
            path.addLine(to: CGPoint(x: 16.5, y: 4.5))
            path.addCurve(to: CGPoint(x: 18.16, y: 4.59), control1: CGPoint(x: 17.12, y: 4.5), control2: CGPoint(x: 17.67, y: 4.52))
            path.addCurve(to: CGPoint(x: 21.5, y: 9.5), control1: CGPoint(x: 20.79, y: 4.88), control2: CGPoint(x: 21.5, y: 6.12))
            path.addLine(to: CGPoint(x: 21.5, y: 14.5))
            path.addCurve(to: CGPoint(x: 18.16, y: 19.41), control1: CGPoint(x: 21.5, y: 17.88), control2: CGPoint(x: 20.79, y: 19.12))
            path.addCurve(to: CGPoint(x: 16.5, y: 19.5), control1: CGPoint(x: 17.67, y: 19.48), control2: CGPoint(x: 17.12, y: 19.5))
            path.addLine(to: CGPoint(x: 15.02, y: 19.5))
        case .divider:
            path.move(to: CGPoint(x: 15, y: 2))
            path.addLine(to: CGPoint(x: 15, y: 22))
        case .dots:
            path.move(to: CGPoint(x: 11.0946, y: 12))
            path.addLine(to: CGPoint(x: 11.1036, y: 12))
            path.move(to: CGPoint(x: 7.0946, y: 12))
            path.addLine(to: CGPoint(x: 7.1036, y: 12))
        }
        return path.applying(transform)
    }
}

private struct DictionaryHeaderIconButton<Icon: View>: View {
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 15, height: 15)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(DictionaryHeaderIconButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DictionaryHeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DictionaryHeaderIconButtonStyleBody(configuration: configuration)
    }
}

private struct DictionaryHeaderIconButtonStyleBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(Color.secondary)
            .background(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
    }

    private var fillColor: Color {
        if configuration.isPressed {
            return SettingsUIStyle.subtleFillColor.opacity(0.92)
        }
        if isHovered {
            return SettingsUIStyle.subtleFillColor.opacity(0.72)
        }
        return SettingsUIStyle.subtleFillColor
    }
}

private struct DictionaryActionIcon: View {
    enum Kind {
        case createCategory
        case deleteCategory
        case createTerm
    }

    let kind: Kind
    var size: CGFloat = 18

    var body: some View {
        DictionaryActionIconShape(kind: kind)
            .fill(kind == .deleteCategory ? Color.red : Color.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct DictionaryActionIconShape: Shape {
    let kind: DictionaryActionIcon.Kind

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: rect.midX - 12 * scale,
            ty: rect.midY - 12 * scale
        )

        var path = Path()
        switch kind {
        case .createCategory:
            addFolderPlus(to: &path)
        case .deleteCategory:
            addFolderDelete(to: &path)
        case .createTerm:
            addBookmarkPlus(to: &path)
        }
        return path.applying(transform)
    }

    private func addFolderPlus(to path: inout Path) {
        path.move(to: CGPoint(x: 12.0601, y: 17.25))
        path.addCurve(to: CGPoint(x: 11.3101, y: 16.5), control1: CGPoint(x: 11.6501, y: 17.25), control2: CGPoint(x: 11.3101, y: 16.91))
        path.addLine(to: CGPoint(x: 11.3101, y: 11.5))
        path.addCurve(to: CGPoint(x: 12.0601, y: 10.75), control1: CGPoint(x: 11.3101, y: 11.09), control2: CGPoint(x: 11.6501, y: 10.75))
        path.addCurve(to: CGPoint(x: 12.8101, y: 11.5), control1: CGPoint(x: 12.4701, y: 10.75), control2: CGPoint(x: 12.8101, y: 11.09))
        path.addLine(to: CGPoint(x: 12.8101, y: 16.5))
        path.addCurve(to: CGPoint(x: 12.0601, y: 17.25), control1: CGPoint(x: 12.8101, y: 16.91), control2: CGPoint(x: 12.4701, y: 17.25))
        path.closeSubpath()

        path.move(to: CGPoint(x: 14.5, y: 14.75))
        path.addLine(to: CGPoint(x: 9.5, y: 14.75))
        path.addCurve(to: CGPoint(x: 8.75, y: 14), control1: CGPoint(x: 9.09, y: 14.75), control2: CGPoint(x: 8.75, y: 14.41))
        path.addCurve(to: CGPoint(x: 9.5, y: 13.25), control1: CGPoint(x: 8.75, y: 13.59), control2: CGPoint(x: 9.09, y: 13.25))
        path.addLine(to: CGPoint(x: 14.5, y: 13.25))
        path.addCurve(to: CGPoint(x: 15.25, y: 14), control1: CGPoint(x: 14.91, y: 13.25), control2: CGPoint(x: 15.25, y: 13.59))
        path.addCurve(to: CGPoint(x: 14.5, y: 14.75), control1: CGPoint(x: 15.25, y: 14.41), control2: CGPoint(x: 14.91, y: 14.75))
        path.closeSubpath()

        addFolderOutline(to: &path)
    }

    private func addFolderDelete(to path: inout Path) {
        path.move(to: CGPoint(x: 13.81, y: 16.4799))
        path.addCurve(to: CGPoint(x: 13.28, y: 16.2599), control1: CGPoint(x: 13.62, y: 16.4799), control2: CGPoint(x: 13.43, y: 16.4099))
        path.addLine(to: CGPoint(x: 9.74, y: 12.7199))
        path.addCurve(to: CGPoint(x: 9.74, y: 11.6599), control1: CGPoint(x: 9.45, y: 12.4299), control2: CGPoint(x: 9.45, y: 11.9499))
        path.addCurve(to: CGPoint(x: 10.8, y: 11.6599), control1: CGPoint(x: 10.03, y: 11.3699), control2: CGPoint(x: 10.51, y: 11.3699))
        path.addLine(to: CGPoint(x: 14.34, y: 15.1999))
        path.addCurve(to: CGPoint(x: 14.34, y: 16.2599), control1: CGPoint(x: 14.63, y: 15.4899), control2: CGPoint(x: 14.63, y: 15.9699))
        path.addCurve(to: CGPoint(x: 13.81, y: 16.4799), control1: CGPoint(x: 14.19, y: 16.3999), control2: CGPoint(x: 14, y: 16.4799))
        path.closeSubpath()

        path.move(to: CGPoint(x: 10.2299, y: 16.5199))
        path.addCurve(to: CGPoint(x: 9.6999, y: 16.2999), control1: CGPoint(x: 10.0399, y: 16.5199), control2: CGPoint(x: 9.8499, y: 16.4499))
        path.addCurve(to: CGPoint(x: 9.6999, y: 15.2399), control1: CGPoint(x: 9.4099, y: 16.0099), control2: CGPoint(x: 9.4099, y: 15.5299))
        path.addLine(to: CGPoint(x: 13.2399, y: 11.6999))
        path.addCurve(to: CGPoint(x: 14.2999, y: 11.6999), control1: CGPoint(x: 13.5299, y: 11.4099), control2: CGPoint(x: 14.0099, y: 11.4099))
        path.addCurve(to: CGPoint(x: 14.2999, y: 12.7599), control1: CGPoint(x: 14.5899, y: 11.9899), control2: CGPoint(x: 14.5899, y: 12.4699))
        path.addLine(to: CGPoint(x: 10.7599, y: 16.2999))
        path.addCurve(to: CGPoint(x: 10.2299, y: 16.5199), control1: CGPoint(x: 10.6199, y: 16.4399), control2: CGPoint(x: 10.4199, y: 16.5199))
        path.closeSubpath()

        addFolderOutline(to: &path)
    }

    private func addFolderOutline(to path: inout Path) {
        path.move(to: CGPoint(x: 17, y: 22.75))
        path.addLine(to: CGPoint(x: 7, y: 22.75))
        path.addCurve(to: CGPoint(x: 1.25, y: 17), control1: CGPoint(x: 2.59, y: 22.75), control2: CGPoint(x: 1.25, y: 21.41))
        path.addLine(to: CGPoint(x: 1.25, y: 7))
        path.addCurve(to: CGPoint(x: 7, y: 1.25), control1: CGPoint(x: 1.25, y: 2.59), control2: CGPoint(x: 2.59, y: 1.25))
        path.addLine(to: CGPoint(x: 8.5, y: 1.25))
        path.addCurve(to: CGPoint(x: 11.5, y: 2.75), control1: CGPoint(x: 10.25, y: 1.25), control2: CGPoint(x: 10.8, y: 1.82))
        path.addLine(to: CGPoint(x: 13, y: 4.75))
        path.addCurve(to: CGPoint(x: 14, y: 5.25), control1: CGPoint(x: 13.33, y: 5.19), control2: CGPoint(x: 13.38, y: 5.25))
        path.addLine(to: CGPoint(x: 17, y: 5.25))
        path.addCurve(to: CGPoint(x: 22.75, y: 11), control1: CGPoint(x: 21.41, y: 5.25), control2: CGPoint(x: 22.75, y: 6.59))
        path.addLine(to: CGPoint(x: 22.75, y: 17))
        path.addCurve(to: CGPoint(x: 17, y: 22.75), control1: CGPoint(x: 22.75, y: 21.41), control2: CGPoint(x: 21.41, y: 22.75))
        path.closeSubpath()

        path.move(to: CGPoint(x: 7, y: 2.75))
        path.addCurve(to: CGPoint(x: 2.75, y: 7), control1: CGPoint(x: 3.43, y: 2.75), control2: CGPoint(x: 2.75, y: 3.43))
        path.addLine(to: CGPoint(x: 2.75, y: 17))
        path.addCurve(to: CGPoint(x: 7, y: 21.25), control1: CGPoint(x: 2.75, y: 20.57), control2: CGPoint(x: 3.43, y: 21.25))
        path.addLine(to: CGPoint(x: 17, y: 21.25))
        path.addCurve(to: CGPoint(x: 21.25, y: 17), control1: CGPoint(x: 20.57, y: 21.25), control2: CGPoint(x: 21.25, y: 20.57))
        path.addLine(to: CGPoint(x: 21.25, y: 11))
        path.addCurve(to: CGPoint(x: 17, y: 6.75), control1: CGPoint(x: 21.25, y: 7.43), control2: CGPoint(x: 20.57, y: 6.75))
        path.addLine(to: CGPoint(x: 14, y: 6.75))
        path.addCurve(to: CGPoint(x: 11.8, y: 5.65), control1: CGPoint(x: 12.72, y: 6.75), control2: CGPoint(x: 12.3, y: 6.31))
        path.addLine(to: CGPoint(x: 10.3, y: 3.65))
        path.addCurve(to: CGPoint(x: 8.5, y: 2.75), control1: CGPoint(x: 9.78, y: 2.96), control2: CGPoint(x: 9.63, y: 2.75))
        path.addLine(to: CGPoint(x: 7, y: 2.75))
        path.closeSubpath()
    }

    private func addBookmarkPlus(to path: inout Path) {
        path.move(to: CGPoint(x: 14.5, y: 11.4004))
        path.addLine(to: CGPoint(x: 9.5, y: 11.4004))
        path.addCurve(to: CGPoint(x: 8.75, y: 10.6504), control1: CGPoint(x: 9.09, y: 11.4004), control2: CGPoint(x: 8.75, y: 11.0604))
        path.addCurve(to: CGPoint(x: 9.5, y: 9.9004), control1: CGPoint(x: 8.75, y: 10.2404), control2: CGPoint(x: 9.09, y: 9.9004))
        path.addLine(to: CGPoint(x: 14.5, y: 9.9004))
        path.addCurve(to: CGPoint(x: 15.25, y: 10.6504), control1: CGPoint(x: 14.91, y: 9.9004), control2: CGPoint(x: 15.25, y: 10.2404))
        path.addCurve(to: CGPoint(x: 14.5, y: 11.4004), control1: CGPoint(x: 15.25, y: 11.0604), control2: CGPoint(x: 14.91, y: 11.4004))
        path.closeSubpath()

        path.move(to: CGPoint(x: 12, y: 13.9609))
        path.addCurve(to: CGPoint(x: 11.25, y: 13.2109), control1: CGPoint(x: 11.59, y: 13.9609), control2: CGPoint(x: 11.25, y: 13.6209))
        path.addLine(to: CGPoint(x: 11.25, y: 8.2109))
        path.addCurve(to: CGPoint(x: 12, y: 7.4609), control1: CGPoint(x: 11.25, y: 7.8009), control2: CGPoint(x: 11.59, y: 7.4609))
        path.addCurve(to: CGPoint(x: 12.75, y: 8.2109), control1: CGPoint(x: 12.41, y: 7.4609), control2: CGPoint(x: 12.75, y: 7.8009))
        path.addLine(to: CGPoint(x: 12.75, y: 13.2109))
        path.addCurve(to: CGPoint(x: 12, y: 13.9609), control1: CGPoint(x: 12.75, y: 13.6209), control2: CGPoint(x: 12.41, y: 13.9609))
        path.closeSubpath()

        path.move(to: CGPoint(x: 19.0701, y: 22.75))
        path.addCurve(to: CGPoint(x: 17.4601, y: 22.29), control1: CGPoint(x: 18.5601, y: 22.75), control2: CGPoint(x: 18.0001, y: 22.6))
        path.addLine(to: CGPoint(x: 12.5801, y: 19.58))
        path.addCurve(to: CGPoint(x: 11.4301, y: 19.58), control1: CGPoint(x: 12.2901, y: 19.42), control2: CGPoint(x: 11.7201, y: 19.42))
        path.addLine(to: CGPoint(x: 6.5501, y: 22.29))
        path.addCurve(to: CGPoint(x: 3.7801, y: 22.44), control1: CGPoint(x: 5.5601, y: 22.84), control2: CGPoint(x: 4.5501, y: 22.9))
        path.addCurve(to: CGPoint(x: 2.5701, y: 19.95), control1: CGPoint(x: 3.0101, y: 21.99), control2: CGPoint(x: 2.5701, y: 21.08))
        path.addLine(to: CGPoint(x: 2.5701, y: 5.86))
        path.addCurve(to: CGPoint(x: 7.1801, y: 1.25), control1: CGPoint(x: 2.5701, y: 3.32), control2: CGPoint(x: 4.6401, y: 1.25))
        path.addLine(to: CGPoint(x: 16.8301, y: 1.25))
        path.addCurve(to: CGPoint(x: 21.4401, y: 5.86), control1: CGPoint(x: 19.3701, y: 1.25), control2: CGPoint(x: 21.4401, y: 3.32))
        path.addLine(to: CGPoint(x: 21.4401, y: 19.95))
        path.addCurve(to: CGPoint(x: 20.2301, y: 22.44), control1: CGPoint(x: 21.4401, y: 21.08), control2: CGPoint(x: 21.0001, y: 21.99))
        path.addCurve(to: CGPoint(x: 19.0701, y: 22.75), control1: CGPoint(x: 19.8801, y: 22.65), control2: CGPoint(x: 19.4801, y: 22.75))
        path.closeSubpath()

        path.move(to: CGPoint(x: 12.0001, y: 17.96))
        path.addCurve(to: CGPoint(x: 13.3001, y: 18.27), control1: CGPoint(x: 12.4701, y: 17.96), control2: CGPoint(x: 12.9301, y: 18.06))
        path.addLine(to: CGPoint(x: 18.1801, y: 20.98))
        path.addCurve(to: CGPoint(x: 19.4601, y: 21.15), control1: CGPoint(x: 18.6901, y: 21.27), control2: CGPoint(x: 19.1601, y: 21.33))
        path.addCurve(to: CGPoint(x: 19.9301, y: 19.95), control1: CGPoint(x: 19.7601, y: 20.97), control2: CGPoint(x: 19.9301, y: 20.54))
        path.addLine(to: CGPoint(x: 19.9301, y: 5.86))
        path.addCurve(to: CGPoint(x: 16.8201, y: 2.75), control1: CGPoint(x: 19.9301, y: 4.15), control2: CGPoint(x: 18.5301, y: 2.75))
        path.addLine(to: CGPoint(x: 7.1801, y: 2.75))
        path.addCurve(to: CGPoint(x: 4.0701, y: 5.86), control1: CGPoint(x: 5.4701, y: 2.75), control2: CGPoint(x: 4.0701, y: 4.15))
        path.addLine(to: CGPoint(x: 4.0701, y: 19.95))
        path.addCurve(to: CGPoint(x: 4.5401, y: 21.15), control1: CGPoint(x: 4.0701, y: 20.54), control2: CGPoint(x: 4.2401, y: 20.98))
        path.addCurve(to: CGPoint(x: 5.8201, y: 20.98), control1: CGPoint(x: 4.8401, y: 21.32), control2: CGPoint(x: 5.3101, y: 21.27))
        path.addLine(to: CGPoint(x: 10.7001, y: 18.27))
        path.addCurve(to: CGPoint(x: 12.0001, y: 17.96), control1: CGPoint(x: 11.0701, y: 18.06), control2: CGPoint(x: 11.5301, y: 17.96))
        path.closeSubpath()
    }
}

import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct FeatureModelSelectorDialog: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    let title: String
    let entries: [FeatureModelSelectorEntry]
    let selectedID: FeatureModelSelectionID
    let onSelect: (FeatureModelSelectionID) -> Void

    @State private var selectedTags = Set<String>()

    private var statusFilterTags: Set<String> {
        FeatureModelSelectorFiltering.statusFilterTags
    }

    private var defaultSelectedTags: Set<String> {
        FeatureModelSelectorFiltering.defaultSelectedTags(entries: entries)
    }

    private var locationScopedEntriesForTags: [FeatureModelSelectorEntry] {
        FeatureModelSelectorFiltering.locationScopedEntries(entries: entries, selectedTags: selectedTags)
    }

    private var availableTags: [String] {
        FeatureModelSelectorFiltering.availableTags(
            entries: entries,
            selectedTags: selectedTags,
            locationScopedEntries: locationScopedEntriesForTags
        )
    }

    private var availableTagGroups: [[String]] {
        let available = Set(availableTags)
        var groups = [[String]]()
        let locationGroup = FeatureSelectorTagPriority.groups[0].filter { available.contains($0) }
        if !locationGroup.isEmpty {
            groups.append(locationGroup)
        }
        groups.append(
            contentsOf: FeatureSelectorTagPriority.groups.dropFirst()
                .map { $0.filter { available.contains($0) } }
                .filter { !$0.isEmpty }
        )
        return groups
    }

    private var filteredEntries: [FeatureModelSelectorEntry] {
        FeatureModelSelectorFiltering.filteredEntries(entries: entries, selectedTags: selectedTags)
    }

    private var selectedEntry: FeatureModelSelectorEntry? {
        entries.first(where: { $0.selectionID == selectedID })
    }

    private var selectionReminder: String? {
        guard let selectedEntry, !selectedEntry.isSelectable else { return nil }
        guard let disabledReason = selectedEntry.disabledReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !disabledReason.isEmpty else { return nil }
        return disabledReason
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SettingsCompactIconButtonStyle())
            }

            if let selectionReminder {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(selectionReminder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if !availableTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(availableTagGroups.enumerated()), id: \.offset) { index, group in
                            HStack(spacing: 8) {
                                ForEach(group, id: \.self) { tag in
                                    FeatureModelTagChip(
                                        title: tag,
                                        isSelected: selectedTags.contains(tag)
                                    ) {
                                        toggleTag(tag)
                                    }
                                }
                            }

                            if index < availableTagGroups.count - 1 {
                                Rectangle()
                                    .fill(SettingsUIStyle.subtleBorderColor.opacity(0.95))
                                    .frame(width: 1, height: 20)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if filteredEntries.isEmpty {
                        FeatureSelectorEmptyState()
                    } else {
                        ForEach(filteredEntries) { entry in
                            FeatureModelSelectorRow(
                                entry: entry,
                                isSelected: entry.selectionID == selectedID,
                                onSelect: {
                                    onSelect(entry.selectionID)
                                    dismiss()
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 400)
        }
        .padding(18)
        .frame(width: 640)
        .background(SettingsUIStyle.groupedFillColor)
        .onAppear(perform: initializeDefaultTags)
        .id(interfaceLanguageRaw)
    }

    private func toggleTag(_ tag: String) {
        selectedTags = FeatureModelSelectorFiltering.toggledTags(
            current: selectedTags,
            tag: tag,
            entries: entries
        )
    }

    private func initializeDefaultTags() {
        guard selectedTags.isEmpty else { return }
        selectedTags = defaultSelectedTags
    }
}

enum FeatureModelSelectorFiltering {
    static var statusFilterTags: Set<String> {
        Set<String>([localized("Installed"), localized("Configured"), localized("In Use")])
    }

    static func defaultSelectedTags(entries: [FeatureModelSelectorEntry]) -> Set<String> {
        Set<String>([localized("Installed"), localized("Configured")]).intersection(
            Set<String>(availableTags(entries: entries, selectedTags: []))
        )
    }

    static func locationScopedEntries(
        entries: [FeatureModelSelectorEntry],
        selectedTags: Set<String>
    ) -> [FeatureModelSelectorEntry] {
        if selectedTags.contains(localized("Local")) {
            return entries.filter { $0.filterTags.contains(localized("Local")) }
        }
        if selectedTags.contains(localized("Remote")) {
            return entries.filter { $0.filterTags.contains(localized("Remote")) }
        }
        return entries
    }

    static func availableTags(
        entries: [FeatureModelSelectorEntry],
        selectedTags: Set<String>,
        locationScopedEntries overrideEntries: [FeatureModelSelectorEntry]? = nil
    ) -> [String] {
        let scopedEntries = overrideEntries ?? self.locationScopedEntries(entries: entries, selectedTags: selectedTags)
        let locationTags = Set<String>(entries.flatMap(\.filterTags)).intersection(FeatureSelectorTagPriority.locationTags)
        let tagSet = locationTags.union(Set<String>(scopedEntries.flatMap(\.filterTags)))
        return FeatureSelectorTagPriority.priority.compactMap { tagSet.contains($0) ? $0 : nil }
    }

    static func filteredEntries(
        entries: [FeatureModelSelectorEntry],
        selectedTags: Set<String>
    ) -> [FeatureModelSelectorEntry] {
        let matchingEntries: [FeatureModelSelectorEntry]
        if selectedTags.isEmpty {
            matchingEntries = entries
        } else {
            let selectedStatusTags = selectedTags.intersection(statusFilterTags)
            let requiredTags = selectedTags.subtracting(selectedStatusTags)
            matchingEntries = entries.filter { entry in
                let entryTags = Set(entry.filterTags)
                guard requiredTags.isSubset(of: entryTags) else { return false }
                if selectedStatusTags.isEmpty {
                    return true
                }
                return !entryTags.intersection(selectedStatusTags).isEmpty
            }
        }

        return matchingEntries.enumerated()
            .sorted { lhs, rhs in
                let lhsInUse = !lhs.element.usageLocations.isEmpty
                let rhsInUse = !rhs.element.usageLocations.isEmpty
                if lhsInUse != rhsInUse {
                    return lhsInUse && !rhsInUse
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func toggledTags(
        current: Set<String>,
        tag: String,
        entries: [FeatureModelSelectorEntry]
    ) -> Set<String> {
        var next = current
        if next.contains(tag) {
            next.remove(tag)
        } else {
            if FeatureSelectorTagPriority.exclusiveSelectionTags.contains(tag) {
                next.subtract(FeatureSelectorTagPriority.exclusiveSelectionTags)
            }
            next.insert(tag)
        }
        return next.intersection(Set<String>(availableTags(entries: entries, selectedTags: next)))
    }
}

private struct FeatureModelSelectorRow: View {
    let entry: FeatureModelSelectorEntry
    let isSelected: Bool
    let onSelect: () -> Void

    private var hintText: String? {
        if let disabledReason = entry.disabledReason, !entry.isSelectable {
            return disabledReason
        }

        let trimmed = entry.statusText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let genericStatuses = Set([
            localized("Installed"),
            localized("Not installed"),
            localized("Configured"),
            localized("Not configured"),
            localized("Available on this Mac"),
            localized("Works immediately with no model download.")
        ] as [String])

        guard !trimmed.isEmpty, !genericStatuses.contains(trimmed) else { return nil }
        return trimmed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(entry.title)
                        .font(.headline)

                    Text(entry.engine)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SettingsUIStyle.groupedFillColor)
                        )

                    if let hintText {
                        Text(hintText)
                            .font(.caption.weight(entry.isSelectable ? .regular : .semibold))
                            .foregroundStyle(entry.isSelectable ? Color.secondary : Color.orange)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    FeatureSelectorMetaText(title: localized("Size"), value: entry.sizeText)
                    FeatureSelectorMetaText(title: localized("Score"), value: entry.ratingText)
                    if !entry.usageLocations.isEmpty {
                        FeatureSelectorMetaText(
                            title: localized("Usage"),
                            value: entry.usageLocations.joined(separator: " · ")
                        )
                    }
                }

                FeatureSelectorTagStrip(tags: entry.displayTags)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if isSelected {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(localized("Selected"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 1)
                )
            } else if entry.isSelectable {
                Button(localized("Select")) {
                    onSelect()
                }
                .buttonStyle(SettingsCompactActionButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SettingsUIStyle.controlFillColor.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : SettingsUIStyle.subtleBorderColor, lineWidth: 1)
        )
    }
}

private struct FeatureSelectorEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(localized("No models match the selected tags."))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SettingsUIStyle.controlFillColor.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
        )
    }
}

private struct FeatureModelTagChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : SettingsUIStyle.controlFillColor)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.28) : SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FeatureSelectorMetaText: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }
}

private struct FeatureSelectorTagStrip: View {
    let tags: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    tagChip(tag)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Array(tags.prefix(5)), id: \.self) { tag in
                    tagChip(tag)
                }
                if tags.count > 5 {
                    tagChip("+\(tags.count - 5)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(SettingsUIStyle.groupedFillColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
    }
}

private enum FeatureSelectorTagPriority {
    static var locationTags: Set<String> {
        Set<String>([localized("Local"), localized("Remote")])
    }

    static var groups: [[String]] {
        [
            [localized("Local"), localized("Remote")],
            [localized("Fast"), localized("Accurate"), localized("Realtime"), localized("Multilingual")],
            [localized("Installed"), localized("Configured"), localized("In Use")]
        ]
    }

    static var exclusiveSelectionTags: Set<String> {
        locationTags
    }

    static var priority: [String] {
        groups.flatMap { $0 }
    }
}

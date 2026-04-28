import Foundation

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct LocalModelSeriesDescriptor: Hashable {
    let id: String
    let title: String
    let variantTitle: String
    let engine: String
}

struct ModelCatalogGroupSection: Identifiable {
    let id: String
    let title: String
    let engine: String
    let tags: [String]
    let usageLocations: [String]
    let installedCount: Int
    let ratingText: String
    let badgeText: String?
    let entries: [ModelCatalogEntry]
    let defaultExpanded: Bool
}

enum ModelCatalogDisplayItem: Identifiable {
    case row(ModelCatalogEntry)
    case group(ModelCatalogGroupSection)

    var id: String {
        switch self {
        case .row(let entry):
            return "row:\(entry.id)"
        case .group(let group):
            return "group:\(group.id)"
        }
    }
}

struct FeatureModelSelectorGroupSection: Identifiable {
    let id: String
    let title: String
    let engine: String
    let tags: [String]
    let usageLocations: [String]
    let installedCount: Int
    let ratingText: String
    let entries: [FeatureModelSelectorEntry]
    let defaultExpanded: Bool
}

enum FeatureModelSelectorDisplayItem: Identifiable {
    case row(FeatureModelSelectorEntry)
    case group(FeatureModelSelectorGroupSection)

    var id: String {
        switch self {
        case .row(let entry):
            return "row:\(entry.id)"
        case .group(let group):
            return "group:\(group.id)"
        }
    }
}

enum LocalModelSeriesGrouping {
    static func modelCatalogItems(from entries: [ModelCatalogEntry]) -> [ModelCatalogDisplayItem] {
        let groupedSource: [(LocalModelSeriesDescriptor, ModelCatalogEntry)] = entries.compactMap { entry in
            guard let descriptor = entry.localSeriesDescriptor else { return nil }
            return (descriptor, entry)
        }
        let groupedEntries = Dictionary(grouping: groupedSource, by: { $0.0.id })
        let groupedIDs = Set(groupedEntries.compactMap { $0.value.count > 1 ? $0.key : nil })
        var emittedIDs = Set<String>()
        var items = [ModelCatalogDisplayItem]()

        for entry in entries {
            guard let descriptor = entry.localSeriesDescriptor, groupedIDs.contains(descriptor.id) else {
                items.append(.row(entry))
                continue
            }
            guard emittedIDs.insert(descriptor.id).inserted else { continue }
            let groupEntries = groupedEntries[descriptor.id]?.map { $0.1 } ?? [entry]
            items.append(
                .group(
                    ModelCatalogGroupSection(
                        id: descriptor.id,
                        title: descriptor.title,
                        engine: descriptor.engine,
                        tags: prioritizedTags(from: groupEntries.flatMap { $0.displayTags }),
                        usageLocations: orderedUsageLocations(from: groupEntries.flatMap { $0.usageLocations }),
                        installedCount: groupEntries.filter { $0.filterTags.contains(localized("Installed")) }.count,
                        ratingText: averageRatingText(from: groupEntries.map { $0.ratingText }),
                        badgeText: groupEntries.compactMap { $0.badgeText }.first,
                        entries: groupEntries,
                        defaultExpanded: groupEntries.contains(where: { !$0.usageLocations.isEmpty })
                    )
                )
            )
        }

        return items
    }

    static func featureSelectorItems(
        from entries: [FeatureModelSelectorEntry],
        selectedID: FeatureModelSelectionID
    ) -> [FeatureModelSelectorDisplayItem] {
        let groupedSource: [(LocalModelSeriesDescriptor, FeatureModelSelectorEntry)] = entries.compactMap { entry in
            guard let descriptor = entry.localSeriesDescriptor else { return nil }
            return (descriptor, entry)
        }
        let groupedEntries = Dictionary(grouping: groupedSource, by: { $0.0.id })
        let groupedIDs = Set(groupedEntries.compactMap { $0.value.count > 1 ? $0.key : nil })
        var emittedIDs = Set<String>()
        var items = [FeatureModelSelectorDisplayItem]()

        for entry in entries {
            guard let descriptor = entry.localSeriesDescriptor, groupedIDs.contains(descriptor.id) else {
                items.append(.row(entry))
                continue
            }
            guard emittedIDs.insert(descriptor.id).inserted else { continue }
            let groupEntries = groupedEntries[descriptor.id]?.map { $0.1 } ?? [entry]
            items.append(
                .group(
                    FeatureModelSelectorGroupSection(
                        id: descriptor.id,
                        title: descriptor.title,
                        engine: descriptor.engine,
                        tags: prioritizedTags(from: groupEntries.flatMap { $0.displayTags }),
                        usageLocations: orderedUsageLocations(from: groupEntries.flatMap { $0.usageLocations }),
                        installedCount: groupEntries.filter { $0.filterTags.contains(localized("Installed")) }.count,
                        ratingText: averageRatingText(from: groupEntries.map { $0.ratingText }),
                        entries: groupEntries,
                        defaultExpanded: groupEntries.contains(where: {
                            $0.selectionID == selectedID || !$0.usageLocations.isEmpty
                        })
                    )
                )
            )
        }

        return items
    }

    static func prioritizedTags(from tags: [String]) -> [String] {
        let uniqueTags = deduplicated(tags)
        let priority = [
            localized("Local"),
            localized("Remote"),
            localized("Built-in"),
            localized("Fast"),
            localized("Accurate"),
            localized("Realtime"),
            localized("Supports Primary Language"),
            localized("Does Not Support Primary Language"),
            localized("Configured"),
            localized("In Use")
        ]
        let prioritized = priority.filter { uniqueTags.contains($0) }
        let remainder = uniqueTags.filter { !priority.contains($0) }
        return prioritized + remainder
    }

    private static func orderedUsageLocations(from locations: [String]) -> [String] {
        let unique = deduplicated(locations)
        let priority = [
            localized("Transcription"),
            localized("Notes"),
            localized("Translation"),
            localized("Rewrite"),
            localized("Meeting")
        ]
        let prioritized = priority.filter { unique.contains($0) }
        let remainder = unique.filter { !priority.contains($0) }
        return prioritized + remainder
    }

    private static func averageRatingText(from values: [String]) -> String {
        let ratings = values.compactMap { Double($0) }
        guard !ratings.isEmpty else { return "-" }
        let average = ratings.reduce(0, +) / Double(ratings.count)
        return String(format: "%.1f", average)
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

extension ModelCatalogEntry {
    var localSeriesDescriptor: LocalModelSeriesDescriptor? {
        LocalModelSeriesClassifier.classify(title: title, engine: engine)
    }

    var groupedVariantTitle: String {
        localSeriesDescriptor?.variantTitle ?? title
    }
}

extension FeatureModelSelectorEntry {
    var localSeriesDescriptor: LocalModelSeriesDescriptor? {
        LocalModelSeriesClassifier.classify(title: title, engine: engine)
    }

    var groupedVariantTitle: String {
        localSeriesDescriptor?.variantTitle ?? title
    }
}

enum LocalModelSeriesClassifier {
    static func classify(title: String, engine: String) -> LocalModelSeriesDescriptor? {
        guard let family = familyInfo(title: title, engine: engine) else { return nil }
        return LocalModelSeriesDescriptor(
            id: "\(engine):\(family.title)",
            title: family.title,
            variantTitle: family.variantTitle,
            engine: engine
        )
    }

    private static func familyInfo(title: String, engine: String) -> (title: String, variantTitle: String)? {
        if engine == localized("Whisper") {
            guard title != localized("Whisper Direct Translate") else { return nil }
            return prefixedFamily(title: title, prefix: "Whisper ", family: "Whisper")
        }

        if engine == localized("MLX Audio") {
            if let family = prefixedFamily(title: title, prefix: "Qwen3-ASR ", family: "Qwen3-ASR") {
                return family
            }
            if let family = prefixedFamily(title: title, prefix: "Voxtral Realtime ", family: "Voxtral Realtime") {
                return family
            }
            if let family = prefixedFamily(title: title, prefix: "Parakeet ", family: "Parakeet") {
                return family
            }
            return nil
        }

        if engine == localized("Local LLM") {
            if let family = prefixedFamily(title: title, prefix: "Qwen", family: "Qwen") {
                return family
            }
            if let family = prefixedFamily(title: title, prefix: "GLM", family: "GLM") {
                return family
            }
            if let family = prefixedFamily(title: title, prefix: "Mistral ", family: "Mistral") {
                return family
            }
            if let family = prefixedFamily(title: title, prefix: "Gemma ", family: "Gemma") {
                return family
            }
            if title.contains("Llama") {
                let normalized = title.replacingOccurrences(of: "Meta ", with: "")
                return prefixedFamily(title: normalized, prefix: "Llama ", family: "Llama")
            }
        }

        return nil
    }

    private static func prefixedFamily(
        title: String,
        prefix: String,
        family: String
    ) -> (title: String, variantTitle: String)? {
        guard title.hasPrefix(prefix) else { return nil }
        let variant = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            title: family,
            variantTitle: variant.isEmpty ? title : variant
        )
    }
}

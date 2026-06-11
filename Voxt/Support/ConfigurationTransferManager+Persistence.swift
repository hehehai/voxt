import Foundation

extension ConfigurationTransferManager {
    static func persistTrackedMicrophoneRecords(
        _ records: [TrackedMicrophoneRecord],
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(records),
              let raw = String(data: data, encoding: .utf8)
        else {
            defaults.removeObject(forKey: AppPreferenceKey.trackedMicrophoneRecords)
            return
        }
        defaults.set(raw, forKey: AppPreferenceKey.trackedMicrophoneRecords)
    }

    static func loadDictionarySuggestionFilterSettings(defaults: UserDefaults) -> DictionarySuggestionFilterSettings {
        guard let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionFilterSettings),
              let decoded = try? JSONDecoder().decode(DictionarySuggestionFilterSettings.self, from: data)
        else {
            return .defaultValue
        }
        return decoded.sanitized()
    }

    static func loadDictionaryHistoryScanCheckpoint(defaults: UserDefaults) -> DictionaryHistoryScanCheckpoint? {
        guard let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint),
              let checkpoint = try? JSONDecoder().decode(DictionaryHistoryScanCheckpoint.self, from: data)
        else {
            return nil
        }
        return checkpoint
    }

    static func persistDictionaryHistoryScanCheckpoint(
        _ checkpoint: DictionaryHistoryScanCheckpoint?,
        defaults: UserDefaults
    ) {
        guard let checkpoint else {
            defaults.removeObject(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
            return
        }
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        defaults.set(data, forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
    }

    static func loadDictionaryEntries(environment: FileEnvironment) -> [DictionaryEntry] {
        if let repository = environment.dictionaryRepository(),
           let entries = try? repository.allEntries() {
            return entries
        }

        guard let url = try? environment.dictionaryEntriesURL(),
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    static func persistDictionaryEntries(
        _ entries: [DictionaryEntry],
        environment: FileEnvironment
    ) {
        if let repository = environment.dictionaryRepository() {
            do {
                try repository.replaceAll(entries)
            } catch {
                VoxtLog.error("Failed to persist dictionary entries during configuration import: \(error.localizedDescription)")
            }
            return
        }

        guard let url = try? environment.dictionaryEntriesURL(),
              let data = try? JSONEncoder().encode(entries)
        else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            VoxtLog.error("Failed to persist dictionary entries during configuration import: \(error.localizedDescription)")
        }
    }

    static func loadDictionaryCategories(environment: FileEnvironment) -> [DictionaryCategory] {
        if let repository = environment.dictionaryRepository(),
           let categories = try? repository.allCategories() {
            return categories
        }

        let entries = loadDictionaryEntries(environment: environment)
        var categoriesByID: [UUID: DictionaryCategory] = [
            DictionaryCategory.defaultID: DictionaryCategory.defaultCategory
        ]
        for entry in entries where categoriesByID[entry.categoryID] == nil {
            categoriesByID[entry.categoryID] = DictionaryCategory(
                id: entry.categoryID,
                name: entry.categoryNameSnapshot ?? DictionaryCategory.defaultName,
                isDefault: entry.categoryID == DictionaryCategory.defaultID,
                isExpanded: true,
                sortOrder: categoriesByID.count
            )
        }
        return categoriesByID.values.sorted {
            if $0.isDefault != $1.isDefault {
                return $0.isDefault
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func persistDictionary(
        entries: [DictionaryEntry],
        categories: [DictionaryCategory],
        environment: FileEnvironment
    ) {
        if let repository = environment.dictionaryRepository() {
            do {
                try repository.replaceAll(entries: entries, categories: categories)
            } catch {
                VoxtLog.error("Failed to persist dictionary during configuration import: \(error.localizedDescription)")
            }
            return
        }

        persistDictionaryEntries(entries, environment: environment)
    }

    static func loadDictionarySuggestions(environment: FileEnvironment) -> [DictionarySuggestion] {
        guard let url = try? environment.dictionarySuggestionsURL(),
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let suggestions = try? JSONDecoder().decode([DictionarySuggestion].self, from: data)
        else {
            return []
        }
        return suggestions
    }

    static func persistDictionarySuggestions(
        _ suggestions: [DictionarySuggestion],
        environment: FileEnvironment
    ) {
        guard let url = try? environment.dictionarySuggestionsURL(),
              let data = try? JSONEncoder().encode(suggestions)
        else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            VoxtLog.error("Failed to persist dictionary suggestions during configuration import: \(error.localizedDescription)")
        }
    }

    static func loadAppBranchGroups(defaults: UserDefaults) -> [ExportedAppBranchGroup] {
        guard let data = defaults.data(forKey: AppPreferenceKey.appBranchGroups),
              let groups = try? JSONDecoder().decode([AppBranchGroup].self, from: data)
        else {
            return []
        }
        return groups.map {
            ExportedAppBranchGroup(
                id: $0.id,
                name: $0.name,
                prompt: $0.prompt,
                appBundleIDs: $0.appBundleIDs,
                appRefs: $0.appRefs,
                urlPatternIDs: $0.urlPatternIDs,
                isExpanded: $0.isExpanded,
                iconPlaceholder: ""
            )
        }
    }

    static func loadBranchURLs(defaults: UserDefaults) -> [ExportedBranchURLItem] {
        guard let data = defaults.data(forKey: AppPreferenceKey.appBranchURLs),
              let items = try? JSONDecoder().decode([BranchURLItem].self, from: data)
        else {
            return []
        }
        return items.map {
            ExportedBranchURLItem(
                id: $0.id,
                pattern: $0.pattern,
                iconPlaceholder: ""
            )
        }
    }

    static func dictionaryFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary.json")
    }

    static func dictionarySuggestionsFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary-suggestions.json")
    }
}

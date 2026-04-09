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
                iconPlaceholder: "app-icon-placeholder"
            )
        }
    }

    static func loadBranchURLs(defaults: UserDefaults) -> [ExportedBranchURLItem] {
        guard let data = defaults.data(forKey: AppPreferenceKey.appBranchURLs),
              let urls = try? JSONDecoder().decode([BranchURLItem].self, from: data)
        else {
            return []
        }
        return urls.map { ExportedBranchURLItem(id: $0.id, pattern: $0.pattern, iconPlaceholder: "url-icon-placeholder") }
    }

    static func loadDictionaryEntries(environment: FileEnvironment) -> [DictionaryEntry] {
        guard let url = try? environment.dictionaryEntriesURL(),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    static func loadDictionarySuggestionFilterSettings(
        defaults: UserDefaults
    ) -> DictionarySuggestionFilterSettings {
        guard
            let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionFilterSettings),
            let settings = try? JSONDecoder().decode(DictionarySuggestionFilterSettings.self, from: data)
        else {
            return .defaultValue
        }
        return settings.sanitized()
    }

    static func loadDictionaryHistoryScanCheckpoint(
        defaults: UserDefaults
    ) -> DictionaryHistoryScanCheckpoint? {
        guard
            let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint),
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

        guard let data = try? JSONEncoder().encode(checkpoint) else {
            defaults.removeObject(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
            return
        }
        defaults.set(data, forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
    }

    static func persistDictionaryEntries(
        _ entries: [DictionaryEntry],
        environment: FileEnvironment
    ) {
        guard let url = try? environment.dictionaryEntriesURL(),
              let data = try? JSONEncoder().encode(entries)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Ignore config import dictionary persistence failures.
        }
    }

    static func loadDictionarySuggestions(environment: FileEnvironment) -> [DictionarySuggestion] {
        guard let url = try? environment.dictionarySuggestionsURL(),
              let data = try? Data(contentsOf: url),
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
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Ignore config import dictionary persistence failures.
        }
    }
}

import Foundation

extension TranscriptionHistoryStore {
    func historyFileLocation() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("transcription-history.json")
    }

    func persistEntries() {
        do {
            let data = try JSONEncoder().encode(allEntries)
            let url = try historyFileLocation()
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }

    func currentHistoryRetentionPeriod() -> HistoryRetentionPeriod {
        let raw = defaults.string(forKey: AppPreferenceKey.historyRetentionPeriod)
        return HistoryRetentionPeriod(rawValue: raw ?? "") ?? .thirtyDays
    }
}

import Foundation
import XCTest
@testable import Voxt

enum TestDoubles {
    static func makeUserDefaults(testName: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "VoxtTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

final class TemporaryDirectory {
    let url: URL

    init() throws {
        let baseURL = FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        url = directoryURL
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

enum TestEnvironmentFactory {
    static func configurationTransferEnvironment(
        in directory: TemporaryDirectory
    ) -> ConfigurationTransferManager.FileEnvironment {
        ConfigurationTransferManager.FileEnvironment(
            dictionaryEntriesURL: { directory.url.appendingPathComponent("dictionary.json") },
            dictionarySuggestionsURL: { directory.url.appendingPathComponent("dictionary-suggestions.json") }
        )
    }
}


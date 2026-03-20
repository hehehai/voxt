import XCTest
@testable import Voxt

final class SettingsTypesTests: XCTestCase {
    func testUserMainLanguageSanitizedSelectionDeduplicatesAndFallsBack() {
        XCTAssertEqual(
            UserMainLanguageOption.sanitizedSelection(["zh-CN", "zh-Hans", "EN", "unknown", "en"]),
            ["zh-hans", "en"]
        )
        XCTAssertEqual(
            UserMainLanguageOption.sanitizedSelection(["unknown"]),
            UserMainLanguageOption.defaultSelectionCodes()
        )
    }

    func testStoredSelectionAndStorageValueRoundTrip() {
        let raw = UserMainLanguageOption.storageValue(for: ["zh-Hant", "en"])

        XCTAssertEqual(UserMainLanguageOption.storedSelection(from: raw), ["zh-hant", "en"])
    }

    func testFallbackOptionUsesPreferredLanguages() {
        let option = UserMainLanguageOption.fallbackOption(preferredLanguages: ["zh-TW", "en-US"])

        XCTAssertEqual(option.code, "zh-hant")
        XCTAssertTrue(option.isChinese)
        XCTAssertTrue(option.isTraditionalChinese)
        XCTAssertEqual(option.baseLanguageCode, "zh")
    }

    func testDictionarySuggestionFilterSettingsSanitizedClampsAndDefaultsPrompt() {
        let sanitized = DictionarySuggestionFilterSettings(
            prompt: "   ",
            batchSize: 999,
            maxCandidatesPerBatch: 0
        ).sanitized()

        XCTAssertEqual(sanitized.prompt, DictionarySuggestionFilterSettings.defaultPrompt)
        XCTAssertEqual(sanitized.batchSize, DictionarySuggestionFilterSettings.maximumBatchSize)
        XCTAssertEqual(sanitized.maxCandidatesPerBatch, DictionarySuggestionFilterSettings.minimumMaxCandidates)
    }
}


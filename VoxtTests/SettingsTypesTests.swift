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

    func testOnboardingStepStatusResolverMatchesExpectedRules() {
        let readySnapshot = OnboardingStepStatusSnapshot(
            hasModelIssues: false,
            hasRecordingMicrophone: true,
            hasRecordingPermissions: true,
            hasRewriteIssues: false,
            appEnhancementEnabled: true,
            meetingNotesEnabled: true,
            hasMeetingIssues: false
        )
        let blockedSnapshot = OnboardingStepStatusSnapshot(
            hasModelIssues: true,
            hasRecordingMicrophone: false,
            hasRecordingPermissions: false,
            hasRewriteIssues: true,
            appEnhancementEnabled: false,
            meetingNotesEnabled: true,
            hasMeetingIssues: true
        )

        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .language, snapshot: blockedSnapshot), .ready)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .model, snapshot: blockedSnapshot), .needsSetup)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .transcription, snapshot: blockedSnapshot), .needsSetup)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .translation, snapshot: blockedSnapshot), .ready)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .rewrite, snapshot: blockedSnapshot), .needsSetup)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .appEnhancement, snapshot: blockedSnapshot), .optional)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .meeting, snapshot: blockedSnapshot), .needsSetup)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .finish, snapshot: blockedSnapshot), .done)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .meeting, snapshot: readySnapshot), .ready)
    }
}

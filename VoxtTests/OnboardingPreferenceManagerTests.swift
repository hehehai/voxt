import XCTest
@testable import Voxt

final class OnboardingPreferenceManagerTests: XCTestCase {
    func testResolvedCompletionStateDefaultsToFalseForFreshInstall() {
        let suiteName = "VoxtTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let completed = OnboardingPreferenceManager.resolvedCompletionState(
            defaults: defaults,
            bundleIdentifier: suiteName
        )

        XCTAssertFalse(completed)
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, false)
    }

    func testResolvedCompletionStateTreatsExistingPersistentDomainAsCompleted() {
        let suiteName = "VoxtTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.setPersistentDomain(
            [AppPreferenceKey.translationTargetLanguage: TranslationTargetLanguage.english.rawValue],
            forName: suiteName
        )

        let completed = OnboardingPreferenceManager.resolvedCompletionState(
            defaults: defaults,
            bundleIdentifier: suiteName
        )

        XCTAssertTrue(completed)
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, true)
    }

    func testMarkCompletedClearsSavedStep() {
        let defaults = TestDoubles.makeUserDefaults()
        OnboardingPreferenceManager.saveLastStep(.meeting, defaults: defaults)

        OnboardingPreferenceManager.markCompleted(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, true)
        XCTAssertNil(defaults.string(forKey: AppPreferenceKey.onboardingLastStepID))
    }
}

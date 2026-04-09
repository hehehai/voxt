import XCTest
@testable import Voxt

final class LocalizationResourcesTests: XCTestCase {
    func testFeatureMenuTitleIsLocalizedInSupportedLanguages() {
        XCTAssertEqual(AppLocalization.localizedString("Feature", localeIdentifier: "en"), "Feature")
        XCTAssertEqual(AppLocalization.localizedString("Feature", localeIdentifier: "zh-Hans"), "功能")
        XCTAssertEqual(AppLocalization.localizedString("Feature", localeIdentifier: "ja"), "機能")
    }

    func testBackLabelIsLocalizedInSupportedLanguages() {
        XCTAssertEqual(AppLocalization.localizedString("Back", localeIdentifier: "en"), "Back")
        XCTAssertEqual(AppLocalization.localizedString("Back", localeIdentifier: "zh-Hans"), "返回")
        XCTAssertEqual(AppLocalization.localizedString("Back", localeIdentifier: "ja"), "戻る")
    }

    func testMeetingToggleLabelIsLocalizedInSupportedLanguages() {
        XCTAssertEqual(AppLocalization.localizedString("Enable Meeting", localeIdentifier: "en"), "Enable Meeting")

        let chinese = AppLocalization.localizedString("Enable Meeting", localeIdentifier: "zh-Hans")
        XCTAssertFalse(chinese.isEmpty)
        XCTAssertNotEqual(chinese, "Enable Meeting")

        let japanese = AppLocalization.localizedString("Enable Meeting", localeIdentifier: "ja")
        XCTAssertFalse(japanese.isEmpty)
        XCTAssertNotEqual(japanese, "Enable Meeting")
    }

    func testMeetingToggleDescriptionIsLocalizedInSupportedLanguages() {
        let key = "Turn on the dedicated meeting workflow, shortcut, overlay, and meeting-specific model settings."

        XCTAssertEqual(AppLocalization.localizedString(key, localeIdentifier: "en"), key)

        let chinese = AppLocalization.localizedString(key, localeIdentifier: "zh-Hans")
        XCTAssertFalse(chinese.isEmpty)
        XCTAssertNotEqual(chinese, key)

        let japanese = AppLocalization.localizedString(key, localeIdentifier: "ja")
        XCTAssertFalse(japanese.isEmpty)
        XCTAssertNotEqual(japanese, key)
    }

    func testMeetingOnboardingLabelsAreLocalizedInSupportedLanguages() {
        let keys = [
            "Meeting Shortcut",
            "Meeting is optional during onboarding. You can enable it later from Feature > Transcription.",
            "Meeting permissions are only required after you turn this feature on."
        ]

        for key in keys {
            XCTAssertEqual(AppLocalization.localizedString(key, localeIdentifier: "en"), key)

            let chinese = AppLocalization.localizedString(key, localeIdentifier: "zh-Hans")
            XCTAssertFalse(chinese.isEmpty, "Missing zh-Hans localization for \(key)")
            XCTAssertNotEqual(chinese, key, "Expected zh-Hans translation for \(key)")

            let japanese = AppLocalization.localizedString(key, localeIdentifier: "ja")
            XCTAssertFalse(japanese.isEmpty, "Missing ja localization for \(key)")
            XCTAssertNotEqual(japanese, key, "Expected ja translation for \(key)")
        }
    }

    func testModelFilterLabelsAreLocalizedInSupportedLanguages() {
        let keys = ["Local", "Remote", "Installed", "Configured", "In Use"]

        for key in keys {
            XCTAssertEqual(AppLocalization.localizedString(key, localeIdentifier: "en"), key)

            let chinese = AppLocalization.localizedString(key, localeIdentifier: "zh-Hans")
            XCTAssertFalse(chinese.isEmpty, "Missing zh-Hans localization for \(key)")
            XCTAssertNotEqual(chinese, key, "Expected zh-Hans translation for \(key)")

            let japanese = AppLocalization.localizedString(key, localeIdentifier: "ja")
            XCTAssertFalse(japanese.isEmpty, "Missing ja localization for \(key)")
            XCTAssertNotEqual(japanese, key, "Expected ja translation for \(key)")
        }
    }
}

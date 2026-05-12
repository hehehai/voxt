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

    func testAppEnhancementLabelIsLocalizedInSupportedLanguages() {
        XCTAssertEqual(AppLocalization.localizedString("App Enhancement", localeIdentifier: "en"), "App Enhancement")

        let chinese = AppLocalization.localizedString("App Enhancement", localeIdentifier: "zh-Hans")
        XCTAssertFalse(chinese.isEmpty)
        XCTAssertNotEqual(chinese, "App Enhancement")

        let japanese = AppLocalization.localizedString("App Enhancement", localeIdentifier: "ja")
        XCTAssertFalse(japanese.isEmpty)
        XCTAssertNotEqual(japanese, "App Enhancement")
    }

    func testAppEnhancementDescriptionIsLocalizedInSupportedLanguages() {
        let key = "Use different enhancement prompts for different apps or browser pages."

        XCTAssertEqual(AppLocalization.localizedString(key, localeIdentifier: "en"), key)

        let chinese = AppLocalization.localizedString(key, localeIdentifier: "zh-Hans")
        XCTAssertFalse(chinese.isEmpty)
        XCTAssertNotEqual(chinese, key)

        let japanese = AppLocalization.localizedString(key, localeIdentifier: "ja")
        XCTAssertFalse(japanese.isEmpty)
        XCTAssertNotEqual(japanese, key)
    }

    func testFeatureLabelsAreLocalizedInSupportedLanguages() {
        let keys = [
            "Transcription",
            "Translation",
            "Rewrite"
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

    func testOpeningUpdateWindowLabelIsLocalizedInSupportedLanguages() {
        let key = "Opening update window…"

        XCTAssertEqual(AppLocalization.localizedString(key, localeIdentifier: "en"), key)
        XCTAssertEqual(AppLocalization.localizedString(key, localeIdentifier: "zh-Hans"), "正在打开更新窗口…")
        XCTAssertEqual(AppLocalization.localizedString(key, localeIdentifier: "ja"), "更新ウィンドウを開いています…")
    }

    func testManualCorrectionActionIsLocalizedInSupportedLanguages() {
        XCTAssertEqual(AppLocalization.localizedString("Correct", localeIdentifier: "en"), "Correct")
        XCTAssertEqual(AppLocalization.localizedString("Correct", localeIdentifier: "zh-Hans"), "纠错")
        XCTAssertEqual(AppLocalization.localizedString("Correct", localeIdentifier: "ja"), "修正")
    }
}

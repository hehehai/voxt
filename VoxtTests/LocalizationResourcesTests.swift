// LocalizationResourcesTests.swift
// Provides Localization Resources Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class LocalizationResourcesTests: XCTestCase {
    private var originalInterfaceLanguage: String?

    override func setUp() {
        super.setUp()
        originalInterfaceLanguage = UserDefaults.standard.string(forKey: AppPreferenceKey.interfaceLanguage)
    }

    override func tearDown() {
        if let originalInterfaceLanguage {
            UserDefaults.standard.set(originalInterfaceLanguage, forKey: AppPreferenceKey.interfaceLanguage)
        } else {
            UserDefaults.standard.removeObject(forKey: AppPreferenceKey.interfaceLanguage)
        }
        AppLocalization.refreshLanguageCache()
        super.tearDown()
    }

    func testFeatureMenuTitleIsLocalizedInSupportedLanguages() {
        XCTAssertEqual(AppLocalization.localizedString("Feature", localeIdentifier: "en"), "Feature")
        XCTAssertEqual(AppLocalization.localizedString("Feature", localeIdentifier: "zh-Hans"), "功能")
        XCTAssertEqual(AppLocalization.localizedString("Feature", localeIdentifier: "ja"), "機能")
    }

    func testCachedInterfaceLanguageRefreshesFromUserDefaults() {
        UserDefaults.standard.set(AppInterfaceLanguage.english.rawValue, forKey: AppPreferenceKey.interfaceLanguage)
        AppLocalization.refreshLanguageCache()
        XCTAssertEqual(AppLocalization.language, .english)
        XCTAssertEqual(AppLocalization.localizedString("Feature"), "Feature")

        UserDefaults.standard.set(AppInterfaceLanguage.chineseSimplified.rawValue, forKey: AppPreferenceKey.interfaceLanguage)
        AppLocalization.refreshLanguageCache()
        XCTAssertEqual(AppLocalization.language, .chineseSimplified)
        XCTAssertEqual(AppLocalization.localizedString("Feature"), "功能")
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

    func testBetaUpdatesLabelIsLocalizedInSupportedLanguages() {
        XCTAssertEqual(AppLocalization.localizedString("Beta Updates", localeIdentifier: "en"), "Beta Updates")
        XCTAssertEqual(AppLocalization.localizedString("Beta Updates", localeIdentifier: "zh-Hans"), "Beta 更新")
        XCTAssertEqual(AppLocalization.localizedString("Beta Updates", localeIdentifier: "ja"), "ベータ更新")
    }

    func testManualCorrectionActionIsLocalizedInSupportedLanguages() {
        XCTAssertEqual(AppLocalization.localizedString("Correct", localeIdentifier: "en"), "Correct")
        XCTAssertEqual(AppLocalization.localizedString("Correct", localeIdentifier: "zh-Hans"), "纠错")
        XCTAssertEqual(AppLocalization.localizedString("Correct", localeIdentifier: "ja"), "修正")
    }

    func testCodexConfigurationTextIsLocalizedInSupportedLanguages() {
        let keys = [
            "Codex Credentials",
            "Codex Credentials, Voxt uses local Codex OAuth credentials.",
            "For first-time setup, manually choose the auth.json configuration file once.",
            "Codex auth.json permission denied at %@. Click Choose and select auth.json to grant Voxt access.",
            "Codex auth.json has no ChatGPT OAuth tokens. Run `codex login` first."
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
}

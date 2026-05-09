import XCTest
@testable import Voxt

final class GeneralSettingsDataTests: XCTestCase {
    func testUserMainLanguageSummaryFallsBackWhenSelectionIsEmpty() {
        let summary = GeneralSettingsData.userMainLanguageSummary(
            selectedCodes: [],
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(summary, UserMainLanguageOption.fallbackOption().title(locale: Locale(identifier: "en")))
    }

    func testUserMainLanguageSummaryIncludesOverflowCount() {
        let summary = GeneralSettingsData.userMainLanguageSummary(
            selectedCodes: ["zh-hans", "en", "ja"],
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(summary, "Chinese (Simplified) + 2 more")
    }

    func testCustomPasteHotkeyFiltersSidedModifiersByEnabledModifiers() {
        let hotkey = GeneralSettingsData.customPasteHotkey(
            keyCode: 9,
            modifiersRawValue: Int(NSEvent.ModifierFlags.command.rawValue),
            sidedModifiersRawValue: Int(SidedModifierFlags.leftOption.rawValue | SidedModifierFlags.leftCommand.rawValue)
        )

        XCTAssertEqual(hotkey.modifiers, [.command])
        XCTAssertEqual(hotkey.sidedModifiers, [.leftCommand])
    }

    func testProxyTitlesAndOverlayClamping() {
        XCTAssertEqual(GeneralSettingsData.networkProxyModeTitle(.system), "Follow System")
        XCTAssertEqual(GeneralSettingsData.networkProxyModeTitle(.disabled), "Off")
        XCTAssertEqual(GeneralSettingsData.networkProxyModeTitle(.custom), "Custom")
        XCTAssertEqual(GeneralSettingsData.proxySchemeTitle(.http), "HTTP")
        XCTAssertEqual(GeneralSettingsData.proxySchemeTitle(.https), "HTTPS")
        XCTAssertEqual(GeneralSettingsData.proxySchemeTitle(.socks5), "SOCKS5")
        XCTAssertEqual(GeneralSettingsData.clampedOverlayOpacity(140), 100)
        XCTAssertEqual(GeneralSettingsData.clampedOverlayOpacity(-8), 0)
        XCTAssertEqual(GeneralSettingsData.clampedOverlayCornerRadius(55), 40)
        XCTAssertEqual(GeneralSettingsData.clampedOverlayScreenEdgeInset(-1), 0)
    }
}

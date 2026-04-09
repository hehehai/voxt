import XCTest
@testable import Voxt

final class AppUpdateManagerTests: XCTestCase {
    @MainActor
    func testLocalizedFeedURLStringUsesInterfaceLanguageQueryParameter() {
        let url = AppUpdateManager.localizedFeedURLString(
            baseURLString: "https://voxt.actnow.dev/updates/stable/appcast.xml",
            interfaceLanguage: .chineseSimplified
        )

        let components = URLComponents(string: url)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "lang" })?.value, "zh-Hans")
    }

    @MainActor
    func testLocalizedFeedURLStringPreservesExistingQueryItems() {
        let url = AppUpdateManager.localizedFeedURLString(
            baseURLString: "https://voxt.actnow.dev/updates/stable/appcast.xml?channel=stable",
            interfaceLanguage: .japanese
        )

        let components = URLComponents(string: url)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "channel" })?.value, "stable")
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "lang" })?.value, "ja")
    }
}

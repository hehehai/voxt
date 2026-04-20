import XCTest
@testable import Voxt

final class VoxtNetworkSessionTests: XCTestCase {
    func testClearProcessProxyEnvironmentOverridesRemovesStandardProxyVariables() {
        let keys = [
            "http_proxy",
            "https_proxy",
            "all_proxy",
            "no_proxy",
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "NO_PROXY"
        ]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, ProcessInfo.processInfo.environment[key])
        })

        setenv("http_proxy", "http://127.0.0.1:7897", 1)
        setenv("https_proxy", "http://127.0.0.1:7897", 1)
        setenv("all_proxy", "socks5://127.0.0.1:7897", 1)
        setenv("no_proxy", "localhost,127.0.0.1", 1)

        VoxtNetworkSession.clearProcessProxyEnvironmentOverridesIfNeeded()

        XCTAssertNil(ProcessInfo.processInfo.environment["http_proxy"])
        XCTAssertNil(ProcessInfo.processInfo.environment["https_proxy"])
        XCTAssertNil(ProcessInfo.processInfo.environment["all_proxy"])
        XCTAssertNil(ProcessInfo.processInfo.environment["no_proxy"])

        for (key, value) in originalValues {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
}

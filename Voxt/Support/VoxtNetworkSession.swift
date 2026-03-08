import Foundation
import CFNetwork

enum VoxtNetworkSession {
    // Force direct outbound network requests and bypass system HTTP/HTTPS/SOCKS proxies.
    static let direct: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false
        ]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static let system: URLSession = {
        URLSession(configuration: .default)
    }()

    static var isUsingSystemProxy: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.useSystemProxy)
    }

    static var active: URLSession {
        isUsingSystemProxy ? system : direct
    }
}

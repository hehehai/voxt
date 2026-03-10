import Foundation
import CFNetwork

enum VoxtNetworkSession {
    enum ProxyMode: String, CaseIterable, Identifiable {
        case system
        case disabled
        case custom

        var id: String { rawValue }
    }

    enum ProxyScheme: String, CaseIterable, Identifiable {
        case http
        case https
        case socks5

        var id: String { rawValue }
    }

    struct ProxySettings {
        let mode: ProxyMode
        let scheme: ProxyScheme
        let host: String
        let port: Int?
        let username: String
        let password: String

        var hasValidCustomEndpoint: Bool {
            !host.isEmpty && port != nil
        }

        var hasCredentials: Bool {
            !username.isEmpty && !password.isEmpty
        }
    }

    private final class ProxyAuthenticationDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
        private let settings: ProxySettings

        init(settings: ProxySettings) {
            self.settings = settings
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            handle(challenge: challenge, completionHandler: completionHandler)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            handle(challenge: challenge, completionHandler: completionHandler)
        }

        private func handle(
            challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard settings.hasCredentials, isProxyAuthenticationChallenge(challenge.protectionSpace) else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            let credential = URLCredential(
                user: settings.username,
                password: settings.password,
                persistence: .forSession
            )
            completionHandler(.useCredential, credential)
        }

        private func isProxyAuthenticationChallenge(_ protectionSpace: URLProtectionSpace) -> Bool {
            protectionSpace.proxyType != nil
        }
    }

    // Force direct outbound network requests and bypass system HTTP/HTTPS/SOCKS proxies.
    static let direct: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
            kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false,
            kCFNetworkProxiesHTTPProxy as String: "",
            kCFNetworkProxiesHTTPPort as String: 0,
            kCFNetworkProxiesHTTPSProxy as String: "",
            kCFNetworkProxiesHTTPSPort as String: 0,
            kCFNetworkProxiesSOCKSProxy as String: "",
            kCFNetworkProxiesSOCKSPort as String: 0,
            kCFNetworkProxiesProxyAutoConfigURLString as String: "",
            kCFNetworkProxiesExceptionsList as String: [],
            kCFNetworkProxiesExcludeSimpleHostnames as String: false
        ]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static let system: URLSession = {
        URLSession(configuration: .default)
    }()

    static var currentProxySettings: ProxySettings {
        let defaults = UserDefaults.standard
        let mode = ProxyMode(rawValue: defaults.string(forKey: AppPreferenceKey.networkProxyMode) ?? "") ?? .system
        let scheme = ProxyScheme(rawValue: defaults.string(forKey: AppPreferenceKey.customProxyScheme) ?? "") ?? .http
        let host = (defaults.string(forKey: AppPreferenceKey.customProxyHost) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = (defaults.string(forKey: AppPreferenceKey.customProxyPort) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let username = defaults.string(forKey: AppPreferenceKey.customProxyUsername) ?? ""
        let password = defaults.string(forKey: AppPreferenceKey.customProxyPassword) ?? ""

        return ProxySettings(
            mode: mode,
            scheme: scheme,
            host: host,
            port: Int(portText),
            username: username,
            password: password
        )
    }

    static var isUsingSystemProxy: Bool {
        currentProxySettings.mode == .system
    }

    static var modeDescription: String {
        let settings = currentProxySettings
        switch settings.mode {
        case .system:
            return "system"
        case .disabled:
            return "direct"
        case .custom:
            guard settings.hasValidCustomEndpoint, let port = settings.port else {
                return "custom(incomplete)"
            }
            return "custom(\(settings.scheme.rawValue)://\(settings.host):\(port))"
        }
    }

    static var active: URLSession {
        let settings = currentProxySettings
        switch settings.mode {
        case .system:
            return system
        case .disabled:
            return direct
        case .custom:
            guard settings.hasValidCustomEndpoint else {
                return direct
            }
            return customSession(settings: settings)
        }
    }

    private static func customSession(settings: ProxySettings) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = customProxyDictionary(settings: settings)
        let delegate = settings.hasCredentials ? ProxyAuthenticationDelegate(settings: settings) : nil
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    private static func customProxyDictionary(settings: ProxySettings) -> [AnyHashable: Any] {
        guard let port = settings.port else {
            return [:]
        }

        var dictionary: [AnyHashable: Any] = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
            kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false
        ]

        switch settings.scheme {
        case .http, .https:
            dictionary[kCFNetworkProxiesHTTPEnable as String] = true
            dictionary[kCFNetworkProxiesHTTPProxy as String] = settings.host
            dictionary[kCFNetworkProxiesHTTPPort as String] = port
            dictionary[kCFNetworkProxiesHTTPSEnable as String] = true
            dictionary[kCFNetworkProxiesHTTPSProxy as String] = settings.host
            dictionary[kCFNetworkProxiesHTTPSPort as String] = port
        case .socks5:
            dictionary[kCFNetworkProxiesSOCKSEnable as String] = true
            dictionary[kCFNetworkProxiesSOCKSProxy as String] = settings.host
            dictionary[kCFNetworkProxiesSOCKSPort as String] = port
        }

        return dictionary
    }
}

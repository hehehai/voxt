import Foundation
import CFNetwork
import Network

enum VoxtNetworkSession {
    private enum SecureField: String {
        case customProxyUsername
        case customProxyPassword
    }

    final class ManagedWebSocketTask {
        let session: URLSession
        let task: URLSessionWebSocketTask

        init(session: URLSession, task: URLSessionWebSocketTask) {
            self.session = session
            self.task = task
        }
    }

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
        applyDirectProxyBypass(to: configuration)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static let system: URLSession = {
        URLSession(configuration: .default)
    }()

    static var currentProxySettings: ProxySettings {
        let credentials = currentProxyCredentials()
        let defaults = UserDefaults.standard
        let mode = ProxyMode(rawValue: defaults.string(forKey: AppPreferenceKey.networkProxyMode) ?? "") ?? .system
        let scheme = ProxyScheme(rawValue: defaults.string(forKey: AppPreferenceKey.customProxyScheme) ?? "") ?? .http
        let host = (defaults.string(forKey: AppPreferenceKey.customProxyHost) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = (defaults.string(forKey: AppPreferenceKey.customProxyPort) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ProxySettings(
            mode: mode,
            scheme: scheme,
            host: host,
            port: Int(portText),
            username: credentials.username,
            password: credentials.password
        )
    }

    static func currentProxyCredentials() -> (username: String, password: String) {
        proxyCredentials(defaults: .standard)
    }

    static func proxyCredentials(defaults: UserDefaults) -> (username: String, password: String) {
        (
            secureValue(
                for: .customProxyUsername,
                fallbackDefaultsKey: AppPreferenceKey.customProxyUsername,
                defaults: defaults
            ),
            secureValue(
                for: .customProxyPassword,
                fallbackDefaultsKey: AppPreferenceKey.customProxyPassword,
                defaults: defaults
            )
        )
    }

    static func setCustomProxyCredentials(
        username: String,
        password: String,
        defaults: UserDefaults = .standard
    ) {
        VoxtSecureStorage.set(username, for: secureAccount(for: .customProxyUsername))
        VoxtSecureStorage.set(password, for: secureAccount(for: .customProxyPassword))
        defaults.removeObject(forKey: AppPreferenceKey.customProxyUsername)
        defaults.removeObject(forKey: AppPreferenceKey.customProxyPassword)
    }

    static func migrateLegacyProxyCredentials(defaults: UserDefaults = .standard) {
        migrateLegacyValue(for: .customProxyUsername, defaultsKey: AppPreferenceKey.customProxyUsername, defaults: defaults)
        migrateLegacyValue(for: .customProxyPassword, defaultsKey: AppPreferenceKey.customProxyPassword, defaults: defaults)
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

    static func makeWebSocketTask(with request: URLRequest) -> ManagedWebSocketTask {
        let settings = currentProxySettings
        let session = makeSession(for: settings)
        let task = session.webSocketTask(with: request)
        return ManagedWebSocketTask(session: session, task: task)
    }

    private static func customSession(settings: ProxySettings) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = customProxyDictionary(settings: settings)
        configuration.proxyConfigurations = customProxyConfigurations(settings: settings)
        let delegate = settings.hasCredentials ? ProxyAuthenticationDelegate(settings: settings) : nil
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    private static func makeSession(for settings: ProxySettings) -> URLSession {
        switch settings.mode {
        case .system:
            return URLSession(configuration: .default)
        case .disabled:
            let configuration = URLSessionConfiguration.ephemeral
            applyDirectProxyBypass(to: configuration)
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: configuration)
        case .custom:
            guard settings.hasValidCustomEndpoint else {
                let configuration = URLSessionConfiguration.ephemeral
                applyDirectProxyBypass(to: configuration)
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                return URLSession(configuration: configuration)
            }
            return customSession(settings: settings)
        }
    }

    private static func applyDirectProxyBypass(to configuration: URLSessionConfiguration) {
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
        configuration.proxyConfigurations = []
    }

    private static func secureValue(
        for field: SecureField,
        fallbackDefaultsKey: String,
        defaults: UserDefaults
    ) -> String {
        if let stored = VoxtSecureStorage.string(for: secureAccount(for: field)) {
            return stored
        }

        let legacyValue = defaults.string(forKey: fallbackDefaultsKey) ?? ""
        if !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VoxtSecureStorage.set(legacyValue, for: secureAccount(for: field))
            defaults.removeObject(forKey: fallbackDefaultsKey)
        }
        return legacyValue
    }

    private static func migrateLegacyValue(for field: SecureField, defaultsKey: String, defaults: UserDefaults) {
        let legacyValue = defaults.string(forKey: defaultsKey) ?? ""
        if !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VoxtSecureStorage.set(legacyValue, for: secureAccount(for: field))
        }
        defaults.removeObject(forKey: defaultsKey)
    }

    private static func secureAccount(for field: SecureField) -> String {
        "network-proxy.\(field.rawValue)"
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

    private static func customProxyConfigurations(settings: ProxySettings) -> [ProxyConfiguration] {
        guard
            let portValue = settings.port,
            let port = NWEndpoint.Port(rawValue: UInt16(portValue))
        else {
            return []
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(settings.host), port: port)
        var configuration: ProxyConfiguration
        switch settings.scheme {
        case .http, .https:
            configuration = ProxyConfiguration(httpCONNECTProxy: endpoint)
        case .socks5:
            configuration = ProxyConfiguration(socksv5Proxy: endpoint)
        }
        configuration.allowFailover = false
        if settings.hasCredentials {
            configuration.applyCredential(username: settings.username, password: settings.password)
        }
        return [configuration]
    }
}

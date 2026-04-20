import Foundation
import CFNetwork

extension RemoteLLMRuntimeClient {
    nonisolated func providerDefaultEndpoint(_ provider: RemoteLLMProvider) -> String {
        switch provider {
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .google:
            return "https://generativelanguage.googleapis.com/v1beta/models"
        case .openAI:
            return "https://api.openai.com/v1/models"
        case .ollama:
            return "http://127.0.0.1:11434/api/chat"
        case .deepseek:
            return "https://api.deepseek.com/v1/models"
        case .openrouter:
            return "https://openrouter.ai/api/v1/models"
        case .grok:
            return "https://api.x.ai/v1/models"
        case .zai:
            return "https://open.bigmodel.cn/api/paas/v4/models"
        case .volcengine:
            return "https://ark.cn-beijing.volces.com/api/v3/responses"
        case .kimi:
            return "https://api.moonshot.cn/v1/models"
        case .lmStudio:
            return "http://127.0.0.1:1234/v1/models"
        case .minimax:
            return "https://api.minimax.chat/v1/text/chatcompletion_v2"
        case .aliyunBailian:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"
        }
    }

    nonisolated func usesNativeOllamaChatEndpoint(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix("/api/chat")
    }

    nonisolated func resolvedLLMEndpoint(provider: RemoteLLMProvider, endpoint: String, model: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? providerDefaultEndpoint(provider) : trimmed
        guard let url = URL(string: base) else { return base }
        let path = url.path.lowercased()

        switch provider {
        case .volcengine:
            return normalizedResponsesEndpoint(
                base,
                defaultPath: "/api/v3/responses"
            )
        case .aliyunBailian:
            return normalizedResponsesEndpoint(
                base,
                defaultPath: "/compatible-mode/v1/responses"
            )
        case .anthropic:
            if path.hasSuffix("/v1/messages") { return base }
            if path.hasSuffix("/v1/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/v1/models", newSuffix: "/v1/messages")
            }
            if path.hasSuffix("/v1") { return appendingPath(base, suffix: "/messages") }
            if path.isEmpty || path == "/" { return appendingPath(base, suffix: "/v1/messages") }
            return base
        case .google:
            if path.contains(":generatecontent") { return base }
            if path.hasSuffix("/v1beta/models") || path.hasSuffix("/v1/models") || path.hasSuffix("/models") {
                return appendingPath(base, suffix: "/\(model):generateContent")
            }
            if path.hasSuffix("/v1beta") || path.hasSuffix("/v1") {
                return appendingPath(base, suffix: "/models/\(model):generateContent")
            }
            if path.isEmpty || path == "/" {
                return appendingPath(base, suffix: "/v1beta/models/\(model):generateContent")
            }
            return base
        case .minimax:
            if path.hasSuffix("/v1/text/chatcompletion_v2") || path.hasSuffix("/text/chatcompletion_v2") {
                return base
            }
            if path.hasSuffix("/v1/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/v1/models", newSuffix: "/v1/text/chatcompletion_v2")
            }
            if path.hasSuffix("/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/models", newSuffix: "/text/chatcompletion_v2")
            }
            if path.hasSuffix("/v1") { return appendingPath(base, suffix: "/text/chatcompletion_v2") }
            if path.isEmpty || path == "/" { return appendingPath(base, suffix: "/v1/text/chatcompletion_v2") }
            return base
        case .ollama:
            if path.hasSuffix("/api/chat") || path.hasSuffix("/v1/chat/completions") || path.hasSuffix("/chat/completions") {
                return base
            }
            if path.hasSuffix("/api/tags") {
                return replacingPathSuffix(in: base, oldSuffix: "/api/tags", newSuffix: "/api/chat")
            }
            if path.hasSuffix("/v1/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/v1/models", newSuffix: "/v1/chat/completions")
            }
            if path.hasSuffix("/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/models", newSuffix: "/chat/completions")
            }
            if path.hasSuffix("/v1") { return appendingPath(base, suffix: "/chat/completions") }
            if path.isEmpty || path == "/" { return appendingPath(base, suffix: "/api/chat") }
            return base
        case .openAI, .deepseek, .openrouter, .grok, .zai, .kimi, .lmStudio:
            if path.hasSuffix("/v1/chat/completions") || path.hasSuffix("/chat/completions") {
                return base
            }
            if path.hasSuffix("/v1/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/v1/models", newSuffix: "/v1/chat/completions")
            }
            if path.hasSuffix("/models") {
                return replacingPathSuffix(in: base, oldSuffix: "/models", newSuffix: "/chat/completions")
            }
            if path.hasSuffix("/v1") { return appendingPath(base, suffix: "/chat/completions") }
            if path.isEmpty || path == "/" { return appendingPath(base, suffix: "/v1/chat/completions") }
            return base
        }
    }

    nonisolated func streamingEndpointValue(
        provider: RemoteLLMProvider,
        endpoint: String,
        model: String,
        streamingEnabled: Bool
    ) -> String {
        let resolved = resolvedLLMEndpoint(provider: provider, endpoint: endpoint, model: model)
        guard streamingEnabled else { return resolved }

        switch provider {
        case .google:
            if let range = resolved.range(of: ":generateContent", options: [.caseInsensitive]) {
                return resolved.replacingCharacters(in: range, with: ":streamGenerateContent")
            }
            return resolved
        default:
            return resolved
        }
    }

    nonisolated func responsesEndpointValue(
        provider: RemoteLLMProvider,
        endpoint: String,
        model: String
    ) -> String {
        if provider.usesResponsesAPI {
            return resolvedLLMEndpoint(provider: provider, endpoint: endpoint, model: model)
        }

        let resolved = resolvedLLMEndpoint(provider: provider, endpoint: endpoint, model: model)
        if resolved.hasSuffix("/v1/chat/completions") {
            return replacingPathSuffix(in: resolved, oldSuffix: "/v1/chat/completions", newSuffix: "/v1/responses")
        }
        if resolved.hasSuffix("/chat/completions") {
            return replacingPathSuffix(in: resolved, oldSuffix: "/chat/completions", newSuffix: "/responses")
        }
        if resolved.hasSuffix("/v1/models") {
            return replacingPathSuffix(in: resolved, oldSuffix: "/v1/models", newSuffix: "/v1/responses")
        }
        if resolved.hasSuffix("/models") {
            return replacingPathSuffix(in: resolved, oldSuffix: "/models", newSuffix: "/responses")
        }
        if resolved.hasSuffix("/v1") {
            return appendingPath(resolved, suffix: "/responses")
        }
        if resolved.hasSuffix("/compatible-mode") {
            return appendingPath(resolved, suffix: "/v1/responses")
        }
        return appendingPath(resolved, suffix: "/responses")
    }

    nonisolated private func normalizedResponsesEndpoint(_ value: String, defaultPath: String) -> String {
        guard let url = URL(string: value) else { return value }
        let normalizedPath = url.path.lowercased()

        if normalizedPath.hasSuffix("/responses") {
            return value
        }
        if normalizedPath.hasSuffix("/v1/chat/completions") {
            return replacingPathSuffix(in: value, oldSuffix: "/v1/chat/completions", newSuffix: "/v1/responses")
        }
        if normalizedPath.hasSuffix("/chat/completions") {
            return replacingPathSuffix(in: value, oldSuffix: "/chat/completions", newSuffix: "/responses")
        }
        if normalizedPath.hasSuffix("/v1/models") {
            return replacingPathSuffix(in: value, oldSuffix: "/v1/models", newSuffix: "/v1/responses")
        }
        if normalizedPath.hasSuffix("/models") {
            return replacingPathSuffix(in: value, oldSuffix: "/models", newSuffix: "/responses")
        }
        if normalizedPath.isEmpty || normalizedPath == "/" {
            return appendingPath(value, suffix: defaultPath)
        }
        if normalizedPath.hasSuffix("/v1") || normalizedPath.hasSuffix("/v3") {
            return appendingPath(value, suffix: "/responses")
        }
        return value
    }

    nonisolated func resolvedProxyRoute(for url: URL, settings: VoxtNetworkSession.ProxySettings) -> String {
        let detected = resolvedSystemProxyRoute(for: url)
        switch settings.mode {
        case .system:
            return "enabled(system),resolved=\(detected)"
        case .disabled:
            return "disabled(direct),systemDetected=\(detected)"
        case .custom:
            guard let port = settings.port, settings.hasValidCustomEndpoint else {
                return "custom(incomplete),systemDetected=\(detected)"
            }
            return "custom(\(settings.scheme.rawValue)://\(settings.host):\(port)),systemDetected=\(detected)"
        }
    }

    nonisolated func resolvedSystemProxyRoute(for url: URL) -> String {
        guard
            let settingsRef = CFNetworkCopySystemProxySettings(),
            let settings = settingsRef.takeRetainedValue() as? [String: Any]
        else {
            return "unavailable"
        }

        let proxiesCF = CFNetworkCopyProxiesForURL(url as CFURL, settings as CFDictionary).takeRetainedValue()
        guard
            let proxies = proxiesCF as? [[String: Any]],
            let selected = proxies.first
        else {
            return "unavailable"
        }

        let type = (selected[kCFProxyTypeKey as String] as? String) ?? "unknown"
        if type == (kCFProxyTypeNone as String) {
            return "none"
        }

        let host = (selected[kCFProxyHostNameKey as String] as? String) ?? ""
        let portValue = selected[kCFProxyPortNumberKey as String]
        let port: String
        if let number = portValue as? NSNumber {
            port = number.stringValue
        } else if let value = portValue as? String {
            port = value
        } else {
            port = ""
        }

        let auth = ((selected[kCFProxyUsernameKey as String] as? String)?.isEmpty == false) ? "auth" : "noauth"
        let address = host.isEmpty ? "unknown" : (port.isEmpty ? host : "\(host):\(port)")
        return "\(type)@\(address),\(auth)"
    }

    nonisolated func networkErrorDetail(error: NSError) -> String {
        let streamDomain = error.userInfo["_kCFStreamErrorDomainKey"] ?? "nil"
        let streamCode = error.userInfo["_kCFStreamErrorCodeKey"] ?? "nil"
        return "domain=\(error.domain), code=\(error.code), streamDomain=\(streamDomain), streamCode=\(streamCode), desc=\(error.localizedDescription)"
    }

    nonisolated func replacingPathSuffix(in value: String, oldSuffix: String, newSuffix: String) -> String {
        guard value.lowercased().hasSuffix(oldSuffix) else { return value }
        return String(value.dropLast(oldSuffix.count)) + newSuffix
    }

    nonisolated func appendingPath(_ value: String, suffix: String) -> String {
        if value.hasSuffix("/") {
            return value + suffix.dropFirst()
        }
        return value + suffix
    }
}

import Foundation
import CFNetwork

struct RemoteLLMRuntimeClient {
    private enum CompletionIntent {
        case enhancement
        case translation
    }

    private struct GenerationTuning {
        let maxTokens: Int
        let temperature: Double
        let topP: Double
    }

    func enhance(
        text: String,
        systemPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        let prompt = """
        Clean up this transcription while preserving meaning and style.
        Input:
        \(text)
        """
        let output = try await complete(
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            inputTextLength: text.count,
            intent: .enhancement,
            provider: provider,
            configuration: configuration
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    func translate(
        text: String,
        systemPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        let prompt = """
        Translate the following text according to the instructions.
        Input:
        \(text)
        """
        let output = try await complete(
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            inputTextLength: text.count,
            intent: .translation,
            provider: provider,
            configuration: configuration
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    private func complete(
        systemPrompt: String,
        userPrompt: String,
        inputTextLength: Int,
        intent: CompletionIntent,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.suggestedModel
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = resolvedLLMEndpoint(provider: provider, endpoint: configuration.endpoint, model: model)
        let endpoints = resolvedEndpointCandidates(provider: provider, primaryEndpoint: endpoint)
        var lastError: Error?

        for (index, endpointValue) in endpoints.enumerated() {
            guard let url = URL(string: endpointValue) else {
                lastError = NSError(
                    domain: "Voxt.RemoteLLM",
                    code: -300,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM endpoint URL: \(endpointValue)"]
                )
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = requestTimeoutInterval(for: provider)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let tuning = generationTuning(
                for: provider,
                inputTextLength: inputTextLength,
                systemPromptLength: systemPrompt.count,
                userPromptLength: userPrompt.count,
                intent: intent
            )

            switch provider {
            case .anthropic:
                guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NSError(domain: "Voxt.RemoteLLM", code: -301, userInfo: [NSLocalizedDescriptionKey: "Anthropic API key is empty."])
                }
                request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": model,
                    "max_tokens": 2048,
                    "system": systemPrompt,
                    "messages": [
                        ["role": "user", "content": userPrompt]
                    ]
                ])
            case .google:
                let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !apiKey.isEmpty else {
                    throw NSError(domain: "Voxt.RemoteLLM", code: -302, userInfo: [NSLocalizedDescriptionKey: "Google API key is empty."])
                }
                guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    throw NSError(domain: "Voxt.RemoteLLM", code: -303, userInfo: [NSLocalizedDescriptionKey: "Invalid Google endpoint URL."])
                }
                if !(components.queryItems?.contains(where: { $0.name == "key" }) ?? false) {
                    var items = components.queryItems ?? []
                    items.append(URLQueryItem(name: "key", value: apiKey))
                    components.queryItems = items
                }
                request.url = components.url
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "system_instruction": ["parts": [["text": systemPrompt]]],
                    "contents": [
                        ["parts": [["text": userPrompt]]]
                    ]
                ])
            case .minimax:
                let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !apiKey.isEmpty else {
                    throw NSError(domain: "Voxt.RemoteLLM", code: -304, userInfo: [NSLocalizedDescriptionKey: "MiniMax API key is empty."])
                }
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": model,
                    "messages": [
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": userPrompt]
                    ]
                ])
            default:
                let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !apiKey.isEmpty {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": model,
                    "messages": [
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": userPrompt]
                    ],
                    "stream": false,
                    "max_tokens": tuning.maxTokens,
                    "temperature": tuning.temperature,
                    "top_p": tuning.topP
                ])
            }

            let requestStartedAt = Date()
            let useSystemProxy = VoxtNetworkSession.isUsingSystemProxy
            let proxyRoute = resolvedProxyRoute(for: url, useSystemProxy: useSystemProxy)
            let networkMode = useSystemProxy ? "system" : "direct"
            VoxtLog.info(
                "Remote LLM request started. provider=\(provider.rawValue), endpoint=\(endpointValue), model=\(model), timeoutSec=\(Int(request.timeoutInterval)), inputChars=\(inputTextLength), systemChars=\(systemPrompt.count), userChars=\(userPrompt.count), maxTokens=\(tuning.maxTokens), temp=\(tuning.temperature), topP=\(tuning.topP), networkMode=\(networkMode), proxy=\(proxyRoute)"
            )
            do {
                let (data, response) = try await VoxtNetworkSession.active.data(for: request)
                let responseElapsedMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
                guard let http = response as? HTTPURLResponse else {
                    throw NSError(domain: "Voxt.RemoteLLM", code: -305, userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM response."])
                }
                guard (200...299).contains(http.statusCode) else {
                    let payload = String(data: data.prefix(260), encoding: .utf8) ?? ""
                    throw NSError(
                        domain: "Voxt.RemoteLLM",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Remote LLM request failed (HTTP \(http.statusCode)): \(payload)"]
                    )
                }

                let decodeStartedAt = Date()
                let object = try JSONSerialization.jsonObject(with: data)
                let decodeElapsedMs = Int(Date().timeIntervalSince(decodeStartedAt) * 1000)
                let totalElapsedMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
                let attempt = index + 1
                if let content = extractPrimaryText(from: object), !content.isEmpty {
                    VoxtLog.info(
                        "Remote LLM response received. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), attempt=\(attempt)/\(endpoints.count), bytes=\(data.count), networkMs=\(responseElapsedMs), decodeMs=\(decodeElapsedMs), totalMs=\(totalElapsedMs)"
                    )
                    return content
                }

                VoxtLog.warning(
                    "Remote LLM response has no usable text. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), attempt=\(attempt)/\(endpoints.count), bytes=\(data.count), networkMs=\(responseElapsedMs), decodeMs=\(decodeElapsedMs), totalMs=\(totalElapsedMs)"
                )
                throw NSError(domain: "Voxt.RemoteLLM", code: -306, userInfo: [NSLocalizedDescriptionKey: "Remote LLM returned no text content."])
            } catch {
                lastError = error
                let elapsedMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
                let detail = networkErrorDetail(error: nsError)
                let attempt = index + 1
                if isTimeout {
                    VoxtLog.warning("Remote LLM request timeout. provider=\(provider.rawValue), endpoint=\(endpointValue), attempt=\(attempt)/\(endpoints.count), elapsedMs=\(elapsedMs), timeoutSec=\(Int(request.timeoutInterval)), proxy=\(proxyRoute), detail=\(detail)")
                } else {
                    VoxtLog.warning("Remote LLM request failed. provider=\(provider.rawValue), endpoint=\(endpointValue), attempt=\(attempt)/\(endpoints.count), elapsedMs=\(elapsedMs), proxy=\(proxyRoute), detail=\(detail)")
                }

                let hasNext = index < endpoints.count - 1
                if hasNext && shouldRetry(error: error, provider: provider) {
                    VoxtLog.warning("Remote LLM request failed on endpoint \(endpointValue); retrying next endpoint. attempt=\(attempt)/\(endpoints.count), reason=\(error.localizedDescription)")
                    continue
                }
                throw error
            }
        }

        throw lastError ?? NSError(domain: "Voxt.RemoteLLM", code: -306, userInfo: [NSLocalizedDescriptionKey: "Remote LLM returned no text content."])
    }

    private func requestTimeoutInterval(for provider: RemoteLLMProvider) -> TimeInterval {
        switch provider {
        case .zai, .volcengine:
            return 30
        default:
            return 40
        }
    }

    private func generationTuning(
        for provider: RemoteLLMProvider,
        inputTextLength: Int,
        systemPromptLength: Int,
        userPromptLength: Int,
        intent: CompletionIntent
    ) -> GenerationTuning {
        let outputBudget = estimatedOutputTokenBudget(
            inputTextLength: inputTextLength,
            systemPromptLength: systemPromptLength,
            userPromptLength: userPromptLength,
            intent: intent
        )
        switch provider {
        case .volcengine:
            // Favor low latency and deterministic rewrite/translation behavior.
            return GenerationTuning(maxTokens: outputBudget, temperature: 0.1, topP: 0.3)
        case .zai:
            return GenerationTuning(maxTokens: outputBudget, temperature: 0.2, topP: 0.7)
        default:
            return GenerationTuning(maxTokens: outputBudget, temperature: 0.2, topP: 0.9)
        }
    }

    private func estimatedOutputTokenBudget(
        inputTextLength: Int,
        systemPromptLength: Int,
        userPromptLength: Int,
        intent: CompletionIntent
    ) -> Int {
        let safeInput = max(1, inputTextLength)
        // Keep output budget mainly tied to ASR text length, and reserve a small
        // extra window for instruction overhead (system/user prompt framing).
        let instructionChars = max(0, systemPromptLength + userPromptLength - safeInput)
        let baseMultiplier: Double = (intent == .translation) ? 1.35 : 1.15
        let contentEstimate = Int(Double(safeInput) * baseMultiplier)
        let instructionReserve = min(192, max(32, instructionChars / 12))
        let estimate = contentEstimate + instructionReserve
        return max(128, min(estimate, 1024))
    }

    private func shouldRetry(error: Error, provider: RemoteLLMProvider) -> Bool {
        guard provider == .zai else { return false }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet
            ].contains(nsError.code)
        }
        if nsError.domain == "Voxt.RemoteLLM" {
            return (500...599).contains(nsError.code)
        }
        return false
    }

    private func resolvedEndpointCandidates(provider: RemoteLLMProvider, primaryEndpoint: String) -> [String] {
        guard provider == .zai else { return [primaryEndpoint] }

        var values: [String] = [primaryEndpoint]
        if let alternate = alternateZAIEndpoint(from: primaryEndpoint),
           alternate.caseInsensitiveCompare(primaryEndpoint) != .orderedSame {
            values.append(alternate)
        }
        return values
    }

    private func alternateZAIEndpoint(from endpoint: String) -> String? {
        guard var components = URLComponents(string: endpoint) else {
            return "https://api.z.ai/api/paas/v4/chat/completions"
        }
        let host = (components.host ?? "").lowercased()
        if host == "open.bigmodel.cn" {
            components.host = "api.z.ai"
            return components.string
        }
        if host == "api.z.ai" {
            components.host = "open.bigmodel.cn"
            return components.string
        }
        if host.hasSuffix("bigmodel.cn") {
            components.host = "api.z.ai"
            return components.string
        }
        return "https://api.z.ai/api/paas/v4/chat/completions"
    }

    private func extractPrimaryText(from object: Any) -> String? {
        if let dict = object as? [String: Any] {
            if let choices = dict["choices"] as? [[String: Any]],
               let first = choices.first {
                if let message = first["message"] as? [String: Any] {
                    if let value = extractMessageContent(from: message["content"]) {
                        return value
                    }
                }
                if let text = first["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
            if let contentArray = dict["content"] as? [[String: Any]] {
                for item in contentArray {
                    if let text = item["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                }
            }
            if let candidates = dict["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                for part in parts {
                    if let text = part["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                }
            }
            if let reply = dict["reply"] as? String, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return reply
            }
        }
        return nil
    }

    private func extractMessageContent(from value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let blocks = value as? [[String: Any]] {
            let texts = blocks.compactMap { block -> String? in
                if let text = block["text"] as? String { return text }
                return nil
            }
            let merged = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return merged.isEmpty ? nil : merged
        }
        return nil
    }

    private func providerDefaultEndpoint(_ provider: RemoteLLMProvider) -> String {
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
            return "https://ark.cn-beijing.volces.com/api/v3/models"
        case .kimi:
            return "https://api.moonshot.cn/v1/models"
        case .lmStudio:
            return "http://127.0.0.1:1234/v1/models"
        case .minimax:
            return "https://api.minimax.chat/v1/text/chatcompletion_v2"
        }
    }

    private func resolvedLLMEndpoint(provider: RemoteLLMProvider, endpoint: String, model: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? providerDefaultEndpoint(provider) : trimmed
        guard let url = URL(string: base) else { return base }
        let path = url.path.lowercased()

        switch provider {
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
        case .openAI, .deepseek, .openrouter, .grok, .zai, .volcengine, .kimi, .lmStudio:
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

    private func resolvedProxyRoute(for url: URL, useSystemProxy: Bool) -> String {
        let detected = resolvedSystemProxyRoute(for: url)
        guard useSystemProxy else {
            return "disabled(direct),systemDetected=\(detected)"
        }
        return "enabled(system),resolved=\(detected)"
    }

    private func resolvedSystemProxyRoute(for url: URL) -> String {
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

    private func networkErrorDetail(error: NSError) -> String {
        let streamDomain = error.userInfo["_kCFStreamErrorDomainKey"] ?? "nil"
        let streamCode = error.userInfo["_kCFStreamErrorCodeKey"] ?? "nil"
        return "domain=\(error.domain), code=\(error.code), streamDomain=\(streamDomain), streamCode=\(streamCode), desc=\(error.localizedDescription)"
    }

    private func replacingPathSuffix(in value: String, oldSuffix: String, newSuffix: String) -> String {
        guard value.lowercased().hasSuffix(oldSuffix) else { return value }
        return String(value.dropLast(oldSuffix.count)) + newSuffix
    }

    private func appendingPath(_ value: String, suffix: String) -> String {
        if value.hasSuffix("/") {
            return value + suffix.dropFirst()
        }
        return value + suffix
    }
}

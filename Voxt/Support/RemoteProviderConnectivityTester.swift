import Foundation

enum RemoteProviderTestTarget {
    case asr(RemoteASRProvider)
    case llm(RemoteLLMProvider)
}

struct RemoteProviderConnectivityTester {
    let testTarget: RemoteProviderTestTarget

    func run(configuration: RemoteProviderConfiguration) async throws -> String {
        try await performConnectivityTest(configuration: configuration)
    }

    private func performConnectivityTest(configuration: RemoteProviderConfiguration) async throws -> String {
        switch testTarget {
        case .asr(let provider):
            return try await testASRProvider(provider, configuration: configuration)
        case .llm(let provider):
            return try await testLLMProvider(provider, configuration: configuration)
        }
    }
    private func testASRProvider(_ provider: RemoteASRProvider, configuration: RemoteProviderConfiguration) async throws -> String {
        switch provider {
        case .doubaoASR:
            let token = configuration.accessToken
            guard !token.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -1, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Doubao Access Token is required for testing.")])
            }
            guard !configuration.appID.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -2, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Doubao App ID is required for testing.")])
            }
            let endpoint = RemoteProviderConnectivityTestEndpoints.resolvedDoubaoASREndpoint(configuration.endpoint, model: configuration.model)
            return try await testDoubaoStreamingReachability(
                endpoint: endpoint,
                appID: configuration.appID,
                accessToken: token,
                model: configuration.model
            )
        case .openAIWhisper:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -3, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("OpenAI API Key is required for testing.")])
            }
            let endpoint = RemoteProviderConnectivityTestEndpoints.resolvedASRTranscriptionEndpoint(
                endpoint: configuration.endpoint,
                defaultValue: "https://api.openai.com/v1/audio/transcriptions"
            )
            return try await testASRMultipartReachability(
                endpoint: endpoint,
                headers: ["Authorization": "Bearer \(configuration.apiKey)"],
                model: configuration.model.isEmpty ? RemoteASRProvider.openAIWhisper.suggestedModel : configuration.model
            )
        case .glmASR:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -4, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("GLM API Key is required for testing.")])
            }
            let endpoint = RemoteProviderConnectivityTestEndpoints.resolvedGLMASRTranscriptionEndpoint(
                endpoint: configuration.endpoint,
                defaultValue: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions"
            )
            return try await testASRMultipartReachability(
                endpoint: endpoint,
                headers: ["Authorization": "Bearer \(configuration.apiKey)"],
                model: configuration.model.isEmpty ? "glm-asr-1" : configuration.model
            )
        case .aliyunBailianASR:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -5, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Aliyun Bailian API Key is required for testing.")])
            }
            let model = configuration.model.isEmpty ? "fun-asr-realtime" : configuration.model
            if let kind = RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: model) {
                let endpoint = RemoteProviderConnectivityTestEndpoints.resolvedAliyunASRQwenRealtimeWebSocketEndpoint(
                    endpoint: configuration.endpoint,
                    model: model
                )
                return try await testAliyunASRQwenRealtimeWebSocketReachability(
                    endpoint: endpoint,
                    apiKey: configuration.apiKey,
                    kind: kind
                )
            }
            let endpoint = RemoteProviderConnectivityTestEndpoints.resolvedAliyunASRRealtimeWebSocketEndpoint(
                endpoint: configuration.endpoint,
                defaultValue: "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
            )
            return try await testAliyunASRRealtimeWebSocketReachability(
                endpoint: endpoint,
                apiKey: configuration.apiKey,
                model: model
            )
        }
    }

    private func testAliyunASRRealtimeReachability(
        endpoint: String,
        apiKey: String,
        model: String,
        successMessage: String = ""
    ) async throws -> String {
        let audioDataURI = "data:audio/wav;base64,\(silentTestWavData().base64EncodedString())"
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": audioDataURI,
                                "format": "wav"
                            ]
                        ]
                    ]
                ]
            ],
            "stream": false
        ]
        return try await testJSONPOSTReachability(
            endpoint: endpoint,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: body,
            successMessage: successMessage
        )
    }

    private func testAliyunASRRealtimeWebSocketReachability(
        endpoint: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -50, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid WebSocket endpoint URL.")])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        RemoteProviderConnectivityTestLogging.logHTTPRequest(context: "Aliyun ASR realtime WebSocket test", request: request, bodyPreview: "run-task + finish-task")

        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        let ws = managedSocket.task
        ws.resume()
        defer {
            ws.cancel(with: .goingAway, reason: nil)
        }

        let taskID = AliyunRemoteASRConfiguration.makeRealtimeTaskID()
        let runPayload = AliyunRemoteASRConfiguration.funRealtimeControlPayload(
            action: "run-task",
            taskID: taskID,
            model: model,
            parameters: [
                "sample_rate": 16000,
                "format": "pcm",
                "language_hints": ["zh", "en"]
            ]
        )
        let finishPayload = AliyunRemoteASRConfiguration.funRealtimeControlPayload(
            action: "finish-task",
            taskID: taskID
        )
        let runData = try JSONSerialization.data(withJSONObject: runPayload)
        let finishData = try JSONSerialization.data(withJSONObject: finishPayload)
        guard let runText = String(data: runData, encoding: .utf8),
              let finishText = String(data: finishData, encoding: .utf8) else {
            throw NSError(domain: "Voxt.Settings", code: -51, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Failed to encode Aliyun WebSocket payload.")])
        }

        try await ws.send(.string(runText))
        try await ws.send(.string(finishText))

        for _ in 0..<6 {
            let message = try await receiveWebSocketMessage(task: ws, timeoutSeconds: 3)
            guard case .string(let text) = message,
                  let data = text.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let event = AliyunRemoteASRConfiguration.realtimeSocketEvent(from: object)
            if event == "task-started" || event == "task-finished" || event == "result-generated" {
                return AppLocalization.localizedString("Connection test succeeded (Aliyun ASR WebSocket reachable).")
            }
            if event == "task-failed" || event == "error" {
                let detail = AliyunRemoteASRConfiguration.realtimeSocketErrorMessage(from: object) ?? ""
                throw NSError(
                    domain: "Voxt.Settings",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Connection failed (HTTP %d). %@", 403, detail)]
                )
            }
        }

        throw NSError(
            domain: "Voxt.Settings",
            code: -52,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Connection failed (HTTP %d). %@").replacingOccurrences(of: "%d", with: "0").replacingOccurrences(of: "%@", with: "No valid ASR response packet.")]
        )
    }

    private func testAliyunASRQwenRealtimeWebSocketReachability(
        endpoint: String,
        apiKey: String,
        kind: AliyunQwenRealtimeSessionKind
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -53, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid WebSocket endpoint URL.")])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        RemoteProviderConnectivityTestLogging.logHTTPRequest(context: "Aliyun ASR Qwen realtime WebSocket test", request: request, bodyPreview: "session.update + session.finish")

        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        let ws = managedSocket.task
        ws.resume()
        defer {
            ws.cancel(with: .goingAway, reason: nil)
        }

        let updatePayload = AliyunQwenRealtimePayloadSupport.sessionUpdatePayload(
            kind: kind,
            hintPayload: .init(language: "zh", languageHints: ["zh"])
        )
        let finishPayload: [String: Any] = [
            "event_id": UUID().uuidString.lowercased(),
            "type": "session.finish"
        ]
        let updateData = try JSONSerialization.data(withJSONObject: updatePayload)
        let finishData = try JSONSerialization.data(withJSONObject: finishPayload)
        guard let updateText = String(data: updateData, encoding: .utf8),
              let finishText = String(data: finishData, encoding: .utf8) else {
            throw NSError(domain: "Voxt.Settings", code: -54, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Failed to encode Aliyun Qwen realtime payload.")])
        }

        do {
            try await ws.send(.string(updateText))
        } catch {
            throw NSError(
                domain: "Voxt.Settings",
                code: -56,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Network connection failed before realtime handshake. %@ (Check proxy/VPN and endpoint reachability.)", error.localizedDescription)]
            )
        }

        do {
            for _ in 0..<6 {
                let message = try await receiveWebSocketMessage(task: ws, timeoutSeconds: 3)
                guard case .string(let text) = message,
                      let data = text.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                let type = (object["type"] as? String ?? "").lowercased()
                if type == "session.created" || type == "session.updated" || type == "conversation.item.input_audio_transcription.text" {
                    try await ws.send(.string(finishText))
                    return AppLocalization.localizedString("Connection test succeeded (Aliyun Qwen realtime WebSocket reachable).")
                }
                if type == "error" {
                    let detail = (object["message"] as? String) ?? ""
                    throw NSError(
                        domain: "Voxt.Settings",
                        code: 403,
                        userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Connection failed (HTTP %d). %@", 403, detail)]
                    )
                }
            }
        } catch {
            if isWebSocketHandshakeFailure(error),
               let detailedError = await fetchAliyunQwenRealtimeHandshakeFailureDetail(
                endpoint: endpoint,
                apiKey: apiKey
               ) {
                throw detailedError
            }
            throw NSError(
                domain: "Voxt.Settings",
                code: -57,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Realtime WebSocket receive failed. %@ (Check proxy/VPN or region endpoint.)", error.localizedDescription)]
            )
        }

        throw NSError(
            domain: "Voxt.Settings",
            code: -55,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Connection failed (HTTP %d). %@").replacingOccurrences(of: "%d", with: "0").replacingOccurrences(of: "%@", with: "No valid ASR response packet.")]
        )
    }

    private func testASRMultipartReachability(
        endpoint: String,
        headers: [String: String],
        model: String
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -20, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid ASR endpoint URL.")])
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = makeASRTestMultipartBody(boundary: boundary, model: model)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream, text/plain", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        RemoteProviderConnectivityTestLogging.logHTTPRequest(
            context: "ASR multipart test",
            request: request,
            bodyPreview: "multipart/form-data body bytes=\(body.count)"
        )

        let (data, response) = try await VoxtNetworkSession.active.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -21, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        RemoteProviderConnectivityTestLogging.logHTTPResponse(context: "ASR multipart test", response: http, data: data)

        let payload = String(data: data.prefix(200), encoding: .utf8) ?? ""
        if (200...299).contains(http.statusCode) {
            return AppLocalization.format("Connection test succeeded (HTTP %d).", http.statusCode)
        }
        if http.statusCode == 400 || http.statusCode == 422 {
            return AppLocalization.format("Endpoint reachable (HTTP %d). Authentication and routing look valid.", http.statusCode)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NSError(
                domain: "Voxt.Settings",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Server reachable, but authentication failed (HTTP %d). %@", http.statusCode, payload)]
            )
        }
        throw NSError(
            domain: "Voxt.Settings",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Connection failed (HTTP %d). %@", http.statusCode, payload)]
        )
    }

    private func makeASRTestMultipartBody(boundary: String, model: String) -> Data {
        var body = Data()

        func append(_ text: String) {
            body.append(text.data(using: .utf8) ?? Data())
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"test.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(silentTestWavData())
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }

    private func silentTestWavData() -> Data {
        var data = Data()
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let durationMs: UInt32 = 100
        let samples = sampleRate * durationMs / 1000
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataSize = samples * UInt32(channels) * bytesPerSample
        let byteRate = sampleRate * UInt32(channels) * bytesPerSample
        let blockAlign = channels * (bitsPerSample / 8)
        let riffSize = 36 + dataSize

        data.append("RIFF".data(using: .ascii) ?? Data())
        data.append(le32(riffSize))
        data.append("WAVE".data(using: .ascii) ?? Data())
        data.append("fmt ".data(using: .ascii) ?? Data())
        data.append(le32(16))
        data.append(le16(1))
        data.append(le16(channels))
        data.append(le32(sampleRate))
        data.append(le32(byteRate))
        data.append(le16(blockAlign))
        data.append(le16(bitsPerSample))
        data.append("data".data(using: .ascii) ?? Data())
        data.append(le32(dataSize))
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func le16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func testLLMProvider(_ provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration) async throws -> String {
        let model = configuration.model.isEmpty ? provider.suggestedModel : configuration.model
        let endpoint = resolvedLLMTestEndpoint(provider: provider, endpoint: configuration.endpoint, model: model)
        var headers: [String: String] = [:]
        switch provider {
        case .anthropic:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -30, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Anthropic API Key is required for testing.")])
            }
            headers["x-api-key"] = configuration.apiKey
            headers["anthropic-version"] = "2023-06-01"
            return try await testAnthropicReachability(endpoint: endpoint, headers: headers, model: model)
        case .google:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -31, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Google API Key is required for testing.")])
            }
            return try await testGoogleReachability(endpoint: endpoint, apiKey: configuration.apiKey)
        case .minimax:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -32, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("MiniMax API Key is required for testing.")])
            }
            headers["Authorization"] = "Bearer \(configuration.apiKey)"
            return try await testMiniMaxReachability(endpoint: endpoint, headers: headers, model: model)
        case .openAI, .ollama, .omlx, .deepseek, .openrouter, .grok, .zai, .volcengine, .kimi, .lmStudio, .aliyunBailian:
            if !configuration.apiKey.isEmpty {
                headers["Authorization"] = "Bearer \(configuration.apiKey)"
            }
            if provider.usesResponsesAPI {
                return try await testResponsesReachability(
                    provider: provider,
                    endpoint: endpoint,
                    headers: headers,
                    configuration: configuration,
                    model: model
                )
            }
            return try await testOpenAICompatibleReachability(
                provider: provider,
                endpoint: endpoint,
                headers: headers,
                configuration: configuration,
                model: model
            )
        }
    }

    private func testOpenAICompatibleReachability(
        provider: RemoteLLMProvider,
        endpoint: String,
        headers: [String: String],
        configuration: RemoteProviderConfiguration,
        model: String
    ) async throws -> String {
        let runtimeClient = RemoteLLMRuntimeClient()
        let requestEndpoint: String
        if provider == .ollama {
            requestEndpoint = runtimeClient.resolvedOllamaRequestEndpoint(
                endpoint: endpoint,
                useGenerate: false
            )
        } else {
            requestEndpoint = endpoint
        }
        let body = try await openAICompatibleReachabilityBody(
            provider: provider,
            endpoint: requestEndpoint,
            configuration: configuration,
            model: model
        )
        return try await testJSONPOSTReachability(endpoint: requestEndpoint, headers: headers, body: body)
    }

    func openAICompatibleReachabilityBody(
        provider: RemoteLLMProvider,
        endpoint: String,
        configuration: RemoteProviderConfiguration,
        model: String
    ) async throws -> [String: Any] {
        let runtimeClient = RemoteLLMRuntimeClient()
        if provider == .ollama,
           let url = URL(string: endpoint),
           usesNativeOllamaEndpoint(url) {
            return try runtimeClient.ollamaNativePayload(
                endpointURL: url,
                model: model,
                systemPrompt: "",
                userPrompt: "ping",
                configuration: configuration,
                tuning: .init(maxTokens: 32, temperature: 0.2, topP: 0.9),
                streamingEnabled: false
            )
        }

        if provider == .deepseek {
            return [
                "model": model,
                "messages": [
                    ["role": "user", "content": "ping"]
                ],
                "thinking": [
                    "type": "disabled"
                ],
                "max_tokens": 1,
                "stream": false
            ]
        }

        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "ping"]
            ],
            "stream": false
        ]
        if provider == .ollama {
            try runtimeClient.applyOllamaCompatibleOptionOverrides(
                to: &payload,
                configuration: configuration
            )
        } else if provider == .omlx {
            try runtimeClient.applyOMLXCompatibleConfiguration(
                to: &payload,
                configuration: configuration
            )
        }
        return payload
    }

    private func testResponsesReachability(
        provider: RemoteLLMProvider,
        endpoint: String,
        headers: [String: String],
        configuration: RemoteProviderConfiguration,
        model: String
    ) async throws -> String {
        let runtimeClient = RemoteLLMRuntimeClient()
        let request = try runtimeClient.makeResponsesRequest(
            provider: provider,
            endpointValue: endpoint,
            model: model,
            systemPrompt: "",
            inputPayload: "ping",
            configuration: configuration,
            previousResponseID: nil,
            tuning: .init(maxTokens: 32, temperature: 0.2, topP: 0.9),
            textFormat: nil,
            streamingEnabled: false
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
        return try await testJSONPOSTReachability(endpoint: endpoint, headers: headers, body: body)
    }

    private func testAnthropicReachability(
        endpoint: String,
        headers: [String: String],
        model: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "ping"]
            ],
            "stream": false
        ]
        return try await testJSONPOSTReachability(endpoint: endpoint, headers: headers, body: body)
    }

    private func testGoogleReachability(
        endpoint: String,
        apiKey: String
    ) async throws -> String {
        guard var components = URLComponents(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -33, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid Google endpoint URL.")])
        }
        let hasKeyQuery = components.queryItems?.contains(where: { $0.name == "key" }) ?? false
        if !hasKeyQuery {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "key", value: apiKey))
            components.queryItems = items
        }
        guard let url = components.url else {
            throw NSError(domain: "Voxt.Settings", code: -34, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid Google endpoint URL.")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": "ping"]]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await sendLLMTestRequest(request, context: "LLM Google test")
    }

    private func testMiniMaxReachability(
        endpoint: String,
        headers: [String: String],
        model: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "ping"]
            ]
        ]
        return try await testJSONPOSTReachability(endpoint: endpoint, headers: headers, body: body)
    }

    private func testJSONPOSTReachability(
        endpoint: String,
        headers: [String: String],
        body: [String: Any],
        successMessage: String = ""
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -35, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid endpoint URL.")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await sendLLMTestRequest(
            request,
            context: "LLM JSON POST test",
            successMessage: successMessage
        )
    }

    private func sendLLMTestRequest(
        _ request: URLRequest,
        context: String,
        successMessage: String = ""
    ) async throws -> String {
        let bodyPreview = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "<empty>"
        RemoteProviderConnectivityTestLogging.logHTTPRequest(context: context, request: request, bodyPreview: bodyPreview)
        let (data, response) = try await VoxtNetworkSession.active.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -36, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        RemoteProviderConnectivityTestLogging.logHTTPResponse(context: context, response: http, data: data)

        let payload = String(data: data.prefix(220), encoding: .utf8) ?? ""
        if (200...299).contains(http.statusCode) {
            if !successMessage.isEmpty {
                return successMessage
            }
            return AppLocalization.format("Connection test succeeded (HTTP %d).", http.statusCode)
        }
        if http.statusCode == 400 || http.statusCode == 422 {
            return AppLocalization.format("Endpoint reachable (HTTP %d). Authentication and routing look valid.", http.statusCode)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NSError(
                domain: "Voxt.Settings",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Server reachable, but authentication failed (HTTP %d). %@", http.statusCode, payload)]
            )
        }
        throw NSError(
            domain: "Voxt.Settings",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Connection failed (HTTP %d). %@", http.statusCode, payload)]
        )
    }

    private func usesNativeOllamaEndpoint(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.isEmpty ||
            path == "/" ||
            path == "/api" ||
            path.hasSuffix("/api/chat") ||
            path.hasSuffix("/api/generate") ||
            path.hasSuffix("/api/tags")
    }

    private func testHTTPReachability(
        endpoint: String,
        headers: [String: String]
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -10, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid endpoint URL.")])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        RemoteProviderConnectivityTestLogging.logHTTPRequest(context: "HTTP reachability test", request: request, bodyPreview: "<empty>")

        let (data, response) = try await VoxtNetworkSession.active.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -11, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        RemoteProviderConnectivityTestLogging.logHTTPResponse(context: "HTTP reachability test", response: http, data: data)
        if (200...299).contains(http.statusCode) {
            return AppLocalization.format("Connection test succeeded (HTTP %d).", http.statusCode)
        }
        let payload = String(data: data.prefix(180), encoding: .utf8) ?? ""
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NSError(
                domain: "Voxt.Settings",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Server reachable, but authentication failed (HTTP %d). %@", http.statusCode, payload)]
            )
        }
        throw NSError(
            domain: "Voxt.Settings",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Connection failed (HTTP %d). %@", http.statusCode, payload)]
        )
    }

    private func testWebSocketReachability(
        endpoint: String,
        headers: [String: String]
    ) async throws {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -12, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid WebSocket endpoint URL.")])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        RemoteProviderConnectivityTestLogging.logHTTPRequest(context: "WebSocket reachability test", request: request, bodyPreview: "<websocket ping>")
        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        let task = managedSocket.task
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    VoxtLog.warning("WebSocket reachability test failed. error=\(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    VoxtLog.info("WebSocket reachability test succeeded.")
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func testDoubaoStreamingReachability(
        endpoint: String,
        appID: String,
        accessToken: String,
        model: String,
        successMessage: String = ""
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -12, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid WebSocket endpoint URL.")])
        }

        let resourceID = DoubaoConnectivityTestSupport.normalizedResourceID(model)
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        RemoteProviderConnectivityTestLogging.logHTTPRequest(
            context: "Doubao streaming test",
            request: request,
            bodyPreview: "full-request(audio=\(DoubaoASRConfiguration.requestAudioFormat),gzip) + silent wav bytes(gzip)"
        )

        do {
            let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
            let ws = managedSocket.task
            ws.resume()
            defer {
                ws.cancel(with: .goingAway, reason: nil)
            }

            let reqID = UUID().uuidString.lowercased()
            let payloadObject = DoubaoASRConfiguration.fullRequestPayload(
                requestID: reqID,
                userID: "voxt-test",
                language: "zh-CN",
                chineseOutputVariant: nil
            )
            let initPayload = try JSONSerialization.data(withJSONObject: payloadObject)
            let (initCompression, initPacketPayload) = DoubaoConnectivityTestSupport.encodePacketPayload(initPayload, preferGzip: true)
            try await ws.send(.data(DoubaoConnectivityTestSupport.buildPacket(
                messageType: 0x1,
                messageFlags: 0x1,
                serialization: 0x1,
                compression: initCompression,
                sequence: 1,
                payload: initPacketPayload
            )))

            let (audioCompression, audioPayload) = DoubaoConnectivityTestSupport.encodePacketPayload(silentTestWavData(), preferGzip: true)
            try await ws.send(.data(DoubaoConnectivityTestSupport.buildPacket(
                messageType: 0x2,
                messageFlags: 0x3,
                serialization: 0x0,
                compression: audioCompression,
                sequence: -2,
                payload: audioPayload
            )))

            for index in 1...4 {
                let message = try await receiveWebSocketMessage(task: ws, timeoutSeconds: 3)
                guard case .data(let packetData) = message else { continue }
                let parsed = try DoubaoConnectivityTestSupport.parseServerPacket(packetData)
                VoxtLog.info(
                    "Doubao test server packet. index=\(index), type=\(parsed.messageType), bytes=\(packetData.count), hasText=\(parsed.hasText), isFinal=\(parsed.isFinal)",
                    verbose: true
                )

                if let errorText = parsed.errorText, !errorText.isEmpty {
                    throw NSError(domain: "Voxt.Settings", code: 403, userInfo: [NSLocalizedDescriptionKey: errorText])
                }
                if parsed.hasText || parsed.isFinal || parsed.messageType == 0xB || parsed.messageType == 0x9 {
                    if !successMessage.isEmpty {
                        return successMessage
                    }
                    return AppLocalization.localizedString("Connection test succeeded (Doubao WebSocket reachable).")
                }
            }

            throw NSError(
                domain: "Voxt.Settings",
                code: -120,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Connection failed (HTTP %d). %@").replacingOccurrences(of: "%d", with: "0").replacingOccurrences(of: "%@", with: "No valid ASR response packet.")]
            )
        } catch {
            if isWebSocketHandshakeFailure(error),
               let detailedError = await fetchDoubaoHandshakeFailureDetail(
                    endpoint: endpoint,
                    appID: appID,
                    accessToken: accessToken,
                    resourceID: resourceID
               ) {
                throw detailedError
            }
            throw error
        }
    }

    private func receiveWebSocketMessage(
        task: URLSessionWebSocketTask,
        timeoutSeconds: TimeInterval
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await task.receive()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw NSError(
                    domain: "Voxt.Settings",
                    code: -121,
                    userInfo: [NSLocalizedDescriptionKey: "Doubao test timed out waiting for server packet."]
                )
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func isWebSocketHandshakeFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorBadServerResponse
    }

    private func fetchDoubaoHandshakeFailureDetail(
        endpoint: String,
        appID: String,
        accessToken: String,
        resourceID: String
    ) async -> NSError? {
        guard var components = URLComponents(string: endpoint) else {
            return nil
        }
        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }
        guard let probeURL = components.url else {
            return nil
        }

        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")

        do {
            let (data, response) = try await VoxtNetworkSession.active.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return nil
            }
            RemoteProviderConnectivityTestLogging.logHTTPResponse(context: "Doubao handshake probe", response: http, data: data)
            let payload = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if payload.isEmpty {
                return NSError(
                    domain: "Voxt.Settings",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Doubao handshake failed (HTTP %d).", http.statusCode)]
                )
            }
            return NSError(
                domain: "Voxt.Settings",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Doubao handshake failed (HTTP %d): %@", http.statusCode, payload)]
            )
        } catch {
            return nil
        }
    }

    private func fetchAliyunQwenRealtimeHandshakeFailureDetail(
        endpoint: String,
        apiKey: String
    ) async -> NSError? {
        guard var components = URLComponents(string: endpoint) else {
            return nil
        }
        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }
        guard let probeURL = components.url else {
            return nil
        }

        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        do {
            let (data, response) = try await VoxtNetworkSession.active.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            RemoteProviderConnectivityTestLogging.logHTTPResponse(context: "Aliyun Qwen realtime handshake probe", response: http, data: data)
            let payload = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if payload.isEmpty {
                return NSError(
                    domain: "Voxt.Settings",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Aliyun Qwen realtime handshake failed (HTTP %d).", http.statusCode)]
                )
            }
            return NSError(
                domain: "Voxt.Settings",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Aliyun Qwen realtime handshake failed (HTTP %d). %@", http.statusCode, payload)]
            )
        } catch {
            return nil
        }
    }

    private func providerDefaultTestEndpoint(_ provider: RemoteLLMProvider) -> String {
        RemoteLLMRuntimeClient().providerDefaultEndpoint(provider)
    }

    private func resolvedLLMTestEndpoint(provider: RemoteLLMProvider, endpoint: String, model: String) -> String {
        RemoteLLMRuntimeClient().resolvedLLMEndpoint(
            provider: provider,
            endpoint: endpoint,
            model: model
        )
    }

    private var testTargetLogName: String {
        switch testTarget {
        case .asr:
            return "asr"
        case .llm:
            return "llm"
        }
    }

}

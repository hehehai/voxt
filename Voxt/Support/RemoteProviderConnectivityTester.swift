import Foundation
import zlib

enum RemoteProviderTestTarget {
    case asr(RemoteASRProvider)
    case meetingASR(RemoteASRProvider)
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
        case .meetingASR(let provider):
            return try await testMeetingASRProvider(provider, configuration: configuration)
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
            let endpoint = resolvedDoubaoASREndpoint(configuration.endpoint, model: configuration.model)
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
            let endpoint = resolvedASRTranscriptionEndpoint(
                endpoint: configuration.endpoint,
                defaultValue: "https://api.openai.com/v1/audio/transcriptions"
            )
            return try await testASRMultipartReachability(
                endpoint: endpoint,
                headers: ["Authorization": "Bearer \(configuration.apiKey)"],
                model: configuration.model.isEmpty ? "whisper-1" : configuration.model
            )
        case .glmASR:
            guard !configuration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -4, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("GLM API Key is required for testing.")])
            }
            let endpoint = resolvedGLMASRTranscriptionEndpoint(
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
            if isAliyunQwenRealtimeModel(model) {
                let endpoint = resolvedAliyunASRQwenRealtimeWebSocketEndpoint(
                    endpoint: configuration.endpoint,
                    model: model
                )
                return try await testAliyunASRQwenRealtimeWebSocketReachability(
                    endpoint: endpoint,
                    apiKey: configuration.apiKey
                )
            }
            let endpoint = resolvedAliyunASRRealtimeWebSocketEndpoint(
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

    private func testMeetingASRProvider(
        _ provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        guard RemoteASRMeetingConfiguration.hasValidMeetingModel(
            provider: provider,
            configuration: configuration
        ) else {
            throw NSError(
                domain: "Voxt.Settings",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: RemoteASRMeetingConfiguration.startBlockedMessage(for: provider, configuration: configuration)]
            )
        }

        let meetingConfiguration = RemoteASRMeetingConfiguration.resolvedMeetingConfiguration(
            provider: provider,
            configuration: configuration
        )

        switch provider {
        case .doubaoASR:
            let token = meetingConfiguration.accessToken
            guard !token.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -7, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Doubao Access Token is required for testing.")])
            }
            guard !meetingConfiguration.appID.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -8, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Doubao App ID is required for testing.")])
            }
            let endpoint = DoubaoASRConfiguration.resolvedMeetingFlashEndpoint(
                meetingConfiguration.endpoint
            )
            return try await testDoubaoMeetingReachability(
                endpoint: endpoint,
                appID: meetingConfiguration.appID,
                accessToken: token,
                model: meetingConfiguration.model,
                successMessage: AppLocalization.localizedString("Connection test succeeded (Meeting ASR reachable).")
            )
        case .aliyunBailianASR:
            guard !meetingConfiguration.apiKey.isEmpty else {
                throw NSError(domain: "Voxt.Settings", code: -9, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Aliyun Bailian API Key is required for testing.")])
            }
            let model = meetingConfiguration.model.isEmpty
                ? RemoteASRMeetingConfiguration.suggestedMeetingModel(for: provider)
                : meetingConfiguration.model
            switch AliyunMeetingASRConfiguration.routing(for: model) {
            case .asyncFileTranscription:
                let endpoint = AliyunMeetingASRConfiguration.resolvedTranscriptionEndpoint(
                    meetingConfiguration.endpoint,
                    model: model
                )
                return try await testAliyunMeetingReachability(
                    endpoint: endpoint,
                    apiKey: meetingConfiguration.apiKey,
                    model: model,
                    successMessage: AppLocalization.localizedString("Connection test succeeded (Meeting ASR reachable).")
                )
            case .compatibleShortAudio:
                let endpoint = AliyunMeetingASRConfiguration.resolvedCompatibleEndpoint(
                    meetingConfiguration.endpoint,
                    model: model
                )
                return try await testAliyunASRRealtimeReachability(
                    endpoint: endpoint,
                    apiKey: meetingConfiguration.apiKey,
                    model: model,
                    successMessage: AppLocalization.localizedString("Connection test succeeded (Meeting ASR reachable).")
                )
            case nil:
                throw NSError(
                    domain: "Voxt.Settings",
                    code: -125,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.format("Aliyun meeting ASR model %@ is not supported.", model)]
                )
            }
        case .openAIWhisper, .glmASR:
            return try await testASRProvider(provider, configuration: configuration)
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

    private func testAliyunMeetingReachability(
        endpoint: String,
        apiKey: String,
        model: String,
        successMessage: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "input": [
                "file_url": "https://dashscope.oss-cn-beijing.aliyuncs.com/audios/welcome.mp3"
            ],
            "parameters": [
                "channel_id": [0]
            ]
        ]

        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -124, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid endpoint URL.")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await sendLLMTestRequest(
            request,
            context: "Aliyun meeting ASR test",
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
        logHTTPRequest(context: "Aliyun ASR realtime WebSocket test", request: request, bodyPreview: "run-task + finish-task")

        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        let ws = managedSocket.task
        ws.resume()
        defer {
            ws.cancel(with: .goingAway, reason: nil)
        }

        let taskID = AliyunMeetingASRConfiguration.makeRealtimeTaskID()
        let runPayload = AliyunMeetingASRConfiguration.funRealtimeControlPayload(
            action: "run-task",
            taskID: taskID,
            model: model,
            parameters: [
                "sample_rate": 16000,
                "format": "pcm",
                "language_hints": ["zh", "en"]
            ]
        )
        let finishPayload = AliyunMeetingASRConfiguration.funRealtimeControlPayload(
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
            let event = AliyunMeetingASRConfiguration.realtimeSocketEvent(from: object)
            if event == "task-started" || event == "task-finished" || event == "result-generated" {
                return AppLocalization.localizedString("Connection test succeeded (Aliyun ASR WebSocket reachable).")
            }
            if event == "task-failed" || event == "error" {
                let detail = AliyunMeetingASRConfiguration.realtimeSocketErrorMessage(from: object) ?? ""
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
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -53, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid WebSocket endpoint URL.")])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        logHTTPRequest(context: "Aliyun ASR Qwen realtime WebSocket test", request: request, bodyPreview: "session.update + session.finish")

        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        let ws = managedSocket.task
        ws.resume()
        defer {
            ws.cancel(with: .goingAway, reason: nil)
        }

        let updatePayload: [String: Any] = [
            "event_id": UUID().uuidString.lowercased(),
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "input_audio_format": "pcm",
                "sample_rate": 16000,
                "input_audio_transcription": [
                    "language": "zh"
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.0,
                    "silence_duration_ms": 400
                ]
            ]
        ]
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
        logHTTPRequest(
            context: "ASR multipart test",
            request: request,
            bodyPreview: "multipart/form-data body bytes=\(body.count)"
        )

        let (data, response) = try await VoxtNetworkSession.active.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -21, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        logHTTPResponse(context: "ASR multipart test", response: http, data: data)

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

    private func resolvedASRTranscriptionEndpoint(endpoint: String, defaultValue: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultValue }
        guard let url = URL(string: trimmed) else { return trimmed }
        let normalizedPath = url.path.lowercased()
        if normalizedPath.hasSuffix("/audio/transcriptions") {
            return trimmed
        }
        if normalizedPath.hasSuffix("/v1") {
            return trimmed + "/audio/transcriptions"
        }
        if normalizedPath.isEmpty || normalizedPath == "/" {
            return trimmed.hasSuffix("/") ? trimmed + "v1/audio/transcriptions" : trimmed + "/v1/audio/transcriptions"
        }
        return trimmed
    }

    private func resolvedGLMASRTranscriptionEndpoint(endpoint: String, defaultValue: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultValue }
        guard let url = URL(string: trimmed) else { return trimmed }
        let normalizedPath = url.path.lowercased()
        if normalizedPath.hasSuffix("/audio/transcriptions") {
            return trimmed
        }
        if normalizedPath.hasSuffix("/models") {
            return replacingPathSuffix(in: trimmed, oldSuffix: "/models", newSuffix: "/audio/transcriptions")
        }
        if normalizedPath.hasSuffix("/v4") {
            return appendingPath(trimmed, suffix: "/audio/transcriptions")
        }
        return trimmed
    }

    private func resolvedAliyunASRRealtimeEndpoint(endpoint: String, defaultValue: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultValue }
        guard let url = URL(string: trimmed) else { return trimmed }
        let normalizedPath = url.path.lowercased()
        if normalizedPath.hasSuffix("/chat/completions") {
            return trimmed
        }
        if normalizedPath.hasSuffix("/models") {
            return replacingPathSuffix(in: trimmed, oldSuffix: "/models", newSuffix: "/chat/completions")
        }
        if normalizedPath.hasSuffix("/v1") {
            return appendingPath(trimmed, suffix: "/chat/completions")
        }
        if normalizedPath.isEmpty || normalizedPath == "/" {
            return trimmed.hasSuffix("/") ? trimmed + "v1/chat/completions" : trimmed + "/v1/chat/completions"
        }
        return trimmed
    }

    private func resolvedAliyunASRRealtimeWebSocketEndpoint(endpoint: String, defaultValue: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultValue }
        guard var components = URLComponents(string: trimmed) else { return trimmed }
        let normalizedPath = components.path.lowercased()
        if normalizedPath.hasSuffix("/api-ws/v1/inference") {
            return trimmed
        }
        if normalizedPath.hasSuffix("/api-ws/v1/realtime") {
            components.path = components.path.replacingOccurrences(of: "/api-ws/v1/realtime", with: "/api-ws/v1/inference")
            components.queryItems = nil
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/chat/completions") {
            return replacingPathSuffix(in: trimmed, oldSuffix: "/chat/completions", newSuffix: "/api-ws/v1/inference")
        }
        if normalizedPath.hasSuffix("/models") {
            return replacingPathSuffix(in: trimmed, oldSuffix: "/models", newSuffix: "/api-ws/v1/inference")
        }
        if normalizedPath.hasSuffix("/v1") {
            return appendingPath(trimmed, suffix: "/inference")
        }
        if normalizedPath.isEmpty || normalizedPath == "/" {
            return trimmed.hasSuffix("/") ? trimmed + "api-ws/v1/inference" : trimmed + "/api-ws/v1/inference"
        }
        return trimmed
    }

    private func resolvedAliyunASRQwenRealtimeWebSocketEndpoint(endpoint: String, model: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? model
        guard !trimmed.isEmpty else {
            return "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=\(encodedModel)"
        }
        guard var components = URLComponents(string: trimmed) else { return trimmed }
        let normalizedPath = components.path.lowercased()
        if normalizedPath.hasSuffix("/api-ws/v1/realtime") {
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "model" }) {
                items.append(URLQueryItem(name: "model", value: model))
                components.queryItems = items
            }
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/api-ws/v1/inference") {
            components.path = components.path.replacingOccurrences(of: "/api-ws/v1/inference", with: "/api-ws/v1/realtime")
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "model" }) {
                items.append(URLQueryItem(name: "model", value: model))
                components.queryItems = items
            }
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/chat/completions") {
            let base = replacingPathSuffix(in: trimmed, oldSuffix: "/chat/completions", newSuffix: "/api-ws/v1/realtime")
            return base.contains("?") ? base : "\(base)?model=\(encodedModel)"
        }
        return trimmed
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
        case .openAI, .ollama, .deepseek, .openrouter, .grok, .zai, .volcengine, .kimi, .lmStudio, .aliyunBailian:
            if !configuration.apiKey.isEmpty {
                headers["Authorization"] = "Bearer \(configuration.apiKey)"
            }
            if provider.usesResponsesAPI {
                return try await testResponsesReachability(
                    endpoint: endpoint,
                    headers: headers,
                    model: model
                )
            }
            return try await testOpenAICompatibleReachability(
                provider: provider,
                endpoint: endpoint,
                headers: headers,
                model: model
            )
        }
    }

    private func testOpenAICompatibleReachability(
        provider: RemoteLLMProvider,
        endpoint: String,
        headers: [String: String],
        model: String
    ) async throws -> String {
        let body: [String: Any]
        if provider == .ollama,
           let url = URL(string: endpoint),
           usesNativeOllamaChatEndpoint(url) {
            body = [
                "model": model,
                "messages": [
                    ["role": "user", "content": "ping"]
                ],
                "stream": false,
                "options": [
                    "temperature": 0.2,
                    "top_p": 0.9,
                    "num_predict": 32
                ]
            ]
        } else {
            body = [
                "model": model,
                "messages": [
                    ["role": "user", "content": "ping"]
                ],
                "stream": false
            ]
        }
        return try await testJSONPOSTReachability(endpoint: endpoint, headers: headers, body: body)
    }

    private func testResponsesReachability(
        endpoint: String,
        headers: [String: String],
        model: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "input": "ping"
        ]
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
        logHTTPRequest(context: context, request: request, bodyPreview: bodyPreview)
        let (data, response) = try await VoxtNetworkSession.active.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -36, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        logHTTPResponse(context: context, response: http, data: data)

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

    private func usesNativeOllamaChatEndpoint(_ url: URL) -> Bool {
        url.path.lowercased().hasSuffix("/api/chat")
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
        logHTTPRequest(context: "HTTP reachability test", request: request, bodyPreview: "<empty>")

        let (data, response) = try await VoxtNetworkSession.active.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -11, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        logHTTPResponse(context: "HTTP reachability test", response: http, data: data)
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
        logHTTPRequest(context: "WebSocket reachability test", request: request, bodyPreview: "<websocket ping>")
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

    private func resolvedDoubaoASREndpoint(_ endpoint: String, model: String) -> String {
        DoubaoASRConfiguration.resolvedStreamingEndpoint(endpoint, model: model)
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

        let resourceID = normalizedDoubaoResourceID(model)
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        logHTTPRequest(
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
            let (initCompression, initPacketPayload) = encodeDoubaoTestPacketPayload(initPayload, preferGzip: true)
            try await ws.send(.data(buildDoubaoTestPacket(
                messageType: 0x1,
                messageFlags: 0x1,
                serialization: 0x1,
                compression: initCompression,
                sequence: 1,
                payload: initPacketPayload
            )))

            let (audioCompression, audioPayload) = encodeDoubaoTestPacketPayload(silentTestWavData(), preferGzip: true)
            try await ws.send(.data(buildDoubaoTestPacket(
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
                let parsed = try parseDoubaoTestServerPacket(packetData)
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

    private func testDoubaoMeetingReachability(
        endpoint: String,
        appID: String,
        accessToken: String,
        model: String,
        successMessage: String
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Settings", code: -122, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid endpoint URL.")])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(normalizedDoubaoResourceID(model), forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Api-Request-Id")
        let body: [String: Any] = [
            "user": ["uid": "voxt-test"],
            "audio": ["data": silentTestWavData().base64EncodedString()],
            "request": [
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "show_utterances": true
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        logHTTPRequest(
            context: "Doubao meeting ASR flash test",
            request: request,
            bodyPreview: "{\"audio\":\"<base64 wav>\",\"request\":{\"show_utterances\":true}}"
        )

        let (data, response) = try await VoxtNetworkSession.active.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.Settings", code: -123, userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Invalid server response.")])
        }
        logHTTPResponse(context: "Doubao meeting ASR flash test", response: http, data: data)

        let payload = String(data: data.prefix(220), encoding: .utf8) ?? ""
        if (200...299).contains(http.statusCode) {
            let apiStatus = http.value(forHTTPHeaderField: "X-Api-Status-Code")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if apiStatus.isEmpty || apiStatus == "20000000" {
                return successMessage
            }
            let apiMessage = http.value(forHTTPHeaderField: "X-Api-Message")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !apiMessage.isEmpty {
                return AppLocalization.format("Meeting ASR endpoint reachable. %@", apiMessage)
            }
            return successMessage
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
            logHTTPResponse(context: "Doubao handshake probe", response: http, data: data)
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
            logHTTPResponse(context: "Aliyun Qwen realtime handshake probe", response: http, data: data)
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

    private func buildDoubaoTestPacket(
        messageType: UInt8,
        messageFlags: UInt8,
        serialization: UInt8,
        compression: UInt8,
        sequence: Int32,
        payload: Data
    ) -> Data {
        var data = Data()
        data.append((0x1 << 4) | 0x1)
        data.append((messageType << 4) | messageFlags)
        data.append((serialization << 4) | compression)
        data.append(0x00)
        if messageFlags == 0x1 || messageFlags == 0x2 || messageFlags == 0x3 {
            withUnsafeBytes(of: sequence.bigEndian) { data.append(contentsOf: $0) }
        }
        var length = UInt32(payload.count).bigEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(payload)
        return data
    }

    private func parseDoubaoTestServerPacket(_ data: Data) throws -> (messageType: UInt8, hasText: Bool, isFinal: Bool, errorText: String?) {
        guard data.count >= 8 else {
            return (0, false, false, "Doubao server packet too short.")
        }

        let byte0 = data[0]
        let byte1 = data[1]
        let byte2 = data[2]
        let headerSizeWords = Int(byte0 & 0x0F)
        let headerSizeBytes = max(4, headerSizeWords * 4)
        let messageType = (byte1 >> 4) & 0x0F
        let messageFlags = byte1 & 0x0F
        let compression = byte2 & 0x0F

        var cursor = headerSizeBytes

        let hasSequence = (messageFlags & 0x1) != 0 || (messageFlags & 0x2) != 0
        var sequence: Int32?
        if hasSequence {
            guard data.count >= cursor + 4 else {
                return (messageType, false, false, "Invalid Doubao sequence header.")
            }
            let seqData = data.subdata(in: cursor..<(cursor + 4))
            let raw = seqData.reduce(UInt32(0)) { partial, byte in
                (partial << 8) | UInt32(byte)
            }
            sequence = Int32(bitPattern: raw)
            cursor += 4
        }

        guard data.count >= cursor + 4 else {
            return (messageType, false, false, "Invalid Doubao payload header.")
        }
        let payloadSizeData = data.subdata(in: cursor..<(cursor + 4))
        let payloadSize = payloadSizeData.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        cursor += 4
        guard data.count >= cursor + Int(payloadSize) else {
            return (messageType, false, false, "Invalid Doubao payload size.")
        }
        let payload = data.subdata(in: cursor..<(cursor + Int(payloadSize)))
        let decodedPayload: Data
        if compression == 0x1 {
            decodedPayload = try decodeDoubaoTestGzipPayload(payload)
        } else {
            decodedPayload = payload
        }
        if messageType == 0xF {
            let errorText = String(data: decodedPayload, encoding: .utf8) ?? "Doubao server returned an error packet."
            return (messageType, false, false, errorText)
        }

        guard let object = try? JSONSerialization.jsonObject(with: decodedPayload) else {
            return (messageType, false, (sequence ?? 1) < 0, nil)
        }

        let text = extractTextFromJSONObject(object)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let jsonSequence = extractSequence(in: object)
        let isFinal = (jsonSequence ?? sequence ?? 1) < 0
        return (messageType, !text.isEmpty, isFinal, nil)
    }

    private func normalizedDoubaoResourceID(_ model: String) -> String {
        DoubaoASRConfiguration.resolvedResourceID(model)
    }

    private func extractTextFromJSONObject(_ object: Any) -> String? {
        if let text = object as? String {
            return text
        }
        if let dict = object as? [String: Any] {
            let preferredKeys = ["text", "result_text", "utterance", "transcript", "result", "content"]
            for key in preferredKeys {
                if let value = dict[key], let text = extractTextFromJSONObject(value), !text.isEmpty {
                    return text
                }
            }
            for value in dict.values {
                if let text = extractTextFromJSONObject(value), !text.isEmpty {
                    return text
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let text = extractTextFromJSONObject(item), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func extractSequence(in object: Any) -> Int32? {
        if let value = object as? Int { return Int32(value) }
        if let value = object as? Int32 { return value }
        if let value = object as? Int64 { return Int32(value) }
        if let dict = object as? [String: Any] {
            if let seq = dict["sequence"] {
                return extractSequence(in: seq)
            }
            for nested in dict.values {
                if let seq = extractSequence(in: nested) {
                    return seq
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let seq = extractSequence(in: item) {
                    return seq
                }
            }
        }
        return nil
    }

    private func encodeDoubaoTestPacketPayload(
        _ payload: Data,
        preferGzip: Bool
    ) -> (compression: UInt8, payload: Data) {
        guard preferGzip, !payload.isEmpty else {
            return (0x0, payload)
        }

        do {
            return (0x1, try gzipCompressDoubaoTestPayload(payload))
        } catch {
            VoxtLog.warning("Doubao test gzip compression failed. fallback to plain payload. error=\(error.localizedDescription)")
            return (0x0, payload)
        }
    }

    private func gzipCompressDoubaoTestPayload(_ data: Data) throws -> Data {
        if data.isEmpty {
            return Data()
        }

        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }

            var stream = z_stream()
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input)
            stream.avail_in = uInt(data.count)

            let initStatus = deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                MAX_WBITS + 16,
                MAX_MEM_LEVEL,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else {
                throw NSError(domain: "Voxt.Settings", code: -122, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Doubao test GZIP compression."])
            }
            defer { deflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK
            repeat {
                var chunk = [UInt8](repeating: 0, count: 4096)
                let statusCode = chunk.withUnsafeMutableBufferPointer { buffer -> Int32 in
                    stream.next_out = buffer.baseAddress
                    stream.avail_out = uInt(buffer.count)
                    return deflate(&stream, Z_FINISH)
                }
                status = statusCode
                let produced = chunk.count - Int(stream.avail_out)
                if produced > 0 {
                    output.append(chunk, count: produced)
                }
            } while status == Z_OK

            guard status == Z_STREAM_END else {
                throw NSError(domain: "Voxt.Settings", code: -123, userInfo: [NSLocalizedDescriptionKey: "Failed to compress Doubao test payload with GZIP."])
            }

            return output
        }
    }

    private func decodeDoubaoTestGzipPayload(_ data: Data) throws -> Data {
        if data.isEmpty {
            return Data()
        }

        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }

            var stream = z_stream()
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input)
            stream.avail_in = uInt(data.count)

            let initStatus = inflateInit2_(
                &stream,
                MAX_WBITS + 16,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else {
                throw NSError(domain: "Voxt.Settings", code: -124, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Doubao test GZIP decompression."])
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK
            repeat {
                var chunk = [UInt8](repeating: 0, count: 4096)
                let statusCode = chunk.withUnsafeMutableBufferPointer { buffer -> Int32 in
                    stream.next_out = buffer.baseAddress
                    stream.avail_out = uInt(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                status = statusCode
                let produced = chunk.count - Int(stream.avail_out)
                if produced > 0 {
                    output.append(chunk, count: produced)
                }
            } while status == Z_OK

            guard status == Z_STREAM_END else {
                throw NSError(domain: "Voxt.Settings", code: -125, userInfo: [NSLocalizedDescriptionKey: "Failed to decompress Doubao test GZIP payload."])
            }

            return output
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

    private var testTargetLogName: String {
        switch testTarget {
        case .asr:
            return "asr"
        case .meetingASR:
            return "meeting-asr"
        case .llm:
            return "llm"
        }
    }

    private func sanitizedEndpointForLog(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<default>" : trimmed
    }

    private func logHTTPRequest(context: String, request: URLRequest, bodyPreview: String) {
        let method = request.httpMethod ?? "GET"
        let url = redactedURLString(request.url)
        let headers = redactedHeaders(request.allHTTPHeaderFields ?? [:])
        VoxtLog.info(
            "Network test request. context=\(context), method=\(method), url=\(url), headers=\(headers), body=\(truncateLogText(bodyPreview, limit: 700))",
            verbose: true
        )
    }

    private func logHTTPResponse(context: String, response: HTTPURLResponse, data: Data) {
        let url = redactedURLString(response.url)
        let headers = redactedHeaders(response.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
            partialResult[String(describing: pair.key)] = String(describing: pair.value)
        })
        let payload = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        VoxtLog.info(
            "Network test response. context=\(context), status=\(response.statusCode), url=\(url), headers=\(headers), body=\(truncateLogText(payload, limit: 700))",
            verbose: true
        )
    }

    private func redactedHeaders(_ headers: [String: String]) -> String {
        let redacted = headers.reduce(into: [String: String]()) { partialResult, pair in
            let key = pair.key
            let lower = key.lowercased()
            if lower == "authorization" || lower == "x-api-key" || lower.contains("token") {
                partialResult[key] = "<redacted>"
            } else {
                partialResult[key] = pair.value
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "\(redacted)"
    }

    private func redactedURLString(_ url: URL?) -> String {
        guard let url else { return "<nil>" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.map { item in
            let lower = item.name.lowercased()
            if lower == "key" || lower == "api_key" || lower.contains("token") {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return components.string ?? url.absoluteString
    }

    private func truncateLogText(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "...(truncated)"
    }

    private func isAliyunQwenRealtimeModel(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("qwen3-asr-flash-realtime")
    }
}

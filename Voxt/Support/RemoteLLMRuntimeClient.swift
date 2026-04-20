import Foundation
import CFNetwork

struct RemoteLLMRuntimeClient {
    nonisolated init() {}

    struct StreamingFailure: Error {
        let underlying: Error
        let partialText: String
        let emittedChunkCount: Int
    }

    private struct ResponsesStreamingResult {
        let text: String
        let responseID: String?
    }

    private enum CompletionIntent: Equatable {
        case enhancement
        case translation
        case rewrite
    }

    struct GenerationTuning {
        let maxTokens: Int
        let temperature: Double
        let topP: Double
    }

    private struct StreamingPartialDeliveryState {
        var lastPublishedAt = Date.distantPast
        var lastPublishedLength = 0

        mutating func shouldPublish(
            aggregatedText: String,
            force: Bool,
            minimumInterval: TimeInterval = 0.05,
            minimumCharacterDelta: Int = 96
        ) -> Bool {
            guard force else {
                let elapsed = Date().timeIntervalSince(lastPublishedAt)
                let appendedCount = aggregatedText.count - lastPublishedLength
                guard elapsed >= minimumInterval || appendedCount >= minimumCharacterDelta else {
                    return false
                }
                return true
            }
            return aggregatedText.count != lastPublishedLength
        }

        mutating func markPublished(aggregatedText: String) {
            lastPublishedAt = Date()
            lastPublishedLength = aggregatedText.count
        }
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
        if provider.usesResponsesAPI {
            let result = try await completeResponses(
                systemPrompt: systemPrompt,
                debugInput: text,
                requestContentForLog: prompt,
                inputPayload: prompt,
                inputTextLength: text.count,
                intent: .enhancement,
                provider: provider,
                configuration: configuration
            )
            let trimmed = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return trimmed.isEmpty ? text : trimmed
        }
        let output = try await complete(
            systemPrompt: systemPrompt,
            debugInput: text,
            userPrompt: prompt,
            inputTextLength: text.count,
            intent: .enhancement,
            provider: provider,
            configuration: configuration
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    func enhance(
        userPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        let input = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return "" }
        if provider.usesResponsesAPI {
            let result = try await completeResponses(
                systemPrompt: "",
                debugInput: input,
                requestContentForLog: input,
                inputPayload: input,
                inputTextLength: input.count,
                intent: .enhancement,
                provider: provider,
                configuration: configuration
            )
            return result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        let output = try await complete(
            systemPrompt: "",
            debugInput: input,
            userPrompt: input,
            inputTextLength: input.count,
            intent: .enhancement,
            provider: provider,
            configuration: configuration
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func dictionaryHistoryScanTerms(
        userPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> [String] {
        let input = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return [] }
        if provider.usesResponsesAPI {
            let result = try await completeResponses(
                systemPrompt: "",
                debugInput: input,
                requestContentForLog: input,
                inputPayload: input,
                inputTextLength: input.count,
                intent: .enhancement,
                provider: provider,
                configuration: configuration,
                textFormat: DictionaryHistoryScanResponseParser.responsesTextFormatPayload()
            )
            return try DictionaryHistoryScanResponseParser.parseTerms(from: result.text)
        }
        let output = try await complete(
            systemPrompt: "",
            debugInput: input,
            userPrompt: input,
            inputTextLength: input.count,
            intent: .enhancement,
            provider: provider,
            configuration: configuration
        )
        return try DictionaryHistoryScanResponseParser.parseTerms(from: output)
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
        if provider.usesResponsesAPI {
            let result = try await completeResponses(
                systemPrompt: systemPrompt,
                debugInput: text,
                requestContentForLog: prompt,
                inputPayload: prompt,
                inputTextLength: text.count,
                intent: .translation,
                provider: provider,
                configuration: configuration
            )
            let trimmed = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return trimmed.isEmpty ? text : trimmed
        }
        let output = try await complete(
            systemPrompt: systemPrompt,
            debugInput: text,
            userPrompt: prompt,
            inputTextLength: text.count,
            intent: .translation,
            provider: provider,
            configuration: configuration
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    func rewrite(
        sourceText: String,
        dictatedPrompt: String,
        systemPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration,
        conversationHistory: [RewriteConversationPromptTurn] = [],
        previousResponseID: String? = nil,
        onPartialText: (@Sendable (String) -> Void)? = nil,
        onResponseID: ((String) -> Void)? = nil
    ) async throws -> String {
        let prompt = """
        Produce the final text to insert according to the instructions.
        Spoken instruction:
        \(dictatedPrompt)

        Selected source text:
        \(sourceText)
        """

        if provider.usesResponsesAPI {
            let directAnswerMode = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let trimmedPreviousResponseID = previousResponseID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let inputPayload: Any
            let requestContentForLog: String

            if directAnswerMode {
                if !trimmedPreviousResponseID.isEmpty {
                    inputPayload = dictatedPrompt
                    requestContentForLog = dictatedPrompt
                } else if !conversationHistory.isEmpty {
                    inputPayload = responsesInputMessages(
                        currentUserInput: dictatedPrompt,
                        conversationHistory: conversationHistory
                    )
                    requestContentForLog = dictatedPrompt
                } else {
                    inputPayload = dictatedPrompt
                    requestContentForLog = dictatedPrompt
                }
            } else {
                inputPayload = prompt
                requestContentForLog = prompt
            }

            let result = try await completeResponses(
                systemPrompt: systemPrompt,
                debugInput: """
                Spoken instruction:
                \(dictatedPrompt)

                Selected source text:
                \(sourceText)
                """,
                requestContentForLog: requestContentForLog,
                inputPayload: inputPayload,
                inputTextLength: sourceText.count + dictatedPrompt.count,
                intent: .rewrite,
                provider: provider,
                configuration: configuration,
                previousResponseID: directAnswerMode ? previousResponseID : nil,
                onPartialText: onPartialText,
                onResponseID: onResponseID
            )
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? sourceText : trimmed
        }

        let shouldUseConversationMessages =
            sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !conversationHistory.isEmpty
        let userPrompt = shouldUseConversationMessages ? dictatedPrompt : prompt
        let output = try await complete(
            systemPrompt: systemPrompt,
            debugInput: """
            Spoken instruction:
            \(dictatedPrompt)

            Selected source text:
            \(sourceText)
            """,
            userPrompt: userPrompt,
            inputTextLength: sourceText.count + dictatedPrompt.count,
            intent: .rewrite,
            provider: provider,
            configuration: configuration,
            messagesOverride: shouldUseConversationMessages
                ? openAICompatibleConversationMessages(
                    systemPrompt: systemPrompt,
                    currentUserPrompt: dictatedPrompt,
                    conversationHistory: conversationHistory
                )
                : nil,
            onPartialText: onPartialText
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sourceText : trimmed
    }

    private func completeResponses(
        systemPrompt: String,
        debugInput: String,
        requestContentForLog: String,
        inputPayload: Any,
        inputTextLength: Int,
        intent: CompletionIntent,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration,
        previousResponseID: String? = nil,
        textFormat: [String: Any]? = nil,
        onPartialText: (@Sendable (String) -> Void)? = nil,
        onResponseID: ((String) -> Void)? = nil
    ) async throws -> ResponsesStreamingResult {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.suggestedModel
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointValue = responsesEndpointValue(provider: provider, endpoint: configuration.endpoint, model: model)
        let tuning = generationTuning(
            for: provider,
            inputTextLength: inputTextLength,
            systemPromptLength: systemPrompt.count,
            userPromptLength: requestContentForLog.count,
            intent: intent
        )
        let shouldAttemptStreaming = onPartialText != nil && supportsStreaming(provider: provider, intent: intent)

        if shouldAttemptStreaming, let onPartialText {
            do {
                let streamingRequest = try makeResponsesRequest(
                    provider: provider,
                    endpointValue: endpointValue,
                    model: model,
                    systemPrompt: systemPrompt,
                    inputPayload: inputPayload,
                    configuration: configuration,
                    previousResponseID: previousResponseID,
                    tuning: tuning,
                    textFormat: textFormat,
                    streamingEnabled: true
                )
                let requestStartedAt = Date()
                logRequest(
                    request: streamingRequest,
                    provider: provider,
                    endpointValue: endpointValue,
                    model: model,
                    inputTextLength: inputTextLength,
                    systemPrompt: systemPrompt,
                    debugInput: debugInput,
                    userPrompt: requestContentForLog,
                    tuning: tuning
                )
                return try await completeResponsesStreaming(
                    request: streamingRequest,
                    provider: provider,
                    endpointValue: endpointValue,
                    requestStartedAt: requestStartedAt,
                    onPartialText: onPartialText,
                    onResponseID: onResponseID
                )
            } catch let streamingFailure as StreamingFailure where streamingFailure.emittedChunkCount == 0 {
                VoxtLog.warning(
                    "Remote LLM Responses streaming unavailable, retrying non-streaming. provider=\(provider.rawValue), endpoint=\(endpointValue), detail=\(streamingFailure.underlying.localizedDescription)"
                )
            }
        }

        let request = try makeResponsesRequest(
            provider: provider,
            endpointValue: endpointValue,
            model: model,
            systemPrompt: systemPrompt,
            inputPayload: inputPayload,
            configuration: configuration,
            previousResponseID: previousResponseID,
            tuning: tuning,
            textFormat: textFormat,
            streamingEnabled: false
        )
        let requestStartedAt = Date()
        logRequest(
            request: request,
            provider: provider,
            endpointValue: endpointValue,
            model: model,
            inputTextLength: inputTextLength,
            systemPrompt: systemPrompt,
            debugInput: debugInput,
            userPrompt: requestContentForLog,
            tuning: tuning
        )

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

        if let dict = object as? [String: Any],
           let responseID = responsesResponseID(from: dict) {
            onResponseID?(responseID)
        }

        guard let content = extractPrimaryText(from: object), !content.isEmpty else {
            throw NSError(domain: "Voxt.RemoteLLM", code: -306, userInfo: [NSLocalizedDescriptionKey: "Remote LLM returned no text content."])
        }

        VoxtLog.llm(
            "Remote LLM Responses response received. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), bytes=\(data.count), networkMs=\(responseElapsedMs), decodeMs=\(decodeElapsedMs), totalMs=\(totalElapsedMs)"
        )
        VoxtLog.llm(
            """
            Remote LLM Responses content. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode)
            [output]
            \(VoxtLog.llmPreview(content))
            """
        )
        return ResponsesStreamingResult(
            text: content,
            responseID: (object as? [String: Any]).flatMap { responsesResponseID(from: $0) }
        )
    }

    private func completeResponsesStreaming(
        request: URLRequest,
        provider: RemoteLLMProvider,
        endpointValue: String,
        requestStartedAt: Date,
        onPartialText: @escaping (String) -> Void,
        onResponseID: ((String) -> Void)?
    ) async throws -> ResponsesStreamingResult {
        var aggregated = ""
        var responseID: String?
        var emittedChunkCount = 0
        var partialDeliveryState = StreamingPartialDeliveryState()

        do {
            let (bytes, response) = try await VoxtNetworkSession.active.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -305, userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM response."])
            }
            guard (200...299).contains(http.statusCode) else {
                throw NSError(
                    domain: "Voxt.RemoteLLM",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Remote LLM request failed (HTTP \(http.statusCode)) while opening stream."]
                )
            }

            var bufferedEventLines: [String] = []
            var sawEventStreamMarkers = false

            func publishAggregated(force: Bool = false) {
                guard partialDeliveryState.shouldPublish(aggregatedText: aggregated, force: force) else { return }
                partialDeliveryState.markPublished(aggregatedText: aggregated)
                onPartialText(aggregated)
            }

            func publish(_ chunkPayload: String) throws {
                let trimmed = chunkPayload.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "[DONE]" else { return }
                guard let data = trimmed.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }

                if let extractedResponseID = responsesResponseID(from: object) {
                    responseID = extractedResponseID
                    onResponseID?(extractedResponseID)
                }

                if let errorMessage = extractStreamingErrorMessage(from: object) ?? responsesErrorMessage(from: object) {
                    throw NSError(
                        domain: "Voxt.RemoteLLM",
                        code: -307,
                        userInfo: [NSLocalizedDescriptionKey: errorMessage]
                    )
                }

                if let delta = responsesStreamingDelta(from: object), !delta.isEmpty {
                    let eventType = object["type"] as? String
                    if eventType == "response.output_text.delta" {
                        aggregated.append(delta)
                    } else {
                        aggregated = mergedStreamingSnapshot(current: aggregated, next: delta)
                    }
                    emittedChunkCount += 1
                    publishAggregated()
                }
            }

            for try await line in bytes.lines {
                let trimmedLine = line.trimmingCharacters(in: .newlines)
                if trimmedLine.isEmpty {
                    if !bufferedEventLines.isEmpty {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                if trimmedLine.hasPrefix(":") {
                    continue
                }

                if trimmedLine.hasPrefix("event:") || trimmedLine.hasPrefix("id:") || trimmedLine.hasPrefix("retry:") {
                    sawEventStreamMarkers = true
                    continue
                }

                if trimmedLine.hasPrefix("data:") {
                    sawEventStreamMarkers = true
                    var payload = String(trimmedLine.dropFirst(5))
                    if payload.hasPrefix(" ") {
                        payload.removeFirst()
                    }
                    bufferedEventLines.append(payload)
                    if shouldFlushBufferedEventLines(bufferedEventLines) {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                if sawEventStreamMarkers {
                    bufferedEventLines.append(trimmedLine)
                    if shouldFlushBufferedEventLines(bufferedEventLines) {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                }
            }

            if !bufferedEventLines.isEmpty {
                try publish(bufferedEventLines.joined(separator: "\n"))
            }
            publishAggregated(force: true)

            let totalElapsedMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            VoxtLog.llm(
                "Remote LLM Responses streaming response received. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), chunks=\(emittedChunkCount), totalMs=\(totalElapsedMs), responseID=\(responseID ?? "nil")"
            )
            VoxtLog.llm(
                """
                Remote LLM Responses streaming content. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode)
                [output]
                \(VoxtLog.llmPreview(aggregated))
                """
            )
            return ResponsesStreamingResult(text: aggregated, responseID: responseID)
        } catch {
            throw StreamingFailure(
                underlying: error,
                partialText: aggregated,
                emittedChunkCount: emittedChunkCount
            )
        }
    }

    private func complete(
        systemPrompt: String,
        debugInput: String,
        userPrompt: String,
        inputTextLength: Int,
        intent: CompletionIntent,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration,
        messagesOverride: [[String: String]]? = nil,
        onPartialText: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.suggestedModel
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = resolvedLLMEndpoint(provider: provider, endpoint: configuration.endpoint, model: model)
        let endpoints = resolvedEndpointCandidates(provider: provider, primaryEndpoint: endpoint)
        var lastError: Error?
        let shouldAttemptStreaming = onPartialText != nil && supportsStreaming(provider: provider, intent: intent)

        for (index, endpointValue) in endpoints.enumerated() {
            let attemptStartedAt = Date()
            let tuning = generationTuning(
                for: provider,
                inputTextLength: inputTextLength,
                systemPromptLength: systemPrompt.count,
                userPromptLength: userPrompt.count,
                intent: intent
            )
            do {
                if shouldAttemptStreaming, let onPartialText {
                    do {
                        let streamingRequest = try makeCompletionRequest(
                            provider: provider,
                            configuration: configuration,
                            endpointValue: endpointValue,
                            model: model,
                            systemPrompt: systemPrompt,
                            userPrompt: userPrompt,
                            messagesOverride: messagesOverride,
                            tuning: tuning,
                            streamingEnabled: true
                        )
                        let requestStartedAt = Date()
                        logRequest(
                            request: streamingRequest,
                            provider: provider,
                            endpointValue: endpointValue,
                            model: model,
                            inputTextLength: inputTextLength,
                            systemPrompt: systemPrompt,
                            debugInput: debugInput,
                            userPrompt: userPrompt,
                            tuning: tuning
                        )
                        let streamed = try await completeStreaming(
                            request: streamingRequest,
                            provider: provider,
                            endpointValue: endpointValue,
                            requestStartedAt: requestStartedAt,
                            attempt: index + 1,
                            endpointCount: endpoints.count,
                            onPartialText: onPartialText
                        )
                        let trimmed = streamed.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            throw NSError(domain: "Voxt.RemoteLLM", code: -306, userInfo: [NSLocalizedDescriptionKey: "Remote LLM returned no text content."])
                        }
                        return trimmed
                    } catch let streamingFailure as StreamingFailure where streamingFailure.emittedChunkCount == 0 {
                        VoxtLog.warning(
                            "Remote LLM streaming unavailable, retrying non-streaming. provider=\(provider.rawValue), endpoint=\(endpointValue), attempt=\(index + 1)/\(endpoints.count), detail=\(streamingFailure.underlying.localizedDescription)"
                        )
                    } catch {
                        throw error
                    }
                }

                let request = try makeCompletionRequest(
                    provider: provider,
                    configuration: configuration,
                    endpointValue: endpointValue,
                    model: model,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    messagesOverride: messagesOverride,
                    tuning: tuning,
                    streamingEnabled: false
                )
                let requestStartedAt = Date()
                logRequest(
                    request: request,
                    provider: provider,
                    endpointValue: endpointValue,
                    model: model,
                    inputTextLength: inputTextLength,
                    systemPrompt: systemPrompt,
                    debugInput: debugInput,
                    userPrompt: userPrompt,
                    tuning: tuning
                )
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
                    VoxtLog.llm(
                        "Remote LLM response received. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), attempt=\(attempt)/\(endpoints.count), bytes=\(data.count), networkMs=\(responseElapsedMs), decodeMs=\(decodeElapsedMs), totalMs=\(totalElapsedMs)"
                    )
                    VoxtLog.llm(
                        """
                        Remote LLM response content. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode)
                        [output]
                        \(VoxtLog.llmPreview(content))
                        """
                    )
                    return content
                }

                VoxtLog.warning(
                    "Remote LLM response has no usable text. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), attempt=\(attempt)/\(endpoints.count), bytes=\(data.count), networkMs=\(responseElapsedMs), decodeMs=\(decodeElapsedMs), totalMs=\(totalElapsedMs)"
                )
                throw NSError(domain: "Voxt.RemoteLLM", code: -306, userInfo: [NSLocalizedDescriptionKey: "Remote LLM returned no text content."])
            } catch {
                lastError = error
                let elapsedMs = Int(Date().timeIntervalSince(attemptStartedAt) * 1000)
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
                let detail = networkErrorDetail(error: nsError)
                let attempt = index + 1
                let requestTimeout = requestTimeoutInterval(for: provider)
                let resolvedURL = URL(string: streamingEndpointValue(
                    provider: provider,
                    endpoint: endpointValue,
                    model: model,
                    streamingEnabled: shouldAttemptStreaming
                )) ?? URL(string: endpointValue)
                let proxyRoute = resolvedURL.map {
                    resolvedProxyRoute(for: $0, settings: VoxtNetworkSession.currentProxySettings)
                } ?? "unavailable"
                if isTimeout {
                    VoxtLog.warning("Remote LLM request timeout. provider=\(provider.rawValue), endpoint=\(endpointValue), attempt=\(attempt)/\(endpoints.count), elapsedMs=\(elapsedMs), timeoutSec=\(Int(requestTimeout)), proxy=\(proxyRoute), detail=\(detail)")
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

    private func makeCompletionRequest(
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration,
        endpointValue: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        messagesOverride: [[String: String]]? = nil,
        tuning: GenerationTuning,
        streamingEnabled: Bool
    ) throws -> URLRequest {
        let resolvedEndpoint = streamingEndpointValue(
            provider: provider,
            endpoint: endpointValue,
            model: model,
            streamingEnabled: streamingEnabled
        )
        guard let url = URL(string: resolvedEndpoint) else {
            throw NSError(
                domain: "Voxt.RemoteLLM",
                code: -300,
                userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM endpoint URL: \(resolvedEndpoint)"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeoutInterval(for: provider)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            streamingEnabled ? "text/event-stream, application/x-ndjson, application/json" : "application/json",
            forHTTPHeaderField: "Accept"
        )

        switch provider {
        case .anthropic:
            guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -301, userInfo: [NSLocalizedDescriptionKey: "Anthropic API key is empty."])
            }
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var payload: [String: Any] = [
                "model": model,
                "max_tokens": 2048,
                "stream": streamingEnabled,
                "messages": [
                    ["role": "user", "content": userPrompt]
                ]
            ]
            let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSystem.isEmpty {
                payload["system"] = systemPrompt
            }
            if configuration.searchEnabled && provider.supportsHostedSearch {
                payload["tools"] = [
                    [
                        "type": "web_search_20250305",
                        "name": "web_search",
                        "max_uses": 5
                    ]
                ]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        case .google:
            let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -302, userInfo: [NSLocalizedDescriptionKey: "Google API key is empty."])
            }
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -303, userInfo: [NSLocalizedDescriptionKey: "Invalid Google endpoint URL."])
            }
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "key" }) {
                items.append(URLQueryItem(name: "key", value: apiKey))
            }
            if streamingEnabled && !items.contains(where: { $0.name == "alt" }) {
                items.append(URLQueryItem(name: "alt", value: "sse"))
            }
            components.queryItems = items
            request.url = components.url
            var payload: [String: Any] = [
                "contents": [
                    ["parts": [["text": userPrompt]]]
                ]
            ]
            let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSystem.isEmpty {
                payload["system_instruction"] = ["parts": [["text": systemPrompt]]]
            }
            if configuration.searchEnabled && provider.supportsHostedSearch {
                payload["tools"] = [googleSearchToolPayload(for: model)]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        case .minimax:
            let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -304, userInfo: [NSLocalizedDescriptionKey: "MiniMax API key is empty."])
            }
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "stream": streamingEnabled,
                "messages": openAICompatibleMessages(systemPrompt: systemPrompt, userPrompt: userPrompt)
            ])
        case .ollama where usesNativeOllamaChatEndpoint(url):
            let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "messages": openAICompatibleMessages(systemPrompt: systemPrompt, userPrompt: userPrompt),
                "stream": streamingEnabled,
                "options": [
                    "temperature": tuning.temperature,
                    "top_p": tuning.topP,
                    "num_predict": tuning.maxTokens
                ]
            ])
        default:
            let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            var payload: [String: Any] = [
                "model": model,
                "messages": messagesOverride ?? openAICompatibleMessages(systemPrompt: systemPrompt, userPrompt: userPrompt),
                "stream": streamingEnabled,
                "max_tokens": tuning.maxTokens,
                "temperature": tuning.temperature,
                "top_p": tuning.topP
            ]
            applyOpenAICompatibleSearchConfiguration(
                to: &payload,
                provider: provider,
                configuration: configuration
            )
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        return request
    }

    private func logRequest(
        request: URLRequest,
        provider: RemoteLLMProvider,
        endpointValue: String,
        model: String,
        inputTextLength: Int,
        systemPrompt: String,
        debugInput: String,
        userPrompt: String,
        tuning: GenerationTuning
    ) {
        let proxySettings = VoxtNetworkSession.currentProxySettings
        let proxyRoute = request.url.map { resolvedProxyRoute(for: $0, settings: proxySettings) } ?? "unavailable"
        let networkMode = VoxtNetworkSession.modeDescription
        VoxtLog.llm(
            "Remote LLM request started. provider=\(provider.rawValue), endpoint=\(endpointValue), url=\(request.url?.absoluteString ?? endpointValue), model=\(model), timeoutSec=\(Int(request.timeoutInterval)), inputChars=\(inputTextLength), systemChars=\(systemPrompt.count), userChars=\(userPrompt.count), maxTokens=\(tuning.maxTokens), temp=\(tuning.temperature), topP=\(tuning.topP), networkMode=\(networkMode), proxy=\(proxyRoute)"
        )
        VoxtLog.llm(
            """
            Remote LLM request content. provider=\(provider.rawValue), endpoint=\(endpointValue), model=\(model)
            [system_prompt]
            \(VoxtLog.llmPreview(systemPrompt))
            [input]
            \(VoxtLog.llmPreview(debugInput))
            [request_content]
            \(VoxtLog.llmPreview(userPrompt))
            """
        )
    }

    private func completeStreaming(
        request: URLRequest,
        provider: RemoteLLMProvider,
        endpointValue: String,
        requestStartedAt: Date,
        attempt: Int,
        endpointCount: Int,
        onPartialText: @Sendable (String) -> Void
    ) async throws -> String {
        var aggregated = ""
        var emittedChunkCount = 0
        var partialDeliveryState = StreamingPartialDeliveryState()
        do {
            let (bytes, response) = try await VoxtNetworkSession.active.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -305, userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM response."])
            }
            guard (200...299).contains(http.statusCode) else {
                throw NSError(
                    domain: "Voxt.RemoteLLM",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Remote LLM request failed (HTTP \(http.statusCode)) while opening stream."]
                )
            }

            var bufferedEventLines: [String] = []
            var sawEventStreamMarkers = false
            var nonEventStreamBuffer = ""

            func publishAggregated(force: Bool = false) {
                guard partialDeliveryState.shouldPublish(aggregatedText: aggregated, force: force) else { return }
                partialDeliveryState.markPublished(aggregatedText: aggregated)
                onPartialText(aggregated)
            }

            func publish(_ chunkPayload: String) throws {
                let trimmed = chunkPayload.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "[DONE]" else { return }

                if let data = trimmed.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) {
                    if let errorMessage = extractStreamingErrorMessage(from: object) {
                        throw NSError(
                            domain: "Voxt.RemoteLLM",
                            code: -307,
                            userInfo: [NSLocalizedDescriptionKey: errorMessage]
                        )
                    }
                    if let delta = extractStreamingDelta(from: object), !delta.isEmpty {
                        aggregated.append(delta)
                    } else if let snapshot = extractPrimaryText(from: object), !snapshot.isEmpty {
                        aggregated = mergedStreamingSnapshot(current: aggregated, next: snapshot)
                    } else {
                        return
                    }
                } else if let recovered = recoverStreamingDelta(fromRawPayload: trimmed), !recovered.isEmpty {
                    aggregated.append(recovered)
                } else if looksLikeStreamingEnvelopeFragment(trimmed) {
                    return
                } else {
                    aggregated = mergedStreamingSnapshot(current: aggregated, next: trimmed)
                }

                emittedChunkCount += 1
                publishAggregated()
            }

            for try await line in bytes.lines {
                let trimmedLine = line.trimmingCharacters(in: .newlines)
                if trimmedLine.isEmpty {
                    if !bufferedEventLines.isEmpty {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                if trimmedLine.hasPrefix(":") {
                    continue
                }

                if trimmedLine.hasPrefix("event:") || trimmedLine.hasPrefix("id:") || trimmedLine.hasPrefix("retry:") {
                    sawEventStreamMarkers = true
                    continue
                }

                if trimmedLine.hasPrefix("data:") {
                    sawEventStreamMarkers = true
                    var payload = String(trimmedLine.dropFirst(5))
                    if payload.hasPrefix(" ") {
                        payload.removeFirst()
                    }
                    bufferedEventLines.append(payload)
                    if shouldFlushBufferedEventLines(bufferedEventLines) {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                if sawEventStreamMarkers {
                    bufferedEventLines.append(trimmedLine)
                    if shouldFlushBufferedEventLines(bufferedEventLines) {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                } else {
                    nonEventStreamBuffer.append(line)
                    nonEventStreamBuffer.append("\n")
                    let payloads = drainNonEventStreamPayloads(buffer: &nonEventStreamBuffer)
                    for payload in payloads {
                        try publish(payload)
                    }
                }
            }

            if !bufferedEventLines.isEmpty {
                try publish(bufferedEventLines.joined(separator: "\n"))
            }
            let trailingPayloads = drainNonEventStreamPayloads(buffer: &nonEventStreamBuffer)
            for payload in trailingPayloads {
                try publish(payload)
            }
            let trailingText = nonEventStreamBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trailingText.isEmpty {
                try publish(trailingText)
            }
            publishAggregated(force: true)

            let totalElapsedMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            VoxtLog.llm(
                "Remote LLM streaming response received. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), attempt=\(attempt)/\(endpointCount), chunks=\(emittedChunkCount), totalMs=\(totalElapsedMs)"
            )
            VoxtLog.llm(
                """
                Remote LLM streaming content. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode)
                [output]
                \(VoxtLog.llmPreview(aggregated))
                """
            )
            return aggregated
        } catch {
            throw StreamingFailure(
                underlying: error,
                partialText: aggregated,
                emittedChunkCount: emittedChunkCount
            )
        }
    }

    private func supportsStreaming(provider: RemoteLLMProvider, intent: CompletionIntent) -> Bool {
        guard intent == .rewrite else { return false }
        return true
    }

    func requestTimeoutInterval(for provider: RemoteLLMProvider) -> TimeInterval {
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
        let baseMultiplier: Double
        let minimumBudget: Int
        let maximumBudget: Int

        switch intent {
        case .translation:
            baseMultiplier = 1.35
            minimumBudget = 128
            maximumBudget = 1024
        case .rewrite:
            // Rewrite often needs to synthesize a fresh answer from a short spoken
            // instruction, so the budget cannot track prompt length too closely.
            baseMultiplier = safeInput < 180 ? 2.6 : 1.4
            minimumBudget = safeInput < 180 ? 384 : 256
            maximumBudget = 1536
        case .enhancement:
            baseMultiplier = 1.15
            minimumBudget = 128
            maximumBudget = 1024
        }

        let contentEstimate = Int(Double(safeInput) * baseMultiplier)
        let instructionReserve = min(intent == .rewrite ? 256 : 192, max(32, instructionChars / 12))
        let estimate = contentEstimate + instructionReserve
        return max(minimumBudget, min(estimate, maximumBudget))
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

}

import XCTest
@testable import Voxt

final class RemoteLLMRuntimeClientStreamingTests: XCTestCase {
    func testResolvedLLMEndpointNormalizesAliyunResponsesEndpoints() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .aliyunBailian,
                endpoint: "",
                model: "qwen-plus"
            ),
            "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .aliyunBailian,
                endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/models",
                model: "qwen-plus"
            ),
            "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .aliyunBailian,
                endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                model: "qwen-plus"
            ),
            "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"
        )
    }

    func testResolvedLLMEndpointNormalizesVolcengineResponsesEndpoints() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .volcengine,
                endpoint: "",
                model: "doubao-1-5-pro"
            ),
            "https://ark.cn-beijing.volces.com/api/v3/responses"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .volcengine,
                endpoint: "https://ark.cn-beijing.volces.com/api/v3/models",
                model: "doubao-1-5-pro"
            ),
            "https://ark.cn-beijing.volces.com/api/v3/responses"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .volcengine,
                endpoint: "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
                model: "doubao-1-5-pro"
            ),
            "https://ark.cn-beijing.volces.com/api/v3/responses"
        )
    }

    func testStreamingEndpointValueBuildsGoogleStreamEndpoint() {
        let client = RemoteLLMRuntimeClient()

        let endpoint = client.streamingEndpointValue(
            provider: .google,
            endpoint: "https://generativelanguage.googleapis.com/v1beta/models",
            model: "gemini-2.5-pro",
            streamingEnabled: true
        )

        XCTAssertEqual(
            endpoint,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:streamGenerateContent"
        )
    }

    func testStreamingEndpointValueBuildsOpenAIResponsesEndpoint() {
        let client = RemoteLLMRuntimeClient()

        let endpoint = client.streamingEndpointValue(
            provider: .openAI,
            endpoint: "https://api.openai.com/v1/chat/completions",
            model: "gpt-5.2",
            streamingEnabled: true
        )

        XCTAssertEqual(endpoint, "https://api.openai.com/v1/responses")
    }

    func testOpenAIResolvedEndpointDefaultsToResponsesAPI() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .openAI,
                endpoint: "",
                model: "gpt-5.2"
            ),
            "https://api.openai.com/v1/responses"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .openAI,
                endpoint: "https://api.openai.com",
                model: "gpt-5.2"
            ),
            "https://api.openai.com/v1/responses"
        )
    }

    func testResolvedLLMEndpointBuildsDeepSeekChatCompletionsFromOfficialBaseURL() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .deepseek,
                endpoint: "",
                model: "deepseek-v4-flash"
            ),
            "https://api.deepseek.com/v1/chat/completions"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .deepseek,
                endpoint: "https://api.deepseek.com",
                model: "deepseek-v4-flash"
            ),
            "https://api.deepseek.com/v1/chat/completions"
        )
    }

    func testResolvedLLMEndpointDefaultsOllamaToBaseEndpoint() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertEqual(
            client.providerDefaultEndpoint(.ollama),
            "http://localhost:11434"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .ollama,
                endpoint: "",
                model: "qwen3"
            ),
            "http://localhost:11434"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .ollama,
                endpoint: "http://localhost:11434/api",
                model: "qwen3"
            ),
            "http://localhost:11434"
        )
    }

    func testResolvedLLMEndpointBuildsOMLXChatCompletionsFromBaseURL() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertEqual(
            client.providerDefaultEndpoint(.omlx),
            "http://localhost:8000/v1"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .omlx,
                endpoint: "",
                model: "qwen3"
            ),
            "http://localhost:8000/v1/chat/completions"
        )
        XCTAssertEqual(
            client.resolvedLLMEndpoint(
                provider: .omlx,
                endpoint: "http://localhost:8000/v1/models",
                model: "qwen3"
            ),
            "http://localhost:8000/v1/chat/completions"
        )
    }

    func testResolvedOllamaRequestEndpointSelectsNativeRouteFromBaseEndpoint() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertEqual(
            client.resolvedOllamaRequestEndpoint(
                endpoint: "http://localhost:11434",
                useGenerate: true
            ),
            "http://localhost:11434/api/generate"
        )
        XCTAssertEqual(
            client.resolvedOllamaRequestEndpoint(
                endpoint: "http://localhost:11434",
                useGenerate: false
            ),
            "http://localhost:11434/api/chat"
        )
    }

    func testExtractStreamingDeltaParsesAnthropicTextDelta() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "type": "content_block_delta",
            "delta": [
                "type": "text_delta",
                "text": "你好"
            ]
        ]

        XCTAssertEqual(client.extractStreamingDelta(from: payload), "你好")
    }

    func testExtractStreamingDeltaParsesOpenAIChoiceDelta() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "choices": [
                [
                    "delta": [
                        "content": " world"
                    ]
                ]
            ]
        ]

        XCTAssertEqual(client.extractStreamingDelta(from: payload), " world")
    }

    func testExtractStreamingDeltaParsesOllamaNativeMessageContent() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "message": [
                "role": "assistant",
                "content": "本地流式输出"
            ],
            "done": false
        ]

        XCTAssertEqual(client.extractStreamingDelta(from: payload), "本地流式输出")
    }

    func testExtractStreamingDeltaParsesOllamaGenerateResponse() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "response": "本地生成增量",
            "done": false
        ]

        XCTAssertEqual(client.extractStreamingDelta(from: payload), "本地生成增量")
    }

    func testExtractPrimaryTextParsesOllamaNativeResponse() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "message": [
                "role": "assistant",
                "content": "这是最终回复"
            ],
            "done": true
        ]

        XCTAssertEqual(client.extractPrimaryText(from: payload), "这是最终回复")
    }

    func testExtractPrimaryTextParsesOpenAICompatibleMessageStringContent() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "这是 OpenAI 兼容返回"
                    ]
                ]
            ]
        ]

        XCTAssertEqual(client.extractPrimaryText(from: payload), "这是 OpenAI 兼容返回")
    }

    func testExtractPrimaryTextParsesOpenAICompatibleMessageArrayContent() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": [
                            [
                                "type": "text",
                                "text": "这是数组 content 返回"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        XCTAssertEqual(client.extractPrimaryText(from: payload), "这是数组 content 返回")
    }

    func testExtractPrimaryTextParsesGeminiCandidatesParts() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            [
                                "text": "这是 Gemini parts 返回"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        XCTAssertEqual(client.extractPrimaryText(from: payload), "这是 Gemini parts 返回")
    }

    func testShouldFlushBufferedEventLinesRecognizesSingleChunkJSONWithoutBlankSeparator() {
        let client = RemoteLLMRuntimeClient()
        let bufferedEventLines = [
            #"{"choices":[{"delta":{"content":"大"},"index":0}]}"#
        ]

        XCTAssertTrue(client.shouldFlushBufferedEventLines(bufferedEventLines))
    }

    func testShouldFlushBufferedEventLinesRecognizesDoneMarkerWithoutBlankSeparator() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertTrue(client.shouldFlushBufferedEventLines(["[DONE]"]))
    }

    func testExtractStreamingDeltaParsesDashScopeChunkPayload() throws {
        let client = RemoteLLMRuntimeClient()
        let raw = #"{"choices":[{"delta":{"content":"大同市的经纬度约为：北纬39.98°，东经113.30°。"},"index":0,"logprobs":null,"finish_reason":null}],"object":"chat.completion.chunk","usage":null,"created":1775896175,"system_fingerprint":null,"model":"qwen-plus-latest","id":"chatcmpl-920daaa7-d5a8-9df8-a704-8078ff684102"}"#
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])

        XCTAssertEqual(
            client.extractStreamingDelta(from: object),
            "大同市的经纬度约为：北纬39.98°，东经113.30°。"
        )
    }

    func testExtractStreamingDeltaParsesResponsesDeltaEvent() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "type": "response.output_text.delta",
            "delta": "山西大同"
        ]

        XCTAssertEqual(client.extractStreamingDelta(from: payload), "山西大同")
    }

    func testExtractPrimaryTextParsesResponsesOutputArray() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "output": [
                [
                    "content": [
                        [
                            "type": "output_text",
                            "text": "北纬 40.076，东经 113.300"
                        ]
                    ]
                ]
            ]
        ]

        XCTAssertEqual(client.extractPrimaryText(from: payload), "北纬 40.076，东经 113.300")
    }

    func testExtractPrimaryTextParsesResponsesOutputArrayWithStringContent() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "output": [
                [
                    "type": "message",
                    "content": "这是百炼返回的字符串内容"
                ]
            ]
        ]

        XCTAssertEqual(client.extractPrimaryText(from: payload), "这是百炼返回的字符串内容")
    }

    func testExtractPrimaryTextParsesResponsesOutputArrayWithNestedTextValue() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "output": [
                [
                    "type": "message",
                    "content": [
                        [
                            "type": "output_text",
                            "text": [
                                "value": "这是嵌套 text.value 返回"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        XCTAssertEqual(client.extractPrimaryText(from: payload), "这是嵌套 text.value 返回")
    }

    func testExtractPrimaryTextParsesResponsesOutputArrayWithMixedToolAndMessageItems() {
        let client = RemoteLLMRuntimeClient()
        let payload: [String: Any] = [
            "output": [
                [
                    "type": "web_search_call",
                    "output": "{\"ok\":true}"
                ],
                [
                    "type": "message",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "这是最终增强文本"
                        ]
                    ]
                ]
            ]
        ]

        XCTAssertEqual(client.extractPrimaryText(from: payload), "这是最终增强文本")
    }

    func testResponsesInputMessagesBuildsConversationHistoryAndCurrentTurn() {
        let client = RemoteLLMRuntimeClient()
        let input = client.responsesInputMessages(
            currentUserInput: "看一下大同的经纬度。",
            conversationHistory: [
                RewriteConversationPromptTurn(
                    userPromptText: "",
                    resultTitle: "大同天气查询",
                    resultContent: "请查看最新天气预报应用或网站获取大同实时天气信息。"
                )
            ]
        )

        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input.first?["role"] as? String, "assistant")
        XCTAssertEqual(input.last?["role"] as? String, "user")
        XCTAssertEqual(input.last?["content"] as? String, "看一下大同的经纬度。")
    }

    func testResponsesResponseIDParsesNestedAndTopLevelForms() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertEqual(
            client.responsesResponseID(
                from: [
                    "response": [
                        "id": "resp_nested"
                    ]
                ]
            ),
            "resp_nested"
        )
        XCTAssertEqual(
            client.responsesResponseID(
                from: [
                    "response_id": "resp_top_level"
                ]
            ),
            "resp_top_level"
        )
    }

    func testMakeResponsesRequestBuildsSingleTurnAliyunPayload() throws {
        let client = RemoteLLMRuntimeClient()
        let request = try client.makeResponsesRequest(
            provider: .aliyunBailian,
            endpointValue: "https://dashscope.aliyuncs.com/compatible-mode/v1/responses",
            model: "qwen-plus",
            systemPrompt: "你是助手",
            inputPayload: "山西大同的经纬度是什么？",
            configuration: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.aliyunBailian.rawValue,
                model: "qwen-plus",
                endpoint: "",
                apiKey: "test-key",
                searchEnabled: true
            ),
            previousResponseID: nil,
            tuning: .init(maxTokens: 512, temperature: 0.2, topP: 0.9),
            textFormat: nil,
            streamingEnabled: true
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(object["instructions"] as? String, "你是助手")
        XCTAssertEqual(object["input"] as? String, "山西大同的经纬度是什么？")
        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "web_search")
    }

    func testMakeResponsesRequestBuildsContinuePayloadWithPreviousResponseID() throws {
        let client = RemoteLLMRuntimeClient()
        let request = try client.makeResponsesRequest(
            provider: .volcengine,
            endpointValue: "https://ark.cn-beijing.volces.com/api/v3/responses",
            model: "doubao-1-5-pro",
            systemPrompt: "",
            inputPayload: "继续",
            configuration: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.volcengine.rawValue,
                model: "doubao-1-5-pro",
                endpoint: "",
                apiKey: "test-key",
                searchEnabled: true
            ),
            previousResponseID: "resp_123",
            tuning: .init(maxTokens: 256, temperature: 0.1, topP: 0.8),
            textFormat: nil,
            streamingEnabled: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(object["previous_response_id"] as? String, "resp_123")
        XCTAssertEqual(object["input"] as? String, "继续")
        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "web_search")
    }

    func testMakeResponsesRequestAppliesOpenAIOptions() throws {
        let client = RemoteLLMRuntimeClient()
        let request = try client.makeResponsesRequest(
            provider: .openAI,
            endpointValue: "https://api.openai.com/v1/responses",
            model: "gpt-5.2",
            systemPrompt: "",
            inputPayload: "ping",
            configuration: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "",
                apiKey: "test-key",
                openAIReasoningEffort: OpenAIReasoningEffort.high.rawValue,
                openAITextVerbosity: OpenAITextVerbosity.low.rawValue,
                openAIMaxOutputTokens: 2048
            ),
            previousResponseID: nil,
            tuning: .init(maxTokens: 512, temperature: 0.2, topP: 0.9),
            textFormat: [
                "format": [
                    "type": "json_object"
                ]
            ],
            streamingEnabled: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let reasoning = try XCTUnwrap(object["reasoning"] as? [String: Any])
        let text = try XCTUnwrap(object["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])

        XCTAssertEqual(object["max_output_tokens"] as? Int, 2048)
        XCTAssertNil(object["temperature"])
        XCTAssertNil(object["top_p"])
        XCTAssertEqual(reasoning["effort"] as? String, "high")
        XCTAssertEqual(text["verbosity"] as? String, "low")
        XCTAssertEqual(format["type"] as? String, "json_object")
    }

    func testMakeResponsesRequestUsesJSONAcceptHeaderWhenNonStreaming() throws {
        let client = RemoteLLMRuntimeClient()
        let request = try client.makeResponsesRequest(
            provider: .openAI,
            endpointValue: "https://api.openai.com/v1/responses",
            model: "gpt-5.2",
            systemPrompt: "",
            inputPayload: "ping",
            configuration: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "",
                apiKey: "test-key"
            ),
            previousResponseID: nil,
            tuning: .init(maxTokens: 512, temperature: 0.2, topP: 0.9),
            textFormat: nil,
            streamingEnabled: false
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testMakeResponsesRequestUsesEventStreamAcceptHeaderWhenStreaming() throws {
        let client = RemoteLLMRuntimeClient()
        let request = try client.makeResponsesRequest(
            provider: .openAI,
            endpointValue: "https://api.openai.com/v1/responses",
            model: "gpt-5.2",
            systemPrompt: "",
            inputPayload: "ping",
            configuration: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "",
                apiKey: "test-key"
            ),
            previousResponseID: nil,
            tuning: .init(maxTokens: 512, temperature: 0.2, topP: 0.9),
            textFormat: nil,
            streamingEnabled: true
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream, application/json")
    }

    func testDecodeResponsesObjectAcceptsJSONResponseObject() throws {
        let client = RemoteLLMRuntimeClient()
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        let body = #"{"id":"resp_123","output_text":"优化后的文本"}"#

        XCTAssertEqual(
            try client.decodeResponsesObject(from: Data(body.utf8), response: response)["output_text"] as? String,
            "优化后的文本"
        )
    }

    func testDecodeResponsesObjectRejectsHTMLGatewayPage() throws {
        let client = RemoteLLMRuntimeClient()
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        ))
        let body = """
        <!doctype html>
        <html><head><title>AI API Gateway</title></head><body></body></html>
        """

        XCTAssertThrowsError(
            try client.decodeResponsesObject(from: Data(body.utf8), response: response)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("returned HTML instead of JSON"))
        }
    }

    func testDecodeResponsesObjectRejectsEventStreamForNonStreamingResponse() throws {
        let client = RemoteLLMRuntimeClient()
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        ))
        let body = #"data: {"type":"response.output_text.delta","delta":"你好"}"#

        XCTAssertThrowsError(
            try client.decodeResponsesObject(from: Data(body.utf8), response: response)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("event stream for a non-streaming request"))
        }
    }

    func testMakeResponsesRequestFiltersOpenAIOptionsByModelFamily() throws {
        let client = RemoteLLMRuntimeClient()
        let request = try client.makeResponsesRequest(
            provider: .openAI,
            endpointValue: "https://api.openai.com/v1/responses",
            model: "gpt-5",
            systemPrompt: "",
            inputPayload: "ping",
            configuration: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5",
                endpoint: "",
                apiKey: "test-key",
                openAIReasoningEffort: OpenAIReasoningEffort.none.rawValue,
                openAITextVerbosity: OpenAITextVerbosity.high.rawValue
            ),
            previousResponseID: nil,
            tuning: .init(maxTokens: 512, temperature: 0.2, topP: 0.9),
            textFormat: nil,
            streamingEnabled: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let text = try XCTUnwrap(object["text"] as? [String: Any])

        XCTAssertNil(object["reasoning"])
        XCTAssertEqual(text["verbosity"] as? String, "high")
    }

    func testMakeResponsesRequestOmitsOpenAIModelOptionsForNonSupportingModel() throws {
        let client = RemoteLLMRuntimeClient()
        let request = try client.makeResponsesRequest(
            provider: .openAI,
            endpointValue: "https://api.openai.com/v1/responses",
            model: "gpt-4o",
            systemPrompt: "",
            inputPayload: "ping",
            configuration: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-4o",
                endpoint: "",
                apiKey: "test-key",
                openAIReasoningEffort: OpenAIReasoningEffort.high.rawValue,
                openAITextVerbosity: OpenAITextVerbosity.low.rawValue
            ),
            previousResponseID: nil,
            tuning: .init(maxTokens: 512, temperature: 0.2, topP: 0.9),
            textFormat: nil,
            streamingEnabled: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertNil(object["temperature"])
        XCTAssertNil(object["top_p"])
        XCTAssertNil(object["reasoning"])
        XCTAssertNil(object["text"])
    }

    func testMakeResponsesRequestDoesNotApplyOpenAIOptionsToCompatibleProviders() throws {
        let client = RemoteLLMRuntimeClient()
        let request = try client.makeResponsesRequest(
            provider: .aliyunBailian,
            endpointValue: "https://dashscope.aliyuncs.com/compatible-mode/v1/responses",
            model: "qwen-plus",
            systemPrompt: "",
            inputPayload: "ping",
            configuration: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.aliyunBailian.rawValue,
                model: "qwen-plus",
                endpoint: "",
                apiKey: "test-key",
                openAIReasoningEffort: OpenAIReasoningEffort.high.rawValue,
                openAITextVerbosity: OpenAITextVerbosity.low.rawValue,
                openAIMaxOutputTokens: 2048
            ),
            previousResponseID: nil,
            tuning: .init(maxTokens: 512, temperature: 0.2, topP: 0.9),
            textFormat: nil,
            streamingEnabled: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(object["max_output_tokens"] as? Int, 512)
        XCTAssertEqual(object["temperature"] as? Double, 0.2)
        XCTAssertEqual(object["top_p"] as? Double, 0.9)
        XCTAssertNil(object["reasoning"])
        XCTAssertNil(object["text"])
    }

    func testOpenAICompatiblePayloadOmitsResponseFormatByDefault() {
        let client = RemoteLLMRuntimeClient()

        let payload = client.openAICompatiblePayload(
            model: "deepseek-v4-flash",
            systemPrompt: "你是助手",
            userPrompt: "你好",
            tuning: .init(maxTokens: 256, temperature: 0.2, topP: 0.9),
            streamingEnabled: false
        )

        XCTAssertNil(payload["response_format"])
    }

    func testOpenAICompatiblePayloadAddsJSONModeWhenRequested() throws {
        let client = RemoteLLMRuntimeClient()

        let payload = client.openAICompatiblePayload(
            model: "deepseek-v4-flash",
            systemPrompt: "返回 JSON",
            userPrompt: "生成结构化结果",
            tuning: .init(maxTokens: 256, temperature: 0.2, topP: 0.9),
            streamingEnabled: true,
            responseFormat: .jsonObject
        )

        let responseFormat = try XCTUnwrap(payload["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_object")
        XCTAssertEqual(payload["stream"] as? Bool, true)
    }

    func testOllamaNativePayloadIncludesConfiguredFields() throws {
        let client = RemoteLLMRuntimeClient()

        let payload = try client.ollamaNativePayload(
            model: "qwen3",
            systemPrompt: "你是助手",
            userPrompt: "你好",
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3",
                ollamaResponseFormat: OllamaResponseFormat.json.rawValue,
                ollamaThinkMode: OllamaThinkMode.medium.rawValue,
                ollamaKeepAlive: "10m",
                ollamaLogprobsEnabled: true,
                ollamaTopLogprobs: 3,
                ollamaOptionsJSON: #"{"temperature":0.7,"repeat_penalty":1.1}"#
            ),
            tuning: .init(maxTokens: 256, temperature: 0.2, topP: 0.9),
            streamingEnabled: true
        )

        XCTAssertEqual(payload["format"] as? String, "json")
        XCTAssertEqual(payload["think"] as? String, "medium")
        XCTAssertEqual(payload["keep_alive"] as? String, "10m")
        XCTAssertEqual(payload["logprobs"] as? Bool, true)
        XCTAssertEqual(payload["top_logprobs"] as? Int, 3)

        let options = try XCTUnwrap(payload["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Double, 0.7)
        XCTAssertEqual(options["top_p"] as? Double, 0.9)
        XCTAssertEqual(options["num_predict"] as? Int, 256)
        XCTAssertEqual(options["repeat_penalty"] as? Double, 1.1)
    }

    func testOllamaGeneratePayloadUsesPromptAndSystemFields() throws {
        let client = RemoteLLMRuntimeClient()

        let payload = try client.ollamaNativePayload(
            endpointURL: URL(string: "http://localhost:11434/api/generate"),
            model: "qwen3",
            systemPrompt: "你是助手",
            userPrompt: "你好",
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3",
                ollamaThinkMode: OllamaThinkMode.on.rawValue
            ),
            tuning: .init(maxTokens: 128, temperature: 0.2, topP: 0.9),
            streamingEnabled: true
        )

        XCTAssertEqual(payload["prompt"] as? String, "你好")
        XCTAssertEqual(payload["system"] as? String, "你是助手")
        XCTAssertNil(payload["messages"])
        XCTAssertEqual(payload["think"] as? Bool, true)
    }

    func testOllamaGeneratePayloadFlattensConversationMessagesIntoPrompt() throws {
        let client = RemoteLLMRuntimeClient()

        let payload = try client.ollamaNativePayload(
            endpointURL: URL(string: "http://localhost:11434/api/generate"),
            model: "qwen3",
            systemPrompt: "",
            userPrompt: "继续",
            messagesOverride: [
                ["role": "system", "content": "你是助手"],
                ["role": "user", "content": "第一问"],
                ["role": "assistant", "content": "第一答"],
                ["role": "user", "content": "继续"]
            ],
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3"
            ),
            tuning: .init(maxTokens: 128, temperature: 0.2, topP: 0.9),
            streamingEnabled: false
        )

        XCTAssertEqual(payload["system"] as? String, "你是助手")
        XCTAssertEqual(
            payload["prompt"] as? String,
            """
            User:
            第一问

            Assistant:
            第一答

            User:
            继续
            """
        )
    }

    func testResolvedOllamaRequestEndpointPreservesExplicitNativeAndCompatibleEndpoints() {
        let client = RemoteLLMRuntimeClient()

        XCTAssertEqual(
            client.resolvedOllamaRequestEndpoint(
                endpoint: "http://localhost:11434/api/chat",
                useGenerate: true
            ),
            "http://localhost:11434/api/chat"
        )
        XCTAssertEqual(
            client.resolvedOllamaRequestEndpoint(
                endpoint: "http://localhost:11434/v1/chat/completions",
                useGenerate: true
            ),
            "http://localhost:11434/v1/chat/completions"
        )
    }

    func testOllamaNativePayloadSupportsJSONObjectFormatSchema() throws {
        let client = RemoteLLMRuntimeClient()

        let payload = try client.ollamaNativePayload(
            model: "qwen3",
            systemPrompt: "",
            userPrompt: "返回结构化结果",
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3",
                ollamaResponseFormat: OllamaResponseFormat.jsonSchema.rawValue,
                ollamaJSONSchema: #"{"type":"object","properties":{"answer":{"type":"string"}}}"#
            ),
            tuning: .init(maxTokens: 128, temperature: 0.2, topP: 0.9),
            streamingEnabled: false
        )

        let schema = try XCTUnwrap(payload["format"] as? [String: Any])
        XCTAssertEqual(schema["type"] as? String, "object")
    }

    func testOllamaCompatibleOverridesMapSupportedOptionKeysOnly() throws {
        let client = RemoteLLMRuntimeClient()
        var payload = client.openAICompatiblePayload(
            model: "qwen3",
            systemPrompt: "",
            userPrompt: "hi",
            tuning: .init(maxTokens: 256, temperature: 0.2, topP: 0.9),
            streamingEnabled: false
        )

        try client.applyOllamaCompatibleOptionOverrides(
            to: &payload,
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3",
                ollamaOptionsJSON: #"{"temperature":0.4,"top_p":0.8,"num_predict":64,"repeat_penalty":1.2}"#
            )
        )

        XCTAssertEqual(payload["temperature"] as? Double, 0.4)
        XCTAssertEqual(payload["top_p"] as? Double, 0.8)
        XCTAssertEqual(payload["max_tokens"] as? Int, 64)
        XCTAssertNil(payload["repeat_penalty"])
    }
}

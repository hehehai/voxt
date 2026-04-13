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

    func testStreamingEndpointValueKeepsOpenAICompatibleEndpoint() {
        let client = RemoteLLMRuntimeClient()

        let endpoint = client.streamingEndpointValue(
            provider: .openAI,
            endpoint: "https://api.openai.com/v1/chat/completions",
            model: "gpt-5.2",
            streamingEnabled: true
        )

        XCTAssertEqual(endpoint, "https://api.openai.com/v1/chat/completions")
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
}

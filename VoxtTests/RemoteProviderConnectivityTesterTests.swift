import XCTest
@testable import Voxt

final class RemoteProviderConnectivityTesterTests: XCTestCase {
    func testDeepSeekReachabilityBodyDisablesThinkingAndLimitsOutput() async throws {
        let tester = RemoteProviderConnectivityTester(testTarget: .llm(.deepseek))

        let body = try await tester.openAICompatibleReachabilityBody(
            provider: .deepseek,
            endpoint: "https://api.deepseek.com/chat/completions",
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.deepseek.rawValue,
                model: "deepseek-v4-flash"
            ),
            model: "deepseek-v4-flash"
        )

        XCTAssertEqual(body["model"] as? String, "deepseek-v4-flash")
        XCTAssertEqual(body["max_tokens"] as? Int, 1)
        XCTAssertEqual(body["stream"] as? Bool, false)

        let thinking = try XCTUnwrap(body["thinking"] as? [String: String])
        XCTAssertEqual(thinking["type"], "disabled")
    }

    func testOllamaNativeReachabilityBodyIncludesConfiguredOptions() async throws {
        let tester = RemoteProviderConnectivityTester(testTarget: .llm(.ollama))

        let body = try await tester.openAICompatibleReachabilityBody(
            provider: .ollama,
            endpoint: "http://127.0.0.1:11434/api/chat",
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3",
                ollamaResponseFormat: OllamaResponseFormat.json.rawValue,
                ollamaThinkMode: OllamaThinkMode.high.rawValue,
                ollamaKeepAlive: "5m",
                ollamaLogprobsEnabled: true,
                ollamaTopLogprobs: 4,
                ollamaOptionsJSON: #"{"temperature":0.6,"num_ctx":8192}"#
            ),
            model: "qwen3"
        )

        XCTAssertEqual(body["format"] as? String, "json")
        XCTAssertEqual(body["think"] as? String, "high")
        XCTAssertEqual(body["keep_alive"] as? String, "5m")
        XCTAssertEqual(body["logprobs"] as? Bool, true)
        XCTAssertEqual(body["top_logprobs"] as? Int, 4)

        let options = try XCTUnwrap(body["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Double, 0.6)
        XCTAssertEqual(options["num_ctx"] as? Int, 8192)
        XCTAssertEqual(options["num_predict"] as? Int, 32)
    }

    func testOllamaNativeReachabilityBodyUsesGenerateShapeForExplicitGenerateEndpoint() async throws {
        let tester = RemoteProviderConnectivityTester(testTarget: .llm(.ollama))

        let body = try await tester.openAICompatibleReachabilityBody(
            provider: .ollama,
            endpoint: "http://localhost:11434/api/generate",
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3"
            ),
            model: "qwen3"
        )

        XCTAssertEqual(body["prompt"] as? String, "ping")
        XCTAssertNil(body["messages"])
    }

    func testOllamaNativeReachabilityBodyUsesChatShapeForBaseEndpoint() async throws {
        let tester = RemoteProviderConnectivityTester(testTarget: .llm(.ollama))

        let body = try await tester.openAICompatibleReachabilityBody(
            provider: .ollama,
            endpoint: "http://localhost:11434/api/chat",
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3"
            ),
            model: "qwen3"
        )

        XCTAssertNotNil(body["messages"])
        XCTAssertNil(body["prompt"])
    }

    func testStepFunReachabilityBodyUsesChatCompletionsShape() async throws {
        let tester = RemoteProviderConnectivityTester(testTarget: .llm(.stepFun))

        let body = try await tester.openAICompatibleReachabilityBody(
            provider: .stepFun,
            endpoint: "https://api.stepfun.com/v1/chat/completions",
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.stepFun.rawValue,
                model: "step-3.5-flash"
            ),
            model: "step-3.5-flash"
        )

        XCTAssertEqual(body["model"] as? String, "step-3.5-flash")
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "user")
        XCTAssertEqual(messages.first?["content"], "ping")
        XCTAssertNil(body["max_output_tokens"])
    }

    func testStepFunReachabilityHeadersRequestSSE() {
        let tester = RemoteProviderConnectivityTester(testTarget: .asr(.stepFunASR))

        let headers = tester.stepFunReachabilityHeaders(token: "step-token")

        XCTAssertEqual(headers["Accept"], "text/event-stream")
        XCTAssertEqual(headers["Authorization"], "Bearer step-token")
    }

    func testStepFunReachabilityDefaultEndpointUsesDocumentedSSEPath() {
        XCTAssertEqual(
            RemoteProviderConnectivityTestEndpoints.resolvedStepFunASREndpoint(""),
            "https://api.stepfun.com/v1/audio/asr/sse"
        )
    }
}

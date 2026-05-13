import XCTest
@testable import Voxt

final class RemoteModelConfigurationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VoxtSecureStorage.clearAllForTesting()
    }

    override func tearDown() {
        VoxtSecureStorage.clearAllForTesting()
        super.tearDown()
    }

    func testDoubaoConfigurationUsesExpectedDefaults() {
        XCTAssertEqual(DoubaoASRConfiguration.resolvedEndpoint("", model: ""), DoubaoASRConfiguration.defaultNostreamEndpoint)
        XCTAssertEqual(
            DoubaoASRConfiguration.resolvedStreamingEndpoint("", model: DoubaoASRConfiguration.modelV1),
            DoubaoASRConfiguration.defaultStreamingEndpointV1
        )
        XCTAssertEqual(
            DoubaoASRConfiguration.resolvedStreamingEndpoint("", model: ""),
            DoubaoASRConfiguration.defaultStreamingEndpointV2
        )
    }

    func testDoubaoFullRequestPayloadIncludesLanguageAndVariant() {
        let payload = DoubaoASRConfiguration.fullRequestPayload(
            requestID: "req-1",
            userID: "user-1",
            language: "zh-CN",
            chineseOutputVariant: "zh-Hans",
            enableNonstream: true
        )

        let audio = payload["audio"] as? [String: Any]
        let request = payload["request"] as? [String: Any]
        XCTAssertEqual(audio?["language"] as? String, "zh-CN")
        XCTAssertEqual(request?["output_zh_variant"] as? String, "zh-Hans")
        XCTAssertEqual(request?["enable_nonstream"] as? Bool, true)
    }

    func testDoubaoFullRequestPayloadIncludesDictionaryContextAndCorpus() throws {
        let payload = DoubaoASRConfiguration.fullRequestPayload(
            requestID: "req-1",
            userID: "user-1",
            language: "zh-CN",
            chineseOutputVariant: "zh-Hans",
            dictionaryPayload: DoubaoDictionaryRequestPayload(
                hotwords: ["OpenAI"],
                correctWords: ["open ai": "OpenAI"]
            )
        )

        let request = try XCTUnwrap(payload["request"] as? [String: Any])
        let corpus = try XCTUnwrap(request["corpus"] as? [String: Any])

        let contextString = try XCTUnwrap(corpus["context"] as? String)
        let contextData = try XCTUnwrap(contextString.data(using: .utf8))
        let context = try XCTUnwrap(try JSONSerialization.jsonObject(with: contextData) as? [String: Any])
        XCTAssertEqual((context["hotwords"] as? [[String: String]])?.first?["word"], "OpenAI")
        XCTAssertEqual((context["correct_words"] as? [String: String])?["open ai"], "OpenAI")
    }

    func testDoubaoRecommendedStreamingChunkSplitsAndFlushesTrailingPartial() {
        let packetBytes = DoubaoASRConfiguration.recommendedStreamingPacketBytes
        var buffer = Data(repeating: 1, count: packetBytes * 2 + 123)

        let first = DoubaoASRConfiguration.popRecommendedStreamingChunk(from: &buffer, includeTrailingPartial: false)
        let second = DoubaoASRConfiguration.popRecommendedStreamingChunk(from: &buffer, includeTrailingPartial: false)
        let noneYet = DoubaoASRConfiguration.popRecommendedStreamingChunk(from: &buffer, includeTrailingPartial: false)
        let trailing = DoubaoASRConfiguration.popRecommendedStreamingChunk(from: &buffer, includeTrailingPartial: true)

        XCTAssertEqual(first?.count, packetBytes)
        XCTAssertEqual(second?.count, packetBytes)
        XCTAssertNil(noneYet)
        XCTAssertEqual(trailing?.count, 123)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDoubaoFinalStreamingSequenceUsesNextSequence() {
        XCTAssertEqual(DoubaoASRConfiguration.finalStreamingSequence(nextAudioSequence: 2), -2)
        XCTAssertEqual(DoubaoASRConfiguration.finalStreamingSequence(nextAudioSequence: 16), -16)
    }

    func testAliyunASRModelOptionsIncludeOmniRealtimeModels() {
        let ids = Set(RemoteASRProvider.aliyunBailianASR.modelOptions.map(\.id))
        XCTAssertTrue(ids.contains("qwen3.5-omni-flash-realtime"))
        XCTAssertTrue(ids.contains("qwen3.5-omni-plus-realtime"))
        XCTAssertTrue(ids.contains("qwen-omni-turbo-realtime"))
    }

    func testAliyunRealtimeModelFamilyDetectionSeparatesQwenAndOmni() {
        XCTAssertEqual(
            RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "qwen3-asr-flash-realtime"),
            .qwenASR
        )
        XCTAssertEqual(
            RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "qwen3.5-omni-flash-realtime"),
            .omniASR
        )
        XCTAssertEqual(
            RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "qwen3.5-omni-plus-realtime"),
            .omniASR
        )
        XCTAssertEqual(
            RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "qwen-omni-turbo-realtime"),
            .omniASR
        )
        XCTAssertNil(RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "fun-asr-realtime"))
    }

    func testAliyunOmniSessionUpdatePayloadUsesExplicitInputTranscriptionModel() throws {
        let payload = AliyunQwenRealtimePayloadSupport.sessionUpdatePayload(
            kind: .omniASR,
            hintPayload: ResolvedASRHintPayload(language: "zh", languageHints: ["zh"])
        )

        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        let transcription = try XCTUnwrap(session["input_audio_transcription"] as? [String: Any])
        let turnDetection = try XCTUnwrap(session["turn_detection"] as? [String: Any])

        XCTAssertEqual(payload["type"] as? String, "session.update")
        XCTAssertEqual(session["modalities"] as? [String], ["text"])
        XCTAssertEqual(session["input_audio_format"] as? String, "pcm")
        XCTAssertEqual(session["sample_rate"] as? Int, 16000)
        XCTAssertEqual(transcription["model"] as? String, "qwen3-asr-flash-realtime")
        XCTAssertEqual(transcription["language"] as? String, "zh")
        XCTAssertEqual(turnDetection["type"] as? String, "server_vad")
        XCTAssertEqual(turnDetection["threshold"] as? Double, 0.0)
        XCTAssertEqual(turnDetection["silence_duration_ms"] as? Int, 400)
    }

    func testAliyunOmniRealtimeDoesNotRequireManualCommitWhenUsingServerVAD() {
        XCTAssertFalse(AliyunQwenRealtimeSessionKind.omniASR.shouldCommitBeforeFinish)
    }

    func testAliyunQwenSessionUpdatePayloadLeavesTranscriptionModelUnset() throws {
        let payload = AliyunQwenRealtimePayloadSupport.sessionUpdatePayload(
            kind: .qwenASR,
            hintPayload: ResolvedASRHintPayload(language: nil, languageHints: [])
        )

        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        let transcription = try XCTUnwrap(session["input_audio_transcription"] as? [String: Any])

        XCTAssertNil(transcription["model"])
        XCTAssertNil(transcription["language"])
    }

    func testLoadSaveRoundTripPreservesConfigurations() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteASRProvider.openAIWhisper.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.openAIWhisper.rawValue,
                model: "whisper-1",
                endpoint: "https://example.com/asr",
                apiKey: "secret"
            ),
            RemoteASRProvider.doubaoASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                appID: "app-id",
                accessToken: "token",
                doubaoDictionaryMode: DoubaoDictionaryMode.off.rawValue,
                doubaoEnableRequestHotwords: false,
                doubaoEnableRequestCorrections: false
            ),
            RemoteLLMProvider.openAI.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "https://example.com/llm",
                apiKey: "secret",
                openAIReasoningEffort: OpenAIReasoningEffort.high.rawValue,
                openAITextVerbosity: OpenAITextVerbosity.low.rawValue,
                openAIMaxOutputTokens: 4096
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(stored)
        let roundTrip = RemoteModelConfigurationStore.loadConfigurations(from: raw)

        XCTAssertFalse(raw.contains("secret"))
        XCTAssertFalse(raw.contains("app-id"))
        XCTAssertFalse(raw.contains("token"))
        XCTAssertEqual(roundTrip, stored)
    }

    func testMetadataOnlyLoadDoesNotResolveStoredSensitiveValues() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteLLMProvider.openAI.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "https://example.com/llm",
                apiKey: "secret"
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(stored)
        let metadataOnly = RemoteModelConfigurationStore.loadConfigurations(
            from: raw,
            sensitiveValueLoading: .metadataOnly
        )

        XCTAssertEqual(metadataOnly[RemoteLLMProvider.openAI.rawValue]?.model, "gpt-5.2")
        XCTAssertEqual(metadataOnly[RemoteLLMProvider.openAI.rawValue]?.endpoint, "https://example.com/llm")
        XCTAssertFalse(metadataOnly[RemoteLLMProvider.openAI.rawValue]?.apiKey.isEmpty ?? true)
        XCTAssertNotEqual(metadataOnly[RemoteLLMProvider.openAI.rawValue]?.apiKey, "secret")
        XCTAssertTrue(metadataOnly[RemoteLLMProvider.openAI.rawValue]?.isConfigured ?? false)
    }

    func testOllamaConfigurationIsConfiguredWithoutAPIKeyWhenModelExists() {
        let configuration = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.ollama.rawValue,
            model: "qwen3"
        )

        XCTAssertTrue(configuration.isConfigured)
    }

    func testOMLXConfigurationIsConfiguredWithoutAPIKeyWhenModelExists() {
        let configuration = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.omlx.rawValue,
            model: "qwen3"
        )

        XCTAssertTrue(configuration.isConfigured)
    }

    func testOpenAIConfigurationStillRequiresCredential() {
        let configuration = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.openAI.rawValue,
            model: "gpt-5.2"
        )

        XCTAssertFalse(configuration.isConfigured)
    }

    func testOpenAIModelCatalogUsesOfficialModelIDs() {
        XCTAssertEqual(RemoteLLMProvider.openAI.suggestedModel, "gpt-5.2")

        let ids = RemoteLLMProvider.openAI.modelOptions.map(\.id)
        XCTAssertTrue(ids.contains("gpt-5.2"))
        XCTAssertTrue(ids.contains("gpt-5.2-pro"))
        XCTAssertTrue(ids.contains("gpt-5.1"))
        XCTAssertFalse(ids.contains("gpt-5.5"))
        XCTAssertFalse(ids.contains("gpt-5.4"))
    }

    func testOpenAIReasoningEffortOptionsFollowModelSupport() {
        XCTAssertEqual(
            OpenAIReasoningEffort.supportedCases(forModel: "gpt-5.2"),
            [.automatic, .none, .low, .medium, .high, .xhigh]
        )
        XCTAssertEqual(
            OpenAIReasoningEffort.supportedCases(forModel: "gpt-5.2-pro"),
            [.automatic, .medium, .high, .xhigh]
        )
        XCTAssertEqual(
            OpenAIReasoningEffort.supportedCases(forModel: "gpt-5.1"),
            [.automatic, .none, .low, .medium, .high]
        )
        XCTAssertEqual(
            OpenAIReasoningEffort.supportedCases(forModel: "gpt-5"),
            [.automatic, .minimal, .low, .medium, .high]
        )
    }

    func testLoadSaveRoundTripPreservesOllamaConfigurationFields() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteLLMProvider.ollama.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3",
                endpoint: "http://127.0.0.1:11434/api/chat",
                ollamaResponseFormat: OllamaResponseFormat.jsonSchema.rawValue,
                ollamaJSONSchema: #"{"type":"object","properties":{"answer":{"type":"string"}}}"#,
                ollamaThinkMode: OllamaThinkMode.low.rawValue,
                ollamaKeepAlive: "5m",
                ollamaLogprobsEnabled: true,
                ollamaTopLogprobs: 7,
                ollamaOptionsJSON: #"{"num_ctx":8192,"repeat_penalty":1.05}"#
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(stored)
        let roundTrip = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        let restored = roundTrip[RemoteLLMProvider.ollama.rawValue]

        XCTAssertEqual(restored?.ollamaResponseFormat, OllamaResponseFormat.jsonSchema.rawValue)
        XCTAssertEqual(restored?.ollamaJSONSchema, #"{"type":"object","properties":{"answer":{"type":"string"}}}"#)
        XCTAssertEqual(restored?.ollamaThinkMode, OllamaThinkMode.low.rawValue)
        XCTAssertEqual(restored?.ollamaKeepAlive, "5m")
        XCTAssertEqual(restored?.ollamaLogprobsEnabled, true)
        XCTAssertEqual(restored?.ollamaTopLogprobs, 7)
        XCTAssertEqual(restored?.ollamaOptionsJSON, #"{"num_ctx":8192,"repeat_penalty":1.05}"#)
    }

    func testResolvedASRConfigurationFallsBackToSuggestedModelAndClearsRealtimeFlag() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteASRProvider.doubaoASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: "invalid-model",
                accessToken: "token",
                openAIChunkPseudoRealtimeEnabled: true
            )
        ]

        let resolved = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: .doubaoASR,
            stored: stored
        )

        XCTAssertEqual(resolved.model, RemoteASRProvider.doubaoASR.suggestedModel)
        XCTAssertFalse(resolved.openAIChunkPseudoRealtimeEnabled)
    }

    func testResolvedLLMConfigurationDefaultsWhenMissing() {
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: .anthropic,
            stored: [:]
        )

        XCTAssertEqual(resolved.providerID, RemoteLLMProvider.anthropic.rawValue)
        XCTAssertEqual(resolved.model, RemoteLLMProvider.anthropic.suggestedModel)
        XCTAssertEqual(resolved.endpoint, "")
        XCTAssertFalse(resolved.searchEnabled)
    }

    func testResponsesProviderCapabilitiesAreConfiguredPerProvider() {
        XCTAssertTrue(RemoteLLMProvider.openAI.usesResponsesAPI)
        XCTAssertTrue(RemoteLLMProvider.aliyunBailian.usesResponsesAPI)
        XCTAssertTrue(RemoteLLMProvider.volcengine.usesResponsesAPI)
        XCTAssertTrue(RemoteLLMProvider.aliyunBailian.supportsHostedSearch)
        XCTAssertTrue(RemoteLLMProvider.volcengine.supportsHostedSearch)
        XCTAssertTrue(RemoteLLMProvider.aliyunBailian.defaultSearchEnabled)
        XCTAssertFalse(RemoteLLMProvider.volcengine.defaultSearchEnabled)
        XCTAssertTrue(RemoteLLMProvider.omlx.apiKeyIsOptional)
        XCTAssertFalse(RemoteLLMProvider.omlx.usesResponsesAPI)
    }

    func testDeepSeekUsesCurrentSuggestedModelAndKeepsLegacyAliases() {
        XCTAssertEqual(RemoteLLMProvider.deepseek.suggestedModel, "deepseek-v4-flash")

        let latestIDs = RemoteLLMProvider.deepseek.latestModelOptions.map(\.id)
        XCTAssertTrue(latestIDs.contains("deepseek-v4-flash"))
        XCTAssertTrue(latestIDs.contains("deepseek-v4-pro"))

        let allIDs = RemoteLLMProvider.deepseek.modelOptions.map(\.id)
        XCTAssertTrue(allIDs.contains("deepseek-chat"))
        XCTAssertTrue(allIDs.contains("deepseek-reasoner"))
    }

    func testResolvedAliyunLLMConfigurationDefaultsSearchToEnabled() {
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: .aliyunBailian,
            stored: [:]
        )

        XCTAssertTrue(resolved.searchEnabled)
    }

    func testResolvedVolcengineLLMConfigurationDefaultsSearchToDisabled() {
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: .volcengine,
            stored: [:]
        )

        XCTAssertFalse(resolved.searchEnabled)
    }

    func testDecodeLegacyAliyunLLMConfigurationDefaultsSearchToEnabled() throws {
        let legacyJSON = """
        [
          {
            "providerID": "aliyunBailian",
            "model": "qwen-plus-latest",
            "endpoint": "",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(loaded["aliyunBailian"]?.searchEnabled, true)
    }

    func testDecodeLegacyVolcengineLLMConfigurationDefaultsSearchToDisabled() throws {
        let legacyJSON = """
        [
          {
            "providerID": "volcengine",
            "model": "doubao-1-5-pro",
            "endpoint": "",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(loaded["volcengine"]?.searchEnabled, false)
    }

    func testDecodeLegacyAliyunEndpointMigratesToResponsesURL() {
        let legacyJSON = """
        [
          {
            "providerID": "aliyunBailian",
            "model": "qwen-plus-latest",
            "endpoint": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(
            loaded["aliyunBailian"]?.endpoint,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"
        )
    }

    func testDecodeLegacyVolcengineEndpointMigratesToResponsesURL() {
        let legacyJSON = """
        [
          {
            "providerID": "volcengine",
            "model": "doubao-1-5-pro",
            "endpoint": "https://ark.cn-beijing.volces.com/api/v3/models",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(
            loaded["volcengine"]?.endpoint,
            "https://ark.cn-beijing.volces.com/api/v3/responses"
        )
    }

    func testDecodeLegacyOpenAIEndpointMigratesToResponsesURL() {
        let legacyJSON = """
        [
          {
            "providerID": "openAI",
            "model": "gpt-5.2",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(
            loaded["openAI"]?.endpoint,
            "https://api.openai.com/v1/responses"
        )
    }

    func testMigrateLegacyLLMEndpointsRewritesPersistedLegacyURLs() {
        let suiteName = "RemoteModelConfigurationTests.migrateLegacyLLMEndpoints.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            """
            [
              {
                "providerID": "openAI",
                "model": "gpt-5.2",
                "endpoint": "https://api.openai.com/v1/models",
                "apiKey": "",
                "appID": "",
                "accessToken": ""
              },
              {
                "providerID": "aliyunBailian",
                "model": "qwen-plus-latest",
                "endpoint": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                "apiKey": "",
                "appID": "",
                "accessToken": ""
              },
              {
                "providerID": "volcengine",
                "model": "doubao-1-5-pro",
                "endpoint": "https://ark.cn-beijing.volces.com/api/v3/models",
                "apiKey": "",
                "appID": "",
                "accessToken": ""
              }
            ]
            """,
            forKey: AppPreferenceKey.remoteLLMProviderConfigurations
        )

        RemoteModelConfigurationStore.migrateLegacyLLMEndpoints(defaults: defaults)

        let migrated = RemoteModelConfigurationStore.loadConfigurations(
            from: defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? ""
        )

        XCTAssertEqual(
            migrated["openAI"]?.endpoint,
            "https://api.openai.com/v1/responses"
        )
        XCTAssertEqual(
            migrated["aliyunBailian"]?.endpoint,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"
        )
        XCTAssertEqual(
            migrated["volcengine"]?.endpoint,
            "https://ark.cn-beijing.volces.com/api/v3/responses"
        )
    }

    func testMigrateLegacyStoredSecretsSkipsAlreadySanitizedPayloads() {
        let suiteName = "RemoteModelConfigurationTests.migrateLegacyStoredSecrets.skip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let raw = """
        [
          {
            "providerID": "openAI",
            "model": "gpt-5.2",
            "endpoint": "https://example.com/responses",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        defaults.set(raw, forKey: AppPreferenceKey.remoteLLMProviderConfigurations)

        RemoteModelConfigurationStore.migrateLegacyStoredSecrets(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations),
            raw
        )
        XCTAssertNil(
            VoxtSecureStorage.string(
                for: "remote-provider.openAI.apiKey"
            )
        )
    }

    func testSavingOneRemoteASRProviderPreservesOtherProviderSecrets() {
        let initial: [String: RemoteProviderConfiguration] = [
            RemoteASRProvider.doubaoASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                appID: "doubao-app",
                accessToken: "doubao-token"
            ),
            RemoteASRProvider.aliyunBailianASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
                model: "fun-asr-realtime",
                endpoint: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
                apiKey: "aliyun-key"
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(initial)
        let updatedAliyun = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
            model: "qwen3-asr-flash-realtime",
            endpoint: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
            apiKey: "aliyun-key-updated"
        )

        let mergedRaw = RemoteModelConfigurationStore.saveConfiguration(
            updatedAliyun,
            updating: raw
        )
        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: mergedRaw)

        XCTAssertEqual(loaded[RemoteASRProvider.aliyunBailianASR.rawValue]?.apiKey, "aliyun-key-updated")
        XCTAssertEqual(loaded[RemoteASRProvider.doubaoASR.rawValue]?.appID, "doubao-app")
        XCTAssertEqual(loaded[RemoteASRProvider.doubaoASR.rawValue]?.accessToken, "doubao-token")
    }

    func testRemoteASRTextSanitizerRejectsIdentifierLikeStrings() {
        XCTAssertTrue(RemoteASRTextSanitizer.isLikelyIdentifierText("9ff6a1a4-f758-4a87-b761-11508533c499"))
        XCTAssertTrue(RemoteASRTextSanitizer.isLikelyIdentifierText("abc123ef456789ab_cdef1234567890"))
        XCTAssertTrue(RemoteASRTextSanitizer.isLikelyIdentifierText("9ff6a1a4f7584a87b76111508533c499"))
    }

    func testRemoteASRTextSanitizerAllowsNaturalLanguageText() {
        XCTAssertFalse(RemoteASRTextSanitizer.isLikelyIdentifierText("你好"))
        XCTAssertFalse(RemoteASRTextSanitizer.isLikelyIdentifierText("我们今天继续开会"))
        XCTAssertFalse(RemoteASRTextSanitizer.isLikelyIdentifierText("hello world 2026"))
    }

}

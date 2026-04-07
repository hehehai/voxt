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

    func testLoadSaveRoundTripPreservesConfigurations() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteASRProvider.openAIWhisper.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.openAIWhisper.rawValue,
                model: "whisper-1",
                meetingModel: "",
                endpoint: "https://example.com/asr",
                apiKey: "secret"
            ),
            RemoteASRProvider.doubaoASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                meetingModel: DoubaoASRConfiguration.meetingModelTurbo,
                appID: "app-id",
                accessToken: "token"
            ),
            RemoteLLMProvider.openAI.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "https://example.com/llm",
                apiKey: "secret"
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(stored)
        let roundTrip = RemoteModelConfigurationStore.loadConfigurations(from: raw)

        XCTAssertFalse(raw.contains("secret"))
        XCTAssertFalse(raw.contains("app-id"))
        XCTAssertFalse(raw.contains("token"))
        XCTAssertEqual(roundTrip, stored)
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
        XCTAssertEqual(resolved.meetingModel, "")
        XCTAssertEqual(resolved.endpoint, "")
    }

    func testAliyunMeetingFileTranscriptionUsesAsyncEndpoints() {
        XCTAssertEqual(
            AliyunMeetingASRConfiguration.resolvedTranscriptionEndpoint(
                "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
                model: "qwen3-asr-flash-filetrans"
            ),
            "wss://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"
                .replacingOccurrences(of: "wss://", with: "https://")
        )
        XCTAssertEqual(
            AliyunMeetingASRConfiguration.resolvedUploadPolicyEndpoint(
                "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription",
                model: "qwen3-asr-flash-filetrans"
            ),
            "https://dashscope.aliyuncs.com/api/v1/uploads"
        )
        XCTAssertEqual(
            AliyunMeetingASRConfiguration.taskQueryMethod(for: "qwen3-asr-flash-filetrans"),
            .get
        )
    }

    func testAliyunMeetingUSShortAudioUsesCompatibleEndpoint() {
        XCTAssertEqual(
            AliyunMeetingASRConfiguration.resolvedCompatibleEndpoint(
                "",
                model: "qwen3-asr-flash-us"
            ),
            "https://dashscope-us.aliyuncs.com/compatible-mode/v1/chat/completions"
        )
        XCTAssertNil(
            AliyunMeetingASRConfiguration.validationError(
                model: "qwen3-asr-flash-us",
                endpoint: "https://dashscope-us.aliyuncs.com/compatible-mode/v1/chat/completions"
            )
        )
    }

    func testAliyunMeetingFileTranscriptionRejectsUSRegion() {
        XCTAssertNotNil(
            AliyunMeetingASRConfiguration.validationError(
                model: "qwen3-asr-flash-filetrans",
                endpoint: "https://dashscope-us.aliyuncs.com/api/v1/services/audio/asr/transcription"
            )
        )
        XCTAssertEqual(
            AliyunMeetingASRConfiguration.endpointPresets(for: "qwen3-asr-flash-filetrans").map(\.url),
            [
                "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription",
                "https://dashscope-intl.aliyuncs.com/api/v1/services/audio/asr/transcription"
            ]
        )
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

    func testRealtimeMeetingProvidersSkipDedicatedMeetingModelRequirement() {
        let doubaoRealtime = RemoteProviderConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            model: DoubaoASRConfiguration.modelV2,
            endpoint: "",
            apiKey: "",
            appID: "app-id",
            accessToken: "token"
        )
        XCTAssertFalse(
            RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(
                .doubaoASR,
                configuration: doubaoRealtime
            )
        )

        let aliyunRealtime = RemoteProviderConfiguration(
            providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
            model: "fun-asr-realtime",
            endpoint: "",
            apiKey: "token"
        )
        XCTAssertFalse(
            RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(
                .aliyunBailianASR,
                configuration: aliyunRealtime
            )
        )

        let aliyunFile = RemoteProviderConfiguration(
            providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
            model: "paraformer-v2",
            endpoint: "",
            apiKey: "token"
        )
        XCTAssertTrue(
            RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(
                .aliyunBailianASR,
                configuration: aliyunFile
            )
        )
    }
}

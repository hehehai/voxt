import XCTest
@testable import Voxt

final class RemoteModelConfigurationTests: XCTestCase {
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
            chineseOutputVariant: "zh-Hans"
        )

        let audio = payload["audio"] as? [String: Any]
        let request = payload["request"] as? [String: Any]
        XCTAssertEqual(audio?["language"] as? String, "zh-CN")
        XCTAssertEqual(request?["output_zh_variant"] as? String, "zh-Hans")
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
}

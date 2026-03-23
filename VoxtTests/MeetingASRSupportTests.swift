import XCTest
@testable import Voxt

@MainActor
final class MeetingASRSupportTests: XCTestCase {
    private func assertChunkMode(
        _ context: MeetingASREngineContext,
        profile expectedProfile: MeetingChunkingProfile,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch context.resolvedMode {
        case .chunk(let profile):
            XCTAssertEqual(profile, expectedProfile, file: file, line: line)
        case .liveRemote(let provider):
            XCTFail("Expected chunk mode, got live remote for \(provider)", file: file, line: line)
        }
    }

    func testWhisperRealtimeUsesRealtimeProfile() {
        let context = MeetingASRSupport.resolveContext(
            transcriptionEngine: .whisperKit,
            whisperModelState: .ready,
            whisperCurrentModelID: "base",
            whisperRealtimeEnabled: true,
            whisperIsCurrentModelLoaded: true,
            whisperDisplayTitle: { _ in "Whisper Base" },
            mlxModelState: .notDownloaded,
            mlxCurrentModelRepo: MLXModelManager.defaultModelRepo,
            mlxIsCurrentModelLoaded: false,
            mlxDisplayTitle: { _ in "" },
            remoteProvider: .openAIWhisper,
            remoteConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "whisper-1", endpoint: "", apiKey: "")
        )

        XCTAssertEqual(context.engine, .whisperKit)
        XCTAssertEqual(context.chunkingProfile, .realtime)
        XCTAssertFalse(context.needsModelInitialization)
    }

    func testMLXRealtimeModelUsesRealtimeProfile() {
        let context = MeetingASRSupport.resolveContext(
            transcriptionEngine: .mlxAudio,
            whisperModelState: .notDownloaded,
            whisperCurrentModelID: "base",
            whisperRealtimeEnabled: false,
            whisperIsCurrentModelLoaded: false,
            whisperDisplayTitle: { _ in "" },
            mlxModelState: .ready,
            mlxCurrentModelRepo: "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16",
            mlxIsCurrentModelLoaded: true,
            mlxDisplayTitle: { _ in "Voxtral Realtime Mini 4B" },
            remoteProvider: .openAIWhisper,
            remoteConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "whisper-1", endpoint: "", apiKey: "")
        )

        XCTAssertEqual(context.engine, .mlxAudio)
        XCTAssertEqual(context.chunkingProfile, .realtime)
        XCTAssertFalse(context.needsModelInitialization)
    }

    func testOpenAIPseudoRealtimeUsesRealtimeProfile() {
        let context = MeetingASRSupport.resolveContext(
            transcriptionEngine: .remote,
            whisperModelState: .notDownloaded,
            whisperCurrentModelID: "base",
            whisperRealtimeEnabled: false,
            whisperIsCurrentModelLoaded: false,
            whisperDisplayTitle: { _ in "" },
            mlxModelState: .notDownloaded,
            mlxCurrentModelRepo: MLXModelManager.defaultModelRepo,
            mlxIsCurrentModelLoaded: false,
            mlxDisplayTitle: { _ in "" },
            remoteProvider: .openAIWhisper,
            remoteConfiguration: .init(
                providerID: RemoteASRProvider.openAIWhisper.rawValue,
                model: "gpt-4o-mini-transcribe",
                endpoint: "",
                apiKey: "token",
                openAIChunkPseudoRealtimeEnabled: true
            )
        )

        XCTAssertEqual(context.engine, .remote)
        XCTAssertEqual(context.chunkingProfile, .realtime)
        assertChunkMode(context, profile: .realtime)
    }

    func testGLMRemoteUsesQualityProfile() {
        let context = MeetingASRSupport.resolveContext(
            transcriptionEngine: .remote,
            whisperModelState: .notDownloaded,
            whisperCurrentModelID: "base",
            whisperRealtimeEnabled: false,
            whisperIsCurrentModelLoaded: false,
            whisperDisplayTitle: { _ in "" },
            mlxModelState: .notDownloaded,
            mlxCurrentModelRepo: MLXModelManager.defaultModelRepo,
            mlxIsCurrentModelLoaded: false,
            mlxDisplayTitle: { _ in "" },
            remoteProvider: .glmASR,
            remoteConfiguration: .init(
                providerID: RemoteASRProvider.glmASR.rawValue,
                model: "glm-asr-1",
                endpoint: "",
                apiKey: "token"
            )
        )

        XCTAssertEqual(context.chunkingProfile, .quality)
        assertChunkMode(context, profile: .quality)
    }

    func testAliyunMeetingUsesChunkProfile() {
        let context = MeetingASRSupport.resolveContext(
            transcriptionEngine: .remote,
            whisperModelState: .notDownloaded,
            whisperCurrentModelID: "base",
            whisperRealtimeEnabled: false,
            whisperIsCurrentModelLoaded: false,
            whisperDisplayTitle: { _ in "" },
            mlxModelState: .notDownloaded,
            mlxCurrentModelRepo: MLXModelManager.defaultModelRepo,
            mlxIsCurrentModelLoaded: false,
            mlxDisplayTitle: { _ in "" },
            remoteProvider: .aliyunBailianASR,
            remoteConfiguration: .init(
                providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
                model: "fun-asr-realtime",
                meetingModel: "qwen3-asr-flash-filetrans",
                endpoint: "",
                apiKey: "token"
            )
        )

        assertChunkMode(context, profile: .quality)
    }

    func testDoubaoMeetingUsesDedicatedMeetingModel() {
        let context = MeetingASRSupport.resolveContext(
            transcriptionEngine: .remote,
            whisperModelState: .notDownloaded,
            whisperCurrentModelID: "base",
            whisperRealtimeEnabled: false,
            whisperIsCurrentModelLoaded: false,
            whisperDisplayTitle: { _ in "" },
            mlxModelState: .notDownloaded,
            mlxCurrentModelRepo: MLXModelManager.defaultModelRepo,
            mlxIsCurrentModelLoaded: false,
            mlxDisplayTitle: { _ in "" },
            remoteProvider: .doubaoASR,
            remoteConfiguration: .init(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                meetingModel: DoubaoASRConfiguration.meetingModelTurbo,
                endpoint: "",
                apiKey: "",
                appID: "app-id",
                accessToken: "token"
            )
        )

        XCTAssertEqual(context.historyModelDescription, "\(RemoteASRProvider.doubaoASR.title) (\(DoubaoASRConfiguration.meetingModelTurbo))")
        assertChunkMode(context, profile: .quality)
    }
}

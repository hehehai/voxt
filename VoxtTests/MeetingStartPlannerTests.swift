import XCTest
@testable import Voxt

@MainActor
final class MeetingStartPlannerTests: XCTestCase {
    func testWhisperMeetingFallsBackToMLXWhenAvailable() {
        let decision = MeetingStartPlanner.resolve(
            selectedEngine: .whisperKit,
            mlxModelState: .ready,
            whisperModelState: .ready,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "", endpoint: "", apiKey: "")
        )

        XCTAssertEqual(decision, .start(.mlxAudio))
    }

    func testWhisperMeetingUsesMLXAvailabilityRules() {
        let decision = MeetingStartPlanner.resolve(
            selectedEngine: .whisperKit,
            mlxModelState: .notDownloaded,
            whisperModelState: .ready,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "", endpoint: "", apiKey: "")
        )

        XCTAssertEqual(decision, .blocked(.recording(.mlxModelNotInstalled)))
    }

    func testMLXMeetingFollowsRecordingPlanner() {
        let decision = MeetingStartPlanner.resolve(
            selectedEngine: .mlxAudio,
            mlxModelState: .ready,
            whisperModelState: .notDownloaded,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "", endpoint: "", apiKey: "")
        )

        XCTAssertEqual(decision, .start(.mlxAudio))
    }

    func testMLXMeetingIgnoresDifferentRepoActiveDownload() {
        let decision = MeetingStartPlanner.resolve(
            selectedEngine: .mlxAudio,
            selectedMLXRepo: "mlx-community/parakeet-tdt-0.6b-v3",
            activeMLXDownloadRepo: "mlx-community/Qwen3-ASR-0.6B-4bit",
            isSelectedMLXModelDownloaded: true,
            mlxModelState: .downloading(
                progress: 0.5,
                completed: 10,
                total: 20,
                currentFile: "weights.bin",
                completedFiles: 1,
                totalFiles: 2
            ),
            whisperModelState: .ready,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "", endpoint: "", apiKey: "")
        )

        XCTAssertEqual(decision, .start(.mlxAudio))
    }

    func testRemoteMeetingRequiresConfiguredProvider() {
        let blocked = MeetingStartPlanner.resolve(
            selectedEngine: .remote,
            mlxModelState: .ready,
            whisperModelState: .ready,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "whisper-1", endpoint: "", apiKey: "")
        )
        XCTAssertEqual(blocked, .blocked(.remoteASRUnavailable))

        let allowed = MeetingStartPlanner.resolve(
            selectedEngine: .remote,
            mlxModelState: .ready,
            whisperModelState: .ready,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "whisper-1", endpoint: "", apiKey: "token")
        )
        XCTAssertEqual(allowed, .start(.remote))
    }

    func testDoubaoMeetingUsesConfiguredRealtimeProvider() {
        let allowed = MeetingStartPlanner.resolve(
            selectedEngine: .remote,
            mlxModelState: .ready,
            whisperModelState: .ready,
            remoteASRProvider: .doubaoASR,
            remoteASRConfiguration: .init(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                endpoint: "",
                apiKey: "",
                appID: "app-id",
                accessToken: "token"
            )
        )
        XCTAssertEqual(allowed, .start(.remote))
    }

    func testDictationMeetingIsBlocked() {
        let decision = MeetingStartPlanner.resolve(
            selectedEngine: .dictation,
            mlxModelState: .ready,
            whisperModelState: .ready,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "whisper-1", endpoint: "", apiKey: "token")
        )

        XCTAssertEqual(decision, .blocked(.dictationUnsupported))
    }
}

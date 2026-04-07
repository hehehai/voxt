import XCTest
@testable import Voxt

@MainActor
final class MeetingStartPlannerTests: XCTestCase {
    func testWhisperMeetingFollowsRecordingPlanner() {
        let decision = MeetingStartPlanner.resolve(
            selectedEngine: .whisperKit,
            mlxModelState: .notDownloaded,
            whisperModelState: .ready,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "", endpoint: "", apiKey: "")
        )

        XCTAssertEqual(decision, .start(.whisperKit))
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

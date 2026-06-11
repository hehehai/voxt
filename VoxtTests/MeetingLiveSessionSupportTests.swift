import XCTest
@testable import Voxt

final class MeetingLiveSessionSupportTests: XCTestCase {
    func testDoubaoPolicyEnablesKeepaliveAndReconnect() {
        let policy = MeetingLiveSessionPolicy.resolved(
            provider: .doubaoASR,
            configuration: .init(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                endpoint: "",
                apiKey: "",
                appID: "app-id",
                accessToken: "token"
            )
        )

        XCTAssertTrue(policy.idleKeepaliveEnabled)
        XCTAssertEqual(policy.idleKeepaliveInterval, 3.0, accuracy: 0.001)
        XCTAssertEqual(policy.idleKeepaliveFrameDuration, 0.2, accuracy: 0.001)
        XCTAssertTrue(policy.autoReconnectOnUnexpectedClose)
        XCTAssertEqual(policy.prebufferDuration, 1.0, accuracy: 0.001)
        XCTAssertEqual(policy.segmentSilenceSplitThreshold, 1.2, accuracy: 0.001)
    }

    func testAliyunNonRealtimePolicyDisablesKeepaliveAndReconnect() {
        let policy = MeetingLiveSessionPolicy.resolved(
            provider: .aliyunBailianASR,
            configuration: .init(
                providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
                model: "paraformer-v2",
                endpoint: "",
                apiKey: "token"
            )
        )

        XCTAssertFalse(policy.idleKeepaliveEnabled)
        XCTAssertFalse(policy.autoReconnectOnUnexpectedClose)
        XCTAssertEqual(policy.prebufferDuration, 1.0, accuracy: 0.001)
    }

    func testAliyunRealtimePolicyEnablesKeepaliveAndReconnect() {
        let policy = MeetingLiveSessionPolicy.resolved(
            provider: .aliyunBailianASR,
            configuration: .init(
                providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
                model: "fun-asr-realtime",
                endpoint: "",
                apiKey: "token"
            )
        )

        XCTAssertTrue(policy.idleKeepaliveEnabled)
        XCTAssertTrue(policy.autoReconnectOnUnexpectedClose)
        XCTAssertEqual(policy.segmentSilenceSplitThreshold, 1.2, accuracy: 0.001)
    }

    func testOpenAIPolicyDisablesLiveSessionMaintenance() {
        let policy = MeetingLiveSessionPolicy.resolved(
            provider: .openAIWhisper,
            configuration: .init(
                providerID: RemoteASRProvider.openAIWhisper.rawValue,
                model: "gpt-4o-mini-transcribe",
                endpoint: "",
                apiKey: "token",
                openAIChunkPseudoRealtimeEnabled: true
            )
        )

        XCTAssertFalse(policy.idleKeepaliveEnabled)
        XCTAssertFalse(policy.autoReconnectOnUnexpectedClose)
        XCTAssertEqual(policy.prebufferDuration, 0, accuracy: 0.001)
    }

    func testPrebufferKeepsOnlyMostRecentWindow() {
        var prebuffer = MeetingLiveAudioPrebuffer(maxDuration: 1.0)
        prebuffer.append(samples: Array(repeating: 0.1, count: 16_000 / 2), sampleRate: 16_000)
        prebuffer.append(samples: Array(repeating: 0.2, count: 16_000 / 2), sampleRate: 16_000)
        prebuffer.append(samples: Array(repeating: 0.3, count: 16_000 / 2), sampleRate: 16_000)

        let frames = prebuffer.snapshot()
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames.first?.samples.first ?? 0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(frames.last?.samples.first ?? 0, 0.3, accuracy: 0.0001)
    }

    func testTranscriptStateSubtractsAllPriorFrozenText() {
        var state = MeetingLiveTranscriptState()

        XCTAssertEqual(state.normalizedVisibleText(for: "A"), "A")
        state.freezeCurrentItem(text: "A")

        XCTAssertEqual(state.normalizedVisibleText(for: "AB"), "B")
        state.freezeCurrentItem(text: "B")

        XCTAssertEqual(state.normalizedVisibleText(for: "ABC"), "C")
    }

    func testTranscriptStateIgnoresPunctuationWhenSubtractingFrozenText() {
        var state = MeetingLiveTranscriptState()
        state.freezeCurrentItem(text: "你好。")

        XCTAssertEqual(state.normalizedVisibleText(for: "你好，世界"), "世界")
    }

    func testTranscriptStateReturnsEmptyWhenOnlyFrozenPrefixIsPresent() {
        var state = MeetingLiveTranscriptState()
        state.freezeCurrentItem(text: "hello world")

        XCTAssertEqual(state.normalizedVisibleText(for: "hello world"), "")
    }

    func testTranscriptStateKeepsSpeakersIsolatedByUsingIndependentState() {
        var meState = MeetingLiveTranscriptState()
        var themState = MeetingLiveTranscriptState()

        meState.freezeCurrentItem(text: "me-one")
        themState.freezeCurrentItem(text: "them-one")

        XCTAssertEqual(meState.normalizedVisibleText(for: "me-one me-two"), "me-two")
        XCTAssertEqual(themState.normalizedVisibleText(for: "them-one them-two"), "them-two")
    }

    func testPreventAdjacentMergeBlocksFrozenLiveItemsFromMergingBack() {
        let previous = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 0,
            endSeconds: 1.0,
            text: "aaa",
            preventsAdjacentMerge: true
        )
        let next = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 1.3,
            endSeconds: 2.0,
            text: "bbb",
            preventsAdjacentMerge: true
        )

        XCTAssertNil(MeetingTranscriptFormatter.mergedAdjacentSegment(previous: previous, next: next))
    }
}

import XCTest
@testable import Voxt

final class RecordingSessionSupportTests: XCTestCase {
    func testFallbackInjectBundleIDRejectsOwnAppBundleID() {
        XCTAssertNil(
            RecordingSessionSupport.fallbackInjectBundleID(
                from: "com.voxt.Voxt.dev",
                ownBundleID: "com.voxt.Voxt.dev"
            )
        )
        XCTAssertEqual(
            RecordingSessionSupport.fallbackInjectBundleID(
                from: "com.apple.TextEdit",
                ownBundleID: "com.voxt.Voxt.dev"
            ),
            "com.apple.TextEdit"
        )
    }

    func testStopRecordingFallbackTimeoutUsesProviderSpecificRemoteBudget() {
        XCTAssertEqual(
            RecordingSessionSupport.stopRecordingFallbackTimeoutSeconds(
                transcriptionEngine: .whisperKit,
                remoteProvider: .openAIWhisper
            ),
            20
        )
        XCTAssertEqual(
            RecordingSessionSupport.stopRecordingFallbackTimeoutSeconds(
                transcriptionEngine: .remote,
                remoteProvider: .openAIWhisper
            ),
            60
        )
        XCTAssertEqual(
            RecordingSessionSupport.stopRecordingFallbackTimeoutSeconds(
                transcriptionEngine: .remote,
                remoteProvider: .doubaoASR
            ),
            8
        )
        XCTAssertEqual(
            RecordingSessionSupport.stopRecordingFallbackTimeoutSeconds(
                transcriptionEngine: .dictation,
                remoteProvider: .openAIWhisper
            ),
            8
        )
    }

    func testExtractTranscriptionTextValuePrefersKnownKeysAndNestedContent() {
        let payload: [String: Any] = [
            "metadata": ["ignored": true],
            "data": [
                "content": [
                    ["text": "  hello world  "]
                ]
            ]
        ]

        XCTAssertEqual(
            RecordingSessionSupport.extractTranscriptionTextValue(from: payload),
            "hello world"
        )
    }

    func testOutputLabelAndOverlayIconModeStayAligned() {
        XCTAssertEqual(RecordingSessionSupport.outputLabel(for: .transcription), "transcription")
        XCTAssertEqual(RecordingSessionSupport.overlayIconMode(for: .transcription), .transcription)
        XCTAssertEqual(RecordingSessionSupport.outputLabel(for: .translation), "translation")
        XCTAssertEqual(RecordingSessionSupport.overlayIconMode(for: .translation), .translation)
        XCTAssertEqual(RecordingSessionSupport.outputLabel(for: .rewrite), "rewrite")
        XCTAssertEqual(RecordingSessionSupport.overlayIconMode(for: .rewrite), .rewrite)
    }
}

import XCTest
@testable import Voxt

final class RecordingStartPlannerTests: XCTestCase {
    func testMLXAudioNotDownloadedBlocksRecordingStart() {
        let decision = RecordingStartPlanner.resolve(
            selectedEngine: .mlxAudio,
            mlxModelState: .notDownloaded,
            whisperModelState: .notDownloaded
        )

        XCTAssertEqual(decision, .blocked(.mlxModelNotInstalled))
    }

    func testMLXAudioErrorBlocksRecordingStart() {
        let decision = RecordingStartPlanner.resolve(
            selectedEngine: .mlxAudio,
            mlxModelState: .error("broken"),
            whisperModelState: .notDownloaded
        )

        XCTAssertEqual(decision, .blocked(.mlxModelUnavailable))
    }

    func testMLXAudioDownloadedStartsWithMLXAudio() {
        let decision = RecordingStartPlanner.resolve(
            selectedEngine: .mlxAudio,
            mlxModelState: .downloaded,
            whisperModelState: .notDownloaded
        )

        XCTAssertEqual(decision, .start(.mlxAudio))
    }

    func testMLXAudioDownloadingBlocksRecordingStart() {
        let decision = RecordingStartPlanner.resolve(
            selectedEngine: .mlxAudio,
            mlxModelState: .downloading(
                progress: 0.5,
                completed: 10,
                total: 20,
                currentFile: "weights.bin",
                completedFiles: 1,
                totalFiles: 2
            ),
            whisperModelState: .notDownloaded
        )

        XCTAssertEqual(decision, .blocked(.mlxModelDownloading))
    }

    func testDictationStartIgnoresMLXModelState() {
        let decision = RecordingStartPlanner.resolve(
            selectedEngine: .dictation,
            mlxModelState: .notDownloaded,
            whisperModelState: .notDownloaded
        )

        XCTAssertEqual(decision, .start(.dictation))
    }

    func testWhisperNotDownloadedBlocksRecordingStart() {
        let decision = RecordingStartPlanner.resolve(
            selectedEngine: .whisperKit,
            mlxModelState: .downloaded,
            whisperModelState: .notDownloaded
        )

        XCTAssertEqual(decision, .blocked(.whisperModelNotInstalled))
    }

    func testWhisperErrorBlocksRecordingStart() {
        let decision = RecordingStartPlanner.resolve(
            selectedEngine: .whisperKit,
            mlxModelState: .downloaded,
            whisperModelState: .error("broken")
        )

        XCTAssertEqual(decision, .blocked(.whisperModelUnavailable))
    }

    func testWhisperDownloadedStartsWithWhisperEngine() {
        let decision = RecordingStartPlanner.resolve(
            selectedEngine: .whisperKit,
            mlxModelState: .downloaded,
            whisperModelState: .downloaded
        )

        XCTAssertEqual(decision, .start(.whisperKit))
    }
}

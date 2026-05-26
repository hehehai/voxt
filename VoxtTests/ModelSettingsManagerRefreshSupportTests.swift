import XCTest
@testable import Voxt

@MainActor
final class ModelSettingsManagerRefreshSupportTests: XCTestCase {
    func testMLXPhaseIgnoresProgressPayloadChanges() {
        let phaseA = ModelSettingsManagerRefreshSupport.phase(
            for: MLXModelManager.ModelState.downloading(
                progress: 0.1,
                completed: 10,
                total: 100,
                currentFile: "a",
                completedFiles: 0,
                totalFiles: 2
            )
        )
        let phaseB = ModelSettingsManagerRefreshSupport.phase(
            for: MLXModelManager.ModelState.downloading(
                progress: 0.9,
                completed: 90,
                total: 100,
                currentFile: "b",
                completedFiles: 1,
                totalFiles: 2
            )
        )

        XCTAssertEqual(phaseA, ModelSettingsManagerActivityPhase.downloading)
        XCTAssertEqual(phaseA, phaseB)
    }

    func testWhisperDownloadDescriptorTracksIdentityAndPauseState() {
        let activeDownload = WhisperKitModelManager.ActiveDownload(
            modelID: "openai_whisper-large-v3-v20240930",
            isPaused: true,
            progress: 0.5,
            completed: 50,
            total: 100,
            currentFile: "weights.bin",
            currentFileCompleted: 25,
            currentFileTotal: 50,
            completedFiles: 1,
            totalFiles: 2
        )

        let descriptor = ModelSettingsManagerRefreshSupport.whisperDownloadDescriptor(for: activeDownload)

        XCTAssertEqual(
            descriptor,
            WhisperDownloadActivityDescriptor(
                modelID: "openai_whisper-large-v3-v20240930",
                isPaused: true
            )
        )
    }

    func testCustomLLMPhaseMapsPausedState() {
        let phase = ModelSettingsManagerRefreshSupport.phase(
            for: CustomLLMModelManager.ModelState.paused(
                progress: 0.4,
                completed: 40,
                total: 100,
                currentFile: "weights.safetensors",
                completedFiles: 1,
                totalFiles: 4
            )
        )

        XCTAssertEqual(phase, ModelSettingsManagerActivityPhase.paused)
    }

    func testDownloadLifecycleTokenIgnoresMLXRepoOrdering() {
        let tokenA = ModelSettingsManagerRefreshSupport.downloadLifecycleToken(
            mlxState: .paused(
                progress: 0.5,
                completed: 50,
                total: 100,
                currentFile: "weights.bin",
                completedFiles: 1,
                totalFiles: 2
            ),
            mlxActiveDownloadRepos: ["repo-b", "repo-a"],
            whisperState: .downloaded,
            whisperActiveDownload: nil,
            customLLMState: .downloaded
        )
        let tokenB = ModelSettingsManagerRefreshSupport.downloadLifecycleToken(
            mlxState: .paused(
                progress: 0.1,
                completed: 10,
                total: 100,
                currentFile: "other.bin",
                completedFiles: 0,
                totalFiles: 2
            ),
            mlxActiveDownloadRepos: ["repo-a", "repo-b"],
            whisperState: .ready,
            whisperActiveDownload: nil,
            customLLMState: .downloaded
        )

        XCTAssertEqual(tokenA, tokenB)
    }

    func testDownloadLifecycleTokenTracksWhisperPauseDescriptor() {
        let pausedDownload = WhisperKitModelManager.ActiveDownload(
            modelID: "openai_whisper-large-v3-v20240930",
            isPaused: true,
            progress: 0.2,
            completed: 20,
            total: 100,
            currentFile: "weights.bin",
            currentFileCompleted: 10,
            currentFileTotal: 50,
            completedFiles: 1,
            totalFiles: 2
        )
        let activeDownload = WhisperKitModelManager.ActiveDownload(
            modelID: "openai_whisper-large-v3-v20240930",
            isPaused: false,
            progress: 0.2,
            completed: 20,
            total: 100,
            currentFile: "weights.bin",
            currentFileCompleted: 10,
            currentFileTotal: 50,
            completedFiles: 1,
            totalFiles: 2
        )

        let pausedToken = ModelSettingsManagerRefreshSupport.downloadLifecycleToken(
            mlxState: .notDownloaded,
            mlxActiveDownloadRepos: [],
            whisperState: .paused(
                progress: 0.2,
                completed: 20,
                total: 100,
                currentFile: "weights.bin",
                completedFiles: 1,
                totalFiles: 2
            ),
            whisperActiveDownload: pausedDownload,
            customLLMState: .notDownloaded
        )
        let activeToken = ModelSettingsManagerRefreshSupport.downloadLifecycleToken(
            mlxState: .notDownloaded,
            mlxActiveDownloadRepos: [],
            whisperState: .downloading(
                progress: 0.2,
                completed: 20,
                total: 100,
                currentFile: "weights.bin",
                completedFiles: 1,
                totalFiles: 2
            ),
            whisperActiveDownload: activeDownload,
            customLLMState: .notDownloaded
        )

        XCTAssertNotEqual(pausedToken, activeToken)
    }
}

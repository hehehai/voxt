import XCTest
@testable import Voxt

final class ModelDownloadStateRoutingTests: XCTestCase {
    func testMLXDownloadRoutingTracksActiveDownloadRepo() {
        let targetRepo = "mlx-community/Qwen3-ASR-0.6B-4bit"
        let otherRepo = "mlx-community/parakeet-tdt-0.6b-v3"
        let state = MLXModelManager.ModelState.downloading(
            progress: 0.5,
            completed: 50,
            total: 100,
            currentFile: "weights",
            completedFiles: 1,
            totalFiles: 2
        )

        XCTAssertTrue(
            ModelDownloadStateRouting.isMLXDownloading(
                repo: targetRepo,
                activeRepo: targetRepo,
                state: state
            )
        )
        XCTAssertTrue(
            ModelDownloadStateRouting.isAnotherMLXDownloadActive(
                repo: otherRepo,
                activeRepo: targetRepo,
                state: state
            )
        )
        XCTAssertFalse(
            ModelDownloadStateRouting.isAnotherMLXDownloadActive(
                repo: targetRepo,
                activeRepo: targetRepo,
                state: state
            )
        )
    }

    func testCustomLLMDownloadRoutingTracksManagerCurrentRepoInsteadOfSelectedRepo() {
        let targetRepo = "mlx-community/Qwen3-4B-4bit"
        let otherRepo = "mlx-community/Qwen3-8B-4bit"
        let state = CustomLLMModelManager.ModelState.downloading(
            progress: 0.25,
            completed: 25,
            total: 100,
            currentFile: "model.safetensors",
            completedFiles: 1,
            totalFiles: 4
        )

        XCTAssertTrue(
            ModelDownloadStateRouting.isCustomLLMDownloading(
                repo: targetRepo,
                managerRepo: targetRepo,
                state: state
            )
        )
        XCTAssertTrue(
            ModelDownloadStateRouting.isAnotherCustomLLMDownloadActive(
                repo: otherRepo,
                managerRepo: targetRepo,
                state: state
            )
        )
        XCTAssertFalse(
            ModelDownloadStateRouting.isAnotherCustomLLMDownloadActive(
                repo: targetRepo,
                managerRepo: targetRepo,
                state: state
            )
        )
    }

    func testPausedRoutingMatchesManagerOperationTarget() {
        let mlxState = MLXModelManager.ModelState.paused(
            progress: 0.8,
            completed: 80,
            total: 100,
            currentFile: "weights",
            completedFiles: 3,
            totalFiles: 4
        )
        let llmState = CustomLLMModelManager.ModelState.paused(
            progress: 0.8,
            completed: 80,
            total: 100,
            currentFile: "weights",
            completedFiles: 3,
            totalFiles: 4
        )

        XCTAssertTrue(
            ModelDownloadStateRouting.isMLXPaused(
                repo: "mlx-community/Qwen3-ASR-0.6B-4bit",
                activeRepo: "mlx-community/Qwen3-ASR-0.6B-4bit",
                state: mlxState
            )
        )
        XCTAssertTrue(
            ModelDownloadStateRouting.isCustomLLMPaused(
                repo: "mlx-community/Qwen3-4B-4bit",
                managerRepo: "mlx-community/Qwen3-4B-4bit",
                state: llmState
            )
        )
    }
}

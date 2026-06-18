// SettingsModelDownloadBadgeSupportTests.swift
// Provides Settings Model Download Badge Support Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class SettingsModelDownloadBadgeSupportTests: XCTestCase {
    func testActiveDownloadCountTracksConcurrentMLXDownloads() {
        let count = SettingsModelDownloadBadgeSupport.activeDownloadCount(
            mlxActiveDownloadRepos: [
                MLXModelManager.canonicalModelRepo("openai/whisper-tiny"),
                MLXModelManager.canonicalModelRepo("mlx-community/FireRedASR")
            ],
            whisperActiveDownload: nil,
            customLLMState: .notDownloaded,
            ggufActiveDownloadModelID: nil
        )

        XCTAssertEqual(count, 2)
    }

    func testActiveDownloadCountKeepsRemainingMLXDownloadAfterCancelingAnother() {
        let count = SettingsModelDownloadBadgeSupport.activeDownloadCount(
            mlxActiveDownloadRepos: [
                MLXModelManager.canonicalModelRepo("mlx-community/FireRedASR")
            ],
            whisperActiveDownload: nil,
            customLLMState: .notDownloaded,
            ggufActiveDownloadModelID: nil
        )

        XCTAssertEqual(count, 1)
    }

    func testActiveDownloadCountIgnoresPausedWhisperDownload() {
        let whisperDownload = WhisperKitModelManager.ActiveDownload(
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

        let count = SettingsModelDownloadBadgeSupport.activeDownloadCount(
            mlxActiveDownloadRepos: [],
            whisperActiveDownload: whisperDownload,
            customLLMState: .notDownloaded,
            ggufActiveDownloadModelID: nil
        )

        XCTAssertEqual(count, 0)
    }
}

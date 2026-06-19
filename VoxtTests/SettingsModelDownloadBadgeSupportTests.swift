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
            customLLMState: .notDownloaded,
            ggufActiveDownloadModelID: nil
        )

        XCTAssertEqual(count, 1)
    }
}

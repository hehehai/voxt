// ModelSettingsProgressRefreshSupportTests.swift
// Provides Model Settings Progress Refresh Support Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class ModelSettingsProgressRefreshSupportTests: XCTestCase {
    func testShouldRefreshCatalogForLifecycleChangeOnlyWhenActiveAndVisible() {
        XCTAssertTrue(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForLifecycleChange(
                isActive: true,
                isWindowVisible: true
            )
        )
        XCTAssertFalse(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForLifecycleChange(
                isActive: false,
                isWindowVisible: true
            )
        )
        XCTAssertFalse(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForLifecycleChange(
                isActive: true,
                isWindowVisible: false
            )
        )
    }

    func testShouldRefreshCatalogForMetadataChangeOnlyWhenActiveVisibleAndPolling() {
        XCTAssertTrue(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForMetadataChange(
                isActive: true,
                isWindowVisible: true,
                shouldPollModelState: true
            )
        )
        XCTAssertFalse(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForMetadataChange(
                isActive: false,
                isWindowVisible: true,
                shouldPollModelState: true
            )
        )
        XCTAssertFalse(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForMetadataChange(
                isActive: true,
                isWindowVisible: false,
                shouldPollModelState: true
            )
        )
        XCTAssertFalse(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForMetadataChange(
                isActive: true,
                isWindowVisible: true,
                shouldPollModelState: false
            )
        )
    }

    func testShouldPollModelStateWhenNonCurrentMLXDownloadIsActive() {
        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .notDownloaded,
            mlxHasActiveDownloadingRepos: true,
            whisperState: .notDownloaded,
            whisperActiveDownload: nil,
            customLLMState: .notDownloaded
        )

        XCTAssertTrue(shouldPoll)
    }

    func testShouldPollModelStateForActiveWhisperDownload() {
        let whisperDownload = WhisperKitModelManager.ActiveDownload(
            modelID: "openai_whisper-large-v3-v20240930",
            isPaused: false,
            progress: 0.5,
            completed: 50,
            total: 100,
            currentFile: "weights.bin",
            currentFileCompleted: 25,
            currentFileTotal: 50,
            completedFiles: 1,
            totalFiles: 2
        )

        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .notDownloaded,
            mlxHasActiveDownloadingRepos: false,
            whisperState: .notDownloaded,
            whisperActiveDownload: whisperDownload,
            customLLMState: .notDownloaded
        )

        XCTAssertTrue(shouldPoll)
    }

    func testShouldNotPollModelStateWithoutActiveDownloads() {
        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .downloaded,
            mlxHasActiveDownloadingRepos: false,
            whisperState: .downloaded,
            whisperActiveDownload: nil,
            customLLMState: .downloaded
        )

        XCTAssertFalse(shouldPoll)
    }

    func testShouldNotPollModelStateForLoadingWithoutActiveDownloads() {
        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .loading,
            mlxHasActiveDownloadingRepos: false,
            whisperState: .loading,
            whisperActiveDownload: nil,
            customLLMState: .notDownloaded
        )

        XCTAssertFalse(shouldPoll)
    }

    func testShouldNotPollModelStateForPausedMLXWhileCancellationStillCleansUp() {
        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .paused(
                progress: 0.5,
                completed: 50,
                total: 100,
                currentFile: "weights.bin",
                completedFiles: 1,
                totalFiles: 2
            ),
            mlxHasActiveDownloadingRepos: false,
            whisperState: .notDownloaded,
            whisperActiveDownload: nil,
            customLLMState: .notDownloaded
        )

        XCTAssertFalse(shouldPoll)
    }
}

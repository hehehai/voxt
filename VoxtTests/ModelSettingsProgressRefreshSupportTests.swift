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
            customLLMState: .notDownloaded,
            ggufStateByID: [:],
            ggufActiveDownloadModelID: nil
        )

        XCTAssertTrue(shouldPoll)
    }

    func testShouldNotPollModelStateWithoutActiveDownloads() {
        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .downloaded,
            mlxHasActiveDownloadingRepos: false,
            customLLMState: .downloaded,
            ggufStateByID: [:],
            ggufActiveDownloadModelID: nil
        )

        XCTAssertFalse(shouldPoll)
    }

    func testShouldNotPollModelStateForLoadingWithoutActiveDownloads() {
        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .loading,
            mlxHasActiveDownloadingRepos: false,
            customLLMState: .notDownloaded,
            ggufStateByID: [:],
            ggufActiveDownloadModelID: nil
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
            customLLMState: .notDownloaded,
            ggufStateByID: [:],
            ggufActiveDownloadModelID: nil
        )

        XCTAssertFalse(shouldPoll)
    }
}

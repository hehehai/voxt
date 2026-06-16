// ModelDownloadStatusSnapshotTests.swift
// Provides Model Download Status Snapshot Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class ModelDownloadStatusSnapshotTests: XCTestCase {
    func testMLXDownloadingSnapshotDoesNotShowHundredPercentBeforeDownloadFinishes() {
        let snapshot = ModelDownloadStatusSnapshot.fromMLXState(
            .downloading(
                progress: 1,
                completed: 100,
                total: 100,
                currentFile: nil,
                completedFiles: 9,
                totalFiles: 9
            )
        )

        XCTAssertNotNil(snapshot)
        XCTAssertTrue(snapshot?.titleText.contains("99%") == true)
        XCTAssertFalse(snapshot?.titleText.contains("100%") == true)
    }

    func testFinalizingDownloadUsesFinalizingDetailCopy() {
        let text = ModelDownloadProgressFormatter.fileProgressText(
            currentFile: nil,
            completedFiles: 9,
            totalFiles: 9
        )

        let filesText = AppLocalization.format("%d/%d files", 9, 9)
        XCTAssertEqual(text, AppLocalization.format("Finalizing download… (%@)", filesText))
    }
}

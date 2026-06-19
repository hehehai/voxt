// WhisperKitModelSupportTests.swift
// Provides Whisper Kit Model Support Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class WhisperKitModelSupportTests: XCTestCase {
    func testCanonicalModelIDFallsBackToDefaultForUnknownModel() {
        XCTAssertEqual(
            WhisperKitModelCatalog.canonicalModelID("unknown-model"),
            WhisperKitModelCatalog.defaultModelID
        )
    }

    func testDisplayTitleFallsBackToCanonicalModelID() {
        XCTAssertEqual(WhisperKitModelCatalog.displayTitle(for: "base"), "Whisper Base")
        XCTAssertEqual(
            WhisperKitModelCatalog.displayTitle(for: "unknown-model"),
            "Whisper Small"
        )
    }

    func testAllCuratedWhisperModelsHaveFallbackSizes() {
        let missingModelIDs = WhisperKitModelCatalog.supportedModels
            .map(\.id)
            .filter { WhisperKitModelCatalog.fallbackRemoteSizeText(id: $0) == nil }

        XCTAssertEqual(missingModelIDs, [])
    }

    func testAvailableWhisperModelsHideTinyAndBase() {
        let availableIDs = Set(WhisperKitModelCatalog.availableModels.map(\.id))
        let supportedIDs = Set(WhisperKitModelCatalog.supportedModels.map(\.id))

        XCTAssertEqual(availableIDs, ["small", "medium", "large-v3"])
        XCTAssertTrue(supportedIDs.contains("tiny"))
        XCTAssertTrue(supportedIDs.contains("base"))
    }

    func testHiddenWhisperModelsDisplayWhenIncludedByLocalState() {
        XCTAssertFalse(
            WhisperKitModelCatalog.displayModels(includingInstalled: []).contains { $0.id == "base" }
        )
        XCTAssertTrue(
            WhisperKitModelCatalog.displayModels(includingInstalled: ["base"]).contains { $0.id == "base" }
        )
    }

    func testTopLevelFolderNameUsesCanonicalModelID() {
        XCTAssertEqual(
            WhisperKitModelCatalog.topLevelFolderName(for: "base"),
            "openai_whisper-base"
        )
        XCTAssertEqual(
            WhisperKitModelCatalog.topLevelFolderName(for: "unknown-model"),
            "openai_whisper-\(WhisperKitModelCatalog.defaultModelID)"
        )
    }
}

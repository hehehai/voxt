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
            "Whisper Base"
        )
    }

    func testAllCuratedWhisperModelsHaveFallbackSizes() {
        let missingModelIDs = WhisperKitModelCatalog.availableModels
            .map(\.id)
            .filter { WhisperKitModelCatalog.fallbackRemoteSizeText(id: $0) == nil }

        XCTAssertEqual(missingModelIDs, [])
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

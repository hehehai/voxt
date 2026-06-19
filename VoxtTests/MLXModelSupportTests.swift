// MLXModelSupportTests.swift
// Provides MLXModel Support Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class MLXModelSupportTests: XCTestCase {
    func testCanonicalModelRepoMapsLegacyRepos() {
        XCTAssertEqual(
            MLXModelCatalog.canonicalModelRepo("mlx-community/Parakeet-0.6B"),
            "mlx-community/parakeet-tdt-0.6b-v3"
        )
        XCTAssertEqual(
            MLXModelCatalog.canonicalModelRepo("mlx-community/FireRedASR2"),
            "mlx-community/FireRedASR2-AED-mlx"
        )
        XCTAssertEqual(
            MLXModelCatalog.canonicalModelRepo("mlx-community/Qwen3-ASR-0.6B-4bit"),
            "mlx-community/Qwen3-ASR-0.6B-4bit"
        )
    }

    func testRealtimeCapabilityUsesCanonicalizedRepo() {
        XCTAssertTrue(
            MLXModelCatalog.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602")
        )
        XCTAssertTrue(
            MLXModelCatalog.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-6bit")
        )
        XCTAssertFalse(
            MLXModelCatalog.isRealtimeCapableModelRepo("mlx-community/Qwen3-ASR-0.6B-4bit")
        )
    }

    func testLiveModeUsesNativeSessionForQwen3AndNemotronASR() {
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/Qwen3-ASR-0.6B-4bit"),
            .nativeQwenLive
        )
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/Qwen3-ASR-1.7B-6bit"),
            .nativeQwenLive
        )
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"),
            .nativeNemotronLive
        )
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"),
            .batchPreview
        )
    }

    func testQwen3CatalogTagsExposeRealtimeBadge() {
        XCTAssertTrue(
            MLXModelCatalog.catalogTagKeys(for: "mlx-community/Qwen3-ASR-0.6B-4bit").contains("Realtime")
        )
        XCTAssertTrue(
            MLXModelCatalog.catalogTagKeys(for: "mlx-community/Qwen3-ASR-1.7B-6bit").contains("Realtime")
        )
    }

    func testFallbackRemoteSizeSupportsLegacyAndCuratedRepos() {
        XCTAssertEqual(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/FireRedASR2"),
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/FireRedASR2-AED-mlx")
        )
        XCTAssertNotNil(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/Qwen3-ASR-0.6B-4bit")
        )
        XCTAssertNotNil(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/whisper-large-v3-turbo")
        )
        XCTAssertNotNil(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/whisper-small-mlx")
        )
    }

    func testWhisperMigrationMapsLegacyModelIDsToMLXRepos() {
        XCTAssertEqual(
            MLXWhisperMigrationSupport.repo(forLegacyWhisperModelID: "tiny"),
            "mlx-community/whisper-tiny-mlx"
        )
        XCTAssertEqual(
            MLXWhisperMigrationSupport.repo(forLegacyWhisperModelID: "base"),
            "mlx-community/whisper-base-mlx"
        )
        XCTAssertEqual(
            MLXWhisperMigrationSupport.repo(forLegacyWhisperModelID: "medium"),
            "mlx-community/whisper-large-v3-turbo"
        )
        XCTAssertTrue(
            MLXWhisperMigrationSupport.isWhisperRepo("mlx-community/whisper-large-v3-turbo")
        )
    }

    func testTinyAndBaseWhisperReposAreHiddenUnlessInstalled() {
        let defaultDisplayRepos = Set(MLXModelCatalog.displayModels(includingInstalled: []).map(\.id))

        XCTAssertFalse(defaultDisplayRepos.contains("mlx-community/whisper-tiny-mlx"))
        XCTAssertFalse(defaultDisplayRepos.contains("mlx-community/whisper-base-mlx"))

        let displayReposIncludingInstalled = Set(
            MLXModelCatalog.displayModels(includingInstalled: ["mlx-community/whisper-base-mlx"]).map(\.id)
        )

        XCTAssertTrue(displayReposIncludingInstalled.contains("mlx-community/whisper-base-mlx"))
    }
}

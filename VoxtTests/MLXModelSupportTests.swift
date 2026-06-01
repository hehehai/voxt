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

    func testLiveModeUsesNativeSessionOnlyForQwen3ASR() {
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/Qwen3-ASR-0.6B-4bit"),
            .nativeQwenLive
        )
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/Qwen3-ASR-1.7B-6bit"),
            .nativeQwenLive
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
    }
}

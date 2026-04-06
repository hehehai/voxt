import XCTest
@testable import Voxt

@MainActor
final class MLXModelManagerTests: XCTestCase {
    func testCanonicalModelRepoMapsLegacyReposToCurrentIdentifiers() {
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/Parakeet-0.6B"),
            "mlx-community/parakeet-tdt-0.6b-v3"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/GLM-ASR-Nano-4bit"),
            "mlx-community/GLM-ASR-Nano-2512-4bit"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602"),
            "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/FireRedASR2"),
            "mlx-community/FireRedASR2-AED-mlx"
        )
    }

    func testRealtimeCapableModelRepoTreatsAllVoxtralQuantizationsAsRealtime() {
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-6bit"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"))
        XCTAssertFalse(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Qwen3-ASR-0.6B-4bit"))
    }

    func testAvailableModelsIncludeLatestSupportedSTTRepos() {
        let modelIDs = Set(MLXModelManager.availableModels.map(\.id))

        XCTAssertTrue(modelIDs.contains("mlx-community/parakeet-tdt-0.6b-v2"))
        XCTAssertTrue(modelIDs.contains("mlx-community/granite-4.0-1b-speech-5bit"))
        XCTAssertTrue(modelIDs.contains("mlx-community/FireRedASR2-AED-mlx"))
        XCTAssertTrue(modelIDs.contains("mlx-community/SenseVoiceSmall"))
    }
}

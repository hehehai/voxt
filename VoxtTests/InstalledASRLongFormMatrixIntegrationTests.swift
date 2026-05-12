import XCTest
@testable import Voxt

@MainActor
final class InstalledASRLongFormMatrixIntegrationTests: XCTestCase {
    private struct ClipCase {
        let path: String
        let minimumReasonableCharacters: Int
        let maximumReasonableCharacters: Int
    }

    private func skipIfCI() throws {
        let env = ProcessInfo.processInfo.environment
        if env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" {
            throw XCTSkip("Installed-model matrix integration tests are local-only and are skipped on CI.")
        }
    }

    private func officialFixtureDirectoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/qwen-official", isDirectory: true)
    }

    private func officialFixturePath(named fileName: String) -> String? {
        let path = officialFixtureDirectoryURL().appendingPathComponent(fileName).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func longFormClips() -> [ClipCase] {
        let preferred = [
            ClipCase(
                path: officialFixturePath(named: "qwen_audio_long_en_composite.wav") ?? "",
                minimumReasonableCharacters: 80,
                maximumReasonableCharacters: 8000
            ),
            ClipCase(
                path: officialFixturePath(named: "qwen_audio_long_zh_composite.wav") ?? "",
                minimumReasonableCharacters: 40,
                maximumReasonableCharacters: 8000
            ),
            ClipCase(
                path: "/Users/guanwei/Library/Application Support/Voxt/transcription-history-audio/transcription/transcription-6247D986-B2EC-4758-AB40-7C1030296D7A.wav",
                minimumReasonableCharacters: 40,
                maximumReasonableCharacters: 5000
            ),
            ClipCase(
                path: "/Users/guanwei/Library/Application Support/Voxt/transcription-history-audio/transcription/transcription-FD3C99FC-822F-45DB-8734-FFADEF6DC6EE.wav",
                minimumReasonableCharacters: 40,
                maximumReasonableCharacters: 4000
            )
        ]
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        var seen = Set<String>()
        return preferred.filter { seen.insert($0.path).inserted }
    }

    private func configuredHubURL() -> URL {
        let defaults = UserDefaults.standard
        defaults.set("/Users/guanwei/x/models", forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)
        return defaults.bool(forKey: AppPreferenceKey.useHfMirror)
            ? MLXModelManager.mirrorHubBaseURL
            : MLXModelManager.defaultHubBaseURL
    }

    private func installedWhisperModelIDs() -> [String] {
        let hubURL = configuredHubURL()
        let probeManager = WhisperKitModelManager(modelID: WhisperKitModelManager.defaultModelID, hubBaseURL: hubURL)
        return WhisperKitModelManager.availableModels
            .map(\.id)
            .map(WhisperKitModelManager.canonicalModelID(_:))
            .filter { probeManager.isModelDownloaded(id: $0) }
    }

    private func installedMultilingualMLXRepos() -> [String] {
        let hubURL = configuredHubURL()
        let probeManager = MLXModelManager(modelRepo: MLXModelManager.defaultModelRepo, hubBaseURL: hubURL)
        return MLXModelManager.availableModels
            .map(\.id)
            .map(MLXModelManager.canonicalModelRepo(_:))
            .filter { MLXModelManager.isMultilingualModelRepo($0) }
            .filter { probeManager.isModelDownloaded(repo: $0) }
    }

    func testInstalledWhisperModelsProduceReasonableLongFormResults() async throws {
        try skipIfCI()
        let clips = longFormClips()
        guard !clips.isEmpty else {
            throw XCTSkip("No long-form clips are available for installed-model matrix testing.")
        }

        let modelIDs = installedWhisperModelIDs()
        guard !modelIDs.isEmpty else {
            throw XCTSkip("No downloaded Whisper models are available for installed-model matrix testing.")
        }

        let hubURL = configuredHubURL()

        for modelID in modelIDs {
            let transcriber = WhisperKitTranscriber(
                modelManager: WhisperKitModelManager(modelID: modelID, hubBaseURL: hubURL)
            )
            for clip in clips {
                let text = try await transcriber.transcribeAudioFile(URL(fileURLWithPath: clip.path))
                let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
                print("ASR_MATRIX whisper \(modelID) \(clip.path) chars=\(count)")
                XCTAssertGreaterThan(
                    count,
                    clip.minimumReasonableCharacters,
                    "Whisper model \(modelID) collapsed on long-form clip \(clip.path)"
                )
                XCTAssertLessThan(
                    count,
                    clip.maximumReasonableCharacters,
                    "Whisper model \(modelID) ballooned on long-form clip \(clip.path)"
                )
            }
        }
    }

    func testInstalledMultilingualMLXModelsProduceReasonableLongFormResults() async throws {
        try skipIfCI()
        let clips = longFormClips()
        guard !clips.isEmpty else {
            throw XCTSkip("No long-form clips are available for installed-model matrix testing.")
        }

        let repos = installedMultilingualMLXRepos()
        guard !repos.isEmpty else {
            throw XCTSkip("No downloaded multilingual MLX ASR models are available for installed-model matrix testing.")
        }

        let hubURL = configuredHubURL()

        for repo in repos {
            let transcriber = MLXTranscriber(
                modelManager: MLXModelManager(modelRepo: repo, hubBaseURL: hubURL)
            )
            for clip in clips {
                let text = try await transcriber.transcribeAudioFile(URL(fileURLWithPath: clip.path))
                let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
                print("ASR_MATRIX mlx \(repo) \(clip.path) chars=\(count)")
                XCTAssertGreaterThan(
                    count,
                    clip.minimumReasonableCharacters,
                    "MLX model \(repo) collapsed on long-form clip \(clip.path)"
                )
                XCTAssertLessThan(
                    count,
                    clip.maximumReasonableCharacters,
                    "MLX model \(repo) ballooned on long-form clip \(clip.path)"
                )
            }
        }
    }
}

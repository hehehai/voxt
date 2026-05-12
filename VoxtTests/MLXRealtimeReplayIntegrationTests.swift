import XCTest
@testable import Voxt

@MainActor
final class MLXRealtimeReplayIntegrationTests: XCTestCase {
    private let minimumLongFormDurationSeconds = 30.0

    private func skipIfCI() throws {
        let env = ProcessInfo.processInfo.environment
        if env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" {
            throw XCTSkip("Official audio fixture integration tests are local-only and are skipped on CI.")
        }
    }

    private func officialFixtureDirectoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/qwen-official", isDirectory: true)
    }

    private func fixtureURL(named fileName: String) throws -> URL {
        let url = officialFixtureDirectoryURL().appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing official audio fixture: \(fileName)")
        }
        return url
    }

    private func resolvedModelRepoAndHubURL() throws -> (repo: String, hubURL: URL) {
        let defaults = UserDefaults.standard
        defaults.set("/Users/guanwei/x/models", forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)
        let hubURL = defaults.bool(forKey: AppPreferenceKey.useHfMirror)
            ? MLXModelManager.mirrorHubBaseURL
            : MLXModelManager.defaultHubBaseURL

        let preferredRepo = MLXModelManager.canonicalModelRepo(
            defaults.string(forKey: AppPreferenceKey.mlxModelRepo) ?? MLXModelManager.defaultModelRepo
        )
        let probeManager = MLXModelManager(modelRepo: preferredRepo, hubBaseURL: hubURL)
        if probeManager.isModelDownloaded(repo: preferredRepo),
           MLXModelManager.isMultilingualModelRepo(preferredRepo) {
            return (preferredRepo, hubURL)
        }

        guard let fallbackRepo = MLXModelManager.availableModels
            .map(\.id)
            .map(MLXModelManager.canonicalModelRepo(_:))
            .first(where: {
                MLXModelManager.isMultilingualModelRepo($0) &&
                    probeManager.isModelDownloaded(repo: $0)
            }) else {
            throw XCTSkip("No downloaded multilingual MLX ASR model is available for realtime replay regression.")
        }
        return (fallbackRepo, hubURL)
    }

    private func makeTranscriber() throws -> MLXTranscriber {
        let resolved = try resolvedModelRepoAndHubURL()
        return MLXTranscriber(
            modelManager: MLXModelManager(modelRepo: resolved.repo, hubBaseURL: resolved.hubURL)
        )
    }

    func testReplayOfficialShortFixtureProducesLiveAndFinalEvents() async throws {
        try skipIfCI()
        let transcriber = try makeTranscriber()
        let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(
            fixtureURL(named: "qwen_audio_short_zh_chongqing.wav"),
            stepSeconds: 1.5
        )

        XCTAssertFalse(diagnostics.events.isEmpty)
        XCTAssertTrue(diagnostics.events.contains(where: { !$0.isFinal }))
        XCTAssertTrue(diagnostics.events.contains(where: \.isFinal))
    }

    func testReplayOfficialLongFixtureKeepsPublishingIntoLaterPortion() async throws {
        try skipIfCI()
        let clipURL = try fixtureURL(named: "qwen_audio_long_zh_composite.wav")
        let transcriber = try makeTranscriber()

        let clip = try DebugAudioClipIO.clip(for: clipURL)
        XCTAssertGreaterThanOrEqual(clip.durationSeconds, minimumLongFormDurationSeconds)

        let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(
            clipURL,
            stepSeconds: 4.0
        )
        let finalEvent = try XCTUnwrap(diagnostics.events.last(where: { $0.isFinal }))
        let liveEvents = diagnostics.events.filter { !$0.isFinal }
        let liveTexts = liveEvents
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        XCTAssertGreaterThanOrEqual(liveTexts.count, 3, "Expected several progressive MLX live updates.")

        let latestLiveTime = liveEvents.map(\.elapsedSeconds).max() ?? 0
        XCTAssertGreaterThanOrEqual(
            latestLiveTime,
            finalEvent.elapsedSeconds * 0.75,
            "MLX realtime replay should keep publishing updates into the later portion of the clip."
        )
    }

    func testReplayOfficialLongFixturePublishesStopPreviewBeforeFinal() async throws {
        try skipIfCI()
        let clipURL = try fixtureURL(named: "qwen_audio_long_en_composite.wav")
        let transcriber = try makeTranscriber()

        let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(
            clipURL,
            stepSeconds: 4.0
        )
        let finalEvent = try XCTUnwrap(diagnostics.events.last(where: { $0.isFinal }))

        XCTAssertTrue(
            diagnostics.events.contains(where: { !$0.isFinal && $0.source == "post-stop-quick" }),
            "Expected MLX realtime replay to publish a post-stop quick preview before the final transcript."
        )
        XCTAssertFalse(finalEvent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

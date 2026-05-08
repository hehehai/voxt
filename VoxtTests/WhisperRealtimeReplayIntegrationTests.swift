import XCTest
@testable import Voxt

@MainActor
final class WhisperRealtimeReplayIntegrationTests: XCTestCase {
    private func resolvedReplayClipPath() -> String {
        let overridePathFile = "/tmp/voxt-realtime-replay-clip-path.txt"
        let overridePath = try? String(contentsOfFile: overridePathFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessInfo.processInfo.environment["VOXT_REALTIME_REPLAY_CLIP"]
            ?? overridePath
            ?? "/Users/guanwei/Downloads/transcription/20260507-123725-transcription-CF5D4F69-31F4-4F86-ADCA-18029BDB0EE8.wav"
    }

    private func resolvedPauseAwareClipPath() throws -> String {
        let candidates = [
            ProcessInfo.processInfo.environment["VOXT_REALTIME_PAUSE_REPLAY_CLIP"],
            "/Users/guanwei/Downloads/transcription/transcription-0A0E87B1-7C9A-4BB6-8469-E18485A63103.wav",
            "/Users/guanwei/Downloads/transcription/20260507-123725-transcription-CF5D4F69-31F4-4F86-ADCA-18029BDB0EE8.wav"
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }

        guard let clipPath = candidates.first else {
            throw XCTSkip("No pause-aware realtime replay clip is available.")
        }
        return clipPath
    }

    private func resolvedModelManager() throws -> (modelID: String, manager: WhisperKitModelManager) {
        let defaults = UserDefaults.standard
        defaults.set("/Users/guanwei/x/models", forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)
        let hubURL = defaults.bool(forKey: AppPreferenceKey.useHfMirror)
            ? MLXModelManager.mirrorHubBaseURL
            : MLXModelManager.defaultHubBaseURL
        let preferredModelID = defaults.string(forKey: AppPreferenceKey.whisperModelID) ?? WhisperKitModelManager.defaultModelID
        let candidateModelIDs = [preferredModelID, "large-v3", "small", "base"] + WhisperKitModelManager.availableModels.map(\.id)
        let probeManager = WhisperKitModelManager(modelID: preferredModelID, hubBaseURL: hubURL)
        guard let chosenModelID = candidateModelIDs
            .map(WhisperKitModelManager.canonicalModelID(_:))
            .first(where: { probeManager.isModelDownloaded(id: $0) }) else {
            throw XCTSkip("No downloaded Whisper model is available for realtime replay.")
        }
        return (chosenModelID, WhisperKitModelManager(modelID: chosenModelID, hubBaseURL: hubURL))
    }

    func testReplayProvidedClipProducesLiveAndFinalEvents() async throws {
        let clipPath = resolvedReplayClipPath()
        let clipURL = URL(fileURLWithPath: clipPath)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: clipURL.path),
            "Replay clip is missing: \(clipURL.path)"
        )

        let resolved = try resolvedModelManager()

        let transcriber = WhisperKitTranscriber(modelManager: resolved.manager)
        let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(clipURL)
        let events = diagnostics.events

        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.contains(where: { !$0.isFinal }))
        XCTAssertTrue(events.contains(where: \.isFinal))
    }

    func testReplayPauseAwareClipKeepsPublishingIntoLaterPortion() async throws {
        let clipPath = try resolvedPauseAwareClipPath()
        let clipURL = URL(fileURLWithPath: clipPath)
        let resolved = try resolvedModelManager()
        let transcriber = WhisperKitTranscriber(modelManager: resolved.manager)

        let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(clipURL)
        let events = diagnostics.events
        let finalEvent = try XCTUnwrap(events.last(where: { $0.isFinal }))
        let liveEvents = events.filter { !$0.isFinal }
        let liveTexts = liveEvents
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        XCTAssertGreaterThanOrEqual(liveTexts.count, 3, "Expected several progressive live updates.")

        let latestLiveTime = liveEvents.map(\.elapsedSeconds).max() ?? 0
        XCTAssertGreaterThanOrEqual(
            latestLiveTime,
            finalEvent.elapsedSeconds * 0.75,
            "Realtime replay should keep publishing updates into the later portion of the clip, including after pauses."
        )

        if let silenceFlushIndex = liveEvents.firstIndex(where: { $0.source == "silence-flush" }),
           silenceFlushIndex > 0 {
            let previousEvent = liveEvents[silenceFlushIndex - 1]
            let silenceFlushEvent = liveEvents[silenceFlushIndex]
            XCTAssertLessThanOrEqual(
                silenceFlushEvent.elapsedSeconds - previousEvent.elapsedSeconds,
                1.0,
                "Pause handling should flush the previous phrase quickly instead of leaving the last words pending for about a second."
            )
        }

        XCTAssertFalse(finalEvent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

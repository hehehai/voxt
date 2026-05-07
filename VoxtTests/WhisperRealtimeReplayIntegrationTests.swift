import XCTest
@testable import Voxt

@MainActor
final class WhisperRealtimeReplayIntegrationTests: XCTestCase {
    func testReplayProvidedClip() async throws {
        let overridePathFile = "/tmp/voxt-realtime-replay-clip-path.txt"
        let overridePath = try? String(contentsOfFile: overridePathFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipPath = ProcessInfo.processInfo.environment["VOXT_REALTIME_REPLAY_CLIP"]
            ?? overridePath
            ?? "/Users/guanwei/Downloads/transcription/20260507-123725-transcription-CF5D4F69-31F4-4F86-ADCA-18029BDB0EE8.wav"
        let clipURL = URL(fileURLWithPath: clipPath)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: clipURL.path),
            "Replay clip is missing: \(clipURL.path)"
        )

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
        let modelManager = WhisperKitModelManager(modelID: chosenModelID, hubBaseURL: hubURL)

        let transcriber = WhisperKitTranscriber(modelManager: modelManager)
        let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(clipURL)
        let events = diagnostics.events

        print("REALTIME_REPLAY_MODEL=\(chosenModelID)")
        print("REALTIME_REPLAY_CLIP=\(clipURL.path)")
        print("REALTIME_REPLAY_TRACE_BEGIN")
        diagnostics.trace.forEach { print($0) }
        print("REALTIME_REPLAY_TRACE_END")
        print("REALTIME_REPLAY_BEGIN")
        for event in events {
            let phase = event.isFinal ? "final" : "live"
            print(
                String(
                    format: "[%.1fs] %@/%@: %@ | raw=%@",
                    event.elapsedSeconds,
                    phase,
                    event.source,
                    event.text,
                    event.rawText
                )
            )
        }
        print("REALTIME_REPLAY_END")

        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.contains(where: { !$0.isFinal }))
        XCTAssertTrue(events.contains(where: \.isFinal))
    }
}

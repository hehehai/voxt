import XCTest
@testable import Voxt

@MainActor
final class WhisperLongFormReplayIntegrationTests: XCTestCase {
    private let minimumLongFormDurationSeconds = WhisperKitTranscriber.realtimeLongFormFinalProfileThresholdSeconds

    private func resolvedCandidateClipPaths() -> [String] {
        let overridePathFile = "/tmp/voxt-longform-replay-clip-path.txt"
        let overridePath = try? String(contentsOfFile: overridePathFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            ProcessInfo.processInfo.environment["VOXT_LONGFORM_REPLAY_CLIP"],
            overridePath,
            "/Users/guanwei/Library/Application Support/Voxt/transcription-history-audio/transcription/transcription-FD3C99FC-822F-45DB-8734-FFADEF6DC6EE.wav",
            "/Users/guanwei/Library/Application Support/Voxt/transcription-history-audio/transcription/transcription-6247D986-B2EC-4758-AB40-7C1030296D7A.wav",
            "/Users/guanwei/Downloads/transcription/20260505-104918-transcription-5F2FAD9F-D22E-4D0E-BA36-E1D95A53197D.wav",
            "/Users/guanwei/Downloads/transcription/transcription-0A0E87B1-7C9A-4BB6-8469-E18485A63103.wav",
            "/Users/guanwei/Downloads/transcription/20260507-123725-transcription-CF5D4F69-31F4-4F86-ADCA-18029BDB0EE8.wav"
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private func resolvedLongFormCandidateClipPaths() -> [String] {
        resolvedCandidateClipPaths().filter { path in
            guard let clip = try? DebugAudioClipIO.clip(for: URL(fileURLWithPath: path)) else {
                return false
            }
            return clip.durationSeconds >= minimumLongFormDurationSeconds
        }
    }

    private func knownGoodBaselineClipPaths() -> [String] {
        let preferred = [
            ProcessInfo.processInfo.environment["VOXT_LONGFORM_REPLAY_CLIP"],
            try? String(contentsOfFile: "/tmp/voxt-longform-replay-clip-path.txt", encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "/Users/guanwei/Library/Application Support/Voxt/transcription-history-audio/transcription/transcription-6247D986-B2EC-4758-AB40-7C1030296D7A.wav",
            "/Users/guanwei/Library/Application Support/Voxt/transcription-history-audio/transcription/transcription-FD3C99FC-822F-45DB-8734-FFADEF6DC6EE.wav",
            "/Users/guanwei/Downloads/transcription/transcription-0A0E87B1-7C9A-4BB6-8469-E18485A63103.wav",
            "/Users/guanwei/Downloads/transcription/20260507-123725-transcription-CF5D4F69-31F4-4F86-ADCA-18029BDB0EE8.wav"
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }

        var seen = Set<String>()
        return preferred.filter { seen.insert($0).inserted }
    }

    private func knownGoodLongFormBaselineClipPaths() -> [String] {
        knownGoodBaselineClipPaths().filter { path in
            guard let clip = try? DebugAudioClipIO.clip(for: URL(fileURLWithPath: path)) else {
                return false
            }
            return clip.durationSeconds >= minimumLongFormDurationSeconds
        }
    }

    private func resolvedModelIDAndHubURL() throws -> (modelID: String, hubURL: URL) {
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
            throw XCTSkip("No downloaded Whisper model is available for long-form replay.")
        }
        return (chosenModelID, hubURL)
    }

    func testOfflineTranscriptionConfirmsModelSupportsProvidedLongFormClip() async throws {
        let existingClipPaths = resolvedLongFormCandidateClipPaths()
        guard let clipPath = existingClipPaths.first else {
            throw XCTSkip("No long-form replay clip is available.")
        }
        let clipURL = URL(fileURLWithPath: clipPath)
        let resolved = try resolvedModelIDAndHubURL()
        let transcriber = WhisperKitTranscriber(
            modelManager: WhisperKitModelManager(modelID: resolved.modelID, hubBaseURL: resolved.hubURL)
        )

        let text = try await transcriber.transcribeAudioFile(clipURL)
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertGreaterThan(text.trimmingCharacters(in: .whitespacesAndNewlines).count, 20)
    }

    func testReplayProvidedLongFormClipProducesFinalTranscript() async throws {
        let existingClipPaths = resolvedLongFormCandidateClipPaths()
        guard let clipPath = existingClipPaths.first else {
            throw XCTSkip("No long-form replay clip is available.")
        }
        let clipURL = URL(fileURLWithPath: clipPath)
        let longFormReplayStepSeconds = 4.0

        let resolved = try resolvedModelIDAndHubURL()
        let transcriber = WhisperKitTranscriber(
            modelManager: WhisperKitModelManager(modelID: resolved.modelID, hubBaseURL: resolved.hubURL)
        )
        let offlineText = try await transcriber.transcribeAudioFile(clipURL)
        let offlineCount = offlineText.trimmingCharacters(in: .whitespacesAndNewlines).count

        let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(
            clipURL,
            stepSeconds: longFormReplayStepSeconds
        )
        let finalEvent = try XCTUnwrap(diagnostics.events.last(where: { $0.isFinal }))

        XCTAssertFalse(offlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(finalEvent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(diagnostics.events.contains(where: { $0.isFinal }))

        let finalCount = finalEvent.text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if finalEvent.elapsedSeconds >= 60, offlineCount >= 60 {
            XCTAssertGreaterThanOrEqual(
                finalCount,
                Int(Double(offlineCount) * 0.6),
                "Realtime long-form final transcript collapsed too far below the offline baseline."
            )
        }

        let strongestLiveTextCount = diagnostics.events
            .filter { !$0.isFinal }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).count }
            .max() ?? 0
        XCTAssertGreaterThanOrEqual(
            finalCount,
            min(strongestLiveTextCount, 2),
            "Final transcript should not collapse below the strongest live hypothesis baseline."
        )

        let clipDurationSeconds = finalEvent.elapsedSeconds
        if clipDurationSeconds >= WhisperKitTranscriber.realtimeLongFormFinalProfileThresholdSeconds {
            XCTAssertTrue(
                diagnostics.trace.contains(where: { $0.contains("final/offline") }),
                "Long-form replay should use the same offline-biased final profile as runtime stop finalization."
            )
        }
        if clipDurationSeconds >= 30 {
            let latestLiveEventTime = diagnostics.events
                .filter { !$0.isFinal }
                .map(\.elapsedSeconds)
                .max() ?? 0
            XCTAssertGreaterThanOrEqual(
                latestLiveEventTime,
                clipDurationSeconds * 0.8,
                "Long-form realtime replay should keep publishing updates into the later portion of the clip."
            )
        }
    }

    func testReplayAllAvailableLongFormClipsProduceNonEmptyFinalTranscript() async throws {
        let candidateClipPaths = resolvedLongFormCandidateClipPaths()
        guard !candidateClipPaths.isEmpty else {
            throw XCTSkip("No available long-form clips found.")
        }
        let resolved = try resolvedModelIDAndHubURL()
        let transcriber = WhisperKitTranscriber(
            modelManager: WhisperKitModelManager(modelID: resolved.modelID, hubBaseURL: resolved.hubURL)
        )
        for clipPath in candidateClipPaths {
            let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(
                URL(fileURLWithPath: clipPath),
                stepSeconds: 4.0
            )
            let finalEvent = try XCTUnwrap(diagnostics.events.last(where: { $0.isFinal }))
            XCTAssertFalse(
                finalEvent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Expected non-empty final transcript for \(clipPath)"
            )
        }
    }

    func testReplayAllAvailableLongFormClipsTrackOfflineBaseline() async throws {
        let candidateClipPaths = knownGoodLongFormBaselineClipPaths()
        guard !candidateClipPaths.isEmpty else {
            throw XCTSkip("No known-good long-form baseline clips found.")
        }

        let resolved = try resolvedModelIDAndHubURL()
        let transcriber = WhisperKitTranscriber(
            modelManager: WhisperKitModelManager(modelID: resolved.modelID, hubBaseURL: resolved.hubURL)
        )

        for clipPath in candidateClipPaths {
            let clipURL = URL(fileURLWithPath: clipPath)
            let offlineText = try await transcriber.transcribeAudioFile(clipURL)
            let offlineCount = offlineText.trimmingCharacters(in: .whitespacesAndNewlines).count

            let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(
                clipURL,
                stepSeconds: 4.0
            )
            let finalEvent = try XCTUnwrap(diagnostics.events.last(where: { $0.isFinal }))
            let finalCount = finalEvent.text.trimmingCharacters(in: .whitespacesAndNewlines).count

            XCTAssertFalse(
                finalEvent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Expected non-empty final transcript for \(clipPath)"
            )
            XCTAssertGreaterThan(offlineCount, 20, "Offline baseline should be meaningfully non-empty for \(clipPath)")
            XCTAssertGreaterThanOrEqual(
                finalCount,
                Int(Double(offlineCount) * 0.6),
                "Realtime final transcript collapsed too far below the offline baseline for \(clipPath)"
            )

            if finalEvent.elapsedSeconds >= WhisperKitTranscriber.realtimeLongFormFinalProfileThresholdSeconds {
                XCTAssertTrue(
                    diagnostics.trace.contains(where: { $0.contains("final/offline") }),
                    "Long-form replay should use the offline final profile for \(clipPath)"
                )
            }
        }
    }
}

import XCTest
@testable import Voxt

@MainActor
final class WhisperLongFormDiagnosticsTests: XCTestCase {
    private func skipIfCI() throws {
        let env = ProcessInfo.processInfo.environment
        if env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" {
            throw XCTSkip("Whisper long-form diagnostics are local-only and are skipped on CI.")
        }
    }

    private func fixtureURL(named fileName: String) throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/qwen-official", isDirectory: true)
            .appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing official audio fixture: \(fileName)")
        }
        return url
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
            throw XCTSkip("No downloaded Whisper model is available for diagnostics.")
        }
        return (chosenModelID, WhisperKitModelManager(modelID: chosenModelID, hubBaseURL: hubURL))
    }

    func testPrintChineseLongFixtureAutoVsForcedLanguageDiagnostics() async throws {
        try skipIfCI()
        let resolved = try resolvedModelManager()
        let transcriber = WhisperKitTranscriber(modelManager: resolved.manager)
        let fixture = try fixtureURL(named: "qwen_audio_long_zh_composite.wav")

        let autoDiagnostics = try await transcriber.debugTranscribeAudioFileWithDiagnostics(fixture)
        let forcedDiagnostics = try await transcriber.debugTranscribeAudioFileWithDiagnostics(
            fixture,
            forcedLanguage: "zh"
        )

        print(
            "WHISPER_LONGFORM_DIAGNOSTIC model=\(resolved.modelID) mode=auto " +
            "rawJoined=\(Self.traceQuoted(autoDiagnostics.rawJoinedText)) " +
            "normalized=\(Self.traceQuoted(autoDiagnostics.normalizedText))"
        )
        print(
            "WHISPER_LONGFORM_DIAGNOSTIC model=\(resolved.modelID) mode=forced-zh " +
            "rawJoined=\(Self.traceQuoted(forcedDiagnostics.rawJoinedText)) " +
            "normalized=\(Self.traceQuoted(forcedDiagnostics.normalizedText))"
        )
    }

    func testPrintOfficialLongFixtureReplayTraceDiagnostics() async throws {
        try skipIfCI()
        let resolved = try resolvedModelManager()
        let transcriber = WhisperKitTranscriber(modelManager: resolved.manager)

        for fileName in ["qwen_audio_long_en_composite.wav", "qwen_audio_long_zh_composite.wav"] {
            let fixture = try fixtureURL(named: fileName)
            let diagnostics = try await transcriber.debugReplayRealtimeAudioFileWithTrace(
                fixture,
                stepSeconds: 4.0
            )
            let events = diagnostics.events.map {
                String(
                    format: "[%.1fs %@ %@]",
                    $0.elapsedSeconds,
                    $0.isFinal ? "final" : "live",
                    $0.source
                ) + " " + Self.traceQuoted($0.text)
            }.joined(separator: " | ")
            let traceTail = diagnostics.trace.suffix(8).joined(separator: " | ")
            print("WHISPER_REPLAY_DIAGNOSTIC model=\(resolved.modelID) file=\(fileName) events=\(events)")
            print("WHISPER_REPLAY_TRACE_TAIL model=\(resolved.modelID) file=\(fileName) trace=\(traceTail)")
        }
    }

    func testCompareInstalledWhisperModelsOnChineseFixtures() async throws {
        try skipIfCI()
        let defaults = UserDefaults.standard
        defaults.set("/Users/guanwei/x/models", forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)
        let hubURL = defaults.bool(forKey: AppPreferenceKey.useHfMirror)
            ? MLXModelManager.mirrorHubBaseURL
            : MLXModelManager.defaultHubBaseURL
        let probeManager = WhisperKitModelManager(modelID: WhisperKitModelManager.defaultModelID, hubBaseURL: hubURL)
        let installedModelIDs = ["large-v3", "small", "tiny"]
            .map(WhisperKitModelManager.canonicalModelID(_:))
            .filter { probeManager.isModelDownloaded(id: $0) }

        let longFixture = try fixtureURL(named: "qwen_audio_long_zh_composite.wav")
        let dialectFixture = try fixtureURL(named: "qwen_audio_short_zh_chongqing.wav")

        for modelID in installedModelIDs {
            let transcriber = WhisperKitTranscriber(
                modelManager: WhisperKitModelManager(modelID: modelID, hubBaseURL: hubURL)
            )
            let longDiagnostics = try await transcriber.debugTranscribeAudioFileWithDiagnostics(longFixture)
            let dialectDiagnostics = try await transcriber.debugTranscribeAudioFileWithDiagnostics(dialectFixture)
            print(
                "WHISPER_MODEL_COMPARISON model=\(modelID) " +
                "longZhChars=\(longDiagnostics.normalizedText.count) " +
                "longZh=\(Self.traceQuoted(longDiagnostics.normalizedText)) " +
                "dialectChars=\(dialectDiagnostics.normalizedText.count) " +
                "dialect=\(Self.traceQuoted(dialectDiagnostics.normalizedText))"
            )
        }
    }

    private static func traceQuoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

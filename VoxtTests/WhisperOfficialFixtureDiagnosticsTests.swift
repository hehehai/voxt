import XCTest
@testable import Voxt

@MainActor
final class WhisperOfficialFixtureDiagnosticsTests: XCTestCase {
    private func skipIfCI() throws {
        let env = ProcessInfo.processInfo.environment
        if env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" {
            throw XCTSkip("Whisper diagnostics are local-only and are skipped on CI.")
        }
    }

    private func fixtureDirectoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/qwen-official", isDirectory: true)
    }

    private func fixtureURL(named fileName: String) throws -> URL {
        let url = fixtureDirectoryURL().appendingPathComponent(fileName)
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

    func testPrintOfficialShortFixtureOfflineDiagnostics() async throws {
        try skipIfCI()
        let resolved = try resolvedModelManager()
        let transcriber = WhisperKitTranscriber(modelManager: resolved.manager)

        for fileName in [
            "qwen_audio_short_en.wav",
            "qwen_audio_short_zh_chongqing.wav",
            "qwen_audio_short_zh_relaxed.wav",
            "qwen_audio_short_zh_negative.wav"
        ] {
            let diagnostics = try await transcriber.debugTranscribeAudioFileWithDiagnostics(
                fixtureURL(named: fileName)
            )
            let joinedSegments = diagnostics.rawSegments
                .map { "\"\($0)\"" }
                .joined(separator: ", ")
            print(
                "WHISPER_OFFLINE_DIAGNOSTIC model=\(resolved.modelID) file=\(fileName) " +
                "segments=\(diagnostics.rawSegments.count) rawJoined=\(Self.traceQuoted(diagnostics.rawJoinedText)) " +
                "normalized=\(Self.traceQuoted(diagnostics.normalizedText)) rawSegments=[\(joinedSegments)]"
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

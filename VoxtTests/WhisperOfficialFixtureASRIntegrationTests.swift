import XCTest
@testable import Voxt

@MainActor
final class WhisperOfficialFixtureASRIntegrationTests: XCTestCase {
    private func skipIfCI() throws {
        let env = ProcessInfo.processInfo.environment
        if env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" {
            throw XCTSkip("Official audio fixture integration tests are local-only and are skipped on CI.")
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
            throw XCTSkip("No downloaded Whisper model is available for official fixture regression.")
        }
        return (chosenModelID, hubURL)
    }

    private func makeTranscriber() throws -> WhisperKitTranscriber {
        let resolved = try resolvedModelIDAndHubURL()
        return WhisperKitTranscriber(
            modelManager: WhisperKitModelManager(modelID: resolved.modelID, hubBaseURL: resolved.hubURL)
        )
    }

    private func normalizedLatinText(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalizedHanText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[，。！？、；：,.!?;:\"'“”‘’（）()\\-]", with: "", options: .regularExpression)
    }

    func testOfficialEnglishFixtureContainsExpectedTranscriptAnchors() async throws {
        try skipIfCI()
        let transcriber = try makeTranscriber()
        let text = try await transcriber.transcribeAudioFile(fixtureURL(named: "qwen_audio_short_en.wav"))
        let normalized = normalizedLatinText(text)

        XCTAssertTrue(normalized.contains("middle classes"), "Expected transcript to preserve 'middle classes'. Got: \(text)")
        XCTAssertTrue(normalized.contains("welcome his gospel"), "Expected transcript to preserve the ending phrase. Got: \(text)")
    }

    func testOfficialChongqingChineseFixtureContainsExpectedTranscriptAnchors() async throws {
        try skipIfCI()
        let transcriber = try makeTranscriber()
        let text = try await transcriber.transcribeAudioFile(fixtureURL(named: "qwen_audio_short_zh_chongqing.wav"))
        let normalized = normalizedHanText(text)

        XCTAssertTrue(normalized.contains("租一些自行车"), "Expected Chongqing dialect sample to mention renting bicycles. Got: \(text)")
        XCTAssertTrue(normalized.contains("锻炼身体"), "Expected Chongqing dialect sample to preserve the exercise phrase. Got: \(text)")
    }

    func testOfficialShortChineseEmotionFixturesPreserveCoreUtterance() async throws {
        try skipIfCI()
        let transcriber = try makeTranscriber()

        for fileName in ["qwen_audio_short_zh_relaxed.wav", "qwen_audio_short_zh_negative.wav"] {
            let text = try await transcriber.transcribeAudioFile(fixtureURL(named: fileName))
            let normalized = normalizedHanText(text)
            XCTAssertTrue(normalized.contains("你没事吧"), "Expected \(fileName) to preserve the core utterance '你没事吧'. Got: \(text)")
        }
    }
}

import XCTest
@testable import Voxt

final class WhisperModelArtifactsTests: XCTestCase {
    func testValidDirectoryRequiresCriticalWeightFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for path in WhisperModelArtifacts.requiredRelativePaths {
            let targetURL = root.appendingPathComponent(path)
            if path.hasSuffix(".mlmodelc") || path.hasSuffix("/weights") {
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("ok".utf8).write(to: targetURL)
            }
        }

        XCTAssertTrue(WhisperModelArtifacts.isValidModelDirectory(root))

        try FileManager.default.removeItem(
            at: root.appendingPathComponent("TextDecoder.mlmodelc/weights/weight.bin")
        )
        XCTAssertFalse(WhisperModelArtifacts.isValidModelDirectory(root))
    }

    func testCorruptLoadFailureMatchesBrokenModelMessages() {
        let error = NSError(
            domain: "CoreML",
            code: 71,
            userInfo: [NSLocalizedDescriptionKey: "Failed to parse ML Program. Could not open weights/weight.bin"]
        )
        XCTAssertTrue(WhisperModelArtifacts.isCorruptLoadFailure(error))
    }

    func testIncompleteWhisperFolderIsNotTreatedAsInstalled() throws {
        let root = try makeTemporaryDirectory()
        let modelDirectory = root
            .appendingPathComponent("whisperkit")
            .appendingPathComponent("openai_whisper-base", isDirectory: true)

        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(WhisperModelArtifacts.isValidModelDirectory(modelDirectory))
        XCTAssertTrue(FileManager.default.directoryContainsRegularFiles(at: modelDirectory))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

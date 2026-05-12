import XCTest
@testable import Voxt

final class CustomLLMModelSupportTests: XCTestCase {
    func testRepetitionGuardTruncatesShortRepeatedSuffix() {
        let repeated = String(repeating: "好", count: 24)
        let result = LLMOutputRepetitionGuard().repeatedSuffix(in: "结论：\(repeated)")

        XCTAssertEqual(result?.repeatedUnit, "好")
        XCTAssertEqual(result?.truncatedText, "结论：好")
    }

    func testRepetitionGuardTruncatesRepeatedPhraseSuffix() {
        let repeated = String(repeating: " thank you", count: 8)
        let result = LLMOutputRepetitionGuard().repeatedSuffix(in: "Done.\(repeated)")

        XCTAssertEqual(result?.repeatedUnit, " thank you")
        XCTAssertEqual(result?.truncatedText, "Done. thank you")
    }

    func testRepetitionGuardIgnoresSmallNaturalRepetitions() {
        let result = LLMOutputRepetitionGuard().repeatedSuffix(in: "谢谢，谢谢，谢谢。")

        XCTAssertNil(result)
    }

    func testCatalogRecognizesSupportedRepoAndFallbackTitle() {
        XCTAssertTrue(CustomLLMModelCatalog.isSupportedModelRepo("mlx-community/Qwen3-4B-4bit"))
        XCTAssertTrue(CustomLLMModelCatalog.isSupportedModelRepo("Qwen/Qwen3-8B-4bit"))
        XCTAssertFalse(CustomLLMModelCatalog.isSupportedModelRepo("unsupported/repo"))
        XCTAssertEqual(
            CustomLLMModelCatalog.displayTitle(for: "mlx-community/Qwen3-4B-4bit"),
            "Qwen3 4B (4bit)"
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.canonicalModelRepo("Qwen/Qwen3-8B-4bit"),
            "mlx-community/Qwen3-8B-4bit"
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.displayTitle(for: "custom/repo"),
            "custom/repo"
        )
    }

    func testCatalogUsesKnownRemoteSizeFallbacksForLegacyCuratedRepos() {
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "Qwen/Qwen2-1.5B-Instruct"))
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/Qwen3-4B-4bit"))
        XCTAssertNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/Qwen3.5-2B-4bit"))
    }

    func testCatalogUsesKnownRemoteSizeFallbacksForNewRecommendedModels() {
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/Qwen3.5-0.8B-4bit-OptiQ"))
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/Qwen3.5-4B-4bit"))
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/Qwen3.5-4B-OptiQ-4bit"))
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/Qwen3.5-9B-OptiQ-4bit"))
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/MiniCPM4-8B-4bit"))
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/internlm2_5-7b-chat-4bit"))
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/glm-4-9b-chat-1m-4bit"))
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/GLM-Z1-9B-0414-4bit"))
        XCTAssertNotNil(CustomLLMModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/GLM-4.7-Flash-4bit"))
    }

    func testCatalogMarksNewAndHiddenCompatibilityModels() {
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/Qwen3.5-2B-4bit"),
            .new
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/Qwen3.5-0.8B-4bit-OptiQ"),
            .new
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/Qwen3.5-4B-4bit"),
            .new
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/Qwen3.5-4B-OptiQ-4bit"),
            .new
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/Qwen3.5-9B-OptiQ-4bit"),
            .new
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/MiniCPM4-8B-4bit"),
            .new
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/internlm2_5-7b-chat-4bit"),
            .new
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/glm-4-9b-chat-1m-4bit"),
            .new
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/GLM-Z1-9B-0414-4bit"),
            .new
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.releaseStatus(for: "mlx-community/GLM-4.7-Flash-4bit"),
            .standard
        )
        let compatibilityOnly = CustomLLMModelCatalog.displayModels(including: "Qwen/Qwen2.5-7B-Instruct")
        XCTAssertTrue(compatibilityOnly.contains(where: { $0.id == "mlx-community/Qwen2.5-7B-Instruct-4bit" }))
        let qwen30BCompatibility = CustomLLMModelCatalog.displayModels(including: "mlx-community/Qwen3-30B-A3B-4bit")
        XCTAssertTrue(qwen30BCompatibility.contains(where: { $0.id == "mlx-community/Qwen3-30B-A3B-4bit" }))
        let glm47Compatibility = CustomLLMModelCatalog.displayModels(including: "mlx-community/GLM-4.7-Flash-4bit")
        XCTAssertTrue(glm47Compatibility.contains(where: { $0.id == "mlx-community/GLM-4.7-Flash-4bit" }))
    }

    func testCatalogIncludesNewRecommendedHomeMacModels() {
        let modelIDs = Set(CustomLLMModelCatalog.availableModels.map(\.id))

        XCTAssertTrue(modelIDs.contains("mlx-community/Qwen3.5-0.8B-4bit-OptiQ"))
        XCTAssertTrue(modelIDs.contains("mlx-community/Qwen3.5-4B-4bit"))
        XCTAssertTrue(modelIDs.contains("mlx-community/Qwen3.5-4B-OptiQ-4bit"))
        XCTAssertTrue(modelIDs.contains("mlx-community/Qwen3.5-9B-OptiQ-4bit"))
        XCTAssertTrue(modelIDs.contains("mlx-community/MiniCPM4-8B-4bit"))
        XCTAssertTrue(modelIDs.contains("mlx-community/internlm2_5-7b-chat-4bit"))
        XCTAssertTrue(modelIDs.contains("mlx-community/glm-4-9b-chat-1m-4bit"))
        XCTAssertTrue(modelIDs.contains("mlx-community/GLM-Z1-9B-0414-4bit"))
        XCTAssertFalse(modelIDs.contains("mlx-community/Qwen3-30B-A3B-4bit"))
        XCTAssertFalse(modelIDs.contains("mlx-community/GLM-4.7-Flash-4bit"))
    }

    func testStorageSupportBuildsExpectedCacheDirectory() {
        let rootDirectory = URL(fileURLWithPath: "/tmp/voxt-tests", isDirectory: true)
        let directory = CustomLLMModelStorageSupport.cacheDirectory(
            for: "mlx-community/Qwen3-4B-4bit",
            rootDirectory: rootDirectory
        )
        XCTAssertEqual(
            directory?.path,
            "/tmp/voxt-tests/mlx-llm/mlx-community_Qwen3-4B-4bit"
        )
    }

    func testChatTemplateDetectionRecognizesDownloadedTemplateSidecars() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jinjaURL = root.appendingPathComponent("chat_template.jinja")
        try "{% for m in messages %}{{ m.content }}{% endfor %}".write(
            to: jinjaURL,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(CustomLLMModelDownloadSupport.hasUsableChatTemplate(in: root))
    }

    func testChatTemplateDetectionRecognizesInlineTokenizerTemplate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let tokenizerConfigURL = root.appendingPathComponent("tokenizer_config.json")
        let json = """
        {
          "chat_template": "{{ bos_token }}{{ messages[0]['content'] }}"
        }
        """
        try json.write(to: tokenizerConfigURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(CustomLLMModelDownloadSupport.hasUsableChatTemplate(in: root))
    }

    func testPartialCustomLLMDirectoryIsNotTreatedAsInstalled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelDirectory = root
            .appendingPathComponent("mlx-llm")
            .appendingPathComponent("mlx-community_Qwen3-4B-4bit")

        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: modelDirectory.appendingPathComponent("model.safetensors"))
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(CustomLLMModelStorageSupport.isModelDirectoryValid(modelDirectory))
        XCTAssertTrue(FileManager.default.directoryContainsRegularFiles(at: modelDirectory))
    }
}

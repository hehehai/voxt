import XCTest
@testable import Voxt

final class RemoteLLMRuntimeClientMessagesTests: XCTestCase {
    func testResponsesInputMessagesBuildsConversationHistoryAndCurrentTurn() {
        let client = RemoteLLMRuntimeClient()
        let input: [[String: Any]] = client.responsesInputMessages(
            currentUserInput: "看一下大同的经纬度。",
            currentAttachments: [],
            conversationHistory: [
                RewriteConversationPromptTurn(
                    userPromptText: "北京今天的天气怎么样？",
                    sourceText: "北京行程安排",
                    resultTitle: "大同天气查询",
                    resultContent: "请查看最新天气预报应用或网站获取大同实时天气信息。"
                )
            ]
        )

        XCTAssertEqual(input.count, 3)
        let firstRole = input.first?["role"] as? String
        let lastRole = input.last?["role"] as? String
        let lastContent = input.last?["content"] as? String
        let firstContent = input.first?["content"] as? String
        let assistantContent = input[1]["content"] as? String
        XCTAssertEqual(firstRole, "user")
        XCTAssertEqual(
            firstContent,
            """
            Spoken instruction:
            北京今天的天气怎么样？

            Selected source text:
            北京行程安排
            """
        )
        XCTAssertEqual(assistantContent, "请查看最新天气预报应用或网站获取大同实时天气信息。")
        XCTAssertFalse(assistantContent?.contains("大同天气查询") == true)
        XCTAssertEqual(lastRole, "user")
        XCTAssertEqual(lastContent, "看一下大同的经纬度。")
        XCTAssertFalse(lastContent?.contains("北京行程安排") == true)
    }

    func testChatConversationMessagesCarrySelectedTextOnlyInInitialHistoricalTurn() {
        let client = RemoteLLMRuntimeClient()
        let messages = client.openAICompatibleConversationMessages(
            systemPrompt: "Answer the follow-up directly.",
            currentUserPrompt: "更简短一点",
            conversationHistory: [
                RewriteConversationPromptTurn(
                    userPromptText: "帮我回复",
                    sourceText: "明天下午三点可以吗？",
                    resultTitle: "回复",
                    resultContent: "可以，明天下午三点见。"
                )
            ]
        )

        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user", "assistant", "user"])
        XCTAssertContains(messages[1]["content"] ?? "", "Spoken instruction:\n帮我回复")
        XCTAssertContains(messages[1]["content"] ?? "", "Selected source text:\n明天下午三点可以吗？")
        XCTAssertEqual(messages[2]["content"], "可以，明天下午三点见。")
        XCTAssertEqual(messages[3]["content"], "更简短一点")
        XCTAssertFalse(messages[3]["content"]?.contains("明天下午三点可以吗？") == true)
    }

    func testResponsesUserInputPayloadEncodesImageAttachmentsAsInputBlocks() throws {
        let client = RemoteLLMRuntimeClient()
        let payload = client.responsesUserInputPayload(
            text: "看一下这个界面。",
            attachments: [
                .image(
                    LLMImageAttachment(
                        data: Data([0x01, 0x02, 0x03]),
                        mimeType: "image/jpeg",
                        detail: .high,
                        filename: "capture.jpg"
                    )
                )
            ]
        )

        let messages = try XCTUnwrap(payload as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")

        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertEqual(content.first?["text"] as? String, "看一下这个界面。")
        XCTAssertEqual(content.last?["type"] as? String, "input_image")
        XCTAssertEqual(content.last?["detail"] as? String, "high")
        XCTAssertEqual(
            content.last?["image_url"] as? String,
            "data:image/jpeg;base64,AQID"
        )
    }

    func testTranscriptionAppContextCapabilityResolverDetectsSupportedVisionInputs() {
        let openAIVisionProvider = LLMExecutionProvider.remote(
            provider: .openAI,
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5"
            )
        )
        let openAIGPT41Provider = LLMExecutionProvider.remote(
            provider: .openAI,
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-4.1"
            )
        )
        let openAITextOnlyProvider = LLMExecutionProvider.remote(
            provider: .openAI,
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-4"
            )
        )
        let volcengineVisionProvider = LLMExecutionProvider.remote(
            provider: .volcengine,
            configuration: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.volcengine.rawValue,
                model: "doubao-seed-2-0-pro-260215"
            )
        )
        let customVisionProvider = LLMExecutionProvider.customLLM(
            repo: "mlx-community/gemma-4-e4b-it-4bit"
        )

        let openAIVisionCapabilities = TranscriptionAppContextCapabilityResolver.capabilities(
            for: openAIVisionProvider
        )
        let openAIGPT41Capabilities = TranscriptionAppContextCapabilityResolver.capabilities(
            for: openAIGPT41Provider
        )
        let openAITextOnlyCapabilities = TranscriptionAppContextCapabilityResolver.capabilities(
            for: openAITextOnlyProvider
        )
        let volcengineCapabilities = TranscriptionAppContextCapabilityResolver.capabilities(
            for: volcengineVisionProvider
        )
        let customTextOnlyCapabilities = TranscriptionAppContextCapabilityResolver.capabilities(
            for: .customLLM(repo: "mlx-community/Qwen3-8B-4bit")
        )
        let customVisionCapabilities = TranscriptionAppContextCapabilityResolver.capabilities(
            for: customVisionProvider
        )

        XCTAssertTrue(openAIVisionCapabilities.supportsTextContext)
        XCTAssertTrue(openAIVisionCapabilities.supportsImageInput)
        XCTAssertTrue(openAIGPT41Capabilities.supportsTextContext)
        XCTAssertTrue(openAIGPT41Capabilities.supportsImageInput)
        XCTAssertTrue(openAITextOnlyCapabilities.supportsTextContext)
        XCTAssertFalse(openAITextOnlyCapabilities.supportsImageInput)
        XCTAssertTrue(volcengineCapabilities.supportsTextContext)
        XCTAssertTrue(volcengineCapabilities.supportsImageInput)
        XCTAssertTrue(customTextOnlyCapabilities.supportsTextContext)
        XCTAssertFalse(customTextOnlyCapabilities.supportsImageInput)
        XCTAssertTrue(customVisionCapabilities.supportsTextContext)
        XCTAssertTrue(customVisionCapabilities.supportsImageInput)
    }
}

import XCTest
@testable import Voxt

@MainActor
final class MLXModelManagerTests: XCTestCase {
    func testCanonicalModelRepoMapsLegacyReposToCurrentIdentifiers() {
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/Parakeet-0.6B"),
            "mlx-community/parakeet-tdt-0.6b-v3"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/GLM-ASR-Nano-4bit"),
            "mlx-community/GLM-ASR-Nano-2512-4bit"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602"),
            "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-6bit"),
            "mlx-community/Voxtral-Mini-4B-Realtime-6bit"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/FireRedASR2"),
            "mlx-community/FireRedASR2-AED-mlx"
        )
    }

    func testRealtimeCapableModelRepoTreatsAllVoxtralQuantizationsAsRealtime() {
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-6bit"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-6bit"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"))
        XCTAssertFalse(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Qwen3-ASR-0.6B-4bit"))
    }

    func testTranscriptionBehaviorUsesFinalizationOnlyModeForFireRed() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/FireRedASR2")

        XCTAssertEqual(behavior.correctionMode, .finalizationOnly)
        XCTAssertFalse(behavior.runsIntermediateCorrections)
        XCTAssertFalse(behavior.allowsQuickStopPass)
        XCTAssertTrue(behavior.preloadsOnRecordingStart)
    }

    func testTranscriptionBehaviorUsesIncrementalModeForDefaultModels() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/Qwen3-ASR-0.6B-4bit")

        XCTAssertEqual(behavior.correctionMode, .incremental)
        XCTAssertTrue(behavior.runsIntermediateCorrections)
        XCTAssertTrue(behavior.allowsQuickStopPass)
        XCTAssertTrue(behavior.preloadsOnRecordingStart)
    }

    func testIntermediateCorrectionDecisionSkipsFinalizationOnlyBehavior() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/FireRedASR2")

        XCTAssertNil(
            MLXTranscriptionPlanning.intermediateCorrectionDecision(
                sampleCount: 16000 * 8,
                sampleRate: 16000,
                nextCorrectionAtSeconds: 6,
                behavior: behavior,
                firstCorrectionMinimumSeconds: 3.5,
                contextWindowSeconds: 18
            )
        )
    }

    func testIntermediateCorrectionDecisionReturnsContextWindowForIncrementalBehavior() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/Qwen3-ASR-0.6B-4bit")

        let decision = MLXTranscriptionPlanning.intermediateCorrectionDecision(
            sampleCount: 16000 * 8,
            sampleRate: 16000,
            nextCorrectionAtSeconds: 6,
            behavior: behavior,
            firstCorrectionMinimumSeconds: 3.5,
            contextWindowSeconds: 18
        )

        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.elapsedSeconds ?? 0, 8, accuracy: 0.0001)
        XCTAssertEqual(decision?.contextSampleCount, 16000 * 18)
    }

    func testFinalizationPlanDisablesQuickPassForFireRed() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/FireRedASR2")
        let plan = MLXTranscriptionPlanning.finalizationPlan(
            sampleCount: 16000 * 30,
            sampleRate: 16000,
            behavior: behavior,
            quickPassMinimumDurationSeconds: 14,
            quickPassContextWindowSeconds: 30
        )

        XCTAssertEqual(plan.durationSeconds, 30, accuracy: 0.0001)
        XCTAssertFalse(plan.shouldRunQuickPass)
        XCTAssertNil(plan.quickPassSampleCount)
    }

    func testFinalizationPlanUsesQuickPassForLongIncrementalAudio() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/Qwen3-ASR-0.6B-4bit")
        let plan = MLXTranscriptionPlanning.finalizationPlan(
            sampleCount: 16000 * 30,
            sampleRate: 16000,
            behavior: behavior,
            quickPassMinimumDurationSeconds: 14,
            quickPassContextWindowSeconds: 30
        )

        XCTAssertEqual(plan.durationSeconds, 30, accuracy: 0.0001)
        XCTAssertTrue(plan.shouldRunQuickPass)
        XCTAssertEqual(plan.quickPassSampleCount, 16000 * 30)
    }

    func testAvailableModelsIncludeLatestSupportedSTTRepos() {
        let modelIDs = Set(MLXModelManager.availableModels.map(\.id))

        XCTAssertTrue(modelIDs.contains("mlx-community/parakeet-tdt-0.6b-v2"))
        XCTAssertTrue(modelIDs.contains("mlx-community/granite-4.0-1b-speech-5bit"))
        XCTAssertTrue(modelIDs.contains("mlx-community/FireRedASR2-AED-mlx"))
        XCTAssertTrue(modelIDs.contains("mlx-community/SenseVoiceSmall"))
        XCTAssertTrue(modelIDs.contains("mlx-community/Voxtral-Mini-4B-Realtime-6bit"))
    }

    func testCustomLLMBehaviorDisablesThinkingForQwen3Family() {
        XCTAssertEqual(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Qwen3-4B-4bit").family, .qwen3)
        XCTAssertTrue(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Qwen3-4B-4bit").disablesThinking)
        XCTAssertTrue(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Qwen3-8B-4bit").disablesThinking)
        XCTAssertTrue(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Qwen3.5-4B-MLX-4bit").disablesThinking)
    }

    func testCustomLLMBehaviorLeavesOtherInstructionModelsUntouched() {
        XCTAssertEqual(CustomLLMModelBehaviorResolver.behavior(for: "Qwen/Qwen2-1.5B-Instruct").family, .qwen2)
        XCTAssertEqual(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/GLM-4-9B-0414-4bit").family, .glm4)
        XCTAssertEqual(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Llama-3.2-3B-Instruct-4bit").family, .llama)
        XCTAssertEqual(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Mistral-Nemo-Instruct-2407-4bit").family, .mistral)
        XCTAssertEqual(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/gemma-2-2b-it-4bit").family, .gemma)
        XCTAssertFalse(CustomLLMModelBehaviorResolver.behavior(for: "Qwen/Qwen2-1.5B-Instruct").disablesThinking)
        XCTAssertFalse(CustomLLMModelBehaviorResolver.behavior(for: "Qwen/Qwen2.5-3B-Instruct").disablesThinking)
        XCTAssertFalse(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/GLM-4-9B-0414-4bit").disablesThinking)
        XCTAssertFalse(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Llama-3.2-3B-Instruct-4bit").disablesThinking)
    }

    func testCustomLLMBehaviorProvidesAdditionalContextOnlyForThinkingModels() {
        let qwen3Behavior = CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Qwen3-4B-4bit")
        let qwen2Behavior = CustomLLMModelBehaviorResolver.behavior(for: "Qwen/Qwen2-1.5B-Instruct")

        XCTAssertEqual(qwen3Behavior.additionalContext?["enable_thinking"] as? Bool, false)
        XCTAssertNil(qwen2Behavior.additionalContext)
    }

    func testCustomLLMTaskKindUsesExpectedTokenBudgetMultipliers() {
        XCTAssertEqual(CustomLLMTaskKind.enhancement.tokenBudgetMultiplier, 1.10, accuracy: 0.0001)
        XCTAssertEqual(CustomLLMTaskKind.translation.tokenBudgetMultiplier, 1.35, accuracy: 0.0001)
        XCTAssertEqual(CustomLLMTaskKind.rewrite.tokenBudgetMultiplier, 1.35, accuracy: 0.0001)
    }

    func testCustomLLMRepoSelectionFallsBackForUnsupportedRepo() {
        let selection = CustomLLMRepoSelection.resolve(
            requestedRepo: "unsupported/repo",
            supportedRepos: ["a", "b"],
            fallbackRepo: "a"
        )

        XCTAssertEqual(selection.effectiveRepo, "a")
        XCTAssertTrue(selection.didFallback)
    }

    func testCustomLLMRepoSelectionPreservesSupportedRepo() {
        let selection = CustomLLMRepoSelection.resolve(
            requestedRepo: "b",
            supportedRepos: ["a", "b"],
            fallbackRepo: "a"
        )

        XCTAssertEqual(selection.effectiveRepo, "b")
        XCTAssertFalse(selection.didFallback)
    }

    func testCustomLLMRemoteSizeCacheTreatsUnknownAsMissing() {
        XCTAssertNil(
            CustomLLMRemoteSizeCache.cachedState(
                for: "repo",
                cache: ["repo": CustomLLMRemoteSizeCache.unknownText]
            )
        )
        XCTAssertTrue(
            CustomLLMRemoteSizeCache.shouldPrefetch(
                repo: "missing",
                cache: ["repo": "2.1 GB"]
            )
        )
        XCTAssertFalse(
            CustomLLMRemoteSizeCache.shouldPrefetch(
                repo: "repo",
                cache: ["repo": "2.1 GB"]
            )
        )
    }

    func testCustomLLMRemoteSizeCacheReturnsReadyStateForCachedText() {
        let cachedState = CustomLLMRemoteSizeCache.cachedState(
            for: "repo",
            cache: ["repo": "2.1 GB"]
        )

        XCTAssertEqual(cachedState, .ready(bytes: 0, text: "2.1 GB"))
        XCTAssertEqual(
            CustomLLMRemoteSizeCache.updatedCache([:], repo: "repo", text: "1.0 GB"),
            ["repo": "1.0 GB"]
        )
    }

    func testCustomLLMRequestPlanBuilderBuildsStructuredEnhancementRequest() {
        let plan = CustomLLMRequestPlanBuilder.enhancement(
            input: "hello world",
            systemPrompt: "clean it",
            repo: "mlx-community/Qwen3-4B-4bit",
            resultFallback: "raw text",
            structuredOutputPrompt: { instruction, input in "\(instruction)\nINPUT:\(input)" }
        )

        XCTAssertEqual(plan.kind, .enhancement)
        XCTAssertEqual(plan.repo, "mlx-community/Qwen3-4B-4bit")
        XCTAssertEqual(plan.instructions, "clean it")
        XCTAssertEqual(plan.inputCharacterCount, 11)
        XCTAssertEqual(plan.resultFallback, "raw text")
        XCTAssertNil(plan.logMode)
        XCTAssertEqual(plan.contentLogSections.map(\.label), ["system_prompt", "input", "request_content"])
        XCTAssertEqual(plan.contentLogSections.last?.content, "Clean up this transcription while preserving meaning and style.\nINPUT:hello world")
    }

    func testCustomLLMRequestPlanBuilderBuildsUserPromptEnhancementRequest() {
        let plan = CustomLLMRequestPlanBuilder.userPromptEnhancement(
            prompt: "rewrite this",
            repo: "Qwen/Qwen2-1.5B-Instruct"
        )

        XCTAssertEqual(plan.kind, .enhancement)
        XCTAssertEqual(plan.instructions, "")
        XCTAssertEqual(plan.prompt, "rewrite this")
        XCTAssertEqual(plan.logMode, "userMessage")
        XCTAssertEqual(plan.contentLogSections.map(\.label), ["system_prompt", "input"])
        XCTAssertEqual(plan.contentLogSections.first?.content, "<empty>")
    }

    func testCustomLLMRequestPlanBuilderBuildsTranslationRequest() {
        let plan = CustomLLMRequestPlanBuilder.translation(
            text: "bonjour",
            instructions: "translate to english",
            repo: "mlx-community/GLM-4-9B-0414-4bit",
            structuredOutputPrompt: { instruction, input in "\(instruction) => \(input)" }
        )

        XCTAssertEqual(plan.kind, .translation)
        XCTAssertEqual(plan.repo, "mlx-community/GLM-4-9B-0414-4bit")
        XCTAssertEqual(plan.instructions, "translate to english")
        XCTAssertEqual(plan.inputCharacterCount, 7)
        XCTAssertEqual(plan.contentLogSections.map(\.label), ["system_prompt", "input", "request_content"])
        XCTAssertEqual(plan.contentLogSections.last?.content, "Process the input according to the instructions. => bonjour")
    }

    func testCustomLLMRequestPlanBuilderBuildsRewriteRequest() {
        let plan = CustomLLMRequestPlanBuilder.rewrite(
            sourceText: "Old text",
            dictatedPrompt: "make it shorter",
            instructions: "rewrite carefully",
            repo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            structuredOutputPrompt: { instruction, input in "\(instruction)\n---\n\(input)" }
        )

        XCTAssertEqual(plan.kind, .rewrite)
        XCTAssertEqual(plan.instructions, "rewrite carefully")
        XCTAssertNil(plan.logMode)
        XCTAssertTrue(plan.prompt.contains("Produce the final text to insert according to the instructions."))
        XCTAssertTrue(plan.contentLogSections[1].content.contains("Spoken instruction:"))
        XCTAssertTrue(plan.contentLogSections[1].content.contains("Selected source text:"))
    }

    func testCustomLLMNormalizeResultTextStripsThinkBlocksAndMarkers() {
        let output = """
        <think>
        reason
        </think>

        ```json
        {"resultText":"Hello"}
        ```
        """

        XCTAssertEqual(CustomLLMOutputSanitizer.normalizeResultText(output), #"{"resultText":"Hello"}"#)
        XCTAssertEqual(CustomLLMOutputSanitizer.normalizeResultText("<think>\n\n</think>\n\nHello"), "Hello")
    }
}

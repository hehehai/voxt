import XCTest
@testable import Voxt

final class LLMExecutionPlanCompilerTests: XCTestCase {
    func testUserMessageCompilationMovesGlossaryIntoInstructions() {
        let plan = LLMExecutionPlan(
            task: .translation(sourceText: "hello", targetLanguage: .english),
            provider: .customLLM(repo: "test/repo"),
            delivery: .userMessage,
            promptContent: "Translate hello to English.",
            fallbackText: "hello",
            executionStrategy: TaskLLMStrategyResolver.resolve(
                taskKind: .translation,
                rawText: "hello",
                promptCharacterCount: 27,
                baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.translation.selectionPolicy,
                capabilities: .unknown
            ),
            outputTokenBudgetHint: nil,
            contextBlocks: [
                LLMContextBlock(
                    kind: .glossary,
                    title: "Dictionary Guidance",
                    content: "Prefer these exact spellings:\n- OpenAI",
                    isStablePrefixCandidate: true
                )
            ],
            conversationHistory: [],
            previousResponseID: nil,
            responseFormat: nil
        )

        let compiled = LLMExecutionPlanCompiler.compile(plan)

        XCTAssertEqual(compiled.prompt, "Translate hello to English.")
        XCTAssertContains(compiled.instructions, "### Dictionary Guidance")
        XCTAssertContains(compiled.instructions, "- OpenAI")
    }

    func testSystemPromptCompilationKeepsRequestPromptDynamicAndGlossaryStable() {
        let plan = LLMExecutionPlan(
            task: .enhancement(rawText: "raw transcript"),
            provider: .customLLM(repo: "test/repo"),
            delivery: .systemPrompt,
            promptContent: "Clean up the transcript.",
            fallbackText: "raw transcript",
            executionStrategy: TaskLLMStrategyResolver.resolve(
                taskKind: .transcriptionEnhancement,
                rawText: "raw transcript",
                promptCharacterCount: 24,
                baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.enhancement.selectionPolicy,
                capabilities: .unknown
            ),
            outputTokenBudgetHint: nil,
            contextBlocks: [
                LLMContextBlock(
                    kind: .glossary,
                    title: "Dictionary Guidance",
                    content: "Prefer these exact spellings:\n- Anthropic",
                    isStablePrefixCandidate: true
                ),
                LLMContextBlock(
                    kind: .input,
                    title: "Raw transcription",
                    content: "raw transcript",
                    isStablePrefixCandidate: false
                )
            ],
            conversationHistory: [],
            previousResponseID: nil,
            responseFormat: nil
        )

        let compiled = LLMExecutionPlanCompiler.compile(plan)

        XCTAssertContains(compiled.instructions, "Clean up the transcript.")
        XCTAssertContains(compiled.instructions, "### Dictionary Guidance")
        XCTAssertContains(compiled.instructions, "- Anthropic")
        XCTAssertContains(compiled.prompt, "Process this ASR transcription according to the system instructions.")
        XCTAssertContains(compiled.prompt, "raw transcript")
        XCTAssertFalse(compiled.prompt.contains("Clean this ASR transcription conservatively."))
        XCTAssertFalse(compiled.instructions.contains("Raw transcription"))
    }

    func testSystemPromptCompilationIncludesMetadataAndAppBlocks() {
        let plan = LLMExecutionPlan(
            task: .enhancement(rawText: "raw transcript"),
            provider: .customLLM(repo: "test/repo"),
            delivery: .systemPrompt,
            promptContent: "Clean up the transcript.",
            fallbackText: "raw transcript",
            executionStrategy: TaskLLMStrategyResolver.resolve(
                taskKind: .transcriptionEnhancement,
                rawText: "raw transcript",
                promptCharacterCount: 24,
                baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.enhancement.selectionPolicy,
                capabilities: .unknown
            ),
            outputTokenBudgetHint: nil,
            contextBlocks: [
                LLMContextBlock(
                    kind: .app,
                    title: "Enhancement source",
                    content: "App group: Slack",
                    isStablePrefixCandidate: true
                ),
                LLMContextBlock(
                    kind: .metadata,
                    title: "Latency profile",
                    content: "quality",
                    isStablePrefixCandidate: true
                )
            ],
            conversationHistory: [],
            previousResponseID: nil,
            responseFormat: nil
        )

        let compiled = LLMExecutionPlanCompiler.compile(plan)

        XCTAssertContains(compiled.instructions, "### Latency profile")
        XCTAssertContains(compiled.instructions, "quality")
    }

    func testReducedLongInputGlossaryPolicyTightensBudget() {
        let standard = DictionaryGlossaryPurpose.rewrite.selectionPolicy
        let reduced = standard.reducedForLongInput()

        XCTAssertLessThan(reduced.maxTerms, standard.maxTerms)
        XCTAssertLessThan(reduced.maxCharacters, standard.maxCharacters)
    }
}

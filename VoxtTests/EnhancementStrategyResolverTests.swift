import XCTest
@testable import Voxt

final class EnhancementStrategyResolverTests: XCTestCase {
    func testShortTranscriptionUsesSinglePassWithNoHintWhenModelLimitUnknown() {
        let strategy = TaskLLMStrategyResolver.resolve(
            taskKind: .transcriptionEnhancement,
            rawText: String(repeating: "短", count: 120),
            promptCharacterCount: 80,
            baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.enhancement.selectionPolicy,
            capabilities: .unknown
        )

        XCTAssertEqual(strategy.rawTextCharacterCount, 120)
        XCTAssertEqual(strategy.mode, .singlePass)
        XCTAssertEqual(strategy.contextBudgetPolicy, .standard)
        XCTAssertNil(strategy.outputTokenBudgetHint)
        XCTAssertFalse(strategy.truncationGuard.isEnabled)
    }

    func testLongTranslationWithTightModelLimitUsesSegmentedMode() {
        let strategy = TaskLLMStrategyResolver.resolve(
            taskKind: .translation,
            rawText: String(repeating: "长", count: 360),
            promptCharacterCount: 120,
            baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.translation.selectionPolicy,
            capabilities: LLMProviderModelCapabilities(maxContextTokens: 8192, maxOutputTokens: 400)
        )

        XCTAssertEqual(strategy.rawTextCharacterCount, 360)
        XCTAssertEqual(strategy.mode, .segmented)
        XCTAssertEqual(strategy.contextBudgetPolicy, .reducedForLongInput)
        XCTAssertEqual(strategy.outputTokenBudgetHint, 400)
        XCTAssertTrue(strategy.truncationGuard.isEnabled)
        XCTAssertNotNil(strategy.segmentationCharacterLimit)
    }

    func testTruncationGuardFallsBackForPrefixLikeOutput() {
        let original = String(repeating: "这是一段比较长的原始文本。", count: 30)
        let enhanced = String(original.prefix(60))
        let strategy = TaskLLMStrategyResolver.resolve(
            taskKind: .rewrite,
            rawText: original,
            promptCharacterCount: 100,
            baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.rewrite.selectionPolicy,
            capabilities: .unknown
        )

        let guarded = TaskLLMStrategyResolver.applyTruncationGuard(
            outputText: enhanced,
            originalText: original,
            strategy: strategy
        )

        XCTAssertTrue(guarded.didFallback)
        XCTAssertEqual(guarded.text, original)
    }

    func testTruncationGuardKeepsHealthyLongOutput() {
        let original = String(repeating: "做 PPT 时，从资料库里挑素材，起稿就可以发起任务。", count: 12)
        let enhanced = String(repeating: "做 PPT 时，从资料库里挑素材，起稿就可以发起任务。", count: 11)
        let strategy = TaskLLMStrategyResolver.resolve(
            taskKind: .transcriptionEnhancement,
            rawText: original,
            promptCharacterCount: 100,
            baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.enhancement.selectionPolicy,
            capabilities: .unknown
        )

        let guarded = TaskLLMStrategyResolver.applyTruncationGuard(
            outputText: enhanced,
            originalText: original,
            strategy: strategy
        )

        XCTAssertFalse(guarded.didFallback)
        XCTAssertEqual(guarded.text, enhanced)
    }

    func testLongRewriteWithLooseOrUnknownModelLimitStaysSinglePass() {
        let strategy = TaskLLMStrategyResolver.resolve(
            taskKind: .rewrite,
            rawText: String(repeating: "长", count: 360),
            promptCharacterCount: 100,
            baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.rewrite.selectionPolicy,
            capabilities: LLMProviderModelCapabilities(maxContextTokens: 8192, maxOutputTokens: 800)
        )

        XCTAssertEqual(strategy.mode, .singlePass)
        XCTAssertEqual(strategy.outputTokenBudgetHint, 487)
        XCTAssertTrue(strategy.truncationGuard.isEnabled)
    }
}

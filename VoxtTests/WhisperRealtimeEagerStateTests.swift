import Testing
import WhisperKit
@testable import Voxt

struct WhisperRealtimeEagerStateTests {
    @Test
    func firstPassPublishesImmediateHypothesis() {
        var state = WhisperRealtimeEagerState()

        let published = state.apply(hypothesisText: "hello world")

        #expect(published == "hello world")
        #expect(state.publishedText == "hello world")
    }

    @Test
    func overlapExtensionKeepsDroppedPrefixVisible() {
        var state = WhisperRealtimeEagerState()

        _ = state.apply(hypothesisText: "你好这是一个最小的")
        let published = state.apply(hypothesisText: "这是一个最小的回归")

        #expect(published == "你好这是一个最小的回归")
        #expect(state.publishedText == "你好这是一个最小的回归")
    }

    @Test
    func punctuationCandidateReplacesCleanlyWithoutPrefixCorruption() {
        var state = WhisperRealtimeEagerState()

        _ = state.apply(hypothesisText: "你好这是一个最小的回归测试测试已经")
        let published = state.apply(hypothesisText: "你好,这是一个最小的回归测试测试已经通过")

        #expect(published == "你好,这是一个最小的回归测试测试已经通过")
        #expect(state.publishedText == "你好,这是一个最小的回归测试测试已经通过")
    }

    @Test
    func shortNewUtteranceAfterSealDoesNotAppendImmediately() {
        var state = WhisperRealtimeEagerState()

        _ = state.apply(hypothesisText: "你好")
        state.sealCurrentPublishedTextForNextUtterance()

        let shortCandidate = state.apply(hypothesisText: "美国")
        let longerCandidate = state.apply(hypothesisText: "谢谢大家")

        #expect(shortCandidate == nil)
        #expect(longerCandidate == "你好谢谢大家")
        #expect(state.publishedText == "你好谢谢大家")
    }

    @Test
    func sealingCurrentPublishedTextStartsANewUtteranceWithoutDuplicatingBoundary() {
        var state = WhisperRealtimeEagerState()

        _ = state.apply(hypothesisText: "你好这是一个最小的回归测试")
        state.sealCurrentPublishedTextForNextUtterance()
        let published = state.apply(hypothesisText: "回归测试相比上一版")

        #expect(published == "你好这是一个最小的回归测试相比上一版")
        #expect(state.publishedText == "你好这是一个最小的回归测试相比上一版")
    }

    @Test
    func finalOverridesRealtimeState() {
        var state = WhisperRealtimeEagerState()

        _ = state.apply(hypothesisText: "draft text")
        let final = state.applyFinal("final corrected text")

        #expect(final == "final corrected text")
        #expect(state.publishedText == "final corrected text")
        #expect(state.liveCandidateText.isEmpty)
    }
}

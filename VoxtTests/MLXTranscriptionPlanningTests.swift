import XCTest
@testable import Voxt

final class MLXTranscriptionPlanningTests: XCTestCase {
    func testIntermediateSchedulingSkipsWhenAnotherPassIsInFlight() {
        let decision = MLXTranscriptionPlanning.correctionPassSchedulingDecision(
            requestedPass: .intermediate,
            inFlightPass: .intermediate
        )

        XCTAssertEqual(decision, .skipRequestedPass)
    }

    func testStopTimeSchedulingInterruptsInFlightIntermediatePass() {
        let decision = MLXTranscriptionPlanning.correctionPassSchedulingDecision(
            requestedPass: .postStopFinal,
            inFlightPass: .intermediate
        )

        XCTAssertEqual(decision, .interruptInFlightPass)
    }

    func testStopTimeSchedulingWaitsForAnotherStopPass() {
        let decision = MLXTranscriptionPlanning.correctionPassSchedulingDecision(
            requestedPass: .postStopFinal,
            inFlightPass: .postStopQuick
        )

        XCTAssertEqual(decision, .waitForInFlightPass)
    }

    func testMergedHiddenPostStopPreviewKeepsLongerBaseWhenCandidateIsContained() {
        let base = "文档目录结构都能被读取。你可以在文档列表中复制一份或多份文档，直接发起对话。"
        let candidate = "你可以在文档列表中复制一份或多份文档"

        let merged = MLXTranscriptionPlanning.mergedHiddenPostStopPreview(base: base, candidate: candidate)

        XCTAssertEqual(merged, base)
    }

    func testMergedHiddenPostStopPreviewAvoidsSuspiciousDuplicateGrowth() {
        let base = "比如写周报的时候，勾选本周的项目文档，让 AI 总结并更新到周报文档里。做 PPT 时，从资料库里挑素材，起稿就发起做一份某某汇报 PPT 的任务。"
        let candidate = "比如写周报的时候，勾选本周的项目文档，让 AI 总结并更新到周报文档里。做 PPT 时，从资料库里挑素材，起稿就发起做一份某某汇报 PPT 的任务，有了准确的上下文，生成的结果自然更贴近原文。"

        let merged = MLXTranscriptionPlanning.mergedHiddenPostStopPreview(base: base, candidate: candidate)

        XCTAssertEqual(merged, candidate)
    }

    func testMergedHiddenPostStopPreviewAvoidsConcatenatingLowOverlapFragments() {
        let base = "连接 Work Body 成功后，腾讯文档里的所有内容和目录结构都能被读取。你可以在文档列表中复制一份或多份文档，直接发起对话。"
        let candidate = "文档目录结构都能被读取。你可以在文档列表中复制一份或多份文档，直接发起对话，或者在新的任务里添加文档。AI 就能基于这些文档做出真实的内容思考和输出。"

        let merged = MLXTranscriptionPlanning.mergedHiddenPostStopPreview(base: base, candidate: candidate)

        XCTAssertEqual(merged, candidate)
        XCTAssertFalse(merged.contains("连接 Work Body 成功后，腾讯文档里的所有内容和目录结构都能被读取。你可以在文档列表中复制一份或多份文档，直接发起对话。 文档目录结构都能被读取。"))
    }

    func testMergedHiddenPostStopPreviewConcatenatesDisjointSentenceFragments() {
        let base = "比如写周报的时候，勾选本周的项目文档，让AI总结并更新到周报文档里。"
        let candidate = "做PPT时，从资料库里挑素材，起稿就发起一份“某某汇报PPT”的任务。有了准确的上下文，生成的结果自然更贴近原文。"

        let merged = MLXTranscriptionPlanning.mergedHiddenPostStopPreview(base: base, candidate: candidate)

        XCTAssertEqual(
            merged,
            "比如写周报的时候，勾选本周的项目文档，让AI总结并更新到周报文档里。做PPT时，从资料库里挑素材，起稿就发起一份“某某汇报PPT”的任务。有了准确的上下文，生成的结果自然更贴近原文。"
        )
    }

    func testMergedHiddenPostStopPreviewStitchesContinuationWhenCandidateStartsWithMinorNoise() {
        let base = "比如写作报的时候，勾选本周的项目文档，让AI总结并更新到周报文档里。"
        let candidate = "来总结并更新到周报文档里。做PPT时，从资料库里挑选素材，起稿就可以发一份“某某汇报PPT”的任务。有了准确的上下文，生成的结果自然更贴近原文。"

        let merged = MLXTranscriptionPlanning.mergedHiddenPostStopPreview(base: base, candidate: candidate)

        XCTAssertEqual(
            merged,
            "比如写作报的时候，勾选本周的项目文档，让AI总结并更新到周报文档里。做PPT时，从资料库里挑选素材，起稿就可以发一份“某某汇报PPT”的任务。有了准确的上下文，生成的结果自然更贴近原文。"
        )
    }
}

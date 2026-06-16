// MLXTranscriptionPlanningTests.swift
// Provides MLXTranscription Planning Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class MLXTranscriptionPlanningTests: XCTestCase {
    func testSenseVoiceUsesDirectPassForShortAudio() {
        let shouldUseVAD = MLXTranscriptionPlanning.shouldUseSenseVoiceVAD(
            sampleCount: 16000 * 12,
            sampleRate: 16000,
            directPassMaximumDurationSeconds: 30
        )

        XCTAssertFalse(shouldUseVAD)
    }

    func testSenseVoiceUsesVADForLongAudio() {
        let shouldUseVAD = MLXTranscriptionPlanning.shouldUseSenseVoiceVAD(
            sampleCount: 16000 * 40,
            sampleRate: 16000,
            directPassMaximumDurationSeconds: 30
        )

        XCTAssertTrue(shouldUseVAD)
    }

    func testSenseVoiceSplitRangeReturnsOriginalRangeWhenChunkingIsNotNeeded() {
        let ranges = MLXTranscriptionPlanning.splitSenseVoiceRange(
            start: 100,
            end: 1000,
            maxChunkSamples: 5000,
            overlapSamples: 320
        )

        XCTAssertEqual(ranges, [100..<1000])
    }

    func testSenseVoiceSplitRangeProducesOverlappingChunksForLongSegments() {
        let sampleCount = 16000 * 61
        let ranges = MLXTranscriptionPlanning.splitSenseVoiceRange(
            start: 0,
            end: sampleCount,
            maxChunkSamples: 16000 * 24,
            overlapSamples: Int(0.35 * 16000)
        )

        XCTAssertGreaterThan(ranges.count, 1)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, sampleCount)
        XCTAssertEqual(ranges[0].upperBound - ranges[1].lowerBound, Int(0.35 * 16000))
    }

    func testSenseVoiceVisibleRealtimeCorrectionCadenceIsMoreAggressive() {
        let cadence = MLXTranscriptionPlanning.correctionCadence(
            for: "mlx-community/SenseVoiceSmall",
            sessionAllowsRealtimeTextDisplay: true
        )

        XCTAssertEqual(cadence.correctionIntervalSeconds, 4.0, accuracy: 0.0001)
        XCTAssertEqual(cadence.firstCorrectionMinimumSeconds, 2.2, accuracy: 0.0001)
        XCTAssertEqual(cadence.intermediateContextWindowSeconds, 14.0, accuracy: 0.0001)
        XCTAssertEqual(cadence.quickPassContextWindowSeconds, 24.0, accuracy: 0.0001)
    }

    func testDefaultVisibleRealtimeCorrectionCadenceRemainsUnchanged() {
        let cadence = MLXTranscriptionPlanning.correctionCadence(
            for: "mlx-community/Qwen3-ASR-0.6B-4bit",
            sessionAllowsRealtimeTextDisplay: true
        )

        XCTAssertEqual(cadence.correctionIntervalSeconds, 6.0, accuracy: 0.0001)
        XCTAssertEqual(cadence.firstCorrectionMinimumSeconds, 3.5, accuracy: 0.0001)
        XCTAssertEqual(cadence.intermediateContextWindowSeconds, 18.0, accuracy: 0.0001)
        XCTAssertEqual(cadence.quickPassContextWindowSeconds, 30.0, accuracy: 0.0001)
    }

    func testSenseVoiceHiddenRealtimeCorrectionCadenceUsesShorterIntervals() {
        let cadence = MLXTranscriptionPlanning.correctionCadence(
            for: "mlx-community/SenseVoiceSmall",
            sessionAllowsRealtimeTextDisplay: false
        )

        XCTAssertEqual(cadence.correctionIntervalSeconds, 2.6, accuracy: 0.0001)
        XCTAssertEqual(cadence.firstCorrectionMinimumSeconds, 1.8, accuracy: 0.0001)
        XCTAssertEqual(cadence.intermediateContextWindowSeconds, 18.0, accuracy: 0.0001)
        XCTAssertEqual(cadence.quickPassContextWindowSeconds, 18.0, accuracy: 0.0001)
    }

    func testSenseVoiceSequentialMergeRemovesChunkBoundaryOverlap() {
        let merged = MLXTranscriptionPlanning.mergeSequentialTranscript(
            base: "hello world",
            next: "world again"
        )

        XCTAssertEqual(merged, "hello world again")
    }

    func testSenseVoiceSequentialMergeHandlesChineseBoundaryOverlap() {
        let merged = MLXTranscriptionPlanning.mergeSequentialTranscript(
            base: "我们正在测试长音频切分",
            next: "音频切分和合并效果"
        )

        XCTAssertEqual(merged, "我们正在测试长音频切分和合并效果")
    }

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

    func testQuickStopPassDisabledForNativeQwenLiveMode() {
        let plan = MLXFinalizationPlan(durationSeconds: 30, quickPassSampleCount: 16000 * 30)

        XCTAssertFalse(
            MLXTranscriptionPlanning.shouldRunQuickStopPass(
                plan: plan,
                sessionAllowsRealtimeTextDisplay: true,
                liveMode: .nativeQwenLive
            )
        )
        XCTAssertTrue(
            MLXTranscriptionPlanning.shouldRunQuickStopPass(
                plan: plan,
                sessionAllowsRealtimeTextDisplay: true,
                liveMode: .batchPreview
            )
        )
    }

    func testNativeLiveVisiblePreviewSuppressesSilentCollapseWhenConfirmedIsUnchanged() {
        XCTAssertNil(
            MLXTranscriptionPlanning.resolvedNativeLiveVisiblePreview(
                previousPreview: "hello world",
                previousConfirmedText: "hello",
                confirmedText: "hello",
                provisionalText: ""
            )
        )
    }

    func testNativeLiveVisiblePreviewAllowsNewCombinedText() {
        XCTAssertEqual(
            MLXTranscriptionPlanning.resolvedNativeLiveVisiblePreview(
                previousPreview: "hello",
                previousConfirmedText: "hello",
                confirmedText: "hello",
                provisionalText: " world"
            ),
            "hello world"
        )
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

import XCTest
@testable import Voxt

final class SessionTimingSummarySupportTests: XCTestCase {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("session_timing_summary_samples.log")
    }

    func testParsesSessionTimingSummaryLine() throws {
        let line = """
        [Voxt] 2026-05-12T02:57:31.024Z [INFO] Session timing summary. output=transcription, pipeline=finalOnly, stages=record>stop>finalASR>enhance>deliver, asrProvider=mlx, asrModel=mlx-community/Qwen3-ASR-0.6B-bf16, llmCalls=1, deliveredChars=97, didInject=true, requestToStartMs=132, startToStopMs=28485, startToFirstLiveASRMs=n/a, capturedAudioMs=28100, captureGapMs=385, stopToASRMs=3639, asrToFirstLLMChunkMs=656, asrToFirstLLMCompleteMs=1637, asrToFinalLLMCompleteMs=1637, asrToDeliveredMs=1718, stopToDeliveredMs=5357, overallMs=33975, firstLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=625,prefillMs=585,generationMs=977,totalElapsedMs=1606, finalLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=625,prefillMs=585,generationMs=977,totalElapsedMs=1606
        """

        let record = try XCTUnwrap(SessionTimingSummarySupport.parse(line: line))
        XCTAssertEqual(record.output, "transcription")
        XCTAssertEqual(record.pipeline, "finalOnly")
        XCTAssertEqual(record.stages, "record>stop>finalASR>enhance>deliver")
        XCTAssertEqual(record.llmCalls, 1)
        XCTAssertEqual(record.asrProvider, "mlx")
        XCTAssertEqual(record.asrModel, "mlx-community/Qwen3-ASR-0.6B-bf16")
        XCTAssertEqual(record.captureGapMs, 385)
        XCTAssertEqual(record.stopToASRMs, 3639)
        XCTAssertEqual(record.stopToDeliveredMs, 5357)
        XCTAssertEqual(record.llmProvider, "customLLM(mlx-community/Qwen3.5-2B-4bit)")
    }

    func testAggregatesMainPathTimingAverages() throws {
        let lines = [
            """
            [Voxt] 2026-05-12T02:02:49.881Z [INFO] Session timing summary. output=transcription, pipeline=finalOnly, stages=record>stop>finalASR>enhance>deliver, asrProvider=mlx, asrModel=mlx-community/Qwen3-ASR-0.6B-bf16, llmCalls=1, deliveredChars=96, didInject=true, requestToStartMs=140, startToStopMs=27395, startToFirstLiveASRMs=n/a, capturedAudioMs=27000, captureGapMs=395, stopToASRMs=3093, asrToFirstLLMChunkMs=834, asrToFirstLLMCompleteMs=1821, asrToFinalLLMCompleteMs=1821, asrToDeliveredMs=1894, stopToDeliveredMs=4988, overallMs=32524, firstLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=802,prefillMs=752,generationMs=983,totalElapsedMs=1789, finalLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=802,prefillMs=752,generationMs=983,totalElapsedMs=1789
            """,
            """
            [Voxt] 2026-05-12T02:24:59.991Z [INFO] Session timing summary. output=transcription, pipeline=finalOnly, stages=record>stop>finalASR>enhance>deliver, asrProvider=mlx, asrModel=mlx-community/Qwen3-ASR-0.6B-bf16, llmCalls=2, deliveredChars=96, didInject=true, requestToStartMs=1655, startToStopMs=26144, startToFirstLiveASRMs=n/a, capturedAudioMs=25800, captureGapMs=344, stopToASRMs=4392, asrToFirstLLMChunkMs=0, asrToFirstLLMCompleteMs=0, asrToFinalLLMCompleteMs=1841, asrToDeliveredMs=1909, stopToDeliveredMs=6302, overallMs=34102, firstLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=1247,prefillMs=1197,generationMs=1484,totalElapsedMs=2735, finalLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=822,prefillMs=786,generationMs=986,totalElapsedMs=1812
            """,
            """
            [Voxt] 2026-05-12T02:57:31.024Z [INFO] Session timing summary. output=transcription, pipeline=finalOnly, stages=record>stop>finalASR>enhance>deliver, asrProvider=mlx, asrModel=mlx-community/Qwen3-ASR-0.6B-bf16, llmCalls=1, deliveredChars=97, didInject=true, requestToStartMs=132, startToStopMs=28485, startToFirstLiveASRMs=n/a, capturedAudioMs=28100, captureGapMs=385, stopToASRMs=3639, asrToFirstLLMChunkMs=656, asrToFirstLLMCompleteMs=1637, asrToFinalLLMCompleteMs=1637, asrToDeliveredMs=1718, stopToDeliveredMs=5357, overallMs=33975, firstLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=625,prefillMs=585,generationMs=977,totalElapsedMs=1606, finalLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=625,prefillMs=585,generationMs=977,totalElapsedMs=1606
            """
        ]

        let records = try lines.map {
            try XCTUnwrap(SessionTimingSummarySupport.parse(line: $0))
        }
        let aggregate = SessionTimingSummarySupport.aggregate(records)

        XCTAssertEqual(aggregate.sampleCount, 3)
        XCTAssertEqual(aggregate.meanLLMCalls, 4.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(aggregate.meanStopToDeliveredMs), 5549.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(aggregate.meanStopToASRMs), 3708.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(aggregate.meanCaptureGapMs), 374.6666666666667, accuracy: 0.0001)
    }

    func testAggregatesRecentSamplesPerProviderAndPipeline() throws {
        let lines = [
            """
            [Voxt] 2026-05-12T02:02:49.881Z [INFO] Session timing summary. output=transcription, pipeline=finalOnly, stages=record>stop>finalASR>enhance>deliver, asrProvider=mlx, asrModel=mlx-community/Qwen3-ASR-0.6B-bf16, llmCalls=1, deliveredChars=96, didInject=true, requestToStartMs=140, startToStopMs=27395, startToFirstLiveASRMs=n/a, capturedAudioMs=27000, captureGapMs=395, stopToASRMs=3093, asrToFirstLLMChunkMs=834, asrToFirstLLMCompleteMs=1821, asrToFinalLLMCompleteMs=1821, asrToDeliveredMs=1894, stopToDeliveredMs=4988, overallMs=32524, firstLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=802,prefillMs=752,generationMs=983,totalElapsedMs=1789, finalLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=802,prefillMs=752,generationMs=983,totalElapsedMs=1789
            """,
            """
            [Voxt] 2026-05-12T02:24:59.991Z [INFO] Session timing summary. output=transcription, pipeline=finalOnly, stages=record>stop>finalASR>enhance>deliver, asrProvider=mlx, asrModel=mlx-community/Qwen3-ASR-0.6B-bf16, llmCalls=2, deliveredChars=96, didInject=true, requestToStartMs=1655, startToStopMs=26144, startToFirstLiveASRMs=n/a, capturedAudioMs=25800, captureGapMs=344, stopToASRMs=4392, asrToFirstLLMChunkMs=0, asrToFirstLLMCompleteMs=0, asrToFinalLLMCompleteMs=1841, asrToDeliveredMs=1909, stopToDeliveredMs=6302, overallMs=34102, firstLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=1247,prefillMs=1197,generationMs=1484,totalElapsedMs=2735, finalLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=822,prefillMs=786,generationMs=986,totalElapsedMs=1812
            """,
            """
            [Voxt] 2026-05-12T02:57:31.024Z [INFO] Session timing summary. output=transcription, pipeline=finalOnly, stages=record>stop>finalASR>enhance>deliver, asrProvider=mlx, asrModel=mlx-community/Qwen3-ASR-0.6B-bf16, llmCalls=1, deliveredChars=97, didInject=true, requestToStartMs=132, startToStopMs=28485, startToFirstLiveASRMs=n/a, capturedAudioMs=28100, captureGapMs=385, stopToASRMs=3639, asrToFirstLLMChunkMs=656, asrToFirstLLMCompleteMs=1637, asrToFinalLLMCompleteMs=1637, asrToDeliveredMs=1718, stopToDeliveredMs=5357, overallMs=33975, firstLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=625,prefillMs=585,generationMs=977,totalElapsedMs=1606, finalLLM=task=enhancement,provider=customLLM(mlx-community/Qwen3.5-2B-4bit),firstChunkMs=625,prefillMs=585,generationMs=977,totalElapsedMs=1606
            """,
            """
            [Voxt] 2026-05-11T15:00:00.000Z [INFO] Session timing summary. output=translation, pipeline=liveDisplay, stages=record>liveASR>stop>previewASR>finalASR>enhance>deliver, asrProvider=remote:openAIWhisper, asrModel=gpt-4o-mini-transcribe, llmCalls=2, deliveredChars=44, didInject=true, requestToStartMs=120, startToStopMs=14000, startToFirstLiveASRMs=900, capturedAudioMs=13800, captureGapMs=200, stopToASRMs=2500, asrToFirstLLMChunkMs=20, asrToFirstLLMCompleteMs=100, asrToFinalLLMCompleteMs=800, asrToDeliveredMs=900, stopToDeliveredMs=3400, overallMs=17500, firstLLM=task=enhancement,provider=customLLM(other-model),firstChunkMs=300,prefillMs=250,generationMs=400,totalElapsedMs=700, finalLLM=task=enhancement,provider=customLLM(other-model),firstChunkMs=280,prefillMs=220,generationMs=380,totalElapsedMs=640
            """
        ]

        let records = try lines.map {
            try XCTUnwrap(SessionTimingSummarySupport.parse(line: $0))
        }
        let aggregates = SessionTimingSummarySupport.aggregateRecent(records, limit: 2)

        let mlxKey = SessionTimingSummaryKey(
            output: "transcription",
            pipeline: "finalOnly",
            asrProvider: "mlx",
            asrModel: "mlx-community/Qwen3-ASR-0.6B-bf16",
            llmProvider: "customLLM(mlx-community/Qwen3.5-2B-4bit)"
        )
        let mlxAggregate = try XCTUnwrap(aggregates[mlxKey])
        XCTAssertEqual(mlxAggregate.sampleCount, 2)
        XCTAssertEqual(mlxAggregate.meanLLMCalls, 1.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(mlxAggregate.meanStopToASRMs), 4015.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(mlxAggregate.meanStopToDeliveredMs), 5829.5, accuracy: 0.0001)

        let otherKey = SessionTimingSummaryKey(
            output: "translation",
            pipeline: "liveDisplay",
            asrProvider: "remote:openAIWhisper",
            asrModel: "gpt-4o-mini-transcribe",
            llmProvider: "customLLM(other-model)"
        )
        let otherAggregate = try XCTUnwrap(aggregates[otherKey])
        XCTAssertEqual(otherAggregate.sampleCount, 1)
        XCTAssertEqual(otherAggregate.meanLLMCalls, 2.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(otherAggregate.meanStopToASRMs), 2500.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(otherAggregate.meanStopToDeliveredMs), 3400.0, accuracy: 0.0001)
    }

    func testParsesAllRecordsFromFixtureLog() throws {
        let text = try String(contentsOf: fixtureURL, encoding: .utf8)
        let records = SessionTimingSummarySupport.parseAll(lines: text)

        XCTAssertEqual(records.count, 4)
        XCTAssertEqual(records.first?.asrProvider, "mlx")
        XCTAssertEqual(records.first?.pipeline, "finalOnly")
        XCTAssertEqual(records.last?.asrProvider, "remote:openAIWhisper")
        XCTAssertEqual(records.last?.asrModel, "gpt-4o-mini-transcribe")
    }

    func testSortedReportRowsUsesRecentLimitPerASRAndPipeline() throws {
        let text = try String(contentsOf: fixtureURL, encoding: .utf8)
        let records = SessionTimingSummarySupport.parseAll(lines: text)
        let rows = SessionTimingSummarySupport.sortedReportRows(records, limit: 2)

        XCTAssertEqual(rows.count, 2)

        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(first.key.asrProvider, "mlx")
        XCTAssertEqual(first.key.asrModel, "mlx-community/Qwen3-ASR-0.6B-bf16")
        XCTAssertEqual(first.key.pipeline, "finalOnly")
        XCTAssertEqual(first.aggregate.sampleCount, 2)
        XCTAssertEqual(first.aggregate.meanLLMCalls, 1.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(first.aggregate.meanStopToDeliveredMs), 5829.5, accuracy: 0.0001)

        let second = try XCTUnwrap(rows.last)
        XCTAssertEqual(second.key.asrProvider, "remote:openAIWhisper")
        XCTAssertEqual(second.key.asrModel, "gpt-4o-mini-transcribe")
        XCTAssertEqual(second.key.pipeline, "liveDisplay")
        XCTAssertEqual(second.aggregate.sampleCount, 1)
        XCTAssertEqual(second.aggregate.meanLLMCalls, 2.0, accuracy: 0.0001)
    }
}

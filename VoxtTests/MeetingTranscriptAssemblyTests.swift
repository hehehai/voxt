import XCTest
@testable import Voxt

final class MeetingTranscriptAssemblyTests: XCTestCase {
    func testPartialThenFinalReusesSegmentID() {
        let id = UUID()
        let partial = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 2.5,
            text: "hello"
        )
        let final = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 3,
            text: "hello world"
        )

        let partialResult = MeetingTranscriptAssembler.apply(.partial(partial), to: [])
        let finalResult = MeetingTranscriptAssembler.apply(.final(final), to: partialResult.segments)

        XCTAssertEqual(partialResult.segments.count, 1)
        XCTAssertEqual(finalResult.segments.count, 1)
        XCTAssertEqual(finalResult.segments[0].id, id)
        XCTAssertEqual(finalResult.segments[0].text, "hello world")
        XCTAssertEqual(finalResult.finalizedSegmentID, id)
    }

    func testFinalSegmentsMergeWithinTwoSecondsForSameSpeaker() {
        let first = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .me,
            startSeconds: 1,
            endSeconds: 2,
            text: "hello"
        )
        let second = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .me,
            startSeconds: 3.2,
            endSeconds: 4.1,
            text: "world"
        )

        let firstResult = MeetingTranscriptAssembler.apply(.final(first), to: [])
        let secondResult = MeetingTranscriptAssembler.apply(.final(second), to: firstResult.segments)

        XCTAssertEqual(secondResult.segments.count, 1)
        XCTAssertEqual(secondResult.segments[0].text, "hello world")
        XCTAssertEqual(Set(secondResult.supersededSegmentIDs), Set([first.id, second.id]))
        XCTAssertEqual(secondResult.finalizedSegmentID, first.id)
    }

    func testDifferentSpeakersDoNotMerge() {
        let first = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .me,
            startSeconds: 1,
            endSeconds: 2,
            text: "hello"
        )
        let second = MeetingTranscriptSegment(
            id: UUID(),
            speaker: .them,
            startSeconds: 2.5,
            endSeconds: 3,
            text: "world"
        )

        let firstResult = MeetingTranscriptAssembler.apply(.final(first), to: [])
        let secondResult = MeetingTranscriptAssembler.apply(.final(second), to: firstResult.segments)

        XCTAssertEqual(secondResult.segments.count, 2)
        XCTAssertTrue(secondResult.supersededSegmentIDs.isEmpty)
    }

    func testUpdatedSegmentPreservesExistingTranslationWhileRefreshIsPending() {
        let id = UUID()
        let existing = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 4,
            text: "hello there",
            translatedText: "你好",
            isTranslationPending: false
        )
        let updated = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 5,
            text: "hello there again"
        )

        let result = MeetingTranscriptAssembler.apply(.final(updated), to: [existing])

        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].translatedText, "你好")
        XCTAssertTrue(result.segments[0].isTranslationPending)
    }

    func testUpdatedSegmentDoesNotEnterPendingStateWithoutExistingTranslation() {
        let id = UUID()
        let existing = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 4,
            text: "hello there",
            translatedText: nil,
            isTranslationPending: false
        )
        let updated = MeetingTranscriptSegment(
            id: id,
            speaker: .them,
            startSeconds: 2,
            endSeconds: 5,
            text: "hello there again"
        )

        let result = MeetingTranscriptAssembler.apply(.final(updated), to: [existing])

        XCTAssertEqual(result.segments.count, 1)
        XCTAssertNil(result.segments[0].translatedText)
        XCTAssertFalse(result.segments[0].isTranslationPending)
    }

    func testFinalTextPostProcessorCollapsesSpacedAcronyms() {
        let text = MeetingTranscriptTextPostProcessor.normalizedFinalText("放进 C P U，然后做 R L 微调。")

        XCTAssertEqual(text, "放进 CPU，然后做 RL 微调。")
    }

    func testFinalPostProcessorMergesOverlappingAdjacentSegments() {
        let first = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 0,
            endSeconds: 10,
            text: "We should move data into CPU memory"
        )
        let second = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 9.2,
            endSeconds: 18,
            text: "CPU memory before running RL"
        )

        let result = MeetingTranscriptPostProcessor.process([first, second])
        let combinedText = result.map(\.text).joined(separator: " ")

        XCTAssertGreaterThanOrEqual(result.count, 1)
        XCTAssertEqual(combinedText, "We should move data into CPU memory before running RL")
        XCTAssertEqual(result.first?.startSeconds ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(result.last?.endSeconds ?? -1, 18, accuracy: 0.001)
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].preventsAdjacentMerge)
    }

    func testFinalPostProcessorDoesNotChainLongOverlappingChunksWithoutTextOverlap() {
        let first = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 0,
            endSeconds: 16,
            text: "We discussed the project background and model engine choices."
        )
        let second = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 15,
            endSeconds: 31,
            text: "The next part focused on safety and deployment tradeoffs."
        )

        let result = MeetingTranscriptPostProcessor.process([first, second])

        XCTAssertGreaterThanOrEqual(result.count, 2)
        XCTAssertEqual(result.map(\.text).joined(separator: " "), "\(first.text) \(second.text)")
        XCTAssertTrue(result.contains { $0.startSeconds >= 15 })
        XCTAssertTrue(result.allSatisfy { !$0.text.contains("backgr ound") })
    }

    func testFinalPostProcessorHonorsPreventAdjacentMergeBoundaries() {
        let first = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 0,
            endSeconds: 3,
            text: "first turn",
            preventsAdjacentMerge: true
        )
        let second = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 3.1,
            endSeconds: 5,
            text: "second turn"
        )

        let result = MeetingTranscriptPostProcessor.process([first, second])

        XCTAssertEqual(result.count, 2)
    }

    func testFinalPostProcessorSplitsLongSingleSegmentIntoReadableChunks() {
        let segment = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 0,
            endSeconds: 60,
            text: "第一段内容主要介绍项目背景和模型选择，大家先讨论了系统音频和麦克风的采集。第二段内容继续讨论发言人识别和时间对齐，需要避免所有内容都挤在一个段落里。第三段内容强调即使只有一个发言人结果，也要按照阅读节奏拆成更短的段落。"
        )

        let result = MeetingTranscriptPostProcessor.process(
            [segment],
            options: MeetingTranscriptPostProcessor.Options(maxSegmentTextCharacters: 45)
        )

        XCTAssertGreaterThan(result.count, 1)
        XCTAssertEqual(result.first?.id, segment.id)
        XCTAssertTrue(result.allSatisfy(\.preventsAdjacentMerge))
        XCTAssertTrue(result.allSatisfy { $0.text.count <= 45 })
        XCTAssertEqual(result.first?.startSeconds ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(result.last?.endSeconds ?? -1, 60, accuracy: 0.001)
    }

    func testFinalPostProcessorSplitsRealMeetingExportSampleIntoReadableChunks() {
        let exportedText = "哎。一些可能。不那么需要的。放在起，放进 C P U。好了，非常感谢万晨老师。我觉得我们也。可以到下一个环节了。我们啊，除了要推理方面的优化。阿西拉，相比于。啊，不一样的这个解解解决方案。我们也提供了这个。带领就。立马，我们就有了一个 R L 上的这个知识。相当于说。直接就可以拿你的数据在上面进行一些微调。啊，进行一些。标化。然后让让它能够适用在你的这个使用场。场景中。那么这里的话，我也邀请我们下一位同学。上来给我们。介绍一下这个 mouse 相关的啊，还是。Java开发。对。嗯，我觉得其实带领。二 L 这样事件本身。"
        let segment = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 4,
            endSeconds: 45,
            text: exportedText
        )

        let result = MeetingTranscriptPostProcessor.process([segment])

        XCTAssertGreaterThan(result.count, 1)
        XCTAssertTrue(result.allSatisfy { $0.text.count <= 140 })
        XCTAssertEqual(result.first?.id, segment.id)
        XCTAssertEqual(result.first?.startSeconds ?? -1, 4, accuracy: 0.001)
        XCTAssertEqual(result.last?.endSeconds ?? -1, 45, accuracy: 0.001)
        XCTAssertEqual(result.map(\.text).joined(), MeetingTranscriptTextPostProcessor.normalizedFinalText(exportedText))
    }

    func testFinalPostProcessorKeepsCoherentShortTextTogetherEvenWhenDurationIsLong() {
        let segment = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 0,
            endSeconds: 35,
            text: "第一句介绍背景。第二句解释方案。第三句讨论风险。第四句确认下一步。"
        )

        let result = MeetingTranscriptPostProcessor.process([segment])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.startSeconds ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(result.last?.endSeconds ?? -1, 35, accuracy: 0.001)
    }

    func testFinalPostProcessorDoesNotMergeAcrossReadablePauseGap() {
        let first = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 0,
            endSeconds: 2,
            text: "第一句讲完一个完整观点。"
        )
        let second = MeetingTranscriptSegment(
            speaker: .them,
            speakerID: "S1",
            speakerDisplayName: "Speaker 1",
            audioSource: .systemAudio,
            startSeconds: 2.8,
            endSeconds: 4,
            text: "停顿后开始新的观点。"
        )

        let result = MeetingTranscriptPostProcessor.process([first, second])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.text), [first.text, second.text])
    }

    func testFinalTranscriptionPassBuildsLongOverlappingChunksPerSource() {
        let samples = [Float](repeating: 0.1, count: 40)
        let asset = MeetingAudioAsset(
            source: .systemAudio,
            samples: samples,
            sampleRate: 10,
            sessionStartOffset: 3
        )

        let chunks = MeetingFinalTranscriptionPass.chunks(
            for: asset,
            options: MeetingFinalTranscriptionPass.Options(
                maxChunkSeconds: 2,
                overlapSeconds: 0.5,
                minimumChunkSeconds: 0.5,
                minimumRMS: 0.001
            )
        )

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].startSeconds, 3, accuracy: 0.001)
        XCTAssertEqual(chunks[0].endSeconds, 5, accuracy: 0.001)
        XCTAssertEqual(chunks[1].startSeconds, 4.5, accuracy: 0.001)
        XCTAssertEqual(chunks[1].speaker, .them)
    }

    func testFinalTranscriptionPassUsesMicrophoneSpeakerForMicrophoneAssets() {
        let asset = MeetingAudioAsset(
            source: .microphone,
            samples: [Float](repeating: 0.1, count: 20),
            sampleRate: 10,
            sessionStartOffset: 0
        )

        let chunks = MeetingFinalTranscriptionPass.chunks(
            for: asset,
            options: MeetingFinalTranscriptionPass.Options(
                maxChunkSeconds: 3,
                overlapSeconds: 0,
                minimumChunkSeconds: 0.5,
                minimumRMS: 0.001
            )
        )

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { $0.speaker == .me })
    }

    func testFinalTranscriptionPassSplitsChunksOnLongSilence() {
        let samples =
            [Float](repeating: 0.1, count: 12) +
            [Float](repeating: 0, count: 10) +
            [Float](repeating: 0.1, count: 12)
        let asset = MeetingAudioAsset(
            source: .systemAudio,
            samples: samples,
            sampleRate: 10,
            sessionStartOffset: 3
        )

        let chunks = MeetingFinalTranscriptionPass.chunks(
            for: asset,
            options: MeetingFinalTranscriptionPass.Options(
                maxChunkSeconds: 10,
                overlapSeconds: 0,
                minimumChunkSeconds: 0.2,
                minimumRMS: 0.001,
                silenceSplitSeconds: 0.8,
                silenceWindowSeconds: 0.1,
                speechPaddingSeconds: 0
            )
        )

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].startSeconds, 3, accuracy: 0.001)
        XCTAssertEqual(chunks[0].endSeconds, 4.2, accuracy: 0.001)
        XCTAssertEqual(chunks[1].startSeconds, 5.2, accuracy: 0.001)
        XCTAssertEqual(chunks[1].endSeconds, 6.4, accuracy: 0.001)
        XCTAssertTrue(chunks.allSatisfy(\.preventsAdjacentMerge))
    }
}

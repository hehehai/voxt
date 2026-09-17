import Foundation
import XCTest
@testable import Voxt

@MainActor
final class MeetingFileResourceSafetyTests: XCTestCase {
    func testDurationAndOfflineSpeakerBudgetsAreBounded() throws {
        XCTAssertEqual(try MeetingFileResourcePolicy.preparedByteCount(duration: 3600), 115_200_044)
        for duration in [Double.nan, .infinity, -1, 0, 43_201] {
            XCTAssertThrowsError(try MeetingFileResourcePolicy.preparedByteCount(duration: duration))
        }
        XCTAssertTrue(MeetingFileResourcePolicy.allowsOfflineSpeakers(duration: 1800, physicalMemory: 8 * 1024 * 1024 * 1024))
        XCTAssertFalse(MeetingFileResourcePolicy.allowsOfflineSpeakers(duration: 1801, physicalMemory: 8 * 1024 * 1024 * 1024))
        XCTAssertTrue(MeetingFileResourcePolicy.allowsOfflineSpeakers(duration: 3600, physicalMemory: 16 * 1024 * 1024 * 1024))
        XCTAssertFalse(MeetingFileResourcePolicy.allowsOfflineSpeakers(duration: 3601, physicalMemory: 16 * 1024 * 1024 * 1024))
        XCTAssertFalse(MeetingFileResourcePolicy.allowsOfflineSpeakers(duration: .nan, physicalMemory: UInt64.max))
    }

    func testCheckpointRestoresCommittedWindowsAndStableHistoryID() async throws {
        let directory = try TemporaryDirectory()
        let source = try makeSource(in: directory.url)
        let store = MeetingFileCheckpointStore(sourceURL: source, signature: "configuration")
        let initial = try await store.load(windowCount: 2)
        let segment = makeSegment("saved", start: 0)
        try await store.commit(index: 0, segments: [segment])

        let restoredStore = MeetingFileCheckpointStore(sourceURL: source, signature: "configuration")
        let restored = try await restoredStore.load(windowCount: 2)
        XCTAssertEqual(restored.historyID, initial.historyID)
        XCTAssertEqual(restored.completedWindows, 1)
        XCTAssertEqual(restored.segments, [segment])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRestoredMergeBoundariesMatchUninterruptedPostProcessing() async throws {
        let directory = try TemporaryDirectory()
        let source = try makeSource(in: directory.url)
        let store = MeetingFileCheckpointStore(sourceURL: source, signature: "same")
        _ = try await store.load(windowCount: 1)
        let segments = [
            makeSegment("first clause", start: 0),
            MeetingTranscriptSegment(speaker: .them, startSeconds: 1, endSeconds: 2, text: "second clause")
        ]
        try await store.commit(index: 0, segments: segments)
        let restored = try await store.load(windowCount: 1)
        XCTAssertEqual(restored.segments.map(\.preventsAdjacentMerge), [true, false])
        let uninterrupted = MeetingTranscriptPostProcessor.process(segments)
        let resumed = MeetingTranscriptPostProcessor.process(restored.segments)
        XCTAssertEqual(uninterrupted.count, 2)
        XCTAssertEqual(resumed, uninterrupted)
    }

    func testInputSizeChangeInvalidatesCheckpointWithReusedStore() async throws {
        let directory = try TemporaryDirectory()
        let source = try makeSource(in: directory.url)
        let store = MeetingFileCheckpointStore(sourceURL: source, signature: "same")
        _ = try await store.load(windowCount: 1)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 44)
        try handle.close()
        do {
            _ = try await store.load(windowCount: 1)
            XCTFail("Changed input size must invalidate a cached checkpoint")
        } catch MeetingFileWorkError.invalidCheckpoint {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCheckpointRejectsConfigurationChangesAndCorruptionWithoutDeletingResults() async throws {
        let directory = try TemporaryDirectory()
        let source = try makeSource(in: directory.url)
        let store = MeetingFileCheckpointStore(sourceURL: source, signature: "old")
        _ = try await store.load(windowCount: 2)
        try await store.commit(index: 0, segments: [makeSegment("keep", start: 0)])
        do {
            _ = try await MeetingFileCheckpointStore(sourceURL: source, signature: "new").load(windowCount: 2)
            XCTFail("Must not mix configurations")
        } catch MeetingFileWorkError.incompatibleCheckpoint {} catch { XCTFail("Unexpected error: \(error)") }

        let window = MeetingFileCheckpointStore.directory(for: source).appendingPathComponent("window-00000.json")
        try Data("broken".utf8).write(to: window)
        do {
            _ = try await store.load(windowCount: 2)
            XCTFail("Must report a damaged committed window")
        } catch MeetingFileWorkError.invalidCheckpoint {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: window.path))
    }

    func testCompletedTranscriptionCanAnalyzeSpeakersWithChangedASRSettings() async throws {
        let directory = try TemporaryDirectory()
        let source = try makeSource(in: directory.url)
        let store = MeetingFileCheckpointStore(sourceURL: source, signature: "old", engineRawValue: "old-engine", modelDescription: "old-model")
        let initial = try await store.load(windowCount: 1)
        try await store.commit(index: 0, segments: [makeSegment("complete", start: 0)])
        let changed = MeetingFileCheckpointStore(sourceURL: source, signature: "new", engineRawValue: "new-engine", modelDescription: "new-model")
        let restored = try await changed.load(windowCount: 1)
        XCTAssertEqual(restored.completedWindows, 1)
        XCTAssertEqual(restored.historyID, initial.historyID)
        XCTAssertEqual(restored.transcriptionEngineRawValue, "old-engine")
        XCTAssertEqual(restored.transcriptionModelDescription, "old-model")
    }

    func testSettingsCanBeFixedBeforeAnyWindowIsCommitted() async throws {
        let directory = try TemporaryDirectory()
        let source = try makeSource(in: directory.url)
        let initial = try await MeetingFileCheckpointStore(sourceURL: source, signature: "old").load(windowCount: 2)
        let changed = MeetingFileCheckpointStore(sourceURL: source, signature: "new", modelDescription: "fixed")
        let restored = try await changed.load(windowCount: 2)
        XCTAssertEqual(restored.completedWindows, 0)
        XCTAssertEqual(restored.historyID, initial.historyID)
        XCTAssertEqual(restored.transcriptionModelDescription, "fixed")
    }

    func testInputReplacementInvalidatesCheckpoint() async throws {
        let directory = try TemporaryDirectory()
        let source = try makeSource(in: directory.url)
        let store = MeetingFileCheckpointStore(sourceURL: source, signature: "same")
        _ = try await store.load(windowCount: 1)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: source.path)
        do {
            _ = try await store.load(windowCount: 1)
            XCTFail("Changed input must not reuse old text")
        } catch MeetingFileWorkError.invalidCheckpoint {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testInterruptedWindowIsReplayedWithoutRetranscribingCommittedWindows() async throws {
        let directory = try TemporaryDirectory()
        let source = try makeSource(in: directory.url)
        let store = MeetingFileCheckpointStore(sourceURL: source, signature: "same")
        _ = try await store.load(windowCount: 2)
        let descriptors = [0, 20].map {
            MeetingAudioAssetDescriptor(source: .mixed, sampleRate: 10, startSample: $0, sampleCount: 20)
        }
        let failing = FileWindowTestTranscriber(failAt: 2)
        do {
            _ = try await MeetingFinalTranscriptionPass.transcribe(
                descriptors: descriptors, loadAsset: { await Self.asset($0) },
                transcriber: failing,
                commitWindow: { try await store.commit(index: $0, segments: $1) }
            )
            XCTFail("Second window should fail")
        } catch FileWindowTestError.interrupted {} catch { XCTFail("Unexpected error: \(error)") }
        let saved = try await store.load(windowCount: 2)
        XCTAssertEqual(saved.completedWindows, 1)
        let succeeding = FileWindowTestTranscriber()
        let segments = try await MeetingFinalTranscriptionPass.transcribe(
            descriptors: descriptors, loadAsset: { await Self.asset($0) }, transcriber: succeeding,
            completedWindowCount: saved.completedWindows, restoredSegments: saved.segments,
            commitWindow: { try await store.commit(index: $0, segments: $1) }
        )
        XCTAssertEqual(succeeding.starts, [2])
        XCTAssertEqual(segments.map(\.text), ["window 0", "window 2"])
        let complete = try await store.load(windowCount: 2)
        XCTAssertEqual(complete.completedWindows, 2)
        XCTAssertEqual(complete.segments.count, 2)
    }

    func testSilentWindowIsCommittedAndNotLoadedAgain() async throws {
        let descriptor = MeetingAudioAssetDescriptor(source: .mixed, sampleRate: 10, startSample: 0, sampleCount: 20)
        let recorder = FileWindowCommitRecorder()
        _ = try await MeetingFinalTranscriptionPass.transcribe(
            descriptors: [descriptor],
            loadAsset: { descriptor in
                MeetingAudioAsset(source: .mixed, samples: Array(repeating: 0, count: 20), sampleRate: 10, sessionStartOffset: 0)
            },
            transcriber: FileWindowChunkTranscriber(),
            commitWindow: { await recorder.record(index: $0, segments: $1) }
        )
        let indices = await recorder.indices
        XCTAssertEqual(indices, [0])
        let resumed = try await MeetingFinalTranscriptionPass.transcribe(
            descriptors: [descriptor], loadAsset: { _ in XCTFail("Committed silence should not load"); return nil },
            transcriber: FileWindowChunkTranscriber(), completedWindowCount: 1
        )
        XCTAssertTrue(resumed.isEmpty)
    }

    func testCanonicalReaderRejectsHeaderMismatchAndArchiveCopyKeepsInput() throws {
        let directory = try TemporaryDirectory()
        let source = try makeSource(in: directory.url)
        let prepared = try MeetingImportedAudioFile.openPrepared(at: source)
        XCTAssertEqual(prepared.sampleCount, 160)
        let copy = directory.url.appendingPathComponent("copy.wav")
        try MeetingFileArchiveCopy.create(from: source, to: copy)
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: source))
        XCTAssertThrowsError(try MeetingFileArchiveCopy.create(from: source, to: copy))
        var data = try Data(contentsOf: copy)
        data[22] = 2 // stereo must not masquerade as canonical mono
        try data.write(to: copy)
        XCTAssertThrowsError(try MeetingImportedAudioFile.openPrepared(at: copy))
        XCTAssertNoThrow(try MeetingImportedAudioFile.openPrepared(at: source))
    }

    func testSynchronousQueuePersistenceReportsFailure() throws {
        let directory = try TemporaryDirectory()
        let blockedParent = directory.url.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blockedParent)
        let persistence = AsyncJSONPersistenceCoordinator(label: "test.file-analysis.persistence")
        XCTAssertFalse(persistence.flushWrite(["state": "completed"], to: blockedParent.appendingPathComponent("tasks.json")))
        XCTAssertTrue(persistence.flushWrite(["state": "completed"], to: directory.url.appendingPathComponent("tasks.json")))
    }

    func testSignatureIsOrderAndBoundarySensitive() {
        XCTAssertNotEqual(MeetingFileCheckpointStore.signature(parts: ["ab", "c"]), MeetingFileCheckpointStore.signature(parts: ["a", "bc"]))
        XCTAssertEqual(MeetingFileCheckpointStore.signature(parts: ["a"]), MeetingFileCheckpointStore.signature(parts: ["a"]))
    }

    private func makeSource(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("input.wav")
        try MeetingAudioChunkWAVExporter.write(samples: Array(repeating: 0.1, count: 160), sampleRate: 16_000, to: url)
        return url
    }

    private func makeSegment(_ text: String, start: Double) -> MeetingTranscriptSegment {
        MeetingTranscriptSegment(speaker: .them, startSeconds: start, endSeconds: start + 1, text: text, preventsAdjacentMerge: true)
    }

    private static func asset(_ descriptor: MeetingAudioAssetDescriptor) -> MeetingAudioAsset? {
        MeetingAudioAsset(source: descriptor.source, samples: Array(repeating: 0.1, count: descriptor.sampleCount),
                          sampleRate: descriptor.sampleRate, sessionStartOffset: descriptor.sessionStartOffset)
    }
}

private enum FileWindowTestError: Error { case interrupted }

@MainActor
private final class FileWindowTestTranscriber: MeetingSegmentTranscribing {
    let failAt: TimeInterval?
    var starts: [TimeInterval] = []
    init(failAt: TimeInterval? = nil) { self.failAt = failAt }
    func transcribe(chunk: BufferedMeetingChunk) async -> MeetingTranscriptSegment? { nil }
    func transcribeWholeAsset(_ asset: MeetingAudioAsset) async throws -> [MeetingTranscriptSegment]? {
        starts.append(asset.sessionStartOffset)
        if asset.sessionStartOffset == failAt { throw FileWindowTestError.interrupted }
        return [MeetingTranscriptSegment(speaker: .them, startSeconds: asset.sessionStartOffset,
                                         endSeconds: asset.sessionStartOffset + asset.durationSeconds,
                                         text: "window \(Int(asset.sessionStartOffset))", preventsAdjacentMerge: true)]
    }
}

@MainActor
private final class FileWindowChunkTranscriber: MeetingSegmentTranscribing {
    func transcribe(chunk: BufferedMeetingChunk) async -> MeetingTranscriptSegment? { nil }
}

private actor FileWindowCommitRecorder {
    var indices: [Int] = []
    func record(index: Int, segments: [MeetingTranscriptSegment]) { indices.append(index) }
}

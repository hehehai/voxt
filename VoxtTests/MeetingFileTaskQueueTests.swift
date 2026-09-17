import Foundation
import XCTest
@testable import Voxt

@MainActor
final class MeetingFileTaskQueueTests: XCTestCase {
    func testShutdownFlushesLatestTaskStateToDisk() async throws {
        let storage = try TemporaryDirectory()
        let sourceURL = try makeSourceFile(named: "shutdown.wav")
        let taskFileURL = storage.url
            .appendingPathComponent("tasks", isDirectory: true)
            .appendingPathComponent("tasks.json")
        var cancelRequested = false

        let queue = MeetingFileTaskQueue(
            analyzer: { _, _ in
                while !cancelRequested {
                    try await Task.sleep(for: .milliseconds(10))
                }
                throw CancellationError()
            },
            cancelActiveAnalysis: {
                cancelRequested = true
            },
            canStart: { true },
            storageDirectoryURL: storage.url.appendingPathComponent("tasks", isDirectory: true)
        )

        queue.enqueue(urls: [sourceURL])
        try await waitUntil(queue, status: .processing, at: 0)
        await queue.shutdown()

        struct PersistedPayload: Decodable {
            let tasks: [MeetingFileTask]
        }
        let payload = try JSONDecoder().decode(
            PersistedPayload.self,
            from: Data(contentsOf: taskFileURL)
        )
        let persistedTask = try XCTUnwrap(payload.tasks.first)
        XCTAssertEqual(persistedTask.status, .queued)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: storage.url
                    .appendingPathComponent("tasks", isDirectory: true)
                    .appendingPathComponent(persistedTask.stagedFileName)
                    .path
            )
        )
    }

    func testQueueProcessesFilesInFIFOOrderWithOnlyOneActiveAnalyzer() async throws {
        let storage = try TemporaryDirectory()
        let firstURL = try makeSourceFile(named: "first.wav")
        let secondURL = try makeSourceFile(named: "second.wav")
        var processedNames: [String] = []
        var activeAnalyses = 0
        var maximumActiveAnalyses = 0

        let queue = MeetingFileTaskQueue(
            analyzer: { sourceURL, progress in
                activeAnalyses += 1
                maximumActiveAnalyses = max(maximumActiveAnalyses, activeAnalyses)
                processedNames.append(sourceURL.path.contains("first.wav") ? "first" : "second")
                progress(MeetingFileAnalysisProgress(stage: .transcribing, stageFraction: 0.5))
                try await Task.sleep(for: .milliseconds(30))
                progress(MeetingFileAnalysisProgress(stage: .saving, stageFraction: 1))
                activeAnalyses -= 1
                return Self.makeHistoryEntry()
            },
            cancelActiveAnalysis: {},
            canStart: { true },
            storageDirectoryURL: storage.url.appendingPathComponent("tasks", isDirectory: true)
        )

        queue.enqueue(urls: [firstURL, secondURL])
        try await waitUntilAllTasksAreTerminal(queue)

        XCTAssertEqual(processedNames, ["first", "second"])
        XCTAssertEqual(maximumActiveAnalyses, 1)
        XCTAssertEqual(queue.tasks.map(\.status), [.completed, .completed])
        XCTAssertTrue(queue.tasks.allSatisfy { $0.historyEntryID != nil })
        await queue.shutdown()
    }

    func testCancellingCurrentTaskContinuesWithNextQueuedTask() async throws {
        let storage = try TemporaryDirectory()
        let firstURL = try makeSourceFile(named: "cancel-me.wav")
        let secondURL = try makeSourceFile(named: "continue.wav")
        var cancelRequested = false

        let queue = MeetingFileTaskQueue(
            analyzer: { sourceURL, progress in
                if sourceURL.path.contains("cancel-me.wav") {
                    while !cancelRequested {
                        try await Task.sleep(for: .milliseconds(10))
                    }
                    throw CancellationError()
                }
                progress(MeetingFileAnalysisProgress(stage: .saving, stageFraction: 1))
                return Self.makeHistoryEntry()
            },
            cancelActiveAnalysis: {
                cancelRequested = true
            },
            canStart: { true },
            storageDirectoryURL: storage.url.appendingPathComponent("tasks", isDirectory: true)
        )

        queue.enqueue(urls: [firstURL, secondURL])
        try await waitUntil(queue, status: .processing, at: 0)
        queue.cancel(taskID: try XCTUnwrap(queue.tasks.first?.id))
        try await waitUntilAllTasksAreTerminal(queue)

        XCTAssertEqual(queue.tasks.map(\.status), [.cancelled, .completed])
        await queue.shutdown()
    }

    func testCancellingAfterAnalyzerPersistedResultRollsBackHistoryEntry() async throws {
        let storage = try TemporaryDirectory()
        let sourceURL = try makeSourceFile(named: "persisted-then-cancelled.wav")
        var cancelRequested = false
        var rolledBackEntryIDs: [UUID] = []
        let persistedEntry = Self.makeHistoryEntry()

        let queue = MeetingFileTaskQueue(
            analyzer: { _, _ in
                while !cancelRequested {
                    try await Task.sleep(for: .milliseconds(10))
                }
                return persistedEntry
            },
            cancelActiveAnalysis: {
                cancelRequested = true
            },
            canStart: { true },
            rollbackAnalysis: { entry in
                rolledBackEntryIDs.append(entry.id)
            },
            storageDirectoryURL: storage.url.appendingPathComponent("tasks", isDirectory: true)
        )

        queue.enqueue(urls: [sourceURL])
        try await waitUntil(queue, status: .processing, at: 0)
        queue.cancel(taskID: try XCTUnwrap(queue.tasks.first?.id))
        try await waitUntilAllTasksAreTerminal(queue)

        XCTAssertEqual(queue.tasks.first?.status, .cancelled)
        XCTAssertEqual(rolledBackEntryIDs, [persistedEntry.id])
        XCTAssertNil(queue.tasks.first?.historyEntryID)
        await queue.shutdown()
    }

    func testCancellingQueuedTaskDoesNotAffectTheActiveTask() async throws {
        let storage = try TemporaryDirectory()
        let firstURL = try makeSourceFile(named: "active.wav")
        let secondURL = try makeSourceFile(named: "queued-cancel.wav")
        var releaseActiveTask = false

        let queue = MeetingFileTaskQueue(
            analyzer: { sourceURL, progress in
                if sourceURL.path.contains("active.wav") {
                    while !releaseActiveTask {
                        try await Task.sleep(for: .milliseconds(10))
                    }
                }
                progress(MeetingFileAnalysisProgress(stage: .saving, stageFraction: 1))
                return Self.makeHistoryEntry()
            },
            cancelActiveAnalysis: {},
            canStart: { true },
            storageDirectoryURL: storage.url.appendingPathComponent("tasks", isDirectory: true)
        )

        queue.enqueue(urls: [firstURL, secondURL])
        try await waitUntil(queue, status: .processing, at: 0)
        let queuedTaskID = try XCTUnwrap(queue.tasks.first(where: { $0.status == .queued })?.id)

        queue.cancel(taskID: queuedTaskID)

        XCTAssertEqual(queue.task(id: queuedTaskID)?.status, .cancelled)
        releaseActiveTask = true
        try await waitUntilAllTasksAreTerminal(queue)
        XCTAssertEqual(queue.tasks.map(\.status), [.completed, .cancelled])
        await queue.shutdown()
    }

    func testPrioritizingQueuedTaskMovesItAheadOfOtherQueuedTasks() async throws {
        let storage = try TemporaryDirectory()
        let firstURL = try makeSourceFile(named: "first-priority.wav")
        let secondURL = try makeSourceFile(named: "second-priority.wav")
        let priorityURL = try makeSourceFile(named: "priority.wav")
        var processedNames: [String] = []
        var releaseFirstTask = false

        let queue = MeetingFileTaskQueue(
            analyzer: { sourceURL, progress in
                if sourceURL.path.contains("first-priority.wav") {
                    while !releaseFirstTask {
                        try await Task.sleep(for: .milliseconds(10))
                    }
                }
                if sourceURL.path.contains("first-priority.wav") {
                    processedNames.append("first-priority.wav")
                } else if sourceURL.path.contains("second-priority.wav") {
                    processedNames.append("second-priority.wav")
                } else {
                    processedNames.append("priority.wav")
                }
                progress(MeetingFileAnalysisProgress(stage: .saving, stageFraction: 1))
                return Self.makeHistoryEntry()
            },
            cancelActiveAnalysis: {},
            canStart: { true },
            storageDirectoryURL: storage.url.appendingPathComponent("tasks", isDirectory: true)
        )

        queue.enqueue(urls: [firstURL, secondURL, priorityURL])
        try await waitUntil(queue, status: .processing, at: 0)
        let priorityTaskID = try XCTUnwrap(
            queue.tasks.first(where: { $0.fileName == priorityURL.lastPathComponent })?.id
        )

        queue.prioritize(taskID: priorityTaskID)

        XCTAssertEqual(
            queue.tasks.map(\.fileName),
            [firstURL.lastPathComponent, priorityURL.lastPathComponent, secondURL.lastPathComponent]
        )
        releaseFirstTask = true
        try await waitUntilAllTasksAreTerminal(queue)
        XCTAssertEqual(
            processedNames,
            ["first-priority.wav", "priority.wav", "second-priority.wav"]
        )
        await queue.shutdown()
    }

    func testImportNormalizesBeforeAnalyzerAndDoesNotStageOriginalBytes() async throws {
        let storage = try TemporaryDirectory()
        let source = storage.url.appendingPathComponent("source.wav")
        try MeetingAudioChunkWAVExporter.write(samples: Array(repeating: 0.1, count: 8000), sampleRate: 8000, to: source)
        let original = try Data(contentsOf: source)
        var analyzed = false
        let queue = MeetingFileTaskQueue(
            analyzer: { url, _ in
                let audio = try MeetingImportedAudioFile.openPrepared(at: url)
                // AVFoundation resampling can trim a few milliseconds of filter
                // priming/tail samples; validate duration, not exact frame equality.
                XCTAssertEqual(audio.durationSeconds, 1, accuracy: 0.01)
                analyzed = true
                return Self.makeHistoryEntry()
            }, cancelActiveAnalysis: {}, canStart: { true },
            storageDirectoryURL: storage.url.appendingPathComponent("tasks")
        )
        queue.enqueue(urls: [source])
        try await waitUntilAllTasksAreTerminal(queue)
        XCTAssertTrue(analyzed)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(queue.tasks.first?.status, .completed)
        await queue.shutdown()
    }

    func testCompletedTaskReclaimsPreparedAudioButNeverOriginalFile() async throws {
        let storage = try TemporaryDirectory()
        let source = try makeSourceFile(named: "cleanup.wav")
        let queue = MeetingFileTaskQueue(
            analyzer: { url, _ in
                XCTAssertNoThrow(try MeetingImportedAudioFile.openPrepared(at: url))
                XCTAssertNotEqual(url, source)
                return Self.makeHistoryEntry()
            }, cancelActiveAnalysis: {}, canStart: { true }, storageDirectoryURL: storage.url
        )
        queue.enqueue(urls: [source])
        try await waitUntilAllTasksAreTerminal(queue)
        let task = try XCTUnwrap(queue.tasks.first)
        XCTAssertEqual(task.status, .completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.url.appendingPathComponent(task.stagedFileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        await queue.shutdown()
    }

    func testDeliveredTranscriptIsNotRolledBackOnCancellation() async throws {
        let storage = try TemporaryDirectory()
        let source = try makeSourceFile(named: "delivered.wav")
        let entry = Self.makeHistoryEntry()
        var cancelled = false
        var rollbacks = 0
        let queue = MeetingFileTaskQueue(
            analyzer: { _, progress in
                progress(MeetingFileAnalysisProgress(stage: .identifyingSpeakers, historyEntryID: entry.id))
                while !cancelled { try await Task.sleep(for: .milliseconds(10)) }
                return entry
            }, cancelActiveAnalysis: { cancelled = true }, canStart: { true },
            rollbackAnalysis: { _ in rollbacks += 1 }, storageDirectoryURL: storage.url
        )
        queue.enqueue(urls: [source])
        try await waitUntil(queue, status: .processing, at: 0)
        queue.cancel(taskID: try XCTUnwrap(queue.tasks.first?.id))
        try await waitUntilAllTasksAreTerminal(queue)
        XCTAssertEqual(queue.tasks.first?.historyEntryID, entry.id)
        XCTAssertEqual(rollbacks, 0)
        await queue.shutdown()
    }

    func testResourcePauseDoesNotBlockNextFileAndCanResume() async throws {
        let storage = try TemporaryDirectory()
        let first = try makeSourceFile(named: "resource-pause.wav")
        let second = try makeSourceFile(named: "next.wav")
        var shouldPause = true
        let queue = MeetingFileTaskQueue(
            analyzer: { url, _ in
                if url.path.contains("resource-pause"), shouldPause {
                    throw MeetingFileWorkError.resourcesUnavailable
                }
                return Self.makeHistoryEntry()
            }, cancelActiveAnalysis: {}, canStart: { true }, storageDirectoryURL: storage.url
        )
        queue.enqueue(urls: [first, second])
        try await waitUntil(queue, status: .paused, at: 0)
        try await waitUntil(queue, status: .completed, at: 1)
        shouldPause = false
        queue.retry(taskID: try XCTUnwrap(queue.tasks.first?.id))
        try await waitUntilAllTasksAreTerminal(queue)
        XCTAssertEqual(queue.tasks.map(\.status), [.completed, .completed])
        await queue.shutdown()
    }

    func testUserPauseRetainsPreparedInputAndHistoryAcrossRestart() async throws {
        let storage = try TemporaryDirectory()
        let source = try makeSourceFile(named: "pause.wav")
        let entry = Self.makeHistoryEntry()
        var stop = false
        let queue = MeetingFileTaskQueue(
            analyzer: { _, progress in
                progress(MeetingFileAnalysisProgress(stage: .identifyingSpeakers, historyEntryID: entry.id))
                while !stop { try await Task.sleep(for: .milliseconds(10)) }
                throw CancellationError()
            }, cancelActiveAnalysis: { stop = true }, canStart: { true }, storageDirectoryURL: storage.url
        )
        queue.enqueue(urls: [source])
        try await waitUntil(queue, status: .processing, at: 0)
        queue.pause(taskID: try XCTUnwrap(queue.tasks.first?.id))
        try await waitUntil(queue, status: .paused, at: 0)
        await queue.shutdown()
        let restored = MeetingFileTaskQueue(
            analyzer: { _, _ in entry }, cancelActiveAnalysis: {}, canStart: { false }, storageDirectoryURL: storage.url
        )
        let task = try XCTUnwrap(restored.tasks.first)
        XCTAssertEqual(task.status, .paused)
        XCTAssertEqual(task.historyEntryID, entry.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url.appendingPathComponent(task.stagedFileName).path))
        restored.cancel(taskID: task.id)
        restored.clearFinishedTasks()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.url.appendingPathComponent(task.stagedFileName).path))
        await restored.shutdown()
    }

    func testDeferredSpeakerTaskKeepsOnlyOwnedResumeDataUntilCleanup() async throws {
        let storage = try TemporaryDirectory()
        let source = try makeSourceFile(named: "later.wav")
        let queue = MeetingFileTaskQueue(
            analyzer: { _, progress in
                progress(MeetingFileAnalysisProgress(stage: .saving, notice: "pending speakers"))
                return Self.makeHistoryEntry()
            }, cancelActiveAnalysis: {}, canStart: { true }, storageDirectoryURL: storage.url
        )
        queue.enqueue(urls: [source])
        try await waitUntilAllTasksAreTerminal(queue)
        let task = try XCTUnwrap(queue.tasks.first)
        XCTAssertTrue(task.hasPendingSpeakerAnalysis)
        let preparedURL = storage.url.appendingPathComponent(task.stagedFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: preparedURL.path))
        queue.clearFinishedTasks()
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        await queue.shutdown()
    }

    func testFailedCompletionCommitRetainsRecoveryAudio() async throws {
        let storage = try TemporaryDirectory()
        let source = try makeSourceFile(named: "persist-failure.wav")
        let manifestURL = storage.url.appendingPathComponent("tasks.json")
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: true)
        let queue = MeetingFileTaskQueue(
            analyzer: { _, _ in Self.makeHistoryEntry() },
            cancelActiveAnalysis: {}, canStart: { true }, storageDirectoryURL: storage.url
        )
        queue.enqueue(urls: [source])
        try await waitUntilAllTasksAreTerminal(queue)
        let task = try XCTUnwrap(queue.tasks.first)
        XCTAssertEqual(task.status, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url.appendingPathComponent(task.stagedFileName).path))
        await queue.shutdown()
    }

    func testPendingImportCountIsBoundedBeforeStartingDecodeTasks() async throws {
        let storage = try TemporaryDirectory()
        let source = try makeSourceFile(named: "bounded.wav")
        let queue = MeetingFileTaskQueue(
            analyzer: { _, _ in XCTFail("Must not analyze while blocked"); return Self.makeHistoryEntry() },
            cancelActiveAnalysis: {}, canStart: { false }, storageDirectoryURL: storage.url
        )
        let accepted = queue.enqueue(urls: Array(repeating: source, count: MeetingFileTaskQueue.maximumPendingFiles + 10))
        XCTAssertEqual(accepted, MeetingFileTaskQueue.maximumPendingFiles)
        XCTAssertEqual(queue.tasks.count, MeetingFileTaskQueue.maximumPendingFiles)
        await queue.shutdown()
    }

    func testRepeatedCancellationCannotMakeAnActiveTaskClearable() async throws {
        let storage = try TemporaryDirectory()
        let source = try makeSourceFile(named: "cancel-twice.wav")
        var release = false
        let queue = MeetingFileTaskQueue(
            analyzer: { _, _ in
                while !release { try await Task.sleep(for: .milliseconds(10)) }
                throw CancellationError()
            }, cancelActiveAnalysis: {}, canStart: { true }, storageDirectoryURL: storage.url
        )
        queue.enqueue(urls: [source])
        try await waitUntil(queue, status: .processing, at: 0)
        let task = try XCTUnwrap(queue.tasks.first)
        queue.cancel(taskID: task.id)
        queue.cancel(taskID: task.id)
        queue.clearFinishedTasks()
        XCTAssertEqual(queue.tasks.first?.status, .cancelling)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url.appendingPathComponent(task.stagedFileName).path))
        release = true
        try await waitUntilAllTasksAreTerminal(queue)
        await queue.shutdown()
    }

    func testRestartPreservesInFlightPauseAndCancelIntent() async throws {
        let storage = try TemporaryDirectory()
        let pauseID = UUID()
        let cancelID = UUID()
        var pausing = MeetingFileTask.queued(id: pauseID, fileName: "pause.wav", stagedFileName: pauseID.uuidString + "-pause.wav")
        pausing.status = .pausing
        pausing.historyEntryID = UUID()
        var cancelling = MeetingFileTask.queued(id: cancelID, fileName: "cancel.wav", stagedFileName: cancelID.uuidString + "-cancel.wav")
        cancelling.status = .cancelling
        struct Payload: Encodable { let version: Int; let tasks: [MeetingFileTask] }
        try JSONEncoder().encode(Payload(version: 1, tasks: [pausing, cancelling]))
            .write(to: storage.url.appendingPathComponent("tasks.json"))
        let queue = MeetingFileTaskQueue(
            analyzer: { _, _ in XCTFail("Paused work must not restart automatically"); return Self.makeHistoryEntry() },
            cancelActiveAnalysis: {}, canStart: { false }, storageDirectoryURL: storage.url
        )
        XCTAssertEqual(queue.tasks.map(\.status), [.paused, .cancelled])
        XCTAssertEqual(queue.tasks.first?.historyEntryID, pausing.historyEntryID)
        await queue.shutdown()
    }

    func testTaskEstimateAndRetryReset() {
        let enqueuedAt = Date(timeIntervalSince1970: 100)
        var task = MeetingFileTask.queued(
            fileName: "meeting.wav",
            stagedFileName: "staged.wav",
            enqueuedAt: enqueuedAt
        )
        task.status = .processing
        task.startedAt = Date(timeIntervalSince1970: 110)
        task.progressFraction = 0.25

        XCTAssertEqual(task.elapsedSeconds(now: Date(timeIntervalSince1970: 130)), 20)
        let estimatedRemaining = try? XCTUnwrap(
            task.estimatedRemainingSeconds(now: Date(timeIntervalSince1970: 130))
        )
        XCTAssertEqual(estimatedRemaining ?? -1, 60, accuracy: 0.001)

        task.status = .failed
        task.errorMessage = "failure"
        task.historyEntryID = UUID()
        let retry = task.resetForRetry()
        XCTAssertEqual(retry.status, .queued)
        XCTAssertNil(retry.startedAt)
        XCTAssertNil(retry.completedAt)
        XCTAssertNil(retry.errorMessage)
        XCTAssertNil(retry.historyEntryID)
        XCTAssertEqual(retry.progressFraction, 0)
        XCTAssertNil(retry.estimatedTotalSeconds)
    }

    func testTaskEstimateUsesConservativeAnchorAndNeverIncreases() {
        let initial = MeetingFileTask.updatedEstimatedTotalSeconds(
            current: nil,
            elapsed: 10,
            progressFraction: 0.1
        )
        XCTAssertEqual(initial ?? -1, 135, accuracy: 0.001)

        let fasterPhase = MeetingFileTask.updatedEstimatedTotalSeconds(
            current: initial,
            elapsed: 40,
            progressFraction: 0.5
        )
        XCTAssertEqual(fasterPhase ?? -1, 108, accuracy: 0.001)

        let slowerPhase = MeetingFileTask.updatedEstimatedTotalSeconds(
            current: fasterPhase,
            elapsed: 50,
            progressFraction: 0.3
        )
        XCTAssertEqual(slowerPhase ?? -1, fasterPhase ?? -2, accuracy: 0.001)

        let remainingAtAnchor = MeetingFileTask.queued(
            fileName: "meeting.wav",
            stagedFileName: "staged.wav"
        )
        var processingTask = remainingAtAnchor
        processingTask.status = .processing
        processingTask.startedAt = Date(timeIntervalSince1970: 100)
        processingTask.estimatedTotalSeconds = slowerPhase
        XCTAssertEqual(
            processingTask.estimatedRemainingSeconds(now: Date(timeIntervalSince1970: 150)) ?? -1,
            58,
            accuracy: 0.001
        )
    }

    func testTaskEstimateRemainsPositiveWhilePostTranscriptionStagesAreRunning() {
        let estimate = MeetingFileTask.updatedEstimatedTotalSeconds(
            current: nil,
            elapsed: 40,
            progressFraction: 0.78,
            mediaDurationSeconds: 2_520,
            processedMediaDurationSeconds: 2_520,
            stage: .transcribing
        )

        var task = MeetingFileTask.queued(
            fileName: "meeting.wav",
            stagedFileName: "staged.wav"
        )
        task.status = .processing
        task.startedAt = Date(timeIntervalSince1970: 100)
        task.progressFraction = 0.90
        task.estimatedTotalSeconds = estimate

        XCTAssertGreaterThan(task.estimatedRemainingSeconds(now: Date(timeIntervalSince1970: 150)) ?? 0, 0)

        let identifyingEstimate = MeetingFileTask.updatedEstimatedTotalSeconds(
            current: estimate,
            elapsed: 70,
            progressFraction: 0.90,
            mediaDurationSeconds: 2_520,
            processedMediaDurationSeconds: 2_520,
            stage: .identifyingSpeakers
        )
        task.estimatedTotalSeconds = identifyingEstimate
        XCTAssertGreaterThan(task.estimatedRemainingSeconds(now: Date(timeIntervalSince1970: 170)) ?? 0, 0)

        let recoveredEstimate = MeetingFileTask.updatedEstimatedTotalSeconds(
            current: 0,
            elapsed: 10,
            progressFraction: 0.20
        )
        XCTAssertGreaterThan(recoveredEstimate ?? 0, 0)
    }

    func testTaskPersistenceRoundTripsProgressAndHistoryID() throws {
        var task = MeetingFileTask.queued(
            fileName: "meeting.wav",
            stagedFileName: "staged.wav",
            enqueuedAt: Date(timeIntervalSince1970: 100)
        )
        task.status = .completed
        task.startedAt = Date(timeIntervalSince1970: 110)
        task.completedAt = Date(timeIntervalSince1970: 140)
        task.progressStage = .saving
        task.progressFraction = 1
        task.historyEntryID = UUID()

        try XCTAssertJSONRoundTrip(task)
    }

    private func makeSourceFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Voxt-Meeting-Task-\(UUID().uuidString)-\(name)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try MeetingAudioChunkWAVExporter.write(
            samples: Array(repeating: Float.zero, count: 160),
            sampleRate: 16_000,
            to: url
        )
        return url
    }

    private func waitUntilAllTasksAreTerminal(_ queue: MeetingFileTaskQueue) async throws {
        for _ in 0..<200 {
            if !queue.tasks.contains(where: { !$0.isTerminal }) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for the meeting file queue")
    }

    private func waitUntil(
        _ queue: MeetingFileTaskQueue,
        status: MeetingFileTaskStatus,
        at index: Int
    ) async throws {
        for _ in 0..<200 {
            if queue.tasks.indices.contains(index), queue.tasks[index].status == status {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for task status (status)")
    }

    private static func makeHistoryEntry() -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: UUID(),
            text: "Test transcript",
            createdAt: Date(),
            transcriptionEngine: "test",
            transcriptionModel: "test",
            enhancementMode: "off",
            enhancementModel: "",
            kind: .transcript,
            isTranslation: false,
            audioDurationSeconds: nil,
            transcriptionProcessingDurationSeconds: nil,
            llmDurationSeconds: nil,
            focusedAppName: nil,
            focusedAppBundleID: nil,
            matchedGroupID: nil,
            matchedGroupName: nil,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil,
            remoteASRProvider: nil,
            remoteASRModel: nil,
            remoteASREndpoint: nil,
            remoteLLMProvider: nil,
            remoteLLMModel: nil,
            remoteLLMEndpoint: nil,
            whisperWordTimings: nil,
            dictionaryHitTerms: [],
            dictionaryCorrectedTerms: [],
            dictionarySuggestedTerms: []
        )
    }
}

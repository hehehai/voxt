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

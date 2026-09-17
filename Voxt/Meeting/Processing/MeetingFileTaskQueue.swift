// MeetingFileTaskQueue.swift
// Provides persistent, serial processing for imported meeting files.

import Combine
import Foundation

enum MeetingFileTaskStatus: String, Codable, Hashable, Sendable {
    case queued
    case processing
    case cancelling
    case pausing
    case paused
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .queued, .processing, .cancelling, .pausing, .paused:
            return false
        }
    }
}

struct MeetingFileTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let stagedFileName: String
    let enqueuedAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var status: MeetingFileTaskStatus
    var progressStage: MeetingFileAnalysisStage
    var progressFraction: Double
    var mediaDurationSeconds: TimeInterval?
    var processedMediaDurationSeconds: TimeInterval?
    /// Smoothed audio-seconds-per-wall-second measured during transcription.
    var processingSpeedSecondsPerSecond: Double?
    var speedSampleAt: Date?
    var speedSampleProcessedMediaDurationSeconds: TimeInterval?
    /// Conservative total-duration estimate captured while the task is running.
    /// It is intentionally monotonic: later progress observations may lower it,
    /// but never make it larger and cause the UI to oscillate.
    var estimatedTotalSeconds: TimeInterval?
    var errorMessage: String?
    var historyEntryID: UUID?
    var notice: String?

    var isTerminal: Bool { status.isTerminal }
    var hasPendingSpeakerAnalysis: Bool { status == .completed && !(notice ?? "").isEmpty }

    func elapsedSeconds(now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let end = completedAt ?? now
        return max(0, end.timeIntervalSince(startedAt))
    }

    func estimatedRemainingSeconds(now: Date) -> TimeInterval? {
        guard status == .processing else { return nil }
        let elapsed = elapsedSeconds(now: now)
        guard elapsed > 0 else { return nil }
        if let estimatedTotalSeconds, estimatedTotalSeconds > elapsed {
            return max(0, estimatedTotalSeconds - elapsed)
        }

        // If an old estimate was too optimistic and has already elapsed,
        // fall back to the current overall progress instead of displaying
        // zero while the task is still processing.
        guard progressFraction > 0 else { return nil }
        return max(0, elapsed * (1 - progressFraction) / progressFraction)
    }

    static func updatedEstimatedTotalSeconds(
        current: TimeInterval?,
        elapsed: TimeInterval,
        progressFraction: Double,
        mediaDurationSeconds: TimeInterval? = nil,
        processedMediaDurationSeconds: TimeInterval? = nil,
        stage: MeetingFileAnalysisStage? = nil,
        processingSpeed: Double? = nil
    ) -> TimeInterval? {
        guard elapsed > 0, progressFraction > 0 else { return current }

        // The first estimate is deliberately conservative. Once established,
        // only a faster observed rate can lower it; a slower phase never makes
        // the remaining-time label jump backwards.
        let observedTotal: TimeInterval
        if stage == nil || stage == .transcribing || stage == .identifyingSpeakers || stage == .saving,
           let mediaDurationSeconds,
           let processedMediaDurationSeconds,
           mediaDurationSeconds > 0,
           processedMediaDurationSeconds > 0 {
            let sampleSpeed = max(
                processingSpeed ?? processedMediaDurationSeconds / elapsed,
                0.001
            )
            let transcriptionTotal = mediaDurationSeconds / sampleSpeed
            // Transcription accounts for 63% of the overall task progress.
            // Include the later speaker-analysis and save stages so finishing
            // the audio pass does not make the task appear to have no time left.
            let transcriptionWeight = 0.63
            observedTotal = max(
                transcriptionTotal / transcriptionWeight,
                elapsed / progressFraction
            )
        } else {
            observedTotal = elapsed / progressFraction
        }
        let conservativeTotal = max(
            observedTotal * 1.35,
            elapsed + 30
        )
        // Treat a legacy or corrupted zero anchor as missing so it can be
        // recovered instead of permanently winning the minimum comparison.
        guard let current, current > 0 else { return conservativeTotal }
        return min(current, conservativeTotal)
    }

    static func queued(
        id: UUID = UUID(),
        fileName: String,
        stagedFileName: String,
        enqueuedAt: Date = Date()
    ) -> MeetingFileTask {
        MeetingFileTask(
            id: id,
            fileName: fileName,
            stagedFileName: stagedFileName,
            enqueuedAt: enqueuedAt,
            startedAt: nil,
            completedAt: nil,
            status: .queued,
            progressStage: .preparing,
            progressFraction: 0,
            mediaDurationSeconds: nil,
            processedMediaDurationSeconds: nil,
            processingSpeedSecondsPerSecond: nil,
            speedSampleAt: nil,
            speedSampleProcessedMediaDurationSeconds: nil,
            estimatedTotalSeconds: nil,
            errorMessage: nil,
            historyEntryID: nil
        )
    }

    func resetForRetry() -> MeetingFileTask {
        var retry = self
        retry.startedAt = nil
        retry.completedAt = nil
        retry.status = .queued
        retry.progressStage = .preparing
        retry.progressFraction = 0
        retry.processedMediaDurationSeconds = nil
        retry.processingSpeedSecondsPerSecond = nil
        retry.speedSampleAt = nil
        retry.speedSampleProcessedMediaDurationSeconds = nil
        retry.estimatedTotalSeconds = nil
        retry.errorMessage = nil
        retry.historyEntryID = nil
        return retry
    }
}

@MainActor
final class MeetingFileTaskQueue: ObservableObject {
    typealias Analyzer = @MainActor @Sendable (
        _ sourceURL: URL,
        _ progress: @escaping @MainActor @Sendable (MeetingFileAnalysisProgress) -> Void
    ) async throws -> TranscriptionHistoryEntry
    typealias ActiveAnalysisCanceller = @MainActor @Sendable () async -> Void
    typealias CanStartProvider = @MainActor @Sendable () -> Bool
    typealias AnalysisRollback = @MainActor @Sendable (TranscriptionHistoryEntry) -> Void

    @Published private(set) var tasks: [MeetingFileTask]

    private struct PersistedPayload: Codable, Sendable {
        let version: Int
        let tasks: [MeetingFileTask]
    }

    private let analyzer: Analyzer
    private let cancelActiveAnalysis: ActiveAnalysisCanceller
    private let canStart: CanStartProvider
    private let rollbackAnalysis: AnalysisRollback
    private let fileManager: FileManager
    private let now: () -> Date
    private let storageDirectoryURL: URL
    private let taskFileURL: URL
    private let persistenceCoordinator: AsyncJSONPersistenceCoordinator
    private static let maximumStagedSourceBytes = MeetingFileResourcePolicy.maximumPreparedQueueBytes
    static let maximumPendingFiles = 64
    private var workerTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var activeTaskID: UUID?
    private var stagingTaskIDs: Set<UUID> = []
    private var stagingTasks: [UUID: Task<Void, Never>] = [:]
    private var stagingReservations: [UUID: Int64] = [:]
    private var reservedStagingBytes: Int64 = 0
    private var isShuttingDown = false
    private var stagingTail: Task<Void, Never>?
    private var loadedTaskManifest = false

    init(
        analyzer: @escaping Analyzer,
        cancelActiveAnalysis: @escaping ActiveAnalysisCanceller,
        canStart: @escaping CanStartProvider,
        rollbackAnalysis: @escaping AnalysisRollback = { _ in },
        fileManager: FileManager = .default,
        storageDirectoryURL: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.analyzer = analyzer
        self.cancelActiveAnalysis = cancelActiveAnalysis
        self.canStart = canStart
        self.rollbackAnalysis = rollbackAnalysis
        self.fileManager = fileManager
        self.now = now

        let resolvedStorageDirectoryURL = storageDirectoryURL ?? Self.defaultStorageDirectoryURL(fileManager: fileManager)
        self.storageDirectoryURL = resolvedStorageDirectoryURL
        self.taskFileURL = resolvedStorageDirectoryURL.appendingPathComponent("tasks.json")
        self.persistenceCoordinator = AsyncJSONPersistenceCoordinator(
            label: "com.voxt.meeting-file-task-queue.persistence"
        )
        self.tasks = []

        loadPersistedTasks()
        removeAbandonedTaskFiles()
    }

    var hasActiveTasks: Bool {
        tasks.contains { !$0.isTerminal && $0.status != .paused }
    }

    var hasFinishedTasks: Bool {
        tasks.contains(where: \.isTerminal)
    }

    func task(id: UUID) -> MeetingFileTask? {
        tasks.first { $0.id == id }
    }

    @discardableResult
    func enqueue(urls: [URL]) -> Int {
        guard !isShuttingDown else { return 0 }
        var accepted = 0
        let pendingIDs = Set(tasks.filter { !$0.isTerminal }.map(\.id)).union(stagingTaskIDs)
        let availableSlots = max(0, Self.maximumPendingFiles - pendingIDs.count)
        for sourceURL in urls {
            guard accepted < availableSlots else { break }
            guard MeetingFileImportSupport.isSupportedImportFile(at: sourceURL) else { continue }

            let taskID = UUID()
            let fileName = sourceURL.lastPathComponent
            // Leave room for UUID and sidecar suffixes even with long UTF-8 names.
            let stagedName = String(decoding: fileName.utf8.prefix(160), as: UTF8.self)
            let stagedFileName = taskID.uuidString + "-" + stagedName + ".wav"
            tasks.append(
                .queued(
                    id: taskID,
                    fileName: fileName,
                    stagedFileName: stagedFileName,
                    enqueuedAt: now()
                )
            )
            stagingTaskIDs.insert(taskID)
            stage(sourceURL: sourceURL, taskID: taskID, stagedFileName: stagedFileName)
            accepted += 1
        }

        persist()
        startIfNeeded()
        return accepted
    }

    func cancel(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard !tasks[index].isTerminal else { return }

        if activeTaskID == taskID {
            guard tasks[index].status != .cancelling else { return }
            tasks[index].status = .cancelling
            persist()
            Task { @MainActor [weak self] in
                await self?.cancelActiveAnalysis()
            }
            return
        }

        if stagingTaskIDs.contains(taskID) {
            stagingTasks[taskID]?.cancel()
        }
        tasks[index].status = .cancelled
        tasks[index].completedAt = now()
        persist()
        startIfNeeded()
    }

    func pause(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[index].status == .processing else { return }
        tasks[index].status = .pausing
        persist()
        Task { @MainActor [weak self] in
            await self?.cancelActiveAnalysis()
        }
    }

    /// Moves a queued task ahead of the other queued tasks while keeping any
    /// currently processing task in place.
    func prioritize(taskID: UUID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[taskIndex].status == .queued,
              let firstQueuedIndex = tasks.firstIndex(where: { $0.status == .queued }),
              taskIndex != firstQueuedIndex
        else { return }

        let task = tasks.remove(at: taskIndex)
        let insertionIndex = tasks.firstIndex(where: { $0.status == .queued }) ?? tasks.endIndex
        tasks.insert(task, at: insertionIndex)
        persist()
        startIfNeeded()
    }

    func retry(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard tasks[index].status == .failed || tasks[index].status == .cancelled || tasks[index].status == .paused || tasks[index].hasPendingSpeakerAnalysis else { return }
        guard fileManager.fileExists(atPath: stagedURL(for: tasks[index]).path) else {
            tasks[index].status = .failed
            tasks[index].errorMessage = AppLocalization.localizedString("The staged source file is no longer available.")
            persist()
            return
        }

        let historyID = tasks[index].historyEntryID
        tasks[index] = tasks[index].resetForRetry()
        tasks[index].historyEntryID = historyID
        persist()
        startIfNeeded()
    }

    func clearFinishedTasks() {
        let finishedTasks = tasks.filter(\.isTerminal)
        tasks.removeAll(where: \.isTerminal)
        for task in finishedTasks {
            removeTaskFiles(task)
            if !fileManager.fileExists(atPath: stagedURL(for: task).path) {
                releaseStagingReservation(for: task.id)
            }
        }
        persist()
    }

    func startIfNeeded() {
        guard !isShuttingDown, workerTask == nil, hasActiveTasks else { return }
        workerTask = Task { @MainActor [weak self] in
            await self?.runWorker()
        }
        if tickerTask == nil {
            tickerTask = Task { @MainActor [weak self] in
                await self?.runTicker()
            }
        }
    }

    func shutdown() async {
        isShuttingDown = true
        tickerTask?.cancel()
        tickerTask = nil
        if activeTaskID != nil {
            await cancelActiveAnalysis()
        }
        let stagingTaskIDsToCancel = Array(stagingTasks.keys)
        for taskID in stagingTaskIDsToCancel {
            if let index = tasks.firstIndex(where: { $0.id == taskID }), !tasks[index].isTerminal {
                tasks[index].status = .failed
                tasks[index].completedAt = now()
                tasks[index].errorMessage = AppLocalization.localizedString(
                    "The meeting file could not be staged before the app closed."
                )
            }
            stagingTasks[taskID]?.cancel()
        }
        persist()
        if let workerTask {
            await workerTask.value
        }
        workerTask = nil
        let tasksToFinish = Array(stagingTasks.values)
        for stagingTask in tasksToFinish {
            await stagingTask.value
        }
        stagingTasks.removeAll()
        persistenceCoordinator.flushWrite(
            PersistedPayload(version: 1, tasks: tasks),
            to: taskFileURL
        )
    }

    private func runWorker() async {
        defer { workerTask = nil }

        while !Task.isCancelled, !isShuttingDown {
            guard let index = nextRunnableTaskIndex() else {
                guard hasActiveTasks else { return }
                try? await Task.sleep(for: .milliseconds(200))
                continue
            }
            let taskID = tasks[index].id

            while !canStart(), !Task.isCancelled, !isShuttingDown {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, !isShuttingDown else { return }

            guard let currentIndex = tasks.firstIndex(where: { $0.id == taskID }),
                  tasks[currentIndex].status == .queued
            else { continue }

            let startDate = now()
            tasks[currentIndex].status = .processing
            tasks[currentIndex].startedAt = startDate
            tasks[currentIndex].completedAt = nil
            tasks[currentIndex].progressStage = .preparing
            tasks[currentIndex].progressFraction = 0
            tasks[currentIndex].processedMediaDurationSeconds = nil
            tasks[currentIndex].processingSpeedSecondsPerSecond = nil
            tasks[currentIndex].speedSampleAt = nil
            tasks[currentIndex].speedSampleProcessedMediaDurationSeconds = nil
            tasks[currentIndex].estimatedTotalSeconds = nil
            tasks[currentIndex].errorMessage = nil
            activeTaskID = taskID
            persist()

            do {
                let task = tasks[currentIndex]
                let entry = try await analyzer(stagedURL(for: task)) { [weak self] progress in
                    guard let self else { return }
                    self.apply(progress: progress, to: taskID)
                }
                guard let finishedIndex = tasks.firstIndex(where: { $0.id == taskID }) else { continue }
                // Once text was delivered, cancellation must not erase it. Legacy
                // analyzers without early delivery retain the rollback contract.
                let shouldRollback = tasks[finishedIndex].historyEntryID == nil &&
                    (isShuttingDown || tasks[finishedIndex].status == .cancelling)
                if shouldRollback {
                    rollbackAnalysis(entry)
                }
                if isShuttingDown {
                    markInterrupted(taskID: taskID)
                } else if tasks[finishedIndex].status == .pausing {
                    tasks[finishedIndex].historyEntryID = entry.id
                    markPaused(taskID: taskID)
                } else if tasks[finishedIndex].status == .cancelling {
                    tasks[finishedIndex].status = .cancelled
                    tasks[finishedIndex].completedAt = now()
                } else {
                    tasks[finishedIndex].status = .completed
                    tasks[finishedIndex].completedAt = now()
                    tasks[finishedIndex].progressStage = .saving
                    tasks[finishedIndex].progressFraction = 1
                    tasks[finishedIndex].historyEntryID = entry.id
                    // Never delete recovery inputs before both history and queue
                    // completion are durable. Failed state writes keep the inputs.
                    let didPersist = persistenceCoordinator.flushWrite(PersistedPayload(version: 1, tasks: tasks), to: taskFileURL)
                    if didPersist, !tasks[finishedIndex].hasPendingSpeakerAnalysis {
                        removeTaskFiles(tasks[finishedIndex])
                        if !fileManager.fileExists(atPath: stagedURL(for: tasks[finishedIndex]).path) {
                            releaseStagingReservation(for: taskID)
                        }
                    }
                    SystemNotificationSupport.post(
                        title: AppLocalization.localizedString("File conversion completed"),
                        body: AppLocalization.format("%@ has been converted successfully.", tasks[finishedIndex].fileName),
                        userInfo: [
                            "fileTaskID": taskID.uuidString,
                            "historyEntryID": entry.id.uuidString
                        ]
                    )
                }
            } catch is CancellationError {
                if isShuttingDown {
                    markInterrupted(taskID: taskID)
                } else if task(id: taskID)?.status == .pausing {
                    markPaused(taskID: taskID)
                } else {
                    markCancelled(taskID: taskID)
                }
            } catch MeetingFileWorkError.resourcesUnavailable {
                markResourceInterruption(taskID: taskID, message: MeetingFileWorkError.resourcesUnavailable.localizedDescription)
            } catch let error as MeetingLocalInferenceCoordinatorError {
                VoxtLog.meetingWarning("File inference deferred: \(error.localizedDescription)")
                markResourceInterruption(taskID: taskID, message: MeetingFileWorkError.resourcesUnavailable.localizedDescription)
            } catch {
                if isShuttingDown {
                    markInterrupted(taskID: taskID)
                } else if task(id: taskID)?.status == .cancelling {
                    markCancelled(taskID: taskID)
                } else if task(id: taskID)?.status == .pausing {
                    markPaused(taskID: taskID)
                } else {
                    markFailed(taskID: taskID, error: error)
                }
            }

            activeTaskID = nil
            persist()
        }
    }

    private func runTicker() async {
        defer { tickerTask = nil }
        while !Task.isCancelled, !isShuttingDown {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            guard hasActiveTasks else { return }
            objectWillChange.send()
        }
    }

    private func nextRunnableTaskIndex() -> Int? {
        guard let index = tasks.firstIndex(where: { !$0.isTerminal && $0.status != .paused }) else { return nil }
        let task = tasks[index]
        guard task.status == .queued, !stagingTaskIDs.contains(task.id) else { return nil }
        guard fileManager.fileExists(atPath: stagedURL(for: task).path) else {
            markFailed(
                taskID: task.id,
                error: NSError(
                    domain: "Voxt.MeetingFileTaskQueue",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("The staged source file is no longer available.")]
                )
            )
            return nextRunnableTaskIndex()
        }
        return index
    }

    private func apply(progress: MeetingFileAnalysisProgress, to taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }),
              !tasks[index].isTerminal else { return }
        if let historyID = progress.historyEntryID { tasks[index].historyEntryID = historyID }
        if let notice = progress.notice { tasks[index].notice = notice }
        guard tasks[index].status == .processing else { persist(); return }
        let sampleDate = now()
        tasks[index].progressStage = progress.stage
        tasks[index].progressFraction = min(max(progress.fractionCompleted, 0), 1)
        if let mediaDurationSeconds = progress.mediaDurationSeconds {
            tasks[index].mediaDurationSeconds = mediaDurationSeconds
        }
        if let processedMediaDurationSeconds = progress.processedMediaDurationSeconds {
            tasks[index].processedMediaDurationSeconds = processedMediaDurationSeconds
        }
        updateProcessingSpeed(for: &tasks[index], at: sampleDate)
        tasks[index].estimatedTotalSeconds = MeetingFileTask.updatedEstimatedTotalSeconds(
            current: tasks[index].estimatedTotalSeconds,
            elapsed: tasks[index].elapsedSeconds(now: now()),
            progressFraction: tasks[index].progressFraction,
            mediaDurationSeconds: tasks[index].mediaDurationSeconds,
            processedMediaDurationSeconds: tasks[index].processedMediaDurationSeconds,
            stage: progress.stage,
            processingSpeed: tasks[index].processingSpeedSecondsPerSecond
        )
        persist()
    }

    private func updateProcessingSpeed(for task: inout MeetingFileTask, at sampleDate: Date) {
        guard task.progressStage == .transcribing,
              let processedDuration = task.processedMediaDurationSeconds,
              processedDuration > 0
        else { return }

        if let previousDate = task.speedSampleAt,
           let previousProcessedDuration = task.speedSampleProcessedMediaDurationSeconds {
            let wallDuration = sampleDate.timeIntervalSince(previousDate)
            let audioDuration = processedDuration - previousProcessedDuration
            if wallDuration > 0, audioDuration > 0 {
                let instantaneousSpeed = audioDuration / wallDuration
                if let existingSpeed = task.processingSpeedSecondsPerSecond {
                    task.processingSpeedSecondsPerSecond = existingSpeed * 0.7 + instantaneousSpeed * 0.3
                } else {
                    task.processingSpeedSecondsPerSecond = instantaneousSpeed
                }
            }
        }

        task.speedSampleAt = sampleDate
        task.speedSampleProcessedMediaDurationSeconds = processedDuration
    }

    private func markResourceInterruption(taskID: UUID, message: String) {
        if isShuttingDown {
            markInterrupted(taskID: taskID)
        } else if task(id: taskID)?.status == .cancelling {
            markCancelled(taskID: taskID)
        } else {
            markPaused(taskID: taskID, message: message)
        }
    }

    private func markPaused(taskID: UUID, message: String? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .paused
        tasks[index].errorMessage = message
        tasks[index].completedAt = now()
    }

    private func removeTaskFiles(_ task: MeetingFileTask) {
        let source = stagedURL(for: task)
        try? fileManager.removeItem(at: source)
        try? fileManager.removeItem(at: source.appendingPathExtension("partial"))
        try? fileManager.removeItem(at: MeetingFileCheckpointStore.directory(for: source))
    }

    private func markCancelled(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .cancelled
        tasks[index].completedAt = now()
    }

    private func markInterrupted(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if tasks[index].status == .pausing {
            markPaused(taskID: taskID)
            return
        }
        if tasks[index].status == .cancelling {
            markCancelled(taskID: taskID)
            return
        }
        var task = tasks[index].resetForRetry()
        task.historyEntryID = tasks[index].historyEntryID
        task.errorMessage = AppLocalization.localizedString("The task was interrupted and has been queued again.")
        tasks[index] = task
    }

    private func markFailed(taskID: UUID, error: Error) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .failed
        tasks[index].completedAt = now()
        tasks[index].errorMessage = error.localizedDescription
        SystemNotificationSupport.post(
            title: AppLocalization.localizedString("File conversion failed"),
            body: AppLocalization.format("%@: %@", tasks[index].fileName, error.localizedDescription)
        )
    }

    private func stage(sourceURL: URL, taskID: UUID, stagedFileName: String) {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        let destinationURL = storageDirectoryURL.appendingPathComponent(stagedFileName)
        let fileManager = self.fileManager
        let storageDirectoryURL = self.storageDirectoryURL
        let previousStagingTask = stagingTail
        let partialURL = destinationURL.appendingPathExtension("partial")

        let stagingTask = Task { @MainActor [weak self] in
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
                self?.stagingTasks.removeValue(forKey: taskID)
                if self?.stagingTasks.isEmpty == true { self?.stagingTail = nil }
            }

            do {
                // Keep the provider URL/security scope intact while waiting. Only
                // one task may decode or copy audio at a time.
                await previousStagingTask?.value
                try Task.checkCancellation()
                guard let mediaDuration = await MeetingFileImportSupport.mediaDurationSeconds(at: sourceURL) else {
                    throw MeetingFileTaskStagingError.mediaDurationUnavailable
                }
                let preparedBytes = try MeetingFileResourcePolicy.preparedByteCount(duration: mediaDuration)
                guard self?.reserveStagingBytes(preparedBytes, for: taskID) == true else {
                    throw MeetingFileTaskStagingError.stagingLimitExceeded
                }
                try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try MeetingFileResourcePolicy.requireDiskSpace(at: storageDirectoryURL, additionalBytes: preparedBytes)
                self?.updateMediaDuration(mediaDuration, taskID: taskID)
                let preparation = Task.detached(priority: .utility) {
                    if (try? MeetingImportedAudioFile.openPrepared(at: sourceURL)) != nil {
                        try Self.copyFileCancellable(
                            from: sourceURL, to: partialURL, fileManager: fileManager,
                            maximumByteCount: preparedBytes + 32_000
                        )
                    } else {
                        _ = try await MeetingImportedAudioFile.prepare(from: sourceURL, destinationURL: partialURL)
                    }
                    try Task.checkCancellation()
                    _ = try MeetingImportedAudioFile.openPrepared(at: partialURL)
                    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: partialURL.path)
                    try fileManager.moveItem(at: partialURL, to: destinationURL)
                }
                try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: {
                    preparation.cancel()
                }
                try Task.checkCancellation()
                // Replace the metadata estimate with the actual decoded size.
                self?.releaseStagingReservation(for: taskID)
                guard let actualBytes = self?.sourceByteCount(at: destinationURL, fileManager: fileManager),
                      self?.reserveStagingBytes(actualBytes, for: taskID) == true else {
                    throw MeetingFileTaskStagingError.stagingLimitExceeded
                }
                self?.stagingTaskIDs.remove(taskID)
                self?.persist()
                self?.startIfNeeded()
            } catch {
                try? fileManager.removeItem(at: partialURL)
                try? fileManager.removeItem(at: destinationURL)
                self?.stagingTaskIDs.remove(taskID)
                self?.releaseStagingReservation(for: taskID)
                if !(error is CancellationError), self?.task(id: taskID)?.status != .cancelled {
                    self?.markFailed(taskID: taskID, error: error)
                }
                self?.persist()
                self?.startIfNeeded()
            }
        }
        stagingTasks[taskID] = stagingTask
        stagingTail = stagingTask
    }

    private func stagedURL(for task: MeetingFileTask) -> URL {
        storageDirectoryURL.appendingPathComponent(task.stagedFileName)
    }

    private func updateMediaDuration(_ duration: TimeInterval?, taskID: UUID) {
        guard let duration,
              let index = tasks.firstIndex(where: { $0.id == taskID })
        else { return }
        tasks[index].mediaDurationSeconds = duration
    }

    private func reserveStagingBytes(_ byteCount: Int64, for taskID: UUID) -> Bool {
        guard byteCount >= 0,
              byteCount <= Self.maximumStagedSourceBytes,
              stagingReservations[taskID] == nil,
              reservedStagingBytes <= Self.maximumStagedSourceBytes - byteCount
        else {
            return false
        }
        stagingReservations[taskID] = byteCount
        reservedStagingBytes += byteCount
        return true
    }

    private func releaseStagingReservation(for taskID: UUID) {
        guard let byteCount = stagingReservations.removeValue(forKey: taskID) else { return }
        reservedStagingBytes = max(0, reservedStagingBytes - byteCount)
    }

    private func sourceByteCount(at url: URL, fileManager: FileManager) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return size.int64Value
    }

    private func restoreStagingReservations() {
        stagingReservations.removeAll()
        reservedStagingBytes = 0
        for task in tasks {
            let url = stagedURL(for: task)
            guard let byteCount = sourceByteCount(at: url, fileManager: fileManager), byteCount >= 0 else {
                continue
            }
            stagingReservations[task.id] = byteCount
            let (sum, overflow) = reservedStagingBytes.addingReportingOverflow(byteCount)
            reservedStagingBytes = overflow ? Int64.max : sum
        }
    }

    private nonisolated static func copyFileCancellable(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager,
        maximumByteCount: Int64
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        guard fileManager.createFile(atPath: destinationURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }

        var copiedByteCount: Int64 = 0
        while true {
            try Task.checkCancellation()
            let byteCount = try autoreleasepool {
                guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { return 0 }
                let (total, overflow) = copiedByteCount.addingReportingOverflow(Int64(data.count))
                guard !overflow, total <= maximumByteCount else { throw MeetingFileTaskStagingError.sourceTooLarge }
                try output.write(contentsOf: data)
                return data.count
            }
            guard byteCount > 0 else { break }
            copiedByteCount += Int64(byteCount)
            if copiedByteCount.isMultiple(of: 32 * 1_048_576) {
                try MeetingFileResourcePolicy.requireDiskSpace(at: destinationURL.deletingLastPathComponent())
            }
        }
        try output.synchronize()
    }

    private func loadPersistedTasks() {
        do {
            guard fileManager.fileExists(atPath: taskFileURL.path) else { return }
            let data = try Data(contentsOf: taskFileURL)
            let payload = try JSONDecoder().decode(PersistedPayload.self, from: data)
            loadedTaskManifest = true
            tasks = payload.tasks.filter { task in
                task.stagedFileName == URL(fileURLWithPath: task.stagedFileName).lastPathComponent &&
                    task.stagedFileName.hasPrefix(task.id.uuidString + "-")
            }.map { task in
                guard task.status == .processing || task.status == .cancelling || task.status == .pausing else { return task }
                var restored = task.resetForRetry()
                restored.historyEntryID = task.historyEntryID
                if task.status == .pausing {
                    restored.status = .paused
                } else if task.status == .cancelling {
                    restored.status = .cancelled
                } else {
                    restored.errorMessage = AppLocalization.localizedString("The task was interrupted and has been queued again.")
                }
                return restored
            }
            // Only task-owned paths are removed. A prepared .partial file cannot
            // be resumed without the original security-scoped source URL.
            for index in tasks.indices {
                let task = tasks[index]
                try? fileManager.removeItem(at: stagedURL(for: task).appendingPathExtension("partial"))
                if task.status == .completed && !task.hasPendingSpeakerAnalysis {
                    removeTaskFiles(task)
                }
            }
            restoreStagingReservations()
            persist()
        } catch {
            tasks = []
            VoxtLog.meetingWarning("File queue restore failed; recovery files were retained. error=\(error.localizedDescription)")
        }
    }

    private func removeAbandonedTaskFiles() {
        // Never sweep arbitrary temporary files or user-selected media. Only this
        // queue's UUID-owned names, older than a day and absent from its manifest.
        guard loadedTaskManifest, let urls = try? fileManager.contentsOfDirectory(
            at: storageDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        let knownIDs = Set(tasks.map(\.id))
        let cutoff = now().addingTimeInterval(-24 * 60 * 60)
        for url in urls {
            let name = url.lastPathComponent
            guard name.count > 37, name.dropFirst(36).first == "-",
                  let id = UUID(uuidString: String(name.prefix(36))), !knownIDs.contains(id),
                  ["wav", "partial", "analysis"].contains(url.pathExtension),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate, modified < cutoff else { continue }
            let source = url.pathExtension == "analysis" || url.pathExtension == "partial"
                ? url.deletingPathExtension() : url
            let checkpoint = MeetingFileCheckpointStore.directory(for: source).appendingPathComponent("manifest.json")
            // A lost queue row is not permission to delete a recoverable transcript.
            guard !fileManager.fileExists(atPath: checkpoint.path) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func persist() {
        let payload = PersistedPayload(version: 1, tasks: tasks)
        persistenceCoordinator.scheduleWrite(payload, to: taskFileURL)
    }

    private static func defaultStorageDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("meeting-file-tasks", isDirectory: true)
    }
}

// MeetingFileTaskQueue.swift
// Provides persistent, serial processing for imported meeting files.

import Combine
import Foundation

enum MeetingFileTaskStatus: String, Codable, Hashable, Sendable {
    case queued
    case processing
    case cancelling
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .queued, .processing, .cancelling:
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

    var isTerminal: Bool { status.isTerminal }

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
    private static let maximumSingleSourceBytes: Int64 = 4 * 1024 * 1024 * 1024
    private static let maximumStagedSourceBytes: Int64 = 8 * 1024 * 1024 * 1024
    private static let minimumFreeDiskBytes: Int64 = 512 * 1024 * 1024
    private nonisolated static let copyChunkByteCount = 1024 * 1024
    private var workerTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var activeTaskID: UUID?
    private var stagingTaskIDs: Set<UUID> = []
    private var stagingTasks: [UUID: Task<Void, Never>] = [:]
    private var stagingReservations: [UUID: Int64] = [:]
    private var reservedStagingBytes: Int64 = 0
    private var isShuttingDown = false

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
    }

    var hasActiveTasks: Bool {
        tasks.contains { !$0.isTerminal }
    }

    var hasFinishedTasks: Bool {
        tasks.contains(where: \.isTerminal)
    }

    func task(id: UUID) -> MeetingFileTask? {
        tasks.first { $0.id == id }
    }

    func enqueue(urls: [URL]) {
        guard !isShuttingDown else { return }

        for sourceURL in urls {
            guard MeetingFileImportSupport.isSupportedImportFile(at: sourceURL) else { continue }

            let taskID = UUID()
            let fileName = sourceURL.lastPathComponent
            let stagedFileName = taskID.uuidString + "-" + fileName
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
        }

        persist()
        startIfNeeded()
    }

    func cancel(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard !tasks[index].isTerminal else { return }

        if activeTaskID == taskID, tasks[index].status == .processing {
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
        guard tasks[index].status == .failed || tasks[index].status == .cancelled else { return }
        guard fileManager.fileExists(atPath: stagedURL(for: tasks[index]).path) else {
            tasks[index].status = .failed
            tasks[index].errorMessage = AppLocalization.localizedString("The staged source file is no longer available.")
            persist()
            return
        }

        tasks[index] = tasks[index].resetForRetry()
        persist()
        startIfNeeded()
    }

    func clearFinishedTasks() {
        let finishedTasks = tasks.filter(\.isTerminal)
        tasks.removeAll(where: \.isTerminal)
        for task in finishedTasks {
            try? fileManager.removeItem(at: stagedURL(for: task))
            if !fileManager.fileExists(atPath: stagedURL(for: task).path) {
                releaseStagingReservation(for: task.id)
            }
        }
        persist()
    }

    func startIfNeeded() {
        guard !isShuttingDown, workerTask == nil, tasks.contains(where: { !$0.isTerminal }) else { return }
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
                guard tasks.contains(where: { !$0.isTerminal }) else { return }
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
                let shouldRollback = isShuttingDown || tasks[finishedIndex].status == .cancelling
                if shouldRollback {
                    rollbackAnalysis(entry)
                }
                if isShuttingDown {
                    markInterrupted(taskID: taskID)
                } else if tasks[finishedIndex].status == .cancelling {
                    tasks[finishedIndex].status = .cancelled
                    tasks[finishedIndex].completedAt = now()
                } else {
                    tasks[finishedIndex].status = .completed
                    tasks[finishedIndex].completedAt = now()
                    tasks[finishedIndex].progressStage = .saving
                    tasks[finishedIndex].progressFraction = 1
                    tasks[finishedIndex].historyEntryID = entry.id
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
                } else {
                    markCancelled(taskID: taskID)
                }
            } catch {
                markFailed(taskID: taskID, error: error)
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
        guard let index = tasks.firstIndex(where: { !$0.isTerminal }) else { return nil }
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
              tasks[index].status == .processing
        else { return }
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

    private func markCancelled(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .cancelled
        tasks[index].completedAt = now()
    }

    private func markInterrupted(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var task = tasks[index].resetForRetry()
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

        let stagingTask = Task { @MainActor [weak self] in
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
                self?.stagingTasks.removeValue(forKey: taskID)
            }

            do {
                guard let sourceByteCount = self?.sourceByteCount(at: sourceURL, fileManager: fileManager) else {
                    throw MeetingFileTaskStagingError.sourceUnavailable
                }
                guard sourceByteCount <= Self.maximumSingleSourceBytes else {
                    throw MeetingFileTaskStagingError.sourceTooLarge
                }
                guard self?.reserveStagingBytes(sourceByteCount, for: taskID) == true else {
                    throw MeetingFileTaskStagingError.stagingLimitExceeded
                }

                try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
                guard self?.hasSufficientDiskSpace(
                    for: self?.unmaterializedStagingBytes() ?? 0,
                    at: storageDirectoryURL
                ) == true else {
                    throw MeetingFileTaskStagingError.insufficientDiskSpace
                }
                let copyTask = Task.detached(priority: .utility) {
                    try Self.copyFileCancellable(
                        from: sourceURL,
                        to: destinationURL,
                        fileManager: fileManager,
                        maximumByteCount: sourceByteCount
                    )
                }
                try await withTaskCancellationHandler {
                    try await copyTask.value
                } onCancel: {
                    copyTask.cancel()
                }
                try Task.checkCancellation()
                guard let mediaDuration = await MeetingFileImportSupport.mediaDurationSeconds(at: destinationURL) else {
                    throw MeetingFileTaskStagingError.mediaDurationUnavailable
                }
                guard mediaDuration <= MeetingFileImportSupport.maximumAnalysisDurationSeconds else {
                    throw MeetingFileTaskStagingError.mediaTooLong
                }
                self?.updateMediaDuration(mediaDuration, taskID: taskID)

                let estimatedWAVByteCount = self?.estimatedWAVByteCount(for: mediaDuration) ?? 0
                let (pendingBytes, pendingBytesOverflow) = (self?.unmaterializedStagingBytes(excluding: taskID) ?? 0)
                    .addingReportingOverflow(estimatedWAVByteCount)
                guard !pendingBytesOverflow else {
                    throw MeetingFileTaskStagingError.insufficientDiskSpace
                }
                guard self?.hasSufficientDiskSpace(
                    for: pendingBytes,
                    at: storageDirectoryURL
                ) == true else {
                    throw MeetingFileTaskStagingError.insufficientDiskSpace
                }

                self?.stagingTaskIDs.remove(taskID)
                self?.persist()
                self?.startIfNeeded()
            } catch {
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
              byteCount <= Self.maximumSingleSourceBytes,
              stagingReservations[taskID] == nil,
              reservedStagingBytes <= Self.maximumStagedSourceBytes - byteCount
        else {
            return false
        }
        stagingReservations[taskID] = byteCount
        reservedStagingBytes += byteCount
        return true
    }

    private func unmaterializedStagingBytes(excluding taskID: UUID? = nil) -> Int64 {
        stagingTaskIDs.reduce(into: Int64(0)) { total, stagingTaskID in
            guard stagingTaskID != taskID,
                  let byteCount = stagingReservations[stagingTaskID]
            else { return }
            let (sum, overflow) = total.addingReportingOverflow(byteCount)
            total = overflow ? Int64.max : sum
        }
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

    private func estimatedWAVByteCount(for duration: TimeInterval) -> Int64 {
        let bytesPerSecond = Double(MeetingImportedAudioFile.targetSampleRate * MemoryLayout<Int16>.size)
        let estimated = duration * bytesPerSecond
        guard estimated.isFinite, estimated > 0 else { return 0 }
        return min(Int64(estimated.rounded(.up)), MeetingImportedWAVFormat.maximumDataByteCount)
    }

    private func hasSufficientDiskSpace(for requiredBytes: Int64, at url: URL) -> Bool {
        guard requiredBytes >= 0 else {
            return false
        }
        let (requiredWithReserve, requiredBytesOverflow) = requiredBytes
            .addingReportingOverflow(Self.minimumFreeDiskBytes)
        guard !requiredBytesOverflow else { return false }
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else {
            return false
        }
        let available: Int64?
        if let importantCapacity = values.volumeAvailableCapacityForImportantUsage {
            available = Int64(importantCapacity)
        } else if let capacity = values.volumeAvailableCapacity {
            available = Int64(capacity)
        } else {
            available = nil
        }
        return available.map { $0 >= requiredWithReserve } ?? false
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
        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }

        var copiedByteCount: Int64 = 0
        while true {
            try Task.checkCancellation()
            guard let data = try input.read(upToCount: Self.copyChunkByteCount), !data.isEmpty else {
                break
            }
            let (newCopiedByteCount, overflow) = copiedByteCount.addingReportingOverflow(Int64(data.count))
            guard !overflow, newCopiedByteCount <= maximumByteCount else {
                throw MeetingFileTaskStagingError.sourceTooLarge
            }
            try output.write(contentsOf: data)
            copiedByteCount = newCopiedByteCount
        }
        try output.synchronize()
    }

    private func loadPersistedTasks() {
        do {
            guard fileManager.fileExists(atPath: taskFileURL.path) else { return }
            let data = try Data(contentsOf: taskFileURL)
            let payload = try JSONDecoder().decode(PersistedPayload.self, from: data)
            tasks = payload.tasks.map { task in
                guard task.status == .processing || task.status == .cancelling else { return task }
                var restored = task.resetForRetry()
                restored.errorMessage = AppLocalization.localizedString("The task was interrupted and has been queued again.")
                return restored
            }
            restoreStagingReservations()
            persist()
        } catch {
            tasks = []
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

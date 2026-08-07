// MeetingLocalInferenceCoordinator.swift
// Provides one bounded, priority-aware lane for heavyweight local meeting inference.

import Foundation

nonisolated enum MeetingLocalInferenceWorkClass: String, Sendable {
    case liveASRFeed
    case liveASRFinal
    case liveASRPartial
    case realtimeTranslation
    case fileASR
    case finalASR
    case speakerAnalysis
    case detailTranslation
    case summary

    var priority: Int {
        switch self {
        case .liveASRFeed: return 100
        case .liveASRFinal: return 95
        case .liveASRPartial: return 85
        case .realtimeTranslation: return 70
        case .fileASR: return 10
        case .finalASR: return 60
        case .speakerAnalysis: return 50
        case .detailTranslation: return 40
        case .summary: return 20
        }
    }

    var waitsWhileRecording: Bool {
        switch self {
        case .fileASR, .finalASR, .speakerAnalysis, .detailTranslation, .summary:
            return true
        case .liveASRFeed, .liveASRFinal, .liveASRPartial, .realtimeTranslation:
            return false
        }
    }

    var isThermallyDeferrable: Bool {
        switch self {
        case .liveASRFeed, .liveASRFinal, .finalASR:
            return false
        case .liveASRPartial, .realtimeTranslation, .fileASR, .speakerAnalysis, .detailTranslation, .summary:
            return true
        }
    }

    var isMemoryDeferrable: Bool {
        switch self {
        case .liveASRFeed, .liveASRFinal, .finalASR:
            return false
        case .liveASRPartial, .realtimeTranslation, .fileASR, .speakerAnalysis, .detailTranslation, .summary:
            return true
        }
    }
}

nonisolated struct MeetingLocalInferenceStatistics: Equatable, Sendable {
    var submittedCount = 0
    var completedCount = 0
    var cancelledCount = 0
    var overloadedCount = 0
    var thermalDeferralCount = 0
    var memoryDeferralCount = 0
    var peakQueuedCount = 0
    var totalWaitMilliseconds: Int64 = 0
}

nonisolated enum MeetingLocalInferenceCoordinatorError: LocalizedError, Sendable {
    case overloaded
    case thermallyConstrained
    case memoryConstrained

    var errorDescription: String? {
        switch self {
        case .overloaded:
            return "The local meeting inference queue reached its safety limit."
        case .thermallyConstrained:
            return "The Mac is too warm for this nonessential local inference task right now."
        case .memoryConstrained:
            return "The Mac is under memory pressure, so this nonessential local inference task was deferred."
        }
    }
}

actor MeetingLocalInferenceCoordinator {
    static let shared = MeetingLocalInferenceCoordinator()

    private struct Waiter {
        let id: UUID
        let workClass: MeetingLocalInferenceWorkClass
        let sequence: Int64
        let submittedAt: ContinuousClock.Instant
        let continuation: CheckedContinuation<UUID, Error>
    }

    private static let maximumQueuedWork = 32

    private var activeToken: UUID?
    private var waiters: [Waiter] = []
    private var cancelledWaiterIDs = Set<UUID>()
    private var sequence: Int64 = 0
    private var recordingActive = false
    private var memoryPressureConstrained = false
    private var statistics = MeetingLocalInferenceStatistics()
    private let clock = ContinuousClock()

    func setRecordingActive(_ isActive: Bool) {
        recordingActive = isActive
        scheduleNextIfPossible()
    }

    func setMemoryPressureConstrained(_ isConstrained: Bool) {
        memoryPressureConstrained = isConstrained
        scheduleNextIfPossible()
    }

    func withPermit<T: Sendable>(
        _ workClass: MeetingLocalInferenceWorkClass,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let token = try await acquire(workClass)
        defer { release(token) }
        try Task.checkCancellation()
        let value = try await operation()
        statistics.completedCount += 1
        return value
    }

    func currentStatistics() -> MeetingLocalInferenceStatistics {
        statistics
    }

    func resetStatistics() {
        statistics = MeetingLocalInferenceStatistics()
    }

    private func acquire(_ workClass: MeetingLocalInferenceWorkClass) async throws -> UUID {
        try Task.checkCancellation()
        statistics.submittedCount += 1

        if workClass.isThermallyDeferrable {
            switch ProcessInfo.processInfo.thermalState {
            case .serious, .critical:
                statistics.thermalDeferralCount += 1
                throw MeetingLocalInferenceCoordinatorError.thermallyConstrained
            case .nominal, .fair:
                break
            @unknown default:
                break
            }
        }

        if memoryPressureConstrained, workClass.isMemoryDeferrable {
            statistics.memoryDeferralCount += 1
            throw MeetingLocalInferenceCoordinatorError.memoryConstrained
        }

        if activeToken == nil, canRun(workClass) {
            let token = UUID()
            activeToken = token
            return token
        }
        guard waiters.count < Self.maximumQueuedWork else {
            statistics.overloadedCount += 1
            throw MeetingLocalInferenceCoordinatorError.overloaded
        }

        let waiterID = UUID()
        let submittedAt = clock.now
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled || cancelledWaiterIDs.remove(waiterID) != nil {
                    statistics.cancelledCount += 1
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sequence += 1
                waiters.append(
                    Waiter(
                        id: waiterID,
                        workClass: workClass,
                        sequence: sequence,
                        submittedAt: submittedAt,
                        continuation: continuation
                    )
                )
                waiters.sort {
                    if $0.workClass.priority == $1.workClass.priority {
                        return $0.sequence < $1.sequence
                    }
                    return $0.workClass.priority > $1.workClass.priority
                }
                statistics.peakQueuedCount = max(statistics.peakQueuedCount, waiters.count)
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            statistics.cancelledCount += 1
            waiter.continuation.resume(throwing: CancellationError())
        } else {
            cancelledWaiterIDs.insert(id)
        }
    }

    private func release(_ token: UUID) {
        guard activeToken == token else { return }
        activeToken = nil
        scheduleNextIfPossible()
    }

    private func scheduleNextIfPossible() {
        guard activeToken == nil,
              let index = waiters.firstIndex(where: { canRun($0.workClass) })
        else {
            return
        }
        let waiter = waiters.remove(at: index)
        let token = UUID()
        activeToken = token
        let waited = waiter.submittedAt.duration(to: clock.now)
        let components = waited.components
        let milliseconds = (components.seconds * 1_000) + (components.attoseconds / 1_000_000_000_000_000)
        statistics.totalWaitMilliseconds += Int64(max(0, milliseconds))
        waiter.continuation.resume(returning: token)
    }

    private func canRun(_ workClass: MeetingLocalInferenceWorkClass) -> Bool {
        !(recordingActive && workClass.waitsWhileRecording) &&
            !(memoryPressureConstrained && workClass.isMemoryDeferrable)
    }
}

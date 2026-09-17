// File-only safety limits. These are conservative release gates, not benchmark claims.
import Foundation

nonisolated enum MeetingFileResourcePolicy {
    static let minimumFreeDiskBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let maximumDurationSeconds: TimeInterval = 12 * 60 * 60
    static let maximumPreparedQueueBytes: Int64 = 8 * 1024 * 1024 * 1024

    static func preparedByteCount(duration: TimeInterval) throws -> Int64 {
        guard duration.isFinite, duration > 0 else {
            throw MeetingFileTaskStagingError.mediaDurationUnavailable
        }
        guard duration <= maximumDurationSeconds else {
            throw MeetingFileTaskStagingError.mediaTooLong
        }
        return Int64((duration * 32_000).rounded(.up)) + 44
    }

    static func allowsOfflineSpeakers(duration: TimeInterval, physicalMemory: UInt64) -> Bool {
        // Bound the full-session frame matrices until real-device acceptance data allows expansion.
        let limit: TimeInterval = physicalMemory <= 8 * 1024 * 1024 * 1024 ? 30 * 60 : 60 * 60
        return duration.isFinite && duration > 0 && duration <= limit
    }

    static func checkBackgroundWork() async throws {
        try await MeetingLocalInferenceCoordinator.shared.checkFileResources()
        let foregroundActive = await MainActor.run { AppDelegate.shared?.isSessionActive == true }
        guard !foregroundActive else { throw MeetingFileWorkError.resourcesUnavailable }
    }

    static func requireDiskSpace(at url: URL, additionalBytes: Int64 = 0) throws {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let capacity = values.volumeAvailableCapacity, additionalBytes >= 0 else {
            throw MeetingFileTaskStagingError.insufficientDiskSpace
        }
        let (required, overflow) = additionalBytes.addingReportingOverflow(minimumFreeDiskBytes)
        guard !overflow, Int64(capacity) >= required else {
            throw MeetingFileTaskStagingError.insufficientDiskSpace
        }
    }
}

nonisolated enum MeetingFileWorkError: LocalizedError {
    case resourcesUnavailable
    case incompatibleCheckpoint
    case invalidCheckpoint

    var errorDescription: String? {
        switch self {
        case .resourcesUnavailable:
            return AppLocalization.localizedString("File analysis paused to protect system resources. Resume when the Mac is ready.")
        case .incompatibleCheckpoint:
            return AppLocalization.localizedString("Transcription settings changed. Restore the previous settings to resume, or import the file as a new task.")
        case .invalidCheckpoint:
            return AppLocalization.localizedString("The file checkpoint is damaged. Import the file as a new task; existing results have been kept.")
        }
    }
}

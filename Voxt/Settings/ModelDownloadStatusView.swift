import SwiftUI

struct ModelDownloadStatusSnapshot: Equatable {
    private enum Kind: Equatable {
        case standard
        case customLLM
    }

    let progress: Double
    private let kind: Kind
    private let completed: Int64
    private let total: Int64
    private let currentFile: String?
    private let currentFileCompleted: Int64
    private let currentFileTotal: Int64
    private let completedFiles: Int
    private let totalFiles: Int

    var titleText: String {
        let formatKey = kind == .customLLM ? "Custom LLM downloading: %d%% • %@" : "Downloading: %d%% • %@"
        return AppLocalization.format(
            formatKey,
            Int(progress * 100),
            ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
        )
    }

    var detailText: String {
        ModelDownloadProgressFormatter.fileProgressText(
            currentFile: currentFile,
            currentFileCompleted: currentFileCompleted,
            currentFileTotal: currentFileTotal,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
    }

    static func fromMLXState(_ state: MLXModelManager.ModelState) -> Self? {
        guard case .downloading(let progress, let completed, let total, let currentFile, let completedFiles, let totalFiles) = state else {
            return nil
        }

        return .init(
            progress: progress,
            kind: .standard,
            completed: completed,
            total: total,
            currentFile: currentFile,
            currentFileCompleted: 0,
            currentFileTotal: 0,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
    }

    static func fromWhisperDownload(_ activeDownload: WhisperKitModelManager.ActiveDownload?) -> Self? {
        guard let activeDownload else { return nil }

        return .init(
            progress: activeDownload.progress,
            kind: .standard,
            completed: activeDownload.completed,
            total: activeDownload.total,
            currentFile: activeDownload.currentFile,
            currentFileCompleted: activeDownload.currentFileCompleted,
            currentFileTotal: activeDownload.currentFileTotal,
            completedFiles: activeDownload.completedFiles,
            totalFiles: activeDownload.totalFiles
        )
    }

    static func fromCustomLLMState(_ state: CustomLLMModelManager.ModelState) -> Self? {
        guard case .downloading(let progress, let completed, let total, let currentFile, let completedFiles, let totalFiles) = state else {
            return nil
        }

        return .init(
            progress: progress,
            kind: .customLLM,
            completed: completed,
            total: total,
            currentFile: currentFile,
            currentFileCompleted: 0,
            currentFileTotal: 0,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
    }
}

struct ModelDownloadStatusView: View {
    let status: ModelDownloadStatusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: max(0, min(status.progress, 1)))
                .controlSize(.small)

            Text(status.titleText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(status.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

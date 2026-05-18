import Foundation

enum RecordingStartBlockReason: Equatable {
    case mlxModelNotInstalled
    case mlxModelDownloading
    case mlxModelUnavailable(detail: String?)
    case whisperModelNotInstalled
    case whisperModelDownloading
    case whisperModelUnavailable(detail: String?)

    var userMessage: String {
        switch self {
        case .mlxModelNotInstalled:
            return String(localized: "MLX model is not downloaded. Open Settings > Model to install it.")
        case .mlxModelDownloading:
            return String(localized: "MLX model is still downloading. Wait for installation to finish and try again.")
        case .mlxModelUnavailable(let detail):
            return Self.appendingDetail(
                base: String(localized: "MLX model is unavailable. Open Settings > Model to fix it."),
                detail: detail
            )
        case .whisperModelNotInstalled:
            return String(localized: "Whisper model is not downloaded. Open Settings > Model to install it.")
        case .whisperModelDownloading:
            return String(localized: "Whisper model is still downloading. Wait for installation to finish and try again.")
        case .whisperModelUnavailable(let detail):
            return Self.appendingDetail(
                base: String(localized: "Whisper model is unavailable. Open Settings > Model to fix it."),
                detail: detail
            )
        }
    }

    var logDescription: String {
        switch self {
        case .mlxModelNotInstalled:
            return "MLX Audio model is not downloaded."
        case .mlxModelDownloading:
            return "MLX Audio model download is still in progress."
        case .mlxModelUnavailable(let detail):
            return Self.appendingDetail(base: "MLX Audio model is unavailable.", detail: detail)
        case .whisperModelNotInstalled:
            return "Whisper model is not downloaded."
        case .whisperModelDownloading:
            return "Whisper model download is still in progress."
        case .whisperModelUnavailable(let detail):
            return Self.appendingDetail(base: "Whisper model is unavailable.", detail: detail)
        }
    }

    private static func appendingDetail(base: String, detail: String?) -> String {
        guard let detail else { return base }
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let prefix = String(localized: "Reason:")
        return "\(base) \(prefix) \(trimmed)"
    }
}

enum RecordingStartDecision: Equatable {
    case start(TranscriptionEngine)
    case blocked(RecordingStartBlockReason)
}

enum RecordingStartPlanner {
    private enum DownloadableModelAvailability {
        case ready
        case notDownloaded
        case downloadingSelectedModel
        case unavailable(detail: String?)
    }

    private enum DownloadStatePhase {
        case ready
        case notDownloaded
        case activeDownload
        case unavailable(detail: String?)
    }

    static func resolve(
        selectedEngine: TranscriptionEngine,
        selectedMLXRepo: String? = nil,
        activeMLXDownloadRepo: String? = nil,
        isSelectedMLXModelDownloaded: Bool = false,
        mlxModelState: MLXModelManager.ModelState,
        selectedWhisperModelID: String? = nil,
        activeWhisperDownloadModelID: String? = nil,
        isSelectedWhisperModelDownloaded: Bool = false,
        whisperModelState: WhisperKitModelManager.ModelState
    ) -> RecordingStartDecision {
        switch selectedEngine {
        case .dictation:
            return .start(.dictation)
        case .remote:
            return .start(.remote)
        case .mlxAudio:
            return decision(
                engine: .mlxAudio,
                availability: mlxAvailability(
                    selectedRepo: selectedMLXRepo,
                    activeDownloadRepo: activeMLXDownloadRepo,
                    isSelectedModelDownloaded: isSelectedMLXModelDownloaded,
                    state: mlxModelState
                ),
                notInstalledReason: .mlxModelNotInstalled,
                downloadingReason: .mlxModelDownloading,
                unavailableReason: { detail in .mlxModelUnavailable(detail: detail) }
            )
        case .whisperKit:
            return decision(
                engine: .whisperKit,
                availability: whisperAvailability(
                    selectedModelID: selectedWhisperModelID,
                    activeDownloadModelID: activeWhisperDownloadModelID,
                    isSelectedModelDownloaded: isSelectedWhisperModelDownloaded,
                    state: whisperModelState
                ),
                notInstalledReason: .whisperModelNotInstalled,
                downloadingReason: .whisperModelDownloading,
                unavailableReason: { detail in .whisperModelUnavailable(detail: detail) }
            )
        }
    }

    private static func decision(
        engine: TranscriptionEngine,
        availability: DownloadableModelAvailability,
        notInstalledReason: RecordingStartBlockReason,
        downloadingReason: RecordingStartBlockReason,
        unavailableReason: (String?) -> RecordingStartBlockReason
    ) -> RecordingStartDecision {
        switch availability {
        case .ready:
            return .start(engine)
        case .notDownloaded:
            return .blocked(notInstalledReason)
        case .downloadingSelectedModel:
            return .blocked(downloadingReason)
        case .unavailable(let detail):
            return .blocked(unavailableReason(detail))
        }
    }

    private static func mlxAvailability(
        selectedRepo: String?,
        activeDownloadRepo: String?,
        isSelectedModelDownloaded: Bool,
        state: MLXModelManager.ModelState
    ) -> DownloadableModelAvailability {
        availability(
            selectedIdentifier: selectedRepo,
            activeIdentifier: activeDownloadRepo,
            isSelectedModelDownloaded: isSelectedModelDownloaded,
            canonicalize: MLXModelManager.canonicalModelRepo,
            state: state
        )
    }

    private static func whisperAvailability(
        selectedModelID: String?,
        activeDownloadModelID: String?,
        isSelectedModelDownloaded: Bool,
        state: WhisperKitModelManager.ModelState
    ) -> DownloadableModelAvailability {
        availability(
            selectedIdentifier: selectedModelID,
            activeIdentifier: activeDownloadModelID,
            isSelectedModelDownloaded: isSelectedModelDownloaded,
            canonicalize: WhisperKitModelManager.canonicalModelID,
            state: state
        )
    }

    private static func availability(
        selectedIdentifier: String?,
        activeIdentifier: String?,
        isSelectedModelDownloaded: Bool,
        canonicalize: (String) -> String,
        state: MLXModelManager.ModelState
    ) -> DownloadableModelAvailability {
        availability(
            isSelectedDownloadActive: isSelectedOperationActive(
                selectedIdentifier: selectedIdentifier,
                activeIdentifier: activeIdentifier,
                canonicalize: canonicalize
            ),
            isSelectedModelDownloaded: isSelectedModelDownloaded,
            phase: downloadStatePhase(for: state)
        )
    }

    private static func availability(
        selectedIdentifier: String?,
        activeIdentifier: String?,
        isSelectedModelDownloaded: Bool,
        canonicalize: (String) -> String,
        state: WhisperKitModelManager.ModelState
    ) -> DownloadableModelAvailability {
        availability(
            isSelectedDownloadActive: isSelectedOperationActive(
                selectedIdentifier: selectedIdentifier,
                activeIdentifier: activeIdentifier,
                canonicalize: canonicalize
            ),
            isSelectedModelDownloaded: isSelectedModelDownloaded,
            phase: downloadStatePhase(for: state)
        )
    }

    private static func availability(
        isSelectedDownloadActive: Bool,
        isSelectedModelDownloaded: Bool,
        phase: DownloadStatePhase
    ) -> DownloadableModelAvailability {
        switch phase {
        case .ready:
            return .ready
        case .notDownloaded:
            return .notDownloaded
        case .activeDownload:
            if isSelectedDownloadActive {
                return .downloadingSelectedModel
            }
            return isSelectedModelDownloaded ? .ready : .notDownloaded
        case .unavailable(let detail):
            return .unavailable(detail: detail)
        }
    }

    private static func downloadStatePhase(for state: MLXModelManager.ModelState) -> DownloadStatePhase {
        switch state {
        case .downloaded, .ready, .loading:
            return .ready
        case .notDownloaded:
            return .notDownloaded
        case .downloading, .paused:
            return .activeDownload
        case .error(let message):
            return .unavailable(detail: message)
        }
    }

    private static func downloadStatePhase(for state: WhisperKitModelManager.ModelState) -> DownloadStatePhase {
        switch state {
        case .downloaded, .ready, .loading:
            return .ready
        case .notDownloaded:
            return .notDownloaded
        case .downloading, .paused:
            return .activeDownload
        case .error(let message):
            return .unavailable(detail: message)
        }
    }

    private static func isSelectedOperationActive(
        selectedIdentifier: String?,
        activeIdentifier: String?,
        canonicalize: (String) -> String
    ) -> Bool {
        guard let selectedIdentifier, let activeIdentifier else { return false }
        return canonicalize(selectedIdentifier) == canonicalize(activeIdentifier)
    }
}

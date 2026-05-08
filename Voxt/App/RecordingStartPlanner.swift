import Foundation

enum RecordingStartBlockReason: Equatable {
    case mlxModelNotInstalled
    case mlxModelDownloading
    case mlxModelUnavailable
    case whisperModelNotInstalled
    case whisperModelDownloading
    case whisperModelUnavailable

    var userMessage: String {
        switch self {
        case .mlxModelNotInstalled:
            return String(localized: "MLX model is not downloaded. Open Settings > Model to install it.")
        case .mlxModelDownloading:
            return String(localized: "MLX model is still downloading. Wait for installation to finish and try again.")
        case .mlxModelUnavailable:
            return String(localized: "MLX model is unavailable. Open Settings > Model to fix it.")
        case .whisperModelNotInstalled:
            return String(localized: "Whisper model is not downloaded. Open Settings > Model to install it.")
        case .whisperModelDownloading:
            return String(localized: "Whisper model is still downloading. Wait for installation to finish and try again.")
        case .whisperModelUnavailable:
            return String(localized: "Whisper model is unavailable. Open Settings > Model to fix it.")
        }
    }

    var logDescription: String {
        switch self {
        case .mlxModelNotInstalled:
            return "MLX Audio model is not downloaded."
        case .mlxModelDownloading:
            return "MLX Audio model download is still in progress."
        case .mlxModelUnavailable:
            return "MLX Audio model is unavailable."
        case .whisperModelNotInstalled:
            return "Whisper model is not downloaded."
        case .whisperModelDownloading:
            return "Whisper model download is still in progress."
        case .whisperModelUnavailable:
            return "Whisper model is unavailable."
        }
    }
}

enum RecordingStartDecision: Equatable {
    case start(TranscriptionEngine)
    case blocked(RecordingStartBlockReason)
}

enum RecordingStartPlanner {
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
            let selectedMLXCanonicalRepo = selectedMLXRepo.map(MLXModelManager.canonicalModelRepo)
            let activeMLXCanonicalRepo = activeMLXDownloadRepo.map(MLXModelManager.canonicalModelRepo)
            let isSelectedMLXDownloadActive =
                selectedMLXCanonicalRepo != nil &&
                selectedMLXCanonicalRepo == activeMLXCanonicalRepo

            if !isSelectedMLXDownloadActive,
               isSelectedMLXModelDownloaded,
               case .downloading = mlxModelState {
                return .start(.mlxAudio)
            }
            if !isSelectedMLXDownloadActive,
               isSelectedMLXModelDownloaded,
               case .paused = mlxModelState {
                return .start(.mlxAudio)
            }

            switch mlxModelState {
            case .downloaded, .ready, .loading:
                return .start(.mlxAudio)
            case .notDownloaded:
                return .blocked(.mlxModelNotInstalled)
            case .downloading, .paused:
                return isSelectedMLXDownloadActive
                    ? .blocked(.mlxModelDownloading)
                    : (isSelectedMLXModelDownloaded ? .start(.mlxAudio) : .blocked(.mlxModelNotInstalled))
            case .error:
                return .blocked(.mlxModelUnavailable)
            }
        case .whisperKit:
            let selectedWhisperCanonicalID = selectedWhisperModelID.map(WhisperKitModelManager.canonicalModelID)
            let activeWhisperCanonicalID = activeWhisperDownloadModelID.map(WhisperKitModelManager.canonicalModelID)
            let isSelectedWhisperDownloadActive =
                selectedWhisperCanonicalID != nil &&
                selectedWhisperCanonicalID == activeWhisperCanonicalID

            if !isSelectedWhisperDownloadActive,
               isSelectedWhisperModelDownloaded,
               case .downloading = whisperModelState {
                return .start(.whisperKit)
            }
            if !isSelectedWhisperDownloadActive,
               isSelectedWhisperModelDownloaded,
               case .paused = whisperModelState {
                return .start(.whisperKit)
            }

            switch whisperModelState {
            case .downloaded, .ready, .loading:
                return .start(.whisperKit)
            case .notDownloaded:
                return .blocked(.whisperModelNotInstalled)
            case .downloading, .paused:
                return isSelectedWhisperDownloadActive
                    ? .blocked(.whisperModelDownloading)
                    : (isSelectedWhisperModelDownloaded ? .start(.whisperKit) : .blocked(.whisperModelNotInstalled))
            case .error:
                return .blocked(.whisperModelUnavailable)
            }
        }
    }
}

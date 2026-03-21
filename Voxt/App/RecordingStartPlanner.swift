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
        mlxModelState: MLXModelManager.ModelState,
        whisperModelState: WhisperKitModelManager.ModelState
    ) -> RecordingStartDecision {
        switch selectedEngine {
        case .dictation:
            return .start(.dictation)
        case .remote:
            return .start(.remote)
        case .mlxAudio:
            switch mlxModelState {
            case .downloaded, .ready, .loading:
                return .start(.mlxAudio)
            case .notDownloaded:
                return .blocked(.mlxModelNotInstalled)
            case .downloading:
                return .blocked(.mlxModelDownloading)
            case .error:
                return .blocked(.mlxModelUnavailable)
            }
        case .whisperKit:
            switch whisperModelState {
            case .downloaded, .ready, .loading:
                return .start(.whisperKit)
            case .notDownloaded:
                return .blocked(.whisperModelNotInstalled)
            case .downloading:
                return .blocked(.whisperModelDownloading)
            case .error:
                return .blocked(.whisperModelUnavailable)
            }
        }
    }
}

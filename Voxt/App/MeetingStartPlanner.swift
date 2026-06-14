import Foundation

enum MeetingStartBlockReason: Equatable {
    case dictationUnsupported
    case recording(RecordingStartBlockReason)
    case remoteASRUnavailable
    case remoteASRMeetingUnavailable(RemoteASRProvider)

    var userMessage: String {
        switch self {
        case .dictationUnsupported:
            return String(localized: "Meeting Notes currently supports MLX Audio and Remote ASR. Direct Dictation is not available for meetings.")
        case .recording(let reason):
            return reason.userMessage
        case .remoteASRUnavailable:
            return String(localized: "Remote ASR is not configured yet. Open Settings > Model to finish the provider setup.")
        case .remoteASRMeetingUnavailable(let provider):
            return RemoteASRMeetingConfiguration.startBlockedMessage(for: provider)
        }
    }

    var logDescription: String {
        switch self {
        case .dictationUnsupported:
            return "Meeting Notes does not support Direct Dictation."
        case .recording(let reason):
            return reason.logDescription
        case .remoteASRUnavailable:
            return "Remote ASR provider configuration is incomplete."
        case .remoteASRMeetingUnavailable(let provider):
            return "Meeting ASR provider configuration is incomplete for \(provider.rawValue)."
        }
    }
}

enum MeetingStartDecision: Equatable {
    case start(TranscriptionEngine)
    case blocked(MeetingStartBlockReason)
}

enum MeetingStartPlanner {
    static func resolve(
        selectedEngine: TranscriptionEngine,
        selectedMLXRepo: String? = nil,
        activeMLXDownloadRepo: String? = nil,
        isSelectedMLXModelDownloaded: Bool = false,
        mlxModelState: MLXModelManager.ModelState,
        selectedWhisperModelID: String? = nil,
        activeWhisperDownloadModelID: String? = nil,
        isSelectedWhisperModelDownloaded: Bool = false,
        whisperModelState: WhisperKitModelManager.ModelState,
        remoteASRProvider: RemoteASRProvider,
        remoteASRConfiguration: RemoteProviderConfiguration
    ) -> MeetingStartDecision {
        switch selectedEngine {
        case .dictation:
            return .blocked(.dictationUnsupported)
        case .mlxAudio, .whisperKit:
            return resolveLocalMeetingStart(
                selectedMLXRepo: selectedMLXRepo,
                activeMLXDownloadRepo: activeMLXDownloadRepo,
                isSelectedMLXModelDownloaded: isSelectedMLXModelDownloaded,
                mlxModelState: mlxModelState,
                selectedWhisperModelID: selectedWhisperModelID,
                activeWhisperDownloadModelID: activeWhisperDownloadModelID,
                isSelectedWhisperModelDownloaded: isSelectedWhisperModelDownloaded,
                whisperModelState: whisperModelState
            )
        case .remote:
            guard remoteASRConfiguration.isConfigured else {
                return .blocked(.remoteASRUnavailable)
            }
            guard RemoteASRMeetingConfiguration.hasValidMeetingModel(
                provider: remoteASRProvider,
                configuration: remoteASRConfiguration
            ) else {
                return .blocked(.remoteASRMeetingUnavailable(remoteASRProvider))
            }
            return .start(.remote)
        }
    }

    private static func resolveLocalMeetingStart(
        selectedMLXRepo: String?,
        activeMLXDownloadRepo: String?,
        isSelectedMLXModelDownloaded: Bool,
        mlxModelState: MLXModelManager.ModelState,
        selectedWhisperModelID: String?,
        activeWhisperDownloadModelID: String?,
        isSelectedWhisperModelDownloaded: Bool,
        whisperModelState: WhisperKitModelManager.ModelState
    ) -> MeetingStartDecision {
        switch RecordingStartPlanner.resolve(
            selectedEngine: .mlxAudio,
            selectedMLXRepo: selectedMLXRepo,
            activeMLXDownloadRepo: activeMLXDownloadRepo,
            isSelectedMLXModelDownloaded: isSelectedMLXModelDownloaded,
            mlxModelState: mlxModelState,
            selectedWhisperModelID: selectedWhisperModelID,
            activeWhisperDownloadModelID: activeWhisperDownloadModelID,
            isSelectedWhisperModelDownloaded: isSelectedWhisperModelDownloaded,
            whisperModelState: whisperModelState
        ) {
        case .start:
            return .start(.mlxAudio)
        case .blocked(let reason):
            return .blocked(.recording(reason))
        }
    }
}

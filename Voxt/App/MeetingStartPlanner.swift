import Foundation

enum MeetingStartBlockReason: Equatable {
    case dictationUnsupported
    case recording(RecordingStartBlockReason)
    case remoteASRUnavailable
    case remoteASRMeetingUnavailable(RemoteASRProvider)

    var userMessage: String {
        switch self {
        case .dictationUnsupported:
            return String(localized: "Meeting Notes currently supports Whisper, MLX Audio, and Remote ASR. Direct Dictation is not available for meetings.")
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
        mlxModelState: MLXModelManager.ModelState,
        whisperModelState: WhisperKitModelManager.ModelState,
        remoteASRProvider: RemoteASRProvider,
        remoteASRConfiguration: RemoteProviderConfiguration
    ) -> MeetingStartDecision {
        switch selectedEngine {
        case .dictation:
            return .blocked(.dictationUnsupported)
        case .mlxAudio:
            switch RecordingStartPlanner.resolve(
                selectedEngine: .mlxAudio,
                mlxModelState: mlxModelState,
                whisperModelState: whisperModelState
            ) {
            case .start:
                return .start(.mlxAudio)
            case .blocked(let reason):
                return .blocked(.recording(reason))
            }
        case .whisperKit:
            switch RecordingStartPlanner.resolve(
                selectedEngine: .whisperKit,
                mlxModelState: mlxModelState,
                whisperModelState: whisperModelState
            ) {
            case .start:
                return .start(.whisperKit)
            case .blocked(let reason):
                return .blocked(.recording(reason))
            }
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
}

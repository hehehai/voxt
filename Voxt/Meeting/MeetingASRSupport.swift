import Foundation

enum MeetingASRResolvedMode: Equatable, Sendable {
    case chunk(profile: MeetingChunkingProfile)
    case liveRemote(provider: RemoteASRProvider)

    var chunkingProfile: MeetingChunkingProfile {
        switch self {
        case .chunk(let profile):
            return profile
        case .liveRemote:
            return .realtime
        }
    }

    var usesLiveSessions: Bool {
        switch self {
        case .liveRemote:
            return true
        case .chunk:
            return false
        }
    }
}

struct MeetingASREngineContext: Equatable {
    let engine: TranscriptionEngine
    let historyModelDescription: String
    let resolvedMode: MeetingASRResolvedMode
    let needsModelInitialization: Bool

    var chunkingProfile: MeetingChunkingProfile {
        resolvedMode.chunkingProfile
    }
}

enum MeetingASRSupport {
    static func resolveContext(
        transcriptionEngine: TranscriptionEngine,
        whisperModelState: WhisperKitModelManager.ModelState,
        whisperCurrentModelID: String,
        whisperRealtimeEnabled: Bool,
        whisperIsCurrentModelLoaded: Bool,
        whisperDisplayTitle: (String) -> String,
        mlxModelState: MLXModelManager.ModelState,
        mlxCurrentModelRepo: String,
        mlxIsCurrentModelLoaded: Bool,
        mlxDisplayTitle: (String) -> String,
        remoteProvider: RemoteASRProvider,
        remoteConfiguration: RemoteProviderConfiguration
    ) -> MeetingASREngineContext {
        switch transcriptionEngine {
        case .whisperKit:
            return MeetingASREngineContext(
                engine: .whisperKit,
                historyModelDescription: "\(whisperDisplayTitle(whisperCurrentModelID)) (\(whisperCurrentModelID))",
                resolvedMode: .chunk(profile: whisperRealtimeEnabled ? .realtime : .quality),
                needsModelInitialization: !whisperIsCurrentModelLoaded && modelStateNeedsInitialization(whisperModelState)
            )
        case .mlxAudio:
            return MeetingASREngineContext(
                engine: .mlxAudio,
                historyModelDescription: "\(mlxDisplayTitle(mlxCurrentModelRepo)) (\(mlxCurrentModelRepo))",
                resolvedMode: .chunk(
                    profile: MLXModelManager.isRealtimeCapableModelRepo(mlxCurrentModelRepo) ? .realtime : .quality
                ),
                needsModelInitialization: !mlxIsCurrentModelLoaded && modelStateNeedsInitialization(mlxModelState)
            )
        case .remote:
            let meetingConfiguration = RemoteASRMeetingConfiguration.resolvedMeetingConfiguration(
                provider: remoteProvider,
                configuration: remoteConfiguration
            )
            let model = meetingConfiguration.hasUsableModel ? meetingConfiguration.model : remoteProvider.suggestedModel
            let resolvedMode = resolveRemoteMode(
                provider: remoteProvider,
                configuration: meetingConfiguration
            )
            return MeetingASREngineContext(
                engine: .remote,
                historyModelDescription: "\(remoteProvider.title) (\(model))",
                resolvedMode: resolvedMode,
                needsModelInitialization: false
            )
        case .dictation:
            return MeetingASREngineContext(
                engine: .dictation,
                historyModelDescription: "Direct Dictation",
                resolvedMode: .chunk(profile: .quality),
                needsModelInitialization: false
            )
        }
    }

    static func resolveRemoteMode(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> MeetingASRResolvedMode {
        switch provider {
        case .doubaoASR:
            return .chunk(profile: .quality)
        case .aliyunBailianASR:
            return .chunk(profile: .quality)
        case .openAIWhisper:
            return .chunk(profile: configuration.openAIChunkPseudoRealtimeEnabled ? .realtime : .quality)
        case .glmASR:
            return .chunk(profile: .quality)
        }
    }

    private static func modelStateNeedsInitialization<T>(_ state: T) -> Bool where T: Equatable {
        switch state {
        case let state as WhisperKitModelManager.ModelState:
            switch state {
            case .downloaded, .loading, .ready:
                return true
            case .notDownloaded, .downloading, .error:
                return false
            }
        case let state as MLXModelManager.ModelState:
            switch state {
            case .downloaded, .loading, .ready:
                return true
            case .notDownloaded, .downloading, .error:
                return false
            }
        default:
            return false
        }
    }
}

enum RemoteASRRealtimeSupport {
    static func usesRealtimeMeetingProfile(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> Bool {
        switch provider {
        case .openAIWhisper:
            return configuration.openAIChunkPseudoRealtimeEnabled
        case .doubaoASR:
            return false
        case .glmASR:
            return false
        case .aliyunBailianASR:
            return false
        }
    }

    static func isAliyunRealtimeModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.hasPrefix("qwen3-asr-flash-realtime")
            || normalized.hasPrefix("fun-asr")
            || normalized.hasPrefix("paraformer-realtime")
    }
}

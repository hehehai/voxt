// MeetingASRSupport.swift
// Provides Meeting ASRSupport for meeting transcript processing.

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
    var sherpaModelID: SherpaOnnxModelID? = nil

    var chunkingProfile: MeetingChunkingProfile {
        resolvedMode.chunkingProfile
    }

    func resolvingChunkingMode(_ mode: MeetingChunkingMode) -> MeetingASREngineContext {
        guard case .chunk(let automaticProfile) = resolvedMode else {
            return self
        }
        return MeetingASREngineContext(
            engine: engine,
            historyModelDescription: historyModelDescription,
            resolvedMode: .chunk(profile: mode.resolvedProfile(automaticProfile: automaticProfile)),
            needsModelInitialization: needsModelInitialization,
            sherpaModelID: sherpaModelID
        )
    }
}

enum MeetingASRSupport {
    static func resolveContext(
        transcriptionEngine: TranscriptionEngine,
        mlxModelState: MLXModelManager.ModelState,
        mlxCurrentModelRepo: String,
        mlxIsCurrentModelLoaded: Bool,
        mlxDisplayTitle: (String) -> String,
        sherpaModelID: SherpaOnnxModelID = SherpaOnnxModelCatalog.defaultModelID,
        sherpaDisplayTitle: (SherpaOnnxModelID) -> String = SherpaOnnxModelCatalog.displayTitle(for:),
        remoteProvider: RemoteASRProvider,
        remoteConfiguration: RemoteProviderConfiguration
    ) -> MeetingASREngineContext {
        switch transcriptionEngine {
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
            let resolvedMode = resolveRemoteMode(
                provider: remoteProvider,
                configuration: remoteConfiguration
            )
            let modelConfiguration = resolvedMode.usesLiveSessions
                ? remoteConfiguration
                : RemoteASRMeetingConfiguration.resolvedMeetingConfiguration(
                    provider: remoteProvider,
                    configuration: remoteConfiguration
                )
            let model = modelConfiguration.hasUsableModel ? modelConfiguration.model : remoteProvider.suggestedModel
            return MeetingASREngineContext(
                engine: .remote,
                historyModelDescription: "\(remoteProvider.title) (\(model))",
                resolvedMode: resolvedMode,
                needsModelInitialization: false
            )
        case .sherpaOnnx:
            return MeetingASREngineContext(
                engine: .sherpaOnnx,
                historyModelDescription: "\(sherpaDisplayTitle(sherpaModelID)) (\(sherpaModelID.rawValue))",
                resolvedMode: .chunk(profile: .quality),
                needsModelInitialization: false,
                sherpaModelID: sherpaModelID
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
        if RemoteASRRealtimeSupport.usesRealtimeMeetingProfile(
            provider: provider,
            configuration: configuration
        ) {
            return .liveRemote(provider: provider)
        }

        switch provider {
        case .doubaoASR:
            return .chunk(profile: .quality)
        case .aliyunBailianASR:
            return .chunk(profile: .quality)
        case .openAIWhisper:
            return .chunk(profile: configuration.openAIChunkPseudoRealtimeEnabled ? .realtime : .quality)
        case .glmASR, .stepFunASR:
            return .chunk(profile: .quality)
        }
    }

    private static func modelStateNeedsInitialization(_ state: MLXModelManager.ModelState) -> Bool {
        switch state {
        case .downloaded, .loading, .ready:
            return true
        case .notDownloaded, .downloading, .paused, .error:
            return false
        }
    }
}

extension RemoteASRRealtimeSupport {
    static func usesRealtimeMeetingProfile(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> Bool {
        switch provider {
        case .openAIWhisper:
            return false
        case .doubaoASR:
            return true
        case .glmASR:
            return false
        case .aliyunBailianASR:
            return isAliyunRealtimeModel(configuration.model)
        case .stepFunASR:
            return false
        }
    }
}

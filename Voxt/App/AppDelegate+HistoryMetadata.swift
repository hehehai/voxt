import Foundation
import AppKit

struct VoxtHistoryMetadata {
    let transcriptionModel: String
    let enhancementModel: String
    let remoteASRProvider: String?
    let remoteASRModel: String?
    let remoteASREndpoint: String?
    let remoteLLMProvider: String?
    let remoteLLMModel: String?
    let remoteLLMEndpoint: String?
    let focusedAppName: String?
}

extension AppDelegate {
    func currentHistoryMetadata() -> VoxtHistoryMetadata {
        let transcriptionModel: String
        switch transcriptionEngine {
        case .dictation:
            transcriptionModel = "Apple Speech Recognition"
        case .mlxAudio:
            let repo = mlxModelManager.currentModelRepo
            transcriptionModel = "\(mlxModelManager.displayTitle(for: repo)) (\(repo))"
        case .remote:
            let provider = remoteASRSelectedProvider
            if let config = remoteASRConfigurations[provider.rawValue], config.hasUsableModel {
                transcriptionModel = "\(provider.title) (\(config.model))"
            } else {
                transcriptionModel = provider.title
            }
        }

        let enhancementModel: String
        switch enhancementMode {
        case .off:
            enhancementModel = "None"
        case .appleIntelligence:
            enhancementModel = "Apple Intelligence (Foundation Models)"
        case .customLLM:
            let repo = customLLMManager.currentModelRepo
            enhancementModel = "\(customLLMManager.displayTitle(for: repo)) (\(repo))"
        case .remoteLLM:
            let provider = remoteLLMSelectedProvider
            if let config = remoteLLMConfigurations[provider.rawValue], config.hasUsableModel {
                enhancementModel = "\(provider.title) (\(config.model))"
            } else {
                enhancementModel = provider.title
            }
        }

        let remoteASR = currentRemoteASRHistoryMetadata()
        let remoteLLM = currentRemoteLLMHistoryMetadata()

        return VoxtHistoryMetadata(
            transcriptionModel: transcriptionModel,
            enhancementModel: enhancementModel,
            remoteASRProvider: remoteASR.provider,
            remoteASRModel: remoteASR.model,
            remoteASREndpoint: remoteASR.endpoint,
            remoteLLMProvider: remoteLLM.provider,
            remoteLLMModel: remoteLLM.model,
            remoteLLMEndpoint: remoteLLM.endpoint,
            focusedAppName: lastEnhancementPromptContext?.focusedAppName ?? NSWorkspace.shared.frontmostApplication?.localizedName
        )
    }

    func currentRemoteASRHistoryMetadata() -> (provider: String?, model: String?, endpoint: String?) {
        guard transcriptionEngine == .remote else {
            return (nil, nil, nil)
        }
        let provider = remoteASRSelectedProvider
        let config = remoteASRConfigurations[provider.rawValue]
        let model = config?.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? config?.model : nil
        return (provider.title, model, historyDisplayEndpoint(config?.endpoint))
    }

    func currentRemoteLLMHistoryMetadata() -> (provider: String?, model: String?, endpoint: String?) {
        guard enhancementMode == .remoteLLM else {
            return (nil, nil, nil)
        }
        let provider = remoteLLMSelectedProvider
        let config = remoteLLMConfigurations[provider.rawValue]
        let model = config?.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? config?.model : nil
        return (provider.title, model, historyDisplayEndpoint(config?.endpoint))
    }
}

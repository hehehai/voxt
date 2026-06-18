// ModelSettingsSupport.swift
// Provides Model Settings Support for model settings.

import Foundation

enum LocalASRConfigurationTarget: Equatable, Identifiable {
    case mlx(repo: String)
    case whisper(modelID: String)

    var id: String {
        switch self {
        case .mlx(let repo):
            return "mlx:\(repo)"
        case .whisper(let modelID):
            return "whisper:\(modelID)"
        }
    }
}

enum LocalModelRemovalTarget: Equatable, Identifiable {
    case mlx(repo: String)
    case whisper(modelID: String)
    case customLLM(repo: String)
    case ggufTranslation(modelID: GGUFTranslationModelID)

    var id: String {
        switch self {
        case .mlx(let repo):
            return "mlx:\(MLXModelManager.canonicalModelRepo(repo))"
        case .whisper(let modelID):
            return "whisper:\(WhisperKitModelManager.canonicalModelID(modelID))"
        case .customLLM(let repo):
            return "custom-llm:\(CustomLLMModelManager.canonicalModelRepo(repo))"
        case .ggufTranslation(let modelID):
            return "gguf-translation:\(modelID.rawValue)"
        }
    }
}

struct ModelDownloadEndpointCheckResult: Equatable {
    let isReachable: Bool
    let latencyText: String
    let throughputText: String
    let detailText: String
}

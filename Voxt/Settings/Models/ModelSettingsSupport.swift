// ModelSettingsSupport.swift
// Provides Model Settings Support for model settings.

import Foundation

enum LocalASRConfigurationTarget: Equatable, Identifiable {
    case mlx(repo: String)

    var id: String {
        switch self {
        case .mlx(let repo):
            return "mlx:\(repo)"
        }
    }
}

enum LocalModelRemovalTarget: Equatable, Identifiable {
    case mlx(repo: String)
    case customLLM(repo: String)
    case ggufTranslation(modelID: GGUFTranslationModelID)

    var id: String {
        switch self {
        case .mlx(let repo):
            return "mlx:\(MLXModelManager.canonicalModelRepo(repo))"
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

// ModelSettingsSupport.swift
// Provides Model Settings Support for model settings.

import Foundation

enum LocalASRConfigurationTarget: Equatable, Identifiable {
    case mlx(repo: String)
    case sherpaOnnx(modelID: SherpaOnnxModelID)

    var id: String {
        switch self {
        case .mlx(let repo):
            return "mlx:\(repo)"
        case .sherpaOnnx(let modelID):
            return "sherpa:\(modelID.rawValue)"
        }
    }
}

enum LocalModelRemovalTarget: Equatable, Identifiable {
    case mlx(repo: String)
    case sherpaOnnx(modelID: SherpaOnnxModelID)
    case customLLM(repo: String)
    case ggufTranslation(modelID: GGUFTranslationModelID)

    var id: String {
        switch self {
        case .mlx(let repo):
            return "mlx:\(MLXModelManager.canonicalModelRepo(repo))"
        case .sherpaOnnx(let modelID):
            return "sherpa:\(modelID.rawValue)"
        case .customLLM(let repo):
            return "custom-llm:\(CustomLLMModelManager.canonicalModelRepo(repo))"
        case .ggufTranslation(let modelID):
            return "gguf-translation:\(modelID.rawValue)"
        }
    }
}

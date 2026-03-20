import SwiftUI

extension ModelSettingsView {
    var translationProviderOptions: [ModelSettingsProviderOption] {
        TranslationModelProvider.allCases.map {
            ModelSettingsProviderOption(id: $0.rawValue, titleKey: $0.titleKey)
        }
    }

    var rewriteProviderOptions: [ModelSettingsProviderOption] {
        RewriteModelProvider.allCases.map {
            ModelSettingsProviderOption(id: $0.rawValue, titleKey: $0.titleKey)
        }
    }

    var installedCustomLLMOptions: [TranslationModelOption] {
        CustomLLMModelManager.availableModels.compactMap { model in
            guard customLLMManager.isModelDownloaded(repo: model.id) else {
                return nil
            }
            return TranslationModelOption(id: model.id, title: model.title)
        }
    }

    var configuredRemoteLLMOptions: [TranslationModelOption] {
        RemoteLLMProvider.allCases.compactMap { provider in
            guard let config = remoteLLMConfigurations[provider.rawValue] else {
                return nil
            }
            guard config.hasUsableModel else {
                return nil
            }
            return TranslationModelOption(
                id: provider.rawValue,
                title: "\(provider.title) · \(config.model)"
            )
        }
    }

    var translationModelOptions: [TranslationModelOption] {
        switch selectedTranslationModelProvider {
        case .remoteLLM:
            return configuredRemoteLLMOptions
        case .customLLM:
            return installedCustomLLMOptions
        }
    }

    var rewriteModelOptions: [TranslationModelOption] {
        switch selectedRewriteModelProvider {
        case .remoteLLM:
            return configuredRemoteLLMOptions
        case .customLLM:
            return installedCustomLLMOptions
        }
    }

    var translationModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedTranslationSelection },
            set: { newValue in
                switch selectedTranslationModelProvider {
                case .remoteLLM:
                    translationRemoteLLMProviderRaw = newValue
                case .customLLM:
                    translationCustomLLMRepo = newValue
                }
            }
        )
    }

    var resolvedTranslationSelection: String {
        let options = translationModelOptions
        guard !options.isEmpty else {
            return currentTranslationSelectionRaw
        }

        if options.contains(where: { $0.id == currentTranslationSelectionRaw }) {
            return currentTranslationSelectionRaw
        }
        return options[0].id
    }

    var rewriteModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedRewriteSelection },
            set: { newValue in
                switch selectedRewriteModelProvider {
                case .remoteLLM:
                    rewriteRemoteLLMProviderRaw = newValue
                case .customLLM:
                    rewriteCustomLLMRepo = newValue
                }
            }
        )
    }

    var resolvedRewriteSelection: String {
        let options = rewriteModelOptions
        guard !options.isEmpty else {
            return currentRewriteSelectionRaw
        }

        if options.contains(where: { $0.id == currentRewriteSelectionRaw }) {
            return currentRewriteSelectionRaw
        }
        return options[0].id
    }

    var currentTranslationSelectionRaw: String {
        switch selectedTranslationModelProvider {
        case .remoteLLM:
            return translationRemoteLLMProviderRaw
        case .customLLM:
            return translationCustomLLMRepo
        }
    }

    var currentRewriteSelectionRaw: String {
        switch selectedRewriteModelProvider {
        case .remoteLLM:
            return rewriteRemoteLLMProviderRaw
        case .customLLM:
            return rewriteCustomLLMRepo
        }
    }

    var translationModelLabelText: String {
        selectedTranslationModelProvider == .remoteLLM ? "Remote LLM Model" : "Custom LLM Model"
    }

    var translationModelEmptyStateText: String {
        selectedTranslationModelProvider == .remoteLLM
            ? "No configured remote LLM model yet. Configure a provider above."
            : "No installed custom LLM model yet. Install one in the table above."
    }

    var rewriteModelLabelText: String {
        selectedRewriteModelProvider == .remoteLLM ? "Remote LLM Model" : "Custom LLM Model"
    }

    var rewriteModelEmptyStateText: String {
        selectedRewriteModelProvider == .remoteLLM
            ? "No configured remote LLM model yet. Configure a provider above."
            : "No installed custom LLM model yet. Install one in the table above."
    }

    func ensureTranslationModelSelectionConsistency() {
        switch selectedTranslationModelProvider {
        case .remoteLLM:
            let options = configuredRemoteLLMOptions
            guard let first = options.first else {
                translationRemoteLLMProviderRaw = ""
                return
            }
            if !options.contains(where: { $0.id == translationRemoteLLMProviderRaw }) {
                translationRemoteLLMProviderRaw = first.id
            }
        case .customLLM:
            let options = installedCustomLLMOptions
            if let first = options.first {
                if !options.contains(where: { $0.id == translationCustomLLMRepo }) {
                    translationCustomLLMRepo = first.id
                }
            } else {
                translationCustomLLMRepo = customLLMRepo
            }
        }
    }

    func ensureRewriteModelSelectionConsistency() {
        switch selectedRewriteModelProvider {
        case .remoteLLM:
            let options = configuredRemoteLLMOptions
            guard let first = options.first else {
                rewriteRemoteLLMProviderRaw = ""
                return
            }
            if !options.contains(where: { $0.id == rewriteRemoteLLMProviderRaw }) {
                rewriteRemoteLLMProviderRaw = first.id
            }
        case .customLLM:
            let options = installedCustomLLMOptions
            if let first = options.first {
                if !options.contains(where: { $0.id == rewriteCustomLLMRepo }) {
                    rewriteCustomLLMRepo = first.id
                }
            } else {
                rewriteCustomLLMRepo = customLLMRepo
            }
        }
    }
}

struct TranslationModelOption: Identifiable, Hashable {
    let id: String
    let title: String
}

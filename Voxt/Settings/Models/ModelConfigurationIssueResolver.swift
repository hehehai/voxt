// ModelConfigurationIssueResolver.swift
// Provides model setup issue detection for settings screens.

import Foundation

struct ModelConfigurationIssue: Identifiable, Hashable {
    enum Scope: Hashable {
        case remoteASRProvider(RemoteASRProvider)
        case remoteLLMProvider(RemoteLLMProvider)
        case mlxModel(String)
        case sherpaOnnxModel(SherpaOnnxModelID)
        case customLLMModel(String)
        case translationRemoteLLM(RemoteLLMProvider)
        case rewriteRemoteLLM(RemoteLLMProvider)
        case translationCustomLLM(String)
        case rewriteCustomLLM(String)
    }

    let scope: Scope
    let message: String

    var id: String {
        switch scope {
        case .remoteASRProvider(let provider):
            return "asr:\(provider.rawValue)"
        case .remoteLLMProvider(let provider):
            return "llm:\(provider.rawValue)"
        case .mlxModel(let repo):
            return "mlx:\(repo)"
        case .sherpaOnnxModel(let modelID):
            return "sherpa:\(modelID.rawValue)"
        case .customLLMModel(let repo):
            return "custom:\(repo)"
        case .translationRemoteLLM(let provider):
            return "translation-llm:\(provider.rawValue)"
        case .rewriteRemoteLLM(let provider):
            return "rewrite-llm:\(provider.rawValue)"
        case .translationCustomLLM(let repo):
            return "translation-custom:\(repo)"
        case .rewriteCustomLLM(let repo):
            return "rewrite-custom:\(repo)"
        }
    }
}

enum ModelConfigurationIssueResolver {
    static func missingIssues(
        defaults: UserDefaults = .standard,
        mlxModelManager: MLXModelManager,
        sherpaOnnxModelManager: SherpaOnnxModelManager? = nil,
        customLLMManager: CustomLLMModelManager
    ) -> [ModelConfigurationIssue] {
        var issues: [ModelConfigurationIssue] = []

        let featureSettings = FeatureSettingsStore.load(defaults: defaults)
        let remoteASR = RemoteModelConfigurationStore.loadConfigurations(
            from: defaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? "",
            sensitiveValueLoading: .metadataOnly
        )
        let remoteLLM = RemoteModelConfigurationStore.loadConfigurations(
            from: defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? "",
            sensitiveValueLoading: .metadataOnly
        )

        appendASRIssues(
            for: featureSettings.transcription.asrSelectionID,
            issues: &issues,
            remoteASR: remoteASR,
            mlxModelManager: mlxModelManager,
            sherpaOnnxModelManager: sherpaOnnxModelManager
        )
        if featureSettings.transcription.llmEnabled {
            appendTextModelIssues(
                for: featureSettings.transcription.llmSelectionID,
                issues: &issues,
                remoteLLM: remoteLLM,
                customLLMManager: customLLMManager
            )
        }

        appendASRIssues(
            for: featureSettings.translation.asrSelectionID,
            issues: &issues,
            remoteASR: remoteASR,
            mlxModelManager: mlxModelManager,
            sherpaOnnxModelManager: sherpaOnnxModelManager
        )
        appendTranslationModelIssues(
            for: featureSettings.translation,
            issues: &issues,
            remoteLLM: remoteLLM,
            customLLMManager: customLLMManager
        )

        appendASRIssues(
            for: featureSettings.rewrite.asrSelectionID,
            issues: &issues,
            remoteASR: remoteASR,
            mlxModelManager: mlxModelManager,
            sherpaOnnxModelManager: sherpaOnnxModelManager
        )
        appendTextModelIssues(
            for: featureSettings.rewrite.llmSelectionID,
            issues: &issues,
            remoteLLM: remoteLLM,
            customLLMManager: customLLMManager
        )

        return Array(Set(issues)).sorted { $0.id < $1.id }
    }

    private static func appendASRIssues(
        for selectionID: FeatureModelSelectionID,
        issues: inout [ModelConfigurationIssue],
        remoteASR: [String: RemoteProviderConfiguration],
        mlxModelManager: MLXModelManager,
        sherpaOnnxModelManager: SherpaOnnxModelManager?
    ) {
        switch selectionID.asrSelection {
        case .dictation, .none:
            return
        case .mlx(let repo):
            let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
            if !mlxModelManager.isModelDownloaded(repo: canonicalRepo) {
                issues.append(.init(scope: .mlxModel(canonicalRepo), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        case .sherpaOnnx(let modelID):
            if let sherpaOnnxModelManager, !sherpaOnnxModelManager.isModelDownloaded(id: modelID) {
                issues.append(.init(scope: .sherpaOnnxModel(modelID), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        case .remote(let provider):
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: remoteASR)
            if !configuration.isConfigured {
                issues.append(.init(scope: .remoteASRProvider(provider), message: AppLocalization.localizedString("Configuration required.")))
            }
        }
    }

    private static func appendTextModelIssues(
        for selectionID: FeatureModelSelectionID,
        issues: inout [ModelConfigurationIssue],
        remoteLLM: [String: RemoteProviderConfiguration],
        customLLMManager: CustomLLMModelManager
    ) {
        switch selectionID.textSelection {
        case .appleIntelligence, .none:
            return
        case .localLLM(let repo):
            if !customLLMManager.isModelDownloaded(repo: repo) {
                issues.append(.init(scope: .customLLMModel(repo), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        case .remoteLLM(let provider):
            if !RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                provider: provider,
                stored: remoteLLM
            ) {
                issues.append(.init(scope: .remoteLLMProvider(provider), message: AppLocalization.localizedString("Configuration required.")))
            }
        }
    }

    private static func appendTranslationModelIssues(
        for settings: TranslationFeatureSettings,
        issues: inout [ModelConfigurationIssue],
        remoteLLM: [String: RemoteProviderConfiguration],
        customLLMManager: CustomLLMModelManager
    ) {
        switch settings.modelSelectionID.translationSelection {
        case .none:
            return
        case .localLLM(let repo):
            if !customLLMManager.isModelDownloaded(repo: repo) {
                issues.append(.init(scope: .translationCustomLLM(repo), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        case .localGGUF:
            return
        case .remoteLLM(let provider):
            if !RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                provider: provider,
                stored: remoteLLM
            ) {
                issues.append(.init(scope: .translationRemoteLLM(provider), message: AppLocalization.localizedString("Configuration required.")))
            }
        }
    }
}

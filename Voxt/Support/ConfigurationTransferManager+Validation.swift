import Foundation

extension ConfigurationTransferManager {
    static func appendASRIssues(
        for selectionID: FeatureModelSelectionID,
        requiresMeetingConfiguration: Bool = false,
        issues: inout [MissingConfigurationIssue],
        remoteASR: [String: RemoteProviderConfiguration],
        mlxModelManager: MLXModelManager,
        whisperModelManager: WhisperKitModelManager
    ) {
        switch selectionID.asrSelection {
        case .dictation, .none:
            return
        case .mlx(let repo):
            let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
            if !mlxModelManager.isModelDownloaded(repo: canonicalRepo) {
                issues.append(.init(scope: .mlxModel(canonicalRepo), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        case .whisper(let modelID):
            let canonicalModelID = WhisperKitModelManager.canonicalModelID(modelID)
            if !whisperModelManager.isModelDownloaded(id: canonicalModelID) {
                issues.append(.init(scope: .whisperModel(canonicalModelID), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        case .remote(let provider):
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: remoteASR)
            if !configuration.isConfigured {
                issues.append(.init(scope: .remoteASRProvider(provider), message: AppLocalization.localizedString("Configuration required.")))
            } else if requiresMeetingConfiguration,
                      RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(provider, configuration: configuration),
                      !RemoteASRMeetingConfiguration.hasValidMeetingModel(provider: provider, configuration: configuration) {
                issues.append(.init(scope: .remoteASRProvider(provider), message: AppLocalization.localizedString("Meeting ASR configuration required.")))
            }
        }
    }

    static func appendTextModelIssues(
        for selectionID: FeatureModelSelectionID,
        issues: inout [MissingConfigurationIssue],
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
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: provider, stored: remoteLLM)
            if !configuration.isConfigured || !configuration.hasUsableModel {
                issues.append(.init(scope: .remoteLLMProvider(provider), message: AppLocalization.localizedString("Configuration required.")))
            }
        }
    }

    static func appendTranslationModelIssues(
        for settings: TranslationFeatureSettings,
        issues: inout [MissingConfigurationIssue],
        remoteLLM: [String: RemoteProviderConfiguration],
        customLLMManager: CustomLLMModelManager
    ) {
        switch settings.modelSelectionID.translationSelection {
        case .whisperDirectTranslate, .none:
            return
        case .localLLM(let repo):
            if !customLLMManager.isModelDownloaded(repo: repo) {
                issues.append(.init(scope: .translationCustomLLM(repo), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        case .remoteLLM(let provider):
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: provider, stored: remoteLLM)
            if !configuration.isConfigured || !configuration.hasUsableModel {
                issues.append(.init(scope: .translationRemoteLLM(provider), message: AppLocalization.localizedString("Configuration required.")))
            }
        }
    }
}

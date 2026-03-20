import Foundation

extension ModelSettingsView {
    func handleOnAppear() {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(modelRepo)
        if canonicalRepo != modelRepo {
            modelRepo = canonicalRepo
        }
        mlxModelManager.updateModel(repo: canonicalRepo)
        mlxModelManager.prefetchAllModelSizes()

        if customLLMRepo.isEmpty {
            customLLMRepo = CustomLLMModelManager.defaultModelRepo
        }
        if !CustomLLMModelManager.isSupportedModelRepo(customLLMRepo) {
            customLLMRepo = CustomLLMModelManager.defaultModelRepo
        }
        if translationCustomLLMRepo.isEmpty {
            translationCustomLLMRepo = customLLMRepo
        }
        if !CustomLLMModelManager.isSupportedModelRepo(translationCustomLLMRepo) {
            translationCustomLLMRepo = customLLMRepo
        }
        if translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translationPrompt = AppPreferenceKey.defaultTranslationPrompt
        }
        if rewritePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rewritePrompt = AppPreferenceKey.defaultRewritePrompt
        }
        if !TranslationModelProvider.allCases.contains(where: { $0.rawValue == translationModelProviderRaw }) {
            translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
        }
        if !RewriteModelProvider.allCases.contains(where: { $0.rawValue == rewriteModelProviderRaw }) {
            rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
        }
        if rewriteCustomLLMRepo.isEmpty {
            rewriteCustomLLMRepo = customLLMRepo
        }
        if !CustomLLMModelManager.isSupportedModelRepo(rewriteCustomLLMRepo) {
            rewriteCustomLLMRepo = customLLMRepo
        }
        customLLMManager.updateModel(repo: customLLMRepo)
        customLLMManager.prefetchAllModelSizes()
        if !RemoteASRProvider.allCases.contains(where: { $0.rawValue == remoteASRSelectedProviderRaw }) {
            remoteASRSelectedProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
        }
        if !RemoteLLMProvider.allCases.contains(where: { $0.rawValue == remoteLLMSelectedProviderRaw }) {
            remoteLLMSelectedProviderRaw = RemoteLLMProvider.openAI.rawValue
        }
        ensureTranslationModelSelectionConsistency()
        ensureRewriteModelSelectionConsistency()
        updateMirrorSetting()
        refreshModelInstallStateIfNeeded()
    }
}

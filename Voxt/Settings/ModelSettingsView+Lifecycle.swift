import Foundation

extension ModelSettingsView {
    func handleOnAppear() {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(modelRepo)
        if canonicalRepo != modelRepo {
            modelRepo = canonicalRepo
        }
        mlxModelManager.updateModel(repo: canonicalRepo)
        let canonicalWhisperModelID = WhisperKitModelManager.canonicalModelID(whisperModelID)
        if canonicalWhisperModelID != whisperModelID {
            whisperModelID = canonicalWhisperModelID
        }
        whisperModelManager.updateModel(id: canonicalWhisperModelID)
        if UserDefaults.standard.object(forKey: AppPreferenceKey.whisperRealtimeEnabled) == nil {
            whisperRealtimeEnabled = true
        }
        if UserDefaults.standard.object(forKey: AppPreferenceKey.whisperKeepResidentLoaded) == nil {
            whisperKeepResidentLoaded = true
        }

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
        if !TranslationModelProvider.allCases.contains(where: { $0.rawValue == translationFallbackModelProviderRaw }) {
            translationFallbackModelProviderRaw = TranslationModelProvider.customLLM.rawValue
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
        if !RemoteASRProvider.allCases.contains(where: { $0.rawValue == remoteASRSelectedProviderRaw }) {
            remoteASRSelectedProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
        }
        if !RemoteLLMProvider.allCases.contains(where: { $0.rawValue == remoteLLMSelectedProviderRaw }) {
            remoteLLMSelectedProviderRaw = RemoteLLMProvider.openAI.rawValue
        }
        syncTranslationFallbackProvider()
        ensureTranslationModelSelectionConsistency()
        ensureRewriteModelSelectionConsistency()
        updateMirrorSetting()
        whisperModelManager.refreshResidencyPolicy()
        DispatchQueue.main.async {
            refreshModelInstallStateIfNeeded()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            mlxModelManager.prefetchAllModelSizes()
            whisperModelManager.prefetchAllModelSizes()
            customLLMManager.prefetchAllModelSizes()
        }
    }

    func syncTranslationFallbackProvider() {
        let currentProvider = TranslationModelProvider(rawValue: translationModelProviderRaw) ?? .customLLM
        let sanitizedFallback = TranslationProviderResolver.sanitizedFallbackProvider(
            TranslationModelProvider(rawValue: translationFallbackModelProviderRaw) ?? .customLLM
        )

        if currentProvider == .whisperKit {
            if translationFallbackModelProviderRaw != sanitizedFallback.rawValue {
                translationFallbackModelProviderRaw = sanitizedFallback.rawValue
            }
            return
        }

        if translationFallbackModelProviderRaw != currentProvider.rawValue {
            translationFallbackModelProviderRaw = currentProvider.rawValue
        }
    }
}

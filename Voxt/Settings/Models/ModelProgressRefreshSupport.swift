// ModelProgressRefreshSupport.swift
// Provides Model Progress Refresh Support for model settings.

import Foundation

enum ModelSettingsProgressRefreshSupport {
    static func shouldRefreshCatalogForLifecycleChange(
        isActive: Bool,
        isWindowVisible: Bool
    ) -> Bool {
        isActive && isWindowVisible
    }

    static func shouldRefreshCatalogForMetadataChange(
        isActive: Bool,
        isWindowVisible: Bool,
        shouldPollModelState: Bool
    ) -> Bool {
        isActive && isWindowVisible && shouldPollModelState
    }

    static func shouldPollModelState(
        mlxState: MLXModelManager.ModelState,
        mlxHasActiveDownloadingRepos: Bool,
        sherpaOnnxState: MLXModelManager.ModelState,
        sherpaOnnxStateByID: [SherpaOnnxModelID: MLXModelManager.ModelState],
        sherpaOnnxHasActiveDownloads: Bool,
        customLLMState: CustomLLMModelManager.ModelState,
        ggufStateByID: [GGUFTranslationModelID: GGUFTranslationModelManager.ModelState],
        ggufActiveDownloadModelID: GGUFTranslationModelID?
    ) -> Bool {
        if mlxHasActiveDownloadingRepos {
            return true
        }

        if isMLXStatePollingRequired(mlxState) {
            return true
        }

        if sherpaOnnxHasActiveDownloads {
            return true
        }

        if isMLXStatePollingRequired(sherpaOnnxState) {
            return true
        }

        if sherpaOnnxStateByID.values.contains(where: { isMLXStatePollingRequired($0) }) {
            return true
        }

        if isCustomLLMStatePollingRequired(customLLMState) {
            return true
        }

        if ggufActiveDownloadModelID != nil {
            return true
        }

        if ggufStateByID.values.contains(where: {
            if case .downloading = $0 { return true }
            return false
        }) {
            return true
        }

        return false
    }

    private static func isMLXStatePollingRequired(_ state: MLXModelManager.ModelState) -> Bool {
        switch state {
        case .downloading:
            return true
        default:
            return false
        }
    }

    private static func isCustomLLMStatePollingRequired(_ state: CustomLLMModelManager.ModelState) -> Bool {
        switch state {
        case .downloading:
            return true
        default:
            return false
        }
    }
}

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
        whisperState: WhisperKitModelManager.ModelState,
        whisperActiveDownload: WhisperKitModelManager.ActiveDownload?,
        customLLMState: CustomLLMModelManager.ModelState
    ) -> Bool {
        if mlxHasActiveDownloadingRepos {
            return true
        }

        if isMLXStatePollingRequired(mlxState) {
            return true
        }

        if isWhisperStatePollingRequired(whisperState) {
            return true
        }

        if let whisperActiveDownload, !whisperActiveDownload.isPaused {
            return true
        }

        if isCustomLLMStatePollingRequired(customLLMState) {
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

    private static func isWhisperStatePollingRequired(_ state: WhisperKitModelManager.ModelState) -> Bool {
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

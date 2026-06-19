// ModelDownloadBadgeSupport.swift
// Provides Model Download Badge Support for settings shell.

import Foundation

enum SettingsModelDownloadBadgeSupport {
    static func activeDownloadCount(
        mlxActiveDownloadRepos: Set<String>,
        customLLMState: CustomLLMModelManager.ModelState,
        ggufActiveDownloadModelID: GGUFTranslationModelID?
    ) -> Int {
        var count = mlxActiveDownloadRepos.count

        if case .downloading = customLLMState {
            count += 1
        }

        if ggufActiveDownloadModelID != nil {
            count += 1
        }

        return count
    }
}

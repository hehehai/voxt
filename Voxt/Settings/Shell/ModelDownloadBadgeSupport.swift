// ModelDownloadBadgeSupport.swift
// Provides Model Download Badge Support for settings shell.

import Foundation

enum SettingsModelDownloadBadgeSupport {
    static func activeDownloadCount(
        mlxActiveDownloadRepos: Set<String>,
        sherpaActiveDownloadModelIDs: Set<SherpaOnnxModelID> = [],
        customLLMActiveDownloadRepos: Set<String>,
        ggufActiveDownloadModelID: GGUFTranslationModelID?
    ) -> Int {
        var count = mlxActiveDownloadRepos.count
            + sherpaActiveDownloadModelIDs.count
            + customLLMActiveDownloadRepos.count

        if ggufActiveDownloadModelID != nil {
            count += 1
        }

        return count
    }
}

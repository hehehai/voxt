// ModelDownloadBadgeSupport.swift
// Provides Model Download Badge Support for settings shell.

import Foundation

enum SettingsModelDownloadBadgeSupport {
    static func activeDownloadCount(
        mlxActiveDownloadRepos: Set<String>,
        whisperActiveDownload: WhisperKitModelManager.ActiveDownload?,
        customLLMState: CustomLLMModelManager.ModelState
    ) -> Int {
        var count = mlxActiveDownloadRepos.count

        if let whisperActiveDownload, !whisperActiveDownload.isPaused {
            count += 1
        }

        if case .downloading = customLLMState {
            count += 1
        }

        return count
    }
}

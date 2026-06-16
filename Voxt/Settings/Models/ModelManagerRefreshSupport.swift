// ModelManagerRefreshSupport.swift
// Provides Model Manager Refresh Support for model settings.

import Foundation

enum ModelSettingsManagerActivityPhase: Equatable {
    case idle
    case downloading
    case paused
    case loading
    case downloaded
    case error
}

struct ModelSettingsDownloadLifecycleToken: Equatable {
    let mlxPhase: ModelSettingsManagerActivityPhase
    let mlxActiveDownloadRepos: [String]
    let whisperPhase: ModelSettingsManagerActivityPhase
    let whisperDownload: WhisperDownloadActivityDescriptor
    let customLLMPhase: ModelSettingsManagerActivityPhase
}

struct WhisperDownloadActivityDescriptor: Equatable {
    let modelID: String?
    let isPaused: Bool
}

enum ModelSettingsManagerRefreshSupport {
    static func phase(for state: MLXModelManager.ModelState) -> ModelSettingsManagerActivityPhase {
        switch state {
        case .notDownloaded:
            return .idle
        case .downloading:
            return .downloading
        case .paused:
            return .paused
        case .downloaded:
            return .downloaded
        case .loading:
            return .loading
        case .ready:
            return .downloaded
        case .error:
            return .error
        }
    }

    static func phase(for state: WhisperKitModelManager.ModelState) -> ModelSettingsManagerActivityPhase {
        switch state {
        case .notDownloaded:
            return .idle
        case .downloading:
            return .downloading
        case .paused:
            return .paused
        case .downloaded:
            return .downloaded
        case .loading:
            return .loading
        case .ready:
            return .downloaded
        case .error:
            return .error
        }
    }

    static func phase(for state: CustomLLMModelManager.ModelState) -> ModelSettingsManagerActivityPhase {
        switch state {
        case .notDownloaded:
            return .idle
        case .downloading:
            return .downloading
        case .paused:
            return .paused
        case .downloaded:
            return .downloaded
        case .error:
            return .error
        }
    }

    static func whisperDownloadDescriptor(
        for activeDownload: WhisperKitModelManager.ActiveDownload?
    ) -> WhisperDownloadActivityDescriptor {
        WhisperDownloadActivityDescriptor(
            modelID: activeDownload?.modelID,
            isPaused: activeDownload?.isPaused ?? false
        )
    }

    static func downloadLifecycleToken(
        mlxState: MLXModelManager.ModelState,
        mlxActiveDownloadRepos: Set<String>,
        whisperState: WhisperKitModelManager.ModelState,
        whisperActiveDownload: WhisperKitModelManager.ActiveDownload?,
        customLLMState: CustomLLMModelManager.ModelState
    ) -> ModelSettingsDownloadLifecycleToken {
        ModelSettingsDownloadLifecycleToken(
            mlxPhase: phase(for: mlxState),
            mlxActiveDownloadRepos: mlxActiveDownloadRepos.sorted(),
            whisperPhase: phase(for: whisperState),
            whisperDownload: whisperDownloadDescriptor(for: whisperActiveDownload),
            customLLMPhase: phase(for: customLLMState)
        )
    }
}

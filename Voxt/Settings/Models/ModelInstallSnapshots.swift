// ModelInstallSnapshots.swift
// Provides Model Install Snapshots for model settings.

import SwiftUI

@MainActor
extension ModelSettingsView {
    func isCancellationPending(for target: LocalModelInstallTarget) -> Bool {
        cancellingInstallTargets.contains(target)
    }

    func reconcileCancellingInstallTargets() {
        let retained = cancellingInstallTargets.filter(isCancellationStillPending(for:))
        if retained.count != cancellingInstallTargets.count {
            cancellingInstallTargets = Set(retained)
        }
    }

    func mlxInstallSnapshot(for repo: String) -> LocalModelInstallSnapshot {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
        let catalogSnapshot = mlxModelManager.catalogSnapshot(for: canonicalRepo)
        let isUninstalling = isUninstallingModel(canonicalRepo)
        let target = LocalModelInstallTarget.mlx(canonicalRepo)
        let state: LocalModelInstallState

        if isUninstalling {
            state = .uninstalling
        } else if isCancellationPending(for: target) {
            state = .cancelling
        } else if catalogSnapshot.isDownloading {
            state = .downloading
        } else if catalogSnapshot.isPaused {
            state = .paused
        } else if catalogSnapshot.isDownloaded {
            state = .installed
        } else {
            state = .installable(isEnabled: true)
        }

        return LocalModelInstallSnapshot(
            target: target,
            state: state,
            isInstalled: catalogSnapshot.isDownloaded,
            isCurrentSelection: isCurrentModel(canonicalRepo),
            statusText: mlxInstallStatusText(
                for: catalogSnapshot,
                isUninstalling: isUninstalling,
                isCancelling: isCancellationPending(for: target)
            ),
            badgeText: hasIssue(for: .mlxModel(canonicalRepo)) ? AppLocalization.localizedString("Needs Setup") : nil,
            downloadStatus: isCancellationPending(for: target) ? nil : ModelDownloadStatusSnapshot.fromMLXState(
                catalogSnapshot.state,
                pauseMessage: catalogSnapshot.pausedStatusMessage
            ),
            canOpenLocation: catalogSnapshot.isDownloaded && !isUninstalling && !isCancellationPending(for: target),
            canConfigure: !isUninstalling && !isCancellationPending(for: target),
            configureActionTitle: AppLocalization.localizedString("Settings")
        )
    }

    func whisperInstallSnapshot(for modelID: String) -> LocalModelInstallSnapshot {
        let canonicalModelID = WhisperKitModelManager.canonicalModelID(modelID)
        let isInstalled = whisperModelManager.isModelDownloaded(id: canonicalModelID)
        let isUninstalling = isUninstallingWhisperModel(canonicalModelID)
        let target = LocalModelInstallTarget.whisper(canonicalModelID)
        let activeDownload = whisperModelManager.activeDownload?.modelID == canonicalModelID
            ? whisperModelManager.activeDownload
            : nil
        let hasResumableDownload = activeDownload == nil && whisperModelManager.hasResumableDownload(id: canonicalModelID)
        let errorMessage = whisperModelManager.downloadErrorMessage(for: canonicalModelID)
            ?? {
                guard isCurrentWhisperModel(canonicalModelID),
                      case .error(let message) = whisperModelManager.state else {
                    return nil
                }
                return message
            }()

        let state: LocalModelInstallState
        if isUninstalling {
            state = .uninstalling
        } else if isCancellationPending(for: target) {
            state = .cancelling
        } else if let activeDownload {
            state = activeDownload.isPaused ? .paused : .downloading
        } else if hasResumableDownload {
            state = .paused
        } else if isInstalled {
            state = .installed
        } else {
            state = .installable(isEnabled: !isAnotherWhisperModelDownloading(canonicalModelID))
        }

        let pausedFallbackDownload = hasResumableDownload
            ? WhisperKitModelManager.ActiveDownload(
                modelID: canonicalModelID,
                isPaused: true,
                progress: 0,
                completed: 0,
                total: 0,
                currentFile: nil,
                currentFileCompleted: 0,
                currentFileTotal: 0,
                completedFiles: 0,
                totalFiles: 0
            )
            : nil
        let effectiveDownload = activeDownload ?? pausedFallbackDownload
        let pauseMessage = hasResumableDownload && activeDownload == nil
            ? AppLocalization.localizedString("Paused. Ready to continue.")
            : whisperModelManager.pausedStatusMessage(for: canonicalModelID)

        return LocalModelInstallSnapshot(
            target: target,
            state: state,
            isInstalled: isInstalled,
            isCurrentSelection: isCurrentWhisperModel(canonicalModelID),
            statusText: isUninstalling
                ? AppLocalization.localizedString("Uninstalling…")
                : isCancellationPending(for: target)
                ? AppLocalization.localizedString("Cancelling…")
                : ModelDownloadPresentationSupport.whisperStatusText(
                    activeDownload: effectiveDownload,
                    pauseMessage: pauseMessage,
                    errorMessage: errorMessage
                ),
            badgeText: hasIssue(for: .whisperModel(canonicalModelID)) ? AppLocalization.localizedString("Needs Setup") : nil,
            downloadStatus: isCancellationPending(for: target) ? nil : ModelDownloadStatusSnapshot.fromWhisperDownload(
                effectiveDownload,
                pauseMessage: pauseMessage
            ),
            canOpenLocation: isInstalled && !isUninstalling && !isCancellationPending(for: target),
            canConfigure: !isUninstalling && !isCancellationPending(for: target),
            configureActionTitle: AppLocalization.localizedString("Whisper Settings")
        )
    }

    func customLLMInstallSnapshot(for repo: String) -> LocalModelInstallSnapshot {
        let canonicalRepo = CustomLLMModelManager.canonicalModelRepo(repo)
        let isInstalled = customLLMManager.isModelDownloaded(repo: canonicalRepo)
        let isUninstalling = isUninstallingCustomLLM(canonicalRepo)
        let target = LocalModelInstallTarget.customLLM(canonicalRepo)
        let isDownloading = ModelDownloadStateRouting.isCustomLLMDownloading(
            repo: canonicalRepo,
            managerRepo: customLLMManager.currentModelRepo,
            state: customLLMManager.state
        )
        let isPaused = ModelDownloadStateRouting.isCustomLLMPaused(
            repo: canonicalRepo,
            managerRepo: customLLMManager.currentModelRepo,
            state: customLLMManager.state
        ) || customLLMManager.hasResumableDownload(repo: canonicalRepo)
        let isOperationTarget = ModelDownloadStateRouting.isCustomLLMOperationTarget(
            repo: canonicalRepo,
            managerRepo: customLLMManager.currentModelRepo
        )

        let state: LocalModelInstallState
        if isUninstalling {
            state = .uninstalling
        } else if isCancellationPending(for: target) {
            state = .cancelling
        } else if isDownloading {
            state = .downloading
        } else if isPaused {
            state = .paused
        } else if isInstalled {
            state = .installed
        } else {
            state = .installable(isEnabled: !isAnotherCustomLLMDownloading(canonicalRepo))
        }

        let resolvedDownloadStatus: ModelDownloadStatusSnapshot?
        if isOperationTarget {
            resolvedDownloadStatus = ModelDownloadStatusSnapshot.fromCustomLLMState(
                customLLMManager.state,
                pauseMessage: customLLMManager.pausedStatusMessage
            )
        } else if isPaused {
            resolvedDownloadStatus = ModelDownloadStatusSnapshot.fromCustomLLMState(
                .paused(
                    progress: 0,
                    completed: 0,
                    total: 0,
                    currentFile: nil,
                    completedFiles: 0,
                    totalFiles: 0
                ),
                pauseMessage: AppLocalization.localizedString("Paused. Ready to continue.")
            )
        } else {
            resolvedDownloadStatus = nil
        }

        return LocalModelInstallSnapshot(
            target: target,
            state: state,
            isInstalled: isInstalled,
            isCurrentSelection: isCurrentCustomLLM(canonicalRepo),
            statusText: customLLMInstallStatusText(
                isUninstalling: isUninstalling,
                isCancelling: isCancellationPending(for: target),
                isDownloading: isDownloading,
                isPaused: isPaused,
                isOperationTarget: isOperationTarget
            ),
            badgeText: customLLMBadgeText(for: canonicalRepo),
            downloadStatus: isCancellationPending(for: target) ? nil : resolvedDownloadStatus,
            canOpenLocation: isInstalled && !isUninstalling && !isCancellationPending(for: target),
            canConfigure: isInstalled && !isUninstalling && !isCancellationPending(for: target),
            configureActionTitle: AppLocalization.localizedString("Configure")
        )
    }

    func performInstallAction(_ target: LocalModelInstallTarget, kind: LocalModelInstallActionKind) {
        switch (target, kind) {
        case (.mlx(let repo), .use):
            useModel(repo)
        case (.mlx(let repo), .install), (.mlx(let repo), .resume):
            downloadModel(repo)
        case (.mlx(let repo), .pause):
            mlxModelManager.pauseDownload(repo: repo)
            refreshCatalogSnapshot()
        case (.mlx(let repo), .cancel):
            cancellingInstallTargets.insert(.mlx(repo))
            mlxModelManager.cancelDownload(repo: repo)
            refreshCatalogSnapshot()
        case (.mlx(let repo), .uninstall):
            requestDeleteModel(repo)
        case (.mlx(let repo), .openLocation):
            openMLXModelDirectory(repo)
        case (.mlx(let repo), .configure):
            activeLocalASRConfigurationTarget = .mlx(repo: repo)

        case (.whisper(let modelID), .use):
            useWhisperModel(modelID)
        case (.whisper(let modelID), .install), (.whisper(let modelID), .resume):
            downloadWhisperModel(modelID)
        case (.whisper, .pause):
            whisperModelManager.pauseDownload()
            refreshCatalogSnapshot()
        case (.whisper(let modelID), .cancel):
            cancellingInstallTargets.insert(.whisper(modelID))
            whisperModelManager.cancelDownload(id: modelID)
            refreshCatalogSnapshot()
        case (.whisper(let modelID), .uninstall):
            requestDeleteWhisperModel(modelID)
        case (.whisper(let modelID), .openLocation):
            openWhisperModelDirectory(modelID)
        case (.whisper(let modelID), .configure):
            activeLocalASRConfigurationTarget = .whisper(modelID: modelID)

        case (.customLLM(let repo), .use):
            useCustomLLM(repo)
        case (.customLLM(let repo), .install), (.customLLM(let repo), .resume):
            downloadCustomLLM(repo)
        case (.customLLM, .pause):
            customLLMManager.pauseDownload()
            refreshCatalogSnapshot()
        case (.customLLM(let repo), .cancel):
            cancellingInstallTargets.insert(.customLLM(repo))
            customLLMManager.cancelDownload(repo: repo)
            refreshCatalogSnapshot()
        case (.customLLM(let repo), .uninstall):
            requestDeleteCustomLLM(repo)
        case (.customLLM(let repo), .openLocation):
            openCustomLLMModelDirectory(repo)
        case (.customLLM(let repo), .configure):
            customLLMConfigurationRepo = repo
            isCustomLLMConfigurationPresented = true

        case (_, .inactive):
            break
        }
    }

    func modelTableRow(
        id: String,
        title: String,
        snapshot: LocalModelInstallSnapshot
    ) -> ModelTableRow {
        ModelTableRow(
            id: id,
            title: title,
            isActive: snapshot.isCurrentSelection,
            status: snapshot.statusText,
            badgeText: snapshot.badgeText,
            isTitleUnderlined: snapshot.canOpenLocation,
            onTapTitle: snapshot.canOpenLocation ? {
                performInstallAction(snapshot.target, kind: .openLocation)
            } : nil,
            actions: ModelSettingsInstallActionResolver.tableActions(
                for: snapshot,
                perform: performInstallAction(_:kind:)
            )
        )
    }

    private func mlxInstallStatusText(
        for snapshot: MLXModelManager.CatalogSnapshot,
        isUninstalling: Bool,
        isCancelling: Bool
    ) -> String {
        if isUninstalling {
            return AppLocalization.localizedString("Uninstalling…")
        }

        if isCancelling {
            return AppLocalization.localizedString("Cancelling…")
        }

        if case .downloading(_, let completed, let total, _, _, _) = snapshot.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .downloading(completed: completed, total: total)
            )
        }

        if case .paused(_, let completed, let total, _, _, _) = snapshot.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: completed,
                    total: total,
                    pauseMessage: snapshot.pausedStatusMessage
                )
            )
        }

        if snapshot.isPaused {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: 0,
                    total: 0,
                    pauseMessage: AppLocalization.localizedString("Paused. Ready to continue.")
                )
            )
        }

        if case .error(let message) = snapshot.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .idle,
                errorMessage: message
            )
        }

        return ""
    }

    private func customLLMInstallStatusText(
        isUninstalling: Bool,
        isCancelling: Bool,
        isDownloading: Bool,
        isPaused: Bool,
        isOperationTarget: Bool
    ) -> String {
        if isUninstalling {
            return AppLocalization.localizedString("Uninstalling…")
        }

        if isCancelling {
            return AppLocalization.localizedString("Cancelling…")
        }

        if isDownloading,
           case .downloading(_, let completed, let total, _, _, _) = customLLMManager.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .downloading(completed: completed, total: total)
            )
        }

        if isPaused,
           case .paused(_, let completed, let total, _, _, _) = customLLMManager.state,
           isOperationTarget {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: completed,
                    total: total,
                    pauseMessage: customLLMManager.pausedStatusMessage
                )
            )
        }

        if isPaused {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: 0,
                    total: 0,
                    pauseMessage: AppLocalization.localizedString("Paused. Ready to continue.")
                )
            )
        }

        if isOperationTarget, case .error(let message) = customLLMManager.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .idle,
                errorMessage: message
            )
        }
        return ""
    }

    private func isCancellationStillPending(for target: LocalModelInstallTarget) -> Bool {
        switch target {
        case .mlx(let repo):
            let snapshot = mlxModelManager.catalogSnapshot(for: repo)
            return snapshot.isDownloading || snapshot.isPaused
        case .whisper(let modelID):
            if whisperModelManager.activeDownload?.modelID == modelID {
                return true
            }
            return whisperModelManager.hasResumableDownload(id: modelID)
        case .customLLM(let repo):
            return ModelDownloadStateRouting.isCustomLLMDownloading(
                repo: repo,
                managerRepo: customLLMManager.currentModelRepo,
                state: customLLMManager.state
            ) || ModelDownloadStateRouting.isCustomLLMPaused(
                repo: repo,
                managerRepo: customLLMManager.currentModelRepo,
                state: customLLMManager.state
            ) || customLLMManager.hasResumableDownload(repo: repo)
        }
    }
}

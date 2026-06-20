// ModelDownloadPresentationSupport.swift
// Provides Model Download Presentation Support for model settings.

import SwiftUI

enum ModelDownloadPresentationSupport {
    static func downloadingActions(
        onPause: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> [ModelTableAction] {
        [
            ModelTableAction(title: localized("Pause"), handler: onPause),
            ModelTableAction(title: localized("Cancel"), role: .destructive, handler: onCancel)
        ]
    }

    static func pausedActions(
        onResume: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> [ModelTableAction] {
        [
            ModelTableAction(title: localized("Continue"), handler: onResume),
            ModelTableAction(title: localized("Cancel"), role: .destructive, handler: onCancel)
        ]
    }

    static func installedActions(
        isCurrent: Bool,
        onUse: @escaping () -> Void,
        onUninstall: @escaping () -> Void
    ) -> [ModelTableAction] {
        [
            ModelTableAction(
                title: localized(isCurrent ? "Using" : "Use"),
                isEnabled: !isCurrent,
                handler: onUse
            ),
            ModelTableAction(
                title: localized("Uninstall"),
                role: .destructive,
                handler: onUninstall
            )
        ]
    }

    static func installActions(
        isEnabled: Bool,
        onInstall: @escaping () -> Void
    ) -> [ModelTableAction] {
        [
            ModelTableAction(
                title: localized("Download"),
                isEnabled: isEnabled,
                handler: onInstall
            )
        ]
    }

    static func statusText(
        downloadState: DownloadState,
        errorMessage: String? = nil
    ) -> String {
        switch downloadState {
        case .idle:
            if let errorMessage, !errorMessage.isEmpty {
                return "Error: \(errorMessage)"
            }
            return ""
        case .downloading(let completed, let total):
            return AppLocalization.format(
                "Downloading %@",
                ModelDownloadProgressFormatter.byteProgressText(completed: completed, total: total)
            )
        case .paused(let completed, let total, let pauseMessage):
            let progressText = ModelDownloadProgressFormatter.byteProgressText(completed: completed, total: total)
            if let pauseMessage, !pauseMessage.isEmpty {
                return AppLocalization.format("%@ • %@", pauseMessage, progressText)
            }
            return AppLocalization.format("Paused %@", progressText)
        }
    }

    enum DownloadState {
        case idle
        case downloading(completed: Int64, total: Int64)
        case paused(completed: Int64, total: Int64, pauseMessage: String?)
    }

    private static func localized(_ key: String) -> String {
        AppLocalization.localizedString(key)
    }
}

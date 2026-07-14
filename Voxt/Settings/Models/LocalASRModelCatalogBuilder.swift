// LocalASRModelCatalogBuilder.swift
// Provides Local ASRModel Catalog Builder for model settings.

import SwiftUI

private func localizedModelCatalog(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

@MainActor
extension ModelCatalogBuilder {
    func dictationASREntry() -> ModelCatalogEntry {
        let decoration = catalogDecoration(
            base: [localizedModelCatalog("Local"), localizedModelCatalog("Built-in"), localizedModelCatalog("Fast")],
            installed: true,
            requiresConfiguration: false,
            configured: true,
            selectionID: .dictation
        )
        return ModelCatalogEntry(
            id: FeatureModelSelectionID.dictation.rawValue,
            title: localizedModelCatalog("Direct Dictation"),
            engine: localizedModelCatalog("System ASR"),
            sizeText: localizedModelCatalog("Built-in"),
            ratingText: "3.4",
            filterTags: decoration.filterTags,
            displayTags: decoration.displayTags,
            statusText: "",
            usageLocations: decoration.usageLocations,
            badgeText: nil,
            primaryAction: ModelTableAction(title: localizedModelCatalog("Settings")) {
                showASRHintTarget(.dictation)
            },
            secondaryActions: []
        )
    }

    func mlxASREntries() -> [ModelCatalogEntry] {
        mlxModelManager.displayModelsIncludingInstalled().map { model in
            let repo = MLXModelManager.canonicalModelRepo(model.id)
            let selectionID = FeatureModelSelectionID.mlx(repo)
            let installSnapshot = mlxInstallSnapshot(repo)
            let isAvailable = MLXModelManager.isAvailableModelRepo(repo)
            let decoration = catalogDecoration(
                base: [localizedModelCatalog("Local")] + mlxCatalogTags(for: repo),
                installed: installSnapshot.isInstalled,
                requiresConfiguration: false,
                configured: true,
                selectionID: selectionID
            )

            return ModelCatalogEntry(
                id: "mlx:\(repo)",
                title: mlxModelManager.displayTitle(for: repo),
                engine: MLXWhisperMigrationSupport.isWhisperRepo(repo)
                    ? localizedModelCatalog("Whisper (MLX)")
                    : localizedModelCatalog("MLX Audio"),
                sizeText: mlxASRSizeText(repo: repo, isInstalled: installSnapshot.isInstalled),
                ratingText: MLXModelManager.ratingText(for: repo),
                filterTags: decoration.filterTags,
                displayTags: decoration.displayTags,
                statusText: installSnapshot.statusText,
                usageLocations: decoration.usageLocations,
                badgeText: installSnapshot.badgeText ?? ModelCatalogBadgeSupport.recommendedBadgeText(forMLXRepo: repo),
                primaryAction: catalogPrimaryAction(installSnapshot),
                secondaryActions: localASRSecondaryActions(
                    for: installSnapshot,
                    isAvailable: isAvailable
                )
            )
        }
    }

    func sherpaOnnxASREntries() -> [ModelCatalogEntry] {
        return sherpaOnnxDisplayModelsIncludingFeatureSelections().map { model in
            let selectionID = FeatureModelSelectionID.sherpaOnnx(model.id)
            let installSnapshot = sherpaOnnxCatalogSnapshot(for: model.id)
            let decoration = catalogDecoration(
                base: model.tagKeys.map { localizedModelCatalog($0) },
                installed: installSnapshot.isInstalled,
                requiresConfiguration: false,
                configured: true,
                selectionID: selectionID
            )

            return ModelCatalogEntry(
                id: selectionID.rawValue,
                title: model.title,
                engine: localizedModelCatalog("Sherpa"),
                sizeText: sherpaOnnxASRSizeText(id: model.id, isInstalled: installSnapshot.isInstalled),
                ratingText: model.ratingText,
                filterTags: decoration.filterTags,
                displayTags: decoration.displayTags,
                statusText: sherpaOnnxASRStatusText(installSnapshot.statusText),
                usageLocations: decoration.usageLocations,
                badgeText: installSnapshot.badgeText,
                primaryAction: catalogPrimaryAction(installSnapshot),
                secondaryActions: catalogSecondaryActions(installSnapshot)
            )
        }
    }

    private func sherpaOnnxDisplayModelsIncludingFeatureSelections() -> [SherpaOnnxModelOption] {
        let selections = [
            featureSettings.transcription.asrSelectionID,
            featureSettings.translation.asrSelectionID,
            featureSettings.rewrite.asrSelectionID,
            featureSettings.meeting.asrSelectionID,
        ]
        let selectedModelIDs = Set(selections.compactMap { selectionID -> SherpaOnnxModelID? in
            guard case .sherpaOnnx(let modelID)? = selectionID.asrSelection else { return nil }
            return modelID
        })
        return sherpaOnnxModelManager.displayModelsIncludingInstalled(including: selectedModelIDs)
    }

    private func localASRSecondaryActions(
        for snapshot: LocalModelInstallSnapshot,
        isAvailable: Bool
    ) -> [ModelTableAction] {
        if isAvailable {
            return catalogSecondaryActions(snapshot)
        }

        switch snapshot.state {
        case .downloading, .paused:
            return catalogSecondaryActions(snapshot)
        case .installable, .cancelling, .installed, .uninstalling:
            return []
        }
    }

    private func mlxASRSizeText(repo: String, isInstalled: Bool) -> String {
        _ = isInstalled
        return mlxModelManager.remoteSizeText(repo: repo)
    }

    private func sherpaOnnxASRSizeText(id: SherpaOnnxModelID, isInstalled: Bool) -> String {
        _ = isInstalled
        return sherpaOnnxModelManager.remoteSizeText(id: id)
    }

    private func sherpaOnnxASRStatusText(_ statusText: String) -> String {
        let genericStatuses = Set([
            localizedModelCatalog("Installed"),
            localizedModelCatalog("Not installed")
        ])
        return genericStatuses.contains(statusText) ? "" : statusText
    }

    private func sherpaOnnxCatalogSnapshot(for modelID: SherpaOnnxModelID) -> LocalModelInstallSnapshot {
        if SherpaOnnxRuntimeSupport.isAvailable {
            return sherpaInstallSnapshot(modelID)
        }

        return LocalModelInstallSnapshot(
            target: .sherpaOnnx(modelID),
            state: .installable(isEnabled: false),
            isInstalled: false,
            isCurrentSelection: false,
            statusText: SherpaOnnxRuntimeSupport.unavailableDetail ?? localizedModelCatalog("Not available"),
            badgeText: localizedModelCatalog("Not available"),
            downloadStatus: nil,
            canOpenLocation: false,
            canConfigure: false,
            configureActionTitle: nil
        )
    }

}

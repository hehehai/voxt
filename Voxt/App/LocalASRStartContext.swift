// LocalASRStartContext.swift
// Provides Local ASRStart Context for app lifecycle and routing.

import Foundation

extension AppDelegate {
    struct LocalASRStartContext {
        let selectedMLXRepo: String
        let activeMLXDownloadRepo: String?
        let isSelectedMLXModelDownloaded: Bool
        let mlxModelState: MLXModelManager.ModelState
        let selectedSherpaModelID: SherpaOnnxModelID
        let activeSherpaDownloadModelID: SherpaOnnxModelID?
        let isSelectedSherpaModelDownloaded: Bool
        let sherpaModelState: SherpaOnnxModelManager.ModelState
    }

    func currentLocalASRStartContext() -> LocalASRStartContext {
        let selectedMLXRepo = mlxModelManager.currentModelRepo
        let selectedSherpaModelID = sherpaOnnxModelManager.selectedModelID

        return LocalASRStartContext(
            selectedMLXRepo: selectedMLXRepo,
            activeMLXDownloadRepo: mlxModelManager.isDownloadOperationActive(repo: selectedMLXRepo)
                ? selectedMLXRepo
                : nil,
            isSelectedMLXModelDownloaded: mlxModelManager.isModelDownloaded(repo: selectedMLXRepo),
            mlxModelState: mlxModelManager.state,
            selectedSherpaModelID: selectedSherpaModelID,
            activeSherpaDownloadModelID: sherpaOnnxModelManager.isDownloadOperationActive(id: selectedSherpaModelID)
                ? selectedSherpaModelID
                : nil,
            isSelectedSherpaModelDownloaded: sherpaOnnxModelManager.isModelDownloaded(id: selectedSherpaModelID),
            sherpaModelState: sherpaOnnxModelManager.state
        )
    }
}

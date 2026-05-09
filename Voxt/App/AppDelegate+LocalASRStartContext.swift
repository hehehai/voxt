import Foundation

extension AppDelegate {
    struct LocalASRStartContext {
        let selectedMLXRepo: String
        let activeMLXDownloadRepo: String?
        let isSelectedMLXModelDownloaded: Bool
        let mlxModelState: MLXModelManager.ModelState
        let selectedWhisperModelID: String
        let activeWhisperDownloadModelID: String?
        let isSelectedWhisperModelDownloaded: Bool
        let whisperModelState: WhisperKitModelManager.ModelState
    }

    func currentLocalASRStartContext() -> LocalASRStartContext {
        let selectedMLXRepo = mlxModelManager.currentModelRepo

        return LocalASRStartContext(
            selectedMLXRepo: selectedMLXRepo,
            activeMLXDownloadRepo: mlxModelManager.isDownloadOperationActive(repo: selectedMLXRepo)
                ? selectedMLXRepo
                : nil,
            isSelectedMLXModelDownloaded: mlxModelManager.isModelDownloaded(repo: selectedMLXRepo),
            mlxModelState: mlxModelManager.state,
            selectedWhisperModelID: whisperModelManager.currentModelID,
            activeWhisperDownloadModelID: whisperModelManager.activeDownload?.modelID,
            isSelectedWhisperModelDownloaded: whisperModelManager.isModelDownloaded(id: whisperModelManager.currentModelID),
            whisperModelState: whisperModelManager.state
        )
    }
}

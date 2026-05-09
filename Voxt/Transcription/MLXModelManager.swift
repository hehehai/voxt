import Foundation
import Combine
import CFNetwork
import MLX
import MLXAudioCore
import MLXAudioSTT
import HuggingFace

@MainActor
class MLXModelManager: ObservableObject {
    static let defaultHubBaseURL = URL(string: "https://huggingface.co")!
    static let mirrorHubBaseURL = URL(string: "https://hf-mirror.com")!
    static let hubUserAgent = "Voxt/1.0 (MLXAudio)"
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(
            progress: Double,
            completed: Int64,
            total: Int64,
            currentFile: String?,
            completedFiles: Int,
            totalFiles: Int
        )
        case paused(
            progress: Double,
            completed: Int64,
            total: Int64,
            currentFile: String?,
            completedFiles: Int,
            totalFiles: Int
        )
        case downloaded
        case loading
        case ready
        case error(String)
    }

    private enum DownloadStopAction {
        case pause
        case cancel
    }

    typealias ModelOption = MLXModelCatalog.Option

    nonisolated static let defaultModelRepo = MLXModelCatalog.defaultModelRepo
    nonisolated static let availableModels = MLXModelCatalog.availableModels

    enum ModelSizeState: Equatable {
        case unknown
        case loading
        case ready(bytes: Int64, text: String)
        case error(String)
    }

    struct TranscriptionBehavior: Equatable {
        enum CorrectionMode: Equatable {
            case incremental
            case finalizationOnly
        }

        let correctionMode: CorrectionMode
        let allowsQuickStopPass: Bool
        let preloadsOnRecordingStart: Bool

        var runsIntermediateCorrections: Bool {
            correctionMode == .incremental
        }
    }

    @Published private(set) var state: ModelState = .notDownloaded
    @Published private(set) var stateByRepo: [String: ModelState] = [:]
    @Published private(set) var sizeState: ModelSizeState = .unknown
    @Published private(set) var remoteSizeTextByRepo: [String: String] = [:]
    @Published private(set) var pausedStatusMessage: String?
    @Published private(set) var pausedStatusMessageByRepo: [String: String] = [:]
    @Published private(set) var activeDownloadRepos: Set<String> = []

    private var downloadedStateByRepo: [String: Bool] = [:]
    private var downloadedStateCachePrimed = false
    private var localSizeTextByRepo: [String: String] = [:]
    private var modelRepo: String
    private var hubBaseURL: URL
    private var loadedModel: (any STTGenerationModel)?
    private var loadedRepo: String?
    private var loadingTask: Task<Void, Error>?
    private var loadingRepo: String?
    private var downloadTasksByRepo: [String: Task<Void, Never>] = [:]
    private var downloadStopActionsByRepo: [String: DownloadStopAction] = [:]
    private var sizeTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private let downloadSizeTolerance: Double = 0.9
    private let idleUnloadDelay: Duration = .seconds(90)
    private var activeUseCount = 0
    private var isMemoryOptimizationEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKey.localModelMemoryOptimizationEnabled) as? Bool ?? true
    }

    init(modelRepo: String, hubBaseURL: URL = URL(string: "https://huggingface.co")!) {
        self.modelRepo = Self.canonicalModelRepo(modelRepo)
        self.hubBaseURL = hubBaseURL
        self.remoteSizeTextByRepo = MLXModelStorageSupport.loadPersistedRemoteSizeCache()
        checkExistingModel()
    }

    var currentModelRepo: String { modelRepo }
    var isCurrentModelLoaded: Bool { loadedModel != nil && loadedRepo == modelRepo }

    func refreshMemoryOptimizationPolicy() {
        guard loadedModel != nil else {
            cancelIdleUnloadTask()
            return
        }
        guard activeUseCount == 0 else { return }
        if isMemoryOptimizationEnabled {
            scheduleIdleUnloadIfNeeded()
        } else {
            cancelIdleUnloadTask()
        }
    }

    func displayTitle(for repo: String) -> String {
        MLXModelCatalog.displayTitle(for: repo)
    }

    nonisolated static func fallbackRemoteSizeText(repo: String) -> String? {
        MLXModelCatalog.fallbackRemoteSizeText(repo: repo)
    }

    nonisolated static func ratingText(for repo: String) -> String {
        MLXModelCatalog.ratingText(for: repo)
    }

    nonisolated static func catalogTagKeys(for repo: String) -> [String] {
        MLXModelCatalog.catalogTagKeys(for: repo)
    }

    nonisolated static func isMultilingualModelRepo(_ repo: String) -> Bool {
        MLXModelCatalog.isMultilingualModelRepo(repo)
    }

    func isModelDownloaded(repo: String) -> Bool {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        primeDownloadedStateCacheIfNeeded()
        if let cached = downloadedStateByRepo[canonicalRepo] {
            return cached
        }
        guard let modelDir = cacheDirectory(for: canonicalRepo) else { return false }
        let isDownloaded = MLXModelDownloadSupport.isModelDirectoryValid(modelDir, fileManager: .default)
        downloadedStateByRepo[canonicalRepo] = isDownloaded
        return isDownloaded
    }

    func hasResumableDownload(repo: String) -> Bool {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard !isModelDownloaded(repo: canonicalRepo) else { return false }
        guard let tempDir = downloadTempDirectory(for: canonicalRepo),
              FileManager.default.fileExists(atPath: tempDir.path) else {
            return false
        }
        return FileManager.default.directoryContainsRegularFiles(at: tempDir)
    }

    func modelSizeOnDisk(repo: String) -> String {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if let cached = localSizeTextByRepo[canonicalRepo] {
            return cached
        }
        guard let modelDir = cacheDirectory(for: canonicalRepo),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: modelDir),
              size > 0
        else {
            return ""
        }
        let text = MLXModelStorageSupport.formatByteCount(Int64(size))
        localSizeTextByRepo[canonicalRepo] = text
        return text
    }

    func cachedModelSizeText(repo: String) -> String? {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        return localSizeTextByRepo[canonicalRepo]
    }

    func modelDirectoryURL(repo: String) -> URL? {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard let modelDir = cacheDirectory(for: canonicalRepo),
              FileManager.default.fileExists(atPath: modelDir.path)
        else { return nil }
        return modelDir
    }

    func deleteModel(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if canonicalRepo == modelRepo {
            pausedStatusMessage = nil
        }
        if canonicalRepo == modelRepo {
            deleteModel()
            return
        }

        if let repoID = Repo.ID(rawValue: canonicalRepo) {
            MLXModelStorageSupport.clearHubCache(
                for: repoID,
                rootDirectory: ModelStorageDirectoryManager.resolvedRootURL()
            )
        }
        if let modelDir = cacheDirectory(for: canonicalRepo) {
            do {
                try FileManager.default.removeItem(at: modelDir)
                VoxtLog.info("Deleted MLX Audio model directory. repo=\(canonicalRepo), path=\(modelDir.path)")
            } catch {
                VoxtLog.error("Failed to delete MLX Audio model directory. repo=\(canonicalRepo), error=\(error.localizedDescription)")
                return
            }
        }
        invalidateLocalCache(for: canonicalRepo)
        clearPerRepoState(for: canonicalRepo)
    }

    func downloadModel(repo: String) async {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        await performDownload(forRepo: canonicalRepo)
    }

    func cancelDownload(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if let task = downloadTasksByRepo[canonicalRepo] {
            downloadStopActionsByRepo[canonicalRepo] = .cancel
            setPausedStatusMessage(nil, for: canonicalRepo)
            setState(.notDownloaded, for: canonicalRepo)
            task.cancel()
            return
        }

        setPausedStatusMessage(nil, for: canonicalRepo)
        cleanupPartialDownload(for: canonicalRepo)
        clearHubCache(for: canonicalRepo)
        invalidateLocalCache(for: canonicalRepo)
        setState(.notDownloaded, for: canonicalRepo)
        if canonicalRepo == modelRepo {
            checkExistingModel()
        }
    }

    func updateModel(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard canonicalRepo != modelRepo else { return }
        cancelIdleUnloadTask()
        loadingTask?.cancel()
        loadingTask = nil
        loadingRepo = nil
        modelRepo = canonicalRepo
        loadedModel = nil
        loadedRepo = nil
        activeUseCount = 0
        Memory.clearCache()
        checkExistingModel()
        fetchRemoteSize()
    }

    nonisolated static func canonicalModelRepo(_ repo: String) -> String {
        MLXModelCatalog.canonicalModelRepo(repo)
    }

    nonisolated static func isRealtimeCapableModelRepo(_ repo: String) -> Bool {
        MLXModelCatalog.isRealtimeCapableModelRepo(repo)
    }

    nonisolated static func transcriptionBehavior(for repo: String) -> TranscriptionBehavior {
        let canonicalRepo = canonicalModelRepo(repo)
        if canonicalRepo.localizedCaseInsensitiveContains("firered") {
            return TranscriptionBehavior(
                correctionMode: .finalizationOnly,
                allowsQuickStopPass: false,
                preloadsOnRecordingStart: true
            )
        }

        return TranscriptionBehavior(
            correctionMode: .incremental,
            allowsQuickStopPass: true,
            preloadsOnRecordingStart: true
        )
    }

    var currentTranscriptionBehavior: TranscriptionBehavior {
        Self.transcriptionBehavior(for: modelRepo)
    }

    func updateHubBaseURL(_ url: URL) {
        guard url != hubBaseURL else { return }
        hubBaseURL = url
        fetchRemoteSize()
    }

    func checkExistingModel() {
        guard let modelDir = cacheDirectory(for: modelRepo) else {
            setState(.error("Invalid model identifier"), for: modelRepo)
            downloadedStateByRepo[modelRepo] = false
            return
        }

        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            if downloadTasksByRepo[modelRepo] == nil, hasResumableDownload(repo: modelRepo) {
                setPausedState(
                    progress: 0,
                    completed: 0,
                    total: 0,
                    currentFile: nil,
                    completedFiles: 0,
                    totalFiles: 0,
                    for: modelRepo
                )
            } else {
                setState(.notDownloaded, for: modelRepo)
            }
            downloadedStateByRepo[modelRepo] = false
            return
        }

        if MLXModelDownloadSupport.isModelDirectoryValid(modelDir, fileManager: .default) {
            downloadedStateByRepo[modelRepo] = true
            if loadedModel != nil, loadedRepo == modelRepo {
                setState(.ready, for: modelRepo)
            } else {
                setState(.downloaded, for: modelRepo)
            }
        } else {
            if downloadTasksByRepo[modelRepo] == nil, hasResumableDownload(repo: modelRepo) {
                setPausedState(
                    progress: 0,
                    completed: 0,
                    total: 0,
                    currentFile: nil,
                    completedFiles: 0,
                    totalFiles: 0,
                    for: modelRepo
                )
            } else {
                setState(.notDownloaded, for: modelRepo)
            }
            downloadedStateByRepo[modelRepo] = false
        }
    }

    func state(for repo: String) -> ModelState {
        MLXModelPerRepoStateSupport.resolvedState(
            for: repo,
            currentRepo: modelRepo,
            currentState: state,
            storedStates: stateByRepo,
            isDownloaded: { isModelDownloaded(repo: $0) },
            hasResumableDownload: { hasResumableDownload(repo: $0) }
        )
    }

    func pausedStatusMessage(for repo: String) -> String? {
        MLXModelPerRepoStateSupport.pausedStatusMessage(
            for: repo,
            storedMessages: pausedStatusMessageByRepo
        )
    }

    func isDownloading(repo: String) -> Bool {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if downloadTasksByRepo[canonicalRepo] != nil { return true }
        if case .downloading = state(for: canonicalRepo) { return true }
        return false
    }

    func isPaused(repo: String) -> Bool {
        if case .paused = state(for: repo) { return true }
        return false
    }

    func isDownloadOperationActive(repo: String) -> Bool {
        switch state(for: repo) {
        case .downloading, .paused:
            return true
        default:
            return false
        }
    }

    private func setState(_ newState: ModelState, for repo: String) {
        MLXModelPerRepoStateSupport.applyState(
            newState,
            for: repo,
            currentRepo: modelRepo,
            currentState: &state,
            storedStates: &stateByRepo
        )
    }

    private func setPausedStatusMessage(_ message: String?, for repo: String) {
        MLXModelPerRepoStateSupport.applyPausedStatusMessage(
            message,
            for: repo,
            currentRepo: modelRepo,
            currentMessage: &pausedStatusMessage,
            storedMessages: &pausedStatusMessageByRepo
        )
    }

    private func clearPerRepoState(for repo: String) {
        MLXModelPerRepoStateSupport.clearState(
            for: repo,
            currentRepo: modelRepo,
            currentPausedStatusMessage: &pausedStatusMessage,
            storedStates: &stateByRepo,
            storedMessages: &pausedStatusMessageByRepo
        )
    }

    func refreshStorageRoot() {
        downloadedStateByRepo.removeAll()
        downloadedStateCachePrimed = false
        localSizeTextByRepo.removeAll()
        MLXModelPerRepoStateSupport.resetStorageRootState(
            currentPausedStatusMessage: &pausedStatusMessage,
            storedStates: &stateByRepo,
            storedMessages: &pausedStatusMessageByRepo
        )
        checkExistingModel()
    }

    func downloadModel() async {
        await performDownload(forRepo: modelRepo)
    }

    private func performDownload(forRepo canonicalRepo: String) async {
        if downloadTasksByRepo[canonicalRepo] != nil { return }
        if case .loading = state(for: canonicalRepo) { return }

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.downloadTasksByRepo[canonicalRepo] = nil
                self.downloadStopActionsByRepo[canonicalRepo] = nil
                self.activeDownloadRepos.remove(canonicalRepo)
            }
            activeDownloadRepos.insert(canonicalRepo)
            if let pausedState = pausedDownloadSnapshot(for: canonicalRepo) {
                setDownloadingState(
                    progress: pausedState.progress,
                    completed: pausedState.completed,
                    total: pausedState.total,
                    currentFile: pausedState.currentFile,
                    completedFiles: pausedState.completedFiles,
                    totalFiles: pausedState.totalFiles,
                    for: canonicalRepo
                )
            } else {
                setDownloadingState(
                    progress: 0,
                    completed: 0,
                    total: 0,
                    currentFile: nil,
                    completedFiles: 0,
                    totalFiles: 0,
                    for: canonicalRepo
                )
            }
            do {
                setPausedStatusMessage(nil, for: canonicalRepo)
                let modelDir = try await performDownloadWithFallback(for: canonicalRepo)
                try Task.checkCancellation()
                try MLXModelDownloadSupport.validateDownloadedModel(
                    at: modelDir,
                    sizeState: sizeState,
                    downloadSizeTolerance: downloadSizeTolerance,
                    fileManager: .default
                )
                downloadedStateByRepo[canonicalRepo] = true
                localSizeTextByRepo.removeValue(forKey: canonicalRepo)
                if canonicalRepo == modelRepo {
                    checkExistingModel()
                } else {
                    setState(.downloaded, for: canonicalRepo)
                }
                VoxtLog.info("Download complete. repo=\(canonicalRepo)")
            } catch is CancellationError {
                switch downloadStopActionsByRepo[canonicalRepo] {
                case .pause:
                    setPausedStatusMessage(nil, for: canonicalRepo)
                    VoxtLog.info("Download paused. repo=\(canonicalRepo)")
                case .cancel, .none:
                    setPausedStatusMessage(nil, for: canonicalRepo)
                    cleanupPartialDownload(for: canonicalRepo)
                    clearHubCache(for: canonicalRepo)
                    invalidateLocalCache(for: canonicalRepo)
                    if canonicalRepo == modelRepo {
                        checkExistingModel()
                    } else {
                        setState(.notDownloaded, for: canonicalRepo)
                    }
                    VoxtLog.info("Download cancelled. repo=\(canonicalRepo)")
                }
            } catch {
                if pauseDownloadIfNetworkIssue(error, repo: canonicalRepo) {
                    return
                }
                setPausedStatusMessage(nil, for: canonicalRepo)
                clearHubCache(for: canonicalRepo)
                setState(.error(downloadErrorMessage(for: error, repo: canonicalRepo)), for: canonicalRepo)
                VoxtLog.error("Download error. repo=\(canonicalRepo), error=\(error.localizedDescription)")
            }
        }
        downloadTasksByRepo[canonicalRepo] = task
        await task.value
    }

    func pauseDownload() {
        pauseDownload(repo: modelRepo)
    }

    func pauseDownload(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard let task = downloadTasksByRepo[canonicalRepo] else { return }
        downloadStopActionsByRepo[canonicalRepo] = .pause
        setPausedStatusMessage(nil, for: canonicalRepo)
        if let snapshot = downloadingSnapshot(for: canonicalRepo) {
            setPausedState(
                progress: snapshot.progress,
                completed: snapshot.completed,
                total: snapshot.total,
                currentFile: snapshot.currentFile,
                completedFiles: snapshot.completedFiles,
                totalFiles: snapshot.totalFiles,
                for: canonicalRepo
            )
        }
        task.cancel()
    }

    func cancelDownload() {
        cancelDownload(repo: modelRepo)
    }

    func loadModel() async throws -> any STTGenerationModel {
        cancelIdleUnloadTask()
        if let model = loadedModel, loadedRepo == modelRepo {
            VoxtLog.info("MLX Audio model reuse existing instance. repo=\(modelRepo)", verbose: true)
            return model
        }
        if let loadingTask, loadingRepo == modelRepo {
            VoxtLog.info("MLX Audio model awaiting in-flight load. repo=\(modelRepo)", verbose: true)
            try await loadingTask.value
            return try readyModel(for: modelRepo)
        }

        let repo = modelRepo
        let startedAt = Date()
        VoxtLog.info("MLX Audio model load started. repo=\(repo)", verbose: true)
        setState(.loading, for: repo)
        let loadingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let model = try await Self.loadSTTModel(for: repo)
            guard !Task.isCancelled else { return }
            guard self.loadingRepo == repo else { return }
            self.loadedModel = model
            self.loadedRepo = repo
            self.setState(.ready, for: repo)
        }
        self.loadingTask = loadingTask
        self.loadingRepo = repo
        do {
            try await loadingTask.value
            self.loadingTask = nil
            self.loadingRepo = nil
            let model = try readyModel(for: repo)
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            VoxtLog.info("MLX Audio model load completed. repo=\(repo), elapsedMs=\(elapsedMs)")
            return model
        } catch {
            self.loadingTask = nil
            self.loadingRepo = nil
            setState(.error("Model load failed: \(error.localizedDescription)"), for: repo)
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            VoxtLog.error("MLX Audio model load failed. repo=\(repo), elapsedMs=\(elapsedMs), error=\(error.localizedDescription)")
            throw error
        }
    }

    func deleteModel() {
        setPausedStatusMessage(nil, for: modelRepo)
        cancelIdleUnloadTask()
        loadingTask?.cancel()
        loadingTask = nil
        loadingRepo = nil
        loadedModel = nil
        loadedRepo = nil
        activeUseCount = 0
        Memory.clearCache()

        clearHubCache(for: modelRepo)

        guard let modelDir = cacheDirectory(for: modelRepo) else {
            setState(.notDownloaded, for: modelRepo)
            invalidateLocalCache(for: modelRepo)
            return
        }
        do {
            try FileManager.default.removeItem(at: modelDir)
            VoxtLog.info("Deleted MLX Audio model directory. repo=\(modelRepo), path=\(modelDir.path)")
        } catch {
            setState(.error("Couldn't uninstall MLX model. It may still be in use."), for: modelRepo)
            VoxtLog.error("Failed to delete MLX Audio model directory. repo=\(modelRepo), error=\(error.localizedDescription)")
            return
        }
        invalidateLocalCache(for: modelRepo)
        setState(.notDownloaded, for: modelRepo)
    }

    func beginActiveUse() {
        activeUseCount += 1
        cancelIdleUnloadTask()
    }

    func endActiveUse() {
        activeUseCount = max(0, activeUseCount - 1)
        guard activeUseCount == 0 else { return }
        scheduleIdleUnloadIfNeeded()
    }

    var modelSizeOnDisk: String {
        modelSizeOnDisk(repo: modelRepo)
    }

    private func invalidateLocalCache(for repo: String) {
        downloadedStateByRepo.removeValue(forKey: repo)
        localSizeTextByRepo.removeValue(forKey: repo)
    }

    private func primeDownloadedStateCacheIfNeeded() {
        guard !downloadedStateCachePrimed else { return }
        downloadedStateCachePrimed = true

        for model in Self.availableModels {
            let canonicalRepo = Self.canonicalModelRepo(model.id)
            guard downloadedStateByRepo[canonicalRepo] == nil else { continue }
            guard let modelDir = cacheDirectory(for: canonicalRepo),
                  FileManager.default.fileExists(atPath: modelDir.path) else {
                downloadedStateByRepo[canonicalRepo] = false
                continue
            }
            downloadedStateByRepo[canonicalRepo] = MLXModelDownloadSupport.isModelDirectoryValid(
                modelDir,
                fileManager: .default
            )
        }
    }

    private func readyModel(for repo: String) throws -> any STTGenerationModel {
        guard let model = loadedModel, loadedRepo == repo else {
            throw NSError(
                domain: "Voxt.MLXModelManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model load finished without a ready model instance."]
            )
        }
        return model
    }

    private static func loadSTTModel(for repo: String) async throws -> any STTGenerationModel {
        let lower = repo.lowercased()
        let cache = activeHubCache()
        if lower.contains("forcedaligner") {
            throw NSError(
                domain: "MLXModelManager",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Qwen3-ForcedAligner is alignment-only and not supported by Voxt transcription."]
            )
        }
        if lower.contains("glmasr") || lower.contains("glm-asr") {
            return try await GLMASRModel.fromPretrained(repo, cache: cache)
        }
        if lower.contains("firered") {
            return try await FireRedASR2Model.fromPretrained(repo, cache: cache)
        }
        if lower.contains("sensevoice") {
            return try await SenseVoiceModel.fromPretrained(repo, cache: cache)
        }
        if lower.contains("qwen3-asr") || lower.contains("qwen3_asr") {
            return try await Qwen3ASRModel.fromPretrained(repo, cache: cache)
        }
        if lower.contains("voxtral") {
            return try await loadVoxtralModel(repo: repo, cache: cache)
        }
        if lower.contains("cohere") {
            return try await loadCohereModel(repo: repo, cache: cache)
        }
        if lower.contains("parakeet") {
            return try await ParakeetModel.fromPretrained(repo, cache: cache)
        }
        if lower.contains("granite") {
            return try await GraniteSpeechModel.fromPretrained(repo, cache: cache)
        }

        return try await Qwen3ASRModel.fromPretrained(repo, cache: cache)
    }

    private static func loadVoxtralModel(repo: String, cache: HubCache) async throws -> VoxtralRealtimeModel {
        guard let repoID = Repo.ID(rawValue: repo) else {
            throw NSError(
                domain: "MLXModelManager",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repository ID: \(repo)"]
            )
        }

        let modelDir = try await ModelUtils.resolveOrDownloadModel(
            repoID: repoID,
            requiredExtension: "safetensors",
            cache: cache
        )
        return try VoxtralRealtimeModel.fromDirectory(modelDir)
    }

    private static func loadCohereModel(repo: String, cache: HubCache) async throws -> CohereTranscribeModel {
        guard let repoID = Repo.ID(rawValue: repo) else {
            throw NSError(
                domain: "MLXModelManager",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repository ID: \(repo)"]
            )
        }

        let modelDir = try await ModelUtils.resolveOrDownloadModel(
            repoID: repoID,
            requiredExtension: "safetensors",
            additionalMatchingPatterns: ["*.model"],
            cache: cache
        )
        return try CohereTranscribeModel.fromDirectory(modelDir)
    }

    static func activeHubCache() -> HubCache {
        MLXModelStorageSupport.hubCache(rootDirectory: ModelStorageDirectoryManager.resolvedRootURL())
    }

    private func cacheDirectory(for repo: String) -> URL? {
        MLXModelStorageSupport.cacheDirectory(
            for: repo,
            rootDirectory: ModelStorageDirectoryManager.resolvedRootURL()
        )
    }

    private func downloadTempDirectory(for repo: String) -> URL? {
        guard let repoID = Repo.ID(rawValue: repo) else { return nil }
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        return ModelStorageDirectoryManager.resolvedRootURL()
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent("\(modelSubdir)-download")
    }

    private func cleanupPartialDownload(for repo: String) {
        if let tempDir = downloadTempDirectory(for: repo) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        guard let modelDir = cacheDirectory(for: repo) else { return }
        try? FileManager.default.removeItem(at: modelDir)
    }

    private func downloadingSnapshot(for repo: String) -> (
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int
    )? {
        guard case .downloading(
            let progress,
            let completed,
            let total,
            let currentFile,
            let completedFiles,
            let totalFiles
        ) = state(for: repo) else {
            return nil
        }
        return (progress, completed, total, currentFile, completedFiles, totalFiles)
    }

    private func pausedDownloadSnapshot(for repo: String) -> (
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int
    )? {
        guard case .paused(
            let progress,
            let completed,
            let total,
            let currentFile,
            let completedFiles,
            let totalFiles
        ) = state(for: repo) else {
            return nil
        }
        return (progress, completed, total, currentFile, completedFiles, totalFiles)
    }

    private func setPausedState(
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int,
        for repo: String
    ) {
        let nextState = ModelState.paused(
            progress: progress,
            completed: completed,
            total: total,
            currentFile: currentFile,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
        setState(nextState, for: repo)
    }

    private func pauseDownloadIfNetworkIssue(_ error: Error, repo: String) -> Bool {
        guard let message = MLXModelDownloadSupport.pauseMessageForInterruptedDownload(error) else {
            return false
        }
        let snapshot = downloadingSnapshot(for: repo) ?? pausedDownloadSnapshot(for: repo)
        setPausedStatusMessage(message, for: repo)
        if let snapshot {
            setPausedState(
                progress: snapshot.progress,
                completed: snapshot.completed,
                total: snapshot.total,
                currentFile: snapshot.currentFile,
                completedFiles: snapshot.completedFiles,
                totalFiles: snapshot.totalFiles,
                for: repo
            )
        } else {
            setPausedState(
                progress: 0,
                completed: 0,
                total: 0,
                currentFile: nil,
                completedFiles: 0,
                totalFiles: 0,
                for: repo
            )
        }
        VoxtLog.warning("Download auto-paused after network issue. repo=\(repo), error=\(error.localizedDescription)")
        return true
    }

    private func fetchRemoteSize() {
        sizeTask?.cancel()
        sizeState = .loading
        let repo = modelRepo

        sizeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sizeInfo = try await loadRemoteSizeInfo(repo: repo)
                if Task.isCancelled { return }
                sizeState = .ready(bytes: sizeInfo.bytes, text: sizeInfo.text)
                updateRemoteSizeCache(repo: repo, text: sizeInfo.text)
            } catch is CancellationError {
                return
            } catch {
                if let fallback = MLXModelCatalog.fallbackRemoteSizeInfo(repo: repo) {
                    sizeState = .ready(bytes: fallback.bytes, text: fallback.text)
                    updateRemoteSizeCache(repo: repo, text: fallback.text)
                } else {
                    sizeState = .error("Size unavailable")
                    updateRemoteSizeCache(repo: repo, text: "Unknown")
                }
            }
        }
    }

    func remoteSizeText(repo: String) -> String {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if let cached = remoteSizeTextByRepo[canonicalRepo] {
            return cached
        }
        if canonicalRepo == modelRepo {
            switch sizeState {
            case .unknown:
                return Self.fallbackRemoteSizeText(repo: canonicalRepo) ?? "Unknown"
            case .loading:
                return "Loading…"
            case .ready(_, let text):
                return text
            case .error:
                return Self.fallbackRemoteSizeText(repo: canonicalRepo) ?? "Unknown"
            }
        }
        return Self.fallbackRemoteSizeText(repo: canonicalRepo) ?? "Unknown"
    }

    func ensureRemoteSizeLoaded(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard remoteSizeTextByRepo[canonicalRepo] == nil else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await loadRemoteSizeInfo(repo: canonicalRepo)
                await MainActor.run {
                    self.updateRemoteSizeCache(repo: canonicalRepo, text: info.text)
                }
            } catch {
                await MainActor.run {
                    self.updateRemoteSizeCache(
                        repo: canonicalRepo,
                        text: Self.fallbackRemoteSizeText(repo: canonicalRepo) ?? "Unknown"
                    )
                }
            }
        }
    }

    func prefetchAllModelSizes() {
        guard prefetchTask == nil else { return }
        let repos = Self.availableModels
            .map { Self.canonicalModelRepo($0.id) }
            .filter { remoteSizeTextByRepo[$0] == nil }
        guard !repos.isEmpty else { return }

        let baseURL = hubBaseURL
        prefetchTask = Task(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.prefetchTask = nil
                }
            }
            for repo in repos {
                guard let self else { return }
                do {
                    let info = try await self.loadRemoteSizeInfo(repo: repo, preferredBaseURL: baseURL)
                    await MainActor.run {
                        self.updateRemoteSizeCache(repo: repo, text: info.text)
                    }
                } catch {
                    await MainActor.run {
                        self.updateRemoteSizeCache(
                            repo: repo,
                            text: Self.fallbackRemoteSizeText(repo: repo) ?? "Unknown"
                        )
                    }
                }
            }
        }
    }

    private func updateRemoteSizeCache(repo: String, text: String) {
        remoteSizeTextByRepo[repo] = text
        MLXModelStorageSupport.savePersistedRemoteSizeCache(remoteSizeTextByRepo)
    }

    private func fallbackHubBaseURL(from baseURL: URL) -> URL? {
        guard !MLXModelDownloadSupport.isMirrorHost(baseURL) else { return nil }
        return Self.mirrorHubBaseURL
    }

    private func loadRemoteSizeInfo(
        repo: String,
        preferredBaseURL: URL? = nil
    ) async throws -> (bytes: Int64, text: String) {
        let baseURL = preferredBaseURL ?? hubBaseURL
        do {
            return try await MLXModelDownloadSupport.fetchModelSizeInfo(
                repo: repo,
                baseURL: baseURL,
                userAgent: Self.hubUserAgent,
                formatByteCount: MLXModelStorageSupport.formatByteCount
            )
        } catch {
            guard let fallbackBaseURL = fallbackHubBaseURL(from: baseURL) else {
                throw error
            }
            VoxtLog.warning(
                "Primary model metadata endpoint failed. Retrying with mirror. repo=\(repo), baseURL=\(baseURL.absoluteString), error=\(error.localizedDescription)"
            )
            return try await MLXModelDownloadSupport.fetchModelSizeInfo(
                repo: repo,
                baseURL: fallbackBaseURL,
                userAgent: Self.hubUserAgent,
                formatByteCount: MLXModelStorageSupport.formatByteCount
            )
        }
    }

    private func performDownloadWithFallback(for repo: String) async throws -> URL {
        do {
            return try await performDownload(using: hubBaseURL, for: repo)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let fallbackBaseURL = fallbackHubBaseURL(from: hubBaseURL) else {
                throw error
            }
            VoxtLog.warning(
                "Primary model download endpoint failed. Retrying with mirror. repo=\(repo), baseURL=\(hubBaseURL.absoluteString), error=\(error.localizedDescription)"
            )
            clearHubCache(for: repo)
            return try await performDownload(using: fallbackBaseURL, for: repo)
        }
    }

    private func performDownload(using baseURL: URL, for repo: String) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: repo) else {
            throw NSError(
                domain: "MLXModelManager",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model identifier"]
            )
        }
        let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
            ?? Bundle.main.object(forInfoDictionaryKey: "HF_TOKEN") as? String
        let session = MLXModelDownloadSupport.makeDownloadSession(for: baseURL)
        return try await resolveOrDownloadModelUsingLFS(
            repoID: repoID,
            session: session,
            baseURL: baseURL,
            bearerToken: token
        )
    }

    private func resolveOrDownloadModelUsingLFS(
        repoID: Repo.ID,
        session: URLSession,
        baseURL: URL,
        bearerToken: String?
    ) async throws -> URL {
        let repo = repoID.description
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        let baseDir = ModelStorageDirectoryManager.resolvedRootURL().appendingPathComponent("mlx-audio")
        let modelDir = baseDir.appendingPathComponent(modelSubdir)
        let tempDir = baseDir.appendingPathComponent("\(modelSubdir)-download")

        if MLXModelDownloadSupport.isModelDirectoryValid(modelDir, fileManager: .default) {
            return modelDir
        }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        VoxtLog.info("Fetching model entries: \(repoID.description)")
        let entries = try await MLXModelDownloadSupport.fetchModelEntries(
            repo: repoID.description,
            baseURL: baseURL,
            session: session,
            userAgent: Self.hubUserAgent
        )
        VoxtLog.info("Entry count: \(entries.count)")
        guard !entries.isEmpty else {
            throw MLXModelDownloadSupport.DownloadValidationError.emptyFileList
        }
        let totalBytes = max(entries.reduce(Int64(0)) { partial, entry in
            partial + max(entry.size ?? 0, 0)
        }, 1)
        let totalFiles = entries.count
        var completedBytes: Int64 = 0

        for (index, entry) in entries.enumerated() {
            let completedFiles = index
            let expectedEntryBytes = max(entry.size ?? 0, 0)
            let progress = Progress(totalUnitCount: max(expectedEntryBytes, 1))
            let baseCompletedBytes = completedBytes
            let isLastEntry = index == totalFiles - 1
            let beforeFraction = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
            setDownloadingState(
                progress: min(1, beforeFraction),
                completed: min(completedBytes, totalBytes),
                total: totalBytes,
                currentFile: entry.path,
                completedFiles: completedFiles,
                totalFiles: totalFiles,
                for: repo
            )
            VoxtLog.info("Download start: \(entry.path) (size=\(entry.size ?? -1))", verbose: true)

            let sampler = Task { [weak self] in
                let startTime = Date()
                while !Task.isCancelled {
                    let effectiveInFlight = Self.inFlightBytes(
                        progress: progress,
                        expectedEntryBytes: expectedEntryBytes,
                        startTime: startTime
                    )
                    let currentCompleted = min(baseCompletedBytes + effectiveInFlight, totalBytes)
                    let fraction = totalBytes > 0 ? Double(currentCompleted) / Double(totalBytes) : 0
                    let fileTransferLooksComplete = expectedEntryBytes > 0 && effectiveInFlight >= expectedEntryBytes
                    let displayCompletedFiles = (isLastEntry && fileTransferLooksComplete) ? totalFiles : completedFiles
                    let displayCurrentFile = (isLastEntry && fileTransferLooksComplete) ? nil : entry.path
                    await MainActor.run {
                        self?.setDownloadingState(
                            progress: min(1, fraction),
                            completed: currentCompleted,
                            total: totalBytes,
                            currentFile: displayCurrentFile,
                            completedFiles: displayCompletedFiles,
                            totalFiles: totalFiles,
                            for: repo
                        )
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { sampler.cancel() }

            let destination = try MLXModelStorageSupport.destinationFileURL(for: entry.path, under: tempDir)
            if MLXModelDownloadSupport.canReuseExistingDownload(
                at: destination,
                expectedSize: entry.size,
                fileManager: .default
            ) {
                let delta = max(expectedEntryBytes, Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                completedBytes += max(delta, 0)
                let finishedFiles = completedFiles + 1
                let fraction = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 1
                setDownloadingState(
                    progress: min(1, fraction),
                    completed: min(completedBytes, totalBytes),
                    total: totalBytes,
                    currentFile: nil,
                    completedFiles: finishedFiles,
                    totalFiles: totalFiles,
                    for: repo
                )
                VoxtLog.info("Download resume reused existing file: \(entry.path)", verbose: true)
                continue
            }

            try await downloadEntryWithRetry(
                repo: repoID.description,
                entryPath: entry.path,
                tempDir: tempDir,
                progress: progress,
                baseURL: baseURL,
                bearerToken: bearerToken
            )
            VoxtLog.info("Download done: \(entry.path)", verbose: true)
            let delta = max(expectedEntryBytes, max(progress.completedUnitCount, 0))
            completedBytes += max(delta, 0)
            let finishedFiles = completedFiles + 1
            let fraction = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 1
            setDownloadingState(
                progress: min(1, fraction),
                completed: min(completedBytes, totalBytes),
                total: totalBytes,
                currentFile: nil,
                completedFiles: finishedFiles,
                totalFiles: totalFiles,
                for: repo
            )
            VoxtLog.info(
                "Download progress: files=\(finishedFiles)/\(totalFiles), bytes=\(min(completedBytes, totalBytes))/\(totalBytes)",
                verbose: true
            )
        }

        VoxtLog.info("Validating downloaded files...", verbose: true)
        try MLXModelDownloadSupport.validateDownloadedModel(
            at: tempDir,
            sizeState: sizeState,
            downloadSizeTolerance: downloadSizeTolerance,
            fileManager: .default
        )
        VoxtLog.info("Moving downloaded files into final cache...", verbose: true)
        try MLXModelDownloadSupport.clearDirectory(at: modelDir, fileManager: .default)
        try FileManager.default.moveItem(at: tempDir, to: modelDir)
        VoxtLog.info("Download files moved to final cache.", verbose: true)
        return modelDir
    }

    private func downloadEntryWithRetry(
        repo: String,
        entryPath: String,
        tempDir: URL,
        progress: Progress,
        baseURL: URL,
        bearerToken: String?
    ) async throws {
        let destination = try MLXModelStorageSupport.destinationFileURL(for: entryPath, under: tempDir)
        let remoteURL = try MLXModelDownloadSupport.fileResolveURL(
            baseURL: baseURL,
            repo: repo,
            path: entryPath
        )
        _ = try await ResumableModelDownloadSupport.download(
            ResumableDownloadDescriptor(
                sourceURL: remoteURL,
                destinationURL: destination,
                relativePath: entryPath,
                expectedSize: progress.totalUnitCount > 1 ? progress.totalUnitCount : nil,
                userAgent: Self.hubUserAgent,
                bearerToken: bearerToken,
                disableProxy: MLXModelDownloadSupport.isMirrorHost(baseURL)
            ),
            progress: progress
        )
    }

    private func setDownloadingState(
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int,
        for repo: String
    ) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard downloadTasksByRepo[canonicalRepo] != nil,
              downloadStopActionsByRepo[canonicalRepo] == nil else { return }
        let nextState = ModelState.downloading(
            progress: progress,
            completed: completed,
            total: total,
            currentFile: currentFile,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
        setState(nextState, for: canonicalRepo)
    }

    private static func inFlightBytes(
        progress: Progress,
        expectedEntryBytes: Int64,
        startTime: Date
    ) -> Int64 {
        let reported = max(progress.completedUnitCount, 0)
        guard reported == 0 else { return reported }

        let elapsed = Date().timeIntervalSince(startTime)
        let expectedForTenMinutes = Double(expectedEntryBytes) / (10 * 60)
        let fallbackRate = max(expectedForTenMinutes, 256 * 1024)
        let estimated = Int64(elapsed * fallbackRate)
        let cap = Int64(Double(expectedEntryBytes) * 0.95)
        return min(max(estimated, 0), max(cap, 0))
    }

    private func downloadErrorMessage(for error: Error, repo: String) -> String {
        if let validationError = error as? MLXModelDownloadSupport.DownloadValidationError,
           let text = validationError.errorDescription
        {
            return text
        }

        if let networkError = error as? MLXModelDownloadSupport.DownloadNetworkError,
           let text = networkError.errorDescription
        {
            return text
        }

        if let httpError = error as? HTTPClientError {
            switch httpError {
            case .responseError(let response, let detail):
                if MLXModelDownloadSupport.isMirrorHost(hubBaseURL), [401, 403].contains(response.statusCode) {
                    return "China mirror rejected request (HTTP \(response.statusCode))."
                }
                if [401, 404].contains(response.statusCode) {
                    return "Model repository unavailable (\(repo), HTTP \(response.statusCode))."
                }
                return "Download failed (HTTP \(response.statusCode)): \(detail)"
            case .decodingError(let response, _):
                return "Download failed while decoding server response (HTTP \(response.statusCode))."
            case .requestError(let detail):
                return "Download request failed: \(detail)"
            case .unexpectedError(let detail):
                return "Download failed: \(detail)"
            }
        }

        return "Download failed: \(error.localizedDescription)"
    }

    private func scheduleIdleUnloadIfNeeded() {
        guard loadedModel != nil else { return }
        guard isMemoryOptimizationEnabled else {
            cancelIdleUnloadTask()
            return
        }
        idleUnloadTask?.cancel()
        let expectedRepo = loadedRepo
        let delay = idleUnloadDelay
        idleUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self else { return }
            await MainActor.run {
                self.unloadLoadedModelIfIdle(expectedRepo: expectedRepo)
            }
        }
    }

    private func cancelIdleUnloadTask() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    private func unloadLoadedModelIfIdle(expectedRepo: String?) {
        guard activeUseCount == 0 else { return }
        guard loadedModel != nil, loadedRepo == expectedRepo else { return }

        loadedModel = nil
        loadedRepo = nil
        idleUnloadTask = nil
        Memory.clearCache()
        checkExistingModel()
        VoxtLog.info("MLX Audio model released after idle period.", verbose: true)
    }

    private func clearHubCache(for repo: String) {
        guard let repoID = Repo.ID(rawValue: repo) else { return }
        MLXModelStorageSupport.clearHubCache(
            for: repoID,
            rootDirectory: ModelStorageDirectoryManager.resolvedRootURL()
        )
    }
}

extension FileManager {
    func directoryContainsRegularFiles(at url: URL) -> Bool {
        guard let enumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                return true
            }
        }
        return false
    }

    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var totalSize: UInt64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            totalSize += UInt64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
        }
        return totalSize
    }
}

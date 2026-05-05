import Foundation
import Combine
import CFNetwork
import WhisperKit

@MainActor
final class WhisperKitModelManager: ObservableObject {
    private static let repo = "argmaxinc/whisperkit-coreml"
    private static let hubUserAgent = "Voxt/1.0 (WhisperKit)"

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

    typealias ModelOption = WhisperKitModelCatalog.Option

    struct ActiveDownload: Equatable {
        let modelID: String
        let isPaused: Bool
        let progress: Double
        let completed: Int64
        let total: Int64
        let currentFile: String?
        let currentFileCompleted: Int64
        let currentFileTotal: Int64
        let completedFiles: Int
        let totalFiles: Int
    }

    private struct DirectoryLookupCache {
        let validURL: URL?
        let rawURL: URL?
    }

    private enum DownloadStopAction {
        case pause
        case cancel
    }

    nonisolated static let defaultModelID = WhisperKitModelCatalog.defaultModelID

    nonisolated static let availableModels = WhisperKitModelCatalog.availableModels

    @Published private(set) var state: ModelState = .notDownloaded
    @Published private(set) var remoteSizeTextByID: [String: String] = [:]
    @Published private(set) var activeDownload: ActiveDownload?
    @Published private(set) var pausedStatusMessageByID: [String: String] = [:]

    private var downloadedStateByID: [String: Bool] = [:]
    private var directoryLookupCacheByID: [String: DirectoryLookupCache] = [:]
    private var directoryLookupCachePrimed = false
    private var localSizeTextByID: [String: String] = [:]
    private var modelID: String
    private var hubBaseURL: URL
    private var loadedWhisper: WhisperKit?
    private var loadedModelID: String?
    private var loadingTask: Task<WhisperKit, Error>?
    private var downloadTask: Task<Void, Never>?
    private var downloadStopAction: DownloadStopAction?
    private var sizeTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private let idleUnloadDelay: Duration = .seconds(90)
    private var activeUseCount = 0
    private var downloadErrorByID: [String: String] = [:]

    init(modelID: String, hubBaseURL: URL) {
        self.modelID = Self.canonicalModelID(modelID)
        self.hubBaseURL = hubBaseURL
        self.remoteSizeTextByID = WhisperKitModelStorageSupport.loadPersistedRemoteSizeCache()
        checkExistingModel()
    }

    var currentModelID: String { modelID }
    var isCurrentModelLoaded: Bool { loadedWhisper != nil && loadedModelID == modelID }
    private var shouldKeepResidentLoaded: Bool {
        let defaults = UserDefaults.standard
        let keepResident = defaults.object(forKey: AppPreferenceKey.whisperKeepResidentLoaded) as? Bool ?? true
        let engineRaw = defaults.string(forKey: AppPreferenceKey.transcriptionEngine) ?? ""
        return keepResident && engineRaw == TranscriptionEngine.whisperKit.rawValue
    }

    nonisolated static func canonicalModelID(_ modelID: String) -> String {
        WhisperKitModelCatalog.canonicalModelID(modelID)
    }

    nonisolated static func fallbackRemoteSizeText(id: String) -> String? {
        WhisperKitModelCatalog.fallbackRemoteSizeText(id: id)
    }

    nonisolated static func ratingText(for id: String) -> String {
        WhisperKitModelCatalog.ratingText(for: id)
    }

    nonisolated static func catalogTagKeys(for id: String) -> [String] {
        WhisperKitModelCatalog.catalogTagKeys(for: id)
    }

    func updateModel(id: String) {
        let canonicalModelID = Self.canonicalModelID(id)
        guard canonicalModelID != modelID else { return }
        cancelIdleUnloadTask()
        loadingTask?.cancel()
        loadingTask = nil
        modelID = canonicalModelID
        loadedWhisper = nil
        loadedModelID = nil
        activeUseCount = 0
        checkExistingModel()
    }

    func updateHubBaseURL(_ url: URL) {
        guard url != hubBaseURL else { return }
        hubBaseURL = url
        fetchRemoteSize(for: modelID)
    }

    func refreshResidencyPolicy() {
        cancelIdleUnloadTask()
        guard activeUseCount == 0, loadedWhisper != nil else { return }
        guard !shouldKeepResidentLoaded else { return }
        scheduleIdleUnloadIfNeeded()
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

    func loadWhisper() async throws -> WhisperKit {
        cancelIdleUnloadTask()
        if let loadedWhisper, loadedModelID == modelID {
            return loadedWhisper
        }
        if let loadingTask {
            return try await loadingTask.value
        }

        guard let modelFolder = modelDirectoryURL(id: modelID) else {
            state = .notDownloaded
            throw NSError(
                domain: "WhisperKitModelManager",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Whisper model is not installed locally."]
            )
        }

        state = .loading
        let targetModelID = modelID
        let targetHubBaseURL = hubBaseURL
        let targetDownloadBase = downloadRootURL()
        let targetModelFolder = modelFolder.path
        let loadingTask = Task<WhisperKit, Error> {
            try await WhisperKit(
                WhisperKitConfig(
                    model: targetModelID,
                    downloadBase: targetDownloadBase,
                    modelRepo: Self.repo,
                    modelEndpoint: targetHubBaseURL.absoluteString,
                    modelFolder: targetModelFolder,
                    verbose: false,
                    load: true,
                    download: false
                )
            )
        }
        self.loadingTask = loadingTask
        do {
            let whisper = try await loadingTask.value
            self.loadingTask = nil
            loadedWhisper = whisper
            loadedModelID = targetModelID
            state = .ready
            return whisper
        } catch {
            self.loadingTask = nil
            if WhisperModelArtifacts.isCorruptLoadFailure(error),
               let invalidFolder = rawModelDirectoryURL(id: targetModelID) {
                try? FileManager.default.removeItem(at: invalidFolder)
                loadedWhisper = nil
                loadedModelID = nil
                downloadErrorByID[targetModelID] = String(localized: "Installed Whisper model is incomplete. Please download it again.")
                state = .notDownloaded
            } else {
                state = .error("Model load failed: \(error.localizedDescription)")
            }
            throw error
        }
    }

    func downloadModel(id: String) async {
        await downloadModel(targetID: Self.canonicalModelID(id))
    }

    func downloadModel() async {
        await downloadModel(targetID: modelID)
    }

    func downloadErrorMessage(for id: String) -> String? {
        downloadErrorByID[Self.canonicalModelID(id)]
    }

    func pausedStatusMessage(for id: String) -> String? {
        pausedStatusMessageByID[Self.canonicalModelID(id)]
    }

    private func downloadModel(targetID: String) async {
        if downloadTask != nil { return }
        if case .loading = state { return }

        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                downloadTask = nil
                downloadStopAction = nil
            }
            let targetID = Self.canonicalModelID(targetID)
            downloadErrorByID[targetID] = nil
            pausedStatusMessageByID[targetID] = nil
            if let activeDownload, activeDownload.modelID == targetID {
                setDownloadingState(
                    for: targetID,
                    progress: activeDownload.progress,
                    completed: activeDownload.completed,
                    total: activeDownload.total,
                    currentFile: activeDownload.currentFile,
                    currentFileCompleted: activeDownload.currentFileCompleted,
                    currentFileTotal: activeDownload.currentFileTotal,
                    completedFiles: activeDownload.completedFiles,
                    totalFiles: activeDownload.totalFiles
                )
            } else {
                setDownloadingState(for: targetID, progress: 0, completed: 0, total: 0)
            }

            do {
                try FileManager.default.createDirectory(at: downloadRootURL(), withIntermediateDirectories: true)
                let downloadedFolder = try await performModelDownloadWithFallback(targetID: targetID)

                guard !Task.isCancelled else {
                    finalizeDownloadState(for: targetID)
                    return
                }

                guard WhisperModelArtifacts.isValidModelDirectory(downloadedFolder) else {
                    let message = "Downloaded Whisper model files are incomplete."
                    downloadErrorByID[targetID] = message
                    try? FileManager.default.removeItem(at: downloadedFolder)
                    if targetID == modelID {
                        state = .error(message)
                    }
                    activeDownload = nil
                    return
                }

                downloadErrorByID[targetID] = nil
                finalizeDownloadState(for: targetID)
            } catch is CancellationError {
                switch downloadStopAction {
                case .pause:
                    pausedStatusMessageByID[targetID] = nil
                    VoxtLog.info("Whisper download paused. model=\(targetID)")
                case .cancel, .none:
                    pausedStatusMessageByID[targetID] = nil
                    activeDownload = nil
                    removeModelDirectoryIfPresent(id: targetID)
                    if targetID == modelID {
                        state = .notDownloaded
                    }
                }
            } catch {
                let message = error.localizedDescription
                if pauseDownloadIfNetworkIssue(error, targetID: targetID) {
                    return
                }
                VoxtLog.error(
                    "Whisper download failed. model=\(targetID), error=\(WhisperKitDownloadSupport.describeError(error))"
                )
                downloadErrorByID[targetID] = message
                pausedStatusMessageByID[targetID] = nil
                if targetID == modelID {
                    state = .error(message)
                }
                activeDownload = nil
            }
        }

        await downloadTask?.value
    }

    private func performModelDownloadWithFallback(targetID: String) async throws -> URL {
        do {
            return try await performModelDownloadWithMetadataRecovery(targetID: targetID, baseURL: hubBaseURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let fallbackBaseURL = fallbackHubBaseURL(from: hubBaseURL) else {
                throw error
            }
            VoxtLog.warning(
                "Primary Whisper download endpoint failed. Retrying with mirror. model=\(targetID), baseURL=\(hubBaseURL.absoluteString), error=\(error.localizedDescription)"
            )
            clearRepositoryMetadataCache()
            return try await performModelDownloadWithMetadataRecovery(targetID: targetID, baseURL: fallbackBaseURL)
        }
    }

    private func performModelDownloadWithMetadataRecovery(targetID: String, baseURL: URL) async throws -> URL {
        do {
            return try await performModelDownload(targetID: targetID, baseURL: baseURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard shouldRetryAfterMetadataRecovery(for: error) else {
                throw error
            }

            VoxtLog.warning(
                "Whisper download hit invalid metadata cache. Clearing local metadata and retrying once. model=\(targetID), baseURL=\(baseURL.absoluteString), error=\(error.localizedDescription)"
            )
            clearRepositoryMetadataCache()
            return try await performModelDownload(targetID: targetID, baseURL: baseURL)
        }
    }

    func pauseDownload() {
        guard downloadTask != nil, let activeDownload else { return }
        downloadStopAction = .pause
        pausedStatusMessageByID[Self.canonicalModelID(activeDownload.modelID)] = nil
        setPausedState(activeDownload)
        downloadTask?.cancel()
    }

    func cancelDownload() {
        if downloadTask != nil {
            downloadStopAction = .cancel
            if let activeDownload {
                let canonicalModelID = Self.canonicalModelID(activeDownload.modelID)
                pausedStatusMessageByID.removeValue(forKey: canonicalModelID)
                downloadErrorByID.removeValue(forKey: canonicalModelID)
                self.activeDownload = nil
                if canonicalModelID == modelID {
                    state = .notDownloaded
                }
            }
            downloadTask?.cancel()
            return
        }

        guard let pausedDownload = activeDownload, pausedDownload.isPaused else { return }
        pausedStatusMessageByID.removeValue(forKey: Self.canonicalModelID(pausedDownload.modelID))
        activeDownload = nil
        removeModelDirectoryIfPresent(id: pausedDownload.modelID)
        checkExistingModel()
        VoxtLog.info("Whisper download cancelled from paused state. model=\(pausedDownload.modelID)")
    }

    func checkExistingModel() {
        guard modelDirectoryURL(id: modelID) != nil else {
            state = .notDownloaded
            downloadedStateByID[modelID] = false
            return
        }

        downloadedStateByID[modelID] = true
        if loadedWhisper != nil, loadedModelID == modelID {
            state = .ready
        } else {
            state = .downloaded
        }
    }

    func isModelDownloaded(id: String) -> Bool {
        let canonicalModelID = Self.canonicalModelID(id)
        primeDirectoryLookupCacheIfNeeded()
        if let cached = downloadedStateByID[canonicalModelID] {
            return cached
        }
        let isDownloaded = modelDirectoryURL(id: canonicalModelID) != nil
        downloadedStateByID[canonicalModelID] = isDownloaded
        return isDownloaded
    }

    func modelDirectoryURL(id: String) -> URL? {
        firstModelDirectoryURL(id: id, requireValid: true)
    }

    private func rawModelDirectoryURL(id: String) -> URL? {
        firstModelDirectoryURL(id: id, requireValid: false)
    }

    private func firstModelDirectoryURL(id: String, requireValid: Bool) -> URL? {
        let canonicalModelID = Self.canonicalModelID(id)
        primeDirectoryLookupCacheIfNeeded()
        if let cached = directoryLookupCacheByID[canonicalModelID] {
            return requireValid ? cached.validURL : (cached.rawURL ?? cached.validURL)
        }
        let expectedFolderName = "openai_whisper-\(canonicalModelID)"
        guard let enumerator = FileManager.default.enumerator(
            at: downloadRootURL(),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == expectedFolderName else { continue }
            if requireValid && !WhisperModelArtifacts.isValidModelDirectory(fileURL) {
                directoryLookupCacheByID[canonicalModelID] = DirectoryLookupCache(validURL: nil, rawURL: fileURL)
                downloadedStateByID[canonicalModelID] = false
                continue
            }
            directoryLookupCacheByID[canonicalModelID] = DirectoryLookupCache(validURL: fileURL, rawURL: fileURL)
            downloadedStateByID[canonicalModelID] = true
            return fileURL
        }

        directoryLookupCacheByID[canonicalModelID] = DirectoryLookupCache(validURL: nil, rawURL: nil)
        downloadedStateByID[canonicalModelID] = false
        return nil
    }

    private func primeDirectoryLookupCacheIfNeeded() {
        guard !directoryLookupCachePrimed else { return }
        directoryLookupCachePrimed = true

        let expectedModelIDs = Set(Self.availableModels.map { Self.canonicalModelID($0.id) })
        guard let enumerator = FileManager.default.enumerator(
            at: downloadRootURL(),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            for modelID in expectedModelIDs {
                downloadedStateByID[modelID] = false
                directoryLookupCacheByID[modelID] = DirectoryLookupCache(validURL: nil, rawURL: nil)
            }
            return
        }

        for case let fileURL as URL in enumerator {
            let folderName = fileURL.lastPathComponent
            guard folderName.hasPrefix("openai_whisper-") else { continue }
            let rawModelID = String(folderName.dropFirst("openai_whisper-".count))
            let canonicalModelID = Self.canonicalModelID(rawModelID)
            guard expectedModelIDs.contains(canonicalModelID) else { continue }
            guard directoryLookupCacheByID[canonicalModelID] == nil else { continue }

            let isValid = WhisperModelArtifacts.isValidModelDirectory(fileURL)
            directoryLookupCacheByID[canonicalModelID] = DirectoryLookupCache(
                validURL: isValid ? fileURL : nil,
                rawURL: fileURL
            )
            downloadedStateByID[canonicalModelID] = isValid
        }

        for modelID in expectedModelIDs where directoryLookupCacheByID[modelID] == nil {
            downloadedStateByID[modelID] = false
            directoryLookupCacheByID[modelID] = DirectoryLookupCache(validURL: nil, rawURL: nil)
        }
    }

    private func removeModelDirectoryIfPresent(id: String) {
        if let directoryURL = rawModelDirectoryURL(id: id) {
            try? removeModelDirectory(at: directoryURL, modelID: id, updatesCurrentState: false)
        }
        invalidateLocalCache(id: id)
    }

    func deleteModel(id: String) {
        let canonicalModelID = Self.canonicalModelID(id)
        pausedStatusMessageByID.removeValue(forKey: canonicalModelID)
        if loadedModelID == canonicalModelID {
            cancelIdleUnloadTask()
            loadingTask?.cancel()
            loadingTask = nil
            loadedWhisper = nil
            loadedModelID = nil
            activeUseCount = 0
        }

        do {
            try removeModelDirectoryIfPresentIfNeeded(id: canonicalModelID)
        } catch {
            if canonicalModelID == modelID {
                state = .error("Couldn't uninstall Whisper model. It may still be in use.")
            }
            VoxtLog.error("Failed to delete Whisper model directory. id=\(canonicalModelID), error=\(error.localizedDescription)")
            return
        }

        if canonicalModelID == modelID {
            state = .notDownloaded
        }
        invalidateLocalCache(id: canonicalModelID)
    }

    func modelSizeOnDisk(id: String) -> String {
        let canonicalModelID = Self.canonicalModelID(id)
        if let cached = localSizeTextByID[canonicalModelID] {
            return cached
        }
        guard let folderURL = modelDirectoryURL(id: canonicalModelID),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: folderURL),
              size > 0
        else {
            return ""
        }
        let text = WhisperKitModelStorageSupport.formatByteCount(Int64(size))
        localSizeTextByID[canonicalModelID] = text
        return text
    }

    func cachedModelSizeText(id: String) -> String? {
        let canonicalModelID = Self.canonicalModelID(id)
        return localSizeTextByID[canonicalModelID]
    }

    func remoteSizeText(id: String) -> String {
        let canonicalModelID = Self.canonicalModelID(id)
        return remoteSizeTextByID[canonicalModelID]
            ?? Self.fallbackRemoteSizeText(id: canonicalModelID)
            ?? AppLocalization.localizedString("Unknown")
    }

    func ensureRemoteSizeLoaded(id: String) {
        let canonicalModelID = Self.canonicalModelID(id)
        guard shouldFetchRemoteSize(for: canonicalModelID) else { return }
        fetchRemoteSize(for: canonicalModelID)
    }

    func displayTitle(for id: String) -> String {
        let canonicalModelID = Self.canonicalModelID(id)
        return AppLocalization.localizedString(WhisperKitModelCatalog.displayTitle(for: canonicalModelID))
    }

    func prefetchAllModelSizes() {
        guard prefetchTask == nil else { return }
        let modelIDs = Self.availableModels
            .map(\.id)
            .filter { shouldFetchRemoteSize(for: $0) }
        guard !modelIDs.isEmpty else { return }

        let baseURL = hubBaseURL
        prefetchTask = Task(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.prefetchTask = nil
                }
            }
            for modelID in modelIDs {
                guard let self else { return }
                do {
                    let bytes = try await self.fetchRemoteModelBytesWithFallback(
                        modelID: modelID,
                        preferredBaseURL: baseURL
                    )
                    guard !Task.isCancelled else { return }
                    let text = bytes > 0
                        ? WhisperKitModelStorageSupport.formatByteCount(bytes)
                        : AppLocalization.localizedString("Unknown")
                    await MainActor.run {
                        self.updateRemoteSizeCache(id: modelID, text: text)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await MainActor.run {
                        self.updateRemoteSizeCache(
                            id: modelID,
                            text: Self.fallbackRemoteSizeText(id: modelID) ?? AppLocalization.localizedString("Unknown")
                        )
                    }
                }
            }
        }
    }

    private func fetchRemoteSize(for id: String) {
        let canonicalModelID = Self.canonicalModelID(id)
        if !shouldFetchRemoteSize(for: canonicalModelID) {
            return
        }

        if canonicalModelID == modelID {
            sizeTask?.cancel()
        }
        remoteSizeTextByID[canonicalModelID] = AppLocalization.localizedString("Loading…")

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let bytes = try await self.fetchRemoteModelBytesWithFallback(modelID: canonicalModelID)
                guard !Task.isCancelled else { return }
                let text = bytes > 0
                    ? WhisperKitModelStorageSupport.formatByteCount(bytes)
                    : AppLocalization.localizedString("Unknown")
                await MainActor.run {
                    self.updateRemoteSizeCache(id: canonicalModelID, text: text)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.updateRemoteSizeCache(
                        id: canonicalModelID,
                        text: Self.fallbackRemoteSizeText(id: canonicalModelID) ?? AppLocalization.localizedString("Unknown")
                    )
                }
                VoxtLog.warning(
                    "Failed to fetch Whisper remote size: model=\(canonicalModelID), error=\(error.localizedDescription)"
                )
            }
        }

        if canonicalModelID == modelID {
            sizeTask = task
        }
    }

    private func updateRemoteSizeCache(id: String, text: String) {
        remoteSizeTextByID[id] = text
        WhisperKitModelStorageSupport.savePersistedRemoteSizeCache(remoteSizeTextByID)
    }

    private func fallbackHubBaseURL(from baseURL: URL) -> URL? {
        guard baseURL.host?.contains("hf-mirror.com") != true else { return nil }
        return MLXModelManager.mirrorHubBaseURL
    }

    private func fetchRemoteModelBytesWithFallback(
        modelID: String,
        preferredBaseURL: URL? = nil
    ) async throws -> Int64 {
        let baseURL = preferredBaseURL ?? hubBaseURL
        do {
            return try await Self.fetchRemoteModelBytes(modelID: modelID, baseURL: baseURL)
        } catch {
            guard let fallbackBaseURL = fallbackHubBaseURL(from: baseURL) else {
                throw error
            }
            VoxtLog.warning(
                "Primary Whisper metadata endpoint failed. Retrying with mirror. model=\(modelID), baseURL=\(baseURL.absoluteString), error=\(error.localizedDescription)"
            )
            return try await Self.fetchRemoteModelBytes(modelID: modelID, baseURL: fallbackBaseURL)
        }
    }

    private static func fetchRemoteModelBytes(modelID: String, baseURL: URL) async throws -> Int64 {
        guard let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }

        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/models/\(encodedRepo)/tree/main?recursive=1") else {
            throw URLError(.badURL)
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        if baseURL.host?.contains("hf-mirror.com") == true {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: false,
                kCFNetworkProxiesHTTPSEnable as String: false,
                kCFNetworkProxiesSOCKSEnable as String: false,
            ]
        }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.setValue(hubUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let rootFolder = topLevelFolderName(for: modelID)
        let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return items.reduce(Int64(0)) { partial, item in
            guard (item["type"] as? String) == "file",
                  let path = item["path"] as? String,
                  path.hasPrefix(rootFolder + "/")
            else {
                return partial
            }

            let size: Int64
            if let raw = item["size"] as? Int64 {
                size = raw
            } else if let raw = item["size"] as? Int {
                size = Int64(raw)
            } else {
                size = 0
            }
            return partial + max(size, 0)
        }
    }

    private static func topLevelFolderName(for modelID: String) -> String {
        WhisperKitModelCatalog.topLevelFolderName(for: modelID)
    }

    private func shouldFetchRemoteSize(for id: String) -> Bool {
        let canonicalModelID = Self.canonicalModelID(id)
        guard let cached = remoteSizeTextByID[canonicalModelID] else { return true }
        return cached == "Unknown"
    }

    private func setDownloadingState(
        for targetID: String,
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String? = nil,
        currentFileCompleted: Int64 = 0,
        currentFileTotal: Int64 = 0,
        completedFiles: Int = 0,
        totalFiles: Int = 0
    ) {
        guard downloadTask != nil, downloadStopAction == nil else { return }
        let nextActiveDownload = ActiveDownload(
            modelID: targetID,
            isPaused: false,
            progress: progress,
            completed: completed,
            total: total,
            currentFile: currentFile,
            currentFileCompleted: currentFileCompleted,
            currentFileTotal: currentFileTotal,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
        if activeDownload != nextActiveDownload {
            activeDownload = nextActiveDownload
        }
        guard targetID == modelID else { return }
        let nextState = ModelState.downloading(
            progress: progress,
            completed: completed,
            total: total,
            currentFile: currentFile,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
        if state != nextState {
            state = nextState
        }
    }

    private func setPausedState(_ activeDownload: ActiveDownload) {
        let canonicalTargetID = Self.canonicalModelID(activeDownload.modelID)
        let nextActiveDownload = ActiveDownload(
            modelID: canonicalTargetID,
            isPaused: true,
            progress: activeDownload.progress,
            completed: activeDownload.completed,
            total: activeDownload.total,
            currentFile: activeDownload.currentFile,
            currentFileCompleted: activeDownload.currentFileCompleted,
            currentFileTotal: activeDownload.currentFileTotal,
            completedFiles: activeDownload.completedFiles,
            totalFiles: activeDownload.totalFiles
        )
        if self.activeDownload != nextActiveDownload {
            self.activeDownload = nextActiveDownload
        }
        guard canonicalTargetID == modelID else { return }
        let nextState = ModelState.paused(
            progress: activeDownload.progress,
            completed: activeDownload.completed,
            total: activeDownload.total,
            currentFile: activeDownload.currentFile,
            completedFiles: activeDownload.completedFiles,
            totalFiles: activeDownload.totalFiles
        )
        if state != nextState {
            state = nextState
        }
    }

    private func pauseDownloadIfNetworkIssue(_ error: Error, targetID: String) -> Bool {
        guard let message = MLXModelDownloadSupport.pauseMessageForInterruptedDownload(error) else {
            return false
        }
        let canonicalTargetID = Self.canonicalModelID(targetID)
        pausedStatusMessageByID[canonicalTargetID] = message
        downloadErrorByID[canonicalTargetID] = nil
        if let activeDownload, activeDownload.modelID == canonicalTargetID {
            setPausedState(activeDownload)
        } else {
            setPausedState(
                ActiveDownload(
                    modelID: canonicalTargetID,
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
            )
        }
        VoxtLog.warning("Whisper download auto-paused after network issue. model=\(canonicalTargetID), error=\(error.localizedDescription)")
        return true
    }

    private func downloadRootURL() -> URL {
        WhisperKitModelStorageSupport.downloadRootURL(
            rootDirectory: ModelStorageDirectoryManager.resolvedRootURL()
        )
    }

    private func performModelDownload(targetID: String, baseURL: URL) async throws -> URL {
        VoxtLog.info("Whisper download using direct file fetch path. model=\(targetID), baseURL=\(baseURL.absoluteString)")
        return try await performDirectModelDownload(targetID: targetID, baseURL: baseURL)
    }

    private func performDirectModelDownload(targetID: String, baseURL: URL) async throws -> URL {
        let rootFolderName = Self.topLevelFolderName(for: targetID)
        let repoItems = try await WhisperKitDownloadSupport.fetchRepoTreeItems(
            baseURL: baseURL,
            repo: Self.repo,
            userAgent: Self.hubUserAgent
        )
        let fileItems = repoItems
            .filter { $0.type == "file" && $0.path.hasPrefix(rootFolderName + "/") }
            .sorted { $0.path < $1.path }

        guard !fileItems.isEmpty else {
            throw NSError(
                domain: "WhisperKitModelManager",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "No files found for Whisper model \(targetID)."]
            )
        }

        let targetFolder = downloadRootURL().appendingPathComponent(rootFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        let totalBytes = max(fileItems.reduce(Int64(0)) { $0 + max($1.size, 0) }, 1)
        let totalFiles = fileItems.count
        var completedBytes: Int64 = 0
        var completedFiles = 0

        for item in fileItems {
            try Task.checkCancellation()

            let relativePath = String(item.path.dropFirst(rootFolderName.count + 1))
            let destinationURL = targetFolder.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let expectedEntryBytes = max(item.size, 0)
            let progress = Progress(totalUnitCount: max(expectedEntryBytes, 1))
            let baseCompletedBytes = completedBytes

            setDownloadingState(
                for: targetID,
                progress: Double(completedBytes) / Double(totalBytes),
                completed: completedBytes,
                total: totalBytes,
                currentFile: relativePath,
                currentFileCompleted: 0,
                currentFileTotal: expectedEntryBytes,
                completedFiles: completedFiles,
                totalFiles: totalFiles
            )

            let sampler = Task { [weak self] in
                let startTime = Date()
                while !Task.isCancelled {
                    let inFlightBytes = WhisperKitDownloadSupport.inFlightBytes(
                        progress: progress,
                        expectedEntryBytes: expectedEntryBytes,
                        startTime: startTime
                    )
                    let currentCompleted = min(baseCompletedBytes + inFlightBytes, totalBytes)
                    let fraction = totalBytes > 0 ? Double(currentCompleted) / Double(totalBytes) : 0
                    await MainActor.run {
                        self?.setDownloadingState(
                            for: targetID,
                            progress: min(1, fraction),
                            completed: currentCompleted,
                            total: totalBytes,
                            currentFile: relativePath,
                            currentFileCompleted: inFlightBytes,
                            currentFileTotal: expectedEntryBytes,
                            completedFiles: completedFiles,
                            totalFiles: totalFiles
                        )
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { sampler.cancel() }

            if MLXModelDownloadSupport.canReuseExistingDownload(
                at: destinationURL,
                expectedSize: item.size,
                fileManager: .default
            ) {
                let delta = max(expectedEntryBytes, Int64((try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                completedBytes += max(delta, 0)
                completedFiles += 1
                setDownloadingState(
                    for: targetID,
                    progress: Double(completedBytes) / Double(totalBytes),
                    completed: completedBytes,
                    total: totalBytes,
                    currentFile: nil,
                    currentFileCompleted: delta,
                    currentFileTotal: expectedEntryBytes,
                    completedFiles: completedFiles,
                    totalFiles: totalFiles
                )
                VoxtLog.info("Whisper download resume reused existing file: \(relativePath)", verbose: true)
                continue
            }

            let remoteURL = try WhisperKitDownloadSupport.fileResolveURL(
                baseURL: baseURL,
                repo: Self.repo,
                path: item.path
            )
            try await downloadFileWithRetry(
                from: remoteURL,
                to: destinationURL,
                disableProxy: baseURL.host?.contains("hf-mirror.com") == true,
                progress: progress,
                relativePath: relativePath,
                expectedSize: expectedEntryBytes
            )

            completedBytes += max(expectedEntryBytes, max(progress.completedUnitCount, 0))
            completedFiles += 1
            setDownloadingState(
                for: targetID,
                progress: Double(completedBytes) / Double(totalBytes),
                completed: completedBytes,
                total: totalBytes,
                currentFile: relativePath,
                currentFileCompleted: max(progress.completedUnitCount, expectedEntryBytes),
                currentFileTotal: expectedEntryBytes,
                completedFiles: completedFiles,
                totalFiles: totalFiles
            )
        }

        return targetFolder
    }

    private func downloadFileWithRetry(
        from remoteURL: URL,
        to destinationURL: URL,
        disableProxy: Bool,
        progress: Progress,
        relativePath: String,
        expectedSize: Int64
    ) async throws {
        _ = try await ResumableModelDownloadSupport.download(
            ResumableDownloadDescriptor(
                sourceURL: remoteURL,
                destinationURL: destinationURL,
                relativePath: relativePath,
                expectedSize: expectedSize > 0 ? expectedSize : nil,
                userAgent: Self.hubUserAgent,
                disableProxy: disableProxy
            ),
            progress: progress
        )
    }

    private func shouldRetryAfterMetadataRecovery(for error: Error) -> Bool {
        WhisperKitDownloadSupport.shouldRetryAfterMetadataRecovery(for: error)
    }

    private func finalizeDownloadState(for targetID: String) {
        activeDownload = nil
        pausedStatusMessageByID.removeValue(forKey: Self.canonicalModelID(targetID))
        invalidateLocalCache(id: targetID)
        if targetID == modelID {
            checkExistingModel()
        }
    }

    private func invalidateLocalCache(id: String) {
        let canonicalModelID = Self.canonicalModelID(id)
        downloadedStateByID.removeValue(forKey: canonicalModelID)
        directoryLookupCacheByID.removeValue(forKey: canonicalModelID)
        localSizeTextByID.removeValue(forKey: canonicalModelID)
    }

    private func removeModelDirectoryIfPresentIfNeeded(id: String) throws {
        if let directoryURL = rawModelDirectoryURL(id: id) {
            try removeModelDirectory(
                at: directoryURL,
                modelID: id,
                updatesCurrentState: Self.canonicalModelID(id) == modelID
            )
        }
    }

    private func removeModelDirectory(at directoryURL: URL, modelID: String, updatesCurrentState: Bool) throws {
        do {
            try FileManager.default.removeItem(at: directoryURL)
            VoxtLog.info("Deleted Whisper model directory. id=\(Self.canonicalModelID(modelID)), path=\(directoryURL.path)")
        } catch {
            if updatesCurrentState {
                state = .error("Couldn't uninstall Whisper model. It may still be in use.")
            }
            throw error
        }
    }

    private func clearRepositoryMetadataCache() {
        WhisperKitModelStorageSupport.clearRepositoryMetadataCache(
            rootDirectory: ModelStorageDirectoryManager.resolvedRootURL()
        )
    }

    private func scheduleIdleUnloadIfNeeded() {
        cancelIdleUnloadTask()
        guard !shouldKeepResidentLoaded else { return }
        idleUnloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: idleUnloadDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await loadedWhisper?.unloadModels()
            loadedWhisper = nil
            loadedModelID = nil
            checkExistingModel()
        }
    }

    private func cancelIdleUnloadTask() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

}

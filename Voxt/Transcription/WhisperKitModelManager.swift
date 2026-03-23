import Foundation
import Combine
import CFNetwork
import WhisperKit

@MainActor
final class WhisperKitModelManager: ObservableObject {
    private static let repo = "argmaxinc/whisperkit-coreml"
    private static let hubUserAgent = "Voxt/1.0 (WhisperKit)"
    private struct RepoTreeItem {
        let path: String
        let type: String
        let size: Int64
    }
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

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
        case downloaded
        case loading
        case ready
        case error(String)
    }

    struct ModelOption: Identifiable, Hashable {
        let id: String
        let title: String
        let description: String
        let remoteSizeText: String
    }

    struct ActiveDownload: Equatable {
        let modelID: String
        let progress: Double
        let completed: Int64
        let total: Int64
        let currentFile: String?
        let currentFileCompleted: Int64
        let currentFileTotal: Int64
        let completedFiles: Int
        let totalFiles: Int
    }

    static let defaultModelID = "base"

    static let availableModels: [ModelOption] = [
        .init(
            id: "tiny",
            title: "Whisper Tiny",
            description: "Smallest footprint for quick local drafts.",
            remoteSizeText: "Unknown"
        ),
        .init(
            id: "base",
            title: "Whisper Base",
            description: "Default balance between quality and speed.",
            remoteSizeText: "Unknown"
        ),
        .init(
            id: "small",
            title: "Whisper Small",
            description: "Higher quality with moderate local resource usage.",
            remoteSizeText: "Unknown"
        ),
        .init(
            id: "medium",
            title: "Whisper Medium",
            description: "High accuracy with heavier local compute requirements.",
            remoteSizeText: "Unknown"
        ),
        .init(
            id: "large-v3",
            title: "Whisper Large v3",
            description: "Best accuracy in the curated list with the largest footprint.",
            remoteSizeText: "Unknown"
        ),
    ]

    @Published private(set) var state: ModelState = .notDownloaded
    @Published private(set) var remoteSizeTextByID: [String: String] = [:]
    @Published private(set) var activeDownload: ActiveDownload?

    private var modelID: String
    private var hubBaseURL: URL
    private var loadedWhisper: WhisperKit?
    private var loadedModelID: String?
    private var loadingTask: Task<WhisperKit, Error>?
    private var downloadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private let idleUnloadDelay: Duration = .seconds(90)
    private var activeUseCount = 0
    private var downloadErrorByID: [String: String] = [:]

    init(modelID: String, hubBaseURL: URL) {
        self.modelID = Self.canonicalModelID(modelID)
        self.hubBaseURL = hubBaseURL
        prefetchAllModelSizes()
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

    static func canonicalModelID(_ modelID: String) -> String {
        availableModels.contains(where: { $0.id == modelID }) ? modelID : defaultModelID
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
        prefetchAllModelSizes()
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

    private func downloadModel(targetID: String) async {
        if downloadTask != nil { return }
        if case .loading = state { return }

        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer { downloadTask = nil }
            let targetID = Self.canonicalModelID(targetID)
            downloadErrorByID[targetID] = nil
            setDownloadingState(for: targetID, progress: 0, completed: 0, total: 0)

            do {
                try FileManager.default.createDirectory(at: downloadRootURL(), withIntermediateDirectories: true)
                let downloadedFolder: URL
                do {
                    downloadedFolder = try await performModelDownload(targetID: targetID)
                } catch {
                    guard shouldRetryAfterMetadataRecovery(for: error) else {
                        throw error
                    }

                    VoxtLog.warning(
                        "Whisper download hit invalid metadata cache. Clearing local metadata and retrying once. model=\(targetID), error=\(error.localizedDescription)"
                    )
                    clearRepositoryMetadataCache()
                    setDownloadingState(for: targetID, progress: 0, completed: 0, total: 0)
                    downloadedFolder = try await performModelDownload(targetID: targetID)
                }

                guard !Task.isCancelled else {
                    removeModelDirectoryIfPresent(id: targetID)
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
                finalizeDownloadState(for: targetID)
            } catch {
                let message = error.localizedDescription
                downloadErrorByID[targetID] = message
                if targetID == modelID {
                    state = .error(message)
                }
                removeModelDirectoryIfPresent(id: targetID)
                activeDownload = nil
            }
        }

        await downloadTask?.value
    }

    func cancelDownload() {
        guard downloadTask != nil else { return }
        downloadTask?.cancel()
        downloadTask = nil
        activeDownload = nil
        checkExistingModel()
    }

    func checkExistingModel() {
        guard modelDirectoryURL(id: modelID) != nil else {
            state = .notDownloaded
            return
        }

        if loadedWhisper != nil, loadedModelID == modelID {
            state = .ready
        } else {
            state = .downloaded
        }
    }

    func isModelDownloaded(id: String) -> Bool {
        modelDirectoryURL(id: id) != nil
    }

    func modelDirectoryURL(id: String) -> URL? {
        firstModelDirectoryURL(id: id, requireValid: true)
    }

    private func rawModelDirectoryURL(id: String) -> URL? {
        firstModelDirectoryURL(id: id, requireValid: false)
    }

    private func firstModelDirectoryURL(id: String, requireValid: Bool) -> URL? {
        let canonicalModelID = Self.canonicalModelID(id)
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
                continue
            }
            return fileURL
        }

        return nil
    }

    private func removeModelDirectoryIfPresent(id: String) {
        if let directoryURL = rawModelDirectoryURL(id: id) {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func deleteModel(id: String) {
        let canonicalModelID = Self.canonicalModelID(id)
        removeModelDirectoryIfPresent(id: canonicalModelID)

        if loadedModelID == canonicalModelID {
            loadedWhisper = nil
            loadedModelID = nil
            activeUseCount = 0
        }

        if canonicalModelID == modelID {
            state = .notDownloaded
        }
    }

    func modelSizeOnDisk(id: String) -> String {
        guard let folderURL = modelDirectoryURL(id: id),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: folderURL),
              size > 0
        else {
            return ""
        }
        return Self.byteFormatter.string(fromByteCount: Int64(size))
    }

    func remoteSizeText(id: String) -> String {
        let canonicalModelID = Self.canonicalModelID(id)
        return remoteSizeTextByID[canonicalModelID] ?? AppLocalization.localizedString("Unknown")
    }

    func displayTitle(for id: String) -> String {
        let canonicalModelID = Self.canonicalModelID(id)
        guard let title = Self.availableModels.first(where: { $0.id == canonicalModelID })?.title else {
            return canonicalModelID
        }
        return AppLocalization.localizedString(title)
    }

    func prefetchAllModelSizes() {
        for model in Self.availableModels where shouldFetchRemoteSize(for: model.id) {
            fetchRemoteSize(for: model.id)
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
                let bytes = try await Self.fetchRemoteModelBytes(
                    modelID: canonicalModelID,
                    baseURL: hubBaseURL
                )
                guard !Task.isCancelled else { return }
                let text = bytes > 0
                    ? Self.byteFormatter.string(fromByteCount: bytes)
                    : AppLocalization.localizedString("Unknown")
                await MainActor.run {
                    self.remoteSizeTextByID[canonicalModelID] = text
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.remoteSizeTextByID[canonicalModelID] = AppLocalization.localizedString("Unknown")
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
        "openai_whisper-\(canonicalModelID(modelID))"
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
        activeDownload = ActiveDownload(
            modelID: targetID,
            progress: progress,
            completed: completed,
            total: total,
            currentFile: currentFile,
            currentFileCompleted: currentFileCompleted,
            currentFileTotal: currentFileTotal,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
        guard targetID == modelID else { return }
        state = .downloading(
            progress: progress,
            completed: completed,
            total: total,
            currentFile: currentFile,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
    }

    private func downloadRootURL() -> URL {
        ModelStorageDirectoryManager.resolvedRootURL()
            .appendingPathComponent("whisperkit", isDirectory: true)
    }

    private func performModelDownload(targetID: String) async throws -> URL {
        if hubBaseURL.host?.contains("hf-mirror.com") == true {
            VoxtLog.info("Whisper download using direct mirror fetch path. model=\(targetID), baseURL=\(hubBaseURL.absoluteString)")
            return try await performMirrorModelDownload(targetID: targetID)
        }

        return try await WhisperKit.download(
            variant: targetID,
            downloadBase: downloadRootURL(),
            from: Self.repo,
            endpoint: hubBaseURL.absoluteString
        ) { [weak self] progress in
            guard let self else { return }
            let completed = max(progress.completedUnitCount, 0)
            let total = max(progress.totalUnitCount, completed)
            Task { @MainActor in
                self.setDownloadingState(
                    for: targetID,
                    progress: total > 0 ? Double(completed) / Double(total) : 0,
                    completed: completed,
                    total: total
                )
            }
        }
    }

    private func performMirrorModelDownload(targetID: String) async throws -> URL {
        let rootFolderName = Self.topLevelFolderName(for: targetID)
        let repoItems = try await Self.fetchRepoTreeItems(baseURL: hubBaseURL)
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
        try? FileManager.default.removeItem(at: targetFolder)
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
                    let inFlightBytes = Self.inFlightBytes(
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

            let remoteURL = try Self.fileResolveURL(
                baseURL: hubBaseURL,
                repo: Self.repo,
                path: item.path
            )
            try await Self.downloadFile(
                from: remoteURL,
                to: destinationURL,
                userAgent: Self.hubUserAgent,
                disableProxy: true,
                progress: progress
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

    private func shouldRetryAfterMetadataRecovery(for error: Error) -> Bool {
        let combined = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return combined.contains("invalid metadata")
            || combined.contains("metadata file")
            || combined.contains("file metadata must have been retrieved")
    }

    private func finalizeDownloadState(for targetID: String) {
        activeDownload = nil
        if targetID == modelID {
            checkExistingModel()
        }
    }

    private func clearRepositoryMetadataCache() {
        let repoRoot = downloadRootURL()
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
        let metadataCacheURL = repoRoot
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("download", isDirectory: true)
        try? FileManager.default.removeItem(at: metadataCacheURL)
    }

    private static func fetchRepoTreeItems(baseURL: URL) async throws -> [RepoTreeItem] {
        guard let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }

        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/models/\(encodedRepo)/tree/main?recursive=1") else {
            throw URLError(.badURL)
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
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

        let rawItems = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return rawItems.compactMap { item in
            guard let path = item["path"] as? String,
                  let type = item["type"] as? String else {
                return nil
            }

            let size: Int64
            if let raw = item["size"] as? Int64 {
                size = raw
            } else if let raw = item["size"] as? Int {
                size = Int64(raw)
            } else {
                size = 0
            }

            return RepoTreeItem(path: path, type: type, size: size)
        }
    }

    private static func fileResolveURL(baseURL: URL, repo: String, path: String) throws -> URL {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedPath = path
            .split(separator: "/")
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
        guard let url = URL(string: "\(base)/\(repo)/resolve/main/\(encodedPath)?download=true") else {
            throw URLError(.badURL)
        }
        return url
    }

    private static func downloadFile(
        from remoteURL: URL,
        to destinationURL: URL,
        userAgent: String,
        disableProxy: Bool,
        progress: Progress
    ) async throws {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 3600
        if disableProxy {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: false,
                kCFNetworkProxiesHTTPSEnable as String: false,
                kCFNetworkProxiesSOCKSEnable as String: false,
            ]
        }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: remoteURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let temporaryURL = destinationURL.appendingPathExtension("download")
        try? FileManager.default.removeItem(at: temporaryURL)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let (byteStream, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if response.expectedContentLength > 0 {
            progress.totalUnitCount = response.expectedContentLength
        }

        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        do {
            var totalWritten: Int64 = 0
            var buffer = [UInt8]()
            buffer.reserveCapacity(64 * 1024)

            for try await byte in byteStream {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    let data = Data(buffer)
                    try fileHandle.write(contentsOf: data)
                    totalWritten += Int64(data.count)
                    progress.completedUnitCount = totalWritten
                    buffer.removeAll(keepingCapacity: true)
                }
            }

            if !buffer.isEmpty {
                let data = Data(buffer)
                try fileHandle.write(contentsOf: data)
                totalWritten += Int64(data.count)
                progress.completedUnitCount = totalWritten
            }

            try fileHandle.close()
        } catch {
            try? fileHandle.close()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
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

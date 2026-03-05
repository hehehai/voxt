import Foundation
import Combine
import CFNetwork
import MLXAudioSTT
import HuggingFace

@MainActor
class MLXModelManager: ObservableObject {
    static let defaultHubBaseURL = URL(string: "https://huggingface.co")!
    static let mirrorHubBaseURL = URL(string: "https://hf-mirror.com")!
    static let hubUserAgent = "Voxt/1.0 (MLXAudio)"
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
    }

    static let defaultModelRepo = "mlx-community/Qwen3-ASR-0.6B-4bit"

    static let availableModels: [ModelOption] = [
        ModelOption(
            id: "mlx-community/Qwen3-ASR-0.6B-4bit",
            title: "Qwen3-ASR 0.6B (4bit)",
            description: "Balanced quality and speed with low memory use."
        ),
        ModelOption(
            id: "mlx-community/Qwen3-ASR-1.7B-bf16",
            title: "Qwen3-ASR 1.7B (bf16)",
            description: "High accuracy flagship model with higher memory usage."
        ),
        ModelOption(
            id: "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16",
            title: "Voxtral Realtime Mini 4B (fp16)",
            description: "Realtime-oriented model with larger memory footprint."
        ),
        ModelOption(
            id: "mlx-community/parakeet-tdt-0.6b-v3",
            title: "Parakeet 0.6B",
            description: "Fast, lightweight English STT."
        ),
        ModelOption(
            id: "mlx-community/GLM-ASR-Nano-2512-4bit",
            title: "GLM-ASR Nano (4bit)",
            description: "Smallest footprint for quick drafts."
        )
    ]
    private static let legacyModelRepoMap: [String: String] = [
        "mlx-community/Parakeet-0.6B": "mlx-community/parakeet-tdt-0.6b-v3",
        "mlx-community/GLM-ASR-Nano-4bit": "mlx-community/GLM-ASR-Nano-2512-4bit",
    ]

    enum ModelSizeState: Equatable {
        case unknown
        case loading
        case ready(bytes: Int64, text: String)
        case error(String)
    }

    @Published private(set) var state: ModelState = .notDownloaded
    @Published private(set) var sizeState: ModelSizeState = .unknown
    @Published private(set) var remoteSizeTextByRepo: [String: String] = [:]

    private var modelRepo: String
    private var hubBaseURL: URL
    private var loadedModel: (any STTGenerationModel)?
    private var loadedRepo: String?
    private var downloadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var downloadTempDir: URL?
    private let downloadSizeTolerance: Double = 0.9
    private let downloadRetryLimit = 3

    init(modelRepo: String, hubBaseURL: URL = URL(string: "https://huggingface.co")!) {
        self.modelRepo = Self.canonicalModelRepo(modelRepo)
        self.hubBaseURL = hubBaseURL
        checkExistingModel()
        fetchRemoteSize()
    }

    var currentModelRepo: String { modelRepo }

    func displayTitle(for repo: String) -> String {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if let option = Self.availableModels.first(where: { $0.id == canonicalRepo }) {
            return option.title
        }
        return canonicalRepo
    }

    func isModelDownloaded(repo: String) -> Bool {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard let modelDir = Self.cacheDirectory(for: canonicalRepo) else { return false }
        return MLXModelDownloadSupport.isModelDirectoryValid(modelDir, fileManager: .default)
    }

    func modelSizeOnDisk(repo: String) -> String {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard let modelDir = Self.cacheDirectory(for: canonicalRepo),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: modelDir),
              size > 0
        else {
            return ""
        }
        return Self.byteFormatter.string(fromByteCount: Int64(size))
    }

    func deleteModel(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if canonicalRepo == modelRepo {
            deleteModel()
            return
        }

        if let repoID = Repo.ID(rawValue: canonicalRepo) {
            clearHubCache(for: repoID)
        }
        if let modelDir = Self.cacheDirectory(for: canonicalRepo) {
            try? FileManager.default.removeItem(at: modelDir)
        }
    }

    func downloadModel(repo: String) async {
        updateModel(repo: repo)
        await downloadModel()
    }

    func updateModel(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard canonicalRepo != modelRepo else { return }
        modelRepo = canonicalRepo
        loadedModel = nil
        loadedRepo = nil
        checkExistingModel()
        fetchRemoteSize()
    }

    static func canonicalModelRepo(_ repo: String) -> String {
        legacyModelRepoMap[repo] ?? repo
    }

    func updateHubBaseURL(_ url: URL) {
        guard url != hubBaseURL else { return }
        hubBaseURL = url
        fetchRemoteSize()
        prefetchAllModelSizes()
    }

    func checkExistingModel() {
        guard let modelDir = Self.cacheDirectory(for: modelRepo) else {
            state = .error("Invalid model identifier")
            return
        }

        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            state = .notDownloaded
            return
        }

        if MLXModelDownloadSupport.isModelDirectoryValid(modelDir, fileManager: .default) {
            if loadedModel != nil, loadedRepo == modelRepo {
                state = .ready
            } else {
                state = .downloaded
            }
        } else {
            state = .notDownloaded
        }
    }

    func downloadModel() async {
        if downloadTask != nil { return }
        if case .loading = state { return }

        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer { downloadTask = nil }
            setDownloadingState(
                progress: 0,
                completed: 0,
                total: 0,
                currentFile: nil,
                completedFiles: 0,
                totalFiles: 0
            )
            do {
                guard let repoID = Repo.ID(rawValue: modelRepo) else {
                    state = .error("Invalid model identifier")
                    return
                }
                let cache = HubCache.default
                let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
                    ?? Bundle.main.object(forInfoDictionaryKey: "HF_TOKEN") as? String
                let session = MLXModelDownloadSupport.makeDownloadSession(for: hubBaseURL)
                let client = MLXModelDownloadSupport.makeHubClient(
                    session: session,
                    baseURL: hubBaseURL,
                    cache: cache,
                    token: token,
                    userAgent: Self.hubUserAgent
                )
                VoxtLog.info("Model download transport: LFS-only (\(hubBaseURL.absoluteString))")
                let resolvedCache = client.cache ?? cache
                let modelDir = try await resolveOrDownloadModelUsingLFS(
                    client: client,
                    cache: resolvedCache,
                    repoID: repoID,
                    session: session
                )
                try Task.checkCancellation()
                try MLXModelDownloadSupport.validateDownloadedModel(
                    at: modelDir,
                    sizeState: sizeState,
                    downloadSizeTolerance: downloadSizeTolerance,
                    fileManager: .default
                )
                checkExistingModel()
                VoxtLog.info("Download complete.")
            } catch is CancellationError {
                cleanupPartialDownload()
                state = .notDownloaded
            } catch {
                clearCurrentRepoHubCache()
                state = .error(downloadErrorMessage(for: error))
                VoxtLog.error("Download error: \(error.localizedDescription)")
            }
        }
    }

    func cancelDownload() {
        guard downloadTask != nil else { return }
        downloadTask?.cancel()
        downloadTask = nil
        cleanupPartialDownload()
        clearCurrentRepoHubCache()
        state = .notDownloaded
    }

    func loadModel() async throws -> any STTGenerationModel {
        if let model = loadedModel, loadedRepo == modelRepo {
            return model
        }

        state = .loading
        do {
            let model = try await Self.loadSTTModel(for: modelRepo)
            loadedModel = model
            loadedRepo = modelRepo
            state = .ready
            return model
        } catch {
            state = .error("Model load failed: \(error.localizedDescription)")
            throw error
        }
    }

    func deleteModel() {
        loadedModel = nil
        loadedRepo = nil

        clearCurrentRepoHubCache()

        guard let modelDir = Self.cacheDirectory(for: modelRepo) else {
            state = .notDownloaded
            return
        }
        try? FileManager.default.removeItem(at: modelDir)
        state = .notDownloaded
    }

    var modelSizeOnDisk: String {
        guard let modelDir = Self.cacheDirectory(for: modelRepo),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: modelDir), size > 0
        else {
            return ""
        }
        return Self.byteFormatter.string(fromByteCount: Int64(size))
    }

    private static func loadSTTModel(for repo: String) async throws -> any STTGenerationModel {
        let lower = repo.lowercased()
        if lower.contains("forcedaligner") {
            throw NSError(
                domain: "MLXModelManager",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Qwen3-ForcedAligner is alignment-only and not supported by Voxt transcription."]
            )
        }
        if lower.contains("glmasr") || lower.contains("glm-asr") {
            return try await GLMASRModel.fromPretrained(repo)
        }
        if lower.contains("qwen3-asr") || lower.contains("qwen3_asr") {
            return try await Qwen3ASRModel.fromPretrained(repo)
        }
        if lower.contains("voxtral") {
            return try await VoxtralRealtimeModel.fromPretrained(repo)
        }
        if lower.contains("parakeet") {
            return try await ParakeetModel.fromPretrained(repo)
        }

        return try await Qwen3ASRModel.fromPretrained(repo)
    }

    private static func cacheDirectory(for repo: String) -> URL? {
        guard let repoID = Repo.ID(rawValue: repo) else { return nil }
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        return HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)
    }

    private func cleanupPartialDownload() {
        if let tempDir = downloadTempDir {
            try? FileManager.default.removeItem(at: tempDir)
            downloadTempDir = nil
        }
        guard let modelDir = Self.cacheDirectory(for: modelRepo) else { return }
        try? FileManager.default.removeItem(at: modelDir)
    }

    private func fetchRemoteSize() {
        sizeTask?.cancel()
        sizeState = .loading
        let repo = modelRepo

        sizeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sizeInfo = try await MLXModelDownloadSupport.fetchModelSizeInfo(
                    repo: repo,
                    baseURL: hubBaseURL,
                    userAgent: Self.hubUserAgent,
                    byteFormatter: Self.byteFormatter
                )
                if Task.isCancelled { return }
                sizeState = .ready(bytes: sizeInfo.bytes, text: sizeInfo.text)
                remoteSizeTextByRepo[repo] = sizeInfo.text
            } catch is CancellationError {
                return
            } catch {
                sizeState = .error("Size unavailable")
                remoteSizeTextByRepo[repo] = "Unknown"
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
                return "Unknown"
            case .loading:
                return "Loading…"
            case .ready(_, let text):
                return text
            case .error:
                return "Unknown"
            }
        }
        return "Unknown"
    }

    func prefetchAllModelSizes() {
        for model in Self.availableModels {
            let repo = Self.canonicalModelRepo(model.id)
            if remoteSizeTextByRepo[repo] != nil { continue }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let info = try await MLXModelDownloadSupport.fetchModelSizeInfo(
                        repo: repo,
                        baseURL: hubBaseURL,
                        userAgent: Self.hubUserAgent,
                        byteFormatter: Self.byteFormatter
                    )
                    await MainActor.run {
                        self.remoteSizeTextByRepo[repo] = info.text
                    }
                } catch {
                    await MainActor.run {
                        self.remoteSizeTextByRepo[repo] = "Unknown"
                    }
                }
            }
        }
    }

    private func resolveOrDownloadModelUsingLFS(
        client: HubClient,
        cache: HubCache,
        repoID: Repo.ID,
        session: URLSession
    ) async throws -> URL {
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        let baseDir = cache.cacheDirectory.appendingPathComponent("mlx-audio")
        let modelDir = baseDir.appendingPathComponent(modelSubdir)
        let tempDir = baseDir.appendingPathComponent("\(modelSubdir)-download")

        if MLXModelDownloadSupport.isModelDirectoryValid(modelDir, fileManager: .default) {
            return modelDir
        }

        downloadTempDir = tempDir
        try MLXModelDownloadSupport.clearDirectory(at: tempDir, fileManager: .default)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        VoxtLog.info("Fetching model entries: \(repoID.description)")
        let entries = try await MLXModelDownloadSupport.fetchModelEntries(
            repo: repoID.description,
            baseURL: hubBaseURL,
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
            let beforeFraction = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
            setDownloadingState(
                progress: min(1, beforeFraction),
                completed: min(completedBytes, totalBytes),
                total: totalBytes,
                currentFile: entry.path,
                completedFiles: completedFiles,
                totalFiles: totalFiles
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
                    await MainActor.run {
                        self?.setDownloadingState(
                            progress: min(1, fraction),
                            completed: currentCompleted,
                            total: totalBytes,
                            currentFile: entry.path,
                            completedFiles: completedFiles,
                            totalFiles: totalFiles
                        )
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { sampler.cancel() }

            try await downloadEntryWithRetry(
                client: client,
                entryPath: entry.path,
                repoID: repoID,
                tempDir: tempDir,
                progress: progress
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
                totalFiles: totalFiles
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
        downloadTempDir = nil
        VoxtLog.info("Download files moved to final cache.", verbose: true)
        return modelDir
    }

    private func downloadEntryWithRetry(
        client: HubClient,
        entryPath: String,
        repoID: Repo.ID,
        tempDir: URL,
        progress: Progress
    ) async throws {
        var attempt = 0
        while true {
            do {
                _ = try await client.downloadFile(
                    at: entryPath,
                    from: repoID,
                    to: tempDir,
                    kind: .model,
                    revision: "main",
                    progress: progress,
                    transport: .lfs,
                    localFilesOnly: false
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                guard attempt <= downloadRetryLimit, isRetryableDownloadError(error) else {
                    throw error
                }
                let delayMs = Int(pow(2.0, Double(attempt - 1)) * 800.0)
                VoxtLog.warning("Download retry \(attempt)/\(downloadRetryLimit): \(entryPath) (\(error.localizedDescription))")
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
        }
    }

    private func setDownloadingState(
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int
    ) {
        state = .downloading(
            progress: progress,
            completed: completed,
            total: total,
            currentFile: currentFile,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
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

    private func isRetryableDownloadError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled,
                 .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .resourceUnavailable,
                 .cannotLoadFromNetwork:
                return true
            default:
                return false
            }
        }

        if let httpError = error as? HTTPClientError {
            switch httpError {
            case .requestError, .unexpectedError:
                return true
            case .responseError(let response, _):
                return response.statusCode >= 500 || response.statusCode == 429 || response.statusCode == 408
            case .decodingError:
                return false
            }
        }

        return false
    }

    private func downloadErrorMessage(for error: Error) -> String {
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
                    return "Model repository unavailable (\(modelRepo), HTTP \(response.statusCode))."
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

    private func clearHubCache(for repoID: Repo.ID) {
        let cache = HubCache.default
        let repoDir = cache.repoDirectory(repo: repoID, kind: .model)
        let metadataDir = cache.metadataDirectory(repo: repoID, kind: .model)
        try? FileManager.default.removeItem(at: repoDir)
        try? FileManager.default.removeItem(at: metadataDir)
    }

    private func clearCurrentRepoHubCache() {
        guard let repoID = Repo.ID(rawValue: modelRepo) else { return }
        clearHubCache(for: repoID)
    }
}

extension FileManager {
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

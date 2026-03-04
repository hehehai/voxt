import Foundation
import HuggingFace
import Combine
import MLXLMCommon

@MainActor
class CustomLLMModelManager: ObservableObject {
    static let defaultHubBaseURL = URL(string: "https://huggingface.co")!
    static let mirrorHubBaseURL = URL(string: "https://hf-mirror.com")!
    static let hubUserAgent = "Voxt/1.0 (CustomLLM)"

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
        case error(String)
    }

    enum ModelSizeState: Equatable {
        case unknown
        case loading
        case ready(bytes: Int64, text: String)
        case error(String)
    }

    struct ModelOption: Identifiable, Hashable {
        let id: String
        let title: String
        let description: String
    }

    static let defaultModelRepo = "Qwen/Qwen2-1.5B-Instruct"
    static let availableModels: [ModelOption] = [
        ModelOption(
            id: "Qwen/Qwen2-1.5B-Instruct",
            title: "Qwen2 1.5B Instruct",
            description: "General-purpose instruction model for prompt-based text cleanup."
        ),
        ModelOption(
            id: "Qwen/Qwen2.5-3B-Instruct",
            title: "Qwen2.5 3B Instruct",
            description: "Larger instruction model with stronger reasoning and formatting quality."
        ),
        ModelOption(
            id: "mlx-community/Qwen3-4B-4bit",
            title: "Qwen3 4B (4bit)",
            description: "Balanced Qwen3 model for quality and performance."
        ),
        ModelOption(
            id: "mlx-community/Qwen3-8B-4bit",
            title: "Qwen3 8B (4bit)",
            description: "Higher-quality Qwen3 model for stronger enhancement results."
        ),
        ModelOption(
            id: "mlx-community/GLM-4-9B-0414-4bit",
            title: "GLM-4 9B (4bit)",
            description: "GLM-4 model variant with strong multilingual instruction following."
        ),
        ModelOption(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            title: "Llama 3.2 3B Instruct (4bit)",
            description: "Lightweight Llama 3.2 model for fast local enhancement."
        ),
        ModelOption(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            title: "Llama 3.2 1B Instruct (4bit)",
            description: "Smallest Llama 3.2 option with minimal memory footprint."
        ),
        ModelOption(
            id: "mlx-community/Meta-Llama-3-8B-Instruct-4bit",
            title: "Meta Llama 3 8B Instruct (4bit)",
            description: "General-purpose 8B instruction model with strong quality."
        ),
        ModelOption(
            id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            title: "Meta Llama 3.1 8B Instruct (4bit)",
            description: "Refined 8B Llama 3.1 instruction model."
        ),
        ModelOption(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            title: "Mistral 7B Instruct v0.3 (4bit)",
            description: "Reliable 7B instruction model for concise formatting tasks."
        ),
        ModelOption(
            id: "mlx-community/Mistral-Nemo-Instruct-2407-4bit",
            title: "Mistral Nemo Instruct 2407 (4bit)",
            description: "Nemo-based Mistral model with improved instruction quality."
        ),
        ModelOption(
            id: "mlx-community/gemma-2-2b-it-4bit",
            title: "Gemma 2 2B IT (4bit)",
            description: "Compact Gemma 2 instruction-tuned model."
        ),
        ModelOption(
            id: "mlx-community/gemma-2-9b-it-4bit",
            title: "Gemma 2 9B IT (4bit)",
            description: "Higher-capacity Gemma 2 model for better quality output."
        )
    ]

    @Published private(set) var state: ModelState = .notDownloaded
    @Published private(set) var sizeState: ModelSizeState = .unknown
    @Published private(set) var remoteSizeTextByRepo: [String: String] = [:]

    private var modelRepo: String
    private var hubBaseURL: URL
    private var downloadTask: Task<Void, Never>?
    private var downloadProgressTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var inferenceContainer: ModelContainer?
    private var inferenceModelRepo: String?
    private var lastLoggedModelPresence: (repo: String, downloaded: Bool)?
    private var lastInvalidRepoLogged: String?

    init(modelRepo: String, hubBaseURL: URL = URL(string: "https://huggingface.co")!) {
        let sanitizedRepo = Self.isSupportedModelRepo(modelRepo) ? modelRepo : Self.defaultModelRepo
        self.modelRepo = sanitizedRepo
        self.hubBaseURL = hubBaseURL
        self.remoteSizeTextByRepo = Self.loadPersistedRemoteSizeCache()
        if sanitizedRepo != modelRepo {
            VoxtLog.warning("Unsupported custom LLM repo '\(modelRepo)' found in settings. Falling back to \(sanitizedRepo).")
        }
        VoxtLog.info("Custom LLM manager initialized. repo=\(sanitizedRepo), hub=\(hubBaseURL.absoluteString)")
        checkExistingModel()
        fetchRemoteSize()
    }

    var currentModelRepo: String { modelRepo }

    func enhance(_ rawText: String, systemPrompt: String) async throws -> String {
        let input = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return rawText }

        guard isModelDownloaded(repo: modelRepo) else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Custom LLM model is not installed locally."]
            )
        }

        let container: ModelContainer
        if let cached = inferenceContainer, inferenceModelRepo == modelRepo {
            container = cached
        } else {
            guard let directory = cacheDirectory(for: modelRepo) else {
                throw NSError(
                    domain: "Voxt.CustomLLM",
                    code: -10,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid local model path."]
                )
            }
            container = try await loadModelContainer(directory: directory)
            inferenceContainer = container
            inferenceModelRepo = modelRepo
        }

        let session = ChatSession(container, instructions: systemPrompt)
        session.generateParameters = GenerateParameters(
            maxTokens: 256,
            temperature: 0.1,
            topP: 0.95
        )

        let prompt = """
        Clean up this transcription:

        \(input)
        """

        let response = try await session.respond(to: modelPrompt(prompt, repo: modelRepo))
        let cleaned = sanitizeModelOutput(response)
        return cleaned.isEmpty ? rawText : cleaned
    }

    func translate(
        _ text: String,
        targetLanguage: TranslationTargetLanguage,
        systemPrompt: String,
        modelRepo: String
    ) async throws -> String {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return text }
        _ = targetLanguage
        let translated = try await runTranslationPrompt(
            input,
            instructions: systemPrompt,
            modelRepo: modelRepo
        )
        return translated.isEmpty ? text : translated
    }

    private func runTranslationPrompt(
        _ text: String,
        instructions: String,
        modelRepo: String
    ) async throws -> String {
        guard isModelDownloaded(repo: modelRepo) else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Custom LLM model is not installed locally."]
            )
        }

        let container = try await container(for: modelRepo)
        let session = ChatSession(container, instructions: instructions)
        session.generateParameters = GenerateParameters(
            maxTokens: 256,
            temperature: 0.1,
            topP: 0.95
        )
        let response = try await session.respond(to: modelPrompt(text, repo: modelRepo))
        return sanitizeModelOutput(response)
    }

    private func container(for repo: String) async throws -> ModelContainer {
        if let cached = inferenceContainer, inferenceModelRepo == repo {
            return cached
        }

        guard let directory = cacheDirectory(for: repo) else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Invalid local model path."]
            )
        }
        let container = try await loadModelContainer(directory: directory)
        inferenceContainer = container
        inferenceModelRepo = repo
        return container
    }

    func displayTitle(for repo: String) -> String {
        if let option = Self.availableModels.first(where: { $0.id == repo }) {
            return option.title
        }
        return repo
    }

    func updateModel(repo: String) {
        let sanitizedRepo = Self.isSupportedModelRepo(repo) ? repo : Self.defaultModelRepo
        guard sanitizedRepo != modelRepo else { return }
        if sanitizedRepo != repo {
            VoxtLog.warning("Unsupported custom LLM repo '\(repo)' requested. Falling back to \(sanitizedRepo).")
        }
        VoxtLog.info("Custom LLM model changed: \(modelRepo) -> \(sanitizedRepo)")
        modelRepo = sanitizedRepo
        inferenceContainer = nil
        inferenceModelRepo = nil
        lastLoggedModelPresence = nil
        lastInvalidRepoLogged = nil
        checkExistingModel()
        fetchRemoteSize()
    }

    static func isSupportedModelRepo(_ repo: String) -> Bool {
        availableModels.contains { $0.id == repo }
    }

    func updateHubBaseURL(_ url: URL) {
        guard url != hubBaseURL else { return }
        VoxtLog.info("Custom LLM hub base URL changed: \(hubBaseURL.absoluteString) -> \(url.absoluteString)")
        hubBaseURL = url
        fetchRemoteSize()
        prefetchAllModelSizes()
    }

    func isModelDownloaded(repo: String) -> Bool {
        guard let modelDir = cacheDirectory(for: repo) else { return false }
        return Self.isModelDirectoryValid(modelDir)
    }

    func modelSizeOnDisk(repo: String) -> String {
        guard let modelDir = cacheDirectory(for: repo),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: modelDir),
              size > 0
        else {
            return ""
        }
        return Self.byteFormatter.string(fromByteCount: Int64(size))
    }

    func modelDirectoryURL(repo: String) -> URL? {
        guard let modelDir = cacheDirectory(for: repo),
              FileManager.default.fileExists(atPath: modelDir.path)
        else { return nil }
        return modelDir
    }

    func remoteSizeText(repo: String) -> String {
        if let cached = remoteSizeTextByRepo[repo] {
            return cached
        }
        guard repo == modelRepo else { return "Unknown" }
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

    func checkExistingModel() {
        guard let modelDir = cacheDirectory(for: modelRepo) else {
            state = .error("Invalid model identifier")
            if lastInvalidRepoLogged != modelRepo {
                VoxtLog.error("Invalid custom LLM repo identifier: \(modelRepo)")
                lastInvalidRepoLogged = modelRepo
            }
            return
        }
        lastInvalidRepoLogged = nil
        state = Self.isModelDirectoryValid(modelDir) ? .downloaded : .notDownloaded
        let downloaded = (state == .downloaded)
        if lastLoggedModelPresence?.repo != modelRepo || lastLoggedModelPresence?.downloaded != downloaded {
            VoxtLog.info("Custom LLM local model state refreshed: repo=\(modelRepo), downloaded=\(downloaded)")
            lastLoggedModelPresence = (modelRepo, downloaded)
        }
    }

    func downloadModel() async {
        if downloadTask != nil { return }

        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                cancelDownloadProgressTask()
                downloadTask = nil
            }
            setDownloadingState(progress: 0, completed: 0, total: 0, currentFile: nil, completedFiles: 0, totalFiles: 0)

            do {
                guard let repoID = Repo.ID(rawValue: modelRepo) else {
                    state = .error("Invalid model identifier")
                    VoxtLog.error("Custom LLM download failed: invalid repo id \(modelRepo)")
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

                let entries = try await MLXModelDownloadSupport.fetchModelEntries(
                    repo: repoID.description,
                    baseURL: hubBaseURL,
                    session: session,
                    userAgent: Self.hubUserAgent
                )
                guard !entries.isEmpty else {
                    state = .error("No downloadable files were found for this model.")
                    VoxtLog.error("Custom LLM download failed: no downloadable files for \(repoID.description)")
                    return
                }
                VoxtLog.info("Custom LLM download started: repo=\(repoID.description), files=\(entries.count)")

                let totalBytes = max(entries.reduce(Int64(0)) { $0 + max($1.size ?? 0, 0) }, 1)
                let totalFiles = entries.count
                var completedBytes: Int64 = 0

                let modelDir = cacheDirectory(for: modelRepo)!
                try? FileManager.default.removeItem(at: modelDir)
                try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

                for (index, entry) in entries.enumerated() {
                    let expectedFileBytes = max(entry.size ?? 0, 0)
                    let progress = Progress(totalUnitCount: max(expectedFileBytes, 1))
                    let fileBaseCompleted = completedBytes
                    setDownloadingState(
                        progress: min(1, Double(completedBytes) / Double(totalBytes)),
                        completed: min(completedBytes, totalBytes),
                        total: totalBytes,
                        currentFile: entry.path,
                        completedFiles: index,
                        totalFiles: totalFiles
                    )

                    cancelDownloadProgressTask()
                    downloadProgressTask = Task { [weak self] in
                        let startTime = Date()
                        while !Task.isCancelled {
                            await MainActor.run {
                                guard let self else { return }
                                let effectiveCurrentFileCompleted = Self.inFlightBytes(
                                    progress: progress,
                                    expectedFileBytes: expectedFileBytes,
                                    startTime: startTime
                                )
                                let aggregateCompleted = min(
                                    fileBaseCompleted + effectiveCurrentFileCompleted,
                                    totalBytes
                                )
                                self.setDownloadingState(
                                    progress: min(1, Double(aggregateCompleted) / Double(totalBytes)),
                                    completed: aggregateCompleted,
                                    total: totalBytes,
                                    currentFile: entry.path,
                                    completedFiles: index,
                                    totalFiles: totalFiles
                                )
                            }
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                    }

                    _ = try await client.downloadFile(
                        at: entry.path,
                        from: repoID,
                        to: modelDir,
                        kind: .model,
                        revision: "main",
                        progress: progress,
                        transport: .lfs,
                        localFilesOnly: false
                    )
                    cancelDownloadProgressTask()

                    let delta = max(expectedFileBytes, max(progress.completedUnitCount, 0))
                    completedBytes += max(delta, 0)
                    setDownloadingState(
                        progress: min(1, Double(completedBytes) / Double(totalBytes)),
                        completed: min(completedBytes, totalBytes),
                        total: totalBytes,
                        currentFile: nil,
                        completedFiles: index + 1,
                        totalFiles: totalFiles
                    )
                }

                guard Self.isModelDirectoryValid(modelDir) else {
                    state = .error("Downloaded files are incomplete.")
                    VoxtLog.error("Custom LLM download produced incomplete files: \(modelRepo)")
                    return
                }

                state = .downloaded
                VoxtLog.info("Custom LLM download completed: \(modelRepo)")
            } catch is CancellationError {
                cancelDownloadProgressTask()
                state = .notDownloaded
                VoxtLog.warning("Custom LLM download cancelled: \(modelRepo)")
            } catch {
                cancelDownloadProgressTask()
                state = .error("Download failed: \(error.localizedDescription)")
                VoxtLog.error("Custom LLM download failed: \(modelRepo), error=\(error.localizedDescription)")
            }
        }
    }

    func downloadModel(repo: String) async {
        updateModel(repo: repo)
        await downloadModel()
    }

    func cancelDownload() {
        VoxtLog.info("Custom LLM download cancellation requested: \(modelRepo)")
        downloadTask?.cancel()
        cancelDownloadProgressTask()
        downloadTask = nil
        state = .notDownloaded
    }

    private func cancelDownloadProgressTask() {
        downloadProgressTask?.cancel()
        downloadProgressTask = nil
    }

    func deleteModel() {
        deleteModel(repo: modelRepo)
        state = .notDownloaded
    }

    func deleteModel(repo: String) {
        VoxtLog.info("Deleting custom LLM model cache: \(repo)")
        if let repoID = Repo.ID(rawValue: repo) {
            clearHubCache(for: repoID)
        }
        if let modelDir = cacheDirectory(for: repo) {
            try? FileManager.default.removeItem(at: modelDir)
        }
        if repo == inferenceModelRepo {
            inferenceContainer = nil
            inferenceModelRepo = nil
        }
        if repo == modelRepo {
            state = .notDownloaded
        }
    }

    private func fetchRemoteSize() {
        sizeTask?.cancel()
        let repo = modelRepo
        if let cachedText = remoteSizeTextByRepo[repo], cachedText != "Unknown" {
            sizeState = .ready(bytes: 0, text: cachedText)
            return
        }
        sizeState = .loading

        sizeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await MLXModelDownloadSupport.fetchModelSizeInfo(
                    repo: repo,
                    baseURL: hubBaseURL,
                    userAgent: Self.hubUserAgent,
                    byteFormatter: Self.byteFormatter
                )
                if Task.isCancelled { return }
                sizeState = .ready(bytes: info.bytes, text: info.text)
                remoteSizeTextByRepo[repo] = info.text
                Self.savePersistedRemoteSizeCache(remoteSizeTextByRepo)
            } catch is CancellationError {
                return
            } catch {
                sizeState = .error("Size unavailable")
                remoteSizeTextByRepo[repo] = "Unknown"
                VoxtLog.warning("Failed to fetch custom LLM remote size: repo=\(repo), error=\(error.localizedDescription)")
            }
        }
    }

    func prefetchAllModelSizes() {
        for model in Self.availableModels {
            if remoteSizeTextByRepo[model.id] != nil { continue }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let info = try await MLXModelDownloadSupport.fetchModelSizeInfo(
                        repo: model.id,
                        baseURL: hubBaseURL,
                        userAgent: Self.hubUserAgent,
                        byteFormatter: Self.byteFormatter
                    )
                    await MainActor.run {
                        self.remoteSizeTextByRepo[model.id] = info.text
                        Self.savePersistedRemoteSizeCache(self.remoteSizeTextByRepo)
                    }
                } catch {
                    await MainActor.run {
                        self.remoteSizeTextByRepo[model.id] = "Unknown"
                    }
                    VoxtLog.warning("Failed to prefetch custom LLM model size: repo=\(model.id), error=\(error.localizedDescription)")
                }
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
        expectedFileBytes: Int64,
        startTime: Date
    ) -> Int64 {
        let reported = max(progress.completedUnitCount, 0)
        guard reported == 0 else { return reported }

        let elapsed = Date().timeIntervalSince(startTime)
        let expectedForTenMinutes = Double(expectedFileBytes) / (10 * 60)
        let fallbackRate = max(expectedForTenMinutes, 256 * 1024)
        let estimated = Int64(elapsed * fallbackRate)
        let cap = Int64(Double(expectedFileBytes) * 0.95)
        return min(max(estimated, 0), max(cap, 0))
    }

    private static func loadPersistedRemoteSizeCache() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.customLLMRemoteSizeCache),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func savePersistedRemoteSizeCache(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: AppPreferenceKey.customLLMRemoteSizeCache)
    }

    private func modelPrompt(_ prompt: String, repo: String) -> String {
        guard shouldForceNoThink(repo: repo) else { return prompt }
        return "/no_think\n\(prompt)"
    }

    private func shouldForceNoThink(repo: String) -> Bool {
        switch repo {
        case "mlx-community/Qwen3.5-2B-MLX-4bit",
             "mlx-community/Qwen3.5-4B-MLX-4bit",
             "mlx-community/Qwen3.5-9B-MLX-4bit":
            return true
        default:
            return false
        }
    }

    private func sanitizeModelOutput(_ output: String) -> String {
        var cleaned = output
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: (cleaned as NSString).length)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cacheDirectory(for repo: String) -> URL? {
        Self.cacheDirectory(for: repo, rootDirectory: ModelStorageDirectoryManager.resolvedRootURL())
    }

    private static func cacheDirectory(for repo: String, rootDirectory: URL) -> URL? {
        guard let repoID = Repo.ID(rawValue: repo) else { return nil }
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        return rootDirectory
            .appendingPathComponent("mlx-llm")
            .appendingPathComponent(modelSubdir)
    }

    private static func isModelDirectoryValid(_ directory: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        let rootConfig = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: rootConfig.path),
              let rootConfigData = try? Data(contentsOf: rootConfig),
              (try? JSONSerialization.jsonObject(with: rootConfigData)) != nil
        else {
            return false
        }

        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return false
        }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "safetensors" {
                return true
            }
        }
        return false
    }

    private func clearHubCache(for repoID: Repo.ID) {
        let cache = HubCache.default
        let repoDir = cache.repoDirectory(repo: repoID, kind: .model)
        let metadataDir = cache.metadataDirectory(repo: repoID, kind: .model)
        try? FileManager.default.removeItem(at: repoDir)
        try? FileManager.default.removeItem(at: metadataDir)
    }
}

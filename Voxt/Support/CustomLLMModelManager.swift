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
        )
    ]

    @Published private(set) var state: ModelState = .notDownloaded
    @Published private(set) var sizeState: ModelSizeState = .unknown
    @Published private(set) var remoteSizeTextByRepo: [String: String] = [:]

    private var modelRepo: String
    private var hubBaseURL: URL
    private var downloadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var inferenceContainer: ModelContainer?
    private var inferenceModelRepo: String?

    init(modelRepo: String, hubBaseURL: URL = URL(string: "https://huggingface.co")!) {
        self.modelRepo = modelRepo
        self.hubBaseURL = hubBaseURL
        VoxtLog.info("Custom LLM manager initialized. repo=\(modelRepo), hub=\(hubBaseURL.absoluteString)")
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
            guard let directory = Self.cacheDirectory(for: modelRepo) else {
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

        let response = try await session.respond(to: prompt)
        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let response = try await session.respond(to: text)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func container(for repo: String) async throws -> ModelContainer {
        if let cached = inferenceContainer, inferenceModelRepo == repo {
            return cached
        }

        guard let directory = Self.cacheDirectory(for: repo) else {
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
        guard repo != modelRepo else { return }
        VoxtLog.info("Custom LLM model changed: \(modelRepo) -> \(repo)")
        modelRepo = repo
        inferenceContainer = nil
        inferenceModelRepo = nil
        checkExistingModel()
        fetchRemoteSize()
    }

    func updateHubBaseURL(_ url: URL) {
        guard url != hubBaseURL else { return }
        VoxtLog.info("Custom LLM hub base URL changed: \(hubBaseURL.absoluteString) -> \(url.absoluteString)")
        hubBaseURL = url
        fetchRemoteSize()
        prefetchAllModelSizes()
    }

    func isModelDownloaded(repo: String) -> Bool {
        guard let modelDir = Self.cacheDirectory(for: repo) else { return false }
        return Self.isModelDirectoryValid(modelDir)
    }

    func modelSizeOnDisk(repo: String) -> String {
        guard let modelDir = Self.cacheDirectory(for: repo),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: modelDir),
              size > 0
        else {
            return ""
        }
        return Self.byteFormatter.string(fromByteCount: Int64(size))
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
        guard let modelDir = Self.cacheDirectory(for: modelRepo) else {
            state = .error("Invalid model identifier")
            VoxtLog.error("Invalid custom LLM repo identifier: \(modelRepo)")
            return
        }
        state = Self.isModelDirectoryValid(modelDir) ? .downloaded : .notDownloaded
        VoxtLog.info("Custom LLM local model state refreshed: repo=\(modelRepo), downloaded=\(state == .downloaded)")
    }

    func downloadModel() async {
        if downloadTask != nil { return }

        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer { downloadTask = nil }
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

                let modelDir = Self.cacheDirectory(for: modelRepo)!
                try? FileManager.default.removeItem(at: modelDir)
                try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

                for (index, entry) in entries.enumerated() {
                    let progress = Progress(totalUnitCount: max(entry.size ?? 1, 1))
                    setDownloadingState(
                        progress: min(1, Double(completedBytes) / Double(totalBytes)),
                        completed: min(completedBytes, totalBytes),
                        total: totalBytes,
                        currentFile: entry.path,
                        completedFiles: index,
                        totalFiles: totalFiles
                    )

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

                    completedBytes += max(entry.size ?? progress.completedUnitCount, 0)
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
                state = .notDownloaded
                VoxtLog.warning("Custom LLM download cancelled: \(modelRepo)")
            } catch {
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
        guard downloadTask != nil else { return }
        VoxtLog.info("Custom LLM download cancellation requested: \(modelRepo)")
        downloadTask?.cancel()
        downloadTask = nil
        state = .notDownloaded
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
        if let modelDir = Self.cacheDirectory(for: repo) {
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
        sizeState = .loading
        let repo = modelRepo

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

    private static func cacheDirectory(for repo: String) -> URL? {
        guard let repoID = Repo.ID(rawValue: repo) else { return nil }
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        return HubCache.default.cacheDirectory
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

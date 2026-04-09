import Foundation
import HuggingFace
import Combine
import MLX
import MLXLMCommon

@MainActor
class CustomLLMModelManager: ObservableObject {
    private struct TextResultPayload: Decodable {
        let resultText: String
    }

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

    private var downloadedStateByRepo: [String: Bool] = [:]
    private var localSizeTextByRepo: [String: String] = [:]
    private var modelRepo: String
    private var hubBaseURL: URL
    private var downloadTask: Task<Void, Never>?
    private var downloadProgressTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private var inferenceContainer: ModelContainer?
    private var inferenceModelRepo: String?
    private var lastLoggedModelPresence: (repo: String, downloaded: Bool)?
    private var lastInvalidRepoLogged: String?
    private let idleUnloadDelay: Duration = .seconds(90)
    private var activeInferenceCount = 0

    init(modelRepo: String, hubBaseURL: URL = URL(string: "https://huggingface.co")!) {
        let repoSelection = CustomLLMRepoSelection.resolve(
            requestedRepo: modelRepo,
            supportedRepos: Self.availableModels.map(\.id),
            fallbackRepo: Self.defaultModelRepo
        )
        self.modelRepo = repoSelection.effectiveRepo
        self.hubBaseURL = hubBaseURL
        self.remoteSizeTextByRepo = Self.loadPersistedRemoteSizeCache()
        if repoSelection.didFallback {
            VoxtLog.warning("Unsupported custom LLM repo '\(modelRepo)' found in settings. Falling back to \(repoSelection.effectiveRepo).")
        }
        VoxtLog.info("Custom LLM manager initialized. repo=\(repoSelection.effectiveRepo), hub=\(hubBaseURL.absoluteString)")
        checkExistingModel()
    }

    var currentModelRepo: String { modelRepo }

    func enhance(_ rawText: String, systemPrompt: String) async throws -> String {
        let input = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return rawText }
        let request = CustomLLMRequestPlanBuilder.enhancement(
            input: input,
            systemPrompt: systemPrompt,
            repo: modelRepo,
            resultFallback: rawText,
            structuredOutputPrompt: structuredOutputPrompt(taskInstruction:input:)
        )
        return try await runLocalPromptRequest(request)
    }

    func enhance(userPrompt: String) async throws -> String {
        try await enhance(userPrompt: userPrompt, repo: modelRepo)
    }

    func enhance(userPrompt: String, repo: String) async throws -> String {
        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return "" }
        let request = CustomLLMRequestPlanBuilder.userPromptEnhancement(
            prompt: prompt,
            repo: repo
        )
        return try await runLocalPromptRequest(request)
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

    func rewrite(
        sourceText: String,
        dictatedPrompt: String,
        systemPrompt: String,
        modelRepo: String
    ) async throws -> String {
        let instruction = dictatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty || !source.isEmpty else { return sourceText }
        let result = try await runRewritePrompt(
            sourceText: source,
            dictatedPrompt: instruction,
            instructions: systemPrompt,
            modelRepo: modelRepo
        )
        return result.isEmpty ? sourceText : result
    }

    private func runTranslationPrompt(
        _ text: String,
        instructions: String,
        modelRepo: String
    ) async throws -> String {
        let request = CustomLLMRequestPlanBuilder.translation(
            text: text,
            instructions: instructions,
            repo: modelRepo,
            structuredOutputPrompt: structuredOutputPrompt(taskInstruction:input:)
        )
        return try await runLocalPromptRequest(request)
    }

    private func runRewritePrompt(
        sourceText: String,
        dictatedPrompt: String,
        instructions: String,
        modelRepo: String
    ) async throws -> String {
        let request = CustomLLMRequestPlanBuilder.rewrite(
            sourceText: sourceText,
            dictatedPrompt: dictatedPrompt,
            instructions: instructions,
            repo: modelRepo,
            structuredOutputPrompt: structuredOutputPrompt(taskInstruction:input:)
        )
        return try await runLocalPromptRequest(request)
    }

    private func generationParameters(for kind: CustomLLMTaskKind, inputLength: Int) -> GenerateParameters {
        let safeInput = max(1, inputLength)
        let estimated = Int(Double(safeInput) * kind.tokenBudgetMultiplier)
        let budget = max(96, min(estimated + 48, 320))
        return GenerateParameters(
            maxTokens: budget,
            temperature: 0.1,
            topP: 0.85
        )
    }

    private func runLocalPromptRequest(_ request: CustomLLMRequestPlan) async throws -> String {
        return try await withActiveInference {
            guard isModelDownloaded(repo: request.repo) else {
                throw NSError(
                    domain: "Voxt.CustomLLM",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Custom LLM model is not installed locally."]
                )
            }

            let container = try await container(for: request.repo)
            let behavior = CustomLLMModelBehaviorResolver.behavior(for: request.repo)
            let session = makeChatSession(
                container: container,
                instructions: request.instructions,
                repo: request.repo,
                behavior: behavior
            )
            let params = generationParameters(for: request.kind, inputLength: request.inputCharacterCount)
            session.generateParameters = params

            let startedAt = Date()
            VoxtLog.llm(startLogMessage(for: request, params: params, behavior: behavior))
            VoxtLog.llm(contentLogMessage(for: request))

            let response = try await session.respond(to: request.prompt)
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let cleaned = extractResultText(response)

            VoxtLog.llm(
                "Custom LLM \(request.kind.logLabel) completed. repo=\(request.repo), outputChars=\(cleaned.count), elapsedMs=\(elapsedMs)"
            )
            VoxtLog.llm(
                """
                Custom LLM \(request.kind.logLabel) output. repo=\(request.repo)
                [output]
                \(VoxtLog.llmPreview(cleaned))
                """
            )
            return cleaned.isEmpty ? request.resultFallback : cleaned
        }
    }

    private func startLogMessage(
        for request: CustomLLMRequestPlan,
        params: GenerateParameters,
        behavior: CustomLLMModelBehavior
    ) -> String {
        var suffix = ""
        if let mode = request.logMode {
            suffix = ", mode=\(mode)"
        }
        return "Custom LLM \(request.kind.logLabel) started. repo=\(request.repo), inputChars=\(request.inputCharacterCount), maxTokens=\(params.maxTokens ?? 0), temperature=\(params.temperature), topP=\(params.topP)\(suffix), family=\(behavior.family.logLabel), thinkingDisabled=\(behavior.disablesThinking)"
    }

    private func contentLogMessage(for request: CustomLLMRequestPlan) -> String {
        var lines = ["Custom LLM \(request.kind.logLabel) content. repo=\(request.repo)"]
        for section in request.contentLogSections {
            lines.append("[\(section.label)]")
            lines.append(VoxtLog.llmPreview(section.content))
        }
        return lines.joined(separator: "\n")
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
        let repoSelection = CustomLLMRepoSelection.resolve(
            requestedRepo: repo,
            supportedRepos: Self.availableModels.map(\.id),
            fallbackRepo: Self.defaultModelRepo
        )
        guard repoSelection.effectiveRepo != modelRepo else { return }
        if repoSelection.didFallback {
            VoxtLog.warning("Unsupported custom LLM repo '\(repo)' requested. Falling back to \(repoSelection.effectiveRepo).")
        }
        VoxtLog.info("Custom LLM model changed: \(modelRepo) -> \(repoSelection.effectiveRepo)")
        modelRepo = repoSelection.effectiveRepo
        releaseInferenceResources(resetActiveInferenceCount: true)
        lastLoggedModelPresence = nil
        lastInvalidRepoLogged = nil
        checkExistingModel()
        fetchRemoteSize()
    }

    static func isSupportedModelRepo(_ repo: String) -> Bool {
        CustomLLMRepoSelection.isSupported(repo: repo, supportedRepos: availableModels.map(\.id))
    }

    func updateHubBaseURL(_ url: URL) {
        guard url != hubBaseURL else { return }
        VoxtLog.info("Custom LLM hub base URL changed: \(hubBaseURL.absoluteString) -> \(url.absoluteString)")
        hubBaseURL = url
        fetchRemoteSize()
    }

    func isModelDownloaded(repo: String) -> Bool {
        if let cached = downloadedStateByRepo[repo] {
            return cached
        }
        guard let modelDir = cacheDirectory(for: repo) else { return false }
        let isDownloaded = Self.isModelDirectoryValid(modelDir)
        downloadedStateByRepo[repo] = isDownloaded
        return isDownloaded
    }

    func modelSizeOnDisk(repo: String) -> String {
        if let cached = localSizeTextByRepo[repo] {
            return cached
        }
        guard let modelDir = cacheDirectory(for: repo),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: modelDir),
              size > 0
        else {
            return ""
        }
        let text = Self.byteFormatter.string(fromByteCount: Int64(size))
        localSizeTextByRepo[repo] = text
        return text
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

    func ensureRemoteSizeLoaded(repo: String) {
        guard CustomLLMRemoteSizeCache.shouldPrefetch(repo: repo, cache: remoteSizeTextByRepo) else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.loadRemoteSize(for: repo, updatesVisibleState: false)
        }
    }

    func checkExistingModel() {
        guard let modelDir = cacheDirectory(for: modelRepo) else {
            state = .error("Invalid model identifier")
            downloadedStateByRepo[modelRepo] = false
            if lastInvalidRepoLogged != modelRepo {
                VoxtLog.error("Invalid custom LLM repo identifier: \(modelRepo)")
                lastInvalidRepoLogged = modelRepo
            }
            return
        }
        lastInvalidRepoLogged = nil
        let isDownloaded = Self.isModelDirectoryValid(modelDir)
        downloadedStateByRepo[modelRepo] = isDownloaded
        state = isDownloaded ? .downloaded : .notDownloaded
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

                    let destination = try destinationFileURL(for: entry.path, under: modelDir)
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
                        to: destination,
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
        invalidateLocalCache(for: repo)
        if repo == inferenceModelRepo {
            releaseInferenceResources(resetActiveInferenceCount: true)
        }
        if repo == modelRepo {
            state = .notDownloaded
        }
    }

    private func invalidateLocalCache(for repo: String) {
        downloadedStateByRepo.removeValue(forKey: repo)
        localSizeTextByRepo.removeValue(forKey: repo)
    }

    private func fetchRemoteSize() {
        sizeTask?.cancel()
        let repo = modelRepo
        if let cachedState = CustomLLMRemoteSizeCache.cachedState(for: repo, cache: remoteSizeTextByRepo) {
            sizeState = cachedState
            return
        }
        sizeState = .loading

        sizeTask = Task { [weak self] in
            guard let self else { return }
            await loadRemoteSize(for: repo, updatesVisibleState: true)
        }
    }

    func prefetchAllModelSizes() {
        guard prefetchTask == nil else { return }
        let repos = Self.availableModels
            .map(\.id)
            .filter { CustomLLMRemoteSizeCache.shouldPrefetch(repo: $0, cache: remoteSizeTextByRepo) }
        guard !repos.isEmpty else { return }

        prefetchTask = Task(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.prefetchTask = nil
                }
            }
            for repo in repos {
                guard let self else { return }
                await self.loadRemoteSize(for: repo, updatesVisibleState: false)
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

    private func destinationFileURL(for entryPath: String, under directory: URL) throws -> URL {
        let base = directory.standardizedFileURL
        let destination = base.appendingPathComponent(entryPath).standardizedFileURL
        let basePrefix = base.path.hasSuffix("/") ? base.path : "\(base.path)/"
        guard destination.path.hasPrefix(basePrefix) else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model file path: \(entryPath)"]
            )
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return destination
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

    private func makeChatSession(
        container: ModelContainer,
        instructions: String,
        repo: String,
        behavior: CustomLLMModelBehavior
    ) -> ChatSession {
        let session = ChatSession(
            container,
            instructions: instructions,
            additionalContext: behavior.additionalContext
        )
        if behavior.disablesThinking {
            VoxtLog.llm("Custom LLM thinking disabled for repo=\(repo) using chat-template additionalContext.")
        }
        return session
    }

    private func structuredOutputPrompt(taskInstruction: String, input: String) -> String {
        """
        \(taskInstruction)

        Return only valid JSON with exactly one key:
        {"resultText":"..."}

        Input:
        \(input)
        """
    }

    private func extractResultText(_ output: String) -> String {
        let normalized = sanitizeModelOutput(output)
        if let parsed = decodeStructuredResultText(from: normalized) {
            return parsed
        }
        return normalized
    }

    private func decodeStructuredResultText(from output: String) -> String? {
        for candidate in jsonCandidates(from: output) {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(TextResultPayload.self, from: data) else {
                continue
            }
            let text = CustomLLMOutputSanitizer.normalizeResultText(decoded.resultText)
            if !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private func jsonCandidates(from output: String) -> [String] {
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = [normalized]

        let unfenced = CustomLLMOutputSanitizer.unwrapCodeFenceIfNeeded(normalized)
        if unfenced != normalized {
            candidates.append(unfenced)
        }

        if let jsonObject = Self.extractFirstJSONObject(in: unfenced),
           !candidates.contains(jsonObject) {
            candidates.append(jsonObject)
        }

        return candidates
    }

    private static func extractFirstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }

    private func sanitizeModelOutput(_ output: String) -> String {
        let cleaned = CustomLLMOutputSanitizer.normalizeResultText(output)
        if cleaned != output.trimmingCharacters(in: .whitespacesAndNewlines) {
            VoxtLog.llm(
                """
                Custom LLM output sanitized.
                [raw]
                \(VoxtLog.llmPreview(output))
                [cleaned]
                \(VoxtLog.llmPreview(cleaned))
                """
            )
        }
        return cleaned
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

    private func withActiveInference<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        beginActiveInference()
        defer { endActiveInference() }
        return try await operation()
    }

    private func beginActiveInference() {
        activeInferenceCount += 1
        cancelIdleUnloadTask()
    }

    private func endActiveInference() {
        activeInferenceCount = max(0, activeInferenceCount - 1)
        guard activeInferenceCount == 0 else { return }
        Memory.clearCache()
        scheduleIdleUnloadIfNeeded()
    }

    private func scheduleIdleUnloadIfNeeded() {
        guard inferenceContainer != nil else { return }
        idleUnloadTask?.cancel()
        let expectedRepo = inferenceModelRepo
        let delay = idleUnloadDelay
        idleUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self else { return }
            await MainActor.run {
                self.unloadInferenceContainerIfIdle(expectedRepo: expectedRepo)
            }
        }
    }

    private func cancelIdleUnloadTask() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    private func releaseInferenceResources(resetActiveInferenceCount: Bool) {
        cancelIdleUnloadTask()
        inferenceContainer = nil
        inferenceModelRepo = nil
        if resetActiveInferenceCount {
            activeInferenceCount = 0
        }
        Memory.clearCache()
    }

    private func updateRemoteSizeCache(
        for repo: String,
        bytes _: Int64,
        text: String
    ) {
        remoteSizeTextByRepo = CustomLLMRemoteSizeCache.updatedCache(
            remoteSizeTextByRepo,
            repo: repo,
            text: text
        )
        Self.savePersistedRemoteSizeCache(remoteSizeTextByRepo)
    }

    private func markRemoteSizeUnavailable(
        for repo: String,
        logMessage: String
    ) {
        remoteSizeTextByRepo = CustomLLMRemoteSizeCache.updatedCache(
            remoteSizeTextByRepo,
            repo: repo,
            text: CustomLLMRemoteSizeCache.unknownText
        )
        VoxtLog.warning(logMessage)
    }

    private func loadRemoteSize(
        for repo: String,
        updatesVisibleState: Bool
    ) async {
        do {
            let info = try await MLXModelDownloadSupport.fetchModelSizeInfo(
                repo: repo,
                baseURL: hubBaseURL,
                userAgent: Self.hubUserAgent,
                byteFormatter: Self.byteFormatter
            )
            if Task.isCancelled { return }
            updateRemoteSizeCache(for: repo, bytes: info.bytes, text: info.text)
            if updatesVisibleState {
                sizeState = .ready(bytes: info.bytes, text: info.text)
            }
        } catch is CancellationError {
            return
        } catch {
            markRemoteSizeUnavailable(
                for: repo,
                logMessage: "Failed to \(updatesVisibleState ? "fetch" : "prefetch") custom LLM remote size: repo=\(repo), error=\(error.localizedDescription)"
            )
            if updatesVisibleState {
                sizeState = .error("Size unavailable")
            }
        }
    }

    private func unloadInferenceContainerIfIdle(expectedRepo: String?) {
        guard activeInferenceCount == 0 else { return }
        guard inferenceContainer != nil, inferenceModelRepo == expectedRepo else { return }

        releaseInferenceResources(resetActiveInferenceCount: false)
        VoxtLog.info("Custom LLM model released after idle period.", verbose: true)
    }
}

struct CustomLLMModelBehavior: Equatable {
    let family: CustomLLMModelFamily
    let disablesThinking: Bool

    var additionalContext: [String: any Sendable]? {
        guard disablesThinking else { return nil }
        return ["enable_thinking": false]
    }
}

enum CustomLLMModelBehaviorResolver {
    static func behavior(for repo: String) -> CustomLLMModelBehavior {
        let family = CustomLLMModelFamily.resolve(for: repo)
        return CustomLLMModelBehavior(
            family: family,
            disablesThinking: family == .qwen3
        )
    }
}

enum CustomLLMTaskKind: Equatable {
    case enhancement
    case translation
    case rewrite

    var logLabel: String {
        switch self {
        case .enhancement: return "enhance"
        case .translation: return "translate"
        case .rewrite: return "rewrite"
        }
    }

    var tokenBudgetMultiplier: Double {
        switch self {
        case .enhancement:
            return 1.10
        case .translation, .rewrite:
            return 1.35
        }
    }
}

struct CustomLLMRepoSelection: Equatable {
    let requestedRepo: String
    let effectiveRepo: String

    var didFallback: Bool { requestedRepo != effectiveRepo }

    static func resolve(
        requestedRepo: String,
        supportedRepos: [String],
        fallbackRepo: String
    ) -> CustomLLMRepoSelection {
        let effectiveRepo = isSupported(repo: requestedRepo, supportedRepos: supportedRepos)
            ? requestedRepo
            : fallbackRepo
        return CustomLLMRepoSelection(
            requestedRepo: requestedRepo,
            effectiveRepo: effectiveRepo
        )
    }

    static func isSupported(repo: String, supportedRepos: [String]) -> Bool {
        supportedRepos.contains(repo)
    }
}

enum CustomLLMRemoteSizeCache {
    static let unknownText = "Unknown"

    static func cachedState(
        for repo: String,
        cache: [String: String]
    ) -> CustomLLMModelManager.ModelSizeState? {
        guard let cachedText = cache[repo], cachedText != unknownText else { return nil }
        return .ready(bytes: 0, text: cachedText)
    }

    static func shouldPrefetch(
        repo: String,
        cache: [String: String]
    ) -> Bool {
        cache[repo] == nil
    }

    static func updatedCache(
        _ cache: [String: String],
        repo: String,
        text: String
    ) -> [String: String] {
        var updated = cache
        updated[repo] = text
        return updated
    }
}

struct CustomLLMLogSection: Equatable {
    let label: String
    let content: String
}

struct CustomLLMRequestPlan: Equatable {
    let kind: CustomLLMTaskKind
    let repo: String
    let instructions: String
    let prompt: String
    let inputCharacterCount: Int
    let logMode: String?
    let contentLogSections: [CustomLLMLogSection]
    let resultFallback: String
}

enum CustomLLMRequestPlanBuilder {
    static func enhancement(
        input: String,
        systemPrompt: String,
        repo: String,
        resultFallback: String,
        structuredOutputPrompt: (String, String) -> String
    ) -> CustomLLMRequestPlan {
        let prompt = structuredOutputPrompt(
            "Clean up this transcription while preserving meaning and style.",
            input
        )
        return CustomLLMRequestPlan(
            kind: .enhancement,
            repo: repo,
            instructions: systemPrompt,
            prompt: prompt,
            inputCharacterCount: input.count,
            logMode: nil,
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: systemPrompt),
                CustomLLMLogSection(label: "input", content: input),
                CustomLLMLogSection(label: "request_content", content: prompt)
            ],
            resultFallback: resultFallback
        )
    }

    static func userPromptEnhancement(
        prompt: String,
        repo: String
    ) -> CustomLLMRequestPlan {
        CustomLLMRequestPlan(
            kind: .enhancement,
            repo: repo,
            instructions: "",
            prompt: prompt,
            inputCharacterCount: prompt.count,
            logMode: "userMessage",
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: "<empty>"),
                CustomLLMLogSection(label: "input", content: prompt)
            ],
            resultFallback: ""
        )
    }

    static func translation(
        text: String,
        instructions: String,
        repo: String,
        structuredOutputPrompt: (String, String) -> String
    ) -> CustomLLMRequestPlan {
        let prompt = structuredOutputPrompt(
            "Process the input according to the instructions.",
            text
        )
        return CustomLLMRequestPlan(
            kind: .translation,
            repo: repo,
            instructions: instructions,
            prompt: prompt,
            inputCharacterCount: text.count,
            logMode: nil,
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: instructions),
                CustomLLMLogSection(label: "input", content: text),
                CustomLLMLogSection(label: "request_content", content: prompt)
            ],
            resultFallback: ""
        )
    }

    static func rewrite(
        sourceText: String,
        dictatedPrompt: String,
        instructions: String,
        repo: String,
        structuredOutputPrompt: (String, String) -> String
    ) -> CustomLLMRequestPlan {
        let combinedInput = """
        Spoken instruction:
        \(dictatedPrompt)

        Selected source text:
        \(sourceText)
        """
        let prompt = structuredOutputPrompt(
            "Produce the final text to insert according to the instructions.",
            combinedInput
        )
        return CustomLLMRequestPlan(
            kind: .rewrite,
            repo: repo,
            instructions: instructions,
            prompt: prompt,
            inputCharacterCount: combinedInput.count,
            logMode: nil,
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: instructions),
                CustomLLMLogSection(label: "input", content: combinedInput),
                CustomLLMLogSection(label: "request_content", content: prompt)
            ],
            resultFallback: ""
        )
    }
}

enum CustomLLMModelFamily: Equatable {
    case qwen2
    case qwen3
    case glm4
    case llama
    case mistral
    case gemma
    case other

    var logLabel: String {
        switch self {
        case .qwen2: return "qwen2"
        case .qwen3: return "qwen3"
        case .glm4: return "glm4"
        case .llama: return "llama"
        case .mistral: return "mistral"
        case .gemma: return "gemma"
        case .other: return "other"
        }
    }

    static func resolve(for repo: String) -> CustomLLMModelFamily {
        let normalizedRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRepo.contains("qwen3") { return .qwen3 }
        if normalizedRepo.contains("qwen2") { return .qwen2 }
        if normalizedRepo.contains("glm-4") || normalizedRepo.contains("glm4") { return .glm4 }
        if normalizedRepo.contains("llama") { return .llama }
        if normalizedRepo.contains("mistral") { return .mistral }
        if normalizedRepo.contains("gemma") { return .gemma }
        return .other
    }
}


enum CustomLLMOutputSanitizer {
    static func normalizeResultText(_ output: String) -> String {
        var cleaned = output
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: (cleaned as NSString).length)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        cleaned = unwrapCodeFenceIfNeeded(cleaned)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func unwrapCodeFenceIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
            return trimmed
        }
        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return trimmed }
        lines.removeFirst()
        if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

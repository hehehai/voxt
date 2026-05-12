import Foundation
import HuggingFace
import Combine
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

private struct LocalTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

private struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return LocalTokenizerBridge(tokenizer)
    }
}

@MainActor
class CustomLLMModelManager: ObservableObject {
    private struct TextResultPayload: Decodable {
        let resultText: String
    }

    static let defaultHubBaseURL = URL(string: "https://huggingface.co")!
    static let mirrorHubBaseURL = URL(string: "https://hf-mirror.com")!
    static let hubUserAgent = "Voxt/1.0 (CustomLLM)"

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
        case error(String)
    }

    private enum DownloadStopAction {
        case pause
        case cancel
    }

    enum ModelSizeState: Equatable {
        case unknown
        case loading
        case ready(bytes: Int64, text: String)
        case error(String)
    }

    typealias ModelOption = CustomLLMModelCatalog.Option

    nonisolated static let defaultModelRepo = CustomLLMModelCatalog.defaultModelRepo
    nonisolated static let availableModels = CustomLLMModelCatalog.availableModels
    nonisolated static let supportedModels = CustomLLMModelCatalog.supportedModels

    @Published private(set) var state: ModelState = .notDownloaded
    @Published private(set) var sizeState: ModelSizeState = .unknown
    @Published private(set) var remoteSizeTextByRepo: [String: String] = [:]
    @Published private(set) var pausedStatusMessage: String?
    @Published private(set) var lastRunDiagnostics: CustomLLMRunDiagnostics?
    @Published var generationTuning = CustomLLMGenerationTuning.default

    private var downloadedStateByRepo: [String: Bool] = [:]
    private var downloadedStateCachePrimed = false
    private var localSizeTextByRepo: [String: String] = [:]
    private var modelRepo: String
    private var hubBaseURL: URL
    private var downloadTask: Task<Void, Never>?
    private var downloadProgressTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private var downloadStopAction: DownloadStopAction?
    private var inferenceContainer: ModelContainer?
    private var inferenceModelRepo: String?
    private var lastLoggedModelPresence: (repo: String, downloaded: Bool)?
    private var lastInvalidRepoLogged: String?
    private let idleUnloadDelay: Duration = .seconds(90)
    private var activeInferenceCount = 0
    private var isMemoryOptimizationEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKey.localModelMemoryOptimizationEnabled) as? Bool ?? true
    }

    init(modelRepo: String, hubBaseURL: URL = URL(string: "https://huggingface.co")!) {
        let repoSelection = Self.resolveModelRepo(modelRepo)
        let repoWasSupported = Self.isSupportedModelRepo(modelRepo)
        self.modelRepo = repoSelection.effectiveRepo
        self.hubBaseURL = hubBaseURL
        self.remoteSizeTextByRepo = CustomLLMModelStorageSupport.loadPersistedRemoteSizeCache()
        if !repoWasSupported {
            VoxtLog.warning("Unsupported custom LLM repo '\(modelRepo)' found in settings. Falling back to \(repoSelection.effectiveRepo).")
        } else if repoSelection.effectiveRepo != modelRepo {
            VoxtLog.info("Canonicalized custom LLM repo '\(modelRepo)' -> '\(repoSelection.effectiveRepo)'")
        }
        VoxtLog.model("Custom LLM manager initialized. repo=\(repoSelection.effectiveRepo), hub=\(hubBaseURL.absoluteString)")
        checkExistingModel()
    }

    var currentModelRepo: String { modelRepo }

    func refreshMemoryOptimizationPolicy() {
        guard inferenceContainer != nil else {
            cancelIdleUnloadTask()
            return
        }
        guard activeInferenceCount == 0 else { return }
        if isMemoryOptimizationEnabled {
            scheduleIdleUnloadIfNeeded()
        } else {
            cancelIdleUnloadTask()
        }
    }

    func isModelLoaded(repo: String) -> Bool {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        return inferenceContainer != nil && inferenceModelRepo == canonicalRepo
    }

    func prewarmModel(repo: String) async throws {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        try await withActiveInference {
            guard isModelDownloaded(repo: canonicalRepo) else {
                throw NSError(
                    domain: "Voxt.CustomLLM",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Custom LLM model is not installed locally."]
                )
            }
            _ = try await container(for: canonicalRepo)
        }
    }

    func enhance(_ rawText: String, systemPrompt: String) async throws -> String {
        try await enhance(rawText, systemPrompt: systemPrompt, modelRepo: modelRepo)
    }

    func enhance(_ rawText: String, systemPrompt: String, modelRepo: String) async throws -> String {
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

    func dictionaryHistoryScanTerms(userPrompt: String, repo: String) async throws -> [String] {
        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return [] }
        let request = CustomLLMRequestPlanBuilder.dictionaryHistoryScan(
            prompt: prompt,
            repo: repo,
            structuredOutputPrompt: dictionaryHistoryScanStructuredOutputPrompt(_:)
        )
        let rawOutput = try await runLocalPromptRequest(request)
        return try DictionaryHistoryScanResponseParser.parseTerms(from: rawOutput)
    }

    func executeCompiledRequest(
        _ request: LLMCompiledRequest,
        repo: String,
        onPartialText: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return request.fallbackText }
        let compiledPlan = CustomLLMRequestPlanBuilder.compiled(request: request, repo: repo)
        let result = try await runLocalPromptRequest(compiledPlan, onPartialText: onPartialText)
        return result.isEmpty ? request.fallbackText : result
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

    func translate(
        userPrompt: String,
        fallbackText: String,
        modelRepo: String
    ) async throws -> String {
        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return fallbackText }
        let request = CustomLLMRequestPlanBuilder.userPromptTranslation(
            prompt: prompt,
            repo: modelRepo,
            resultFallback: fallbackText
        )
        let translated = try await runLocalPromptRequest(request)
        return translated.isEmpty ? fallbackText : translated
    }

    func rewrite(
        sourceText: String,
        dictatedPrompt: String,
        systemPrompt: String,
        modelRepo: String,
        onPartialText: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let instruction = dictatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty || !source.isEmpty else { return sourceText }
        let result = try await runRewritePrompt(
            sourceText: source,
            dictatedPrompt: instruction,
            instructions: systemPrompt,
            modelRepo: modelRepo,
            onPartialText: onPartialText
        )
        return result.isEmpty ? sourceText : result
    }

    func rewrite(
        userPrompt: String,
        fallbackText: String,
        modelRepo: String,
        onPartialText: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return fallbackText }
        let request = CustomLLMRequestPlanBuilder.userPromptRewrite(
            prompt: prompt,
            repo: modelRepo,
            resultFallback: fallbackText
        )
        let result = try await runLocalPromptRequest(request, onPartialText: onPartialText)
        return result.isEmpty ? fallbackText : result
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
        modelRepo: String,
        onPartialText: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let request = CustomLLMRequestPlanBuilder.rewrite(
            sourceText: sourceText,
            dictatedPrompt: dictatedPrompt,
            instructions: instructions,
            repo: modelRepo,
            structuredOutputPrompt: structuredOutputPrompt(taskInstruction:input:)
        )
        return try await runLocalPromptRequest(request, onPartialText: onPartialText)
    }

    private func generationParameters(
        for request: CustomLLMRequestPlan,
        behavior: CustomLLMModelBehavior
    ) -> GenerateParameters {
        let safeInput = max(1, request.inputCharacterCount)
        let estimated = Int(Double(safeInput) * request.kind.tokenBudgetMultiplier)
        let totalPromptCharacters = request.instructions.count + request.prompt.count
        let budget: Int?
        if let override = generationTuning.maxTokensOverride {
            budget = max(1, override)
        } else if let override = request.maxTokensOverride {
            budget = max(1, override)
        } else {
            budget = defaultOutputTokenBudget(for: request.kind, estimated: estimated)
        }

        let prefillStepSize: Int
        if let override = generationTuning.prefillStepSizeOverride {
            prefillStepSize = override
        } else {
            switch totalPromptCharacters {
            case ..<1000:
                prefillStepSize = 256
            case ..<3000:
                prefillStepSize = 512
            default:
                prefillStepSize = 768
            }
        }

        let repetitionPenalty: Float? =
            behavior.family == .qwen3 ? 1.05 : nil

        return GenerateParameters(
            maxTokens: budget,
            temperature: 0,
            topP: 1.0,
            topK: 0,
            minP: 0,
            repetitionPenalty: repetitionPenalty,
            repetitionContextSize: 32,
            prefillStepSize: prefillStepSize
        )
    }

    private func defaultOutputTokenBudget(for kind: CustomLLMTaskKind, estimated: Int) -> Int {
        switch kind {
        case .enhancement:
            return max(128, min(estimated + 128, 1024))
        case .translation:
            return max(128, min(estimated + 160, 1024))
        case .rewrite:
            return max(256, min(estimated + 192, 1536))
        case .dictionaryHistoryScan:
            return max(256, min(estimated + 96, 2048))
        }
    }

    private func runLocalPromptRequest(
        _ request: CustomLLMRequestPlan,
        onPartialText: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        return try await withActiveInference {
            guard isModelDownloaded(repo: request.repo) else {
                throw NSError(
                    domain: "Voxt.CustomLLM",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Custom LLM model is not installed locally."]
                )
            }

            let overallStartedAt = Date()
            let containerSnapshot = try await profiledContainer(for: request.repo)
            let container = containerSnapshot.container
            let behavior = CustomLLMModelBehaviorResolver.behavior(for: request.repo)
            let session = makeChatSession(
                container: container,
                instructions: request.instructions,
                repo: request.repo,
                behavior: behavior
            )
            let params = generationParameters(for: request, behavior: behavior)
            session.generateParameters = params

            let modelStartedAt = Date()
            let setupMs = Int(modelStartedAt.timeIntervalSince(overallStartedAt) * 1000) - containerSnapshot.elapsedMs
            VoxtLog.llm(startLogMessage(for: request, params: params, behavior: behavior))
            VoxtLog.llm(contentLogMessage(for: request))

            var aggregated = ""
            var firstChunkLatencyMs: Int?
            var completionInfo: GenerateCompletionInfo?
            var repetitionStop: LLMOutputRepetition?
            let repetitionGuard = LLMOutputRepetitionGuard()
            for try await event in session.streamDetails(
                to: request.prompt,
                images: [],
                videos: []
            ) {
                switch event {
                case .chunk(let chunk):
                    if firstChunkLatencyMs == nil, !chunk.isEmpty {
                        firstChunkLatencyMs = Int(Date().timeIntervalSince(modelStartedAt) * 1000)
                    }
                    aggregated += chunk
                    if let repetition = repetitionGuard.repeatedSuffix(in: aggregated) {
                        repetitionStop = repetition
                        aggregated = repetition.truncatedText
                        VoxtLog.warning(
                            "Custom LLM \(request.kind.logLabel) repetition guard stopped generation. repo=\(request.repo), repeatedUnitChars=\(repetition.repeatedUnit.count), repetitions=\(repetition.repetitionCount), outputChars=\(aggregated.count)"
                        )
                        break
                    }
                    if let onPartialText {
                        let preview = CustomLLMOutputSanitizer.normalizeResultText(aggregated)
                        if !preview.isEmpty {
                            onPartialText(preview)
                        }
                    }
                case .info(let info):
                    completionInfo = info
                case .toolCall:
                    continue
                }
            }
            let response = aggregated
            let modelElapsedMs = Int(Date().timeIntervalSince(modelStartedAt) * 1000)
            let totalElapsedMs = Int(Date().timeIntervalSince(overallStartedAt) * 1000)
            if repetitionStop != nil, let onPartialText {
                let preview = CustomLLMOutputSanitizer.normalizeResultText(aggregated)
                if !preview.isEmpty {
                    onPartialText(preview)
                }
            }
            let cleaned: String
            switch request.responseExtractionMode {
            case .textResultPayloadOrNormalizedText:
                cleaned = extractResultText(response)
            case .normalizedRawText:
                cleaned = sanitizeModelOutput(response)
            }

            VoxtLog.llm(
                "Custom LLM \(request.kind.logLabel) completed. repo=\(request.repo), outputChars=\(cleaned.count), elapsedMs=\(modelElapsedMs), totalElapsedMs=\(totalElapsedMs)"
            )
            var diagnostics = CustomLLMRunDiagnostics(
                repo: request.repo,
                taskLabel: request.kind.logLabel,
                containerLoadSource: containerSnapshot.source,
                containerLoadMs: containerSnapshot.elapsedMs,
                setupMs: max(0, setupMs),
                modelElapsedMs: modelElapsedMs,
                totalElapsedMs: totalElapsedMs,
                firstChunkMs: firstChunkLatencyMs,
                overallFirstChunkMs: firstChunkLatencyMs.map { max(0, containerSnapshot.elapsedMs + max(0, setupMs) + $0) },
                promptTokens: nil,
                completionTokens: nil,
                prefillMs: nil,
                generationMs: nil,
                modelOverheadMs: nil,
                totalOverheadMs: nil
            )
            if let completionInfo {
                let firstChunkText = firstChunkLatencyMs.map(String.init) ?? "n/a"
                let promptTPS = String(format: "%.1f", completionInfo.promptTokensPerSecond)
                let generationTPS = String(format: "%.1f", completionInfo.tokensPerSecond)
                let prefillMs = Int((completionInfo.promptTime * 1000).rounded())
                let generationMs = Int((completionInfo.generateTime * 1000).rounded())
                let modelOverheadMs = max(0, modelElapsedMs - prefillMs - generationMs)
                let totalOverheadMs = max(0, totalElapsedMs - prefillMs - generationMs)
                diagnostics = CustomLLMRunDiagnostics(
                    repo: request.repo,
                    taskLabel: request.kind.logLabel,
                    containerLoadSource: containerSnapshot.source,
                    containerLoadMs: containerSnapshot.elapsedMs,
                    setupMs: max(0, setupMs),
                    modelElapsedMs: modelElapsedMs,
                    totalElapsedMs: totalElapsedMs,
                    firstChunkMs: firstChunkLatencyMs,
                    overallFirstChunkMs: firstChunkLatencyMs.map { max(0, containerSnapshot.elapsedMs + max(0, setupMs) + $0) },
                    promptTokens: completionInfo.promptTokenCount,
                    completionTokens: completionInfo.generationTokenCount,
                    prefillMs: prefillMs,
                    generationMs: generationMs,
                    modelOverheadMs: modelOverheadMs,
                    totalOverheadMs: totalOverheadMs
                )
                VoxtLog.llm(
                    "Custom LLM \(request.kind.logLabel) metrics. repo=\(request.repo), containerSource=\(containerSnapshot.source.rawValue), containerLoadMs=\(containerSnapshot.elapsedMs), setupMs=\(max(0, setupMs)), firstChunkMs=\(firstChunkText), overallFirstChunkMs=\(diagnostics.overallFirstChunkMs.map(String.init) ?? "n/a"), promptTokens=\(completionInfo.promptTokenCount), generationTokens=\(completionInfo.generationTokenCount), prefillMs=\(prefillMs), generationMs=\(generationMs), modelOverheadMs=\(modelOverheadMs), totalOverheadMs=\(totalOverheadMs), promptTPS=\(promptTPS), generationTPS=\(generationTPS), stopReason=\(completionInfo.stopReason)"
                )
            }
            lastRunDiagnostics = diagnostics
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
        return "Custom LLM \(request.kind.logLabel) started. repo=\(request.repo), inputChars=\(request.inputCharacterCount), maxTokens=\(params.maxTokens ?? 0), temperature=\(params.temperature), topP=\(params.topP), prefillStep=\(params.prefillStepSize)\(suffix), family=\(behavior.family.logLabel), thinkingDisabled=\(behavior.disablesThinking)"
    }

    private func contentLogMessage(for request: CustomLLMRequestPlan) -> String {
        var lines = ["Custom LLM \(request.kind.logLabel) content. repo=\(request.repo)"]
        for section in request.contentLogSections {
            lines.append("[\(section.label)]")
            lines.append(VoxtLog.llmPreview(section.content))
        }
        return lines.joined(separator: "\n")
    }

    private func profiledContainer(for repo: String) async throws -> (
        container: ModelContainer,
        source: CustomLLMContainerLoadSource,
        elapsedMs: Int
    ) {
        let startedAt = Date()
        if let cached = inferenceContainer, inferenceModelRepo == repo {
            return (
                cached,
                .reusedLoaded,
                Int(Date().timeIntervalSince(startedAt) * 1000)
            )
        }

        let container = try await container(for: repo)
        return (
            container,
            .loadedFromDisk,
            Int(Date().timeIntervalSince(startedAt) * 1000)
        )
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
        let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
            ?? Bundle.main.object(forInfoDictionaryKey: "HF_TOKEN") as? String
        await CustomLLMModelDownloadSupport.repairMissingChatTemplateIfNeeded(
            repo: repo,
            directory: directory,
            preferredBaseURL: hubBaseURL,
            mirrorBaseURL: Self.mirrorHubBaseURL,
            userAgent: Self.hubUserAgent,
            token: token
        )
        let container = try await loadModelContainer(
            from: directory,
            using: LocalTokenizerLoader()
        )
        inferenceContainer = container
        inferenceModelRepo = repo
        return container
    }

    func displayTitle(for repo: String) -> String {
        CustomLLMModelCatalog.displayTitle(for: repo)
    }

    func description(for repo: String) -> String? {
        CustomLLMModelCatalog.description(for: repo)
    }

    nonisolated static func ratingText(for repo: String) -> String {
        CustomLLMModelCatalog.ratingText(for: repo)
    }

    nonisolated static func catalogTagKeys(for repo: String) -> [String] {
        CustomLLMModelCatalog.catalogTagKeys(for: repo)
    }

    nonisolated static func fallbackRemoteSizeText(repo: String) -> String? {
        CustomLLMModelCatalog.fallbackRemoteSizeText(repo: repo)
    }

    nonisolated static func canonicalModelRepo(_ repo: String) -> String {
        CustomLLMModelCatalog.canonicalModelRepo(repo)
    }

    nonisolated static func displayModels(including repo: String? = nil) -> [ModelOption] {
        CustomLLMModelCatalog.displayModels(including: repo)
    }

    nonisolated static func releaseStatus(for repo: String) -> CustomLLMModelCatalog.ReleaseStatus {
        CustomLLMModelCatalog.releaseStatus(for: repo)
    }

    func updateModel(repo: String) {
        let repoSelection = Self.resolveModelRepo(repo)
        let repoWasSupported = Self.isSupportedModelRepo(repo)
        guard repoSelection.effectiveRepo != modelRepo else { return }
        if !repoWasSupported {
            VoxtLog.warning("Unsupported custom LLM repo '\(repo)' requested. Falling back to \(repoSelection.effectiveRepo).")
        } else if repoSelection.effectiveRepo != repo {
            VoxtLog.info("Canonicalized custom LLM repo '\(repo)' -> '\(repoSelection.effectiveRepo)'")
        }
            VoxtLog.model("Custom LLM model changed: \(modelRepo) -> \(repoSelection.effectiveRepo)")
        modelRepo = repoSelection.effectiveRepo
        releaseInferenceResources(resetActiveInferenceCount: true)
        lastLoggedModelPresence = nil
        lastInvalidRepoLogged = nil
        checkExistingModel()
        fetchRemoteSize()
    }

    static func isSupportedModelRepo(_ repo: String) -> Bool {
        CustomLLMModelCatalog.isSupportedModelRepo(repo)
    }

    private nonisolated static func resolveModelRepo(_ requestedRepo: String) -> CustomLLMRepoSelection {
        guard CustomLLMModelCatalog.isSupportedModelRepo(requestedRepo) else {
            return CustomLLMRepoSelection(
                requestedRepo: requestedRepo,
                effectiveRepo: defaultModelRepo
            )
        }
        return CustomLLMRepoSelection(
            requestedRepo: requestedRepo,
            effectiveRepo: CustomLLMModelCatalog.canonicalModelRepo(requestedRepo)
        )
    }

    func updateHubBaseURL(_ url: URL) {
        guard url != hubBaseURL else { return }
        VoxtLog.model("Custom LLM hub base URL changed: \(hubBaseURL.absoluteString) -> \(url.absoluteString)")
        hubBaseURL = url
        fetchRemoteSize()
    }

    func isModelDownloaded(repo: String) -> Bool {
        primeDownloadedStateCacheIfNeeded()
        if let cached = downloadedStateByRepo[repo] {
            return cached
        }
        guard let modelDir = cacheDirectory(for: repo) else { return false }
        let isDownloaded = CustomLLMModelStorageSupport.isModelDirectoryValid(modelDir)
        downloadedStateByRepo[repo] = isDownloaded
        return isDownloaded
    }

    func hasResumableDownload(repo: String) -> Bool {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard !isModelDownloaded(repo: canonicalRepo),
              let modelDir = cacheDirectory(for: canonicalRepo),
              FileManager.default.fileExists(atPath: modelDir.path) else {
            return false
        }
        return FileManager.default.directoryContainsRegularFiles(at: modelDir)
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
        let text = CustomLLMModelStorageSupport.formatByteCount(Int64(size))
        localSizeTextByRepo[repo] = text
        return text
    }

    func cachedModelSizeText(repo: String) -> String? {
        localSizeTextByRepo[repo]
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
        guard repo == modelRepo else { return Self.fallbackRemoteSizeText(repo: repo) ?? "Unknown" }
        switch sizeState {
        case .unknown:
            return Self.fallbackRemoteSizeText(repo: repo) ?? "Unknown"
        case .loading:
            return "Loading…"
        case .ready(_, let text):
            return text
        case .error:
            return Self.fallbackRemoteSizeText(repo: repo) ?? "Unknown"
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
        let isDownloaded = CustomLLMModelStorageSupport.isModelDirectoryValid(modelDir)
        downloadedStateByRepo[modelRepo] = isDownloaded
        if isDownloaded {
            state = .downloaded
        } else if downloadTask == nil, hasResumableDownload(repo: modelRepo) {
            setPausedState(
                progress: 0,
                completed: 0,
                total: 0,
                currentFile: nil,
                completedFiles: 0,
                totalFiles: 0
            )
        } else {
            state = .notDownloaded
        }
        let downloaded = (state == .downloaded)
        if lastLoggedModelPresence?.repo != modelRepo || lastLoggedModelPresence?.downloaded != downloaded {
            VoxtLog.model("Custom LLM local model state refreshed: repo=\(modelRepo), downloaded=\(downloaded)")
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
                downloadStopAction = nil
            }
            if let pausedState = pausedDownloadSnapshot {
                setDownloadingState(
                    progress: pausedState.progress,
                    completed: pausedState.completed,
                    total: pausedState.total,
                    currentFile: pausedState.currentFile,
                    completedFiles: pausedState.completedFiles,
                    totalFiles: pausedState.totalFiles
                )
            } else {
                setDownloadingState(
                    progress: 0,
                    completed: 0,
                    total: 0,
                    currentFile: nil,
                    completedFiles: 0,
                    totalFiles: 0
                )
            }

            do {
                pausedStatusMessage = nil
                let modelDir = try await performDownloadWithFallback()
                guard CustomLLMModelStorageSupport.isModelDirectoryValid(modelDir) else {
                    pausedStatusMessage = nil
                    state = .error("Downloaded files are incomplete.")
                    VoxtLog.error("Custom LLM download produced incomplete files: \(modelRepo)")
                    return
                }
                invalidateLocalCache(for: modelRepo)
                checkExistingModel()
                VoxtLog.model("Custom LLM download completed: \(modelRepo)")
            } catch is CancellationError {
                cancelDownloadProgressTask()
                switch downloadStopAction {
                case .pause:
                    pausedStatusMessage = nil
                    VoxtLog.model("Custom LLM download paused: \(modelRepo)")
                case .cancel, .none:
                    pausedStatusMessage = nil
                    if let modelDir = cacheDirectory(for: modelRepo) {
                        try? FileManager.default.removeItem(at: modelDir)
                    }
                    invalidateLocalCache(for: modelRepo)
                    state = .notDownloaded
                    VoxtLog.warning("Custom LLM download cancelled: \(modelRepo)")
                }
            } catch {
                cancelDownloadProgressTask()
                if pauseDownloadIfNetworkIssue(error) {
                    return
                }
                pausedStatusMessage = nil
                state = .error("Download failed: \(error.localizedDescription)")
                VoxtLog.error("Custom LLM download failed: \(modelRepo), error=\(error.localizedDescription)")
            }
        }
    }

    func downloadModel(repo: String) async {
        updateModel(repo: repo)
        await downloadModel()
    }

    func cancelDownload(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if canonicalRepo == modelRepo {
            cancelDownload()
            return
        }

        if let modelDir = cacheDirectory(for: canonicalRepo) {
            try? FileManager.default.removeItem(at: modelDir)
        }
        if let repoID = Repo.ID(rawValue: canonicalRepo) {
            CustomLLMModelStorageSupport.clearHubCache(for: repoID)
        }
        invalidateLocalCache(for: canonicalRepo)
    }

    func refreshStorageRoot() {
        downloadedStateByRepo.removeAll()
        downloadedStateCachePrimed = false
        localSizeTextByRepo.removeAll()
        checkExistingModel()
    }

    func pauseDownload() {
        guard downloadTask != nil else { return }
        downloadStopAction = .pause
        pausedStatusMessage = nil
        if let snapshot = downloadingSnapshot {
            setPausedState(
                progress: snapshot.progress,
                completed: snapshot.completed,
                total: snapshot.total,
                currentFile: snapshot.currentFile,
                completedFiles: snapshot.completedFiles,
                totalFiles: snapshot.totalFiles
            )
        }
        downloadTask?.cancel()
        cancelDownloadProgressTask()
    }

    func cancelDownload() {
        VoxtLog.model("Custom LLM download cancellation requested: \(modelRepo)")
        if downloadTask != nil {
            downloadStopAction = .cancel
            pausedStatusMessage = nil
            state = .notDownloaded
            downloadTask?.cancel()
            cancelDownloadProgressTask()
            return
        }

        guard pausedDownloadSnapshot != nil else { return }
        pausedStatusMessage = nil
        if let modelDir = cacheDirectory(for: modelRepo) {
            try? FileManager.default.removeItem(at: modelDir)
        }
        invalidateLocalCache(for: modelRepo)
        state = .notDownloaded
        VoxtLog.model("Custom LLM download cancelled from paused state: \(modelRepo)")
    }

    private func cancelDownloadProgressTask() {
        downloadProgressTask?.cancel()
        downloadProgressTask = nil
    }

    private func performDownloadWithFallback() async throws -> URL {
        do {
            return try await performDownload(using: hubBaseURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let fallbackBaseURL = CustomLLMModelDownloadSupport.fallbackHubBaseURL(
                from: hubBaseURL,
                mirrorBaseURL: Self.mirrorHubBaseURL
            ) else {
                throw error
            }
            VoxtLog.warning(
                "Primary custom LLM download endpoint failed. Retrying with mirror. repo=\(modelRepo), baseURL=\(hubBaseURL.absoluteString), error=\(error.localizedDescription)"
            )
            if let repoID = Repo.ID(rawValue: modelRepo) {
                CustomLLMModelStorageSupport.clearHubCache(for: repoID)
            }
            return try await performDownload(using: fallbackBaseURL)
        }
    }

    private func performDownload(using baseURL: URL) async throws -> URL {
        let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
            ?? Bundle.main.object(forInfoDictionaryKey: "HF_TOKEN") as? String
        let context = try await CustomLLMModelDownloadSupport.makeDownloadContext(
            repo: modelRepo,
            baseURL: baseURL,
            userAgent: Self.hubUserAgent,
            token: token
        )
        VoxtLog.model("Custom LLM download started: repo=\(context.repoID.description), files=\(context.entries.count), baseURL=\(baseURL.absoluteString)")

        let totalBytes = context.totalBytes
        let totalFiles = context.entries.count
        var completedBytes: Int64 = 0

        guard let modelDir = cacheDirectory(for: modelRepo) else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model cache directory."]
            )
        }
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        for (index, entry) in context.entries.enumerated() {
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

            let destination = try CustomLLMModelStorageSupport.destinationFileURL(
                for: entry.path,
                under: modelDir
            )
            if MLXModelDownloadSupport.canReuseExistingDownload(
                at: destination,
                expectedSize: entry.size,
                fileManager: .default
            ) {
                let delta = max(expectedFileBytes, Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                completedBytes += max(delta, 0)
                setDownloadingState(
                    progress: min(1, Double(completedBytes) / Double(totalBytes)),
                    completed: min(completedBytes, totalBytes),
                    total: totalBytes,
                    currentFile: nil,
                    completedFiles: index + 1,
                    totalFiles: totalFiles
                )
                VoxtLog.info("Custom LLM download resume reused existing file: \(entry.path)", verbose: true)
                continue
            }
            cancelDownloadProgressTask()
            downloadProgressTask = Task { [weak self] in
                let startTime = Date()
                while !Task.isCancelled {
                    await MainActor.run {
                        guard let self else { return }
                        let effectiveCurrentFileCompleted = CustomLLMModelDownloadSupport.inFlightBytes(
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

            try await downloadEntryWithRetry(
                context: context,
                entryPath: entry.path,
                destination: destination,
                progress: progress,
                baseURL: baseURL,
                bearerToken: token
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

        return modelDir
    }

    private func downloadEntryWithRetry(
        context: CustomLLMModelDownloadSupport.DownloadContext,
        entryPath: String,
        destination: URL,
        progress: Progress,
        baseURL: URL,
        bearerToken: String?
    ) async throws {
        let remoteURL = try MLXModelDownloadSupport.fileResolveURL(
            baseURL: baseURL,
            repo: context.repoID.description,
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

    func deleteModel() {
        pausedStatusMessage = nil
        deleteModel(repo: modelRepo)
        state = .notDownloaded
    }

    func deleteModel(repo: String) {
        let canonicalRepo = repo
        if canonicalRepo == modelRepo {
            pausedStatusMessage = nil
        }
        VoxtLog.info("Deleting custom LLM model cache: \(canonicalRepo)")
        if canonicalRepo == inferenceModelRepo {
            releaseInferenceResources(resetActiveInferenceCount: true)
        }
        if let repoID = Repo.ID(rawValue: canonicalRepo) {
            CustomLLMModelStorageSupport.clearHubCache(for: repoID)
        }
        if let modelDir = cacheDirectory(for: canonicalRepo) {
            do {
                try FileManager.default.removeItem(at: modelDir)
                VoxtLog.info("Deleted custom LLM model directory. repo=\(canonicalRepo), path=\(modelDir.path)")
            } catch {
                if canonicalRepo == modelRepo {
                    state = .error("Couldn't uninstall local LLM. It may still be in use.")
                }
                VoxtLog.error("Failed to delete custom LLM model directory. repo=\(canonicalRepo), error=\(error.localizedDescription)")
                return
            }
        }
        invalidateLocalCache(for: canonicalRepo)
        if canonicalRepo == modelRepo {
            state = .notDownloaded
        }
    }

    private func invalidateLocalCache(for repo: String) {
        downloadedStateByRepo.removeValue(forKey: repo)
        localSizeTextByRepo.removeValue(forKey: repo)
    }

    private func primeDownloadedStateCacheIfNeeded() {
        guard !downloadedStateCachePrimed else { return }
        downloadedStateCachePrimed = true

        for model in Self.supportedModels {
            let canonicalRepo = Self.canonicalModelRepo(model.id)
            guard downloadedStateByRepo[canonicalRepo] == nil else { continue }
            guard let modelDir = cacheDirectory(for: canonicalRepo),
                  FileManager.default.fileExists(atPath: modelDir.path) else {
                downloadedStateByRepo[canonicalRepo] = false
                continue
            }
            downloadedStateByRepo[canonicalRepo] = CustomLLMModelStorageSupport.isModelDirectoryValid(modelDir)
        }
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
        guard downloadTask != nil, downloadStopAction == nil else { return }
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

    private func setPausedState(
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int
    ) {
        let nextState = ModelState.paused(
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

    private func pauseDownloadIfNetworkIssue(_ error: Error) -> Bool {
        guard let message = MLXModelDownloadSupport.pauseMessageForInterruptedDownload(error) else {
            return false
        }
        let snapshot = downloadingSnapshot ?? pausedDownloadSnapshot
        pausedStatusMessage = message
        if let snapshot {
            setPausedState(
                progress: snapshot.progress,
                completed: snapshot.completed,
                total: snapshot.total,
                currentFile: snapshot.currentFile,
                completedFiles: snapshot.completedFiles,
                totalFiles: snapshot.totalFiles
            )
        } else {
            setPausedState(
                progress: 0,
                completed: 0,
                total: 0,
                currentFile: nil,
                completedFiles: 0,
                totalFiles: 0
            )
        }
        VoxtLog.warning("Custom LLM download auto-paused after network issue. repo=\(modelRepo), error=\(error.localizedDescription)")
        return true
    }

    private var downloadingSnapshot: (
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
        ) = state else {
            return nil
        }
        return (progress, completed, total, currentFile, completedFiles, totalFiles)
    }

    private var pausedDownloadSnapshot: (
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
        ) = state else {
            return nil
        }
        return (progress, completed, total, currentFile, completedFiles, totalFiles)
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

    private func dictionaryHistoryScanStructuredOutputPrompt(_ prompt: String) -> String {
        """
        Analyze the following task and return only valid JSON.

        Final answer requirements:
        - Return only a JSON array.
        - Every item must be an object with exactly one key: "term".
        - Example: [{"term":"OpenAI"},{"term":"MCP"}]
        - If no term qualifies, return [].
        - Do not wrap the array in another object.
        - Do not return prose, markdown, code fences, or explanations.

        Task:
        \(prompt)
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
        CustomLLMModelStorageSupport.cacheDirectory(
            for: repo,
            rootDirectory: ModelStorageDirectoryManager.resolvedRootURL()
        )
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
        guard isMemoryOptimizationEnabled else {
            cancelIdleUnloadTask()
            return
        }
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
        CustomLLMModelStorageSupport.savePersistedRemoteSizeCache(remoteSizeTextByRepo)
    }

    private func markRemoteSizeUnavailable(
        for repo: String,
        logMessage: String
    ) {
        remoteSizeTextByRepo = CustomLLMRemoteSizeCache.updatedCache(
            remoteSizeTextByRepo,
            repo: repo,
            text: Self.fallbackRemoteSizeText(repo: repo) ?? CustomLLMRemoteSizeCache.unknownText
        )
        VoxtLog.warning(logMessage)
    }

    private func loadRemoteSize(
        for repo: String,
        updatesVisibleState: Bool
    ) async {
        do {
            let info = try await CustomLLMModelDownloadSupport.fetchRemoteSizeInfo(
                repo: repo,
                preferredBaseURL: hubBaseURL,
                mirrorBaseURL: Self.mirrorHubBaseURL,
                userAgent: Self.hubUserAgent,
                formatByteCount: CustomLLMModelStorageSupport.formatByteCount
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
                if let fallback = CustomLLMModelCatalog.fallbackRemoteSizeInfo(repo: repo) {
                    sizeState = .ready(bytes: fallback.bytes, text: fallback.text)
                } else {
                    sizeState = .error("Size unavailable")
                }
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

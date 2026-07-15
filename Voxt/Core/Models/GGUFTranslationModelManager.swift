// GGUFTranslationModelManager.swift
// Provides translation-only GGUF model management and llama.cpp execution.

import Foundation
import AppKit
import Combine
import LlamaSwift

@MainActor
final class GGUFTranslationModelManager: ObservableObject {
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

    @Published private(set) var stateByID: [GGUFTranslationModelID: ModelState] = [:]
    @Published private(set) var pausedStatusMessageByID: [GGUFTranslationModelID: String] = [:]
    @Published private(set) var activeDownloadModelID: GGUFTranslationModelID?

    private let runtime = GGUFTranslationRuntime()
    private var currentModelID: GGUFTranslationModelID
    private var downloadTask: Task<Void, Never>?
    private var downloadProgressTask: Task<Void, Never>?
    private var downloadStopAction: DownloadStopAction?

    init(modelID: GGUFTranslationModelID) {
        self.currentModelID = modelID
        refreshStorageRoot()
    }

    var selectedModelID: GGUFTranslationModelID {
        currentModelID
    }

    func updateModel(id: GGUFTranslationModelID) {
        currentModelID = id
    }

    func refreshStorageRoot() {
        for modelID in GGUFTranslationModelID.allCases {
            guard activeDownloadModelID != modelID else { continue }
            let resolvedState = resolvedStoredState(for: modelID)
            stateByID[modelID] = resolvedState
            if case .paused = resolvedState {
                if pausedStatusMessageByID[modelID] == nil {
                    pausedStatusMessageByID[modelID] = AppLocalization.localizedString("Paused. Ready to continue.")
                }
            } else {
                pausedStatusMessageByID[modelID] = nil
            }
        }
    }

    func state(for id: GGUFTranslationModelID) -> ModelState {
        stateByID[id] ?? resolvedStoredState(for: id)
    }

    func option(for id: GGUFTranslationModelID) -> GGUFTranslationModelOption {
        GGUFTranslationModelCatalog.option(for: id)
    }

    func displayModelsIncludingInstalled() -> [GGUFTranslationModelOption] {
        let localStateIDs = Set(GGUFTranslationModelID.allCases.compactMap { modelID -> GGUFTranslationModelID? in
            switch state(for: modelID) {
            case .downloaded, .downloading, .paused:
                return modelID
            case .notDownloaded, .error:
                return nil
            }
        })
        return GGUFTranslationModelCatalog.displayModels(
            includingInstalled: localStateIDs.union([selectedModelID])
        )
    }

    func displayTitle(for id: GGUFTranslationModelID) -> String {
        option(for: id).title
    }

    func modelFileURL(for id: GGUFTranslationModelID) -> URL {
        GGUFTranslationModelCatalog.modelFileURL(
            for: id,
            root: ModelStorageDirectoryManager.resolvedWriteRootURL()
        )
    }

    func isModelDownloaded(id: GGUFTranslationModelID) -> Bool {
        FileManager.default.fileExists(atPath: modelFileURL(for: id).path)
    }

    func cachedModelSizeText(id: GGUFTranslationModelID) -> String? {
        let url = modelFileURL(for: id)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    func openModelDirectory(id: GGUFTranslationModelID) {
        let url = modelFileURL(for: id).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @discardableResult
    func deleteModel(id: GGUFTranslationModelID) -> Result<Void, Error> {
        if activeDownloadModelID == id || hasResumableDownload(id: id) {
            cancelDownload(id: id)
        }
        pausedStatusMessageByID[id] = nil
        do {
            try ResumableModelDownloadSupport.purgePartialArtifacts(for: modelFileURL(for: id))
            let modelURL = modelFileURL(for: id)
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }
        } catch {
            stateByID[id] = .error("Couldn't uninstall model: \(error.localizedDescription)")
            return .failure(error)
        }
        stateByID[id] = .notDownloaded
        return .success(())
    }

    func downloadModel(id: GGUFTranslationModelID) {
        guard downloadTask == nil else { return }
        guard activeDownloadModelID == nil || activeDownloadModelID == id else { return }
        guard !isModelDownloaded(id: id) else {
            stateByID[id] = .downloaded
            return
        }

        activeDownloadModelID = id
        pausedStatusMessageByID[id] = nil

        if let snapshot = pausedDownloadSnapshot(for: id) {
            setDownloadingState(
                id: id,
                progress: snapshot.progress,
                completed: snapshot.completed,
                total: snapshot.total,
                currentFile: snapshot.currentFile,
                completedFiles: snapshot.completedFiles,
                totalFiles: snapshot.totalFiles
            )
        } else {
            let modelOption = option(for: id)
            setDownloadingState(
                id: id,
                progress: 0,
                completed: 0,
                total: modelOption.sizeBytes,
                currentFile: modelOption.filename,
                completedFiles: 0,
                totalFiles: 1
            )
        }

        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                cancelDownloadProgressTask()
                downloadTask = nil
                downloadStopAction = nil
                if activeDownloadModelID == id {
                    activeDownloadModelID = nil
                }
            }

            do {
                try await performDownload(id: id)
                pausedStatusMessageByID[id] = nil
                stateByID[id] = .downloaded
            } catch is CancellationError {
                cancelDownloadProgressTask()
                switch downloadStopAction {
                case .pause:
                    if pausedDownloadSnapshot(for: id) == nil {
                        setPausedState(
                            id: id,
                            progress: 0,
                            completed: 0,
                            total: option(for: id).sizeBytes,
                            currentFile: option(for: id).filename,
                            completedFiles: 0,
                            totalFiles: 1
                        )
                    }
                case .cancel, .none:
                    pausedStatusMessageByID[id] = nil
                    try? ResumableModelDownloadSupport.purgePartialArtifacts(for: modelFileURL(for: id))
                    try? FileManager.default.removeItem(at: modelFileURL(for: id))
                    stateByID[id] = .notDownloaded
                }
            } catch {
                cancelDownloadProgressTask()
                if pauseDownloadIfNetworkIssue(error, id: id) {
                    return
                }
                pausedStatusMessageByID[id] = nil
                stateByID[id] = .error("Download failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelDownload(id: GGUFTranslationModelID) {
        guard activeDownloadModelID == id || hasResumableDownload(id: id) else { return }
        pausedStatusMessageByID[id] = nil

        if activeDownloadModelID == id, downloadTask != nil {
            downloadStopAction = .cancel
            stateByID[id] = .notDownloaded
            downloadTask?.cancel()
            cancelDownloadProgressTask()
            return
        }

        try? ResumableModelDownloadSupport.purgePartialArtifacts(for: modelFileURL(for: id))
        try? FileManager.default.removeItem(at: modelFileURL(for: id))
        stateByID[id] = .notDownloaded
    }

    func pauseDownload(id: GGUFTranslationModelID) {
        guard activeDownloadModelID == id, downloadTask != nil else { return }
        downloadStopAction = .pause
        pausedStatusMessageByID[id] = nil
        if let snapshot = downloadingSnapshot(for: id) {
            setPausedState(
                id: id,
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

    func hasResumableDownload(id: GGUFTranslationModelID) -> Bool {
        guard !isModelDownloaded(id: id) else { return false }
        let destinationURL = modelFileURL(for: id)
        let partURL = partialFileURL(for: destinationURL)
        let stateURL = partURL.appendingPathExtension("json")
        return FileManager.default.fileExists(atPath: partURL.path)
            || FileManager.default.fileExists(atPath: stateURL.path)
    }

    func pausedStatusMessage(for id: GGUFTranslationModelID) -> String? {
        pausedStatusMessageByID[id]
    }

    private func resolvedStoredState(for id: GGUFTranslationModelID) -> ModelState {
        if isModelDownloaded(id: id) {
            return .downloaded
        }
        if hasResumableDownload(id: id) {
            return .paused(
                progress: 0,
                completed: 0,
                total: option(for: id).sizeBytes,
                currentFile: option(for: id).filename,
                completedFiles: 0,
                totalFiles: 1
            )
        }
        return .notDownloaded
    }

    private func performDownload(id: GGUFTranslationModelID) async throws {
        let modelOption = option(for: id)
        let destinationURL = modelFileURL(for: id)
        let directoryURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let progress = Progress(totalUnitCount: max(modelOption.sizeBytes, 1))
        let displayedTotal = max(modelOption.sizeBytes, 1)
        let baseCompleted = max(downloadingSnapshot(for: id)?.completed ?? pausedDownloadSnapshot(for: id)?.completed ?? 0, 0)
        setDownloadingState(
            id: id,
            progress: displayedTotal > 0 ? min(1, Double(baseCompleted) / Double(displayedTotal)) : 0,
            completed: baseCompleted,
            total: displayedTotal,
            currentFile: modelOption.filename,
            completedFiles: 0,
            totalFiles: 1
        )

        cancelDownloadProgressTask()
        downloadProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    guard let self else { return }
                    let total = max(progress.totalUnitCount, 1)
                    let completed = max(progress.completedUnitCount, 0)
                    self.setDownloadingState(
                        id: id,
                        progress: min(1, Double(completed) / Double(total)),
                        completed: completed,
                        total: total,
                        currentFile: modelOption.filename,
                        completedFiles: 0,
                        totalFiles: 1
                    )
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        let result = try await ResumableModelDownloadSupport.download(
            ResumableDownloadDescriptor(
                sourceURL: modelOption.downloadURL,
                destinationURL: destinationURL,
                relativePath: modelOption.filename,
                expectedSize: nil,
                userAgent: "Voxt/1.0 (GGUFTranslation)",
                disableProxy: MLXModelDownloadSupport.isMirrorHost(modelOption.downloadURL)
            ),
            progress: progress
        )
        cancelDownloadProgressTask()
        let completed = max(result.bytesDownloaded, progress.completedUnitCount)
        let total = max(progress.totalUnitCount, completed)
        setDownloadingState(
            id: id,
            progress: total > 0 ? min(1, Double(completed) / Double(total)) : 1,
            completed: completed,
            total: total,
            currentFile: nil,
            completedFiles: 1,
            totalFiles: 1
        )
    }

    private func cancelDownloadProgressTask() {
        downloadProgressTask?.cancel()
        downloadProgressTask = nil
    }

    private func setDownloadingState(
        id: GGUFTranslationModelID,
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int
    ) {
        guard activeDownloadModelID == id, downloadStopAction == nil else { return }
        let nextState = ModelState.downloading(
            progress: progress,
            completed: completed,
            total: total,
            currentFile: currentFile,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
        if stateByID[id] != nextState {
            stateByID[id] = nextState
        }
    }

    private func setPausedState(
        id: GGUFTranslationModelID,
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
        if stateByID[id] != nextState {
            stateByID[id] = nextState
        }
    }

    private func pauseDownloadIfNetworkIssue(_ error: Error, id: GGUFTranslationModelID) -> Bool {
        guard let message = MLXModelDownloadSupport.pauseMessageForInterruptedDownload(error) else {
            return false
        }
        pausedStatusMessageByID[id] = message
        if let snapshot = downloadingSnapshot(for: id) ?? pausedDownloadSnapshot(for: id) {
            setPausedState(
                id: id,
                progress: snapshot.progress,
                completed: snapshot.completed,
                total: snapshot.total,
                currentFile: snapshot.currentFile,
                completedFiles: snapshot.completedFiles,
                totalFiles: snapshot.totalFiles
            )
        } else {
            setPausedState(
                id: id,
                progress: 0,
                completed: 0,
                total: option(for: id).sizeBytes,
                currentFile: option(for: id).filename,
                completedFiles: 0,
                totalFiles: 1
            )
        }
        return true
    }

    private func downloadingSnapshot(for id: GGUFTranslationModelID) -> (
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
        ) = stateByID[id] else {
            return nil
        }
        return (progress, completed, total, currentFile, completedFiles, totalFiles)
    }

    private func pausedDownloadSnapshot(for id: GGUFTranslationModelID) -> (
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
        ) = stateByID[id] else {
            return nil
        }
        return (progress, completed, total, currentFile, completedFiles, totalFiles)
    }

    private func partialFileURL(for destinationURL: URL) -> URL {
        destinationURL.appendingPathExtension("part")
    }

    func executeCompiledRequest(
        _ request: LLMCompiledRequest,
        modelID: GGUFTranslationModelID,
        onPartialText: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let modelURL = modelFileURL(for: modelID)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw NSError(
                domain: "Voxt.GGUFTranslation",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Selected GGUF translation model is not installed."]
            )
        }

        let instructions = request.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instructions.isEmpty || !prompt.isEmpty else { return request.fallbackText }

        let maxTokens = resolvedOutputTokenBudget(for: request)
        VoxtLog.llmDebug(
            "GGUF compiled request start. task=\(request.taskLabel), model=\(modelID.rawValue), instructionsChars=\(instructions.count), promptChars=\(prompt.count), inputChars=\(request.inputCharacterCount), outputBudget=\(maxTokens)"
        )
        let generated = try await runtime.generate(
            instructions: instructions,
            prompt: prompt,
            modelURL: modelURL,
            maxTokens: maxTokens,
            onPartialText: onPartialText
        )
        let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        VoxtLog.llmDebug(
            "GGUF compiled request finished. task=\(request.taskLabel), model=\(modelID.rawValue), outputChars=\(trimmed.count), usedFallback=\(trimmed.isEmpty)"
        )
        return trimmed.isEmpty ? request.fallbackText : trimmed
    }

    private func resolvedOutputTokenBudget(for request: LLMCompiledRequest) -> Int {
        if let hint = request.outputTokenBudgetHint {
            return max(48, min(hint, 256))
        }

        let estimated = max(64, request.inputCharacterCount * 2)
        return min(estimated, 192)
    }
}

actor GGUFTranslationRuntime {
    nonisolated private static let backendInitialized: Void = {
        llama_log_set(llamaLogCallback, nil)
        llama_backend_init()
    }()

    nonisolated private static let llamaLogCallback: ggml_log_callback = { level, text, _ in
        guard level == GGML_LOG_LEVEL_ERROR else { return }
        guard let text else { return }
        fputs(text, stderr)
    }

    private var loadedModelPath: String?
    private var loadedModel: OpaquePointer?

    deinit {
        if let loadedModel {
            llama_model_free(loadedModel)
        }
    }

    func generate(
        instructions: String,
        prompt: String,
        modelURL: URL,
        maxTokens: Int,
        onPartialText: (@Sendable (String) -> Void)?
    ) throws -> String {
        let startedAt = CFAbsoluteTimeGetCurrent()
        _ = Self.backendInitialized
        let model = try loadModelIfNeeded(at: modelURL)
        let vocab = llama_model_get_vocab(model)
        let formattedPrompt = try formattedPrompt(
            instructions: instructions,
            prompt: prompt,
            model: model
        )
        let promptTokens = try tokenize(prompt: formattedPrompt, vocab: vocab)
        let modelContextLimit = resolvedModelContextLimit(model)
        let requestedContextSize = max(1024, promptTokens.count + maxTokens + 32)
        let contextSize = min(modelContextLimit, requestedContextSize)
        let batchSize = min(contextSize, max(32, promptTokens.count))

        guard promptTokens.count < contextSize else {
            VoxtLog.llmWarning(
                "GGUF prompt exceeds available context. model=\(modelURL.lastPathComponent), promptTokens=\(promptTokens.count), maxTokens=\(maxTokens), trainedCtx=\(modelContextLimit), requestedCtx=\(requestedContextSize)"
            )
            throw NSError(
                domain: "Voxt.GGUFTranslation",
                code: -7,
                userInfo: [
                    NSLocalizedDescriptionKey: "Translation prompt is too long for the selected GGUF model context window."
                ]
            )
        }

        VoxtLog.llmDebug(
            "GGUF runtime start. model=\(modelURL.lastPathComponent), promptChars=\(formattedPrompt.count), promptTokens=\(promptTokens.count), maxTokens=\(maxTokens), nCtx=\(contextSize), nBatch=\(batchSize), trainedCtx=\(modelContextLimit)"
        )

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = UInt32(batchSize)
        contextParams.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
        contextParams.n_threads_batch = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))

        guard let context = llama_init_from_model(model, contextParams) else {
            throw NSError(
                domain: "Voxt.GGUFTranslation",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create llama.cpp context."]
            )
        }
        defer { llama_free(context) }

        var batch = llama_batch_init(Int32(batchSize), 0, 1)
        defer { llama_batch_free(batch) }

        batch.n_tokens = Int32(promptTokens.count)
        for (index, token) in promptTokens.enumerated() {
            batch.token[index] = token
            batch.pos[index] = Int32(index)
            batch.n_seq_id[index] = 1
            if let seqIDs = batch.seq_id,
               let seqID = seqIDs[index] {
                seqID[0] = 0
            }
            batch.logits[index] = 0
        }
        if batch.n_tokens > 0 {
            batch.logits[Int(batch.n_tokens) - 1] = 1
        }

        let prefillStartedAt = CFAbsoluteTimeGetCurrent()
        guard llama_decode(context, batch) == 0 else {
            throw NSError(
                domain: "Voxt.GGUFTranslation",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Prompt evaluation failed."]
            )
        }
        let prefillElapsedMs = millisecondsSince(prefillStartedAt)

        let sampler = try createSampler()
        defer { llama_sampler_free(sampler) }

        var generated = ""
        var outputAccumulator = GGUFUTF8OutputAccumulator()
        var tokenPosition = Int32(promptTokens.count)
        let eosToken = llama_vocab_eos(vocab)
        let eotToken = llama_vocab_eot(vocab)
        let contextLimit = Int(llama_n_ctx(context))
        var generatedTokenCount = 0
        var firstTokenLatencyMs: Int?
        var stopReason = "tokenLimit"

        let generationLimit = max(0, min(maxTokens, contextSize - promptTokens.count - 1))
        if generationLimit == 0 {
            stopReason = "noGenerationBudget"
        }
        for _ in 0..<generationLimit {
            if Int(tokenPosition) >= contextLimit - 1 {
                stopReason = "contextLimit"
                break
            }

            let nextToken = llama_sampler_sample(sampler, context, -1)
            if nextToken == eosToken || nextToken == eotToken {
                stopReason = nextToken == eosToken ? "eos" : "eot"
                break
            }
            llama_sampler_accept(sampler, nextToken)
            generatedTokenCount += 1
            if firstTokenLatencyMs == nil {
                firstTokenLatencyMs = millisecondsSince(startedAt)
            }

            let pieceBytes = tokenPieceBytes(for: nextToken, vocab: vocab)
            if !pieceBytes.isEmpty,
               let decoded = outputAccumulator.append(pieceBytes) {
                generated = decoded
                onPartialText?(generated)
            }

            batch.n_tokens = 1
            batch.token[0] = nextToken
            batch.pos[0] = tokenPosition
            batch.n_seq_id[0] = 1
            if let seqIDs = batch.seq_id,
               let seqID = seqIDs[0] {
                seqID[0] = 0
            }
            batch.logits[0] = 1
            tokenPosition += 1

            guard llama_decode(context, batch) == 0 else {
                throw NSError(
                    domain: "Voxt.GGUFTranslation",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Token generation failed."]
                )
            }
        }

        let finalizedOutput = outputAccumulator.finalizedText()
        if generated != finalizedOutput {
            generated = finalizedOutput
            if !generated.isEmpty {
                onPartialText?(generated)
            }
        }
        if outputAccumulator.finalizedWithReplacementCharacters {
            VoxtLog.llmDebug(
                "GGUF runtime output contained invalid UTF-8 bytes after token accumulation. model=\(modelURL.lastPathComponent), outputTokens=\(generatedTokenCount)"
            )
        }

        let totalElapsedMs = millisecondsSince(startedAt)
        VoxtLog.llmDebug(
            "GGUF runtime finished. model=\(modelURL.lastPathComponent), outputChars=\(generated.count), outputTokens=\(generatedTokenCount), prefillMs=\(prefillElapsedMs), firstTokenMs=\(firstTokenLatencyMs.map(String.init) ?? "n/a"), totalMs=\(totalElapsedMs), stop=\(stopReason)"
        )
        return generated
    }

    private func millisecondsSince(_ start: CFAbsoluteTime) -> Int {
        max(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()), 0)
    }

    private func resolvedModelContextLimit(_ model: OpaquePointer) -> Int {
        let trainedLimit = Int(llama_model_n_ctx_train(model))
        if trainedLimit > 0 {
            return max(1024, trainedLimit)
        }
        return 4096
    }

    private func formattedPrompt(
        instructions: String,
        prompt: String,
        model: OpaquePointer
    ) throws -> String {
        let fallbackSections = [instructions, prompt]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let fallbackPrompt = fallbackSections.joined(separator: "\n\n")
        guard !fallbackPrompt.isEmpty else { return "" }

        guard let templatePointer = llama_model_chat_template(model, nil) else {
            return fallbackPrompt
        }

        let systemText = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var messages = [llama_chat_message]()
        if !systemText.isEmpty {
            messages.append(
                llama_chat_message(
                    role: strdup("system"),
                    content: strdup(systemText)
                )
            )
        }
        if !userText.isEmpty {
            messages.append(
                llama_chat_message(
                    role: strdup("user"),
                    content: strdup(userText)
                )
            )
        }

        defer {
            for message in messages {
                if let role = message.role {
                    free(UnsafeMutableRawPointer(mutating: role))
                }
                if let content = message.content {
                    free(UnsafeMutableRawPointer(mutating: content))
                }
            }
        }

        guard !messages.isEmpty else { return fallbackPrompt }

        var bufferSize = max(2048, fallbackPrompt.utf8.count * 4)
        while bufferSize <= 1_048_576 {
            var buffer = [CChar](repeating: 0, count: bufferSize)
            let renderedLength = llama_chat_apply_template(
                templatePointer,
                messages,
                messages.count,
                true,
                &buffer,
                Int32(buffer.count)
            )
            guard renderedLength > 0 else {
                return fallbackPrompt
            }
            if renderedLength < buffer.count {
                return String(cString: buffer)
            }
            bufferSize = Int(renderedLength) + 1
        }

        return fallbackPrompt
    }

    private func loadModelIfNeeded(at modelURL: URL) throws -> OpaquePointer {
        if let loadedModel,
           loadedModelPath == modelURL.path {
            return loadedModel
        }

        if let loadedModel {
            llama_model_free(loadedModel)
            self.loadedModel = nil
            self.loadedModelPath = nil
        }

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = -1

        guard let model = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw NSError(
                domain: "Voxt.GGUFTranslation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load GGUF model from \(modelURL.lastPathComponent)."]
            )
        }

        loadedModel = model
        loadedModelPath = modelURL.path
        return model
    }

    private func tokenize(prompt: String, vocab: OpaquePointer?) throws -> [llama_token] {
        let utf8Count = prompt.utf8.count
        let maxTokenCount = max(utf8Count + 8, 128)
        var tokens = [llama_token](repeating: 0, count: maxTokenCount)
        let tokenCount = llama_tokenize(
            vocab,
            prompt,
            Int32(utf8Count),
            &tokens,
            Int32(maxTokenCount),
            true,
            true
        )
        guard tokenCount > 0 else {
            throw NSError(
                domain: "Voxt.GGUFTranslation",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Prompt tokenization failed."]
            )
        }
        return Array(tokens.prefix(Int(tokenCount)))
    }

    private func createSampler() throws -> UnsafeMutablePointer<llama_sampler> {
        let params = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(params) else {
            throw NSError(
                domain: "Voxt.GGUFTranslation",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize llama.cpp sampler."]
            )
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, 1.05, 0, 0))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(10))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.2))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32(Date().timeIntervalSince1970)))
        return sampler
    }

    private func tokenPieceBytes(for token: llama_token, vocab: OpaquePointer?) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        while true {
            let length = llama_token_to_piece(
                vocab,
                token,
                &buffer,
                Int32(buffer.count),
                0,
                false
            )

            guard length != 0 else { return [] }

            if length > 0, length <= Int32(buffer.count) {
                let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
                return bytes
            }

            let requiredLength = Int(abs(length))
            let nextCapacity = max(buffer.count * 2, requiredLength + 1)
            buffer = [CChar](repeating: 0, count: nextCapacity)
        }
    }
}

nonisolated struct GGUFUTF8OutputAccumulator {
    private var bytes: [UInt8] = []
    private(set) var finalizedWithReplacementCharacters = false

    mutating func append(_ newBytes: [UInt8]) -> String? {
        guard !newBytes.isEmpty else {
            return String(data: Data(bytes), encoding: .utf8)
        }
        bytes.append(contentsOf: newBytes)
        return String(data: Data(bytes), encoding: .utf8)
    }

    mutating func finalizedText() -> String {
        if let decoded = String(data: Data(bytes), encoding: .utf8) {
            return decoded
        }
        finalizedWithReplacementCharacters = true
        return String(decoding: bytes, as: UTF8.self)
    }
}

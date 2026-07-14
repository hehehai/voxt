// SherpaOnnxModelManager.swift
// Provides local sherpa-onnx ASR model download and storage management.

import Foundation
import AppKit
import Combine

@MainActor
final class SherpaOnnxModelManager: ObservableObject {
    typealias ModelState = MLXModelManager.ModelState
    private static let downloadUserAgent = "Voxt/1.0 (SherpaOnnx)"

    struct CatalogSnapshot: Equatable {
        let id: SherpaOnnxModelID
        let isDownloaded: Bool
        let state: ModelState
        let pausedStatusMessage: String?
        let hasActiveDownloadTask: Bool

        var isDownloading: Bool {
            if hasActiveDownloadTask { return true }
            if case .downloading = state { return true }
            return false
        }

        var isPaused: Bool {
            if case .paused = state { return true }
            return false
        }
    }

    private enum DownloadStopAction {
        case pause
        case cancel
    }

    @Published private(set) var state: ModelState = .notDownloaded
    @Published private(set) var stateByID: [SherpaOnnxModelID: ModelState] = [:]
    @Published private(set) var pausedStatusMessage: String?
    @Published private(set) var pausedStatusMessageByID: [SherpaOnnxModelID: String] = [:]
    @Published private(set) var activeDownloadModelIDs: Set<SherpaOnnxModelID> = []

    private var currentModelID: SherpaOnnxModelID
    private var downloadTasksByID: [SherpaOnnxModelID: Task<Void, Never>] = [:]
    private var downloadProgressTasksByID: [SherpaOnnxModelID: Task<Void, Never>] = [:]
    private var downloadStopActionsByID: [SherpaOnnxModelID: DownloadStopAction] = [:]
    private var downloadedStateByID: [SherpaOnnxModelID: Bool] = [:]
    private var localSizeTextByID: [SherpaOnnxModelID: String] = [:]

    init(modelID: SherpaOnnxModelID) {
        self.currentModelID = modelID
        checkExistingModel()
    }

    var selectedModelID: SherpaOnnxModelID { currentModelID }
    var currentModelIDRawValue: String { currentModelID.rawValue }

    func updateModel(id: SherpaOnnxModelID) {
        guard id != currentModelID else { return }
        currentModelID = id
        checkExistingModel()
    }

    func displayTitle(for id: SherpaOnnxModelID) -> String {
        SherpaOnnxModelCatalog.displayTitle(for: id)
    }

    func option(for id: SherpaOnnxModelID) -> SherpaOnnxModelOption {
        SherpaOnnxModelCatalog.option(for: id)
    }

    func displayModelsIncludingInstalled(
        including modelIDs: Set<SherpaOnnxModelID> = []
    ) -> [SherpaOnnxModelOption] {
        var includedModelIDs = modelIDs
        for model in SherpaOnnxModelCatalog.supportedModels {
            let snapshot = catalogSnapshot(for: model.id)
            if snapshot.isDownloaded || snapshot.isDownloading || snapshot.isPaused {
                includedModelIDs.insert(model.id)
            }
        }
        return SherpaOnnxModelCatalog.displayModels(including: includedModelIDs)
    }

    func isModelDownloaded(id: SherpaOnnxModelID) -> Bool {
        if let cached = downloadedStateByID[id] {
            return cached
        }
        guard let directory = readableModelDirectory(for: id, requireValid: true) else {
            downloadedStateByID[id] = false
            return false
        }
        let exists = FileManager.default.fileExists(atPath: directory.path)
        downloadedStateByID[id] = exists
        return exists
    }

    func modelDirectoryURL(id: SherpaOnnxModelID) -> URL? {
        readableModelDirectory(for: id, requireValid: false)
    }

    func cachedModelSizeText(id: SherpaOnnxModelID) -> String? {
        if let cached = localSizeTextByID[id] {
            return cached
        }
        guard let directory = readableModelDirectory(for: id, requireValid: true),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: directory),
              size > 0
        else {
            return nil
        }
        let text = MLXModelStorageSupport.formatByteCount(Int64(size))
        localSizeTextByID[id] = text
        return text
    }

    func remoteSizeText(id: SherpaOnnxModelID) -> String {
        SherpaOnnxModelCatalog.sizeText(for: id)
    }

    func catalogSnapshot(for id: SherpaOnnxModelID) -> CatalogSnapshot {
        let isDownloaded = isModelDownloaded(id: id)
        let resolvedState = resolvedState(for: id, isDownloaded: isDownloaded)
        return CatalogSnapshot(
            id: id,
            isDownloaded: isDownloaded,
            state: resolvedState,
            pausedStatusMessage: pausedStatusMessage(for: id),
            hasActiveDownloadTask: downloadTasksByID[id] != nil
        )
    }

    func state(for id: SherpaOnnxModelID) -> ModelState {
        catalogSnapshot(for: id).state
    }

    func pausedStatusMessage(for id: SherpaOnnxModelID) -> String? {
        if id == currentModelID {
            return pausedStatusMessage
        }
        return pausedStatusMessageByID[id]
    }

    func isDownloadOperationActive(id: SherpaOnnxModelID) -> Bool {
        if downloadTasksByID[id] != nil { return true }
        switch state(for: id) {
        case .downloading, .paused:
            return true
        default:
            return false
        }
    }

    func downloadModel(id: SherpaOnnxModelID) {
        guard downloadTasksByID[id] == nil else { return }
        guard !isModelDownloaded(id: id) else {
            setState(.downloaded, for: id)
            return
        }

        let option = option(for: id)
        setPausedStatusMessage(nil, for: id)
        setDownloadingState(
            progress: 0,
            completed: 0,
            total: option.archiveBytes,
            currentFile: option.downloadURL.lastPathComponent,
            completedFiles: 0,
            totalFiles: 1,
            for: id
        )

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                downloadTasksByID[id] = nil
                downloadStopActionsByID[id] = nil
                activeDownloadModelIDs.remove(id)
            }

            activeDownloadModelIDs.insert(id)
            do {
                try await performDownload(id: id)
                cancelDownloadProgressTask(for: id)
                markModelDownloaded(id: id)
            } catch is CancellationError {
                cancelDownloadProgressTask(for: id)
                switch downloadStopActionsByID[id] {
                case .pause:
                    setPausedStatusMessage(AppLocalization.localizedString("Paused. Ready to continue."), for: id)
                    setPausedState(from: state(for: id), option: option, for: id)
                case .cancel, .none:
                    cleanupDownload(id: id)
                    markModelNotDownloaded(id: id)
                }
            } catch {
                cancelDownloadProgressTask(for: id)
                cleanupDownload(id: id)
                downloadedStateByID[id] = false
                setPausedStatusMessage(nil, for: id)
                setState(.error("Download failed: \(error.localizedDescription)"), for: id)
            }
        }
        downloadTasksByID[id] = task
    }

    func pauseDownload(id: SherpaOnnxModelID) {
        guard let task = downloadTasksByID[id] else { return }
        downloadStopActionsByID[id] = .pause
        setPausedState(from: state(for: id), option: option(for: id), for: id)
        task.cancel()
        cancelDownloadProgressTask(for: id)
    }

    func cancelDownload(id: SherpaOnnxModelID) {
        if let task = downloadTasksByID[id] {
            downloadStopActionsByID[id] = .cancel
            clearSelectedDownloadSource(for: id)
            task.cancel()
            cancelDownloadProgressTask(for: id)
            return
        }
        cleanupDownload(id: id)
        clearSelectedDownloadSource(for: id)
        markModelNotDownloaded(id: id)
    }

    @discardableResult
    func deleteModel(id: SherpaOnnxModelID) -> Result<Void, Error> {
        cancelDownload(id: id)
        for directory in allReadableModelDirectories(for: id, requireValid: false) {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                setState(.error("Couldn't uninstall model: \(error.localizedDescription)"), for: id)
                return .failure(error)
            }
        }
        clearSelectedDownloadSource(for: id)
        markModelNotDownloaded(id: id, clearsLocalSize: true)
        return .success(())
    }

    func openModelDirectory(id: SherpaOnnxModelID) {
        let directory = modelDirectoryURL(id: id) ?? writeModelDirectory(for: id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func refreshStorageRoot() {
        downloadedStateByID.removeAll()
        localSizeTextByID.removeAll()
        checkExistingModel()
    }

    func checkExistingModel() {
        if isModelDownloaded(id: currentModelID) {
            setState(.downloaded, for: currentModelID)
        } else if downloadTasksByID[currentModelID] == nil {
            setState(.notDownloaded, for: currentModelID)
        }
    }

    private func performDownload(id: SherpaOnnxModelID) async throws {
        let option = option(for: id)
        let shouldReuseDownload = shouldReuseSavedDownloadSource(for: id)
        let selection = try await ModelDownloadSourceSelector.select(
            candidates: option.downloadSources,
            targetKey: downloadSourceTargetKey(for: id),
            reuseSavedSource: shouldReuseDownload
        ) { candidate in
            try await ModelDownloadSourceSelector.probeHTTPDownloadURL(
                candidate.url,
                userAgent: Self.downloadUserAgent,
                expectedBytes: option.archiveBytes
            )
        }
        let sourceURL = selection.candidate.url

        VoxtLog.modelInfo(
            "Selected sherpa-onnx download source. model=\(id.rawValue), source=\(selection.candidate.displayName), url=\(sourceURL.absoluteString), reusedSavedSource=\(selection.reusedSavedSource), probes=\(ModelDownloadSourceSelector.logSummary(for: selection))"
        )

        var lastError: Error?
        let candidates = downloadAttemptCandidates(from: selection)
        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()

            if !shouldReuseDownload || index > 0 {
                cleanupDownload(id: id)
            }

            do {
                try await performDownload(
                    id: id,
                    option: option,
                    source: candidate,
                    reusesExistingProgress: shouldReuseDownload && index == 0
                )
                ModelDownloadSourceSelectionStore.saveSourceID(
                    candidate.id,
                    for: downloadSourceTargetKey(for: id)
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                VoxtLog.modelWarning(
                    "Sherpa ONNX download source failed. model=\(id.rawValue), source=\(candidate.displayName), error=\(error.localizedDescription)"
                )
                cleanupDownload(id: id)
            }
        }

        clearSelectedDownloadSource(for: id)
        throw lastError ?? NSError(
            domain: "SherpaOnnxModelManager",
            code: 1002,
            userInfo: [NSLocalizedDescriptionKey: "All sherpa-onnx download sources failed."]
        )
    }

    private func downloadAttemptCandidates(
        from selection: ModelDownloadSourceSelection
    ) -> [ModelDownloadSourceCandidate] {
        guard !selection.reusedSavedSource, !selection.probeResults.isEmpty else {
            return [selection.candidate]
        }

        let candidates = selection.probeResults
            .filter(\.isReachable)
            .sorted(by: { $0.elapsed < $1.elapsed })
            .map(\.candidate)
        return candidates.isEmpty ? [selection.candidate] : candidates
    }

    private func performDownload(
        id: SherpaOnnxModelID,
        option: SherpaOnnxModelOption,
        source candidate: ModelDownloadSourceCandidate,
        reusesExistingProgress: Bool
    ) async throws {
        let sourceURL = candidate.url
        let root = writeRootURL()
        let downloadDirectory = SherpaOnnxModelStorageSupport.downloadDirectory(for: id, rootDirectory: root)
        let archiveURL = SherpaOnnxModelStorageSupport.archiveURL(for: id, rootDirectory: root)
        let destinationDirectory = writeModelDirectory(for: id)

        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)

        let progress = Progress(totalUnitCount: max(option.archiveBytes, 1))
        let baseCompleted = reusesExistingProgress ? max(completedBytes(from: state(for: id)), 0) : 0
        setDownloadingState(
            progress: option.archiveBytes > 0 ? min(1, Double(baseCompleted) / Double(option.archiveBytes)) : 0,
            completed: baseCompleted,
            total: option.archiveBytes,
            currentFile: sourceURL.lastPathComponent,
            completedFiles: 0,
            totalFiles: 1,
            for: id
        )

        cancelDownloadProgressTask(for: id)
        downloadProgressTasksByID[id] = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    guard let self else { return }
                    let total = max(progress.totalUnitCount, option.archiveBytes, 1)
                    let completed = max(progress.completedUnitCount, 0)
                    self.setDownloadingState(
                        progress: min(0.86, Double(completed) / Double(total) * 0.86),
                        completed: completed,
                        total: max(option.archiveBytes, total),
                        currentFile: sourceURL.lastPathComponent,
                        completedFiles: 0,
                        totalFiles: 1,
                        for: id
                    )
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        let result = try await ResumableModelDownloadSupport.download(
            ResumableDownloadDescriptor(
                sourceURL: sourceURL,
                destinationURL: archiveURL,
                relativePath: sourceURL.lastPathComponent,
                expectedSize: option.archiveBytes,
                requiresExpectedSizeMatch: false,
                userAgent: Self.downloadUserAgent,
                disableProxy: MLXModelDownloadSupport.isMirrorHost(sourceURL)
            ),
            progress: progress
        )
        cancelDownloadProgressTask(for: id)
        let completedBytes = max(result.bytesDownloaded, progress.completedUnitCount, option.archiveBytes)
        setDownloadingState(
            progress: 0.86,
            completed: completedBytes,
            total: max(option.archiveBytes, completedBytes),
            currentFile: sourceURL.lastPathComponent,
            completedFiles: 0,
            totalFiles: 1,
            for: id
        )

        let extractionRoot = downloadDirectory.appendingPathComponent("extract", isDirectory: true)
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: extractionRoot)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        try await validateTarBzip2Archive(
            archiveURL: archiveURL,
            expectedTopLevelDirectoryName: option.extractedDirectoryName
        )
        try await extractTarBzip2(archiveURL: archiveURL, destinationDirectory: extractionRoot)
        try Task.checkCancellation()

        let extractedDirectory = extractionRoot.appendingPathComponent(option.extractedDirectoryName, isDirectory: true)
        try validateExtractedModelDirectory(extractedDirectory, extractionRoot: extractionRoot)
        guard SherpaOnnxModelStorageSupport.isModelDirectoryValid(extractedDirectory, option: option) else {
            throw NSError(
                domain: "SherpaOnnxModelManager",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded archive is missing required model files."]
            )
        }

        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: destinationDirectory)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: extractedDirectory, to: destinationDirectory)
        try? FileManager.default.removeItem(at: downloadDirectory)
        setDownloadingState(
            progress: 1,
            completed: option.archiveBytes,
            total: option.archiveBytes,
            currentFile: nil,
            completedFiles: 1,
            totalFiles: 1,
            for: id
        )
    }

    private func validateTarBzip2Archive(
        archiveURL: URL,
        expectedTopLevelDirectoryName: String
    ) async throws {
        let listing = try await runTar(arguments: ["-tjf", archiveURL.path], capturesOutput: true)
        let expectedPrefix = "\(expectedTopLevelDirectoryName)/"
        let entries = listing
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        guard !entries.isEmpty else {
            throw NSError(
                domain: "SherpaOnnxModelManager",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded archive is empty."]
            )
        }

        for entry in entries {
            let normalizedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedEntry.isEmpty else { continue }
            guard !normalizedEntry.hasPrefix("/"),
                  normalizedEntry == expectedTopLevelDirectoryName || normalizedEntry.hasPrefix(expectedPrefix)
            else {
                throw NSError(
                    domain: "SherpaOnnxModelManager",
                    code: 1003,
                    userInfo: [NSLocalizedDescriptionKey: "Downloaded archive contains files outside the expected model directory."]
                )
            }

            let pathComponents = normalizedEntry
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard pathComponents.allSatisfy({ $0 != "." && $0 != ".." }) else {
                throw NSError(
                    domain: "SherpaOnnxModelManager",
                    code: 1004,
                    userInfo: [NSLocalizedDescriptionKey: "Downloaded archive contains unsafe path components."]
                )
            }
        }
    }

    private func validateExtractedModelDirectory(_ directory: URL, extractionRoot: URL) throws {
        let rootPath = extractionRoot.standardizedFileURL.path
        guard directory.standardizedFileURL.path.hasPrefix(rootPath + "/") else {
            throw NSError(
                domain: "SherpaOnnxModelManager",
                code: 1005,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded archive extracted outside the temporary directory."]
            )
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw NSError(
                    domain: "SherpaOnnxModelManager",
                    code: 1006,
                    userInfo: [NSLocalizedDescriptionKey: "Downloaded archive contains symbolic links."]
                )
            }
        }
    }

    private func extractTarBzip2(archiveURL: URL, destinationDirectory: URL) async throws {
        _ = try await runTar(arguments: ["-xjf", archiveURL.path, "-C", destinationDirectory.path])
    }

    private func runTar(arguments: [String], capturesOutput: Bool = false) async throws -> String {
        let processBox = CancellableProcessBox()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                try Task.checkCancellation()

                let process = Process()
                processBox.set(process)
                defer { processBox.clear() }

                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = arguments
                let stderrPipe = Pipe()
                let stdoutPipe = capturesOutput ? Pipe() : nil
                process.standardError = stderrPipe
                if let stdoutPipe {
                    process.standardOutput = stdoutPipe
                }
                try process.run()
                let stdoutData = stdoutPipe?.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if processBox.wasCancelled {
                    throw CancellationError()
                }

                guard process.terminationStatus == 0 else {
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8) ?? "tar failed"
                    throw NSError(
                        domain: "SherpaOnnxModelManager",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )
                }

                if let stdoutData {
                    return String(data: stdoutData, encoding: .utf8) ?? ""
                }
                return ""
            }.value
        } onCancel: {
            processBox.cancel()
        }
    }

    private func resolvedState(for id: SherpaOnnxModelID, isDownloaded: Bool) -> ModelState {
        if id == currentModelID {
            return state
        }
        if let stored = stateByID[id] {
            return stored
        }
        return isDownloaded ? .downloaded : .notDownloaded
    }

    private func setState(_ newState: ModelState, for id: SherpaOnnxModelID) {
        if id == currentModelID {
            state = newState
        } else {
            stateByID[id] = newState
        }
    }

    private func setPausedStatusMessage(_ message: String?, for id: SherpaOnnxModelID) {
        if id == currentModelID {
            pausedStatusMessage = message
        } else {
            pausedStatusMessageByID[id] = message
        }
    }

    private func markModelDownloaded(id: SherpaOnnxModelID) {
        setPausedStatusMessage(nil, for: id)
        downloadedStateByID[id] = true
        localSizeTextByID[id] = nil
        setState(.downloaded, for: id)
    }

    private func markModelNotDownloaded(id: SherpaOnnxModelID, clearsLocalSize: Bool = false) {
        downloadedStateByID[id] = false
        if clearsLocalSize {
            localSizeTextByID[id] = nil
        }
        setPausedStatusMessage(nil, for: id)
        setState(.notDownloaded, for: id)
    }

    private func completedBytes(from state: ModelState) -> Int64 {
        switch state {
        case .downloading(_, let completed, _, _, _, _),
             .paused(_, let completed, _, _, _, _):
            return completed
        default:
            return 0
        }
    }

    private func setDownloadingState(
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int,
        for id: SherpaOnnxModelID
    ) {
        setState(
            .downloading(
                progress: progress,
                completed: completed,
                total: total,
                currentFile: currentFile,
                completedFiles: completedFiles,
                totalFiles: totalFiles
            ),
            for: id
        )
    }

    private func cancelDownloadProgressTask(for id: SherpaOnnxModelID) {
        downloadProgressTasksByID[id]?.cancel()
        downloadProgressTasksByID[id] = nil
    }

    private func setPausedState(from state: ModelState, option: SherpaOnnxModelOption, for id: SherpaOnnxModelID) {
        switch state {
        case .downloading(let progress, let completed, let total, let currentFile, let completedFiles, let totalFiles):
            setState(
                .paused(
                    progress: progress,
                    completed: completed,
                    total: total,
                    currentFile: currentFile,
                    completedFiles: completedFiles,
                    totalFiles: totalFiles
                ),
                for: id
            )
        default:
            setState(
                .paused(
                    progress: 0,
                    completed: 0,
                    total: option.archiveBytes,
                    currentFile: option.downloadURL.lastPathComponent,
                    completedFiles: 0,
                    totalFiles: 1
                ),
                for: id
            )
        }
    }

    private func downloadSourceTargetKey(for id: SherpaOnnxModelID) -> String {
        ModelDownloadSourceSelectionStore.targetKey(namespace: "sherpa-onnx", identifier: id.rawValue)
    }

    private func clearSelectedDownloadSource(for id: SherpaOnnxModelID) {
        ModelDownloadSourceSelectionStore.clearSourceID(for: downloadSourceTargetKey(for: id))
    }

    private func shouldReuseSavedDownloadSource(for id: SherpaOnnxModelID) -> Bool {
        if case .paused = state(for: id) {
            return true
        }
        let downloadDirectory = SherpaOnnxModelStorageSupport.downloadDirectory(
            for: id,
            rootDirectory: writeRootURL()
        )
        return FileManager.default.directoryContainsRegularFiles(at: downloadDirectory)
    }

    private func cleanupDownload(id: SherpaOnnxModelID) {
        try? FileManager.default.removeItem(
            at: SherpaOnnxModelStorageSupport.downloadDirectory(for: id, rootDirectory: writeRootURL())
        )
    }

    private func writeRootURL() -> URL {
        ModelStorageDirectoryManager.resolvedWriteRootURL()
    }

    private func readableRootURLs() -> [URL] {
        ModelStorageDirectoryManager.resolvedReadableRootURLs()
    }

    private func writeModelDirectory(for id: SherpaOnnxModelID) -> URL {
        SherpaOnnxModelStorageSupport.modelDirectory(for: id, rootDirectory: writeRootURL())
    }

    private func readableModelDirectory(for id: SherpaOnnxModelID, requireValid: Bool) -> URL? {
        allReadableModelDirectories(for: id, requireValid: requireValid).first
    }

    private func allReadableModelDirectories(for id: SherpaOnnxModelID, requireValid: Bool) -> [URL] {
        let option = option(for: id)
        return readableRootURLs().compactMap { root in
            let directory = SherpaOnnxModelStorageSupport.modelDirectory(for: id, rootDirectory: root)
            guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
            if requireValid && !SherpaOnnxModelStorageSupport.isModelDirectoryValid(directory, option: option) {
                return nil
            }
            return directory
        }
    }
}

private nonisolated final class CancellableProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = isCancelled
        lock.unlock()

        if shouldTerminate {
            process.terminate()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let process = process
        lock.unlock()

        process?.terminate()
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }
}

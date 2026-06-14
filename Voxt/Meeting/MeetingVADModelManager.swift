import Combine
import Foundation
import HuggingFace
import MLXAudioVAD

@MainActor
final class MeetingVADModelManager: ObservableObject {
    enum State: Equatable {
        case notDownloaded
        case downloaded
        case downloading(
            progress: Double,
            completed: Int64,
            total: Int64,
            currentFile: String?,
            completedFiles: Int,
            totalFiles: Int
        )
        case error(String)

        var isDownloading: Bool {
            if case .downloading = self {
                return true
            }
            return false
        }
    }

    @Published private(set) var state: State = .notDownloaded
    @Published private(set) var remoteSizeText = MeetingVADModelStorage.fallbackRemoteSizeText

    private var downloadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?

    init() {
        refresh()
        fetchRemoteSize()
    }

    func refresh() {
        if MeetingVADModelStorage.modelDirectory(requireValid: true) != nil {
            state = .downloaded
        } else if !state.isDownloading {
            state = .notDownloaded
        }
        fetchRemoteSize()
    }

    func downloadSilero() {
        downloadSelectedModel()
    }

    func downloadSelectedModel() {
        guard downloadTask == nil else { return }
        state = .downloading(
            progress: 0,
            completed: 0,
            total: 0,
            currentFile: nil,
            completedFiles: 0,
            totalFiles: 0
        )
        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.downloadTask = nil
            }
            do {
                let directory = try await self.downloadWithFallback()
                try self.validateDownloadedModel(at: directory)
                self.state = .downloaded
                VoxtLog.info("Meeting Silero VAD download complete. repo=\(MeetingVADModelStorage.repo)")
            } catch is CancellationError {
                self.state = .notDownloaded
            } catch {
                self.state = .error(error.localizedDescription)
                VoxtLog.error("Meeting Silero VAD download failed. error=\(error.localizedDescription)")
            }
        }
    }

    func retrySileroDownload() {
        downloadSelectedModel()
    }

    private func fetchRemoteSize() {
        sizeTask?.cancel()
        sizeTask = Task { [weak self] in
            guard let self else { return }
            let preferredBaseURL = Self.preferredHubBaseURL()
            do {
                let info = try await MLXModelDownloadSupport.fetchModelSizeInfo(
                    repo: MeetingVADModelStorage.repo,
                    baseURL: preferredBaseURL,
                    userAgent: MLXModelManager.hubUserAgent,
                    formatByteCount: MLXModelStorageSupport.formatByteCount
                )
                guard !Task.isCancelled else { return }
                self.remoteSizeText = info.text
            } catch {
                guard !Task.isCancelled else { return }
                self.remoteSizeText = MeetingVADModelStorage.fallbackRemoteSizeText
            }
        }
    }

    private func downloadWithFallback() async throws -> URL {
        let preferredBaseURL = Self.preferredHubBaseURL()
        do {
            return try await download(using: preferredBaseURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let fallback = Self.fallbackHubBaseURL(from: preferredBaseURL) else {
                throw error
            }
            VoxtLog.warning(
                "Primary meeting Silero VAD download endpoint failed. Retrying with mirror. baseURL=\(preferredBaseURL.absoluteString), error=\(error.localizedDescription)"
            )
            MeetingVADModelStorage.clearHubCache()
            return try await download(using: fallback)
        }
    }

    private func download(using baseURL: URL) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: MeetingVADModelStorage.repo),
              let modelDir = MeetingVADModelStorage.writeModelDirectory(),
              let tempDir = MeetingVADModelStorage.downloadTempDirectory()
        else {
            throw NSError(
                domain: "Voxt.MeetingVAD",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "Invalid meeting VAD model identifier."]
            )
        }

        if MeetingVADModelStorage.isValidModelDirectory(modelDir) {
            return modelDir
        }

        let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
            ?? Bundle.main.object(forInfoDictionaryKey: "HF_TOKEN") as? String
        let session = MLXModelDownloadSupport.makeDownloadSession(for: baseURL)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let entries = try await MLXModelDownloadSupport.fetchModelEntries(
            repo: repoID.description,
            baseURL: baseURL,
            session: session,
            userAgent: MLXModelManager.hubUserAgent
        )
        guard !entries.isEmpty else {
            throw MLXModelDownloadSupport.DownloadValidationError.emptyFileList
        }

        let totalBytes = max(entries.reduce(Int64(0)) { $0 + max($1.size ?? 0, 0) }, 1)
        let totalFiles = entries.count
        var completedBytes: Int64 = 0

        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            let expectedBytes = max(entry.size ?? 0, 0)
            let progress = Progress(totalUnitCount: max(expectedBytes, 1))
            let baseCompletedBytes = completedBytes
            let completedFiles = index
            updateDownloadingState(
                progress: Double(completedBytes) / Double(totalBytes),
                completed: completedBytes,
                total: totalBytes,
                currentFile: entry.path,
                completedFiles: completedFiles,
                totalFiles: totalFiles
            )

            let sampler = Task { [weak self] in
                let startTime = Date()
                while !Task.isCancelled {
                    let inFlight = CustomLLMModelDownloadSupport.inFlightBytes(
                        progress: progress,
                        expectedFileBytes: expectedBytes,
                        startTime: startTime
                    )
                    let currentCompleted = min(baseCompletedBytes + inFlight, totalBytes)
                    await MainActor.run {
                        self?.updateDownloadingState(
                            progress: Double(currentCompleted) / Double(totalBytes),
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

            let destination = try MLXModelStorageSupport.destinationFileURL(for: entry.path, under: tempDir)
            if MLXModelDownloadSupport.canReuseExistingDownload(
                at: destination,
                expectedSize: entry.size,
                fileManager: .default
            ) {
                let fileSize = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                completedBytes += max(expectedBytes, fileSize)
            } else {
                let remoteURL = try MLXModelDownloadSupport.fileResolveURL(
                    baseURL: baseURL,
                    repo: repoID.description,
                    path: entry.path
                )
                _ = try await ResumableModelDownloadSupport.download(
                    ResumableDownloadDescriptor(
                        sourceURL: remoteURL,
                        destinationURL: destination,
                        relativePath: entry.path,
                        expectedSize: expectedBytes > 0 ? expectedBytes : nil,
                        userAgent: MLXModelManager.hubUserAgent,
                        bearerToken: token,
                        disableProxy: MLXModelDownloadSupport.isMirrorHost(baseURL)
                    ),
                    progress: progress
                )
                completedBytes += max(expectedBytes, max(progress.completedUnitCount, 0))
            }

            updateDownloadingState(
                progress: min(1, Double(completedBytes) / Double(totalBytes)),
                completed: min(completedBytes, totalBytes),
                total: totalBytes,
                currentFile: nil,
                completedFiles: completedFiles + 1,
                totalFiles: totalFiles
            )
        }

        guard MeetingVADModelStorage.isValidModelDirectory(tempDir) else {
            throw MLXModelDownloadSupport.DownloadValidationError.missingFiles
        }
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
        try FileManager.default.moveItem(at: tempDir, to: modelDir)
        return modelDir
    }

    private func validateDownloadedModel(at directory: URL) throws {
        _ = try SileroVAD.fromModelDirectory(directory)
    }

    private func updateDownloadingState(
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int
    ) {
        guard state.isDownloading else { return }
        state = .downloading(
            progress: min(max(progress, 0), 1),
            completed: min(max(completed, 0), max(total, 0)),
            total: max(total, 0),
            currentFile: currentFile,
            completedFiles: min(max(completedFiles, 0), max(totalFiles, 0)),
            totalFiles: max(totalFiles, 0)
        )
    }

    private static func preferredHubBaseURL() -> URL {
        let useMirror = UserDefaults.standard.object(forKey: AppPreferenceKey.useHfMirror) as? Bool ?? false
        return useMirror ? MLXModelManager.mirrorHubBaseURL : MLXModelManager.defaultHubBaseURL
    }

    private static func fallbackHubBaseURL(from baseURL: URL) -> URL? {
        guard baseURL.host?.contains("hf-mirror.com") != true else { return nil }
        return MLXModelManager.mirrorHubBaseURL
    }

}

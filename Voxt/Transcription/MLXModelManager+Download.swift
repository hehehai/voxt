import Foundation
import CFNetwork
import HuggingFace

enum MLXModelDownloadSupport {
    private static let modelEntryAllowedExtensions: Set<String> = ["safetensors", "json", "txt", "wav", "jinja"]
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    enum DownloadValidationError: LocalizedError {
        case missingFiles
        case sizeMismatch(expected: Int64, actual: Int64)
        case emptyFileList

        var errorDescription: String? {
            switch self {
            case .missingFiles:
                return "Downloaded files are incomplete."
            case .sizeMismatch(let expected, let actual):
                let expectedText = byteFormatter.string(fromByteCount: expected)
                let actualText = byteFormatter.string(fromByteCount: actual)
                return "Download incomplete (expected ~\(expectedText), got \(actualText))."
            case .emptyFileList:
                return "No downloadable files were found for this model."
            }
        }
    }

    enum DownloadNetworkError: LocalizedError {
        case mirrorRejected(statusCode: Int)
        case modelUnavailable(repo: String, statusCode: Int)
        case metadataRequestFailed(statusCode: Int)
        case invalidServerResponse

        var errorDescription: String? {
            switch self {
            case .mirrorRejected(let statusCode):
                return "China mirror rejected request (HTTP \(statusCode))."
            case .modelUnavailable(let repo, let statusCode):
                return "Model repository unavailable (\(repo), HTTP \(statusCode))."
            case .metadataRequestFailed(let statusCode):
                return "Model metadata request failed (HTTP \(statusCode))."
            case .invalidServerResponse:
                return "Invalid response from model server."
            }
        }
    }

    struct ModelFileEntry: Hashable {
        let path: String
        let size: Int64?
    }

    static func canReuseExistingDownload(
        at destinationURL: URL,
        expectedSize: Int64?,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: destinationURL.path),
              let fileSize = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        else {
            return false
        }

        let size = Int64(fileSize)
        if let expectedSize, expectedSize > 0 {
            return size == expectedSize
        }
        return size > 0
    }

    static func isRetryableTransportError(_ error: Error) -> Bool {
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
                 .cannotLoadFromNetwork,
                 .badServerResponse:
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

    static func pauseMessageForInterruptedDownload(_ error: Error) -> String? {
        if let conflictMessage = VoxtNetworkSession.directModeConflictMessage(for: error) {
            return conflictMessage
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return AppLocalization.localizedString("Network issue detected. Check your connection, then click Continue to resume.")
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorResourceUnavailable,
                 NSURLErrorCannotLoadFromNetwork:
                return AppLocalization.localizedString("Network issue detected. Check your network or proxy settings, then click Continue to resume.")
            default:
                break
            }
        }

        if let loopError = error as? ResumableDownloadLoopError,
           loopError.recoverableReason == "stall-timeout"
        {
            return AppLocalization.localizedString("Download stalled due to a network issue. Click Continue to resume.")
        }

        return nil
    }

    static func makeDownloadSession(for baseURL: URL) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = false

        if isMirrorHost(baseURL) {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: false,
                kCFNetworkProxiesHTTPSEnable as String: false,
                kCFNetworkProxiesSOCKSEnable as String: false,
            ]
        }

        return URLSession(configuration: configuration)
    }

    static func makeHubClient(
        session: URLSession,
        baseURL: URL,
        cache: HubCache,
        token: String?,
        userAgent: String
    ) -> HubClient {
        if let token, !token.isEmpty {
            return HubClient(
                session: session,
                host: baseURL,
                userAgent: userAgent,
                bearerToken: token,
                cache: cache
            )
        }
        return HubClient(
            session: session,
            host: baseURL,
            userAgent: userAgent,
            cache: cache
        )
    }

    static func fetchModelEntries(
        repo: String,
        baseURL: URL,
        session: URLSession,
        userAgent: String
    ) async throws -> [ModelFileEntry] {
        guard let encoded = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/models/\(encoded)/tree/main?recursive=1")
        else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadNetworkError.invalidServerResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if isMirrorHost(baseURL), [401, 403].contains(httpResponse.statusCode) {
                throw DownloadNetworkError.mirrorRejected(statusCode: httpResponse.statusCode)
            }
            if [401, 404].contains(httpResponse.statusCode) {
                throw DownloadNetworkError.modelUnavailable(repo: repo, statusCode: httpResponse.statusCode)
            }
            throw DownloadNetworkError.metadataRequestFailed(statusCode: httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return json.compactMap { item in
            guard (item["type"] as? String) == "file" else { return nil }
            let path = (item["path"] as? String) ?? ""
            let ext = path.split(separator: ".").last.map(String.init) ?? ""
            guard modelEntryAllowedExtensions.contains(ext.lowercased()) else { return nil }
            let size: Int64?
            if let raw = item["size"] as? Int {
                size = Int64(raw)
            } else if let raw = item["size"] as? Int64 {
                size = raw
            } else {
                size = nil
            }
            return ModelFileEntry(path: path, size: size)
        }
    }

    static func fetchModelSizeInfo(
        repo: String,
        baseURL: URL,
        userAgent: String,
        formatByteCount: @Sendable (Int64) -> String
    ) async throws -> (bytes: Int64, text: String) {
        let entries = try await fetchModelEntries(
            repo: repo,
            baseURL: baseURL,
            session: makeDownloadSession(for: baseURL),
            userAgent: userAgent
        )
        let total = entries.reduce(Int64(0)) { partial, entry in
            partial + max(entry.size ?? 0, 0)
        }

        guard total > 0 else { return (0, "Unknown") }
        return (total, formatByteCount(total))
    }

    static func fileResolveURL(baseURL: URL, repo: String, path: String) throws -> URL {
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

    static func validateDownloadedModel(
        at url: URL,
        sizeState: MLXModelManager.ModelSizeState,
        downloadSizeTolerance: Double,
        fileManager: FileManager
    ) throws {
        let files = allFiles(at: url, fileManager: fileManager)
        let hasWeights = files.contains { file in
            guard file.pathExtension.lowercased() == "safetensors" else { return false }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size > 0
        }
        let configValid = files.contains { file in
            guard file.lastPathComponent.lowercased() == "config.json" else { return false }
            guard let data = try? Data(contentsOf: file) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) != nil
        }

        guard hasWeights, configValid else {
            throw DownloadValidationError.missingFiles
        }

        if case .ready(let expectedBytes, _) = sizeState,
           expectedBytes > 0,
           let actualBytesRaw = try? fileManager.allocatedSizeOfDirectory(at: url)
        {
            let actualBytes = Int64(actualBytesRaw)
            let minimumBytes = Int64(Double(expectedBytes) * downloadSizeTolerance)
            if actualBytes < minimumBytes {
                throw DownloadValidationError.sizeMismatch(expected: expectedBytes, actual: actualBytes)
            }
        }
    }

    static func clearDirectory(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for item in contents {
                try? fileManager.removeItem(at: item)
            }
            try fileManager.removeItem(at: url)
        }
    }

    static func isModelDirectoryValid(_ directory: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return false }

        if let topLevelItems = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            let malformed = topLevelItems.contains { item in
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDirectory else { return false }
                let ext = item.pathExtension.lowercased()
                return ext == "json" || ext == "safetensors" || ext == "txt" || ext == "wav"
            }
            if malformed {
                return false
            }
        }

        let files = allFiles(at: directory, fileManager: fileManager)
        let hasWeights = files.contains { file in
            guard file.pathExtension.lowercased() == "safetensors" else { return false }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size > 0
        }
        let rootConfig = directory.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: rootConfig.path),
              let rootConfigData = try? Data(contentsOf: rootConfig),
              (try? JSONSerialization.jsonObject(with: rootConfigData)) != nil
        else {
            return false
        }

        return hasWeights
    }

    static func isMirrorHost(_ url: URL) -> Bool {
        url.host?.contains("hf-mirror.com") == true
    }

    private static func allFiles(at root: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let isRegular = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isRegular {
                files.append(fileURL)
            }
        }
        return files
    }
}

struct ResumableDownloadDescriptor {
    let sourceURL: URL
    let destinationURL: URL
    let relativePath: String
    let expectedSize: Int64?
    let userAgent: String
    let bearerToken: String?
    let disableProxy: Bool
    let policy: ResumableDownloadPolicy
    let protocolClasses: [AnyClass]?

    init(
        sourceURL: URL,
        destinationURL: URL,
        relativePath: String,
        expectedSize: Int64?,
        userAgent: String,
        bearerToken: String? = nil,
        disableProxy: Bool,
        policy: ResumableDownloadPolicy = .default,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.relativePath = relativePath
        self.expectedSize = expectedSize
        self.userAgent = userAgent
        self.bearerToken = bearerToken
        self.disableProxy = disableProxy
        self.policy = policy
        self.protocolClasses = protocolClasses
    }
}

struct ResumableDownloadPolicy {
    let resumeThresholdBytes: Int64
    let stallTimeout: Duration
    let stallPollInterval: Duration
    let maxRecoveryAttempts: Int
    let initialBackoffSeconds: Double
    let maxBackoffSeconds: Double

    static let `default` = ResumableDownloadPolicy(
        resumeThresholdBytes: 64 * 1024 * 1024,
        stallTimeout: .seconds(45),
        stallPollInterval: .seconds(5),
        maxRecoveryAttempts: 5,
        initialBackoffSeconds: 1,
        maxBackoffSeconds: 30
    )
}

struct ResumableDownloadState: Codable, Equatable {
    let relativePath: String
    let sourceURL: String
    let expectedSize: Int64
    let etag: String
    let downloadedBytes: Int64
    let updatedAt: Date
    let rangeSupported: Bool
}

struct ResumableDownloadResult: Equatable {
    let bytesDownloaded: Int64
    let resumedFromBytes: Int64
    let rangeSupported: Bool
}

private enum ResumableDownloadAttemptOutcome {
    case completed(ResumableDownloadResult)
    case restartFromZero(reason: String)
    case recoverableFailure(reason: String)
    case fatal(Error)
}

private enum ResumableDownloadError: LocalizedError {
    case badServerResponse
    case unexpectedStatusCode(Int)
    case missingETag
    case invalidContentRange(String)
    case inconsistentExpectedSize(expected: Int64, actual: Int64)
    case inconsistentPartialState

    var errorDescription: String? {
        switch self {
        case .badServerResponse:
            return "Invalid response from model server."
        case .unexpectedStatusCode(let code):
            return "Download failed (HTTP \(code))."
        case .missingETag:
            return "Download server did not provide a stable ETag for resume."
        case .invalidContentRange(let value):
            return "Download resume returned invalid Content-Range: \(value)"
        case .inconsistentExpectedSize(let expected, let actual):
            return "Download size mismatch (expected \(expected), got \(actual))."
        case .inconsistentPartialState:
            return "Stored partial download state is inconsistent."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .unexpectedStatusCode(let code):
            return code >= 500 || code == 429 || code == 408
        default:
            return false
        }
    }
}

private struct ResumableResponseMetadata {
    let statusCode: Int
    let etag: String?
    let acceptRanges: Bool
    let contentLength: Int64?
    let contentRange: (start: Int64, end: Int64, total: Int64?)?

    nonisolated init(response: HTTPURLResponse) {
        statusCode = response.statusCode
        etag = response.value(forHTTPHeaderField: "ETag")
        let acceptRangesValue = response.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() ?? ""
        acceptRanges = acceptRangesValue.contains("bytes")
        contentLength = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        contentRange = Self.parseContentRange(response.value(forHTTPHeaderField: "Content-Range"))
    }

    private nonisolated static func parseContentRange(_ value: String?) -> (start: Int64, end: Int64, total: Int64?)? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes ") else { return nil }
        let payload = trimmed.dropFirst("bytes ".count)
        let pieces = payload.split(separator: "/")
        guard pieces.count == 2 else { return nil }
        let rangePart = pieces[0].split(separator: "-")
        guard rangePart.count == 2,
              let start = Int64(rangePart[0]),
              let end = Int64(rangePart[1])
        else {
            return nil
        }
        let total = pieces[1] == "*" ? nil : Int64(pieces[1])
        return (start, end, total)
    }
}

private final class ResumableDownloadAttemptDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum ResponseDecision {
        case stream(fileHandle: FileHandle, initialState: ResumableDownloadState, rangeSupported: Bool, resumedFromBytes: Int64)
        case restartFromZero(reason: String)
        case completedExisting(ResumableDownloadResult)
    }

    private let progress: Progress
    private let descriptor: ResumableDownloadDescriptor
    private let responseHandler: @Sendable (HTTPURLResponse) throws -> ResponseDecision
    private let stateWriter: @Sendable (ResumableDownloadState) -> Void
    private let partURL: URL
    private let stateURL: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ResumableDownloadAttemptOutcome, Error>?
    private var task: URLSessionTask?
    private var fileHandle: FileHandle?
    private var currentState: ResumableDownloadState?
    private var controlledOutcome: ResumableDownloadAttemptOutcome?
    private var lastProgressAt = Date()
    private var bytesWrittenThisAttempt: Int64 = 0
    private var totalBytesWritten: Int64 = 0
    private var rangeSupported = false
    private var resumedFromBytes: Int64 = 0
    private var hasFinished = false
    private var lastPersistedBytes: Int64 = 0
    private var lastPersistedAt = Date.distantPast

    init(
        progress: Progress,
        descriptor: ResumableDownloadDescriptor,
        partURL: URL,
        stateURL: URL,
        responseHandler: @escaping @Sendable (HTTPURLResponse) throws -> ResponseDecision,
        stateWriter: @escaping @Sendable (ResumableDownloadState) -> Void
    ) {
        self.progress = progress
        self.descriptor = descriptor
        self.partURL = partURL
        self.stateURL = stateURL
        self.responseHandler = responseHandler
        self.stateWriter = stateWriter
    }

    func attach(task: URLSessionTask, continuation: CheckedContinuation<ResumableDownloadAttemptOutcome, Error>) {
        lock.lock()
        self.task = task
        self.continuation = continuation
        lock.unlock()
    }

    func progressTimedOut(stallTimeout: Duration) {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }
        let elapsed = Date().timeIntervalSince(lastProgressAt)
        guard elapsed >= ResumableModelDownloadSupport.seconds(from: stallTimeout) else {
            lock.unlock()
            return
        }
        controlledOutcome = .recoverableFailure(reason: "stall-timeout")
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func currentLastProgressAt() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return lastProgressAt
    }

    func currentStateSnapshot() -> ResumableDownloadState? {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            controlledOutcome = .recoverableFailure(reason: ResumableDownloadError.badServerResponse.localizedDescription)
            completionHandler(.cancel)
            return
        }

        do {
            switch try responseHandler(httpResponse) {
            case .stream(let fileHandle, let initialState, let rangeSupported, let resumedFromBytes):
                lock.lock()
                self.fileHandle = fileHandle
                self.currentState = initialState
                self.rangeSupported = rangeSupported
                self.resumedFromBytes = resumedFromBytes
                self.totalBytesWritten = resumedFromBytes
                self.lastPersistedBytes = resumedFromBytes
                self.lastPersistedAt = Date()
                self.lastProgressAt = Date()
                lock.unlock()
                progress.totalUnitCount = max(initialState.expectedSize, 1)
                progress.completedUnitCount = max(resumedFromBytes, 0)
                stateWriter(initialState)
                completionHandler(.allow)
            case .restartFromZero(let reason):
                controlledOutcome = .restartFromZero(reason: reason)
                completionHandler(.cancel)
            case .completedExisting(let result):
                controlledOutcome = .completed(result)
                completionHandler(.cancel)
            }
        } catch {
            controlledOutcome = .fatal(error)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let fileHandle = self.fileHandle
        lock.unlock()

        guard let fileHandle else { return }
        do {
            try fileHandle.write(contentsOf: data)
            let chunkBytes = Int64(data.count)
            lock.lock()
            bytesWrittenThisAttempt += chunkBytes
            totalBytesWritten += chunkBytes
            lastProgressAt = Date()
            let totalBytesWritten = self.totalBytesWritten
            let currentState = self.currentState
            lock.unlock()

            progress.completedUnitCount = max(totalBytesWritten, 0)
            maybePersistProgress(totalBytesWritten: totalBytesWritten, currentState: currentState)
        } catch {
            controlledOutcome = .fatal(error)
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        hasFinished = true
        let continuation = self.continuation
        self.continuation = nil
        let controlledOutcome = self.controlledOutcome
        let currentState = self.currentState
        let fileHandle = self.fileHandle
        let totalBytesWritten = self.totalBytesWritten
        let rangeSupported = self.rangeSupported
        let resumedFromBytes = self.resumedFromBytes
        lock.unlock()

        try? fileHandle?.close()

        if let currentState {
            stateWriter(
                ResumableDownloadState(
                    relativePath: currentState.relativePath,
                    sourceURL: currentState.sourceURL,
                    expectedSize: currentState.expectedSize,
                    etag: currentState.etag,
                    downloadedBytes: totalBytesWritten,
                    updatedAt: Date(),
                    rangeSupported: currentState.rangeSupported
                )
            )
        }

        guard let continuation else { return }

        if let controlledOutcome {
            switch controlledOutcome {
            case .fatal(let error):
                continuation.resume(throwing: error)
            default:
                continuation.resume(returning: controlledOutcome)
            }
            return
        }

        if let error {
            if (error as? URLError)?.code == .cancelled {
                continuation.resume(throwing: CancellationError())
            } else {
                continuation.resume(throwing: error)
            }
            return
        }

        continuation.resume(
            returning: .completed(
                ResumableDownloadResult(
                    bytesDownloaded: totalBytesWritten,
                    resumedFromBytes: resumedFromBytes,
                    rangeSupported: rangeSupported
                )
            )
        )
    }

    private func maybePersistProgress(totalBytesWritten: Int64, currentState: ResumableDownloadState?) {
        guard let currentState else { return }
        let now = Date()
        let shouldPersist = totalBytesWritten - lastPersistedBytes >= 5 * 1024 * 1024
            || now.timeIntervalSince(lastPersistedAt) >= 5
        guard shouldPersist else { return }
        lock.lock()
        lastPersistedBytes = totalBytesWritten
        lastPersistedAt = now
        lock.unlock()
        stateWriter(
            ResumableDownloadState(
                relativePath: currentState.relativePath,
                sourceURL: currentState.sourceURL,
                expectedSize: currentState.expectedSize,
                etag: currentState.etag,
                downloadedBytes: totalBytesWritten,
                updatedAt: now,
                rangeSupported: currentState.rangeSupported
            )
        )
    }
}

enum ResumableModelDownloadSupport {
    static func download(
        _ descriptor: ResumableDownloadDescriptor,
        progress: Progress
    ) async throws -> ResumableDownloadResult {
        let fileManager = FileManager.default
        let partURL = partialFileURL(for: descriptor.destinationURL)
        let stateURL = stateFileURL(for: partURL)
        try fileManager.createDirectory(
            at: descriptor.destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let supportsByteResume = max(descriptor.expectedSize ?? 0, 0) >= descriptor.policy.resumeThresholdBytes
        var recoveryAttempts = 0
        var restartFromZeroCount = 0

        while true {
            try Task.checkCancellation()

            if !supportsByteResume {
                try purgePartialArtifacts(for: descriptor.destinationURL)
            }

            let partialSize = fileSize(at: partURL)
            let loadedState = loadState(from: stateURL)
            let preparedState = try prepareState(
                descriptor: descriptor,
                supportsByteResume: supportsByteResume,
                partialURL: partURL,
                partialSize: partialSize,
                loadedState: loadedState
            )

            do {
                let result = try await performAttempt(
                    descriptor: descriptor,
                    partURL: partURL,
                    stateURL: stateURL,
                    existingState: preparedState,
                    progress: progress
                )
                try finalizeDownload(
                    descriptor: descriptor,
                    partURL: partURL,
                    stateURL: stateURL,
                    result: result
                )
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ResumableDownloadError {
                if error.isRetryable {
                    recoveryAttempts += 1
                    guard recoveryAttempts <= descriptor.policy.maxRecoveryAttempts else {
                        throw error
                    }
                    VoxtLog.warning("Resumable download retry \(recoveryAttempts)/\(descriptor.policy.maxRecoveryAttempts): \(descriptor.relativePath) (\(error.localizedDescription))")
                    try? await Task.sleep(for: backoffDuration(policy: descriptor.policy, attempt: recoveryAttempts))
                    continue
                }
                throw error
            } catch let error as URLError {
                recoveryAttempts += 1
                guard recoveryAttempts <= descriptor.policy.maxRecoveryAttempts,
                      MLXModelDownloadSupport.isRetryableTransportError(error)
                else {
                    throw error
                }
                VoxtLog.warning("Resumable download retry \(recoveryAttempts)/\(descriptor.policy.maxRecoveryAttempts): \(descriptor.relativePath) (\(error.localizedDescription))")
                try? await Task.sleep(for: backoffDuration(policy: descriptor.policy, attempt: recoveryAttempts))
            } catch {
                if let restartReason = (error as? ResumableDownloadLoopError)?.restartReason {
                    restartFromZeroCount += 1
                    guard restartFromZeroCount <= descriptor.policy.maxRecoveryAttempts else {
                        throw error
                    }
                    VoxtLog.warning("Resumable download restart from zero: \(descriptor.relativePath) (\(restartReason))")
                    try purgePartialArtifacts(for: descriptor.destinationURL)
                    continue
                }
                if let recoverableReason = (error as? ResumableDownloadLoopError)?.recoverableReason {
                    recoveryAttempts += 1
                    guard recoveryAttempts <= descriptor.policy.maxRecoveryAttempts else {
                        throw error
                    }
                    VoxtLog.warning("Resumable download recoverable retry \(recoveryAttempts)/\(descriptor.policy.maxRecoveryAttempts): \(descriptor.relativePath) (\(recoverableReason))")
                    try? await Task.sleep(for: backoffDuration(policy: descriptor.policy, attempt: recoveryAttempts))
                    continue
                }
                throw error
            }
        }
    }

    static func purgePartialArtifacts(for destinationURL: URL) throws {
        let fileManager = FileManager.default
        let partURL = partialFileURL(for: destinationURL)
        let sidecarURL = stateFileURL(for: partURL)
        if fileManager.fileExists(atPath: partURL.path) {
            try? fileManager.removeItem(at: partURL)
        }
        if fileManager.fileExists(atPath: sidecarURL.path) {
            try? fileManager.removeItem(at: sidecarURL)
        }
    }

    static func purgePartialArtifactsRecursively(at rootURL: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasSuffix(".part") || name.hasSuffix(".part.json") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func performAttempt(
        descriptor: ResumableDownloadDescriptor,
        partURL: URL,
        stateURL: URL,
        existingState: ResumableDownloadState?,
        progress: Progress
    ) async throws -> ResumableDownloadResult {
        let initialBytes = fileSize(at: partURL)
        let shouldResume = existingState?.rangeSupported == true && initialBytes > 0
        let expectedTotal = max(existingState?.expectedSize ?? descriptor.expectedSize ?? 0, 0)

        progress.totalUnitCount = max(expectedTotal, 1)
        progress.completedUnitCount = max(initialBytes, 0)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = false
        if descriptor.disableProxy {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: false,
                kCFNetworkProxiesHTTPSEnable as String: false,
                kCFNetworkProxiesSOCKSEnable as String: false,
            ]
        }
        if let protocolClasses = descriptor.protocolClasses {
            configuration.protocolClasses = protocolClasses
        }

        let responseHandler: @Sendable (HTTPURLResponse) throws -> ResumableDownloadAttemptDelegate.ResponseDecision = { response in
            let metadata = ResumableResponseMetadata(response: response)
            switch metadata.statusCode {
            case 200:
                if shouldResume {
                    return .restartFromZero(reason: "server-ignored-range")
                }

                let remoteETag = metadata.etag
                guard let remoteETag, !remoteETag.isEmpty else {
                    throw ResumableDownloadError.missingETag
                }

                let actualExpectedSize = max(metadata.contentLength ?? descriptor.expectedSize ?? 0, 0)
                if let descriptorExpected = descriptor.expectedSize,
                   descriptorExpected > 0,
                   actualExpectedSize > 0,
                   descriptorExpected != actualExpectedSize
                {
                    throw ResumableDownloadError.inconsistentExpectedSize(expected: descriptorExpected, actual: actualExpectedSize)
                }

                if FileManager.default.fileExists(atPath: partURL.path) {
                    try? FileManager.default.removeItem(at: partURL)
                }
                FileManager.default.createFile(atPath: partURL.path, contents: nil)
                let fileHandle = try FileHandle(forWritingTo: partURL)
                let initialState = ResumableDownloadState(
                    relativePath: descriptor.relativePath,
                    sourceURL: descriptor.sourceURL.absoluteString,
                    expectedSize: actualExpectedSize,
                    etag: remoteETag,
                    downloadedBytes: 0,
                    updatedAt: Date(),
                    rangeSupported: metadata.acceptRanges
                )
                return .stream(
                    fileHandle: fileHandle,
                    initialState: initialState,
                    rangeSupported: metadata.acceptRanges,
                    resumedFromBytes: 0
                )
            case 206:
                guard shouldResume else {
                    return .restartFromZero(reason: "unexpected-partial-content")
                }
                guard let contentRange = metadata.contentRange else {
                    throw ResumableDownloadError.invalidContentRange(response.value(forHTTPHeaderField: "Content-Range") ?? "")
                }
                guard contentRange.start == initialBytes else {
                    return .restartFromZero(reason: "content-range-mismatch")
                }
                if let stateETag = existingState?.etag,
                   let remoteETag = metadata.etag,
                   remoteETag != stateETag
                {
                    return .restartFromZero(reason: "etag-changed")
                }
                guard let existingState else {
                    throw ResumableDownloadError.inconsistentPartialState
                }
                let fileHandle = try FileHandle(forWritingTo: partURL)
                try fileHandle.seekToEnd()
                let updatedState = ResumableDownloadState(
                    relativePath: existingState.relativePath,
                    sourceURL: descriptor.sourceURL.absoluteString,
                    expectedSize: contentRange.total ?? existingState.expectedSize,
                    etag: metadata.etag ?? existingState.etag,
                    downloadedBytes: initialBytes,
                    updatedAt: Date(),
                    rangeSupported: true
                )
                return .stream(
                    fileHandle: fileHandle,
                    initialState: updatedState,
                    rangeSupported: true,
                    resumedFromBytes: initialBytes
                )
            case 416:
                if let descriptorExpected = descriptor.expectedSize,
                   descriptorExpected > 0,
                   initialBytes == descriptorExpected
                {
                    return .completedExisting(
                        ResumableDownloadResult(
                            bytesDownloaded: initialBytes,
                            resumedFromBytes: initialBytes,
                            rangeSupported: true
                        )
                    )
                }
                return .restartFromZero(reason: "range-not-satisfiable")
            default:
                throw ResumableDownloadError.unexpectedStatusCode(metadata.statusCode)
            }
        }

        let delegate = ResumableDownloadAttemptDelegate(
            progress: progress,
            descriptor: descriptor,
            partURL: partURL,
            stateURL: stateURL,
            responseHandler: responseHandler
        ) { state in
            saveState(state, to: stateURL)
        }
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: descriptor.sourceURL)
        request.setValue(descriptor.userAgent, forHTTPHeaderField: "User-Agent")
        if let bearerToken = descriptor.bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if shouldResume {
            request.setValue("bytes=\(initialBytes)-", forHTTPHeaderField: "Range")
            if let etag = existingState?.etag, !etag.isEmpty {
                request.setValue(etag, forHTTPHeaderField: "If-Range")
            }
            VoxtLog.model("Resumable download resuming: file=\(descriptor.relativePath), offset=\(initialBytes)")
        } else {
            VoxtLog.model("Resumable download starting: file=\(descriptor.relativePath), url=\(descriptor.sourceURL.absoluteString)")
        }

        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler(operation: {
            let watchdog = Task { [policy = descriptor.policy] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: policy.stallPollInterval)
                    delegate.progressTimedOut(stallTimeout: policy.stallTimeout)
                }
            }
            defer {
                watchdog.cancel()
                session.invalidateAndCancel()
            }
            let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ResumableDownloadAttemptOutcome, Error>) in
                delegate.attach(task: task, continuation: continuation)
                task.resume()
            }

            switch outcome {
            case .completed(let result):
                return result
            case .restartFromZero(let reason):
                throw ResumableDownloadLoopError.restartFromZero(reason: reason)
            case .recoverableFailure(let reason):
                throw ResumableDownloadLoopError.recoverable(reason: reason)
            case .fatal(let error):
                throw error
            }
        }, onCancel: {
            task.cancel()
            session.invalidateAndCancel()
        })
    }

    private static func prepareState(
        descriptor: ResumableDownloadDescriptor,
        supportsByteResume: Bool,
        partialURL: URL,
        partialSize: Int64,
        loadedState: ResumableDownloadState?
    ) throws -> ResumableDownloadState? {
        guard partialSize > 0 else {
            if loadedState != nil {
                try purgePartialArtifacts(for: descriptor.destinationURL)
            }
            return nil
        }

        guard supportsByteResume else {
            try purgePartialArtifacts(for: descriptor.destinationURL)
            return nil
        }

        guard let loadedState,
              !loadedState.etag.isEmpty,
              loadedState.expectedSize > 0
        else {
            try purgePartialArtifacts(for: descriptor.destinationURL)
            return nil
        }

        if let expectedSize = descriptor.expectedSize,
           expectedSize > 0,
           loadedState.expectedSize != expectedSize
        {
            try purgePartialArtifacts(for: descriptor.destinationURL)
            return nil
        }

        if partialSize > loadedState.expectedSize {
            try purgePartialArtifacts(for: descriptor.destinationURL)
            return nil
        }

        if partialSize == loadedState.expectedSize {
            return ResumableDownloadState(
                relativePath: loadedState.relativePath,
                sourceURL: loadedState.sourceURL,
                expectedSize: loadedState.expectedSize,
                etag: loadedState.etag,
                downloadedBytes: partialSize,
                updatedAt: Date(),
                rangeSupported: loadedState.rangeSupported
            )
        }

        return ResumableDownloadState(
            relativePath: loadedState.relativePath,
            sourceURL: loadedState.sourceURL,
            expectedSize: loadedState.expectedSize,
            etag: loadedState.etag,
            downloadedBytes: partialSize,
            updatedAt: Date(),
            rangeSupported: loadedState.rangeSupported
        )
    }

    private static func finalizeDownload(
        descriptor: ResumableDownloadDescriptor,
        partURL: URL,
        stateURL: URL,
        result: ResumableDownloadResult
    ) throws {
        let expectedSize = descriptor.expectedSize ?? result.bytesDownloaded
        if expectedSize > 0, result.bytesDownloaded != expectedSize {
            throw ResumableDownloadError.inconsistentExpectedSize(expected: expectedSize, actual: result.bytesDownloaded)
        }

        if FileManager.default.fileExists(atPath: descriptor.destinationURL.path) {
            try? FileManager.default.removeItem(at: descriptor.destinationURL)
        }
        try FileManager.default.moveItem(at: partURL, to: descriptor.destinationURL)
        try? FileManager.default.removeItem(at: stateURL)
        VoxtLog.model("Resumable download completed: file=\(descriptor.relativePath), bytes=\(result.bytesDownloaded), resumedFrom=\(result.resumedFromBytes)")
    }

    private static func partialFileURL(for destinationURL: URL) -> URL {
        destinationURL.appendingPathExtension("part")
    }

    private static func stateFileURL(for partURL: URL) -> URL {
        partURL.appendingPathExtension("json")
    }

    private nonisolated static func loadState(from url: URL) -> ResumableDownloadState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let relativePath = object["relativePath"] as? String,
              let sourceURL = object["sourceURL"] as? String,
              let expectedSize = object["expectedSize"] as? NSNumber,
              let etag = object["etag"] as? String,
              let downloadedBytes = object["downloadedBytes"] as? NSNumber,
              let updatedAtInterval = object["updatedAt"] as? NSNumber,
              let rangeSupported = object["rangeSupported"] as? Bool
        else {
            return nil
        }
        return ResumableDownloadState(
            relativePath: relativePath,
            sourceURL: sourceURL,
            expectedSize: expectedSize.int64Value,
            etag: etag,
            downloadedBytes: downloadedBytes.int64Value,
            updatedAt: Date(timeIntervalSince1970: updatedAtInterval.doubleValue),
            rangeSupported: rangeSupported
        )
    }

    private nonisolated static func saveState(_ state: ResumableDownloadState, to url: URL) {
        let object: [String: Any] = [
            "relativePath": state.relativePath,
            "sourceURL": state.sourceURL,
            "expectedSize": state.expectedSize,
            "etag": state.etag,
            "downloadedBytes": state.downloadedBytes,
            "updatedAt": state.updatedAt.timeIntervalSince1970,
            "rangeSupported": state.rangeSupported,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private nonisolated static func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func backoffDuration(policy: ResumableDownloadPolicy, attempt: Int) -> Duration {
        let exponent = max(0, attempt - 1)
        let rawSeconds = min(
            policy.initialBackoffSeconds * pow(2, Double(exponent)),
            policy.maxBackoffSeconds
        )
        let jitter = min(0.25 * rawSeconds, 1.0)
        let randomized = rawSeconds + Double.random(in: 0 ... jitter)
        return .milliseconds(Int64(randomized * 1000))
    }

    nonisolated static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private enum ResumableDownloadLoopError: Error {
    case restartFromZero(reason: String)
    case recoverable(reason: String)

    var restartReason: String? {
        switch self {
        case .restartFromZero(let reason):
            return reason
        case .recoverable:
            return nil
        }
    }

    var recoverableReason: String? {
        switch self {
        case .restartFromZero:
            return nil
        case .recoverable(let reason):
            return reason
        }
    }
}

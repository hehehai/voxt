// WhisperKitDownloadSupport.swift
// Provides Whisper Kit Download Support for transcription engines.

import Foundation
import CFNetwork

struct WhisperKitRepoTreeItem {
    let path: String
    let type: String
    let size: Int64
}

final class WhisperKitDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: Progress
    private let stagedDownloadURL: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadedFileResult: Result<URL, Error>?

    init(progress: Progress, stagedDownloadURL: URL) {
        self.progress = progress
        self.stagedDownloadURL = stagedDownloadURL
    }

    func attach(_ continuation: CheckedContinuation<(URL, URLResponse), Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            progress.totalUnitCount = totalBytesExpectedToWrite
        }
        progress.completedUnitCount = max(totalBytesWritten, 0)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let result: Result<URL, Error>
        do {
            try? FileManager.default.removeItem(at: stagedDownloadURL)
            try FileManager.default.moveItem(at: location, to: stagedDownloadURL)
            result = .success(stagedDownloadURL)
        } catch {
            let nsError = error as NSError
            let failureReason = nsError.localizedFailureReason ?? "no failure reason"
            result = .failure(
                NSError(
                    domain: "WhisperKitModelManager",
                    code: 1005,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Failed to stage downloaded Whisper file.",
                        NSLocalizedFailureReasonErrorKey: "move \(location.path) -> \(stagedDownloadURL.path) failed: \(failureReason)",
                        NSUnderlyingErrorKey: error,
                    ]
                )
            )
        }

        lock.lock()
        downloadedFileResult = result
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            resume(with: .failure(error))
            return
        }

        lock.lock()
        let downloadedFileResult = self.downloadedFileResult
        lock.unlock()

        guard let response = task.response,
              let downloadedFileResult else {
            resume(with: .failure(URLError(.badServerResponse)))
            return
        }

        switch downloadedFileResult {
        case .success(let stagedDownloadURL):
            resume(with: .success((stagedDownloadURL, response)))
        case .failure(let error):
            resume(with: .failure(error))
        }
    }

    private func resume(with result: Result<(URL, URLResponse), Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

enum WhisperKitDownloadSupport {
    nonisolated static func shouldRetryAfterMetadataRecovery(for error: Error) -> Bool {
        let combined = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return combined.contains("invalid metadata")
            || combined.contains("metadata file")
            || combined.contains("file metadata must have been retrieved")
    }

    nonisolated static func fetchRepoTreeItems(
        baseURL: URL,
        repo: String,
        userAgent: String
    ) async throws -> [WhisperKitRepoTreeItem] {
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
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

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

            return WhisperKitRepoTreeItem(path: path, type: type, size: size)
        }
    }

    nonisolated static func fileResolveURL(baseURL: URL, repo: String, path: String) throws -> URL {
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

    static func downloadFile(
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
        let temporaryURL = destinationURL.appendingPathExtension("download")
        try? FileManager.default.removeItem(at: temporaryURL)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let delegate = WhisperKitDownloadDelegate(progress: progress, stagedDownloadURL: temporaryURL)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: remoteURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (downloadedURL, response) = try await withCheckedThrowingContinuation { continuation in
            delegate.attach(continuation)
            let task = session.downloadTask(with: request)
            task.resume()
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if response.expectedContentLength > 0 {
            progress.totalUnitCount = response.expectedContentLength
        }

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: downloadedURL, to: destinationURL)
        if let finalSize = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            progress.completedUnitCount = Int64(finalSize)
        }
    }

    nonisolated static func describeError(_ error: Error) -> String {
        let nsError = error as NSError
        let failureReason = nsError.localizedFailureReason ?? "nil"
        let recoverySuggestion = nsError.localizedRecoverySuggestion ?? "nil"
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)
            .map { "underlyingDomain=\($0.domain), underlyingCode=\($0.code), underlyingDesc=\($0.localizedDescription)" }
            ?? "underlying=nil"
        return "domain=\(nsError.domain), code=\(nsError.code), desc=\(nsError.localizedDescription), failureReason=\(failureReason), recovery=\(recoverySuggestion), \(underlying)"
    }

    nonisolated static func inFlightBytes(
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
}

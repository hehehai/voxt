import Foundation
import HuggingFace

enum CustomLLMModelDownloadSupport {
    private static let chatTemplateFileNames: Set<String> = [
        "chat_template.jinja",
        "chat_template.json",
    ]

    struct DownloadContext {
        let repoID: Repo.ID
        let entries: [MLXModelDownloadSupport.ModelFileEntry]
        let totalBytes: Int64
    }

    nonisolated static func fallbackHubBaseURL(
        from baseURL: URL,
        mirrorBaseURL: URL
    ) -> URL? {
        guard baseURL.host?.contains("hf-mirror.com") != true else { return nil }
        return mirrorBaseURL
    }

    nonisolated static func inFlightBytes(
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

    static func makeDownloadContext(
        repo: String,
        baseURL: URL,
        userAgent: String,
        token: String?,
        cache: HubCache = .default
    ) async throws -> DownloadContext {
        guard let repoID = Repo.ID(rawValue: repo) else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model identifier"]
            )
        }

        let session = MLXModelDownloadSupport.makeDownloadSession(for: baseURL)
        let entries = try await MLXModelDownloadSupport.fetchModelEntries(
            repo: repoID.description,
            baseURL: baseURL,
            session: session,
            userAgent: userAgent
        )
        guard !entries.isEmpty else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "No downloadable files were found for this model."]
            )
        }

        let totalBytes = max(entries.reduce(Int64(0)) { $0 + max($1.size ?? 0, 0) }, 1)
        return DownloadContext(
            repoID: repoID,
            entries: entries,
            totalBytes: totalBytes
        )
    }

    static func fetchRemoteSizeInfo(
        repo: String,
        preferredBaseURL: URL,
        mirrorBaseURL: URL,
        userAgent: String,
        formatByteCount: @Sendable (Int64) -> String
    ) async throws -> (bytes: Int64, text: String) {
        do {
            return try await MLXModelDownloadSupport.fetchModelSizeInfo(
                repo: repo,
                baseURL: preferredBaseURL,
                userAgent: userAgent,
                formatByteCount: formatByteCount
            )
        } catch {
            guard let fallbackBaseURL = fallbackHubBaseURL(
                from: preferredBaseURL,
                mirrorBaseURL: mirrorBaseURL
            ) else {
                throw error
            }
            VoxtLog.warning(
                "Primary custom LLM metadata endpoint failed. Retrying with mirror. repo=\(repo), baseURL=\(preferredBaseURL.absoluteString), error=\(error.localizedDescription)"
            )
            return try await MLXModelDownloadSupport.fetchModelSizeInfo(
                repo: repo,
                baseURL: fallbackBaseURL,
                userAgent: userAgent,
                formatByteCount: formatByteCount
            )
        }
    }

    static func hasUsableChatTemplate(in directory: URL, fileManager: FileManager = .default) -> Bool {
        for fileName in chatTemplateFileNames {
            if fileManager.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
                return true
            }
        }

        let tokenizerConfigURL = directory.appendingPathComponent("tokenizer_config.json")
        guard fileManager.fileExists(atPath: tokenizerConfigURL.path),
              let data = try? Data(contentsOf: tokenizerConfigURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }

        if let template = object["chat_template"] as? String {
            return !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    static func repairMissingChatTemplateIfNeeded(
        repo: String,
        directory: URL,
        preferredBaseURL: URL,
        mirrorBaseURL: URL,
        userAgent: String,
        token: String?
    ) async {
        guard !hasUsableChatTemplate(in: directory) else { return }

        do {
            let repaired = try await downloadMissingChatTemplateFilesIfNeeded(
                repo: repo,
                directory: directory,
                baseURL: preferredBaseURL,
                userAgent: userAgent,
                token: token
            )
            if repaired {
                VoxtLog.model("Custom LLM chat template repaired from repo metadata: \(repo)")
                return
            }
        } catch {
            if let fallbackBaseURL = fallbackHubBaseURL(
                from: preferredBaseURL,
                mirrorBaseURL: mirrorBaseURL
            ) {
                do {
                    let repaired = try await downloadMissingChatTemplateFilesIfNeeded(
                        repo: repo,
                        directory: directory,
                        baseURL: fallbackBaseURL,
                        userAgent: userAgent,
                        token: token
                    )
                    if repaired {
                        VoxtLog.model("Custom LLM chat template repaired from mirror metadata: \(repo)")
                        return
                    }
                } catch {
                    VoxtLog.warning("Custom LLM chat template repair failed via mirror. repo=\(repo), error=\(error.localizedDescription)")
                }
            } else {
                VoxtLog.warning("Custom LLM chat template repair failed. repo=\(repo), error=\(error.localizedDescription)")
            }
        }
    }

    private static func downloadMissingChatTemplateFilesIfNeeded(
        repo: String,
        directory: URL,
        baseURL: URL,
        userAgent: String,
        token: String?
    ) async throws -> Bool {
        guard let repoID = Repo.ID(rawValue: repo) else { return false }

        let session = MLXModelDownloadSupport.makeDownloadSession(for: baseURL)
        let entries = try await MLXModelDownloadSupport.fetchModelEntries(
            repo: repoID.description,
            baseURL: baseURL,
            session: session,
            userAgent: userAgent
        )

        let templateEntries = entries.filter { entry in
            chatTemplateFileNames.contains(URL(fileURLWithPath: entry.path).lastPathComponent.lowercased())
        }

        guard !templateEntries.isEmpty else { return false }

        var downloadedAny = false
        for entry in templateEntries {
            let destination = try CustomLLMModelStorageSupport.destinationFileURL(
                for: entry.path,
                under: directory
            )
            if MLXModelDownloadSupport.canReuseExistingDownload(
                at: destination,
                expectedSize: entry.size,
                fileManager: .default
            ) {
                continue
            }

            let descriptor = ResumableDownloadDescriptor(
                sourceURL: try MLXModelDownloadSupport.fileResolveURL(
                    baseURL: baseURL,
                    repo: repoID.description,
                    path: entry.path
                ),
                destinationURL: destination,
                relativePath: entry.path,
                expectedSize: entry.size,
                userAgent: userAgent,
                bearerToken: token,
                disableProxy: MLXModelDownloadSupport.isMirrorHost(baseURL)
            )
            _ = try await ResumableModelDownloadSupport.download(
                descriptor,
                progress: Progress(totalUnitCount: max(entry.size ?? 1, 1))
            )
            downloadedAny = true
        }

        return downloadedAny && hasUsableChatTemplate(in: directory)
    }
}

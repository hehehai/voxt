import Foundation

struct WhisperKitModelCatalog {
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let description: String
        let remoteSizeText: String
    }

    private struct PresentationMetadata {
        let ratingText: String
        let tagKeys: [String]
    }

    nonisolated static let defaultModelID = "base"

    nonisolated static let availableModels: [Option] = [
        .init(
            id: "tiny",
            title: "Whisper Tiny",
            description: "Smallest footprint for quick local drafts.",
            remoteSizeText: "Unknown"
        ),
        .init(
            id: "base",
            title: "Whisper Base",
            description: "Default balance between quality and speed.",
            remoteSizeText: "Unknown"
        ),
        .init(
            id: "small",
            title: "Whisper Small",
            description: "Higher quality with moderate local resource usage.",
            remoteSizeText: "Unknown"
        ),
        .init(
            id: "medium",
            title: "Whisper Medium",
            description: "High accuracy with heavier local compute requirements.",
            remoteSizeText: "Unknown"
        ),
        .init(
            id: "large-v3",
            title: "Whisper Large v3",
            description: "Best accuracy in the curated list with the largest footprint.",
            remoteSizeText: "Unknown"
        ),
    ]

    nonisolated private static let presentationByID: [String: PresentationMetadata] = [
        "tiny": PresentationMetadata(ratingText: "4.0", tagKeys: ["Multilingual", "Fast"]),
        "base": PresentationMetadata(ratingText: "4.3", tagKeys: ["Multilingual", "Balanced"]),
        "small": PresentationMetadata(ratingText: "4.5", tagKeys: ["Multilingual", "Balanced"]),
        "medium": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Accurate"]),
        "large-v3": PresentationMetadata(ratingText: "4.9", tagKeys: ["Multilingual", "Accurate"]),
    ]

    nonisolated private static let knownRemoteSizeBytesByID: [String: Int64] = [
        "tiny": 76_635_397,
        "base": 146_719_453,
        "small": 486_487_465,
        "medium": 1_529_654_233,
        "large-v3": 3_090_319_899,
    ]

    nonisolated static func canonicalModelID(_ modelID: String) -> String {
        availableModels.contains(where: { $0.id == modelID }) ? modelID : defaultModelID
    }

    nonisolated static func displayTitle(for modelID: String) -> String {
        let canonicalModelID = canonicalModelID(modelID)
        return availableModels.first(where: { $0.id == canonicalModelID })?.title ?? canonicalModelID
    }

    nonisolated static func ratingText(for modelID: String) -> String {
        presentationByID[canonicalModelID(modelID)]?.ratingText ?? "4.3"
    }

    nonisolated static func catalogTagKeys(for modelID: String) -> [String] {
        presentationByID[canonicalModelID(modelID)]?.tagKeys ?? ["Multilingual"]
    }

    nonisolated static func fallbackRemoteSizeText(id: String) -> String? {
        fallbackRemoteSizeInfo(id: id)?.text
    }

    nonisolated static func fallbackRemoteSizeInfo(id: String) -> (bytes: Int64, text: String)? {
        let canonicalModelID = canonicalModelID(id)
        guard let bytes = knownRemoteSizeBytesByID[canonicalModelID] else { return nil }
        return (bytes, WhisperKitModelStorageSupport.formatByteCount(bytes))
    }

    nonisolated static func topLevelFolderName(for modelID: String) -> String {
        "openai_whisper-\(canonicalModelID(modelID))"
    }
}

enum WhisperKitModelStorageSupport {
    nonisolated private static let remoteSizeCachePreferenceKey = "whisperRemoteSizeCache"

    nonisolated static func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    nonisolated static func loadPersistedRemoteSizeCache() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: remoteSizeCachePreferenceKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    nonisolated static func savePersistedRemoteSizeCache(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: remoteSizeCachePreferenceKey)
    }

    nonisolated static func downloadRootURL(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent("whisperkit", isDirectory: true)
    }

    nonisolated static func clearRepositoryMetadataCache(rootDirectory: URL) {
        let metadataCacheURL = downloadRootURL(rootDirectory: rootDirectory)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("download", isDirectory: true)
        try? FileManager.default.removeItem(at: metadataCacheURL)
    }
}

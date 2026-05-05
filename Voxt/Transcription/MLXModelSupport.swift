import Foundation
import HuggingFace

struct MLXModelCatalog {
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let description: String
    }

    private struct PresentationMetadata {
        let ratingText: String
        let tagKeys: [String]
    }

    nonisolated static let defaultModelRepo = "mlx-community/Qwen3-ASR-0.6B-4bit"

    nonisolated private static let realtimeCapableModelRepos: Set<String> = [
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
        "mlx-community/Voxtral-Mini-4B-Realtime-6bit",
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16",
    ]

    nonisolated private static let legacyModelRepoMap: [String: String] = [
        "mlx-community/Parakeet-0.6B": "mlx-community/parakeet-tdt-0.6b-v3",
        "mlx-community/GLM-ASR-Nano-4bit": "mlx-community/GLM-ASR-Nano-2512-4bit",
        "mlx-community/Voxtral-Mini-4B-Realtime-2602": "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16",
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-6bit": "mlx-community/Voxtral-Mini-4B-Realtime-6bit",
        "mlx-community/FireRedASR2": "mlx-community/FireRedASR2-AED-mlx",
    ]

    nonisolated static let availableModels: [Option] = [
        Option(
            id: "mlx-community/Qwen3-ASR-0.6B-4bit",
            title: "Qwen3-ASR 0.6B (4bit)",
            description: "Balanced quality and speed with low memory use."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-0.6B-6bit",
            title: "Qwen3-ASR 0.6B (6bit)",
            description: "Better accuracy than 4bit with moderate memory usage."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-0.6B-8bit",
            title: "Qwen3-ASR 0.6B (8bit)",
            description: "Highest-precision 0.6B option with higher memory usage."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-0.6B-bf16",
            title: "Qwen3-ASR 0.6B (bf16)",
            description: "Full-precision 0.6B model for maximum local quality."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-1.7B-4bit",
            title: "Qwen3-ASR 1.7B (4bit)",
            description: "Larger multilingual model tuned for accuracy at lower memory cost."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-1.7B-6bit",
            title: "Qwen3-ASR 1.7B (6bit)",
            description: "High-accuracy flagship model with a balanced memory footprint."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-1.7B-8bit",
            title: "Qwen3-ASR 1.7B (8bit)",
            description: "High-precision 1.7B model for stronger recognition quality."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-1.7B-bf16",
            title: "Qwen3-ASR 1.7B (bf16)",
            description: "High accuracy flagship model with higher memory usage."
        ),
        Option(
            id: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
            title: "Voxtral Realtime Mini 4B (4bit)",
            description: "Realtime-oriented multilingual model with reduced memory use."
        ),
        Option(
            id: "mlx-community/Voxtral-Mini-4B-Realtime-6bit",
            title: "Voxtral Realtime Mini 4B (6bit)",
            description: "Realtime multilingual model with a balanced quality-to-memory tradeoff."
        ),
        Option(
            id: "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16",
            title: "Voxtral Realtime Mini 4B (fp16)",
            description: "Realtime-oriented model with larger memory footprint."
        ),
        Option(
            id: "beshkenadze/cohere-transcribe-03-2026-mlx-fp16",
            title: "Cohere Transcribe 03-2026 (fp16)",
            description: "High-accuracy multilingual encoder-decoder model with punctuation enabled."
        ),
        Option(
            id: "mlx-community/parakeet-tdt_ctc-110m",
            title: "Parakeet TDT CTC 110M",
            description: "Smallest Parakeet option for fast English transcription."
        ),
        Option(
            id: "mlx-community/parakeet-tdt-0.6b-v2",
            title: "Parakeet TDT 0.6B v2",
            description: "Lightweight English TDT model for lower-memory local transcription."
        ),
        Option(
            id: "mlx-community/parakeet-tdt-0.6b-v3",
            title: "Parakeet TDT 0.6B v3",
            description: "Fast, lightweight English STT."
        ),
        Option(
            id: "mlx-community/parakeet-ctc-0.6b",
            title: "Parakeet CTC 0.6B",
            description: "Compact English CTC model with low memory use."
        ),
        Option(
            id: "mlx-community/parakeet-rnnt-0.6b",
            title: "Parakeet RNNT 0.6B",
            description: "Compact English RNNT model for streaming-friendly decoding."
        ),
        Option(
            id: "mlx-community/parakeet-tdt-1.1b",
            title: "Parakeet TDT 1.1B",
            description: "Larger English model with improved recognition quality."
        ),
        Option(
            id: "mlx-community/parakeet-tdt_ctc-1.1b",
            title: "Parakeet TDT CTC 1.1B",
            description: "Higher-capacity Parakeet hybrid model for English transcription."
        ),
        Option(
            id: "mlx-community/parakeet-ctc-1.1b",
            title: "Parakeet CTC 1.1B",
            description: "Higher-accuracy English CTC model with increased memory usage."
        ),
        Option(
            id: "mlx-community/parakeet-rnnt-1.1b",
            title: "Parakeet RNNT 1.1B",
            description: "Higher-accuracy English RNNT model for heavier local setups."
        ),
        Option(
            id: "mlx-community/GLM-ASR-Nano-2512-4bit",
            title: "GLM-ASR Nano (4bit)",
            description: "Smallest footprint for quick drafts."
        ),
        Option(
            id: "mlx-community/granite-4.0-1b-speech-5bit",
            title: "Granite Speech 4.0 1B (5bit)",
            description: "Multilingual speech model with stronger accuracy than the nano tier."
        ),
        Option(
            id: "mlx-community/FireRedASR2-AED-mlx",
            title: "FireRed ASR 2",
            description: "Beam-search ASR model tuned for higher offline accuracy."
        ),
        Option(
            id: "mlx-community/SenseVoiceSmall",
            title: "SenseVoice Small",
            description: "Fast multilingual model with built-in language and event detection."
        )
    ]

    nonisolated private static let presentationByRepo: [String: PresentationMetadata] = [
        "mlx-community/Qwen3-ASR-0.6B-4bit": PresentationMetadata(ratingText: "4.4", tagKeys: ["Multilingual", "Fast"]),
        "mlx-community/Qwen3-ASR-0.6B-6bit": PresentationMetadata(ratingText: "4.5", tagKeys: ["Multilingual", "Balanced"]),
        "mlx-community/Qwen3-ASR-0.6B-8bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Multilingual", "Balanced"]),
        "mlx-community/Qwen3-ASR-0.6B-bf16": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Accurate"]),
        "mlx-community/Qwen3-ASR-1.7B-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Balanced"]),
        "mlx-community/Qwen3-ASR-1.7B-6bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Multilingual", "Accurate"]),
        "mlx-community/Qwen3-ASR-1.7B-8bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Multilingual", "Accurate"]),
        "mlx-community/Qwen3-ASR-1.7B-bf16": PresentationMetadata(ratingText: "4.9", tagKeys: ["Multilingual", "Accurate"]),
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Multilingual", "Realtime", "Fast"]),
        "mlx-community/Voxtral-Mini-4B-Realtime-6bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Realtime", "Balanced"]),
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Realtime", "Accurate"]),
        "beshkenadze/cohere-transcribe-03-2026-mlx-fp16": PresentationMetadata(ratingText: "4.8", tagKeys: ["Multilingual", "Accurate"]),
        "mlx-community/parakeet-tdt_ctc-110m": PresentationMetadata(ratingText: "4.0", tagKeys: ["Fast"]),
        "mlx-community/parakeet-tdt-0.6b-v2": PresentationMetadata(ratingText: "4.2", tagKeys: ["Fast"]),
        "mlx-community/parakeet-tdt-0.6b-v3": PresentationMetadata(ratingText: "4.3", tagKeys: ["Fast"]),
        "mlx-community/parakeet-ctc-0.6b": PresentationMetadata(ratingText: "4.2", tagKeys: ["Balanced"]),
        "mlx-community/parakeet-rnnt-0.6b": PresentationMetadata(ratingText: "4.3", tagKeys: ["Balanced"]),
        "mlx-community/parakeet-tdt-1.1b": PresentationMetadata(ratingText: "4.6", tagKeys: ["Accurate"]),
        "mlx-community/parakeet-tdt_ctc-1.1b": PresentationMetadata(ratingText: "4.6", tagKeys: ["Accurate"]),
        "mlx-community/parakeet-ctc-1.1b": PresentationMetadata(ratingText: "4.5", tagKeys: ["Accurate"]),
        "mlx-community/parakeet-rnnt-1.1b": PresentationMetadata(ratingText: "4.5", tagKeys: ["Accurate"]),
        "mlx-community/GLM-ASR-Nano-2512-4bit": PresentationMetadata(ratingText: "4.1", tagKeys: ["Multilingual", "Fast"]),
        "mlx-community/granite-4.0-1b-speech-5bit": PresentationMetadata(ratingText: "4.5", tagKeys: ["Multilingual", "Balanced"]),
        "mlx-community/FireRedASR2-AED-mlx": PresentationMetadata(ratingText: "4.8", tagKeys: ["Multilingual", "Accurate"]),
        "mlx-community/SenseVoiceSmall": PresentationMetadata(ratingText: "4.5", tagKeys: ["Multilingual", "Fast"]),
    ]

    nonisolated private static let knownRemoteSizeBytesByRepo: [String: Int64] = [
        "mlx-community/Qwen3-ASR-0.6B-4bit": 712_781_279,
        "mlx-community/Qwen3-ASR-0.6B-6bit": 861_777_567,
        "mlx-community/Qwen3-ASR-0.6B-8bit": 1_010_773_761,
        "mlx-community/Qwen3-ASR-0.6B-bf16": 1_569_438_434,
        "mlx-community/Qwen3-ASR-1.7B-4bit": 1_607_633_106,
        "mlx-community/Qwen3-ASR-1.7B-6bit": 2_037_746_046,
        "mlx-community/Qwen3-ASR-1.7B-8bit": 2_467_859_030,
        "mlx-community/Qwen3-ASR-1.7B-bf16": 4_080_710_353,
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit": 3_148_833_321,
        "mlx-community/Voxtral-Mini-4B-Realtime-6bit": 3_624_337_564,
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16": 8_885_525_001,
        "beshkenadze/cohere-transcribe-03-2026-mlx-fp16": 4_132_564_062,
        "mlx-community/parakeet-tdt_ctc-110m": 458_961_098,
        "mlx-community/parakeet-tdt-0.6b-v2": 2_471_865_399,
        "mlx-community/parakeet-tdt-0.6b-v3": 2_509_044_141,
        "mlx-community/parakeet-ctc-0.6b": 2_435_805_367,
        "mlx-community/parakeet-rnnt-0.6b": 2_467_370_930,
        "mlx-community/parakeet-tdt-1.1b": 4_282_575_398,
        "mlx-community/parakeet-tdt_ctc-1.1b": 4_286_788_359,
        "mlx-community/parakeet-ctc-1.1b": 4_250_996_647,
        "mlx-community/parakeet-rnnt-1.1b": 4_282_562_211,
        "mlx-community/GLM-ASR-Nano-2512-4bit": 1_288_437_789,
        "mlx-community/granite-4.0-1b-speech-5bit": 2_226_816_753,
        "mlx-community/FireRedASR2-AED-mlx": 4_566_119_694,
        "mlx-community/SenseVoiceSmall": 936_491_235,
    ]

    nonisolated static func canonicalModelRepo(_ repo: String) -> String {
        legacyModelRepoMap[repo] ?? repo
    }

    nonisolated static func displayTitle(for repo: String) -> String {
        let canonicalRepo = canonicalModelRepo(repo)
        return availableModels.first(where: { $0.id == canonicalRepo })?.title ?? canonicalRepo
    }

    nonisolated static func isRealtimeCapableModelRepo(_ repo: String) -> Bool {
        realtimeCapableModelRepos.contains(canonicalModelRepo(repo))
    }

    nonisolated static func ratingText(for repo: String) -> String {
        presentationByRepo[canonicalModelRepo(repo)]?.ratingText ?? "4.3"
    }

    nonisolated static func catalogTagKeys(for repo: String) -> [String] {
        presentationByRepo[canonicalModelRepo(repo)]?.tagKeys ?? []
    }

    nonisolated static func isMultilingualModelRepo(_ repo: String) -> Bool {
        catalogTagKeys(for: repo).contains("Multilingual")
    }

    nonisolated static func fallbackRemoteSizeText(repo: String) -> String? {
        fallbackRemoteSizeInfo(repo: repo)?.text
    }

    nonisolated static func fallbackRemoteSizeInfo(repo: String) -> (bytes: Int64, text: String)? {
        let canonicalRepo = canonicalModelRepo(repo)
        guard let bytes = knownRemoteSizeBytesByRepo[canonicalRepo] else { return nil }
        return (bytes, MLXModelStorageSupport.formatByteCount(bytes))
    }
}

enum MLXModelStorageSupport {
    nonisolated private static let remoteSizeCachePreferenceKey = "mlxRemoteSizeCache"

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

    nonisolated static func cacheDirectory(for repo: String, rootDirectory: URL) -> URL? {
        guard let repoID = Repo.ID(rawValue: repo) else { return nil }
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        return rootDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)
    }

    nonisolated static func hubCache(rootDirectory: URL) -> HubCache {
        HubCache(cacheDirectory: rootDirectory)
    }

    nonisolated static func destinationFileURL(for entryPath: String, under directory: URL) throws -> URL {
        let base = directory.standardizedFileURL
        let destination = base.appendingPathComponent(entryPath).standardizedFileURL
        let basePrefix = base.path.hasSuffix("/") ? base.path : "\(base.path)/"
        guard destination.path.hasPrefix(basePrefix) else {
            throw NSError(
                domain: "MLXModelManager",
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

    nonisolated static func clearHubCache(for repoID: Repo.ID, rootDirectory: URL = HubCache.default.cacheDirectory) {
        let cache = hubCache(rootDirectory: rootDirectory)
        let repoDir = cache.repoDirectory(repo: repoID, kind: .model)
        let metadataDir = cache.metadataDirectory(repo: repoID, kind: .model)
        try? FileManager.default.removeItem(at: repoDir)
        try? FileManager.default.removeItem(at: metadataDir)
    }
}

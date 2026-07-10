// MLXModelSupport.swift
// Provides MLXModel Support for transcription engines.

import Foundation
import HuggingFace

enum MLXLiveMode: Equatable {
    case batchPreview
    case nativeQwenLive
    case nativeStreamingLive
    case nativeNemotronLive
    case nativeVoxtralLive
}

enum MLXWhisperMigrationSupport {
    nonisolated static let defaultRepo = "mlx-community/whisper-large-v3-turbo"
    nonisolated static let defaultLegacyModelID = "large-v3"

    nonisolated private static let legacyWhisperModelMap: [String: String] = [
        "tiny": "mlx-community/whisper-tiny-mlx",
        "base": "mlx-community/whisper-base-mlx",
        "small": "mlx-community/whisper-small-mlx",
        "medium": defaultRepo,
        "large-v3": "mlx-community/whisper-large-v3-mlx",
    ]

    nonisolated static func canonicalLegacyModelID(_ modelID: String) -> String {
        let raw = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return defaultLegacyModelID }
        var normalized = raw
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "openai/whisper-", with: "")
        if normalized == "large-v3-v20240930" {
            normalized = "large-v3"
        }
        if legacyWhisperModelMap[normalized] != nil {
            return normalized
        }
        return defaultLegacyModelID
    }

    nonisolated static func repo(forLegacyWhisperModelID modelID: String) -> String {
        let canonicalModelID = canonicalLegacyModelID(modelID)
        return legacyWhisperModelMap[canonicalModelID] ?? defaultRepo
    }

    nonisolated static func isWhisperRepo(_ repo: String) -> Bool {
        MLXModelCatalog.canonicalModelRepo(repo).localizedCaseInsensitiveContains("whisper")
    }
}

struct MLXModelCatalog {
    enum Visibility: String, Hashable {
        case visible
        case hiddenSupport
    }

    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let description: String
        let visibility: Visibility

        init(
            id: String,
            title: String,
            description: String,
            visibility: Visibility = .visible
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.visibility = visibility
        }
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
        "beshkenadze/cohere-transcribe-03-2026-mlx-fp16",
        "OpenMOSS-Team/MOSS-Transcribe-Diarize",
        "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit",
    ]

    nonisolated private static let legacyModelRepoMap: [String: String] = [
        "mlx-community/Parakeet-0.6B": "mlx-community/parakeet-tdt-0.6b-v3",
        "mlx-community/GLM-ASR-Nano-4bit": "mlx-community/GLM-ASR-Nano-2512-4bit",
        "mlx-community/Voxtral-Mini-4B-Realtime-2602": "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16",
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-6bit": "mlx-community/Voxtral-Mini-4B-Realtime-6bit",
        "mlx-community/FireRedASR2": "mlx-community/FireRedASR2-AED-mlx",
    ]

    nonisolated private static let allModels: [Option] = [
        Option(
            id: "mlx-community/whisper-large-v3-turbo",
            title: "Whisper Large v3 Turbo",
            description: "Fast Whisper large-v3 family model with the best quality-to-latency balance."
        ),
        Option(
            id: "mlx-community/whisper-large-v3-mlx",
            title: "Whisper Large v3",
            description: "Accuracy-first Whisper model with a heavier local footprint."
        ),
        Option(
            id: "mlx-community/whisper-small-mlx",
            title: "Whisper Small",
            description: "Lower-resource Whisper model for lighter local setups."
        ),
        Option(
            id: "mlx-community/whisper-tiny-mlx",
            title: "Whisper Tiny",
            description: "Legacy lightweight Whisper option kept for existing installations.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/whisper-base-mlx",
            title: "Whisper Base",
            description: "Legacy compact Whisper option kept for existing installations.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-0.6B-4bit",
            title: "Qwen3 0.6B (4bit)",
            description: "Balanced quality and speed with low memory use."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-0.6B-6bit",
            title: "Qwen3 0.6B (6bit)",
            description: "Better accuracy than 4bit with moderate memory usage.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-0.6B-8bit",
            title: "Qwen3 0.6B (8bit)",
            description: "Highest-precision 0.6B option with higher memory usage.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-0.6B-bf16",
            title: "Qwen3 0.6B (bf16)",
            description: "Full-precision 0.6B model for maximum local quality.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-1.7B-4bit",
            title: "Qwen3 1.7B (4bit)",
            description: "Larger multilingual model tuned for accuracy at lower memory cost.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-1.7B-6bit",
            title: "Qwen3 1.7B (6bit)",
            description: "High-accuracy flagship model with a balanced memory footprint."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-1.7B-8bit",
            title: "Qwen3 1.7B (8bit)",
            description: "High-precision 1.7B model for stronger recognition quality."
        ),
        Option(
            id: "mlx-community/Qwen3-ASR-1.7B-bf16",
            title: "Qwen3 1.7B (bf16)",
            description: "High accuracy flagship model with higher memory usage.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
            title: "Voxtral 4B (4bit)",
            description: "Realtime-oriented multilingual model with reduced memory use.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Voxtral-Mini-4B-Realtime-6bit",
            title: "Voxtral 4B (6bit)",
            description: "Realtime multilingual model with a balanced quality-to-memory tradeoff."
        ),
        Option(
            id: "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16",
            title: "Voxtral 4B (fp16)",
            description: "Realtime-oriented model with larger memory footprint.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "beshkenadze/cohere-transcribe-03-2026-mlx-fp16",
            title: "Cohere 03-2026",
            description: "High-accuracy multilingual encoder-decoder model with punctuation enabled."
        ),
        Option(
            id: "OpenMOSS-Team/MOSS-Transcribe-Diarize",
            title: "MOSS Transcribe Diarize",
            description: "One-pass timestamped transcription and speaker-label model for meeting-style audio."
        ),
        Option(
            id: "Mediform/canary-1b-v2-mlx-q8",
            title: "Canary",
            description: "Canary-compatible NeMo encoder-decoder checkpoint for multilingual transcription."
        ),
        Option(
            id: "UsefulSensors/moonshine-tiny",
            title: "Moonshine Tiny",
            description: "Lightweight Moonshine ASR checkpoint for fast English transcription.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "facebook/wav2vec2-base-960h",
            title: "Wav2Vec2 Base 960h",
            description: "CTC English speech recognizer with a compact encoder-only decoding path.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "facebook/mms-1b-fl102",
            title: "MMS 1B FL102",
            description: "Massively multilingual Wav2Vec2 adapter model for broad language coverage.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/parakeet-tdt_ctc-110m",
            title: "Parakeet TDT CTC 110M",
            description: "Smallest Parakeet option for fast English transcription.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/parakeet-tdt-0.6b-v2",
            title: "Parakeet TDT 0.6B v2",
            description: "Lightweight English TDT model for lower-memory local transcription.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/parakeet-tdt-0.6b-v3",
            title: "Parakeet v3",
            description: "Fast, lightweight English STT."
        ),
        Option(
            id: "mlx-community/parakeet-ctc-0.6b",
            title: "Parakeet CTC 0.6B",
            description: "Compact English CTC model with low memory use.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/parakeet-rnnt-0.6b",
            title: "Parakeet RNNT 0.6B",
            description: "Compact English RNNT model for streaming-friendly decoding.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/parakeet-tdt-1.1b",
            title: "Parakeet TDT 1.1B",
            description: "Larger English model with improved recognition quality.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/parakeet-tdt_ctc-1.1b",
            title: "Parakeet TDT CTC 1.1B",
            description: "Higher-capacity Parakeet hybrid model for English transcription.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/parakeet-ctc-1.1b",
            title: "Parakeet CTC 1.1B",
            description: "Higher-accuracy English CTC model with increased memory usage.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/parakeet-rnnt-1.1b",
            title: "Parakeet RNNT 1.1B",
            description: "Higher-accuracy English RNNT model for heavier local setups.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/GLM-ASR-Nano-2512-4bit",
            title: "GLM Nano (4bit)",
            description: "Smallest footprint for quick drafts.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/granite-4.0-1b-speech-5bit",
            title: "Granite 4",
            description: "Speech model for English, French, German, Spanish, Portuguese, and Japanese.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit",
            title: "Nemotron",
            description: "Streaming ASR model with cache-aware NeMo-family decoding."
        ),
        Option(
            id: "mlx-community/FireRedASR2-AED-mlx",
            title: "FireRed 2",
            description: "Beam-search ASR model tuned for higher offline accuracy.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/SenseVoiceSmall",
            title: "SenseVoice",
            description: "Fast multilingual model with built-in language and event detection."
        )
    ]

    nonisolated static let availableModels: [Option] = allModels.filter { $0.visibility == .visible }
    nonisolated static let supportedModels: [Option] = allModels

    nonisolated private static let presentationByRepo: [String: PresentationMetadata] = [
        "mlx-community/whisper-large-v3-turbo": PresentationMetadata(ratingText: "4.8", tagKeys: ["Multilingual", "Fast", "Balanced"]),
        "mlx-community/whisper-large-v3-mlx": PresentationMetadata(ratingText: "4.9", tagKeys: ["Multilingual", "Accurate"]),
        "mlx-community/whisper-small-mlx": PresentationMetadata(ratingText: "4.5", tagKeys: ["Multilingual", "Fast"]),
        "mlx-community/whisper-tiny-mlx": PresentationMetadata(ratingText: "4.0", tagKeys: ["Multilingual", "Fast"]),
        "mlx-community/whisper-base-mlx": PresentationMetadata(ratingText: "4.3", tagKeys: ["Multilingual", "Fast"]),
        "mlx-community/Qwen3-ASR-0.6B-4bit": PresentationMetadata(ratingText: "4.4", tagKeys: ["Multilingual", "Realtime", "Fast"]),
        "mlx-community/Qwen3-ASR-0.6B-6bit": PresentationMetadata(ratingText: "4.5", tagKeys: ["Multilingual", "Realtime", "Balanced"]),
        "mlx-community/Qwen3-ASR-0.6B-8bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Multilingual", "Realtime", "Balanced"]),
        "mlx-community/Qwen3-ASR-0.6B-bf16": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Realtime", "Accurate"]),
        "mlx-community/Qwen3-ASR-1.7B-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Realtime", "Balanced"]),
        "mlx-community/Qwen3-ASR-1.7B-6bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Multilingual", "Realtime", "Accurate"]),
        "mlx-community/Qwen3-ASR-1.7B-8bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Multilingual", "Realtime", "Accurate"]),
        "mlx-community/Qwen3-ASR-1.7B-bf16": PresentationMetadata(ratingText: "4.9", tagKeys: ["Multilingual", "Realtime", "Accurate"]),
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Multilingual", "Realtime", "Fast"]),
        "mlx-community/Voxtral-Mini-4B-Realtime-6bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Realtime", "Balanced"]),
        "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Realtime", "Accurate"]),
        "beshkenadze/cohere-transcribe-03-2026-mlx-fp16": PresentationMetadata(ratingText: "4.8", tagKeys: ["Multilingual", "Realtime", "Accurate"]),
        "OpenMOSS-Team/MOSS-Transcribe-Diarize": PresentationMetadata(ratingText: "4.7", tagKeys: ["Multilingual", "Realtime", "Diarization"]),
        "Mediform/canary-1b-v2-mlx-q8": PresentationMetadata(ratingText: "4.6", tagKeys: ["Multilingual", "Accurate"]),
        "UsefulSensors/moonshine-tiny": PresentationMetadata(ratingText: "4.1", tagKeys: ["Fast"]),
        "facebook/wav2vec2-base-960h": PresentationMetadata(ratingText: "4.2", tagKeys: ["Fast"]),
        "facebook/mms-1b-fl102": PresentationMetadata(ratingText: "4.4", tagKeys: ["Multilingual"]),
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
        "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit": PresentationMetadata(ratingText: "4.5", tagKeys: ["Multilingual", "Realtime", "Fast"]),
        "mlx-community/FireRedASR2-AED-mlx": PresentationMetadata(ratingText: "4.8", tagKeys: ["Multilingual", "Accurate"]),
        "mlx-community/SenseVoiceSmall": PresentationMetadata(ratingText: "4.5", tagKeys: ["Multilingual", "Fast"]),
    ]

    nonisolated private static let knownRemoteSizeBytesByRepo: [String: Int64] = [
        "mlx-community/whisper-large-v3-turbo": 1_617_000_000,
        "mlx-community/whisper-large-v3-mlx": 3_090_319_899,
        "mlx-community/whisper-small-mlx": 486_487_465,
        "mlx-community/whisper-tiny-mlx": 76_635_397,
        "mlx-community/whisper-base-mlx": 146_719_453,
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
        "OpenMOSS-Team/MOSS-Transcribe-Diarize": 1_833_165_136,
        "Mediform/canary-1b-v2-mlx-q8": 1_137_111_210,
        "UsefulSensors/moonshine-tiny": 110_385_501,
        "facebook/wav2vec2-base-960h": 1_133_123_712,
        "facebook/mms-1b-fl102": 9_657_613_841,
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
        "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit": 760_000_000,
        "mlx-community/FireRedASR2-AED-mlx": 4_566_119_694,
        "mlx-community/SenseVoiceSmall": 936_491_235,
    ]

    nonisolated static func canonicalModelRepo(_ repo: String) -> String {
        legacyModelRepoMap[repo] ?? repo
    }

    nonisolated static func displayTitle(for repo: String) -> String {
        let canonicalRepo = canonicalModelRepo(repo)
        return supportedModels.first(where: { $0.id == canonicalRepo })?.title ?? canonicalRepo
    }

    nonisolated static func description(for repo: String) -> String? {
        let canonicalRepo = canonicalModelRepo(repo)
        return supportedModels.first(where: { $0.id == canonicalRepo })?.description
    }

    nonisolated static func isAvailableModelRepo(_ repo: String) -> Bool {
        let canonicalRepo = canonicalModelRepo(repo)
        return supportedModels.first(where: { $0.id == canonicalRepo })?.visibility == .visible
    }

    nonisolated static func displayModels(includingInstalled repos: Set<String>) -> [Option] {
        let canonicalRepos = Set(repos.map(canonicalModelRepo))
        return supportedModels.filter { option in
            option.visibility == .visible || canonicalRepos.contains(canonicalModelRepo(option.id))
        }
    }

    nonisolated static func isRealtimeCapableModelRepo(_ repo: String) -> Bool {
        realtimeCapableModelRepos.contains(canonicalModelRepo(repo))
    }

    nonisolated static func liveMode(for repo: String) -> MLXLiveMode {
        let canonicalRepo = canonicalModelRepo(repo)
        if canonicalRepo.localizedCaseInsensitiveContains("qwen3-asr") {
            return .nativeQwenLive
        }
        if canonicalRepo.localizedCaseInsensitiveContains("cohere")
            || canonicalRepo.localizedCaseInsensitiveContains("moss-transcribe-diarize")
            || canonicalRepo.localizedCaseInsensitiveContains("moss_transcribe_diarize")
        {
            return .nativeStreamingLive
        }
        if canonicalRepo.localizedCaseInsensitiveContains("nemotron") {
            return .nativeNemotronLive
        }
        if canonicalRepo.localizedCaseInsensitiveContains("voxtral") {
            return .nativeVoxtralLive
        }
        return .batchPreview
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

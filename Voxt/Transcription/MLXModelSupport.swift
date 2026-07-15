// MLXModelSupport.swift
// Provides MLXModel Support for transcription engines.

import Foundation
import HuggingFace

nonisolated enum MLXLiveMode: Equatable, Sendable {
    case batchPreview
    case nativeQwenLive
    case nativeStreamingLive
    case nativeNemotronLive
    case nativeVoxtralLive
}

nonisolated enum MLXLanguageRouting: Equatable, Sendable {
    case unavailable
    case automatic
    case iso6391(requiresExplicitPrimaryLanguage: Bool)
    case languageName
    case localeOrISO6391
    case adapterISO6393
}

nonisolated struct MLXASROutputCapability: OptionSet, Sendable {
    let rawValue: UInt

    nonisolated static let text = Self(rawValue: 1 << 0)
    nonisolated static let timestamps = Self(rawValue: 1 << 1)
    nonisolated static let speakerLabels = Self(rawValue: 1 << 2)
    nonisolated static let language = Self(rawValue: 1 << 3)
    nonisolated static let emotion = Self(rawValue: 1 << 4)
    nonisolated static let audioEvents = Self(rawValue: 1 << 5)
}

nonisolated struct MLXASRConfigurationCapability: OptionSet, Sendable {
    let rawValue: UInt

    nonisolated static let recognitionPreset = Self(rawValue: 1 << 0)
    nonisolated static let languageRouting = Self(rawValue: 1 << 1)
    nonisolated static let whisperTemperature = Self(rawValue: 1 << 2)
    nonisolated static let qwenContext = Self(rawValue: 1 << 3)
    nonisolated static let granitePrompt = Self(rawValue: 1 << 4)
    nonisolated static let senseVoiceITN = Self(rawValue: 1 << 5)
    nonisolated static let cohereLongForm = Self(rawValue: 1 << 6)
    nonisolated static let mossPromptAndOutput = Self(rawValue: 1 << 7)
    nonisolated static let canaryTask = Self(rawValue: 1 << 8)
    nonisolated static let moonshineDecoding = Self(rawValue: 1 << 9)
    nonisolated static let mmsAdapter = Self(rawValue: 1 << 10)
    nonisolated static let nemotronLatency = Self(rawValue: 1 << 11)
    nonisolated static let voxtralDelay = Self(rawValue: 1 << 12)
}

nonisolated enum MLXVADPolicy: Equatable, Sendable {
    case standard
    case preserveTimeline
    case modelManaged

    var usesExternalFinalSpeechValidation: Bool {
        self != .modelManaged
    }
}

nonisolated struct MLXASRPurpose: OptionSet, Sendable {
    let rawValue: UInt

    nonisolated static let dictation = Self(rawValue: 1 << 0)
    nonisolated static let meeting = Self(rawValue: 1 << 1)
}

nonisolated struct MLXASRModelCapability: Equatable, Sendable {
    let family: MLXModelFamily
    let supportedLanguageCodes: Set<String>
    let languageRouting: MLXLanguageRouting
    let liveMode: MLXLiveMode
    let isRealtimeCapable: Bool
    let outputCapabilities: MLXASROutputCapability
    let configurationCapabilities: MLXASRConfigurationCapability
    let vadPolicy: MLXVADPolicy
    let supportedPurposes: MLXASRPurpose

    nonisolated var isMultilingual: Bool { supportedLanguageCodes.count > 1 }

    nonisolated func supportsLanguage(code: String) -> Bool {
        supportedLanguageCodes.contains(code.lowercased())
    }

    @MainActor
    func resolvedLanguage(for language: UserMainLanguageOption) -> String? {
        let baseCode = language.baseLanguageCode
        guard supportsLanguage(code: baseCode) else { return nil }

        switch languageRouting {
        case .unavailable, .automatic, .adapterISO6393:
            return nil
        case .iso6391:
            return baseCode
        case .localeOrISO6391:
            switch language.code {
            case "zh-hans":
                return "zh-CN"
            case "zh-hant":
                return "zh-TW"
            default:
                return baseCode
            }
        case .languageName:
            return language.promptName
        }
    }

    nonisolated var requiresExplicitPrimaryLanguage: Bool {
        switch languageRouting {
        case .iso6391(let required):
            return required
        case .languageName, .localeOrISO6391:
            return true
        default:
            return false
        }
    }
}

nonisolated struct MMSLanguageAdapterOption: Identifiable, Hashable, Sendable {
    let id: String
    let appLanguageCode: String?

    var title: String {
        let languageCode = id.split(separator: "-").first.map(String.init) ?? id
        let languageName = AppLocalization.locale.localizedString(forLanguageCode: languageCode)
            ?? Locale.current.localizedString(forLanguageCode: languageCode)
            ?? id
        return "\(languageName) (\(id))"
    }

    nonisolated static let all: [MMSLanguageAdapterOption] = {
        let appCodesByAdapter = [
            "afr": "af", "amh": "am", "ara": "ar", "asm": "as", "azj-script_latin": "az",
            "bel": "be", "ben": "bn", "bos": "bs", "bul": "bg", "cat": "ca", "ces": "cs",
            "cmn-script_simplified": "zh", "cym": "cy", "dan": "da", "deu": "de", "ell": "el",
            "eng": "en", "est": "et", "fas": "fa", "fin": "fi", "fra": "fr", "glg": "gl",
            "guj": "gu", "hau": "ha", "heb": "he", "hin": "hi", "hrv": "hr", "hun": "hu",
            "hye": "hy", "ind": "id", "isl": "is", "ita": "it", "jav": "jv", "jpn": "ja",
            "kan": "kn", "kat": "ka", "kaz": "kk", "khm": "km", "kor": "ko", "lao": "lo",
            "lav": "lv", "lit": "lt", "ltz": "lb", "mal": "ml", "mar": "mr", "mkd": "mk",
            "mlt": "mt", "mon": "mn", "mri": "mi", "mya": "my", "nld": "nl", "nob": "no",
            "npi": "ne", "oci": "oc", "pan": "pa", "pol": "pl", "por": "pt", "pus": "ps",
            "ron": "ro", "rus": "ru", "slk": "sk", "slv": "sl", "sna": "sn", "snd": "sd",
            "som": "so", "spa": "es", "srp-script_latin": "sr", "swe": "sv", "swh": "sw",
            "tam": "ta", "tel": "te", "tgk": "tg", "tgl": "tl", "tha": "th", "tur": "tr",
            "ukr": "uk", "urd-script_arabic": "ur", "uzb-script_latin": "uz", "vie": "vi",
            "yor": "yo", "yue-script_traditional": "yue", "zlm": "ms",
        ]
        let adapterCodes = """
        afr amh ara asm ast azj-script_latin bel ben bos bul cat ceb ces ckb cmn-script_simplified cym dan deu ell eng est fas fin fra ful gle glg guj hau heb hin hrv hun hye ibo ind isl ita jav jpn kam kan kat kaz kea khm kir kor lao lav lin lit ltz lug luo mal mar mkd mlt mon mri mya nld nob npi nso nya oci orm ory pan pol por pus ron rus slk slv sna snd som spa srp-script_latin swe swh tam tel tgk tgl tha tur ukr umb urd-script_arabic uzb-script_latin vie wol xho yor yue-script_traditional zlm zul
        """
        return adapterCodes.split(whereSeparator: { $0.isWhitespace }).map {
            let code = String($0)
            return MMSLanguageAdapterOption(id: code, appLanguageCode: appCodesByAdapter[code])
        }
    }()

    nonisolated static let supportedAppLanguageCodes = Set(all.compactMap(\.appLanguageCode))
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
        MLXModelCatalog.capability(for: repo).family == .whisper
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

    nonisolated private static let whisperLanguageCodes: Set<String> = [
        "af", "am", "ar", "as", "az", "be", "bg", "bn", "bo", "br", "bs", "ca", "cs", "cy",
        "da", "de", "el", "en", "es", "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha",
        "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja", "jv", "ka", "kk", "km",
        "kn", "ko", "la", "lb", "lo", "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms",
        "mt", "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt", "ro", "ru", "sa",
        "sd", "si", "sk", "sl", "sn", "so", "sq", "sr", "su", "sv", "sw", "ta", "te", "tg",
        "th", "tk", "tl", "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "zh",
    ]

    nonisolated private static let qwenLanguageCodes: Set<String> = [
        "zh", "en", "yue", "ar", "de", "fr", "es", "pt", "id", "it", "ko", "ru", "th", "vi",
        "ja", "tr", "hi", "ms", "nl", "sv", "da", "fi", "pl", "cs", "tl", "fa", "el", "hu",
        "mk", "ro",
    ]

    nonisolated private static let european25LanguageCodes: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv",
        "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    nonisolated private static let nemotronReadyLanguageCodes: Set<String> = [
        "en", "es", "fr", "it", "pt", "nl", "de", "tr", "ru", "ar", "hi", "ja", "ko", "vi",
        "uk", "pl", "sv", "cs", "no", "da", "bg", "fi", "hr", "sk", "zh", "hu", "ro", "et",
    ]

    nonisolated private static let voxtralLanguageCodes: Set<String> = [
        "ar", "de", "en", "es", "fr", "hi", "it", "nl", "pt", "zh", "ja", "ko", "ru",
    ]

    nonisolated private static let cohereLanguageCodes: Set<String> = [
        "zh", "en", "ja", "ko", "vi", "ar", "el", "pl", "nl", "pt", "it", "es", "de", "fr",
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
            description: "Realtime multilingual model with a balanced quality-to-memory tradeoff.",
            visibility: .hiddenSupport
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
            title: "MOSS",
            description: "One-pass timestamped transcription and speaker-label model for meeting-style audio."
        ),
        Option(
            id: "Mediform/canary-1b-v2-mlx-q8",
            title: "Canary",
            description: "Canary-compatible NeMo encoder-decoder checkpoint for multilingual transcription.",
            visibility: .hiddenSupport
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
            description: "Fast 25-language European ASR with automatic language detection."
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

    nonisolated private static let capabilitiesByRepo: [String: MLXASRModelCapability] = {
        var capabilities: [String: MLXASRModelCapability] = [:]

        func register(
            repos: [String],
            family: MLXModelFamily,
            languages: Set<String>,
            routing: MLXLanguageRouting,
            liveMode: MLXLiveMode = .batchPreview,
            realtime: Bool = false,
            outputs: MLXASROutputCapability = [.text],
            configuration: MLXASRConfigurationCapability = [],
            vadPolicy: MLXVADPolicy = .standard,
            purposes: MLXASRPurpose = [.dictation, .meeting]
        ) {
            let capability = MLXASRModelCapability(
                family: family,
                supportedLanguageCodes: languages,
                languageRouting: routing,
                liveMode: liveMode,
                isRealtimeCapable: realtime,
                outputCapabilities: outputs,
                configurationCapabilities: configuration,
                vadPolicy: vadPolicy,
                supportedPurposes: purposes
            )
            repos.forEach { capabilities[$0] = capability }
        }

        register(
            repos: [
                "mlx-community/whisper-large-v3-turbo",
                "mlx-community/whisper-large-v3-mlx",
                "mlx-community/whisper-small-mlx",
                "mlx-community/whisper-tiny-mlx",
                "mlx-community/whisper-base-mlx",
            ],
            family: .whisper,
            languages: whisperLanguageCodes,
            routing: .iso6391(requiresExplicitPrimaryLanguage: false),
            configuration: [.recognitionPreset, .languageRouting, .whisperTemperature]
        )
        register(
            repos: [
                "mlx-community/Qwen3-ASR-0.6B-4bit",
                "mlx-community/Qwen3-ASR-0.6B-6bit",
                "mlx-community/Qwen3-ASR-0.6B-8bit",
                "mlx-community/Qwen3-ASR-0.6B-bf16",
                "mlx-community/Qwen3-ASR-1.7B-4bit",
                "mlx-community/Qwen3-ASR-1.7B-6bit",
                "mlx-community/Qwen3-ASR-1.7B-8bit",
                "mlx-community/Qwen3-ASR-1.7B-bf16",
            ],
            family: .qwen3ASR,
            languages: qwenLanguageCodes,
            routing: .languageName,
            liveMode: .nativeQwenLive,
            configuration: [.recognitionPreset, .languageRouting, .qwenContext]
        )
        register(
            repos: [
                "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
                "mlx-community/Voxtral-Mini-4B-Realtime-6bit",
                "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16",
            ],
            family: .voxtralRealtime,
            languages: voxtralLanguageCodes,
            routing: .automatic,
            liveMode: .nativeVoxtralLive,
            realtime: true,
            configuration: [.voxtralDelay],
            vadPolicy: .modelManaged
        )
        register(
            repos: ["beshkenadze/cohere-transcribe-03-2026-mlx-fp16"],
            family: .cohereTranscribe,
            languages: cohereLanguageCodes,
            routing: .iso6391(requiresExplicitPrimaryLanguage: true),
            liveMode: .nativeStreamingLive,
            realtime: true,
            configuration: [.recognitionPreset, .languageRouting, .cohereLongForm],
            vadPolicy: .modelManaged
        )
        register(
            repos: ["OpenMOSS-Team/MOSS-Transcribe-Diarize"],
            family: .mossTranscribeDiarize,
            languages: ["zh", "en"],
            routing: .automatic,
            liveMode: .nativeStreamingLive,
            realtime: true,
            outputs: [.text, .timestamps, .speakerLabels, .audioEvents],
            configuration: [.mossPromptAndOutput],
            vadPolicy: .preserveTimeline
        )
        register(
            repos: ["Mediform/canary-1b-v2-mlx-q8"],
            family: .canary,
            languages: european25LanguageCodes,
            routing: .iso6391(requiresExplicitPrimaryLanguage: true),
            outputs: [.text, .timestamps],
            configuration: [.languageRouting, .canaryTask]
        )
        register(
            repos: ["UsefulSensors/moonshine-tiny"],
            family: .moonshine,
            languages: ["en"],
            routing: .unavailable,
            configuration: [.moonshineDecoding]
        )
        register(
            repos: ["facebook/wav2vec2-base-960h"],
            family: .wav2vec2CTC,
            languages: ["en"],
            routing: .unavailable
        )
        register(
            repos: ["facebook/mms-1b-fl102"],
            family: .mmsCTC,
            languages: MMSLanguageAdapterOption.supportedAppLanguageCodes,
            routing: .adapterISO6393,
            configuration: [.mmsAdapter]
        )
        register(
            repos: [
                "mlx-community/parakeet-tdt_ctc-110m",
                "mlx-community/parakeet-tdt-0.6b-v2",
                "mlx-community/parakeet-ctc-0.6b",
                "mlx-community/parakeet-rnnt-0.6b",
                "mlx-community/parakeet-tdt-1.1b",
                "mlx-community/parakeet-tdt_ctc-1.1b",
                "mlx-community/parakeet-ctc-1.1b",
                "mlx-community/parakeet-rnnt-1.1b",
            ],
            family: .parakeet,
            languages: ["en"],
            routing: .automatic
        )
        register(
            repos: ["mlx-community/parakeet-tdt-0.6b-v3"],
            family: .parakeet,
            languages: european25LanguageCodes,
            routing: .automatic
        )
        register(
            repos: ["mlx-community/GLM-ASR-Nano-2512-4bit"],
            family: .generic,
            languages: ["zh", "en"],
            routing: .iso6391(requiresExplicitPrimaryLanguage: false),
            configuration: [.recognitionPreset, .languageRouting]
        )
        register(
            repos: ["mlx-community/granite-4.0-1b-speech-5bit"],
            family: .graniteSpeech,
            languages: ["en", "fr", "de", "es", "pt", "ja"],
            routing: .automatic,
            configuration: [.recognitionPreset, .granitePrompt]
        )
        register(
            repos: ["mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"],
            family: .nemotronASR,
            languages: nemotronReadyLanguageCodes,
            routing: .localeOrISO6391,
            liveMode: .nativeNemotronLive,
            realtime: true,
            outputs: [.text, .language],
            configuration: [.languageRouting, .nemotronLatency],
            vadPolicy: .modelManaged
        )
        register(
            repos: ["mlx-community/FireRedASR2-AED-mlx"],
            family: .generic,
            languages: ["zh", "en"],
            routing: .iso6391(requiresExplicitPrimaryLanguage: false),
            configuration: [.recognitionPreset, .languageRouting]
        )
        register(
            repos: ["mlx-community/SenseVoiceSmall"],
            family: .senseVoice,
            languages: ["zh", "en", "yue", "ja", "ko"],
            routing: .iso6391(requiresExplicitPrimaryLanguage: false),
            outputs: [.text, .language, .emotion, .audioEvents],
            configuration: [.languageRouting, .senseVoiceITN]
        )
        return capabilities
    }()

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

    nonisolated static func capability(for repo: String) -> MLXASRModelCapability {
        let canonicalRepo = canonicalModelRepo(repo)
        return capabilitiesByRepo[canonicalRepo] ?? fallbackCapability(for: canonicalRepo)
    }

    nonisolated static func hasRegisteredCapability(for repo: String) -> Bool {
        capabilitiesByRepo[canonicalModelRepo(repo)] != nil
    }

    nonisolated private static func fallbackCapability(for repo: String) -> MLXASRModelCapability {
        let lower = repo.lowercased()
        let family: MLXModelFamily
        let languages: Set<String>
        let routing: MLXLanguageRouting
        let configuration: MLXASRConfigurationCapability
        let liveMode: MLXLiveMode

        if lower.contains("whisper") {
            family = .whisper
            languages = whisperLanguageCodes
            routing = .iso6391(requiresExplicitPrimaryLanguage: false)
            configuration = [.recognitionPreset, .languageRouting, .whisperTemperature]
            liveMode = .batchPreview
        } else if lower.contains("qwen3-asr") {
            family = .qwen3ASR
            languages = qwenLanguageCodes
            routing = .languageName
            configuration = [.recognitionPreset, .languageRouting, .qwenContext]
            liveMode = .nativeQwenLive
        } else if lower.contains("granite-4.0-1b-speech") {
            family = .graniteSpeech
            languages = ["en", "fr", "de", "es", "pt", "ja"]
            routing = .automatic
            configuration = [.recognitionPreset, .granitePrompt]
            liveMode = .batchPreview
        } else if lower.contains("sensevoice") {
            family = .senseVoice
            languages = ["zh", "en", "yue", "ja", "ko"]
            routing = .iso6391(requiresExplicitPrimaryLanguage: false)
            configuration = [.languageRouting, .senseVoiceITN]
            liveMode = .batchPreview
        } else if lower.contains("cohere") {
            family = .cohereTranscribe
            languages = cohereLanguageCodes
            routing = .iso6391(requiresExplicitPrimaryLanguage: true)
            configuration = [.recognitionPreset, .languageRouting, .cohereLongForm]
            liveMode = .nativeStreamingLive
        } else if lower.contains("nemotron") {
            family = .nemotronASR
            languages = nemotronReadyLanguageCodes
            routing = .localeOrISO6391
            configuration = [.languageRouting, .nemotronLatency]
            liveMode = .nativeNemotronLive
        } else if lower.contains("voxtral") {
            family = .voxtralRealtime
            languages = voxtralLanguageCodes
            routing = .automatic
            configuration = [.voxtralDelay]
            liveMode = .nativeVoxtralLive
        } else if lower.contains("moss-transcribe-diarize") || lower.contains("moss_transcribe_diarize") {
            family = .mossTranscribeDiarize
            languages = ["zh", "en"]
            routing = .automatic
            configuration = [.mossPromptAndOutput]
            liveMode = .nativeStreamingLive
        } else if lower.contains("canary") {
            family = .canary
            languages = european25LanguageCodes
            routing = .iso6391(requiresExplicitPrimaryLanguage: true)
            configuration = [.languageRouting, .canaryTask]
            liveMode = .batchPreview
        } else if lower.contains("moonshine") {
            family = .moonshine
            languages = ["en"]
            routing = .unavailable
            configuration = [.moonshineDecoding]
            liveMode = .batchPreview
        } else if lower.contains("/mms-") || lower.contains("mms_") || lower.contains("mms-") {
            family = .mmsCTC
            languages = MMSLanguageAdapterOption.supportedAppLanguageCodes
            routing = .adapterISO6393
            configuration = [.mmsAdapter]
            liveMode = .batchPreview
        } else if lower.contains("wav2vec") {
            family = .wav2vec2CTC
            languages = ["en"]
            routing = .unavailable
            configuration = []
            liveMode = .batchPreview
        } else if lower.contains("parakeet") {
            family = .parakeet
            languages = lower.hasSuffix("v3") ? european25LanguageCodes : ["en"]
            routing = .automatic
            configuration = []
            liveMode = .batchPreview
        } else if lower.contains("lasr") {
            family = .lasrCTC
            languages = []
            routing = .unavailable
            configuration = []
            liveMode = .batchPreview
        } else {
            family = .generic
            languages = []
            routing = .unavailable
            configuration = []
            liveMode = .batchPreview
        }

        return MLXASRModelCapability(
            family: family,
            supportedLanguageCodes: languages,
            languageRouting: routing,
            liveMode: liveMode,
            isRealtimeCapable: [.nativeStreamingLive, .nativeNemotronLive, .nativeVoxtralLive].contains(liveMode),
            outputCapabilities: [.text],
            configurationCapabilities: configuration,
            vadPolicy: .standard,
            supportedPurposes: [.dictation, .meeting]
        )
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
        capability(for: repo).isRealtimeCapable
    }

    nonisolated static func liveMode(for repo: String) -> MLXLiveMode {
        capability(for: repo).liveMode
    }

    nonisolated static func ratingText(for repo: String) -> String {
        presentationByRepo[canonicalModelRepo(repo)]?.ratingText ?? "4.3"
    }

    nonisolated static func catalogTagKeys(for repo: String) -> [String] {
        presentationByRepo[canonicalModelRepo(repo)]?.tagKeys ?? []
    }

    nonisolated static func isMultilingualModelRepo(_ repo: String) -> Bool {
        capability(for: repo).isMultilingual
    }

    nonisolated static func supportsLanguage(_ code: String, for repo: String) -> Bool {
        capability(for: repo).supportsLanguage(code: code)
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

import Foundation

enum LocalASRRecognitionPreset: String, CaseIterable, Codable, Identifiable {
    case balanced
    case accuracyFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return AppLocalization.localizedString("Balanced")
        case .accuracyFirst:
            return AppLocalization.localizedString("Accuracy First")
        }
    }

    var summary: String {
        switch self {
        case .balanced:
            return AppLocalization.localizedString("Default recognition behavior with moderate fallback and minimal extra bias.")
        case .accuracyFirst:
            return AppLocalization.localizedString("Stronger fallback and chunking choices that favor recognition stability over speed.")
        }
    }
}

enum MLXModelFamily: String, CaseIterable, Codable, Identifiable {
    case qwen3ASR
    case graniteSpeech
    case senseVoice
    case cohereTranscribe
    case generic

    var id: String { rawValue }

    static func family(for repo: String) -> MLXModelFamily {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
        if canonicalRepo.localizedCaseInsensitiveContains("Qwen3-ASR") {
            return .qwen3ASR
        }
        if canonicalRepo.localizedCaseInsensitiveContains("granite-4.0-1b-speech") {
            return .graniteSpeech
        }
        if canonicalRepo.localizedCaseInsensitiveContains("sensevoice") {
            return .senseVoice
        }
        if canonicalRepo.localizedCaseInsensitiveContains("cohere-transcribe")
            || canonicalRepo.localizedCaseInsensitiveContains("cohere")
        {
            return .cohereTranscribe
        }
        return .generic
    }

    var title: String {
        switch self {
        case .qwen3ASR:
            return AppLocalization.localizedString("Qwen3-ASR")
        case .graniteSpeech:
            return AppLocalization.localizedString("Granite Speech")
        case .senseVoice:
            return AppLocalization.localizedString("SenseVoice")
        case .cohereTranscribe:
            return AppLocalization.localizedString("Cohere Transcribe")
        case .generic:
            return AppLocalization.localizedString("General MLX ASR")
        }
    }

    var supportsContextBias: Bool { self == .qwen3ASR }
    var supportsPromptBias: Bool { self == .graniteSpeech }
    var supportsITN: Bool { self == .senseVoice }
}

struct WhisperLocalTuningSettings: Codable, Equatable {
    var preset: LocalASRRecognitionPreset = .balanced
    var temperatureFallbackCount: Int = 2
    var temperatureIncrementOnFallback: Double = 0.2
    var compressionRatioThreshold: Double = 2.4
    var logProbThreshold: Double = -1.0
    var noSpeechThreshold: Double = 0.6

    static func defaults(for preset: LocalASRRecognitionPreset) -> WhisperLocalTuningSettings {
        switch preset {
        case .balanced:
            return WhisperLocalTuningSettings(
                preset: .balanced,
                temperatureFallbackCount: 2,
                temperatureIncrementOnFallback: 0.2,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                noSpeechThreshold: 0.4
            )
        case .accuracyFirst:
            return WhisperLocalTuningSettings(
                preset: .accuracyFirst,
                temperatureFallbackCount: 4,
                temperatureIncrementOnFallback: 0.2,
                compressionRatioThreshold: 2.2,
                logProbThreshold: -1.2,
                noSpeechThreshold: 0.3
            )
        }
    }
}

enum WhisperLocalTuningSettingsStore {
    static func resolvedSettings(from rawValue: String?) -> WhisperLocalTuningSettings {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WhisperLocalTuningSettings.self, from: data)
        else {
            return WhisperLocalTuningSettings.defaults(for: .balanced)
        }
        return sanitized(decoded)
    }

    static func storageValue(for settings: WhisperLocalTuningSettings) -> String {
        let sanitized = sanitized(settings)
        guard let data = try? JSONEncoder().encode(sanitized),
              let text = String(data: data, encoding: .utf8) else {
            return defaultStoredValue()
        }
        return text
    }

    static func defaultStoredValue() -> String {
        storageValue(for: WhisperLocalTuningSettings.defaults(for: .balanced))
    }

    static func sanitized(_ settings: WhisperLocalTuningSettings) -> WhisperLocalTuningSettings {
        WhisperLocalTuningSettings(
            preset: settings.preset,
            temperatureFallbackCount: max(0, min(settings.temperatureFallbackCount, 8)),
            temperatureIncrementOnFallback: max(0, min(settings.temperatureIncrementOnFallback, 1.0)),
            compressionRatioThreshold: max(1.0, min(settings.compressionRatioThreshold, 4.0)),
            logProbThreshold: max(-3.0, min(settings.logProbThreshold, 0.0)),
            noSpeechThreshold: max(0.0, min(settings.noSpeechThreshold, 1.0))
        )
    }
}

struct MLXLocalTuningSettings: Codable, Equatable {
    var preset: LocalASRRecognitionPreset = .balanced
    var qwenContextBias: String = ""
    var granitePromptBias: String = ""
    var senseVoiceUseITN: Bool = false

    init(
        preset: LocalASRRecognitionPreset = .balanced,
        qwenContextBias: String = "",
        granitePromptBias: String = "",
        senseVoiceUseITN: Bool = false
    ) {
        self.preset = preset
        self.qwenContextBias = qwenContextBias
        self.granitePromptBias = granitePromptBias
        self.senseVoiceUseITN = senseVoiceUseITN
    }

    static func defaults(for preset: LocalASRRecognitionPreset) -> MLXLocalTuningSettings {
        defaults(for: preset, family: nil)
    }

    static func defaults(for preset: LocalASRRecognitionPreset, family: MLXModelFamily?) -> MLXLocalTuningSettings {
        MLXLocalTuningSettings(
            preset: preset,
            qwenContextBias: family == .qwen3ASR ? AppPromptDefaults.text(for: .qwenASRContextBias) : ""
        )
    }
}

enum MLXLocalTuningSettingsStore {
    static func load(from rawValue: String?) -> [String: MLXLocalTuningSettings] {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: MLXLocalTuningSettings].self, from: data)
        else {
            return [:]
        }

        var result: [String: MLXLocalTuningSettings] = [:]
        for (key, value) in decoded {
            result[key] = sanitized(value)
        }
        return result
    }

    static func resolvedSettings(for repo: String, rawValue: String?) -> MLXLocalTuningSettings {
        let key = familyKey(for: repo)
        let family = MLXModelFamily.family(for: repo)
        var settings = load(from: rawValue)[key] ?? MLXLocalTuningSettings.defaults(for: .balanced, family: family)
        if family == .qwen3ASR,
           settings.qwenContextBias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.qwenContextBias = AppPromptDefaults.text(for: .qwenASRContextBias)
        }
        return settings
    }

    static func save(_ settings: MLXLocalTuningSettings, for repo: String, rawValue: String?) -> String {
        var stored = load(from: rawValue)
        stored[familyKey(for: repo)] = sanitized(settings)
        return storageValue(for: stored)
    }

    static func storageValue(for settingsByFamily: [String: MLXLocalTuningSettings]) -> String {
        let sanitizedSettings = settingsByFamily.mapValues { value in
            Self.sanitized(value)
        }
        guard let data = try? JSONEncoder().encode(sanitizedSettings),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    static func familyKey(for repo: String) -> String {
        MLXModelFamily.family(for: repo).rawValue
    }

    static func sanitized(_ settings: MLXLocalTuningSettings) -> MLXLocalTuningSettings {
        MLXLocalTuningSettings(
            preset: settings.preset,
            qwenContextBias: settings.qwenContextBias.trimmingCharacters(in: .whitespacesAndNewlines),
            granitePromptBias: settings.granitePromptBias.trimmingCharacters(in: .whitespacesAndNewlines),
            senseVoiceUseITN: settings.senseVoiceUseITN
        )
    }
}

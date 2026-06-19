// ASRHintLocalTuning.swift
// Provides ASRHint Local Tuning for transcription processing.

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
    case whisper
    case qwen3ASR
    case graniteSpeech
    case senseVoice
    case cohereTranscribe
    case generic

    var id: String { rawValue }

    static func family(for repo: String) -> MLXModelFamily {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
        if MLXWhisperMigrationSupport.isWhisperRepo(canonicalRepo) {
            return .whisper
        }
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
        case .whisper:
            return AppLocalization.localizedString("Whisper")
        case .qwen3ASR:
            return AppLocalization.localizedString("Qwen3")
        case .graniteSpeech:
            return AppLocalization.localizedString("Granite")
        case .senseVoice:
            return AppLocalization.localizedString("SenseVoice")
        case .cohereTranscribe:
            return AppLocalization.localizedString("Cohere")
        case .generic:
            return AppLocalization.localizedString("General MLX ASR")
        }
    }

    var supportsContextBias: Bool { self == .qwen3ASR }
    var supportsPromptBias: Bool { self == .graniteSpeech }
    var supportsITN: Bool { self == .senseVoice }
    var supportsWhisperTemperature: Bool { self == .whisper }
    var supportsRecognitionPreset: Bool { self != .senseVoice }
}

struct MLXLocalTuningSettings: Codable, Equatable {
    var preset: LocalASRRecognitionPreset = .balanced
    var whisperTemperature: Double = 0.0
    var qwenContextBias: String = ""
    var granitePromptBias: String = ""
    var senseVoiceUseITN: Bool = false

    init(
        preset: LocalASRRecognitionPreset = .balanced,
        whisperTemperature: Double = 0.0,
        qwenContextBias: String = "",
        granitePromptBias: String = "",
        senseVoiceUseITN: Bool = false
    ) {
        self.preset = preset
        self.whisperTemperature = whisperTemperature
        self.qwenContextBias = qwenContextBias
        self.granitePromptBias = granitePromptBias
        self.senseVoiceUseITN = senseVoiceUseITN
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case whisperTemperature
        case qwenContextBias
        case granitePromptBias
        case senseVoiceUseITN
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decodeIfPresent(LocalASRRecognitionPreset.self, forKey: .preset) ?? .balanced
        whisperTemperature = try container.decodeIfPresent(Double.self, forKey: .whisperTemperature) ?? 0.0
        qwenContextBias = try container.decodeIfPresent(String.self, forKey: .qwenContextBias) ?? ""
        granitePromptBias = try container.decodeIfPresent(String.self, forKey: .granitePromptBias) ?? ""
        senseVoiceUseITN = try container.decodeIfPresent(Bool.self, forKey: .senseVoiceUseITN) ?? false
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
        let qwenContextBias = settings.qwenContextBias.trimmingCharacters(in: .whitespacesAndNewlines)
        return MLXLocalTuningSettings(
            preset: settings.preset,
            whisperTemperature: max(0.0, min(settings.whisperTemperature, 1.0)),
            qwenContextBias: AppPromptDefaults.matchesKnownDefault(qwenContextBias, kind: .qwenASRContextBias)
                ? ""
                : qwenContextBias,
            granitePromptBias: settings.granitePromptBias.trimmingCharacters(in: .whitespacesAndNewlines),
            senseVoiceUseITN: settings.senseVoiceUseITN
        )
    }
}

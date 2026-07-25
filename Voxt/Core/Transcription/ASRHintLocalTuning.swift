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

enum NemotronStreamLatency: Int, CaseIterable, Codable, Identifiable, Sendable {
    case minimum = 80
    case fast = 160
    case responsive = 320
    case balanced = 560
    case accurate = 1120

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .minimum: return AppLocalization.localizedString("Minimum (80 ms)")
        case .fast: return AppLocalization.localizedString("Fast (160 ms)")
        case .responsive: return AppLocalization.localizedString("Responsive (320 ms)")
        case .balanced: return AppLocalization.localizedString("Balanced (560 ms)")
        case .accurate: return AppLocalization.localizedString("Accurate (1120 ms)")
        }
    }
}

enum VoxtralTranscriptionDelay: Int, CaseIterable, Codable, Identifiable, Sendable {
    case fastest = 240
    case balanced = 480
    case accurate = 960
    case subtitle = 2400

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fastest: return AppLocalization.localizedString("Fastest (240 ms)")
        case .balanced: return AppLocalization.localizedString("Balanced (480 ms)")
        case .accurate: return AppLocalization.localizedString("Accurate (960 ms)")
        case .subtitle: return AppLocalization.localizedString("Subtitle (2400 ms)")
        }
    }
}

enum MossASROutputMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case timestampedDiarization
    case speakerOnly
    case plainText
    case customPrompt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timestampedDiarization:
            return AppLocalization.localizedString("Timestamped Diarization")
        case .speakerOnly:
            return AppLocalization.localizedString("Speaker Labels Only")
        case .plainText:
            return AppLocalization.localizedString("Plain Text")
        case .customPrompt:
            return AppLocalization.localizedString("Custom Prompt")
        }
    }

    var summary: String {
        switch self {
        case .timestampedDiarization:
            return AppLocalization.localizedString("Include start and end timestamps with anonymous speaker labels.")
        case .speakerOnly:
            return AppLocalization.localizedString("Include anonymous speaker labels without timestamps.")
        case .plainText:
            return AppLocalization.localizedString("Return transcription text without timestamps or speaker labels.")
        case .customPrompt:
            return AppLocalization.localizedString("Use a custom MOSS transcription instruction.")
        }
    }
}

enum MossASRUsageScope: String, CaseIterable, Identifiable, Sendable {
    case dictation
    case meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Dictation Settings")
        case .meeting:
            return AppLocalization.localizedString("Meeting")
        }
    }
}

struct MossASRUsageSettings: Equatable, Sendable {
    var outputMode: MossASROutputMode
    var hotwords: String
    var customPrompt: String
}

enum CohereLongFormStrategy: String, CaseIterable, Codable, Identifiable, Sendable {
    case fixedChunks
    case voiceActivity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixedChunks:
            return AppLocalization.localizedString("Fixed Chunks")
        case .voiceActivity:
            return AppLocalization.localizedString("Voice Activity")
        }
    }

    var summary: String {
        switch self {
        case .fixedChunks:
            return AppLocalization.localizedString("Best for clean, dense narration without long silences.")
        case .voiceActivity:
            return AppLocalization.localizedString("Better for meetings and podcasts with silence or non-speech sections.")
        }
    }
}

enum CanaryTaskMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case transcription
    case translateToEnglish
    case translateFromEnglish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcription:
            return AppLocalization.localizedString("Transcription")
        case .translateToEnglish:
            return AppLocalization.localizedString("Translate to English")
        case .translateFromEnglish:
            return AppLocalization.localizedString("Translate from English")
        }
    }
}

enum CanaryLanguageSupport {
    static let supportedCodes = MLXModelCatalog
        .capability(for: "Mediform/canary-1b-v2-mlx-q8")
        .supportedLanguageCodes
        .sorted()

    static let translationTargetCodes = supportedCodes.filter { $0 != "en" }

    static func title(for code: String) -> String {
        UserMainLanguageOption.option(for: code)?.title()
            ?? AppLocalization.locale.localizedString(forLanguageCode: code)
            ?? code
    }

    static func sanitizedTranslationTarget(_ code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return translationTargetCodes.contains(normalized) ? normalized : "fr"
    }

    static func resolvedTaskLanguages(
        mode: CanaryTaskMode,
        sourceLanguage: String?,
        translationLanguage: String
    ) -> (source: String, target: String) {
        let normalizedSource = sourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let source = supportedCodes.contains(normalizedSource) ? normalizedSource : "en"
        switch mode {
        case .transcription:
            return (source, source)
        case .translateToEnglish:
            return (source, "en")
        case .translateFromEnglish:
            return ("en", sanitizedTranslationTarget(translationLanguage))
        }
    }
}

enum MossASRPromptSupport {
    static func generationOutputMode(
        requestedOutputMode: MossASROutputMode,
        scope: MossASRUsageScope
    ) -> MossASROutputMode {
        // Meeting storage consumes typed timestamped speaker segments. Presentation
        // preferences must not weaken that transport contract into unstructured text.
        scope == .meeting ? .timestampedDiarization : requestedOutputMode
    }

    static func resolvedPrompt(
        requestedOutputMode: MossASROutputMode,
        scope: MossASRUsageScope,
        customPrompt: String,
        hotwords: String
    ) -> String {
        let outputMode = generationOutputMode(
            requestedOutputMode: requestedOutputMode,
            scope: scope
        )
        guard scope == .meeting else {
            return resolvedPrompt(
                outputMode: outputMode,
                customPrompt: customPrompt,
                hotwords: hotwords
            )
        }

        let requiredStructure = resolvedPrompt(
            outputMode: .timestampedDiarization,
            customPrompt: "",
            hotwords: ""
        )
        let trimmedCustomPrompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedPrompt = trimmedCustomPrompt.isEmpty
            ? requiredStructure
            : "\(requiredStructure) Additional transcription instructions: \(trimmedCustomPrompt)"
        return resolvedPrompt(
            outputMode: .customPrompt,
            customPrompt: combinedPrompt,
            hotwords: hotwords
        )
    }

    static func resolvedPrompt(
        outputMode: MossASROutputMode,
        customPrompt: String,
        hotwords: String
    ) -> String {
        let basePrompt: String
        switch outputMode {
        case .timestampedDiarization:
            basePrompt = AppPromptResourceStore.requiredText(for: .mossTimestampedDiarization)
        case .speakerOnly:
            basePrompt = AppPromptResourceStore.requiredText(for: .mossSpeakerOnly)
        case .plainText:
            basePrompt = AppPromptResourceStore.requiredText(for: .mossPlainText)
        case .customPrompt:
            let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            basePrompt = trimmed.isEmpty
                ? AppPromptResourceStore.requiredText(for: .mossTimestampedDiarization)
                : trimmed
        }

        let normalizedHotwords = hotwords
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !normalizedHotwords.isEmpty else { return basePrompt }
        return "\(basePrompt) Hotwords: \(normalizedHotwords)"
    }
}

enum MossASRTranscriptRendering {
    nonisolated static func renderedText(_ rawText: String, outputMode: MossASROutputMode) -> String {
        switch outputMode {
        case .timestampedDiarization, .customPrompt:
            return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .speakerOnly:
            return removingStructuredTags(from: rawText, removesSpeakerLabels: false)
        case .plainText:
            return flattenedPlainText(
                removingStructuredTags(from: rawText, removesSpeakerLabels: true)
            )
        }
    }

    nonisolated private static func flattenedPlainText(_ text: String) -> String {
        let segments = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result = ""
        for segment in segments {
            guard let previous = result.last, let next = segment.first else {
                result = segment
                continue
            }
            if shouldSeparatePlainTextSegments(previous: previous, next: next) {
                result += " "
            }
            result += segment
        }
        return result
    }

    nonisolated private static func shouldSeparatePlainTextSegments(
        previous: Character,
        next: Character
    ) -> Bool {
        guard !isCJKTextBoundary(previous), !isCJKTextBoundary(next) else { return false }
        guard !isClosingPunctuation(next), !isOpeningPunctuation(previous) else { return false }
        return true
    }

    nonisolated private static func isCJKTextBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF,
                 0x2E80...0x303F,
                 0x3040...0x30FF,
                 0x3130...0x318F,
                 0x31F0...0x31FF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xA960...0xA97F,
                 0xAC00...0xD7FF,
                 0xF900...0xFAFF,
                 0xFF00...0xFFEF,
                 0x20000...0x2CEAF:
                return true
            default:
                return false
            }
        }
    }

    nonisolated private static func isClosingPunctuation(_ character: Character) -> Bool {
        ",.!?;:%)]}".contains(character)
    }

    nonisolated private static func isOpeningPunctuation(_ character: Character) -> Bool {
        "([{".contains(character)
    }

    nonisolated private static func removingStructuredTags(from text: String, removesSpeakerLabels: Bool) -> String {
        var result = replacingMatches(
            in: text,
            pattern: #"\[\d+(?:[\.,]\d+)?\]"#,
            with: "\n"
        )
        if removesSpeakerLabels {
            result = replacingMatches(in: result, pattern: #"\[S\d+\]\s*"#, with: "")
        } else {
            result = replacingMatches(in: result, pattern: #"\[(S\d+)\]\s*"#, with: "[$1] ")
        }

        // MOSS can emit acoustic annotations such as `[sniff]` in the transcript body.
        // They are metadata for meeting processing, not user-visible spoken text.
        result = replacingMatches(
            in: result,
            pattern: #"\[[a-z][a-z0-9 _-]{0,31}\]\s*"#,
            with: ""
        )

        // Incremental decoding may publish a speaker tag before its closing bracket.
        // Drop only the malformed protocol prefix and preserve the following speech.
        result = replacingMatches(
            in: result,
            pattern: #"\[S[0-9O]{0,3}\s+"#,
            with: ""
        )
        result = replacingMatches(in: result, pattern: #"\[(?:\d|[\.,])*$"#, with: "")
        result = replacingMatches(
            in: result,
            pattern: #"\[(?:S[0-9O]*|[a-z][a-z0-9 _-]*)$"#,
            with: ""
        )
        return result
            .components(separatedBy: .newlines)
            .map {
                replacingMatches(in: $0, pattern: #"[ \t]{2,}"#, with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    nonisolated private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}

nonisolated enum MLXModelFamily: String, CaseIterable, Codable, Identifiable, Sendable {
    case whisper
    case qwen3ASR
    case graniteSpeech
    case senseVoice
    case cohereTranscribe
    case nemotronASR
    case voxtralRealtime
    case mossTranscribeDiarize
    case canary
    case moonshine
    case wav2vec2CTC
    case mmsCTC
    case parakeet
    case lasrCTC
    case generic

    var id: String { rawValue }

    static func family(for repo: String) -> MLXModelFamily {
        MLXModelCatalog.capability(for: repo).family
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
        case .nemotronASR:
            return AppLocalization.localizedString("Nemotron")
        case .voxtralRealtime:
            return AppLocalization.localizedString("Voxtral")
        case .mossTranscribeDiarize:
            return AppLocalization.localizedString("MOSS")
        case .canary:
            return AppLocalization.localizedString("Canary")
        case .moonshine:
            return AppLocalization.localizedString("Moonshine")
        case .wav2vec2CTC:
            return AppLocalization.localizedString("Wav2Vec2")
        case .mmsCTC:
            return AppLocalization.localizedString("MMS")
        case .parakeet:
            return AppLocalization.localizedString("Parakeet")
        case .lasrCTC:
            return AppLocalization.localizedString("LASR")
        case .generic:
            return AppLocalization.localizedString("General MLX ASR")
        }
    }

}

struct MLXLocalTuningSettings: Codable, Equatable {
    var preset: LocalASRRecognitionPreset = .balanced
    var whisperTemperature: Double = 0.0
    var qwenContextBias: String = ""
    var granitePromptBias: String = ""
    var senseVoiceUseITN: Bool = false
    var mossOutputMode: MossASROutputMode = .plainText
    var mossHotwords: String = AppPreferenceKey.asrDictionaryTermsTemplateVariable
    var mossCustomPrompt: String = ""
    var mossMeetingOutputMode: MossASROutputMode = .timestampedDiarization
    var mossMeetingHotwords: String = AppPreferenceKey.asrDictionaryTermsTemplateVariable
    var mossMeetingCustomPrompt: String = ""
    var cohereLongFormStrategy: CohereLongFormStrategy = .voiceActivity
    var cohereUsePunctuation: Bool = true
    var cohereMaxTokens: Int = 1024
    var cohereTemperature: Double = 0.0
    var nemotronStreamLatency: NemotronStreamLatency = .balanced
    var voxtralTranscriptionDelay: VoxtralTranscriptionDelay = .balanced
    var canaryTaskMode: CanaryTaskMode = .transcription
    var canaryTranslationLanguage: String = "fr"
    var canaryUsePunctuation: Bool = true
    var canaryMaxTokens: Int = 200
    var canaryTemperature: Double = 0.0
    var moonshineMaxTokens: Int = 200
    var moonshineTemperature: Double = 0.0
    var mmsLanguageCode: String = "eng"

    init(
        preset: LocalASRRecognitionPreset = .balanced,
        whisperTemperature: Double = 0.0,
        qwenContextBias: String = "",
        granitePromptBias: String = "",
        senseVoiceUseITN: Bool = false,
        mossOutputMode: MossASROutputMode = .plainText,
        mossHotwords: String = AppPreferenceKey.asrDictionaryTermsTemplateVariable,
        mossCustomPrompt: String = "",
        mossMeetingOutputMode: MossASROutputMode = .timestampedDiarization,
        mossMeetingHotwords: String = AppPreferenceKey.asrDictionaryTermsTemplateVariable,
        mossMeetingCustomPrompt: String = "",
        cohereLongFormStrategy: CohereLongFormStrategy = .voiceActivity,
        cohereUsePunctuation: Bool = true,
        cohereMaxTokens: Int = 1024,
        cohereTemperature: Double = 0.0,
        canaryTaskMode: CanaryTaskMode = .transcription,
        canaryTranslationLanguage: String = "fr",
        canaryUsePunctuation: Bool = true,
        canaryMaxTokens: Int = 200,
        canaryTemperature: Double = 0.0,
        moonshineMaxTokens: Int = 200,
        moonshineTemperature: Double = 0.0,
        mmsLanguageCode: String = "eng",
        nemotronStreamLatency: NemotronStreamLatency = .balanced,
        voxtralTranscriptionDelay: VoxtralTranscriptionDelay = .balanced
    ) {
        self.preset = preset
        self.whisperTemperature = whisperTemperature
        self.qwenContextBias = qwenContextBias
        self.granitePromptBias = granitePromptBias
        self.senseVoiceUseITN = senseVoiceUseITN
        self.mossOutputMode = mossOutputMode
        self.mossHotwords = mossHotwords
        self.mossCustomPrompt = mossCustomPrompt
        self.mossMeetingOutputMode = mossMeetingOutputMode
        self.mossMeetingHotwords = mossMeetingHotwords
        self.mossMeetingCustomPrompt = mossMeetingCustomPrompt
        self.cohereLongFormStrategy = cohereLongFormStrategy
        self.cohereUsePunctuation = cohereUsePunctuation
        self.cohereMaxTokens = cohereMaxTokens
        self.cohereTemperature = cohereTemperature
        self.canaryTaskMode = canaryTaskMode
        self.canaryTranslationLanguage = canaryTranslationLanguage
        self.canaryUsePunctuation = canaryUsePunctuation
        self.canaryMaxTokens = canaryMaxTokens
        self.canaryTemperature = canaryTemperature
        self.moonshineMaxTokens = moonshineMaxTokens
        self.moonshineTemperature = moonshineTemperature
        self.mmsLanguageCode = mmsLanguageCode
        self.nemotronStreamLatency = nemotronStreamLatency
        self.voxtralTranscriptionDelay = voxtralTranscriptionDelay
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case whisperTemperature
        case qwenContextBias
        case granitePromptBias
        case senseVoiceUseITN
        case mossOutputMode
        case mossHotwords
        case mossCustomPrompt
        case mossMeetingOutputMode
        case mossMeetingHotwords
        case mossMeetingCustomPrompt
        case cohereLongFormStrategy
        case cohereUsePunctuation
        case cohereMaxTokens
        case cohereTemperature
        case canaryTaskMode
        case canaryTranslationLanguage
        case canaryUsePunctuation
        case canaryMaxTokens
        case canaryTemperature
        case moonshineMaxTokens
        case moonshineTemperature
        case mmsLanguageCode
        case nemotronStreamLatency
        case voxtralTranscriptionDelay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decodeIfPresent(LocalASRRecognitionPreset.self, forKey: .preset) ?? .balanced
        whisperTemperature = try container.decodeIfPresent(Double.self, forKey: .whisperTemperature) ?? 0.0
        qwenContextBias = try container.decodeIfPresent(String.self, forKey: .qwenContextBias) ?? ""
        granitePromptBias = try container.decodeIfPresent(String.self, forKey: .granitePromptBias) ?? ""
        senseVoiceUseITN = try container.decodeIfPresent(Bool.self, forKey: .senseVoiceUseITN) ?? false
        let legacyMossOutputMode = try container.decodeIfPresent(MossASROutputMode.self, forKey: .mossOutputMode)
        let legacyMossHotwords = try container.decodeIfPresent(String.self, forKey: .mossHotwords)
            ?? AppPreferenceKey.asrDictionaryTermsTemplateVariable
        let legacyMossCustomPrompt = try container.decodeIfPresent(String.self, forKey: .mossCustomPrompt) ?? ""
        let hasScopedMossSettings = container.contains(.mossMeetingOutputMode)
            || container.contains(.mossMeetingHotwords)
            || container.contains(.mossMeetingCustomPrompt)
        if hasScopedMossSettings {
            mossOutputMode = legacyMossOutputMode ?? .plainText
            mossHotwords = legacyMossHotwords
            mossCustomPrompt = legacyMossCustomPrompt
            mossMeetingOutputMode = try container.decodeIfPresent(
                MossASROutputMode.self,
                forKey: .mossMeetingOutputMode
            ) ?? .timestampedDiarization
            mossMeetingHotwords = try container.decodeIfPresent(String.self, forKey: .mossMeetingHotwords)
                ?? AppPreferenceKey.asrDictionaryTermsTemplateVariable
            mossMeetingCustomPrompt = try container.decodeIfPresent(String.self, forKey: .mossMeetingCustomPrompt) ?? ""
        } else {
            mossOutputMode = .plainText
            mossHotwords = legacyMossHotwords
            mossCustomPrompt = legacyMossCustomPrompt
            mossMeetingOutputMode = legacyMossOutputMode ?? .timestampedDiarization
            mossMeetingHotwords = legacyMossHotwords
            mossMeetingCustomPrompt = legacyMossCustomPrompt
        }
        cohereLongFormStrategy = try container.decodeIfPresent(CohereLongFormStrategy.self, forKey: .cohereLongFormStrategy)
            ?? .voiceActivity
        cohereUsePunctuation = try container.decodeIfPresent(Bool.self, forKey: .cohereUsePunctuation) ?? true
        cohereMaxTokens = try container.decodeIfPresent(Int.self, forKey: .cohereMaxTokens) ?? 1024
        cohereTemperature = try container.decodeIfPresent(Double.self, forKey: .cohereTemperature) ?? 0.0
        canaryTaskMode = try container.decodeIfPresent(CanaryTaskMode.self, forKey: .canaryTaskMode) ?? .transcription
        canaryTranslationLanguage = try container.decodeIfPresent(String.self, forKey: .canaryTranslationLanguage) ?? "fr"
        canaryUsePunctuation = try container.decodeIfPresent(Bool.self, forKey: .canaryUsePunctuation) ?? true
        canaryMaxTokens = try container.decodeIfPresent(Int.self, forKey: .canaryMaxTokens) ?? 200
        canaryTemperature = try container.decodeIfPresent(Double.self, forKey: .canaryTemperature) ?? 0.0
        moonshineMaxTokens = try container.decodeIfPresent(Int.self, forKey: .moonshineMaxTokens) ?? 200
        moonshineTemperature = try container.decodeIfPresent(Double.self, forKey: .moonshineTemperature) ?? 0.0
        mmsLanguageCode = try container.decodeIfPresent(String.self, forKey: .mmsLanguageCode) ?? "eng"
        nemotronStreamLatency = try container.decodeIfPresent(NemotronStreamLatency.self, forKey: .nemotronStreamLatency)
            ?? .balanced
        voxtralTranscriptionDelay = try container.decodeIfPresent(
            VoxtralTranscriptionDelay.self,
            forKey: .voxtralTranscriptionDelay
        ) ?? .balanced
    }

    static func defaults(for preset: LocalASRRecognitionPreset) -> MLXLocalTuningSettings {
        defaults(for: preset, family: nil)
    }

    static func defaults(for preset: LocalASRRecognitionPreset, family: MLXModelFamily?) -> MLXLocalTuningSettings {
        MLXLocalTuningSettings(
            preset: preset,
            qwenContextBias: family == .qwen3ASR ? AppPromptDefaults.text(for: .qwenASRContextBias) : "",
            mossHotwords: family == .mossTranscribeDiarize
                ? AppPreferenceKey.asrDictionaryTermsTemplateVariable
                : ""
        )
    }

    func mossSettings(for scope: MossASRUsageScope) -> MossASRUsageSettings {
        switch scope {
        case .dictation:
            return MossASRUsageSettings(
                outputMode: mossOutputMode,
                hotwords: mossHotwords,
                customPrompt: mossCustomPrompt
            )
        case .meeting:
            return MossASRUsageSettings(
                outputMode: mossMeetingOutputMode,
                hotwords: mossMeetingHotwords,
                customPrompt: mossMeetingCustomPrompt
            )
        }
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
            senseVoiceUseITN: settings.senseVoiceUseITN,
            mossOutputMode: settings.mossOutputMode,
            mossHotwords: settings.mossHotwords.trimmingCharacters(in: .whitespacesAndNewlines),
            mossCustomPrompt: settings.mossCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            mossMeetingOutputMode: settings.mossMeetingOutputMode,
            mossMeetingHotwords: settings.mossMeetingHotwords.trimmingCharacters(in: .whitespacesAndNewlines),
            mossMeetingCustomPrompt: settings.mossMeetingCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            cohereLongFormStrategy: settings.cohereLongFormStrategy,
            cohereUsePunctuation: settings.cohereUsePunctuation,
            cohereMaxTokens: max(32, min(settings.cohereMaxTokens, 2048)),
            cohereTemperature: max(0.0, min(settings.cohereTemperature, 1.0)),
            canaryTaskMode: settings.canaryTaskMode,
            canaryTranslationLanguage: CanaryLanguageSupport.sanitizedTranslationTarget(settings.canaryTranslationLanguage),
            canaryUsePunctuation: settings.canaryUsePunctuation,
            canaryMaxTokens: max(32, min(settings.canaryMaxTokens, 2048)),
            canaryTemperature: max(0.0, min(settings.canaryTemperature, 1.0)),
            moonshineMaxTokens: max(32, min(settings.moonshineMaxTokens, 2048)),
            moonshineTemperature: max(0.0, min(settings.moonshineTemperature, 1.0)),
            mmsLanguageCode: sanitizedMMSLanguageCode(settings.mmsLanguageCode),
            nemotronStreamLatency: settings.nemotronStreamLatency,
            voxtralTranscriptionDelay: settings.voxtralTranscriptionDelay
        )
    }

    private static func sanitizedMMSLanguageCode(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Preserve unknown legacy free-text values so the settings UI can warn and inference
        // can fail clearly instead of silently rewriting them to English.
        return normalized.isEmpty ? "eng" : normalized
    }
}

struct SherpaOnnxLocalTuningSettings: Codable, Equatable {
    var numThreads: Int = 2
    var contextBias: String = ""
    var funASRMaxNewTokens: Int = 512
    var funASRTopP: Double = 0.8
    var funASRUseITN: Bool = true

    init(
        numThreads: Int = 2,
        contextBias: String = "",
        funASRMaxNewTokens: Int = 512,
        funASRTopP: Double = 0.8,
        funASRUseITN: Bool = true
    ) {
        self.numThreads = numThreads
        self.contextBias = contextBias
        self.funASRMaxNewTokens = funASRMaxNewTokens
        self.funASRTopP = funASRTopP
        self.funASRUseITN = funASRUseITN
    }

    static func defaults(for kind: SherpaOnnxModelKind) -> SherpaOnnxLocalTuningSettings {
        SherpaOnnxLocalTuningSettings(
            contextBias: kind == .funASRNano ? AppPromptDefaults.text(for: .qwenASRContextBias) : ""
        )
    }
}

enum SherpaOnnxLocalTuningSettingsStore {
    static func load(from rawValue: String?) -> [String: SherpaOnnxLocalTuningSettings] {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: SherpaOnnxLocalTuningSettings].self, from: data)
        else {
            return [:]
        }

        return decoded.mapValues { sanitized($0) }
    }

    static func resolvedSettings(
        for modelID: SherpaOnnxModelID,
        kind: SherpaOnnxModelKind,
        rawValue: String?
    ) -> SherpaOnnxLocalTuningSettings {
        var settings = load(from: rawValue)[modelID.rawValue] ?? SherpaOnnxLocalTuningSettings.defaults(for: kind)
        settings = sanitized(settings)
        if kind == .funASRNano,
           settings.contextBias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.contextBias = AppPromptDefaults.text(for: .qwenASRContextBias)
        }
        return settings
    }

    static func save(
        _ settings: SherpaOnnxLocalTuningSettings,
        for modelID: SherpaOnnxModelID,
        rawValue: String?
    ) -> String {
        var stored = load(from: rawValue)
        stored[modelID.rawValue] = sanitized(settings)
        return storageValue(for: stored)
    }

    static func storageValue(for settingsByModelID: [String: SherpaOnnxLocalTuningSettings]) -> String {
        let sanitizedSettings = settingsByModelID.mapValues { sanitized($0) }
        guard let data = try? JSONEncoder().encode(sanitizedSettings),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    static func sanitized(_ settings: SherpaOnnxLocalTuningSettings) -> SherpaOnnxLocalTuningSettings {
        let contextBias = settings.contextBias.trimmingCharacters(in: .whitespacesAndNewlines)
        return SherpaOnnxLocalTuningSettings(
            numThreads: max(1, min(settings.numThreads, 8)),
            contextBias: AppPromptDefaults.matchesKnownDefault(contextBias, kind: .qwenASRContextBias)
                ? ""
                : contextBias,
            funASRMaxNewTokens: max(64, min(settings.funASRMaxNewTokens, 2048)),
            funASRTopP: max(0.1, min(settings.funASRTopP, 1.0)),
            funASRUseITN: settings.funASRUseITN
        )
    }
}

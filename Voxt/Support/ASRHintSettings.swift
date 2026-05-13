import Foundation

enum ASRHintTarget: String, CaseIterable, Codable, Identifiable {
    case dictation
    case mlxAudio
    case whisperKit
    case openAIWhisper
    case glmASR
    case doubaoASR
    case aliyunBailianASR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Direct Dictation")
        case .mlxAudio:
            return AppLocalization.localizedString("MLX Audio")
        case .whisperKit:
            return AppLocalization.localizedString("Whisper")
        case .openAIWhisper:
            return AppLocalization.localizedString("OpenAI Transcribe")
        case .glmASR:
            return AppLocalization.localizedString("GLM ASR")
        case .doubaoASR:
            return AppLocalization.localizedString("Doubao ASR")
        case .aliyunBailianASR:
            return AppLocalization.localizedString("Aliyun Bailian ASR")
        }
    }

    var supportsPromptEditor: Bool {
        switch self {
        case .whisperKit, .openAIWhisper, .glmASR:
            return true
        case .dictation, .mlxAudio, .doubaoASR, .aliyunBailianASR:
            return false
        }
    }

    var supportsLanguageHints: Bool {
        true
    }

    var defaultPromptTemplate: String {
        switch self {
        case .dictation:
            return ""
        case .whisperKit:
            return AppPromptDefaults.text(for: .whisperASRHint)
        case .openAIWhisper:
            return AppPromptDefaults.text(for: .openAIASRHint)
        case .glmASR:
            return AppPromptDefaults.text(for: .glmASRHint)
        case .mlxAudio, .doubaoASR, .aliyunBailianASR:
            return ""
        }
    }

    var helpText: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Direct Dictation uses your main language, optional contextual phrases, on-device preference, and punctuation settings. Prompt editing is not applied.")
        case .mlxAudio:
            return AppLocalization.localizedString("MLX uses language hints by default. Some model families also expose model-specific local tuning in the Configure dialog.")
        case .whisperKit:
            return AppLocalization.localizedString("Whisper uses the resolved main language and a short prompt bias. Keep the prompt concise and recognition-focused.")
        case .openAIWhisper:
            return AppLocalization.localizedString("OpenAI ASR uses the resolved main language and a short prompt bias. Keep the prompt concise and focused on recognition.")
        case .glmASR:
            return AppLocalization.localizedString("GLM ASR uses a short prompt bias. It does not use hotwords in Voxt.")
        case .doubaoASR:
            return AppLocalization.localizedString("Doubao ASR uses language hints. Chinese output follows your selected simplified or traditional main language automatically.")
        case .aliyunBailianASR:
            return AppLocalization.localizedString("Aliyun ASR uses language hints derived from your selected user languages.")
        }
    }

    var settingsTitle: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Dictation Settings")
        case .mlxAudio, .whisperKit, .openAIWhisper, .glmASR, .doubaoASR, .aliyunBailianASR:
            return AppLocalization.localizedString("Engine Hint Settings")
        }
    }

    static func from(engine: TranscriptionEngine, remoteProvider: RemoteASRProvider?) -> ASRHintTarget {
        switch engine {
        case .dictation:
            return .dictation
        case .mlxAudio:
            return .mlxAudio
        case .whisperKit:
            return .whisperKit
        case .remote:
            switch remoteProvider ?? .openAIWhisper {
            case .openAIWhisper:
                return .openAIWhisper
            case .glmASR:
                return .glmASR
            case .doubaoASR:
                return .doubaoASR
            case .aliyunBailianASR:
                return .aliyunBailianASR
            }
        }
    }
}

struct ASRHintSettings: Codable, Equatable {
    var followsUserMainLanguage: Bool = true
    var promptTemplate: String = ""
    var contextualPhrasesText: String = ""
    var prefersOnDeviceRecognition: Bool = false
    var addsPunctuation: Bool = true
    var reportsPartialResults: Bool = true

    init(
        followsUserMainLanguage: Bool = true,
        promptTemplate: String = "",
        contextualPhrasesText: String = "",
        prefersOnDeviceRecognition: Bool = false,
        addsPunctuation: Bool = true,
        reportsPartialResults: Bool = true
    ) {
        self.followsUserMainLanguage = followsUserMainLanguage
        self.promptTemplate = promptTemplate
        self.contextualPhrasesText = contextualPhrasesText
        self.prefersOnDeviceRecognition = prefersOnDeviceRecognition
        self.addsPunctuation = addsPunctuation
        self.reportsPartialResults = reportsPartialResults
    }

    enum CodingKeys: String, CodingKey {
        case followsUserMainLanguage
        case promptTemplate
        case contextualPhrasesText
        case prefersOnDeviceRecognition
        case addsPunctuation
        case reportsPartialResults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        followsUserMainLanguage = try container.decodeIfPresent(Bool.self, forKey: .followsUserMainLanguage) ?? true
        promptTemplate = try container.decodeIfPresent(String.self, forKey: .promptTemplate) ?? ""
        contextualPhrasesText = try container.decodeIfPresent(String.self, forKey: .contextualPhrasesText) ?? ""
        prefersOnDeviceRecognition = try container.decodeIfPresent(Bool.self, forKey: .prefersOnDeviceRecognition) ?? false
        addsPunctuation = try container.decodeIfPresent(Bool.self, forKey: .addsPunctuation) ?? true
        reportsPartialResults = try container.decodeIfPresent(Bool.self, forKey: .reportsPartialResults) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(followsUserMainLanguage, forKey: .followsUserMainLanguage)
        try container.encode(promptTemplate, forKey: .promptTemplate)
        try container.encode(contextualPhrasesText, forKey: .contextualPhrasesText)
        try container.encode(prefersOnDeviceRecognition, forKey: .prefersOnDeviceRecognition)
        try container.encode(addsPunctuation, forKey: .addsPunctuation)
        try container.encode(reportsPartialResults, forKey: .reportsPartialResults)
    }
}

enum ASRHintSettingsStore {
    static func load(from rawValue: String?) -> [ASRHintTarget: ASRHintSettings] {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: ASRHintSettings].self, from: data)
        else {
            return [:]
        }

        var result: [ASRHintTarget: ASRHintSettings] = [:]
        for (key, value) in decoded {
            guard let target = ASRHintTarget(rawValue: key) else { continue }
            result[target] = resolved(sanitized(value, for: target), for: target)
        }
        return result
    }

    static func resolvedSettings(for target: ASRHintTarget, rawValue: String?) -> ASRHintSettings {
        let stored = load(from: rawValue)
        return stored[target] ?? defaultSettings(for: target)
    }

    static func storageValue(for settingsByTarget: [ASRHintTarget: ASRHintSettings]) -> String {
        let serialized = Dictionary(uniqueKeysWithValues: settingsByTarget.map { key, value in
            (key.rawValue, sanitized(value, for: key))
        })
        guard let data = try? JSONEncoder().encode(serialized),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    static func defaultStoredValue() -> String {
        storageValue(for: Dictionary(uniqueKeysWithValues: ASRHintTarget.allCases.map { ($0, ASRHintSettings()) }))
    }

    static func defaultSettings(for target: ASRHintTarget) -> ASRHintSettings {
        resolved(
            ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: ""
            ),
            for: target
        )
    }

    static func resolved(_ settings: ASRHintSettings, for target: ASRHintTarget) -> ASRHintSettings {
        ASRHintSettings(
            followsUserMainLanguage: settings.followsUserMainLanguage,
            promptTemplate: AppPromptDefaults.resolvedStoredText(
                settings.promptTemplate,
                kind: promptKind(for: target)
            ),
            contextualPhrasesText: settings.contextualPhrasesText,
            prefersOnDeviceRecognition: settings.prefersOnDeviceRecognition,
            addsPunctuation: settings.addsPunctuation,
            reportsPartialResults: settings.reportsPartialResults
        )
    }

    static func sanitized(_ settings: ASRHintSettings, for target: ASRHintTarget) -> ASRHintSettings {
        let trimmedPrompt: String
        if target.supportsPromptEditor {
            let candidate = settings.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            trimmedPrompt = AppPromptDefaults.canonicalStoredText(candidate, kind: promptKind(for: target))
        } else {
            trimmedPrompt = ""
        }

        let contextualPhrases = parseContextualPhrases(settings.contextualPhrasesText)

        return ASRHintSettings(
            followsUserMainLanguage: settings.followsUserMainLanguage,
            promptTemplate: trimmedPrompt,
            contextualPhrasesText: contextualPhrases.joined(separator: "\n"),
            prefersOnDeviceRecognition: settings.prefersOnDeviceRecognition,
            addsPunctuation: settings.addsPunctuation,
            reportsPartialResults: settings.reportsPartialResults
        )
    }

    private static func promptKind(for target: ASRHintTarget) -> AppPromptKind {
        switch target {
        case .openAIWhisper:
            return .openAIASRHint
        case .glmASR:
            return .glmASRHint
        case .whisperKit, .dictation, .mlxAudio, .doubaoASR, .aliyunBailianASR:
            return .whisperASRHint
        }
    }

    static func contextualPhrases(from settings: ASRHintSettings) -> [String] {
        parseContextualPhrases(settings.contextualPhrasesText)
    }

    private static func parseContextualPhrases(_ rawValue: String) -> [String] {
        rawValue
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

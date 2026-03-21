import Foundation

enum ASRHintTarget: String, CaseIterable, Codable, Identifiable {
    case mlxAudio
    case whisperKit
    case openAIWhisper
    case glmASR
    case doubaoASR
    case aliyunBailianASR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mlxAudio:
            return AppLocalization.localizedString("MLX Audio")
        case .whisperKit:
            return AppLocalization.localizedString("Whisper")
        case .openAIWhisper:
            return AppLocalization.localizedString("OpenAI Whisper")
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
        case .mlxAudio, .doubaoASR, .aliyunBailianASR:
            return false
        }
    }

    var supportsLanguageHints: Bool {
        true
    }

    var defaultPromptTemplate: String {
        switch self {
        case .whisperKit:
            return AppPreferenceKey.defaultWhisperASRHintPrompt
        case .openAIWhisper:
            return AppPreferenceKey.defaultOpenAIASRHintPrompt
        case .glmASR:
            return AppPreferenceKey.defaultGLMASRHintPrompt
        case .mlxAudio, .doubaoASR, .aliyunBailianASR:
            return ""
        }
    }

    var helpText: String {
        switch self {
        case .mlxAudio:
            return AppLocalization.localizedString("MLX uses language hints only. Prompt editing is not applied for on-device MLX ASR.")
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

    static func from(engine: TranscriptionEngine, remoteProvider: RemoteASRProvider?) -> ASRHintTarget {
        switch engine {
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
        case .dictation:
            return .mlxAudio
        }
    }
}

struct ASRHintSettings: Codable, Equatable {
    var followsUserMainLanguage: Bool = true
    var promptTemplate: String = ""
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
            result[target] = sanitized(value, for: target)
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
        storageValue(for: Dictionary(uniqueKeysWithValues: ASRHintTarget.allCases.map { ($0, defaultSettings(for: $0)) }))
    }

    static func defaultSettings(for target: ASRHintTarget) -> ASRHintSettings {
        ASRHintSettings(
            followsUserMainLanguage: true,
            promptTemplate: target.defaultPromptTemplate
        )
    }

    static func sanitized(_ settings: ASRHintSettings, for target: ASRHintTarget) -> ASRHintSettings {
        let trimmedPrompt: String
        if target.supportsPromptEditor {
            let candidate = settings.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if target == .whisperKit,
               candidate == AppPreferenceKey.legacyDefaultWhisperASRHintPrompt.trimmingCharacters(in: .whitespacesAndNewlines) {
                trimmedPrompt = ""
            } else {
                trimmedPrompt = candidate
            }
        } else {
            trimmedPrompt = ""
        }

        return ASRHintSettings(
            followsUserMainLanguage: settings.followsUserMainLanguage,
            promptTemplate: trimmedPrompt
        )
    }
}

struct ResolvedASRHintPayload {
    var language: String?
    var languageHints: [String] = []
    var chineseOutputVariant: String?
    var prompt: String?
}

@MainActor
enum ASRHintResolver {
    static func resolve(
        target: ASRHintTarget,
        settings: ASRHintSettings,
        userLanguageCodes: [String],
        mlxModelRepo: String? = nil
    ) -> ResolvedASRHintPayload {
        let selectedOptions = UserMainLanguageOption
            .sanitizedSelection(userLanguageCodes)
            .compactMap(UserMainLanguageOption.option(for:))
        let mainLanguage = selectedOptions.first ?? UserMainLanguageOption.fallbackOption()
        let prompt = resolvePrompt(for: target, template: settings.promptTemplate, mainLanguage: mainLanguage)

        switch target {
        case .mlxAudio:
            return ResolvedASRHintPayload(
                language: settings.followsUserMainLanguage ? resolvedMLXLanguage(mainLanguage: mainLanguage, modelRepo: mlxModelRepo) : nil,
                prompt: nil
            )
        case .whisperKit:
            return ResolvedASRHintPayload(
                language: settings.followsUserMainLanguage ? resolvedOpenAILanguage(mainLanguage) : nil,
                prompt: prompt
            )
        case .openAIWhisper:
            return ResolvedASRHintPayload(
                language: settings.followsUserMainLanguage ? resolvedOpenAILanguage(mainLanguage) : nil,
                prompt: prompt
            )
        case .glmASR:
            return ResolvedASRHintPayload(
                language: nil,
                prompt: prompt
            )
        case .doubaoASR:
            return ResolvedASRHintPayload(
                language: settings.followsUserMainLanguage ? resolvedDoubaoLanguage(mainLanguage) : nil,
                chineseOutputVariant: resolvedDoubaoChineseVariant(mainLanguage),
                prompt: nil
            )
        case .aliyunBailianASR:
            let hints = settings.followsUserMainLanguage ? resolvedAliyunLanguageHints(options: selectedOptions) : []
            return ResolvedASRHintPayload(
                language: hints.first,
                languageHints: hints,
                prompt: nil
            )
        }
    }

    static func selectedLanguageSummary(_ userLanguageCodes: [String]) -> String {
        UserMainLanguageOption
            .sanitizedSelection(userLanguageCodes)
            .compactMap(UserMainLanguageOption.option(for:))
            .map(\.promptName)
            .joined(separator: ", ")
    }

    static func outputVariantDescription(for mainLanguage: UserMainLanguageOption) -> String {
        guard mainLanguage.isChinese else {
            return AppLocalization.localizedString("Not applied")
        }
        return mainLanguage.isTraditionalChinese
            ? AppLocalization.localizedString("Traditional Chinese")
            : AppLocalization.localizedString("Simplified Chinese")
    }

    private static func resolvePrompt(
        for target: ASRHintTarget,
        template: String,
        mainLanguage: UserMainLanguageOption
    ) -> String? {
        guard target.supportsPromptEditor else { return nil }
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let resolved = trimmed.replacingOccurrences(
            of: AppPreferenceKey.asrUserMainLanguageTemplateVariable,
            with: mainLanguage.promptName
        )
        let compact = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? nil : compact
    }

    private static func resolvedOpenAILanguage(_ language: UserMainLanguageOption) -> String {
        language.baseLanguageCode
    }

    private static func resolvedDoubaoLanguage(_ language: UserMainLanguageOption) -> String? {
        switch language.baseLanguageCode {
        case "zh":
            return "zh-CN"
        case "en":
            return "en-US"
        case "ja":
            return "ja-JP"
        case "ko":
            return "ko-KR"
        case "id":
            return "id-ID"
        case "es":
            return "es-MX"
        default:
            return nil
        }
    }

    private static func resolvedDoubaoChineseVariant(_ language: UserMainLanguageOption) -> String? {
        guard language.isChinese else { return nil }
        return language.isTraditionalChinese ? "zh-Hant" : "zh-Hans"
    }

    private static func resolvedAliyunLanguageHints(options: [UserMainLanguageOption]) -> [String] {
        var seen = Set<String>()
        let mapped = options.compactMap { option -> String? in
            switch option.baseLanguageCode {
            case "zh":
                return "zh"
            case "en":
                return "en"
            case "ja":
                return "ja"
            case "ko":
                return "ko"
            default:
                return nil
            }
        }

        let deduped = mapped.filter { seen.insert($0).inserted }
        return Array(deduped.prefix(3))
    }

    private static func resolvedMLXLanguage(mainLanguage: UserMainLanguageOption, modelRepo: String?) -> String? {
        guard let modelRepo else { return nil }
        if modelRepo.localizedCaseInsensitiveContains("Qwen3-ASR") {
            return mainLanguage.promptName
        }

        switch mainLanguage.baseLanguageCode {
        case "zh":
            return "zh"
        case "en":
            return "en"
        case "ja":
            return "ja"
        case "ko":
            return "ko"
        default:
            return mainLanguage.baseLanguageCode
        }
    }
}

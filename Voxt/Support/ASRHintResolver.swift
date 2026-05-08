import Foundation

struct ResolvedASRHintPayload {
    var language: String?
    var languageHints: [String] = []
    var chineseOutputVariant: String?
    var prompt: String?
    var otherLanguages: [String] = []
    var multilingualContext: String?
}

struct ResolvedDictationSettings: Equatable {
    var localeIdentifier: String?
    var contextualPhrases: [String]
    var prefersOnDeviceRecognition: Bool
    var addsPunctuation: Bool
    var reportsPartialResults: Bool
}

@MainActor
enum ASRHintResolver {
    static func resolve(
        target: ASRHintTarget,
        settings: ASRHintSettings,
        userLanguageCodes: [String],
        mlxModelRepo: String? = nil,
        dictionaryTerms: String = ""
    ) -> ResolvedASRHintPayload {
        let selectedOptions = selectedLanguageOptions(userLanguageCodes)
        let mainLanguage = selectedOptions.first ?? UserMainLanguageOption.fallbackOption()
        let otherLanguageOptions = Array(selectedOptions.dropFirst())
        let prompt = resolvePrompt(
            for: target,
            template: settings.promptTemplate,
            mainLanguage: mainLanguage,
            otherLanguages: otherLanguageOptions,
            dictionaryTerms: dictionaryTerms
        )
        let otherLanguages = otherLanguageOptions.map(\.promptName)
        let usesExplicitSingleLanguageHint = settings.followsUserMainLanguage && otherLanguageOptions.isEmpty
        let mlxResolvedLanguage = settings.followsUserMainLanguage
            ? resolvedMLXLanguageHint(
                mainLanguage: mainLanguage,
                otherLanguages: otherLanguageOptions,
                modelRepo: mlxModelRepo
            )
            : nil
        let multilingualContext = settings.followsUserMainLanguage
            ? resolvedMultilingualContext(mainLanguage: mainLanguage, otherLanguages: otherLanguageOptions)
            : nil

        switch target {
        case .dictation:
            return ResolvedASRHintPayload()
        case .mlxAudio:
            return ResolvedASRHintPayload(
                language: mlxResolvedLanguage,
                prompt: nil,
                otherLanguages: otherLanguages,
                multilingualContext: multilingualContext
            )
        case .whisperKit:
            return ResolvedASRHintPayload(
                language: usesExplicitSingleLanguageHint ? resolvedOpenAILanguage(mainLanguage) : nil,
                prompt: prompt,
                otherLanguages: otherLanguages
            )
        case .openAIWhisper:
            return ResolvedASRHintPayload(
                language: usesExplicitSingleLanguageHint ? resolvedOpenAILanguage(mainLanguage) : nil,
                prompt: prompt,
                otherLanguages: otherLanguages
            )
        case .glmASR:
            return ResolvedASRHintPayload(
                language: nil,
                prompt: prompt,
                otherLanguages: otherLanguages
            )
        case .doubaoASR:
            return ResolvedASRHintPayload(
                language: usesExplicitSingleLanguageHint ? resolvedDoubaoLanguage(mainLanguage) : nil,
                chineseOutputVariant: resolvedDoubaoChineseVariant(mainLanguage),
                prompt: nil,
                otherLanguages: otherLanguages
            )
        case .aliyunBailianASR:
            let hints = settings.followsUserMainLanguage ? resolvedAliyunLanguageHints(options: selectedOptions) : []
            return ResolvedASRHintPayload(
                language: hints.first,
                languageHints: hints,
                prompt: nil,
                otherLanguages: otherLanguages
            )
        }
    }

    static func selectedLanguageOptions(_ userLanguageCodes: [String]) -> [UserMainLanguageOption] {
        UserMainLanguageOption
            .sanitizedSelection(userLanguageCodes)
            .compactMap(UserMainLanguageOption.option(for:))
    }

    static func selectedLanguageSummary(_ userLanguageCodes: [String]) -> String {
        selectedLanguageOptions(userLanguageCodes)
            .map(\.promptName)
            .joined(separator: ", ")
    }

    static func secondaryLanguageSummary(_ userLanguageCodes: [String]) -> String {
        let secondary = selectedLanguageOptions(userLanguageCodes)
            .dropFirst()
            .map(\.promptName)
        return secondary.isEmpty ? AppLocalization.localizedString("Not applied") : secondary.joined(separator: ", ")
    }

    static func outputVariantDescription(for mainLanguage: UserMainLanguageOption) -> String {
        guard mainLanguage.isChinese else {
            return AppLocalization.localizedString("Not applied")
        }
        return mainLanguage.isTraditionalChinese
            ? AppLocalization.localizedString("Traditional Chinese")
            : AppLocalization.localizedString("Simplified Chinese")
    }

    static func resolveDictationSettings(
        settings: ASRHintSettings,
        userLanguageCodes: [String]
    ) -> ResolvedDictationSettings {
        let mainLanguage = UserMainLanguageOption
            .sanitizedSelection(userLanguageCodes)
            .compactMap(UserMainLanguageOption.option(for:))
            .first ?? UserMainLanguageOption.fallbackOption()

        return ResolvedDictationSettings(
            localeIdentifier: settings.followsUserMainLanguage ? resolvedDictationLocaleIdentifier(mainLanguage) : nil,
            contextualPhrases: ASRHintSettingsStore.contextualPhrases(from: settings),
            prefersOnDeviceRecognition: settings.prefersOnDeviceRecognition,
            addsPunctuation: settings.addsPunctuation,
            reportsPartialResults: settings.reportsPartialResults
        )
    }

    static func resolveTemplateVariables(
        in template: String,
        userLanguageCodes: [String],
        dictionaryTerms: String = "",
        appendOtherLanguagesWhenMissing: Bool = false
    ) -> String {
        let selectedOptions = selectedLanguageOptions(userLanguageCodes)
        let mainLanguage = selectedOptions.first ?? UserMainLanguageOption.fallbackOption()
        let otherLanguages = Array(selectedOptions.dropFirst())
        return resolveTemplateVariables(
            in: template,
            mainLanguage: mainLanguage,
            otherLanguages: otherLanguages,
            dictionaryTerms: dictionaryTerms,
            appendOtherLanguagesWhenMissing: appendOtherLanguagesWhenMissing
        )
    }

    private static func resolvePrompt(
        for target: ASRHintTarget,
        template: String,
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption],
        dictionaryTerms: String
    ) -> String? {
        guard target.supportsPromptEditor else { return nil }
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return autoGeneratedPrompt(
                for: target,
                mainLanguage: mainLanguage,
                otherLanguages: otherLanguages
            )
        }

        let resolved = resolveTemplateVariables(
            in: trimmed,
            mainLanguage: mainLanguage,
            otherLanguages: otherLanguages,
            dictionaryTerms: dictionaryTerms,
            appendOtherLanguagesWhenMissing: true
        )
        let compact = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? nil : compact
    }

    private static func resolveTemplateVariables(
        in template: String,
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption],
        dictionaryTerms: String,
        appendOtherLanguagesWhenMissing: Bool
    ) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let otherLanguagesSummary = otherLanguages.isEmpty
            ? "None specified"
            : otherLanguages.map(\.promptName).joined(separator: ", ")

        var resolved = trimmed
            .replacingOccurrences(
                of: AppPreferenceKey.asrUserMainLanguageTemplateVariable,
                with: mainLanguage.promptName
            )
            .replacingOccurrences(
                of: AppPreferenceKey.asrUserOtherLanguagesTemplateVariable,
                with: otherLanguagesSummary
            )
            .replacingOccurrences(
                of: AppPreferenceKey.asrDictionaryTermsTemplateVariable,
                with: dictionaryTerms.trimmingCharacters(in: .whitespacesAndNewlines)
            )

        if appendOtherLanguagesWhenMissing,
           !otherLanguages.isEmpty,
           !trimmed.contains(AppPreferenceKey.asrUserOtherLanguagesTemplateVariable) {
            resolved += "\nOther frequently used languages: \(otherLanguagesSummary)."
        }

        return resolved
    }

    private static func autoGeneratedPrompt(
        for target: ASRHintTarget,
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption]
    ) -> String? {
        guard !otherLanguages.isEmpty else { return nil }
        let otherLanguagesSummary = otherLanguages.map(\.promptName).joined(separator: ", ")

        switch target {
        case .whisperKit, .openAIWhisper, .glmASR:
            return """
                The speaker's primary language is \(mainLanguage.promptName), and they may also speak \(otherLanguagesSummary). Mixed-language speech is expected. Preserve names, product terms, URLs, and code-like text exactly as spoken.
                """
        case .dictation, .mlxAudio, .doubaoASR, .aliyunBailianASR:
            return nil
        }
    }

    private static func resolvedMultilingualContext(
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption]
    ) -> String? {
        guard !otherLanguages.isEmpty else { return nil }
        let otherLanguagesSummary = otherLanguages.map(\.promptName).joined(separator: ", ")
        return """
            Primary language: \(mainLanguage.promptName)
            Other frequently used languages: \(otherLanguagesSummary)
            Mixed-language speech may appear. Preserve names, brands, URLs, and code-like text exactly as spoken.
            """
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
        if modelRepo.localizedCaseInsensitiveContains("granite-4.0-1b-speech") {
            return nil
        }
        if modelRepo.localizedCaseInsensitiveContains("cohere-transcribe") || modelRepo.localizedCaseInsensitiveContains("cohere") {
            switch mainLanguage.baseLanguageCode {
            case "zh":
                return "zh"
            case "en":
                return "en"
            case "ja":
                return "ja"
            case "ko":
                return "ko"
            case "vi":
                return "vi"
            case "ar":
                return "ar"
            case "el":
                return "el"
            case "pl":
                return "pl"
            case "nl":
                return "nl"
            case "pt":
                return "pt"
            case "it":
                return "it"
            case "es":
                return "es"
            case "de":
                return "de"
            case "fr":
                return "fr"
            default:
                return nil
            }
        }
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

    private static func resolvedMLXLanguageHint(
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption],
        modelRepo: String?
    ) -> String? {
        guard let modelRepo else { return nil }

        if mlxRequiresExplicitPrimaryLanguage(modelRepo: modelRepo) {
            return resolvedMLXLanguage(mainLanguage: mainLanguage, modelRepo: modelRepo)
        }

        guard otherLanguages.isEmpty else { return nil }
        return resolvedMLXLanguage(mainLanguage: mainLanguage, modelRepo: modelRepo)
    }

    private static func mlxRequiresExplicitPrimaryLanguage(modelRepo: String) -> Bool {
        let lower = modelRepo.lowercased()
        return lower.contains("cohere-transcribe") || lower.contains("cohere")
    }

    private static func resolvedDictationLocaleIdentifier(_ mainLanguage: UserMainLanguageOption) -> String {
        switch mainLanguage.code {
        case "zh-hans":
            return "zh-CN"
        case "zh-hant":
            return "zh-TW"
        default:
            return mainLanguage.baseLanguageCode
        }
    }
}

import SwiftUI

extension Notification.Name {
    static let voxtSettingsSelectTab = Notification.Name("voxt.settings.selectTab")
    static let voxtSettingsNavigate = Notification.Name("voxt.settings.navigate")
    static let voxtInterfaceLanguageDidChange = Notification.Name("voxt.interfaceLanguage.didChange")
    static let voxtConfigurationDidImport = Notification.Name("voxt.configuration.didImport")
    static let voxtSelectedInputDeviceDidChange = Notification.Name("voxt.selectedInputDevice.didChange")
    static let voxtAudioInputDevicesDidChange = Notification.Name("voxt.audioInputDevices.didChange")
    static let voxtOverlayAppearanceDidChange = Notification.Name("voxt.overlayAppearance.didChange")
}

enum SettingsDisplayMode: Equatable {
    case normal
    case onboarding(step: OnboardingStep)
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case language
    case model
    case transcription
    case translation
    case rewrite
    case appEnhancement
    case meeting
    case finish

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .language:
            return "Language"
        case .model:
            return "Model"
        case .transcription:
            return "Transcription"
        case .translation:
            return "Translation"
        case .rewrite:
            return "Rewrite"
        case .appEnhancement:
            return "App Enhancement"
        case .meeting:
            return "Meeting"
        case .finish:
            return "Finish"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .language:
            return "Choose interface language and main language."
        case .model:
            return "Choose one ASR model path and one LLM path for the rest of onboarding."
        case .transcription:
            return "Confirm microphone behavior, shortcut preset, and transcription basics."
        case .translation:
            return "Adjust output behavior and verify the current translation model path."
        case .rewrite:
            return "Understand voice rewrite mode for selected text and prompt-style generation."
        case .appEnhancement:
            return "Optionally enable app-aware prompt switching."
        case .meeting:
            return "Optionally enable the dedicated meeting workflow and verify blockers."
        case .finish:
            return "Import or export your setup, then leave onboarding."
        }
    }

    var title: String {
        AppLocalization.localizedString(rawTitleKey)
    }

    private var rawTitleKey: String {
        switch self {
        case .language:
            return "Language"
        case .model:
            return "Model"
        case .transcription:
            return "Transcription"
        case .translation:
            return "Translation"
        case .rewrite:
            return "Rewrite"
        case .appEnhancement:
            return "App Enhancement"
        case .meeting:
            return "Meeting"
        case .finish:
            return "Finish"
        }
    }

    var stepNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    var previous: OnboardingStep? {
        guard let index = Self.allCases.firstIndex(of: self),
              index > 0 else {
            return nil
        }
        return Self.allCases[index - 1]
    }

    var next: OnboardingStep? {
        guard let index = Self.allCases.firstIndex(of: self),
              index + 1 < Self.allCases.count else {
            return nil
        }
        return Self.allCases[index + 1]
    }
}

enum OnboardingStepStatus: String {
    case ready
    case needsSetup
    case optional
    case done

    var titleKey: LocalizedStringKey {
        switch self {
        case .ready:
            return "Ready"
        case .needsSetup:
            return "Needs Setup"
        case .optional:
            return "Optional"
        case .done:
            return "Done"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .needsSetup:
            return .orange
        case .optional:
            return .secondary
        case .done:
            return .accentColor
        }
    }
}

struct OnboardingStepStatusSnapshot {
    var hasModelIssues: Bool
    var hasRecordingMicrophone: Bool
    var hasRecordingPermissions: Bool
    var hasRewriteIssues: Bool
    var appEnhancementEnabled: Bool
    var meetingNotesEnabled: Bool
    var hasMeetingIssues: Bool
}

enum OnboardingStepStatusResolver {
    static func resolve(
        step: OnboardingStep,
        snapshot: OnboardingStepStatusSnapshot
    ) -> OnboardingStepStatus {
        switch step {
        case .language:
            return .ready
        case .model:
            return snapshot.hasModelIssues ? .needsSetup : .ready
        case .transcription:
            return (snapshot.hasRecordingMicrophone && snapshot.hasRecordingPermissions) ? .ready : .needsSetup
        case .translation:
            return .ready
        case .rewrite:
            return snapshot.hasRewriteIssues ? .needsSetup : .ready
        case .appEnhancement:
            return snapshot.appEnhancementEnabled ? .ready : .optional
        case .meeting:
            guard snapshot.meetingNotesEnabled else { return .optional }
            return snapshot.hasMeetingIssues ? .needsSetup : .ready
        case .finish:
            return .done
        }
    }
}

enum SettingsNavigationSection: String, Hashable {
    case generalConfiguration
    case generalAudio
    case generalTranscriptionUI
    case generalLanguages
    case generalOutput
    case generalLogging
    case generalAppBehavior
    case modelEngine
    case modelTextEnhancement
    case modelTranslation
    case modelContentRewrite
    case modelTranscriptionTest
    case dictionarySettings
    case dictionaryEntries
    case appBranchSources
    case appBranchGroups
    case historySettings
    case historyEntries
    case permissionsMain
    case permissionsAppBranchURLAuthorization
    case aboutVoxt
    case aboutProject
    case aboutAuthor
    case aboutThanks
    case aboutLogs

    var tab: SettingsTab {
        switch self {
        case .generalConfiguration,
             .generalAudio,
             .generalTranscriptionUI,
             .generalLanguages,
             .generalOutput,
             .generalLogging,
             .generalAppBehavior:
            return .general
        case .modelEngine,
             .modelTextEnhancement,
             .modelTranslation,
             .modelContentRewrite,
             .modelTranscriptionTest:
            return .model
        case .dictionarySettings,
             .dictionaryEntries:
            return .dictionary
        case .appBranchSources,
             .appBranchGroups:
            return .feature
        case .historySettings,
             .historyEntries:
            return .history
        case .permissionsMain,
             .permissionsAppBranchURLAuthorization:
            return .permissions
        case .aboutVoxt,
             .aboutProject,
             .aboutAuthor,
             .aboutThanks,
             .aboutLogs:
            return .about
        }
    }

    var titleKey: String {
        switch self {
        case .generalConfiguration: return "Configuration"
        case .generalAudio: return "Audio"
        case .generalTranscriptionUI: return "Transcription UI"
        case .generalLanguages: return "Languages"
        case .generalOutput: return "Output"
        case .generalLogging: return "Logging"
        case .generalAppBehavior: return "App Behavior"
        case .modelEngine: return "Engine"
        case .modelTextEnhancement: return "Text Enhancement"
        case .modelTranslation: return "Translation"
        case .modelContentRewrite: return "Content Rewrite"
        case .modelTranscriptionTest: return "Transcription Test"
        case .dictionarySettings: return "Settings"
        case .dictionaryEntries: return "Dictionary Entries"
        case .appBranchSources: return "Sources"
        case .appBranchGroups: return "Groups"
        case .historySettings: return "History Settings"
        case .historyEntries: return "History Entries"
        case .permissionsMain: return "Permissions"
        case .permissionsAppBranchURLAuthorization: return "App Branch URL Authorization"
        case .aboutVoxt: return "Voxt"
        case .aboutProject: return "Project"
        case .aboutAuthor: return "Author"
        case .aboutThanks: return "Thanks"
        case .aboutLogs: return "Logs"
        }
    }

    var title: String {
        AppLocalization.localizedString(titleKey)
    }
}

struct SettingsNavigationTarget: Hashable {
    let tab: SettingsTab
    let section: SettingsNavigationSection?
    let featureTab: FeatureSettingsTab?

    init(tab: SettingsTab, section: SettingsNavigationSection? = nil, featureTab: FeatureSettingsTab? = nil) {
        self.tab = tab
        self.section = section
        self.featureTab = featureTab ?? Self.defaultFeatureTab(for: tab, section: section)
    }

    init?(notification: Notification) {
        guard let rawTab = notification.userInfo?["tab"] as? String,
              let tab = SettingsTab(rawValue: rawTab)
        else {
            return nil
        }

        let section: SettingsNavigationSection?
        if let rawSection = notification.userInfo?["section"] as? String,
           !rawSection.isEmpty {
            section = SettingsNavigationSection(rawValue: rawSection)
        } else {
            section = nil
        }

        let featureTab: FeatureSettingsTab?
        if let rawFeatureTab = notification.userInfo?["featureTab"] as? String,
           !rawFeatureTab.isEmpty {
            featureTab = FeatureSettingsTab(rawValue: rawFeatureTab)
        } else {
            featureTab = Self.defaultFeatureTab(for: tab, section: section)
        }

        self.init(tab: tab == .appEnhancement ? .feature : tab, section: section, featureTab: featureTab)
    }

    var userInfo: [String: String] {
        [
            "tab": tab.rawValue,
            "section": section?.rawValue ?? "",
            "featureTab": featureTab?.rawValue ?? ""
        ]
    }

    static func defaultFeatureTab(
        for tab: SettingsTab,
        section: SettingsNavigationSection?
    ) -> FeatureSettingsTab? {
        if tab == .appEnhancement {
            return .appEnhancement
        }
        guard tab == .feature || section?.tab == .feature else { return nil }
        switch section {
        case .appBranchSources, .appBranchGroups:
            return .appEnhancement
        case .none:
            return .transcription
        default:
            return .transcription
        }
    }
}

struct SettingsNavigationRequest: Identifiable, Equatable {
    let id: UUID
    let target: SettingsNavigationTarget

    init(id: UUID = UUID(), target: SettingsNavigationTarget) {
        self.id = id
        self.target = target
    }
}

extension View {
    func settingsNavigationAnchor(_ section: SettingsNavigationSection) -> some View {
        id(section.rawValue)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case report
    case general
    case model
    case feature
    case dictionary
    case appEnhancement
    case history
    case permissions
    case hotkey
    case about

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .permissions: return "Permissions"
        case .history: return "History"
        case .report: return "Dashboard"
        case .model: return "Model"
        case .feature: return "Feature"
        case .dictionary: return "Dictionary"
        case .appEnhancement: return "App Branch"
        case .hotkey: return "Hotkey"
        case .about: return "About"
        }
    }

    var title: String { AppLocalization.localizedString(rawTitleKey) }

    private var rawTitleKey: String {
        switch self {
        case .general: return "General"
        case .permissions: return "Permissions"
        case .history: return "History"
        case .report: return "Dashboard"
        case .model: return "Model"
        case .feature: return "Feature"
        case .dictionary: return "Dictionary"
        case .appEnhancement: return "App Branch"
        case .hotkey: return "Hotkey"
        case .about: return "About"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .permissions: return "lock.shield"
        case .history: return "clock.arrow.circlepath"
        case .report: return "chart.bar"
        case .model: return "waveform"
        case .feature: return "square.grid.2x2"
        case .dictionary: return "book.closed"
        case .appEnhancement: return "sparkles.rectangle.stack"
        case .hotkey: return "keyboard"
        case .about: return "info.circle"
        }
    }

    static func visibleTabs(appEnhancementEnabled: Bool) -> [SettingsTab] {
        allCases.filter { tab in
            switch tab {
            case .appEnhancement:
                return false
            default:
                return true
            }
        }
    }
}

enum SettingsSidebarMode: Equatable {
    case root
    case feature
}

enum FeatureSettingsTab: String, CaseIterable, Identifiable {
    case transcription
    case translation
    case rewrite
    case appEnhancement
    case meeting

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .transcription: return "Transcription"
        case .translation: return "Translation"
        case .rewrite: return "Rewrite"
        case .appEnhancement: return "App Enhancement"
        case .meeting: return "Meeting"
        }
    }

    var title: String {
        AppLocalization.localizedString(rawTitleKey)
    }

    private var rawTitleKey: String {
        switch self {
        case .transcription: return "Transcription"
        case .translation: return "Translation"
        case .rewrite: return "Rewrite"
        case .appEnhancement: return "App Enhancement"
        case .meeting: return "Meeting"
        }
    }

    var iconName: String {
        switch self {
        case .transcription: return "waveform.and.mic"
        case .translation: return "globe"
        case .rewrite: return "text.badge.star"
        case .appEnhancement: return "sparkles.rectangle.stack"
        case .meeting: return "person.2.crop.square.stack"
        }
    }

    static func visibleTabs(appEnhancementEnabled: Bool, meetingEnabled: Bool) -> [FeatureSettingsTab] {
        allCases.filter { tab in
            switch tab {
            case .appEnhancement:
                return appEnhancementEnabled
            case .meeting:
                return meetingEnabled
            default:
                return true
            }
        }
    }
}

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
            Divider()
        }
    }
}

enum AppInterfaceLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .japanese: return "Japanese"
        }
    }

    var title: String { AppLocalization.localizedString(rawTitleKey) }

    private var rawTitleKey: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .japanese: return "Japanese"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Self.resolvedSystemLanguage.rawValue
        case .english:
            return "en"
        case .chineseSimplified:
            return "zh-Hans"
        case .japanese:
            return "ja"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    static var resolvedSystemLanguage: AppInterfaceLanguage {
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else {
            return .english
        }
        if preferred.hasPrefix("zh") {
            return .chineseSimplified
        }
        if preferred.hasPrefix("ja") {
            return .japanese
        }
        if preferred.hasPrefix("en") {
            return .english
        }
        return .english
    }
}

struct UserMainLanguageOption: Identifiable, Hashable {
    let code: String
    let promptName: String
    let aliases: [String]

    var id: String { code }

    func title(locale: Locale = AppLocalization.locale) -> String {
        switch code {
        case "zh-hans":
            return AppLocalization.localizedString("Chinese (Simplified)")
        case "zh-hant":
            return AppLocalization.localizedString("Chinese (Traditional)")
        default:
            break
        }
        return locale.localizedString(forLanguageCode: code) ?? promptName
    }

    func matches(_ query: String, locale: Locale = AppLocalization.locale) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }
        let haystack = ([code, promptName, title(locale: locale)] + aliases)
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(normalizedQuery)
    }

    static let fallbackCode = "en"

    static let all: [UserMainLanguageOption] = [
        .init(code: "af", promptName: "Afrikaans", aliases: []),
        .init(code: "am", promptName: "Amharic", aliases: []),
        .init(code: "ar", promptName: "Arabic", aliases: []),
        .init(code: "as", promptName: "Assamese", aliases: []),
        .init(code: "az", promptName: "Azerbaijani", aliases: []),
        .init(code: "be", promptName: "Belarusian", aliases: []),
        .init(code: "bg", promptName: "Bulgarian", aliases: []),
        .init(code: "bn", promptName: "Bengali", aliases: []),
        .init(code: "bo", promptName: "Tibetan", aliases: []),
        .init(code: "br", promptName: "Breton", aliases: []),
        .init(code: "bs", promptName: "Bosnian", aliases: []),
        .init(code: "ca", promptName: "Catalan", aliases: []),
        .init(code: "cs", promptName: "Czech", aliases: []),
        .init(code: "cy", promptName: "Welsh", aliases: []),
        .init(code: "da", promptName: "Danish", aliases: []),
        .init(code: "de", promptName: "German", aliases: []),
        .init(code: "el", promptName: "Greek", aliases: []),
        .init(code: "en", promptName: "English", aliases: []),
        .init(code: "es", promptName: "Spanish", aliases: []),
        .init(code: "et", promptName: "Estonian", aliases: []),
        .init(code: "eu", promptName: "Basque", aliases: []),
        .init(code: "fa", promptName: "Persian", aliases: ["Farsi"]),
        .init(code: "fi", promptName: "Finnish", aliases: []),
        .init(code: "fo", promptName: "Faroese", aliases: []),
        .init(code: "fr", promptName: "French", aliases: []),
        .init(code: "gl", promptName: "Galician", aliases: []),
        .init(code: "gu", promptName: "Gujarati", aliases: []),
        .init(code: "ha", promptName: "Hausa", aliases: []),
        .init(code: "he", promptName: "Hebrew", aliases: []),
        .init(code: "hi", promptName: "Hindi", aliases: []),
        .init(code: "hr", promptName: "Croatian", aliases: []),
        .init(code: "ht", promptName: "Haitian Creole", aliases: []),
        .init(code: "hu", promptName: "Hungarian", aliases: []),
        .init(code: "hy", promptName: "Armenian", aliases: []),
        .init(code: "id", promptName: "Indonesian", aliases: ["Bahasa Indonesia"]),
        .init(code: "is", promptName: "Icelandic", aliases: []),
        .init(code: "it", promptName: "Italian", aliases: []),
        .init(code: "ja", promptName: "Japanese", aliases: []),
        .init(code: "jv", promptName: "Javanese", aliases: []),
        .init(code: "ka", promptName: "Georgian", aliases: []),
        .init(code: "kk", promptName: "Kazakh", aliases: []),
        .init(code: "km", promptName: "Khmer", aliases: []),
        .init(code: "kn", promptName: "Kannada", aliases: []),
        .init(code: "ko", promptName: "Korean", aliases: []),
        .init(code: "la", promptName: "Latin", aliases: []),
        .init(code: "lb", promptName: "Luxembourgish", aliases: []),
        .init(code: "lo", promptName: "Lao", aliases: []),
        .init(code: "lt", promptName: "Lithuanian", aliases: []),
        .init(code: "lv", promptName: "Latvian", aliases: []),
        .init(code: "mg", promptName: "Malagasy", aliases: []),
        .init(code: "mi", promptName: "Maori", aliases: ["Māori"]),
        .init(code: "mk", promptName: "Macedonian", aliases: []),
        .init(code: "ml", promptName: "Malayalam", aliases: []),
        .init(code: "mn", promptName: "Mongolian", aliases: []),
        .init(code: "mr", promptName: "Marathi", aliases: []),
        .init(code: "ms", promptName: "Malay", aliases: []),
        .init(code: "mt", promptName: "Maltese", aliases: []),
        .init(code: "my", promptName: "Burmese", aliases: ["Myanmar"]),
        .init(code: "ne", promptName: "Nepali", aliases: []),
        .init(code: "nl", promptName: "Dutch", aliases: []),
        .init(code: "nn", promptName: "Norwegian Nynorsk", aliases: []),
        .init(code: "no", promptName: "Norwegian", aliases: []),
        .init(code: "oc", promptName: "Occitan", aliases: []),
        .init(code: "pa", promptName: "Punjabi", aliases: []),
        .init(code: "pl", promptName: "Polish", aliases: []),
        .init(code: "ps", promptName: "Pashto", aliases: []),
        .init(code: "pt", promptName: "Portuguese", aliases: []),
        .init(code: "ro", promptName: "Romanian", aliases: []),
        .init(code: "ru", promptName: "Russian", aliases: []),
        .init(code: "sa", promptName: "Sanskrit", aliases: []),
        .init(code: "sd", promptName: "Sindhi", aliases: []),
        .init(code: "si", promptName: "Sinhala", aliases: []),
        .init(code: "sk", promptName: "Slovak", aliases: []),
        .init(code: "sl", promptName: "Slovenian", aliases: []),
        .init(code: "sn", promptName: "Shona", aliases: []),
        .init(code: "so", promptName: "Somali", aliases: []),
        .init(code: "sq", promptName: "Albanian", aliases: []),
        .init(code: "sr", promptName: "Serbian", aliases: []),
        .init(code: "su", promptName: "Sundanese", aliases: []),
        .init(code: "sv", promptName: "Swedish", aliases: []),
        .init(code: "sw", promptName: "Swahili", aliases: []),
        .init(code: "ta", promptName: "Tamil", aliases: []),
        .init(code: "te", promptName: "Telugu", aliases: []),
        .init(code: "tg", promptName: "Tajik", aliases: []),
        .init(code: "th", promptName: "Thai", aliases: []),
        .init(code: "tk", promptName: "Turkmen", aliases: []),
        .init(code: "tl", promptName: "Tagalog", aliases: ["Filipino"]),
        .init(code: "tr", promptName: "Turkish", aliases: []),
        .init(code: "tt", promptName: "Tatar", aliases: []),
        .init(code: "uk", promptName: "Ukrainian", aliases: []),
        .init(code: "ur", promptName: "Urdu", aliases: []),
        .init(code: "uz", promptName: "Uzbek", aliases: []),
        .init(code: "vi", promptName: "Vietnamese", aliases: []),
        .init(code: "yi", promptName: "Yiddish", aliases: []),
        .init(code: "yo", promptName: "Yoruba", aliases: []),
        .init(code: "zh-hans", promptName: "Simplified Chinese", aliases: ["Chinese", "Mandarin", "Chinese (Simplified)"]),
        .init(code: "zh-hant", promptName: "Traditional Chinese", aliases: ["Chinese", "Mandarin", "Chinese (Traditional)", "Traditional Chinese", "zh-TW", "zh-HK"])
    ]

    static func option(for code: String) -> UserMainLanguageOption? {
        let normalized = normalizedCode(for: code)
        return all.first { $0.code == normalized }
    }

    static func sanitizedSelection(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        let sanitized: [String] = codes.compactMap { (code: String) -> String? in
            let normalized = normalizedCode(for: code)
            guard option(for: normalized) != nil, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        return sanitized.isEmpty ? defaultSelectionCodes() : sanitized
    }

    static func storedSelection(from rawValue: String?) -> [String] {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return defaultSelectionCodes()
        }
        return sanitizedSelection(decoded)
    }

    static func storageValue(for codes: [String]) -> String {
        let sanitized = sanitizedSelection(codes)
        guard let data = try? JSONEncoder().encode(sanitized),
              let text = String(data: data, encoding: .utf8)
        else {
            return "[\"\(fallbackCode)\"]"
        }
        return text
    }

    static func defaultSelectionCodes(preferredLanguages: [String] = Locale.preferredLanguages) -> [String] {
        [fallbackOption(preferredLanguages: preferredLanguages).code]
    }

    static var defaultStoredSelectionValue: String {
        storageValue(for: defaultSelectionCodes())
    }

    static func fallbackOption(preferredLanguages: [String] = Locale.preferredLanguages) -> UserMainLanguageOption {
        for identifier in preferredLanguages {
            let normalized = normalizedCode(for: identifier)
            guard !normalized.isEmpty else { continue }
            if let matched = option(for: normalized) {
                return matched
            }
        }
        return option(for: fallbackCode) ?? all[0]
    }

    var isChinese: Bool {
        code == "zh-hans" || code == "zh-hant"
    }

    var isTraditionalChinese: Bool {
        code == "zh-hant"
    }

    var baseLanguageCode: String {
        switch code {
        case "zh-hans", "zh-hant":
            return "zh"
        default:
            return code.split(separator: "-").first.map(String.init) ?? code
        }
    }

    private static func normalizedCode(for rawValue: String) -> String {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return normalized }

        if normalized == "zh" || normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") || normalized.hasPrefix("zh-hans") {
            return "zh-hans"
        }
        if normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") || normalized.hasPrefix("zh-hant") {
            return "zh-hant"
        }

        let baseCode = normalized.split(separator: "-").first.map(String.init) ?? normalized
        if all.contains(where: { $0.code == baseCode }) {
            return baseCode
        }
        return normalized
    }
}

enum TranslationTargetLanguage: String, CaseIterable, Identifiable {
    case english
    case chineseSimplified
    case chineseTraditional
    case japanese
    case korean
    case spanish
    case french
    case german
    case dutch
    case turkish
    case polish
    case ukrainian
    case portuguese
    case italian
    case russian
    case arabic
    case hebrew
    case hindi
    case thai
    case vietnamese
    case indonesian
    case malay

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .chineseTraditional: return "Chinese (Traditional)"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .dutch: return "Dutch"
        case .turkish: return "Turkish"
        case .polish: return "Polish"
        case .ukrainian: return "Ukrainian"
        case .portuguese: return "Portuguese"
        case .italian: return "Italian"
        case .russian: return "Russian"
        case .arabic: return "Arabic"
        case .hebrew: return "Hebrew"
        case .hindi: return "Hindi"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        case .indonesian: return "Indonesian"
        case .malay: return "Malay"
        }
    }

    var title: String { AppLocalization.localizedString(rawTitleKey) }

    private var rawTitleKey: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .chineseTraditional: return "Chinese (Traditional)"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .dutch: return "Dutch"
        case .turkish: return "Turkish"
        case .polish: return "Polish"
        case .ukrainian: return "Ukrainian"
        case .portuguese: return "Portuguese"
        case .italian: return "Italian"
        case .russian: return "Russian"
        case .arabic: return "Arabic"
        case .hebrew: return "Hebrew"
        case .hindi: return "Hindi"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        case .indonesian: return "Indonesian"
        case .malay: return "Malay"
        }
    }

    var instructionName: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "Simplified Chinese"
        case .chineseTraditional: return "Traditional Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .dutch: return "Dutch"
        case .turkish: return "Turkish"
        case .polish: return "Polish"
        case .ukrainian: return "Ukrainian"
        case .portuguese: return "Portuguese"
        case .italian: return "Italian"
        case .russian: return "Russian"
        case .arabic: return "Arabic"
        case .hebrew: return "Hebrew"
        case .hindi: return "Hindi"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        case .indonesian: return "Indonesian"
        case .malay: return "Malay"
        }
    }
}

enum HistoryRetentionPeriod: String, CaseIterable, Identifiable {
    case oneDay
    case sevenDays
    case fifteenDays
    case thirtyDays
    case ninetyDays
    case oneHundredEightyDays
    case forever

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .oneDay:
            return 1
        case .sevenDays:
            return 7
        case .fifteenDays:
            return 15
        case .thirtyDays:
            return 30
        case .ninetyDays:
            return 90
        case .oneHundredEightyDays:
            return 180
        case .forever:
            return nil
        }
    }

    var title: String {
        switch self {
        case .oneDay:
            return AppLocalization.localizedString("1 Day")
        case .sevenDays:
            return AppLocalization.localizedString("7 Days")
        case .fifteenDays:
            return AppLocalization.localizedString("15 Days")
        case .thirtyDays:
            return AppLocalization.localizedString("30 Days")
        case .ninetyDays:
            return AppLocalization.localizedString("90 Days")
        case .oneHundredEightyDays:
            return AppLocalization.localizedString("180 Days")
        case .forever:
            return AppLocalization.localizedString("Forever")
        }
    }
}

enum InteractionSoundPreset: String, CaseIterable, Identifiable {
    case soft
    case glass
    case funk
    case submarine

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .soft: return "Soft (Pop/Tink)"
        case .glass: return "Ping"
        case .funk: return "Morse"
        case .submarine: return "Submarine"
        }
    }

    var title: String { AppLocalization.localizedString(rawTitleKey) }

    private var rawTitleKey: String {
        switch self {
        case .soft: return "Soft (Pop/Tink)"
        case .glass: return "Ping"
        case .funk: return "Morse"
        case .submarine: return "Submarine"
        }
    }
}

enum VoiceEndCommandPreset: String, CaseIterable, Identifiable {
    case over
    case end
    case wanBi
    case haoLe
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .over:
            return "over"
        case .end:
            return "end"
        case .wanBi:
            return "完毕"
        case .haoLe:
            return "好了"
        case .custom:
            return AppLocalization.localizedString("Custom")
        }
    }

    var resolvedCommand: String? {
        switch self {
        case .over:
            return "over"
        case .end:
            return "end"
        case .wanBi:
            return "完毕"
        case .haoLe:
            return "好了"
        case .custom:
            return nil
        }
    }
}

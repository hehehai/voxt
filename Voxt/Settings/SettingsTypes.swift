import SwiftUI

extension Notification.Name {
    static let voxtSettingsSelectTab = Notification.Name("voxt.settings.selectTab")
    static let voxtInterfaceLanguageDidChange = Notification.Name("voxt.interfaceLanguage.didChange")
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case report
    case model
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
        case .report: return "Report"
        case .model: return "Model"
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
        case .report: return "Report"
        case .model: return "Model"
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
        case .hotkey: return "keyboard"
        case .about: return "info.circle"
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

enum TranslationTargetLanguage: String, CaseIterable, Identifiable {
    case english
    case chineseSimplified
    case japanese
    case korean
    case spanish
    case french
    case german

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        }
    }

    var title: String { AppLocalization.localizedString(rawTitleKey) }

    private var rawTitleKey: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        }
    }

    var instructionName: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "Simplified Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
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

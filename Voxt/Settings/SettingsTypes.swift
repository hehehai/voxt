import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case permissions
    case history
    case model
    case hotkey
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .permissions: return String(localized: "Permissions")
        case .history: return String(localized: "History")
        case .model: return String(localized: "Model")
        case .hotkey: return String(localized: "Hotkey")
        case .about: return String(localized: "About")
        }
    }

    var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .permissions: return "lock.shield"
        case .history: return "clock.arrow.circlepath"
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

    var title: String {
        switch self {
        case .system: return String(localized: "System Default")
        case .english: return String(localized: "English")
        case .chineseSimplified: return String(localized: "Chinese (Simplified)")
        case .japanese: return String(localized: "Japanese")
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

    var title: String {
        switch self {
        case .english: return String(localized: "English")
        case .chineseSimplified: return String(localized: "Chinese (Simplified)")
        case .japanese: return String(localized: "Japanese")
        case .korean: return String(localized: "Korean")
        case .spanish: return String(localized: "Spanish")
        case .french: return String(localized: "French")
        case .german: return String(localized: "German")
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

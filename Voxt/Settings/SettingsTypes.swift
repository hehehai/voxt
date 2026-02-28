import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case history
    case model
    case hotkey
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .history: return "History"
        case .model: return "Model"
        case .hotkey: return "Hotkey"
        case .about: return "About"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
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


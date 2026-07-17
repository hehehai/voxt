// OnboardingGuideTypes.swift
// Provides Onboarding Guide Types for onboarding settings.

import SwiftUI

enum OnboardingGuidePhase: String, CaseIterable, Identifiable {
    case basics
    case workflows
    case advanced
    case finish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basics:
            return AppLocalization.localizedString("Basics")
        case .workflows:
            return AppLocalization.localizedString("Workflows")
        case .advanced:
            return AppLocalization.localizedString("Advanced")
        case .finish:
            return AppLocalization.localizedString("Finish")
        }
    }
}

enum OnboardingGuideStep: String, CaseIterable, Identifiable {
    case permissions
    case models
    case transcriptionShortcut
    case transcriptionEnhancement
    case translationShortcut
    case translationSelection
    case rewriteShortcut
    case rewriteSelection
    case appEnhancement
    case meeting
    case finish

    var id: String { rawValue }

    var phase: OnboardingGuidePhase {
        switch self {
        case .permissions, .models:
            return .basics
        case .transcriptionShortcut, .transcriptionEnhancement, .translationShortcut, .translationSelection, .rewriteShortcut, .rewriteSelection:
            return .workflows
        case .appEnhancement, .meeting:
            return .advanced
        case .finish:
            return .finish
        }
    }

    var title: String {
        switch self {
        case .permissions:
            return AppLocalization.localizedString("Get Permissions")
        case .models:
            return AppLocalization.localizedString("Choose Models")
        case .transcriptionShortcut:
            return AppLocalization.localizedString("Transcription Shortcut")
        case .transcriptionEnhancement:
            return AppLocalization.localizedString("Transcription Enhancement")
        case .translationShortcut:
            return AppLocalization.localizedString("Translation Shortcut")
        case .translationSelection:
            return AppLocalization.localizedString("Translate Selected Text")
        case .rewriteShortcut:
            return AppLocalization.localizedString("Rewrite Shortcut")
        case .rewriteSelection:
            return AppLocalization.localizedString("Rewrite Selected Text")
        case .appEnhancement:
            return AppLocalization.localizedString("App Enhancement")
        case .meeting:
            return AppLocalization.localizedString("Meeting")
        case .finish:
            return AppLocalization.localizedString("Ready")
        }
    }

    var subtitle: String {
        switch self {
        case .permissions:
            return AppLocalization.localizedString("Allow Voxt to hear you, read shortcuts, and insert text into active apps.")
        case .models:
            return AppLocalization.localizedString("Pick local models or configure remote providers before testing voice workflows.")
        case .transcriptionShortcut:
            return AppLocalization.localizedString("Press the transcription shortcut in a focused input to confirm the overlay opens.")
        case .transcriptionEnhancement:
            return AppLocalization.localizedString("Try enhanced transcription output in a focused input.")
        case .translationShortcut:
            return AppLocalization.localizedString("Choose a target language and test the translation shortcut.")
        case .translationSelection:
            return AppLocalization.localizedString("Select text in the test area before continuing.")
        case .rewriteShortcut:
            return AppLocalization.localizedString("Use voice rewrite mode to answer or transform text.")
        case .rewriteSelection:
            return AppLocalization.localizedString("Select source text and ask Voxt to rewrite it.")
        case .appEnhancement:
            return AppLocalization.localizedString("Test temporary app-aware instructions while Voxt is focused.")
        case .meeting:
            return AppLocalization.localizedString("Check the meeting shortcut and confirm the audio, summary, and speaker separation setup.")
        case .finish:
            return AppLocalization.localizedString("Review the active shortcuts and start using Voxt.")
        }
    }

    var stepNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    var previous: OnboardingGuideStep? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else { return nil }
        return Self.allCases[index - 1]
    }

    var next: OnboardingGuideStep? {
        guard let index = Self.allCases.firstIndex(of: self), index + 1 < Self.allCases.count else { return nil }
        return Self.allCases[index + 1]
    }

    var sidebarIconKind: SettingsSidebarIconKind {
        switch self {
        case .permissions:
            return .permissions
        case .models:
            return .model
        case .transcriptionShortcut, .transcriptionEnhancement:
            return .transcription
        case .translationShortcut, .translationSelection:
            return .translation
        case .rewriteShortcut, .rewriteSelection:
            return .rewrite
        case .appEnhancement:
            return .appEnhancement
        case .meeting:
            return .meeting
        case .finish:
            return .home
        }
    }
}

enum OnboardingGuideModelFocus {
    case local
    case remote
}

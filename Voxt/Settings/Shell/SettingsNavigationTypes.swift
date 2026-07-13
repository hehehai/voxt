// SettingsNavigationTypes.swift
// Provides Settings Navigation Types for settings shell.

import SwiftUI

enum SettingsNavigationSection: String, Hashable {
    case generalAudio
    case generalTranscriptionUI
    case generalLanguages
    case generalLogging
    case generalAppBehavior
    case generalAdvanced
    case generalProxy
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
        case .generalAudio,
             .generalTranscriptionUI,
             .generalLanguages,
             .generalLogging,
             .generalAppBehavior,
             .generalAdvanced,
             .generalProxy:
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
        case .generalAudio: return "Audio"
        case .generalTranscriptionUI: return "Floating Window Style"
        case .generalLanguages: return "Languages"
        case .generalLogging: return "Logging"
        case .generalAppBehavior: return "App Behavior"
        case .generalAdvanced: return "Advanced"
        case .generalProxy: return "Proxy"
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
    let historyFilter: HistoryFilterTab?
    let modelSelectionID: FeatureModelSelectionID?

    init(
        tab: SettingsTab,
        section: SettingsNavigationSection? = nil,
        featureTab: FeatureSettingsTab? = nil,
        historyFilter: HistoryFilterTab? = nil,
        modelSelectionID: FeatureModelSelectionID? = nil
    ) {
        self.tab = tab
        self.section = section
        self.featureTab = featureTab ?? Self.defaultFeatureTab(for: tab, section: section)
        self.historyFilter = historyFilter
        self.modelSelectionID = modelSelectionID
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

        let historyFilter: HistoryFilterTab?
        if let rawHistoryFilter = notification.userInfo?["historyFilter"] as? String,
           !rawHistoryFilter.isEmpty {
            historyFilter = HistoryFilterTab(rawValue: rawHistoryFilter)
        } else {
            historyFilter = nil
        }

        let modelSelectionID: FeatureModelSelectionID?
        if let rawModelSelectionID = notification.userInfo?["modelSelectionID"] as? String,
           !rawModelSelectionID.isEmpty {
            modelSelectionID = FeatureModelSelectionID(rawValue: rawModelSelectionID)
        } else {
            modelSelectionID = nil
        }

        self.init(
            tab: tab == .appEnhancement ? .feature : tab,
            section: section,
            featureTab: featureTab,
            historyFilter: historyFilter,
            modelSelectionID: modelSelectionID
        )
    }

    var userInfo: [String: String] {
        [
            "tab": tab.rawValue,
            "section": section?.rawValue ?? "",
            "featureTab": featureTab?.rawValue ?? "",
            "historyFilter": historyFilter?.rawValue ?? "",
            "modelSelectionID": modelSelectionID?.rawValue ?? ""
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
        case .report: return "Home"
        case .model: return "Model"
        case .feature: return "Custom"
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
        case .report: return "Home"
        case .model: return "Model"
        case .feature: return "Custom"
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
        case .report: return "house"
        case .model: return "waveform"
        case .feature: return "square.grid.2x2"
        case .dictionary: return "book.closed"
        case .appEnhancement: return "sparkles.rectangle.stack"
        case .hotkey: return "keyboard"
        case .about: return "info.circle"
        }
    }

    static func visibleTabs(appEnhancementEnabled: Bool) -> [SettingsTab] {
        [
            .report,
            .feature,
            .dictionary,
            .history
        ]
    }

    static var settingsTabs: [SettingsTab] {
        [
            .general,
            .model,
            .permissions,
            .hotkey,
            .about
        ]
    }
}

enum SettingsSidebarMode: Equatable {
    case root
    case feature
    case history
    case settings
}

enum FeatureSettingsTab: String, CaseIterable, Identifiable {
    case transcription
    case translation
    case rewrite
    case appEnhancement
    case note
    case meeting

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .transcription: return "Transcription"
        case .meeting: return "Meeting"
        case .note: return "Notes"
        case .translation: return "Translation"
        case .rewrite: return "Rewrite"
        case .appEnhancement: return "App Enhancement"
        }
    }

    var title: String {
        AppLocalization.localizedString(rawTitleKey)
    }

    private var rawTitleKey: String {
        switch self {
        case .transcription: return "Transcription"
        case .meeting: return "Meeting"
        case .note: return "Notes"
        case .translation: return "Translation"
        case .rewrite: return "Rewrite"
        case .appEnhancement: return "App Enhancement"
        }
    }

    var iconName: String {
        switch self {
        case .transcription: return "waveform.and.mic"
        case .meeting: return "person.2.wave.2"
        case .note: return "note.text"
        case .translation: return "globe"
        case .rewrite: return "text.badge.star"
        case .appEnhancement: return "sparkles.rectangle.stack"
        }
    }

    static func visibleTabs(appEnhancementEnabled: Bool, noteEnabled: Bool) -> [FeatureSettingsTab] {
        allCases.filter { tab in
            switch tab {
            case .note:
                return true
            case .appEnhancement:
                return appEnhancementEnabled
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

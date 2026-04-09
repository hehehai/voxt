import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices
import Combine

private func settingsLocalized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct SettingsView: View {
    let availableDictionaryHistoryScanModels: () -> [DictionaryHistoryScanModelOption]
    let onIngestDictionarySuggestionsFromHistory: (DictionaryHistoryScanRequest, Bool) -> Void
    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var whisperModelManager: WhisperKitModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager
    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    @ObservedObject var appUpdateManager: AppUpdateManager
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.appEnhancementEnabled) private var appEnhancementEnabled = false
    @AppStorage(AppPreferenceKey.muteSystemAudioWhileRecording) private var muteSystemAudioWhileRecording = false
    @AppStorage(AppPreferenceKey.transcriptionEngine) private var transcriptionEngineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.featureSettings) private var featureSettingsRaw = ""
    @State private var selectedTab: SettingsTab
    @State private var selectedFeatureTab: FeatureSettingsTab
    @State private var sidebarMode: SettingsSidebarMode
    @State private var navigationRequest: SettingsNavigationRequest?
    @State private var hasMissingPermissions = false
    @State private var hasNoAvailableMicrophones = false
    @State private var missingModelConfigurationIssues: [ConfigurationTransferManager.MissingConfigurationIssue] = []
    @State private var languageRefreshToken = UUID()
    @State private var displayMode: SettingsDisplayMode
    private let issueRefreshTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    init(
        availableDictionaryHistoryScanModels: @escaping () -> [DictionaryHistoryScanModelOption],
        onIngestDictionarySuggestionsFromHistory: @escaping (DictionaryHistoryScanRequest, Bool) -> Void,
        mlxModelManager: MLXModelManager,
        whisperModelManager: WhisperKitModelManager,
        customLLMManager: CustomLLMModelManager,
        historyStore: TranscriptionHistoryStore,
        dictionaryStore: DictionaryStore,
        dictionarySuggestionStore: DictionarySuggestionStore,
        appUpdateManager: AppUpdateManager,
        initialNavigationTarget: SettingsNavigationTarget = SettingsNavigationTarget(tab: .report),
        initialDisplayMode: SettingsDisplayMode = .normal
    ) {
        self.availableDictionaryHistoryScanModels = availableDictionaryHistoryScanModels
        self.onIngestDictionarySuggestionsFromHistory = onIngestDictionarySuggestionsFromHistory
        self.mlxModelManager = mlxModelManager
        self.whisperModelManager = whisperModelManager
        self.customLLMManager = customLLMManager
        self.historyStore = historyStore
        self.dictionaryStore = dictionaryStore
        self.dictionarySuggestionStore = dictionarySuggestionStore
        self.appUpdateManager = appUpdateManager
        _selectedTab = State(initialValue: initialNavigationTarget.tab)
        _selectedFeatureTab = State(initialValue: initialNavigationTarget.featureTab ?? .transcription)
        _sidebarMode = State(initialValue: initialNavigationTarget.tab == .feature ? .feature : .root)
        _navigationRequest = State(initialValue: SettingsNavigationRequest(target: initialNavigationTarget))
        _displayMode = State(initialValue: initialDisplayMode)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SettingsUIStyle.windowCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsUIStyle.windowCornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )

            Group {
                switch displayMode {
                case .normal:
                    normalSettingsContent
                case .onboarding:
                    onboardingContent
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .padding(.top, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: SettingsUIStyle.windowCornerRadius, style: .continuous))
        .frame(minWidth: 760, minHeight: 560)
        .environment(\.locale, interfaceLanguage.locale)
        .groupBoxStyle(SettingsPanelGroupBoxStyle())
        .id(languageRefreshToken)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            refreshPermissionBadge()
            refreshMicrophoneBadge()
            refreshModelConfigurationBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionBadge()
            refreshMicrophoneBadge()
            refreshModelConfigurationBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtAudioInputDevicesDidChange)) { _ in
            refreshMicrophoneBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtSettingsSelectTab)) { notification in
            guard case .normal = displayMode else { return }
            guard let target = SettingsNavigationTarget(notification: notification)
            else {
                return
            }
            applyNavigationTarget(target)
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtSettingsNavigate)) { notification in
            guard case .normal = displayMode else { return }
            guard let target = SettingsNavigationTarget(notification: notification) else { return }
            applyNavigationTarget(target)
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtInterfaceLanguageDidChange)) { _ in
            languageRefreshToken = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtConfigurationDidImport)) { _ in
            refreshPermissionBadge()
            refreshModelConfigurationBadge()
            dictionaryStore.reload()
            dictionarySuggestionStore.reload()
        }
        .onReceive(issueRefreshTimer) { _ in
            refreshModelConfigurationBadge()
        }
        .onChange(of: appEnhancementEnabled) { _, isEnabled in
            if !isEnabled, selectedTab == .feature, selectedFeatureTab == .appEnhancement {
                navigationRequest = nil
                selectedFeatureTab = .rewrite
            }
        }
        .onChange(of: muteSystemAudioWhileRecording) { _, _ in
            refreshPermissionBadge()
        }
        .onChange(of: transcriptionEngineRaw) { _, _ in
            refreshPermissionBadge()
        }
        .onChange(of: featureSettingsRaw) { _, _ in
            refreshPermissionBadge()
            refreshModelConfigurationBadge()
            if !meetingEnabled, selectedTab == .feature, selectedFeatureTab == .meeting {
                navigationRequest = nil
                selectedFeatureTab = .transcription
            }
        }
    }

    private var normalSettingsContent: some View {
        HStack(alignment: .top, spacing: 8) {
            SettingsSidebar(
                sidebarMode: $sidebarMode,
                selectedTab: $selectedTab,
                selectedFeatureTab: $selectedFeatureTab,
                onSelectTab: { tab in
                    navigationRequest = nil
                    switchToRootTab(tab)
                },
                onSelectFeatureTab: { tab in
                    navigationRequest = nil
                    switchToFeatureTab(tab)
                },
                onReturnToRoot: {
                    navigationRequest = nil
                    sidebarMode = .root
                    if selectedTab == .feature {
                        selectedTab = .report
                    }
                },
                appEnhancementEnabled: appEnhancementEnabled,
                meetingEnabled: meetingEnabled,
                hasMissingPermissions: hasMissingPermissions,
                hasNoAvailableMicrophones: hasNoAvailableMicrophones,
                hasMissingModelConfigurationIssues: !missingModelConfigurationIssues.isEmpty,
                updateBadgeState: updateBadgeState,
                onTapPermissionBadge: {
                    navigationRequest = nil
                    selectedTab = .permissions
                },
                onTapMicrophoneBadge: {
                    selectedTab = .general
                    navigationRequest = SettingsNavigationRequest(
                        target: SettingsNavigationTarget(tab: .general, section: .generalAudio)
                    )
                },
                onTapModelBadge: {
                    navigationRequest = nil
                    selectedTab = .model
                },
                onTapUpdateBadge: {
                    appUpdateManager.checkForUpdatesWithUserInterface()
                }
            )
            .frame(width: 170)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text(currentTitle)
                        .font(.title3.weight(.semibold))

                    Spacer(minLength: 0)

                    if sidebarMode == .root, selectedTab == .report {
                        Button(settingsLocalized("Guide")) {
                            enterOnboarding(step: .language)
                        }
                        .buttonStyle(SettingsPillButtonStyle())
                    }
                }
                .padding(.horizontal, 8)

                tabContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var onboardingContent: some View {
        OnboardingSettingsView(
            currentStep: onboardingStepBinding,
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager,
            customLLMManager: customLLMManager,
            appUpdateManager: appUpdateManager,
            onExit: exitOnboarding,
            onFinish: finishOnboarding
        )
    }

    private var interfaceLanguage: AppInterfaceLanguage {
        AppInterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .system
    }

    private var featureSettings: FeatureSettings {
        FeatureSettingsStore.load(defaults: .standard)
    }

    private var meetingEnabled: Bool {
        featureSettings.meeting.enabled
    }

    private var onboardingStepBinding: Binding<OnboardingStep> {
        Binding(
            get: {
                if case .onboarding(let step) = displayMode {
                    return step
                }
                return .language
            },
            set: { newStep in
                displayMode = .onboarding(step: newStep)
            }
        )
    }

    private var updateBadgeState: UpdateBadgeState {
        if let issue = appUpdateManager.updateCheckIssueMessage,
           !issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .checkFailed(issue)
        }
        if appUpdateManager.hasUpdate {
            return .newVersion(appUpdateManager.latestVersion)
        }
        return .none
    }

    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == .history || selectedTab == .report || selectedTab == .feature || selectedTab == .dictionary || selectedTab == .model {
            staticTabContent
        } else {
            scrollableTabContent
        }
    }

    @ViewBuilder
    private var staticTabContent: some View {
        Group {
            if selectedTab == .history {
                HistorySettingsView(
                    historyStore: historyStore,
                    dictionaryStore: dictionaryStore,
                    dictionarySuggestionStore: dictionarySuggestionStore,
                    navigationRequest: navigationRequest
                )
            } else if selectedTab == .dictionary {
                DictionarySettingsView(
                    historyStore: historyStore,
                    dictionaryStore: dictionaryStore,
                    dictionarySuggestionStore: dictionarySuggestionStore,
                    availableHistoryScanModels: availableDictionaryHistoryScanModels,
                    onIngestSuggestionsFromHistory: onIngestDictionarySuggestionsFromHistory,
                    navigationRequest: navigationRequest
                )
            } else if selectedTab == .feature {
                FeatureSettingsView(
                    selectedTab: selectedFeatureTab,
                    navigationRequest: navigationRequest,
                    mlxModelManager: mlxModelManager,
                    whisperModelManager: whisperModelManager,
                    customLLMManager: customLLMManager
                )
            } else if selectedTab == .model {
                ModelSettingsView(
                    mlxModelManager: mlxModelManager,
                    whisperModelManager: whisperModelManager,
                    customLLMManager: customLLMManager,
                    missingConfigurationIssues: missingModelConfigurationIssues,
                    navigationRequest: navigationRequest
                )
            } else {
                ReportSettingsView(historyStore: historyStore)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    private var scrollableTabContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView(
                            appUpdateManager: appUpdateManager,
                            navigationRequest: navigationRequest,
                            onOpenSetupGuide: {
                                enterOnboarding(step: .language)
                            }
                        )
                    case .permissions:
                        PermissionsSettingsView(navigationRequest: navigationRequest)
                    case .report:
                        EmptyView()
                    case .model:
                        ModelSettingsView(
                            mlxModelManager: mlxModelManager,
                            whisperModelManager: whisperModelManager,
                            customLLMManager: customLLMManager,
                            missingConfigurationIssues: missingModelConfigurationIssues,
                            navigationRequest: navigationRequest
                        )
                    case .dictionary:
                        EmptyView()
                    case .feature:
                        EmptyView()
                    case .appEnhancement:
                        EmptyView()
                    case .hotkey:
                        HotkeySettingsView()
                    case .about:
                        AboutSettingsView(
                            appUpdateManager: appUpdateManager,
                            navigationRequest: navigationRequest
                        )
                    case .history:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 8)
                .padding(.top, 2)
            }
            .onAppear {
                scrollScrollableContentIfNeeded(with: navigationRequest, proxy: proxy)
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                scrollScrollableContentIfNeeded(with: navigationRequest, proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func scrollScrollableContentIfNeeded(with request: SettingsNavigationRequest?, proxy: ScrollViewProxy) {
        guard let request,
              request.target.tab == selectedTab,
              let section = request.target.section
        else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(section.rawValue, anchor: .top)
            }
        }
    }

    private func refreshPermissionBadge() {
        let engine = TranscriptionEngine(rawValue: transcriptionEngineRaw) ?? .mlxAudio
        let context = SettingsPermissionRequirementContext(
            selectedEngine: engine,
            muteSystemAudioWhileRecording: muteSystemAudioWhileRecording,
            meetingNotesEnabled: true,
            featureSettings: FeatureSettingsStore.load(defaults: .standard)
        )

        hasMissingPermissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)
            .contains { !SettingsPermissionGrantResolver.isGranted($0) }
    }

    private func refreshModelConfigurationBadge() {
        missingModelConfigurationIssues = ConfigurationTransferManager.missingConfigurationIssues(
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager,
            customLLMManager: customLLMManager
        )
    }

    private func refreshMicrophoneBadge() {
        hasNoAvailableMicrophones = AudioInputDeviceManager.availableInputDevices().isEmpty
    }

    private func enterOnboarding(step: OnboardingStep) {
        OnboardingPreferenceManager.saveLastStep(step)
        displayMode = .onboarding(step: step)
    }

    private func exitOnboarding() {
        OnboardingPreferenceManager.markCompleted()
        navigationRequest = nil
        selectedTab = .report
        displayMode = .normal
    }

    private func finishOnboarding() {
        OnboardingPreferenceManager.markCompleted()
        navigationRequest = nil
        selectedTab = .report
        displayMode = .normal
    }

    private var currentTitle: LocalizedStringKey {
        sidebarMode == .feature ? selectedFeatureTab.titleKey : selectedTab.titleKey
    }

    private func applyNavigationTarget(_ target: SettingsNavigationTarget) {
        navigationRequest = SettingsNavigationRequest(target: target)
        if let featureTab = target.featureTab {
            if FeatureSettingsTab.visibleTabs(appEnhancementEnabled: appEnhancementEnabled, meetingEnabled: meetingEnabled).contains(featureTab) {
                selectedFeatureTab = featureTab
            } else {
                selectedFeatureTab = .transcription
            }
        }
        if target.tab == .feature {
            sidebarMode = .feature
            selectedTab = .feature
        } else {
            sidebarMode = .root
            selectedTab = target.tab
        }
    }

    private func switchToRootTab(_ tab: SettingsTab) {
        if tab == .feature {
            selectedTab = .feature
            sidebarMode = .feature
            if !FeatureSettingsTab.visibleTabs(appEnhancementEnabled: appEnhancementEnabled, meetingEnabled: meetingEnabled).contains(selectedFeatureTab) {
                selectedFeatureTab = .transcription
            }
            return
        }
        sidebarMode = .root
        selectedTab = tab
    }

    private func switchToFeatureTab(_ tab: FeatureSettingsTab) {
        selectedTab = .feature
        sidebarMode = .feature
        selectedFeatureTab = tab
    }

}

private struct SettingsSidebar: View {
    @Binding var sidebarMode: SettingsSidebarMode
    @Binding var selectedTab: SettingsTab
    @Binding var selectedFeatureTab: FeatureSettingsTab
    let onSelectTab: (SettingsTab) -> Void
    let onSelectFeatureTab: (FeatureSettingsTab) -> Void
    let onReturnToRoot: () -> Void
    let appEnhancementEnabled: Bool
    let meetingEnabled: Bool
    let hasMissingPermissions: Bool
    let hasNoAvailableMicrophones: Bool
    let hasMissingModelConfigurationIssues: Bool
    let updateBadgeState: UpdateBadgeState
    let onTapPermissionBadge: () -> Void
    let onTapMicrophoneBadge: () -> Void
    let onTapModelBadge: () -> Void
    let onTapUpdateBadge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sidebarMode == .root {
                ForEach(visibleTabs) { tab in
                    Button {
                        onSelectTab(tab)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 16)
                            Text(tab.titleKey)
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsSidebarItemButtonStyle(isActive: tab == selectedTab))
                }
            } else {
                ForEach(visibleFeatureTabs) { tab in
                    Button {
                        onSelectFeatureTab(tab)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 16)
                            Text(tab.titleKey)
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsSidebarItemButtonStyle(isActive: tab == selectedFeatureTab))
                }
            }

            Spacer(minLength: 8)

            if sidebarMode == .root, hasMissingPermissions {
                Button(action: onTapPermissionBadge) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                        Text(settingsLocalized("Permissions Disabled"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(SettingsStatusButtonStyle(tint: .red))
            }

            if sidebarMode == .root, hasNoAvailableMicrophones {
                Button(action: onTapMicrophoneBadge) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                        Text(settingsLocalized("No Microphone Available"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(SettingsStatusButtonStyle(tint: .red))
            }

            if sidebarMode == .root, hasMissingModelConfigurationIssues {
                Button(action: onTapModelBadge) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(settingsLocalized("Model Setup Required"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(SettingsStatusButtonStyle(tint: .orange))
            }

            if sidebarMode == .root, updateBadgeState != .none {
                Button(action: onTapUpdateBadge) {
                    HStack(spacing: 8) {
                        Image(systemName: updateBadgeState.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(updateBadgeState.tintColor)
                        Text(updateBadgeState.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(updateBadgeState.tintColor)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(SettingsStatusButtonStyle(tint: updateBadgeState.tintColor))
            }

            if sidebarMode == .feature {
                Button(action: onReturnToRoot) {
                    Label(settingsLocalized("Back"), systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SettingsPillButtonStyle())
            }

        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .settingsSidebarSurface()
    }

    private var visibleTabs: [SettingsTab] {
        SettingsTab.visibleTabs(appEnhancementEnabled: appEnhancementEnabled)
    }

    private var visibleFeatureTabs: [FeatureSettingsTab] {
        FeatureSettingsTab.visibleTabs(appEnhancementEnabled: appEnhancementEnabled, meetingEnabled: meetingEnabled)
    }
}

private enum UpdateBadgeState: Equatable {
    case none
    case checkFailed(String)
    case newVersion(String?)

    var iconName: String {
        switch self {
        case .none:
            return "arrow.down.circle.fill"
        case .checkFailed:
            return "exclamationmark.triangle.fill"
        case .newVersion:
            return "arrow.down.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .none:
            return .clear
        case .checkFailed:
            return .orange
        case .newVersion:
            return .green
        }
    }

    var title: String {
        switch self {
        case .none:
            return settingsLocalized("New Version Available")
        case .checkFailed:
            return settingsLocalized("Update Check Failed")
        case .newVersion:
            return settingsLocalized("New Version Available")
        }
    }
}

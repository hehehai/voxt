// SettingsView.swift
// Provides Settings View for settings shell.

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
    let onCancelDictionarySuggestionsFromHistory: () -> Void
    let mlxModelManager: MLXModelManager
    let whisperModelManager: WhisperKitModelManager
    let customLLMManager: CustomLLMModelManager
    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var noteStore: VoxtNoteStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    @ObservedObject var appUpdateManager: AppUpdateManager
    @ObservedObject var mainWindowState: MainWindowVisibilityState
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.appEnhancementEnabled) private var appEnhancementEnabled = true
    @AppStorage(AppPreferenceKey.muteSystemAudioWhileRecording) private var muteSystemAudioWhileRecording = false
    @AppStorage(AppPreferenceKey.transcriptionEngine) private var transcriptionEngineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.featureSettings) private var featureSettingsRaw = ""
    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) private var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) private var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.hotkeyInputType) private var hotkeyInputType = HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
    @AppStorage(AppPreferenceKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyPreference.defaultKeyCode)
    @AppStorage(AppPreferenceKey.hotkeyMouseButtonNumber) private var hotkeyMouseButtonNumber = HotkeyPreference.middleMouseButtonNumber
    @AppStorage(AppPreferenceKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyPreference.defaultModifiers.rawValue)
    @AppStorage(AppPreferenceKey.hotkeySidedModifiers) private var hotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.hotkeyDistinguishModifierSides) private var hotkeyDistinguishModifierSides = HotkeyPreference.defaultDistinguishModifierSides
    @AppStorage(AppPreferenceKey.hotkeyPreset) private var hotkeyPreset = HotkeyPreference.defaultPreset.rawValue
    @State private var selectedTab: SettingsTab
    @State private var selectedFeatureTab: FeatureSettingsTab
    @State private var sidebarMode: SettingsSidebarMode
    @State private var navigationRequest: SettingsNavigationRequest?
    @State private var hasMissingPermissions = false
    @State private var hasNoAvailableMicrophones = false
    @State private var missingModelConfigurationIssues: [ConfigurationTransferManager.MissingConfigurationIssue] = []
    @State private var languageRefreshToken = UUID()
    @State private var displayMode: SettingsDisplayMode
    @State private var initializedStaticTabs: Set<SettingsTab>
    @State private var activeModelDownloadCount = 0
    @State private var isFeedbackDialogPresented = false

    private static let officialWebsiteURL = URL(string: "https://voxt.actnow.dev")!
    private static let changelogURL = URL(string: "https://voxt.actnow.dev/changelog")!
    private static let feedbackURL = URL(string: "https://github.com/hehehai/voxt/issues/new/choose")!
    private static let scrollBottomAnchorID = "settings-scroll-bottom-anchor"

    init(
        availableDictionaryHistoryScanModels: @escaping () -> [DictionaryHistoryScanModelOption],
        onIngestDictionarySuggestionsFromHistory: @escaping (DictionaryHistoryScanRequest, Bool) -> Void,
        onCancelDictionarySuggestionsFromHistory: @escaping () -> Void,
        mlxModelManager: MLXModelManager,
        whisperModelManager: WhisperKitModelManager,
        customLLMManager: CustomLLMModelManager,
        historyStore: TranscriptionHistoryStore,
        noteStore: VoxtNoteStore,
        dictionaryStore: DictionaryStore,
        dictionarySuggestionStore: DictionarySuggestionStore,
        appUpdateManager: AppUpdateManager,
        mainWindowState: MainWindowVisibilityState,
        initialNavigationTarget: SettingsNavigationTarget = SettingsNavigationTarget(tab: .report),
        initialDisplayMode: SettingsDisplayMode = .normal
    ) {
        self.availableDictionaryHistoryScanModels = availableDictionaryHistoryScanModels
        self.onIngestDictionarySuggestionsFromHistory = onIngestDictionarySuggestionsFromHistory
        self.onCancelDictionarySuggestionsFromHistory = onCancelDictionarySuggestionsFromHistory
        self.mlxModelManager = mlxModelManager
        self.whisperModelManager = whisperModelManager
        self.customLLMManager = customLLMManager
        self.historyStore = historyStore
        self.noteStore = noteStore
        self.dictionaryStore = dictionaryStore
        self.dictionarySuggestionStore = dictionarySuggestionStore
        self.appUpdateManager = appUpdateManager
        self.mainWindowState = mainWindowState
        _selectedTab = State(initialValue: initialNavigationTarget.tab)
        _selectedFeatureTab = State(initialValue: initialNavigationTarget.featureTab ?? .transcription)
        _sidebarMode = State(initialValue: Self.initialSidebarMode(for: initialNavigationTarget.tab))
        _navigationRequest = State(initialValue: SettingsNavigationRequest(target: initialNavigationTarget))
        _displayMode = State(initialValue: initialDisplayMode)
        _initializedStaticTabs = State(initialValue: Self.initializedStaticTabs(for: initialNavigationTarget.tab))
        _activeModelDownloadCount = State(
            initialValue: SettingsModelDownloadBadgeSupport.activeDownloadCount(
                mlxActiveDownloadRepos: mlxModelManager.activeDownloadRepos,
                whisperActiveDownload: whisperModelManager.activeDownload,
                customLLMState: customLLMManager.state
            )
        )
    }

    var body: some View {
        ZStack {
            SettingsUIStyle.windowBackgroundColor
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
        .frame(minWidth: 820, minHeight: 560)
        .environment(\.locale, interfaceLanguage.locale)
        .groupBoxStyle(SettingsPanelGroupBoxStyle())
        .id(languageRefreshToken)
        .sheet(isPresented: $isFeedbackDialogPresented) {
            FeedbackDialogView(
                onClose: {
                    isFeedbackDialogPresented = false
                },
                onOpenFeedback: {
                    isFeedbackDialogPresented = false
                    openFeedbackPage()
                }
            )
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            refreshPermissionBadge()
            refreshMicrophoneBadge()
            refreshModelConfigurationBadge()
        }
        .onReceive(modelDownloadBadgeCountPublisher) { count in
            let previousCount = activeModelDownloadCount
            activeModelDownloadCount = count
            if previousCount != count {
                refreshModelConfigurationBadge()
            }
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
            AppLocalization.refreshLanguageCache()
            languageRefreshToken = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtRemoteProviderConfigurationsDidChange)) { _ in
            refreshModelConfigurationBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtPermissionsDidChange)) { _ in
            refreshPermissionBadge()
        }
        .onChange(of: mainWindowState.isVisible) { _, isVisible in
            guard isVisible else { return }
            refreshPermissionBadge()
            refreshMicrophoneBadge()
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
            if !noteEnabled, selectedTab == .feature, selectedFeatureTab == .note {
                navigationRequest = nil
                selectedFeatureTab = .transcription
            }
        }
        .onChange(of: remoteASRProviderConfigurationsRaw) { _, _ in
            refreshModelConfigurationBadge()
        }
        .onChange(of: remoteLLMProviderConfigurationsRaw) { _, _ in
            refreshModelConfigurationBadge()
        }
        .onChange(of: selectedTab) { _, tab in
            if Self.isStaticTab(tab) {
                initializedStaticTabs.insert(tab)
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
                    if selectedTab == .feature || Self.isSettingsTab(selectedTab) {
                        selectedTab = .report
                    }
                },
                appEnhancementEnabled: appEnhancementEnabled,
                noteEnabled: noteEnabled,
                hasMissingPermissions: hasMissingPermissions,
                hasNoAvailableMicrophones: hasNoAvailableMicrophones,
                activeModelDownloadCount: activeModelDownloadCount,
                hasMissingModelConfigurationIssues: !missingModelConfigurationIssues.isEmpty,
                updateBadgeState: updateBadgeState,
                onTapPermissionBadge: {
                    navigationRequest = nil
                    sidebarMode = .settings
                    selectedTab = .permissions
                },
                onTapMicrophoneBadge: {
                    sidebarMode = .settings
                    selectedTab = .general
                    navigationRequest = SettingsNavigationRequest(
                        target: SettingsNavigationTarget(tab: .general, section: .generalAudio)
                    )
                },
                onTapModelBadge: {
                    navigationRequest = nil
                    sidebarMode = .settings
                    selectedTab = .model
                },
                onTapUpdateBadge: {
                    appUpdateManager.checkForUpdatesWithUserInterface()
                },
                onTapWebsite: {
                    openOfficialWebsite()
                },
                onTapFeedback: {
                    isFeedbackDialogPresented = true
                },
                onTapSettings: {
                    navigationRequest = nil
                    if sidebarMode == .settings {
                        sidebarMode = .root
                        if Self.isSettingsTab(selectedTab) {
                            selectedTab = .report
                        }
                    } else {
                        sidebarMode = .settings
                        selectedTab = .general
                    }
                }
            )
            .frame(width: SettingsUIStyle.sidebarWidth)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 0) {
                if showsContentHeader {
                    HStack(alignment: selectedTab == .report && sidebarMode == .root ? .top : .center, spacing: 12) {
                        if sidebarMode == .root, selectedTab == .report {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(settingsLocalized("Speak clearly. Adapt to context."))
                                    .font(.system(size: 18, weight: .bold))
                                    .lineLimit(1)
                                HomeShortcutPrompt(shortcut: currentTranscriptionHotkeyDisplayString)
                            }
                        } else {
                            Text(currentTitle)
                                .font(.title3.weight(.semibold))
                        }

                        Spacer(minLength: 0)

                        if sidebarMode == .root, selectedTab == .report {
                            Button(settingsLocalized("Guide")) {
                                AppDelegate.shared?.openOnboardingWindow()
                            }
                            .buttonStyle(SettingsPillButtonStyle())
                        }
                    }
                }

                tabContent
                    .padding(.top, contentTopPadding)

                if selectedTab == .report && sidebarMode == .root {
                    HStack {
                        Spacer(minLength: 0)

                        Button(settingsLocalized("Changelog")) {
                            openChangelog()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                    .fill(SettingsUIStyle.panelFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                    .strokeBorder(SettingsUIStyle.panelBorderColor, lineWidth: 1)
            )
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

    private var currentTranscriptionHotkeyDisplayString: String {
        _ = hotkeyInputType
        _ = hotkeyKeyCode
        _ = hotkeyMouseButtonNumber
        _ = hotkeyModifiers
        _ = hotkeySidedModifiers
        _ = hotkeyDistinguishModifierSides
        _ = hotkeyPreset

        return HotkeyPreference.displayString(
            for: HotkeyPreference.load(),
            distinguishModifierSides: HotkeyPreference.loadDistinguishModifierSides()
        )
        .replacingOccurrences(of: "fn", with: "FN")
    }

    private var noteEnabled: Bool {
        featureSettings.transcription.notes.enabled
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
        if appUpdateManager.isPreparingInteractiveUpdateUI {
            return .openingWindow(appUpdateManager.latestVersion)
        }
        if let issue = appUpdateManager.updateCheckIssueMessage,
           !issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .checkFailed(issue)
        }
        if appUpdateManager.hasUpdate {
            return .newVersion(appUpdateManager.latestVersion)
        }
        return .none
    }

    private var modelDownloadBadgeCountPublisher: AnyPublisher<Int, Never> {
        Publishers.CombineLatest3(
            mlxModelManager.$activeDownloadRepos,
            whisperModelManager.$activeDownload,
            customLLMManager.$state
        )
        .map { mlxActiveDownloadRepos, whisperActiveDownload, customLLMState in
            SettingsModelDownloadBadgeSupport.activeDownloadCount(
                mlxActiveDownloadRepos: mlxActiveDownloadRepos,
                whisperActiveDownload: whisperActiveDownload,
                customLLMState: customLLMState
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
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
        ZStack(alignment: .topLeading) {
            if initializedStaticTabs.contains(.report) {
                staticTabLayer(for: .report) {
                    ReportSettingsView(
                        historyStore: historyStore,
                        dictionaryStore: dictionaryStore,
                        mainWindowState: mainWindowState,
                        isActive: selectedTab == .report && sidebarMode == .root
                    )
                }
            }

            if initializedStaticTabs.contains(.history) {
                staticTabLayer(for: .history) {
                    HistorySettingsView(
                        historyStore: historyStore,
                        noteStore: noteStore,
                        dictionaryStore: dictionaryStore,
                        dictionarySuggestionStore: dictionarySuggestionStore,
                        navigationRequest: navigationRequest
                    )
                }
            }

            if initializedStaticTabs.contains(.dictionary) {
                staticTabLayer(for: .dictionary) {
                    DictionarySettingsView(
                        historyStore: historyStore,
                        dictionaryStore: dictionaryStore,
                        dictionarySuggestionStore: dictionarySuggestionStore,
                        availableHistoryScanModels: availableDictionaryHistoryScanModels,
                        onIngestSuggestionsFromHistory: onIngestDictionarySuggestionsFromHistory,
                        onCancelIngestSuggestionsFromHistory: onCancelDictionarySuggestionsFromHistory,
                        navigationRequest: navigationRequest
                    )
                }
            }

            if initializedStaticTabs.contains(.feature) {
                staticTabLayer(for: .feature) {
                    FeatureSettingsView(
                        selectedTab: selectedFeatureTab,
                        navigationRequest: navigationRequest,
                        mlxModelManager: mlxModelManager,
                        whisperModelManager: whisperModelManager,
                        customLLMManager: customLLMManager
                    )
                }
            }

            if initializedStaticTabs.contains(.model) {
                staticTabLayer(for: .model) {
                    ModelSettingsView(
                        mlxModelManager: mlxModelManager,
                        whisperModelManager: whisperModelManager,
                        customLLMManager: customLLMManager,
                        mainWindowState: mainWindowState,
                        missingConfigurationIssues: missingModelConfigurationIssues,
                        navigationRequest: navigationRequest,
                        isActive: selectedTab == .model
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func staticTabLayer<Content: View>(
        for tab: SettingsTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }

    private var scrollableTabContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        switch selectedTab {
                        case .general:
                            GeneralSettingsView(
                                appUpdateManager: appUpdateManager,
                                navigationRequest: navigationRequest,
                                onRequestScrollToBottom: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        proxy.scrollTo(Self.scrollBottomAnchorID, anchor: .bottom)
                                    }
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
                                mainWindowState: mainWindowState,
                                missingConfigurationIssues: missingModelConfigurationIssues,
                                navigationRequest: navigationRequest,
                                isActive: true
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
                    .padding(.trailing, SettingsUIStyle.contentScrollTrailingGutter)

                    Color.clear
                        .frame(height: 1)
                        .id(Self.scrollBottomAnchorID)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.trailing, -SettingsUIStyle.contentScrollIndicatorOutset)
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
        let featureSettings = FeatureSettingsStore.load(defaults: .standard)
        let context = SettingsPermissionRequirementResolver.requirementContext(
            selectedEngine: engine,
            muteSystemAudioWhileRecording: muteSystemAudioWhileRecording,
            featureSettings: featureSettings
        )

        hasMissingPermissions = SettingsPermissionRequirementResolver.hasMissingPermissions(context: context)
    }

    private func refreshModelConfigurationBadge() {
        let issues = ConfigurationTransferManager.missingConfigurationIssues(
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager,
            customLLMManager: customLLMManager
        )
        guard issues != missingModelConfigurationIssues else { return }
        missingModelConfigurationIssues = issues
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

    private var showsContentHeader: Bool {
        true
    }

    private var contentTopPadding: CGFloat {
        if sidebarMode == .root, selectedTab == .report {
            return 24
        }
        if !showsContentHeader {
            return 0
        }
        return 12
    }

    private func applyNavigationTarget(_ target: SettingsNavigationTarget) {
        navigationRequest = SettingsNavigationRequest(target: target)
        if let featureTab = target.featureTab {
            if FeatureSettingsTab.visibleTabs(
                appEnhancementEnabled: appEnhancementEnabled,
                noteEnabled: noteEnabled
            ).contains(featureTab) {
                selectedFeatureTab = featureTab
            } else {
                selectedFeatureTab = .transcription
            }
        }
        if target.tab == .feature {
            sidebarMode = .feature
            selectedTab = .feature
        } else if Self.isSettingsTab(target.tab) {
            sidebarMode = .settings
            selectedTab = target.tab
        } else {
            sidebarMode = .root
            selectedTab = target.tab
        }
    }

    private func switchToRootTab(_ tab: SettingsTab) {
        if tab == .feature {
            selectedTab = .feature
            sidebarMode = .feature
            if !FeatureSettingsTab.visibleTabs(
                appEnhancementEnabled: appEnhancementEnabled,
                noteEnabled: noteEnabled
            ).contains(selectedFeatureTab) {
                selectedFeatureTab = .transcription
            }
            return
        }
        if Self.isSettingsTab(tab) {
            sidebarMode = .settings
            selectedTab = tab
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

    private func openOfficialWebsite() {
        NSWorkspace.shared.open(Self.officialWebsiteURL)
    }

    private func openChangelog() {
        NSWorkspace.shared.open(Self.changelogURL)
    }

    private func openFeedbackPage() {
        NSWorkspace.shared.open(Self.feedbackURL)
    }

    private struct FeedbackDialogView: View {
        let onClose: () -> Void
        let onOpenFeedback: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(settingsLocalized("Feedback"))
                    .font(.title3.weight(.semibold))

                Text(settingsLocalized("Feedback Dialog Message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsDialogActionRow {
                    Button(settingsLocalized("Cancel"), action: onClose)
                        .buttonStyle(SettingsPillButtonStyle())
                        .keyboardShortcut(.cancelAction)

                    Button(settingsLocalized("Open Feedback Page"), action: onOpenFeedback)
                        .buttonStyle(SettingsPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .settingsDialogChrome(width: 420, onClose: onClose)
        }
    }

    private static func initializedStaticTabs(for tab: SettingsTab) -> Set<SettingsTab> {
        isStaticTab(tab) ? [tab] : []
    }

    private static func initialSidebarMode(for tab: SettingsTab) -> SettingsSidebarMode {
        if tab == .feature {
            return .feature
        }
        if isSettingsTab(tab) {
            return .settings
        }
        return .root
    }

    private static func isStaticTab(_ tab: SettingsTab) -> Bool {
        tab == .history || tab == .report || tab == .feature || tab == .dictionary || tab == .model
    }

    private static func isSettingsTab(_ tab: SettingsTab) -> Bool {
        SettingsTab.settingsTabs.contains(tab)
    }

}

private struct HomeShortcutPrompt: View {
    let shortcut: String

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            let prefix = settingsLocalized("Home Shortcut Prompt Prefix")
            let suffix = settingsLocalized("Home Shortcut Prompt Suffix")
            if !prefix.isEmpty {
                Text(prefix)
            }
            Text(shortcut)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 7)
                .frame(minHeight: 18)
                .background(
                    Capsule(style: .continuous)
                        .fill(SettingsUIStyle.controlFillColor)
                )
            if !suffix.isEmpty {
                Text(suffix)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
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
    let noteEnabled: Bool
    let hasMissingPermissions: Bool
    let hasNoAvailableMicrophones: Bool
    let activeModelDownloadCount: Int
    let hasMissingModelConfigurationIssues: Bool
    let updateBadgeState: UpdateBadgeState
    let onTapPermissionBadge: () -> Void
    let onTapMicrophoneBadge: () -> Void
    let onTapModelBadge: () -> Void
    let onTapUpdateBadge: () -> Void
    let onTapWebsite: () -> Void
    let onTapFeedback: () -> Void
    let onTapSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSidebarHeader(
                sidebarMode: sidebarMode,
                updateBadgeState: updateBadgeState,
                onTapUpdateBadge: onTapUpdateBadge,
                onReturnToRoot: onReturnToRoot
            )

            SettingsSidebarMenuPager(
                sidebarMode: sidebarMode,
                rootTabs: visibleRootTabs,
                featureTabs: visibleFeatureTabs,
                settingsTabs: visibleSettingsTabs,
                selectedTab: selectedTab,
                selectedFeatureTab: selectedFeatureTab,
                onSelectTab: onSelectTab,
                onSelectFeatureTab: onSelectFeatureTab
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 8) {
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
                    .frame(maxWidth: .infinity)
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
                    .frame(maxWidth: .infinity)
                    .buttonStyle(SettingsStatusButtonStyle(tint: .red))
                }

                if sidebarMode == .root, activeModelDownloadCount > 0 {
                    Button(action: onTapModelBadge) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.accentColor)
                                .frame(width: 13, height: 13)
                            Text(settingsLocalized("Downloading"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(activeModelDownloadCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .frame(minWidth: 22, minHeight: 20)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.opacity(0.14))
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(SettingsStatusButtonStyle(tint: .accentColor))
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
                    .frame(maxWidth: .infinity)
                    .buttonStyle(SettingsStatusButtonStyle(tint: .orange))
                }

                SettingsSidebarInfoBlock(
                    onTapWebsite: onTapWebsite,
                    onTapFeedback: onTapFeedback,
                    onTapSettings: onTapSettings
                )
            }
            .frame(maxWidth: .infinity)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var visibleRootTabs: [SettingsTab] {
        SettingsTab.visibleTabs(appEnhancementEnabled: appEnhancementEnabled)
    }

    private var visibleFeatureTabs: [FeatureSettingsTab] {
        FeatureSettingsTab.visibleTabs(
            appEnhancementEnabled: appEnhancementEnabled,
            noteEnabled: noteEnabled
        )
    }

    private var visibleSettingsTabs: [SettingsTab] {
        SettingsTab.settingsTabs
    }
}

private struct SettingsSidebarMenuPager: View {
    let sidebarMode: SettingsSidebarMode
    let rootTabs: [SettingsTab]
    let featureTabs: [FeatureSettingsTab]
    let settingsTabs: [SettingsTab]
    let selectedTab: SettingsTab
    let selectedFeatureTab: FeatureSettingsTab
    let onSelectTab: (SettingsTab) -> Void
    let onSelectFeatureTab: (FeatureSettingsTab) -> Void

    @State private var visibleSubmenuKind: SettingsSidebarSubmenuKind = .feature
    @State private var visiblePageIndex: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width

            HStack(alignment: .top, spacing: 0) {
                rootMenu
                    .frame(width: pageWidth, alignment: .topLeading)

                subMenu(kind: visibleSubmenuKind)
                    .frame(width: pageWidth, alignment: .topLeading)
            }
            .frame(width: pageWidth * 2, alignment: .leading)
            .offset(x: -pageWidth * visiblePageIndex)
            .onAppear {
                if let submenuKind = sidebarMode.submenuKind {
                    visibleSubmenuKind = submenuKind
                    visiblePageIndex = 1
                } else {
                    visiblePageIndex = 0
                }
            }
            .onChange(of: sidebarMode) { oldMode, newMode in
                if let submenuKind = newMode.submenuKind {
                    updateVisibleSubmenuKind(submenuKind)
                    animateToSubmenu()
                } else {
                    if oldMode != .root, let submenuKind = oldMode.submenuKind {
                        updateVisibleSubmenuKind(submenuKind)
                    }
                    animateToRoot()
                }
            }
        }
        .clipped()
    }

    private func updateVisibleSubmenuKind(_ submenuKind: SettingsSidebarSubmenuKind) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            visibleSubmenuKind = submenuKind
        }
    }

    private func animateToSubmenu() {
        withAnimation(.easeInOut(duration: 0.22)) {
            visiblePageIndex = 1
        }
    }

    private func animateToRoot() {
        withAnimation(.easeInOut(duration: 0.22)) {
            visiblePageIndex = 0
        }
    }

    private var rootMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rootTabs) { tab in
                SettingsSidebarTabButton(
                    iconKind: tab.sidebarIconKind,
                    title: tab.titleKey,
                    isActive: tab == selectedTab,
                    action: { onSelectTab(tab) }
                )
            }
        }
    }

    @ViewBuilder
    private func subMenu(kind: SettingsSidebarSubmenuKind) -> some View {
        switch kind {
        case .feature:
            featureMenu
        case .settings:
            settingsMenu
        }
    }

    private var featureMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(featureTabs) { tab in
                SettingsSidebarTabButton(
                    iconKind: tab.sidebarIconKind,
                    systemImageName: tab.sidebarIconKind == nil ? tab.iconName : nil,
                    title: tab.titleKey,
                    badgeText: tab == .meeting ? "Beta" : nil,
                    isActive: tab == selectedFeatureTab,
                    action: { onSelectFeatureTab(tab) }
                )
            }
        }
    }

    private var settingsMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(settingsTabs) { tab in
                SettingsSidebarTabButton(
                    iconKind: tab.sidebarIconKind,
                    title: tab.titleKey,
                    isActive: tab == selectedTab,
                    action: { onSelectTab(tab) }
                )
            }
        }
    }
}

private enum SettingsSidebarSubmenuKind {
    case feature
    case settings
}

private extension SettingsSidebarMode {
    var submenuKind: SettingsSidebarSubmenuKind? {
        switch self {
        case .root:
            return nil
        case .feature:
            return .feature
        case .settings:
            return .settings
        }
    }
}

private struct SettingsSidebarTabButton: View {
    let iconKind: SettingsSidebarIconKind?
    var systemImageName: String?
    let title: LocalizedStringKey
    var badgeText: String? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let iconKind {
                    SettingsSidebarIconView(kind: iconKind)
                        .frame(width: SettingsUIStyle.sidebarItemIconWidth)
                } else if let systemImageName {
                    Image(systemName: systemImageName)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: SettingsUIStyle.sidebarItemIconWidth)
                }

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .layoutPriority(1)

                if let badgeText {
                    Text(settingsLocalized(badgeText))
                        .font(.system(size: 9, weight: .semibold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(isActive ? 0.20 : 0.12))
                        )
                        .foregroundStyle(Color.accentColor)
                        .fixedSize()
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsSidebarItemButtonStyle(isActive: isActive))
    }
}

private struct SettingsSidebarHeader: View {
    let sidebarMode: SettingsSidebarMode
    let updateBadgeState: UpdateBadgeState
    let onTapUpdateBadge: () -> Void
    let onReturnToRoot: () -> Void

    private var appVersionText: String {
        let bundle = Bundle.main
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let shortVersion, !shortVersion.isEmpty {
            return "v\(shortVersion)"
        }
        return ""
    }

    private var showsNewVersionTag: Bool {
        if case .newVersion = updateBadgeState {
            return true
        }
        return false
    }

    private var headerBadgeHeight: CGFloat {
        19
    }

    var body: some View {
        HStack {
            switch sidebarMode {
            case .root:
                Spacer(minLength: 0)

                if !appVersionText.isEmpty {
                    if showsNewVersionTag {
                        Button(action: onTapUpdateBadge) {
                            badgeContent
                        }
                        .buttonStyle(.plain)
                    } else {
                        badgeContent
                    }
                }

            case .feature, .settings:
                Spacer(minLength: 0)

                Button(action: onReturnToRoot) {
                    SettingsSidebarBackIcon()
                        .frame(width: 16, height: 16)
                        .frame(width: 26, height: headerBadgeHeight)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(SettingsSidebarHeaderBackButtonStyle())
                .accessibilityLabel(settingsLocalized("Back"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 5)
        .padding(.bottom, 14)
    }

    private var badgeContent: some View {
        HStack(spacing: 4) {
            if showsNewVersionTag {
                Text(settingsLocalized("New"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: headerBadgeHeight)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.green.opacity(0.12))
                    )
            }

            Text(appVersionText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 7)
                .frame(height: headerBadgeHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                )
        }
        .contentShape(Capsule(style: .continuous))
    }
}

private struct SettingsSidebarBackIcon: View {
    var body: some View {
        SettingsSidebarBackIconShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: 1.35,
                    lineCap: .round,
                    lineJoin: .round,
                    miterLimit: 10
                )
            )
    }
}

private struct SettingsSidebarBackIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 24, rect.height / 24)
        let xOffset = rect.midX - 12 * scale
        let yOffset = rect.midY - 12 * scale

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: xOffset + x * scale, y: yOffset + y * scale)
        }

        var path = Path()
        path.move(to: point(7.12988, 18.3096))
        path.addLine(to: point(15.1299, 18.3096))
        path.addCurve(
            to: point(20.1299, 13.3096),
            control1: point(17.8899, 18.3096),
            control2: point(20.1299, 16.0696)
        )
        path.addCurve(
            to: point(15.1299, 8.30957),
            control1: point(20.1299, 10.5496),
            control2: point(17.8899, 8.30957)
        )
        path.addLine(to: point(4.12988, 8.30957))

        path.move(to: point(6.43012, 10.8104))
        path.addLine(to: point(3.87012, 8.25043))
        path.addLine(to: point(6.43012, 5.69043))

        return path
    }
}

private struct SettingsSidebarHeaderBackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSidebarHeaderBackButtonBody(configuration: configuration)
    }
}

private struct SettingsSidebarHeaderBackButtonBody: View {
    let configuration: SettingsSidebarHeaderBackButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(Color.secondary.opacity(configuration.isPressed ? 0.72 : 1))
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(backgroundOpacity))
            )
            .contentShape(Capsule(style: .continuous))
            .onHover { isHovered = $0 }
    }

    private var backgroundOpacity: Double {
        if configuration.isPressed {
            return 0.11
        }
        if isHovered {
            return 0.075
        }
        return 0.055
    }
}

private struct SettingsSidebarInfoBlock: View {
    let onTapWebsite: () -> Void
    let onTapFeedback: () -> Void
    let onTapSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onTapWebsite) {
                HStack(spacing: 6) {
                    SettingsWebsiteIconView()
                        .frame(width: 14, height: 14)
                    Text("Voxt")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .buttonStyle(SettingsSidebarInfoTextButtonStyle())

            Spacer(minLength: 6)

            Button(action: onTapFeedback) {
                SettingsSidebarIconView(kind: .feedback)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(SettingsSidebarInfoIconButtonStyle())
            .accessibilityLabel(settingsLocalized("Feedback"))
            .help(settingsLocalized("Feedback"))

            Button(action: onTapSettings) {
                SettingsSidebarIconView(kind: .settings)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(SettingsSidebarInfoIconButtonStyle())
            .accessibilityLabel(settingsLocalized("Settings"))
            .help(settingsLocalized("Settings"))
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsSidebarInfoTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSidebarInfoTextButtonBody(configuration: configuration)
    }
}

private struct SettingsSidebarInfoTextButtonBody: View {
    let configuration: SettingsSidebarInfoTextButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.72 : 0.92))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(Capsule(style: .continuous))
            .onHover { isHovered = $0 }
    }

    private var backgroundFill: Color {
        if configuration.isPressed {
            return SettingsUIStyle.sidebarItemPressedFillColor
        }
        if isHovered {
            return SettingsUIStyle.sidebarItemPressedFillColor
        }
        return SettingsUIStyle.sidebarItemFillColor
    }
}

private struct SettingsSidebarInfoIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSidebarInfoIconButtonBody(configuration: configuration)
    }
}

private struct SettingsSidebarInfoIconButtonBody: View {
    let configuration: SettingsSidebarInfoIconButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.secondary.opacity(configuration.isPressed ? 0.72 : 1))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }

    private var backgroundFill: Color {
        if configuration.isPressed {
            return SettingsUIStyle.sidebarItemPressedFillColor
        }
        if isHovered {
            return SettingsUIStyle.sidebarItemFillColor
        }
        return .clear
    }
}

private enum UpdateBadgeState: Equatable {
    case none
    case checkFailed(String)
    case newVersion(String?)
    case openingWindow(String?)

    var iconName: String {
        switch self {
        case .none:
            return "arrow.down.circle.fill"
        case .checkFailed:
            return "exclamationmark.triangle.fill"
        case .newVersion:
            return "arrow.down.circle.fill"
        case .openingWindow:
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
        case .openingWindow:
            return .green
        }
    }

    var showsSpinner: Bool {
        switch self {
        case .openingWindow:
            return true
        case .none, .checkFailed, .newVersion:
            return false
        }
    }

    var isTriggerDisabled: Bool {
        switch self {
        case .openingWindow:
            return true
        case .none, .checkFailed, .newVersion:
            return false
        }
    }

    var title: String {
        switch self {
        case .none:
            return settingsLocalized("New Update")
        case .checkFailed:
            return settingsLocalized("Update Check Failed")
        case .newVersion:
            return settingsLocalized("New Update")
        case .openingWindow:
            return settingsLocalized("Opening…")
        }
    }
}

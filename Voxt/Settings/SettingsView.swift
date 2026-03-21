import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices
import Combine

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
    @State private var selectedTab: SettingsTab
    @State private var hasMissingPermissions = false
    @State private var missingModelConfigurationIssues: [ConfigurationTransferManager.MissingConfigurationIssue] = []
    @State private var languageRefreshToken = UUID()
    @State private var updateBadgeAlertMessage: String?
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
        initialTab: SettingsTab = .general
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
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))

            HStack(alignment: .top, spacing: 8) {
                SettingsSidebar(
                    selectedTab: $selectedTab,
                    appEnhancementEnabled: appEnhancementEnabled,
                    hasMissingPermissions: hasMissingPermissions,
                    hasMissingModelConfigurationIssues: !missingModelConfigurationIssues.isEmpty,
                    updateBadgeState: updateBadgeState,
                    onTapPermissionBadge: {
                        selectedTab = .permissions
                    },
                    onTapModelBadge: {
                        selectedTab = .model
                    },
                    onTapUpdateBadge: {
                        presentUpdateBadgeDetails()
                    }
                )
                    .frame(width: 170)
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedTab.titleKey)
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 8)

                    tabContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .padding(.top, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(minWidth: 760, minHeight: 560)
        .environment(\.locale, interfaceLanguage.locale)
        .id(languageRefreshToken)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            refreshPermissionBadge()
            refreshModelConfigurationBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionBadge()
            refreshModelConfigurationBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtSettingsSelectTab)) { notification in
            guard let rawValue = notification.userInfo?["tab"] as? String,
                  let targetTab = SettingsTab(rawValue: rawValue)
            else {
                return
            }
            selectedTab = targetTab
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
            if !isEnabled, selectedTab == .appEnhancement {
                selectedTab = .model
            }
        }
        .onChange(of: muteSystemAudioWhileRecording) { _, _ in
            refreshPermissionBadge()
        }
        .alert(
            String(localized: "Update Information"),
            isPresented: Binding(
                get: { updateBadgeAlertMessage != nil },
                set: { if !$0 { updateBadgeAlertMessage = nil } }
            ),
            actions: {
                Button(String(localized: "Check Again")) {
                    appUpdateManager.checkForUpdates(source: .manual)
                }
                Button(String(localized: "OK"), role: .cancel) {}
            },
            message: {
                Text(updateBadgeAlertMessage ?? "")
            }
        )
    }

    private var interfaceLanguage: AppInterfaceLanguage {
        AppInterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .system
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
        if selectedTab == .history || selectedTab == .report || selectedTab == .appEnhancement || selectedTab == .dictionary {
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
                    dictionarySuggestionStore: dictionarySuggestionStore
                )
            } else if selectedTab == .dictionary {
                DictionarySettingsView(
                    historyStore: historyStore,
                    dictionaryStore: dictionaryStore,
                    dictionarySuggestionStore: dictionarySuggestionStore,
                    availableHistoryScanModels: availableDictionaryHistoryScanModels,
                    onIngestSuggestionsFromHistory: onIngestDictionarySuggestionsFromHistory
                )
            } else if selectedTab == .appEnhancement {
                AppEnhancementSettingsView()
            } else {
                ReportSettingsView(historyStore: historyStore)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    private var scrollableTabContent: some View {
        ScrollView {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView(appUpdateManager: appUpdateManager)
                case .permissions:
                    PermissionsSettingsView()
                case .report:
                    EmptyView()
                case .model:
                    ModelSettingsView(
                        mlxModelManager: mlxModelManager,
                        whisperModelManager: whisperModelManager,
                        customLLMManager: customLLMManager,
                        missingConfigurationIssues: missingModelConfigurationIssues
                    )
                case .dictionary:
                    EmptyView()
                case .appEnhancement:
                    EmptyView()
                case .hotkey:
                    HotkeySettingsView()
                case .about:
                    AboutSettingsView(appUpdateManager: appUpdateManager)
                case .history:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 8)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func refreshPermissionBadge() {
        let microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        let accessibilityGranted = AccessibilityPermissionManager.isTrusted()
        let inputMonitoringGranted: Bool
        let requiresSystemAudioCapture = UserDefaults.standard.bool(forKey: AppPreferenceKey.muteSystemAudioWhileRecording)
        let systemAudioCaptureGranted = !requiresSystemAudioCapture || SystemAudioCapturePermission.authorizationStatus() == .authorized
        if #available(macOS 10.15, *) {
            inputMonitoringGranted = CGPreflightListenEventAccess()
        } else {
            inputMonitoringGranted = true
        }
        hasMissingPermissions = !(microphoneGranted && speechGranted && accessibilityGranted && inputMonitoringGranted && systemAudioCaptureGranted)
    }

    private func refreshModelConfigurationBadge() {
        missingModelConfigurationIssues = ConfigurationTransferManager.missingConfigurationIssues(
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager,
            customLLMManager: customLLMManager
        )
    }

    private func presentUpdateBadgeDetails() {
        switch updateBadgeState {
        case .checkFailed(let issue):
            updateBadgeAlertMessage = AppLocalization.format(
                "Unable to check for updates.\n\n%@",
                issue
            )
        case .newVersion(let version):
            let resolvedVersion = version ?? AppLocalization.localizedString("A new version is available.")
            updateBadgeAlertMessage = AppLocalization.format(
                "A new version of Voxt is available:\n%@",
                resolvedVersion
            )
        case .none:
            updateBadgeAlertMessage = AppLocalization.localizedString("No update information is currently available.")
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    let appEnhancementEnabled: Bool
    let hasMissingPermissions: Bool
    let hasMissingModelConfigurationIssues: Bool
    let updateBadgeState: UpdateBadgeState
    let onTapPermissionBadge: () -> Void
    let onTapModelBadge: () -> Void
    let onTapUpdateBadge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleTabs) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 16)
                        Text(tab.titleKey)
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(tab == selectedTab ? .white : .primary)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == selectedTab ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            if hasMissingPermissions {
                Button(action: onTapPermissionBadge) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                        Text(String(localized: "Permissions Disabled"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.red.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if hasMissingModelConfigurationIssues {
                Button(action: onTapModelBadge) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(String(localized: "Model Setup Required"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if updateBadgeState != .none {
                Button(action: onTapUpdateBadge) {
                    HStack(spacing: 8) {
                        Image(systemName: updateBadgeState.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(updateBadgeState.tintColor)
                        Text(updateBadgeState.titleKey)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(updateBadgeState.tintColor)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(updateBadgeState.tintColor.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(updateBadgeState.tintColor.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)
    }

    private var visibleTabs: [SettingsTab] {
        SettingsTab.allCases.filter { tab in
            appEnhancementEnabled || tab != .appEnhancement
        }
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

    var titleKey: LocalizedStringKey {
        switch self {
        case .none:
            return "New Version Available"
        case .checkFailed:
            return "Update Check Failed"
        case .newVersion:
            return "New Version Available"
        }
    }
}

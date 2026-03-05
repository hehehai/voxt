import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager
    @ObservedObject var historyStore: TranscriptionHistoryStore
    let appUpdateManager: AppUpdateManager
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.appEnhancementEnabled) private var appEnhancementEnabled = false
    @State private var selectedTab: SettingsTab
    @State private var hasMissingPermissions = false
    @State private var languageRefreshToken = UUID()

    init(
        mlxModelManager: MLXModelManager,
        customLLMManager: CustomLLMModelManager,
        historyStore: TranscriptionHistoryStore,
        appUpdateManager: AppUpdateManager,
        initialTab: SettingsTab = .general
    ) {
        self.mlxModelManager = mlxModelManager
        self.customLLMManager = customLLMManager
        self.historyStore = historyStore
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
                    onTapPermissionBadge: {
                        selectedTab = .permissions
                    }
                )
                    .frame(width: 170)
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedTab.titleKey)
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 8)

                    if selectedTab == .history || selectedTab == .report || selectedTab == .appEnhancement {
                        Group {
                            if selectedTab == .history {
                                HistorySettingsView(historyStore: historyStore)
                            } else if selectedTab == .appEnhancement {
                                AppEnhancementSettingsView()
                            } else {
                                ReportSettingsView(historyStore: historyStore)
                            }
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 8)
                            .padding(.top, 2)
                    } else {
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
                                        customLLMManager: customLLMManager
                                    )
                                case .appEnhancement:
                                    EmptyView()
                                case .hotkey:
                                    HotkeySettingsView()
                                case .about:
                                    AboutSettingsView()
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
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionBadge()
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
        .onChange(of: appEnhancementEnabled) { _, isEnabled in
            if !isEnabled, selectedTab == .appEnhancement {
                selectedTab = .model
            }
        }
    }

    private var interfaceLanguage: AppInterfaceLanguage {
        AppInterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .system
    }

    private func refreshPermissionBadge() {
        let microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        let accessibilityGranted = AXIsProcessTrusted()
        let inputMonitoringGranted: Bool
        if #available(macOS 10.15, *) {
            inputMonitoringGranted = CGPreflightListenEventAccess()
        } else {
            inputMonitoringGranted = true
        }
        hasMissingPermissions = !(microphoneGranted && speechGranted && accessibilityGranted && inputMonitoringGranted)
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    let appEnhancementEnabled: Bool
    let hasMissingPermissions: Bool
    let onTapPermissionBadge: () -> Void

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

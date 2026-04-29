import SwiftUI
import CoreAudio
import AppKit
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    let appUpdateManager: AppUpdateManager
    let navigationRequest: SettingsNavigationRequest?
    let onOpenSetupGuide: (() -> Void)?
    @AppStorage(AppPreferenceKey.interactionSoundsEnabled) private var interactionSoundsEnabled = true
    @AppStorage(AppPreferenceKey.interactionSoundPreset) private var interactionSoundPresetRaw = InteractionSoundPreset.soft.rawValue
    @AppStorage(AppPreferenceKey.muteSystemAudioWhileRecording) private var muteSystemAudioWhileRecording = false
    @AppStorage(AppPreferenceKey.overlayPosition) private var overlayPositionRaw = OverlayPosition.bottom.rawValue
    @AppStorage(AppPreferenceKey.overlayCardOpacity) private var overlayCardOpacity = 82
    @AppStorage(AppPreferenceKey.overlayCardCornerRadius) private var overlayCardCornerRadius = 24
    @AppStorage(AppPreferenceKey.overlayScreenEdgeInset) private var overlayScreenEdgeInset = 30
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.userMainLanguageCodes) private var userMainLanguageCodesRaw = UserMainLanguageOption.defaultStoredSelectionValue
    @AppStorage(AppPreferenceKey.meetingNotesBetaEnabled) private var meetingNotesBetaEnabled = false
    @AppStorage(AppPreferenceKey.hideMeetingOverlayFromScreenSharing) private var hideMeetingOverlayFromScreenSharing = false
    @AppStorage(AppPreferenceKey.autoCopyWhenNoFocusedInput) private var autoCopyWhenNoFocusedInput = false
    @AppStorage(AppPreferenceKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppPreferenceKey.showInDock) private var showInDock = false
    @AppStorage(AppPreferenceKey.autoCheckForUpdates) private var autoCheckForUpdates = true
    @AppStorage(AppPreferenceKey.hotkeyDebugLoggingEnabled) private var hotkeyDebugLoggingEnabled = false
    @AppStorage(AppPreferenceKey.llmDebugLoggingEnabled) private var llmDebugLoggingEnabled = false
    @AppStorage(AppPreferenceKey.networkProxyMode) private var networkProxyModeRaw = VoxtNetworkSession.ProxyMode.system.rawValue
    @AppStorage(AppPreferenceKey.customProxyScheme) private var customProxySchemeRaw = VoxtNetworkSession.ProxyScheme.http.rawValue
    @AppStorage(AppPreferenceKey.customProxyHost) private var customProxyHost = ""
    @AppStorage(AppPreferenceKey.customProxyPort) private var customProxyPort = ""
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var microphoneState = MicrophoneResolvedState.empty
    @State private var launchAtLoginError: String?
    @State private var isSyncingLaunchAtLoginState = false
    @State private var interactionSoundPlayer = InteractionSoundPlayer()
    @State private var configurationTransferMessage: String?
    @State private var isUserMainLanguageSheetPresented = false
    @State private var isMicrophonePriorityDialogPresented = false
    @State private var systemAudioPermissionMessage: String?
    @State private var customProxyUsername = ""
    @State private var customProxyPassword = ""

    private var networkProxyMode: Binding<VoxtNetworkSession.ProxyMode> {
        Binding(
            get: { VoxtNetworkSession.ProxyMode(rawValue: networkProxyModeRaw) ?? .system },
            set: { networkProxyModeRaw = $0.rawValue }
        )
    }

    private var overlayPosition: Binding<OverlayPosition> {
        Binding(
            get: { OverlayPosition(rawValue: overlayPositionRaw) ?? .bottom },
            set: { overlayPositionRaw = $0.rawValue }
        )
    }

    private var interfaceLanguageSelection: Binding<AppInterfaceLanguage> {
        Binding(
            get: { AppInterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .system },
            set: { interfaceLanguageRaw = $0.rawValue }
        )
    }

    private var interactionSoundPresetSelection: Binding<InteractionSoundPreset> {
        Binding(
            get: { InteractionSoundPreset(rawValue: interactionSoundPresetRaw) ?? .soft },
            set: { interactionSoundPresetRaw = $0.rawValue }
        )
    }

    private var customProxyScheme: Binding<VoxtNetworkSession.ProxyScheme> {
        Binding(
            get: { VoxtNetworkSession.ProxyScheme(rawValue: customProxySchemeRaw) ?? .http },
            set: { customProxySchemeRaw = $0.rawValue }
        )
    }

    private var selectedUserMainLanguageCodes: [String] {
        UserMainLanguageOption.storedSelection(from: userMainLanguageCodesRaw)
    }

    private var userMainLanguageSummary: String {
        let codes = selectedUserMainLanguageCodes
        guard let primaryCode = codes.first,
              let primaryOption = UserMainLanguageOption.option(for: primaryCode)
        else {
            return UserMainLanguageOption.fallbackOption().title()
        }

        if codes.count == 1 {
            return primaryOption.title()
        }

        let format = AppLocalization.localizedString("%@ + %d more")
        return String(format: format, primaryOption.title(), codes.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralConfigurationCard(
                message: configurationTransferMessage,
                onExport: exportConfiguration,
                onImport: importConfiguration,
                onOpenSetupGuide: onOpenSetupGuide
            )
            .settingsNavigationAnchor(.generalConfiguration)

            GeneralAudioCard(
                microphoneState: microphoneState,
                interactionSoundsEnabled: $interactionSoundsEnabled,
                muteSystemAudioWhileRecording: $muteSystemAudioWhileRecording,
                systemAudioPermissionMessage: systemAudioPermissionMessage,
                interactionSoundPreset: interactionSoundPresetSelection,
                onTrySound: { interactionSoundPlayer.playPreview(preset: interactionSoundPreset) },
                onManageMicrophones: { isMicrophonePriorityDialogPresented = true },
                onViewPriorityList: { isMicrophonePriorityDialogPresented = true }
            )
            .settingsNavigationAnchor(.generalAudio)

            GeneralTranscriptionUICard(
                overlayPosition: overlayPosition,
                overlayCardOpacity: $overlayCardOpacity,
                overlayCardCornerRadius: $overlayCardCornerRadius,
                overlayScreenEdgeInset: $overlayScreenEdgeInset,
                meetingNotesBetaEnabled: $meetingNotesBetaEnabled,
                hideMeetingOverlayFromScreenSharing: $hideMeetingOverlayFromScreenSharing
            )
            .settingsNavigationAnchor(.generalTranscriptionUI)

            GeneralLanguagesCard(
                interfaceLanguage: interfaceLanguageSelection,
                userMainLanguageSummary: userMainLanguageSummary,
                onEditUserMainLanguage: { isUserMainLanguageSheetPresented = true }
            )
            .settingsNavigationAnchor(.generalLanguages)

            GeneralOutputCard(
                autoCopyWhenNoFocusedInput: $autoCopyWhenNoFocusedInput
            )
            .settingsNavigationAnchor(.generalOutput)

            GeneralLoggingCard(
                hotkeyDebugLoggingEnabled: $hotkeyDebugLoggingEnabled,
                llmDebugLoggingEnabled: $llmDebugLoggingEnabled
            )
            .settingsNavigationAnchor(.generalLogging)

            GeneralAppBehaviorCard(
                launchAtLogin: $launchAtLogin,
                showInDock: $showInDock,
                autoCheckForUpdates: $autoCheckForUpdates,
                networkProxyMode: networkProxyMode,
                customProxyScheme: customProxyScheme,
                customProxyHost: $customProxyHost,
                customProxyPort: $customProxyPort,
                customProxyUsername: $customProxyUsername,
                customProxyPassword: $customProxyPassword,
                launchAtLoginError: launchAtLoginError
            )
            .settingsNavigationAnchor(.generalAppBehavior)
        }
        .onAppear {
            refreshInputDevices()

            Task {
                let status = AppBehaviorController.launchAtLoginIsEnabled()
                await MainActor.run {
                    isSyncingLaunchAtLoginState = true
                    if status != launchAtLogin {
                        launchAtLogin = status
                    }
                    isSyncingLaunchAtLoginState = false
                }
            }
            if autoCheckForUpdates != appUpdateManager.automaticallyChecksForUpdates {
                autoCheckForUpdates = appUpdateManager.automaticallyChecksForUpdates
            }
            refreshProxyCredentials()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            if isSyncingLaunchAtLoginState { return }
            Task {
                do {
                    try AppBehaviorController.setLaunchAtLogin(newValue)
                    await MainActor.run { launchAtLoginError = nil }
                } catch {
                    await MainActor.run {
                        launchAtLogin.toggle()
                        let format = NSLocalizedString("Unable to change login item: %@", comment: "")
                        launchAtLoginError = String(format: format, error.localizedDescription)
                    }
                }
            }
        }
        .onChange(of: showInDock) { _, newValue in
            if let appDelegate = AppDelegate.shared {
                appDelegate.synchronizeAppActivationPolicy()
            } else {
                AppBehaviorController.applyDockVisibility(
                    showInDock: newValue,
                    mainWindowVisible: true
                )
            }
        }
        .onChange(of: autoCheckForUpdates) { _, newValue in
            appUpdateManager.syncAutomaticallyChecksForUpdates(newValue)
        }
        .onChange(of: muteSystemAudioWhileRecording) { _, newValue in
            guard newValue else {
                systemAudioPermissionMessage = nil
                return
            }

            let status = SystemAudioCapturePermission.authorizationStatus()
            if status == .authorized {
                systemAudioPermissionMessage = nil
                return
            }

            SystemAudioCapturePermission.requestAccess { granted in
                systemAudioPermissionMessage = granted
                    ? AppLocalization.localizedString("System audio recording permission granted.")
                    : AppLocalization.localizedString("System audio recording permission is required for this feature. You can grant it in Settings > Permissions.")
            }
        }
        .onChange(of: interfaceLanguageRaw) { _, _ in
            NotificationCenter.default.post(name: .voxtInterfaceLanguageDidChange, object: nil)
        }
        .onChange(of: overlayPositionRaw) { _, _ in
            postOverlayAppearanceDidChange()
        }
        .onChange(of: overlayCardOpacity) { _, newValue in
            overlayCardOpacity = min(max(newValue, 0), 100)
            postOverlayAppearanceDidChange()
        }
        .onChange(of: overlayCardCornerRadius) { _, newValue in
            overlayCardCornerRadius = min(max(newValue, 0), 40)
            postOverlayAppearanceDidChange()
        }
        .onChange(of: overlayScreenEdgeInset) { _, newValue in
            overlayScreenEdgeInset = min(max(newValue, 0), 120)
            postOverlayAppearanceDidChange()
        }
        .onChange(of: customProxyUsername) { _, _ in
            persistProxyCredentials()
        }
        .onChange(of: customProxyPassword) { _, _ in
            persistProxyCredentials()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtAudioInputDevicesDidChange)) { _ in
            refreshInputDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtSelectedInputDeviceDidChange)) { _ in
            refreshInputDevices()
        }
        .sheet(isPresented: $isUserMainLanguageSheetPresented) {
            UserMainLanguageSelectionSheet(
                selectedCodes: selectedUserMainLanguageCodes,
                localeIdentifier: interfaceLanguage.localeIdentifier
            ) { updatedCodes in
                userMainLanguageCodesRaw = UserMainLanguageOption.storageValue(for: updatedCodes)
            }
        }
        .sheet(isPresented: $isMicrophonePriorityDialogPresented) {
            MicrophonePriorityDialog(
                state: microphoneState,
                onUseNow: { uid in
                    focusMicrophone(uid: uid, source: "settings dialog")
                },
                onAutoSwitchChanged: { isEnabled in
                    setMicrophoneAutoSwitchEnabled(isEnabled)
                },
                onReorderPriority: { orderedUIDs in
                    applyMicrophonePriorityOrder(orderedUIDs)
                }
            )
        }
        .id(interfaceLanguageRaw)
    }

    private func refreshInputDevices() {
        inputDevices = AudioInputDeviceManager.availableInputDevices()
        microphoneState = MicrophonePreferenceManager.syncState(
            defaults: .standard,
            availableDevices: inputDevices
        )
    }

    private var interactionSoundPreset: InteractionSoundPreset {
        InteractionSoundPreset(rawValue: interactionSoundPresetRaw) ?? .soft
    }

    private var interfaceLanguage: AppInterfaceLanguage {
        AppInterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .system
    }

    private func refreshProxyCredentials() {
        let credentials = VoxtNetworkSession.currentProxyCredentials()
        customProxyUsername = credentials.username
        customProxyPassword = credentials.password
    }

    private func persistProxyCredentials() {
        VoxtNetworkSession.setCustomProxyCredentials(
            username: customProxyUsername,
            password: customProxyPassword
        )
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Voxt-Configuration.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try ConfigurationTransferManager.exportJSONString()
            try text.write(to: url, atomically: true, encoding: .utf8)
            configurationTransferMessage = String(localized: "Configuration exported successfully.")
        } catch {
            configurationTransferMessage = String(format: NSLocalizedString("Configuration export failed: %@", comment: ""), error.localizedDescription)
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            try ConfigurationTransferManager.importConfiguration(from: text)
            let defaults = UserDefaults.standard
            if let appDelegate = AppDelegate.shared {
                appDelegate.synchronizeAppActivationPolicy()
            } else {
                AppBehaviorController.applyDockVisibility(
                    showInDock: defaults.bool(forKey: AppPreferenceKey.showInDock),
                    mainWindowVisible: true
                )
            }
            try? AppBehaviorController.setLaunchAtLogin(defaults.bool(forKey: AppPreferenceKey.launchAtLogin))
            appUpdateManager.syncAutomaticallyChecksForUpdates(defaults.bool(forKey: AppPreferenceKey.autoCheckForUpdates))
            NotificationCenter.default.post(name: .voxtConfigurationDidImport, object: nil)
            NotificationCenter.default.post(name: .voxtInterfaceLanguageDidChange, object: nil)
            NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
            NotificationCenter.default.post(name: .voxtOverlayAppearanceDidChange, object: nil)
            refreshInputDevices()
            refreshProxyCredentials()
            configurationTransferMessage = String(localized: "Configuration imported successfully. Included dictionary data was restored, and sensitive fields need to be filled in again if required.")
        } catch {
            configurationTransferMessage = String(format: NSLocalizedString("Configuration import failed: %@", comment: ""), error.localizedDescription)
        }
    }

    private func postOverlayAppearanceDidChange() {
        NotificationCenter.default.post(name: .voxtOverlayAppearanceDidChange, object: nil)
    }

    private func selectMicrophoneManually(uid: String) {
        microphoneState = MicrophonePreferenceManager.setFocusedDevice(
            uid: uid,
            defaults: .standard,
            availableDevices: inputDevices
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
    }

    private func setMicrophoneAutoSwitchEnabled(_ isEnabled: Bool) {
        VoxtLog.info("Microphone auto switch updated from settings dialog. enabled=\(isEnabled)")
        microphoneState = MicrophonePreferenceManager.setAutoSwitchEnabled(
            isEnabled,
            defaults: .standard,
            availableDevices: inputDevices
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
    }

    private func applyMicrophonePriorityOrder(_ orderedUIDs: [String]) {
        VoxtLog.info("Microphone priority updated from settings dialog. orderedUIDs=\(orderedUIDs.joined(separator: ","))", verbose: true)
        microphoneState = MicrophonePreferenceManager.reorderPriority(
            orderedUIDs: orderedUIDs,
            defaults: .standard,
            availableDevices: inputDevices
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
    }

    private func focusMicrophone(uid: String, source: String) {
        if let entry = microphoneState.entries.first(where: { $0.uid == uid }) {
            VoxtLog.info("Microphone focus changed from \(source). uid=\(uid), name=\(entry.name)")
        } else {
            VoxtLog.info("Microphone focus changed from \(source). uid=\(uid)")
        }
        selectMicrophoneManually(uid: uid)
    }
}

import SwiftUI
import CoreAudio
import AppKit
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    let appUpdateManager: AppUpdateManager
    @AppStorage(AppPreferenceKey.selectedInputDeviceID) private var selectedInputDeviceIDRaw = 0
    @AppStorage(AppPreferenceKey.interactionSoundsEnabled) private var interactionSoundsEnabled = true
    @AppStorage(AppPreferenceKey.interactionSoundPreset) private var interactionSoundPresetRaw = InteractionSoundPreset.soft.rawValue
    @AppStorage(AppPreferenceKey.muteSystemAudioWhileRecording) private var muteSystemAudioWhileRecording = false
    @AppStorage(AppPreferenceKey.overlayPosition) private var overlayPositionRaw = OverlayPosition.bottom.rawValue
    @AppStorage(AppPreferenceKey.overlayCardOpacity) private var overlayCardOpacity = 82
    @AppStorage(AppPreferenceKey.overlayCardCornerRadius) private var overlayCardCornerRadius = 24
    @AppStorage(AppPreferenceKey.overlayScreenEdgeInset) private var overlayScreenEdgeInset = 30
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.translationTargetLanguage) private var translationTargetLanguageRaw = TranslationTargetLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.userMainLanguageCodes) private var userMainLanguageCodesRaw = UserMainLanguageOption.defaultStoredSelectionValue
    @AppStorage(AppPreferenceKey.translateSelectedTextOnTranslationHotkey) private var translateSelectedTextOnTranslationHotkey = true
    @AppStorage(AppPreferenceKey.meetingNotesBetaEnabled) private var meetingNotesBetaEnabled = false
    @AppStorage(AppPreferenceKey.autoCopyWhenNoFocusedInput) private var autoCopyWhenNoFocusedInput = false
    @AppStorage(AppPreferenceKey.appEnhancementEnabled) private var appEnhancementEnabled = false
    @AppStorage(AppPreferenceKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppPreferenceKey.showInDock) private var showInDock = false
    @AppStorage(AppPreferenceKey.autoCheckForUpdates) private var autoCheckForUpdates = true
    @AppStorage(AppPreferenceKey.hotkeyDebugLoggingEnabled) private var hotkeyDebugLoggingEnabled = false
    @AppStorage(AppPreferenceKey.llmDebugLoggingEnabled) private var llmDebugLoggingEnabled = false
    @AppStorage(AppPreferenceKey.networkProxyMode) private var networkProxyModeRaw = VoxtNetworkSession.ProxyMode.system.rawValue
    @AppStorage(AppPreferenceKey.customProxyScheme) private var customProxySchemeRaw = VoxtNetworkSession.ProxyScheme.http.rawValue
    @AppStorage(AppPreferenceKey.customProxyHost) private var customProxyHost = ""
    @AppStorage(AppPreferenceKey.customProxyPort) private var customProxyPort = ""
    @AppStorage(AppPreferenceKey.customProxyUsername) private var customProxyUsername = ""
    @AppStorage(AppPreferenceKey.customProxyPassword) private var customProxyPassword = ""
    @AppStorage(AppPreferenceKey.modelStorageRootPath) private var modelStorageRootPath = ""

    @State private var inputDevices: [AudioInputDevice] = []
    @State private var launchAtLoginError: String?
    @State private var isSyncingLaunchAtLoginState = false
    @State private var interactionSoundPlayer = InteractionSoundPlayer()
    @State private var modelStorageDisplayPath = ""
    @State private var modelStorageSelectionError: String?
    @State private var configurationTransferMessage: String?
    @State private var isUserMainLanguageSheetPresented = false
    @State private var systemAudioPermissionMessage: String?

    private var selectedInputDeviceID: AudioDeviceID {
        AudioDeviceID(selectedInputDeviceIDRaw)
    }

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

    private var translationTargetLanguage: Binding<TranslationTargetLanguage> {
        Binding(
            get: { TranslationTargetLanguage(rawValue: translationTargetLanguageRaw) ?? .english },
            set: { translationTargetLanguageRaw = $0.rawValue }
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
                onImport: importConfiguration
            )

            GeneralAudioCard(
                inputDevices: inputDevices,
                selectedInputDeviceIDRaw: $selectedInputDeviceIDRaw,
                interactionSoundsEnabled: $interactionSoundsEnabled,
                muteSystemAudioWhileRecording: $muteSystemAudioWhileRecording,
                systemAudioPermissionMessage: systemAudioPermissionMessage,
                interactionSoundPreset: interactionSoundPresetSelection,
                onTrySound: { interactionSoundPlayer.playPreview(preset: interactionSoundPreset) }
            )

            GeneralTranscriptionUICard(
                overlayPosition: overlayPosition,
                overlayCardOpacity: $overlayCardOpacity,
                overlayCardCornerRadius: $overlayCardCornerRadius,
                overlayScreenEdgeInset: $overlayScreenEdgeInset
            )

            GeneralLanguagesCard(
                interfaceLanguage: interfaceLanguageSelection,
                translationTargetLanguage: translationTargetLanguage,
                userMainLanguageSummary: userMainLanguageSummary,
                onEditUserMainLanguage: { isUserMainLanguageSheetPresented = true }
            )

            GeneralModelStorageCard(
                displayPath: modelStorageDisplayPath.isEmpty ? ModelStorageDirectoryManager.defaultRootURL.path : modelStorageDisplayPath,
                errorMessage: modelStorageSelectionError,
                onOpenFinder: {
                    Task { @MainActor in
                        ModelStorageDirectoryManager.openRootInFinder()
                    }
                },
                onChoose: chooseModelStorageDirectory
            )

            GeneralOutputCard(
                autoCopyWhenNoFocusedInput: $autoCopyWhenNoFocusedInput,
                translateSelectedTextOnTranslationHotkey: $translateSelectedTextOnTranslationHotkey,
                meetingNotesBetaEnabled: $meetingNotesBetaEnabled,
                appEnhancementEnabled: $appEnhancementEnabled
            )

            GeneralLoggingCard(
                hotkeyDebugLoggingEnabled: $hotkeyDebugLoggingEnabled,
                llmDebugLoggingEnabled: $llmDebugLoggingEnabled
            )

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
        }
        .onAppear {
            refreshInputDevices()
            if selectedInputDeviceIDRaw == 0,
               let defaultDeviceID = AudioInputDeviceManager.defaultInputDeviceID() {
                selectedInputDeviceIDRaw = Int(defaultDeviceID)
            }

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
            AppBehaviorController.applyDockVisibility(showInDock: showInDock)
            refreshModelStorageDisplayPath()
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
            AppBehaviorController.applyDockVisibility(showInDock: newValue)
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
        .onChange(of: selectedInputDeviceIDRaw) { _, _ in
            NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
        }
        .onChange(of: modelStorageRootPath) { _, _ in
            refreshModelStorageDisplayPath()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtAudioInputDevicesDidChange)) { _ in
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
        .id(interfaceLanguageRaw)
    }

    private func refreshInputDevices() {
        inputDevices = AudioInputDeviceManager.availableInputDevices()
        if inputDevices.isEmpty {
            selectedInputDeviceIDRaw = 0
            return
        }

        let selectedExists = inputDevices.contains(where: { Int($0.id) == selectedInputDeviceIDRaw })
        if !selectedExists,
           let defaultDeviceID = AudioInputDeviceManager.defaultInputDeviceID(),
           inputDevices.contains(where: { $0.id == defaultDeviceID }) {
            selectedInputDeviceIDRaw = Int(defaultDeviceID)
        } else if !selectedExists, let first = inputDevices.first {
            selectedInputDeviceIDRaw = Int(first.id)
        }
    }

    private var interactionSoundPreset: InteractionSoundPreset {
        InteractionSoundPreset(rawValue: interactionSoundPresetRaw) ?? .soft
    }

    private var interfaceLanguage: AppInterfaceLanguage {
        AppInterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .system
    }

    private func chooseModelStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = ModelStorageDirectoryManager.resolvedRootURL()
        panel.prompt = String(localized: "Choose")

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        do {
            try ModelStorageDirectoryManager.saveUserSelectedRootURL(selectedURL)
            modelStorageSelectionError = nil
            refreshModelStorageDisplayPath()
        } catch {
            let format = NSLocalizedString("Failed to update model storage path: %@", comment: "")
            modelStorageSelectionError = String(format: format, error.localizedDescription)
        }
    }

    private func refreshModelStorageDisplayPath() {
        let resolved = ModelStorageDirectoryManager.resolvedRootURL().path
        modelStorageDisplayPath = resolved
        if modelStorageRootPath != resolved {
            modelStorageRootPath = resolved
        }
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
            AppBehaviorController.applyDockVisibility(showInDock: defaults.bool(forKey: AppPreferenceKey.showInDock))
            try? AppBehaviorController.setLaunchAtLogin(defaults.bool(forKey: AppPreferenceKey.launchAtLogin))
            appUpdateManager.syncAutomaticallyChecksForUpdates(defaults.bool(forKey: AppPreferenceKey.autoCheckForUpdates))
            NotificationCenter.default.post(name: .voxtConfigurationDidImport, object: nil)
            NotificationCenter.default.post(name: .voxtInterfaceLanguageDidChange, object: nil)
            NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
            NotificationCenter.default.post(name: .voxtOverlayAppearanceDidChange, object: nil)
            refreshInputDevices()
            refreshModelStorageDisplayPath()
            configurationTransferMessage = String(localized: "Configuration imported successfully. Included dictionary data was restored, and sensitive fields need to be filled in again if required.")
        } catch {
            configurationTransferMessage = String(format: NSLocalizedString("Configuration import failed: %@", comment: ""), error.localizedDescription)
        }
    }

    private func postOverlayAppearanceDidChange() {
        NotificationCenter.default.post(name: .voxtOverlayAppearanceDidChange, object: nil)
    }
}

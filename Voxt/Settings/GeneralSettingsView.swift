import SwiftUI
import CoreAudio
import AppKit
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    let appUpdateManager: AppUpdateManager
    @AppStorage(AppPreferenceKey.selectedInputDeviceID) private var selectedInputDeviceIDRaw = 0
    @AppStorage(AppPreferenceKey.interactionSoundsEnabled) private var interactionSoundsEnabled = true
    @AppStorage(AppPreferenceKey.interactionSoundPreset) private var interactionSoundPresetRaw = InteractionSoundPreset.soft.rawValue
    @AppStorage(AppPreferenceKey.overlayPosition) private var overlayPositionRaw = OverlayPosition.bottom.rawValue
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.translationTargetLanguage) private var translationTargetLanguageRaw = TranslationTargetLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.translateSelectedTextOnTranslationHotkey) private var translateSelectedTextOnTranslationHotkey = true
    @AppStorage(AppPreferenceKey.autoCopyWhenNoFocusedInput) private var autoCopyWhenNoFocusedInput = false
    @AppStorage(AppPreferenceKey.appEnhancementEnabled) private var appEnhancementEnabled = false
    @AppStorage(AppPreferenceKey.actionAssistantEnabled) private var actionAssistantEnabled = false
    @AppStorage(AppPreferenceKey.actionAssistantLoggingEnabled) private var actionAssistantLoggingEnabled = false
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

    private var selectedInputDeviceID: AudioDeviceID {
        AudioDeviceID(selectedInputDeviceIDRaw)
    }

    private var networkProxyMode: Binding<VoxtNetworkSession.ProxyMode> {
        Binding(
            get: { VoxtNetworkSession.ProxyMode(rawValue: networkProxyModeRaw) ?? .system },
            set: { networkProxyModeRaw = $0.rawValue }
        )
    }

    private var customProxyScheme: Binding<VoxtNetworkSession.ProxyScheme> {
        Binding(
            get: { VoxtNetworkSession.ProxyScheme(rawValue: customProxySchemeRaw) ?? .http },
            set: { customProxySchemeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configuration")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Button("Export Configuration") {
                            exportConfiguration()
                        }
                        Button("Import Configuration") {
                            importConfiguration()
                        }
                    }

                    Text("Export your current general, model, app branch, and hotkey settings to a JSON file. Sensitive fields are replaced with placeholders during export and must be filled in again after import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let configurationTransferMessage {
                        Text(configurationTransferMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio")
                        .font(.headline)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Microphone")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Microphone", selection: $selectedInputDeviceIDRaw) {
                            ForEach(inputDevices) { device in
                                Text(device.name).tag(Int(device.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 260, alignment: .trailing)
                    }

                    Toggle("Interaction Sounds", isOn: $interactionSoundsEnabled)
                    Text("Play a short start chime when recording begins and an end chime when transcription completes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Sound Preset")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Sound Preset", selection: $interactionSoundPresetRaw) {
                            ForEach(InteractionSoundPreset.allCases) { preset in
                                Text(preset.titleKey).tag(preset.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.regular)
                        .labelsHidden()
                        .frame(width: 220, alignment: .trailing)

                        Button("Try Sound") {
                            interactionSoundPlayer.playPreview(preset: interactionSoundPreset)
                        }
                        .controlSize(.regular)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transcription UI")
                        .font(.headline)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Position")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Position", selection: $overlayPositionRaw) {
                            ForEach(OverlayPosition.allCases) { position in
                                Text(position.titleKey).tag(position.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180, alignment: .trailing)
                    }

                    Text("Controls where the floating transcription overlay appears on screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Interface Language")
                        .font(.headline)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Language")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Language", selection: $interfaceLanguageRaw) {
                            ForEach(AppInterfaceLanguage.allCases) { language in
                                Text(language.titleKey).tag(language.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220, alignment: .trailing)
                    }

                    Text("Supports English, Chinese, and Japanese. Unsupported system languages default to English.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Translation")
                        .font(.headline)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Target language")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Target language", selection: $translationTargetLanguageRaw) {
                            ForEach(TranslationTargetLanguage.allCases) { language in
                                Text(language.titleKey).tag(language.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220, alignment: .trailing)
                    }

                    Text("Used by the dedicated translation shortcut (fn + Left Shift).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Model Storage")
                        .font(.headline)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Storage Path")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            ModelStorageDirectoryManager.openRootInFinder()
                        } label: {
                            Text(modelStorageDisplayPath.isEmpty ? ModelStorageDirectoryManager.defaultRootURL.path : modelStorageDisplayPath)
                                .underline()
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .multilineTextAlignment(.trailing)
                        }
                        .buttonStyle(.plain)

                        Button("Choose") {
                            chooseModelStorageDirectory()
                        }
                        .controlSize(.small)
                    }

                    Text("New model downloads in Model settings are stored in this folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("After switching to a new path, previously downloaded models won't be detected and must be downloaded again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let modelStorageSelectionError {
                        Text(modelStorageSelectionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Output")
                        .font(.headline)

                    Toggle("Also copy result to clipboard", isOn: $autoCopyWhenNoFocusedInput)
                    Text("When enabled, Voxt auto-pastes result text and also keeps it in clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Translate selected text with translation shortcut", isOn: $translateSelectedTextOnTranslationHotkey)
                    Text("When enabled, pressing the translation shortcut with selected text translates the selection directly and replaces it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: $appEnhancementEnabled) {
                        HStack(spacing: 8) {
                            Text("App Enhancement")
                            Text("Beta")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.15))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                                )
                        }
                    }
                    Text("Show the App Enhancement menu and enable app-based enhancement configuration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: $actionAssistantEnabled) {
                        HStack(spacing: 8) {
                            Text("Action Assistant")
                            Text("Beta")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.15))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                                )
                        }
                    }
                    Text("Enable Voxt's embedded action assistant flow and show the Action Assistant settings tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Logging")
                        .font(.headline)

                    Toggle("Enable hotkey debug logs", isOn: $hotkeyDebugLoggingEnabled)
                    Text("When enabled, Voxt writes detailed hotkey detection and routing logs. Disabled by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Enable LLM debug logs", isOn: $llmDebugLoggingEnabled)
                    Text("When enabled, Voxt writes detailed local and remote LLM request logs. Disabled by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Enable Action Assistant logs", isOn: $actionAssistantLoggingEnabled)
                    Text("When enabled, Voxt writes detailed planning, execution, and verification logs for Action Assistant. Disabled by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("App Behavior")
                        .font(.headline)

                    Toggle("Launch at Login", isOn: $launchAtLogin)
                    Text("Automatically start Voxt when your Mac starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Show in Dock", isOn: $showInDock)
                    Text("Show Voxt in your Mac Dock for quick access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                    Text("Let Sparkle periodically check for updates in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Proxy")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Proxy", selection: networkProxyMode) {
                            Text("Follow System").tag(VoxtNetworkSession.ProxyMode.system)
                            Text("Off").tag(VoxtNetworkSession.ProxyMode.disabled)
                            Text("Custom").tag(VoxtNetworkSession.ProxyMode.custom)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220, alignment: .trailing)
                    }
                    Text("Follow the macOS proxy settings, disable proxy use entirely, or provide a custom proxy endpoint for Voxt network requests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if networkProxyMode.wrappedValue == .custom {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Protocol")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("Protocol", selection: customProxyScheme) {
                                Text("HTTP").tag(VoxtNetworkSession.ProxyScheme.http)
                                Text("HTTPS").tag(VoxtNetworkSession.ProxyScheme.https)
                                Text("SOCKS5").tag(VoxtNetworkSession.ProxyScheme.socks5)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 160, alignment: .trailing)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Host")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("127.0.0.1", text: $customProxyHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Port")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("7890", text: $customProxyPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Username")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("Optional", text: $customProxyUsername)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Password")
                                .foregroundStyle(.secondary)
                            Spacer()
                            SecureField("Optional", text: $customProxyPassword)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }

                        Text("Custom proxy supports HTTP, HTTPS, and SOCKS5 host/port routing. Username and password are saved now, but not injected into requests automatically yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
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
            autoCheckForUpdates = appUpdateManager.automaticallyChecksForUpdates
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
            appUpdateManager.automaticallyChecksForUpdates = newValue
        }
        .onChange(of: interfaceLanguageRaw) { _, _ in
            NotificationCenter.default.post(name: .voxtInterfaceLanguageDidChange, object: nil)
        }
        .onChange(of: modelStorageRootPath) { _, _ in
            refreshModelStorageDisplayPath()
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
            NotificationCenter.default.post(name: .voxtConfigurationDidImport, object: nil)
            NotificationCenter.default.post(name: .voxtInterfaceLanguageDidChange, object: nil)
            refreshInputDevices()
            refreshModelStorageDisplayPath()
            configurationTransferMessage = String(localized: "Configuration imported successfully. Sensitive fields need to be filled in again if required.")
        } catch {
            configurationTransferMessage = String(format: NSLocalizedString("Configuration import failed: %@", comment: ""), error.localizedDescription)
        }
    }
}

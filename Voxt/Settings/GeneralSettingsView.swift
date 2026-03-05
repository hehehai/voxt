import SwiftUI
import CoreAudio

struct GeneralSettingsView: View {
    let appUpdateManager: AppUpdateManager
    @AppStorage(AppPreferenceKey.selectedInputDeviceID) private var selectedInputDeviceIDRaw = 0
    @AppStorage(AppPreferenceKey.interactionSoundsEnabled) private var interactionSoundsEnabled = true
    @AppStorage(AppPreferenceKey.interactionSoundPreset) private var interactionSoundPresetRaw = InteractionSoundPreset.soft.rawValue
    @AppStorage(AppPreferenceKey.overlayPosition) private var overlayPositionRaw = OverlayPosition.bottom.rawValue
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.translationTargetLanguage) private var translationTargetLanguageRaw = TranslationTargetLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.autoCopyWhenNoFocusedInput) private var autoCopyWhenNoFocusedInput = false
    @AppStorage(AppPreferenceKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppPreferenceKey.showInDock) private var showInDock = false
    @AppStorage(AppPreferenceKey.autoCheckForUpdates) private var autoCheckForUpdates = true

    @State private var inputDevices: [AudioInputDevice] = []
    @State private var launchAtLoginError: String?
    @State private var isSyncingLaunchAtLoginState = false
    @State private var interactionSoundPlayer = InteractionSoundPlayer()

    private var selectedInputDeviceID: AudioDeviceID {
        AudioDeviceID(selectedInputDeviceIDRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        .frame(width: 260)
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
                    Text("Output")
                        .font(.headline)

                    Toggle("Also copy result to clipboard", isOn: $autoCopyWhenNoFocusedInput)
                    Text("When enabled, Voxt auto-pastes result text and also keeps it in clipboard.")
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
}

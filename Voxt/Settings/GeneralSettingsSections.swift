import SwiftUI

struct GeneralConfigurationCard: View {
    let message: String?
    let onExport: () -> Void
    let onImport: () -> Void
    let onOpenSetupGuide: (() -> Void)?

    var body: some View {
        GeneralSettingsCard(title: "Configuration") {
            HStack(spacing: 8) {
                Button("Export Configuration", action: onExport)
                    .buttonStyle(SettingsPillButtonStyle())
                Button("Import Configuration", action: onImport)
                    .buttonStyle(SettingsPillButtonStyle())
                if let onOpenSetupGuide {
                    Button("Open Setup Guide", action: onOpenSetupGuide)
                        .buttonStyle(SettingsPillButtonStyle())
                }
            }

            Text("Export your current general, model, dictionary, voice end command, app branch, and hotkey settings to a JSON file. Sensitive fields are replaced with placeholders during export and must be filled in again after import.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GeneralAudioCard: View {
    let microphoneState: MicrophoneResolvedState
    @Binding var interactionSoundsEnabled: Bool
    @Binding var muteSystemAudioWhileRecording: Bool
    let systemAudioPermissionMessage: String?
    @Binding var interactionSoundPreset: InteractionSoundPreset
    let onTrySound: () -> Void
    let onManageMicrophones: () -> Void
    let onViewPriorityList: () -> Void

    var body: some View {
        GeneralSettingsCard(title: "Audio") {
            HStack(alignment: .center) {
                Text("Microphone")
                    .foregroundStyle(.secondary)
                Spacer()
                if microphoneState.hasAvailableDevices {
                    SettingsSelectionButton(width: 272, action: onManageMicrophones) {
                        HStack(spacing: 0) {
                            Text(microphoneState.activeDevice?.name ?? String(localized: "No available microphone devices"))
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text(String(localized: "No available microphone devices"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.red.opacity(0.10))
                        )
                }
            }

            Text("Reorder microphones to control device priority. Auto Switch only applies when devices connect or disconnect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !microphoneState.hasAvailableDevices, microphoneState.hasTrackedDevices {
                HStack {
                    Spacer()
                    Button("View Priority List", action: onViewPriorityList)
                        .buttonStyle(SettingsPillButtonStyle())
                }
            }

            Toggle("Interaction Sounds", isOn: $interactionSoundsEnabled)
            Text("Play a short start chime when recording begins and an end chime when transcription completes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Mute other media audio while recording", isOn: $muteSystemAudioWhileRecording)
            Text("When enabled, Voxt requests system audio recording permission so it can mute other apps' media audio during recording and restore it after transcription completes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let systemAudioPermissionMessage {
                Text(systemAudioPermissionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center) {
                Text("Sound Preset")
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsMenuPicker(
                    selection: $interactionSoundPreset,
                    options: InteractionSoundPreset.allCases.map { preset in
                        SettingsMenuOption(value: preset, title: preset.title)
                    },
                    selectedTitle: interactionSoundPreset.title,
                    width: 220
                )

                Button("Try Sound", action: onTrySound)
                    .buttonStyle(SettingsPillButtonStyle())
            }
        }
    }
}

struct GeneralTranscriptionUICard: View {
    @Binding var overlayPosition: OverlayPosition
    @Binding var overlayCardOpacity: Int
    @Binding var overlayCardCornerRadius: Int
    @Binding var overlayScreenEdgeInset: Int
    @Binding var meetingNotesBetaEnabled: Bool
    @Binding var hideMeetingOverlayFromScreenSharing: Bool

    var body: some View {
        GeneralSettingsCard(title: "Transcription UI") {
            HStack(alignment: .center) {
                Text("Position")
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsMenuPicker(
                    selection: $overlayPosition,
                    options: OverlayPosition.allCases.map { position in
                        SettingsMenuOption(value: position, title: position.title)
                    },
                    selectedTitle: overlayPosition.title,
                    width: 180
                )
            }

            overlayNumberField(
                title: "Opacity",
                value: $overlayCardOpacity,
                range: 0...100,
                width: 90,
                unit: "%"
            )

            overlayNumberField(
                title: "Corner Radius",
                value: $overlayCardCornerRadius,
                range: 0...40,
                width: 90,
                unit: "pt"
            )

            overlayNumberField(
                title: "Edge Distance",
                value: $overlayScreenEdgeInset,
                range: 0...120,
                width: 90,
                unit: "pt"
            )

            if meetingNotesBetaEnabled {
                Toggle(isOn: $hideMeetingOverlayFromScreenSharing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meeting Transcript UI Shareable")
                        Text("Leave this off to keep the meeting transcript overlay private. Turn it on if you want the UI to appear in screen sharing or screen recordings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func overlayNumberField(
        title: LocalizedStringKey,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        width: CGFloat,
        unit: String
    ) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                ClampedIntegerTextField(
                    value: value,
                    range: range,
                    width: width
                )

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ClampedIntegerTextField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let width: CGFloat

    @State private var text: String

    init(value: Binding<Int>, range: ClosedRange<Int>, width: CGFloat) {
        _value = value
        self.range = range
        self.width = width
        _text = State(initialValue: String(min(max(value.wrappedValue, range.lowerBound), range.upperBound)))
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .settingsFieldSurface(width: width, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            .onChange(of: text) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                guard !digits.isEmpty else {
                    return
                }

                let parsed = Int(digits) ?? range.lowerBound
                let clamped = min(max(parsed, range.lowerBound), range.upperBound)
                value = clamped

                let clampedText = String(clamped)
                if text != clampedText {
                    text = clampedText
                }
            }
            .onSubmit {
                syncTextToValue()
            }
            .onChange(of: value) { _, newValue in
                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                let normalized = String(clamped)
                if text != normalized {
                    text = normalized
                }
            }
            .onAppear {
                syncTextToValue()
            }
    }

    private func syncTextToValue() {
        let digits = text.filter(\.isNumber)
        let parsed = Int(digits) ?? value
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        value = clamped
        text = String(clamped)
    }
}

struct GeneralLanguagesCard: View {
    @Binding var interfaceLanguage: AppInterfaceLanguage
    let userMainLanguageSummary: String
    let onEditUserMainLanguage: () -> Void

    var body: some View {
        GeneralSettingsCard(title: "Languages", spacing: 14) {
            GeneralLanguageSettingBlock(
                title: "Interface Language",
                description: "Supports English, Chinese, and Japanese. Unsupported system languages default to English."
            ) {
                SettingsMenuPicker(
                    selection: $interfaceLanguage,
                    options: AppInterfaceLanguage.allCases.map { language in
                        SettingsMenuOption(value: language, title: language.title)
                    },
                    selectedTitle: interfaceLanguage.title,
                    width: 220
                )
            }

            Divider()

            GeneralLanguageSettingBlock(
                title: "User Main Language",
                description: "Used for the {{USER_MAIN_LANGUAGE}} prompt variable in enhancement and translation. You can select multiple languages and mark one as primary."
            ) {
                SettingsSelectionButton(width: 220, action: onEditUserMainLanguage) {
                    HStack(spacing: 0) {
                        Text(userMainLanguageSummary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }
}

struct GeneralModelStorageCard: View {
    let displayPath: String
    let errorMessage: String?
    let onOpenFinder: () -> Void
    let onChoose: () -> Void

    var body: some View {
        GeneralSettingsCard(title: "Model Storage") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Storage Path")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onOpenFinder) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.caption)
                        Text(displayPath)
                            .underline()
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                    }
                }
                .buttonStyle(SettingsInlineSelectorButtonStyle())
                .help("Open folder")

                Button("Choose", action: onChoose)
                    .buttonStyle(SettingsPillButtonStyle())
            }

            Text("New model downloads in Model settings are stored in this folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("After switching to a new path, previously downloaded models won't be detected and must be downloaded again.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct GeneralOutputCard: View {
    @Binding var autoCopyWhenNoFocusedInput: Bool
    @Binding var translateSelectedTextOnTranslationHotkey: Bool

    var body: some View {
        GeneralSettingsCard(title: "Output") {
            Toggle("Also copy result to clipboard", isOn: $autoCopyWhenNoFocusedInput)
            Text("When enabled, Voxt auto-pastes result text and also keeps it in clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Translate selected text with translation shortcut", isOn: $translateSelectedTextOnTranslationHotkey)
            Text("When enabled, pressing the translation shortcut with selected text translates the selection directly and replaces it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct GeneralLoggingCard: View {
    @Binding var hotkeyDebugLoggingEnabled: Bool
    @Binding var llmDebugLoggingEnabled: Bool

    var body: some View {
        GeneralSettingsCard(title: "Logging") {
            Toggle("Enable hotkey debug logs", isOn: $hotkeyDebugLoggingEnabled)
            Text("When enabled, Voxt writes detailed hotkey detection and routing logs. Disabled by default.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Enable LLM debug logs", isOn: $llmDebugLoggingEnabled)
            Text("When enabled, Voxt writes detailed local and remote LLM request logs. Disabled by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct GeneralAppBehaviorCard: View {
    @Binding var launchAtLogin: Bool
    @Binding var showInDock: Bool
    @Binding var autoCheckForUpdates: Bool
    @Binding var networkProxyMode: VoxtNetworkSession.ProxyMode
    @Binding var customProxyScheme: VoxtNetworkSession.ProxyScheme
    @Binding var customProxyHost: String
    @Binding var customProxyPort: String
    @Binding var customProxyUsername: String
    @Binding var customProxyPassword: String
    let launchAtLoginError: String?

    var body: some View {
        GeneralSettingsCard(title: "App Behavior") {
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

            HStack(alignment: .center) {
                Text("Proxy")
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsMenuPicker(
                    selection: $networkProxyMode,
                    options: [
                        SettingsMenuOption(value: .system, title: String(localized: "Follow System")),
                        SettingsMenuOption(value: .disabled, title: String(localized: "Off")),
                        SettingsMenuOption(value: .custom, title: String(localized: "Custom"))
                    ],
                    selectedTitle: networkProxyModeTitle,
                    width: 220
                )
            }
            Text("Follow the macOS proxy settings, disable proxy use entirely, or provide a custom proxy endpoint for Voxt network requests.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if networkProxyMode == .custom {
                HStack(alignment: .center) {
                    Text("Protocol")
                        .foregroundStyle(.secondary)
                    Spacer()
                    SettingsMenuPicker(
                        selection: $customProxyScheme,
                        options: [
                            SettingsMenuOption(value: .http, title: "HTTP"),
                            SettingsMenuOption(value: .https, title: "HTTPS"),
                            SettingsMenuOption(value: .socks5, title: "SOCKS5")
                        ],
                        selectedTitle: customProxySchemeTitle,
                        width: 160
                    )
                }

                proxyField(title: "Host", placeholder: "127.0.0.1", text: $customProxyHost, width: 220)
                proxyField(title: "Port", placeholder: "7890", text: $customProxyPort, width: 120)
                proxyField(title: "Username", placeholder: "Optional", text: $customProxyUsername, width: 220)

                HStack(alignment: .center) {
                    Text("Password")
                        .foregroundStyle(.secondary)
                    Spacer()
                    SecureField("Optional", text: $customProxyPassword)
                        .textFieldStyle(.plain)
                        .settingsFieldSurface(width: 220)
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
    }

    private func proxyField(title: LocalizedStringKey, placeholder: String, text: Binding<String>, width: CGFloat) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .settingsFieldSurface(width: width)
        }
    }
}

private extension GeneralAppBehaviorCard {
    var networkProxyModeTitle: String {
        switch networkProxyMode {
        case .system:
            return String(localized: "Follow System")
        case .disabled:
            return String(localized: "Off")
        case .custom:
            return String(localized: "Custom")
        }
    }

    var customProxySchemeTitle: String {
        switch customProxyScheme {
        case .http:
            return "HTTP"
        case .https:
            return "HTTPS"
        case .socks5:
            return "SOCKS5"
        }
    }
}

struct GeneralSettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        title: LocalizedStringKey,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .settingsCardSurface()
    }
}

struct GeneralLanguageSettingBlock<Control: View>: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                control()
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

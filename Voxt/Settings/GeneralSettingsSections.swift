import SwiftUI

struct GeneralConfigurationCard: View {
    let message: String?
    let onExport: () -> Void
    let onImport: () -> Void

    var body: some View {
        GeneralSettingsCard(title: "Configuration") {
            HStack(spacing: 8) {
                Button("Export Configuration", action: onExport)
                Button("Import Configuration", action: onImport)
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
    let inputDevices: [AudioInputDevice]
    @Binding var selectedInputDeviceIDRaw: Int
    @Binding var interactionSoundsEnabled: Bool
    @Binding var muteSystemAudioWhileRecording: Bool
    let systemAudioPermissionMessage: String?
    @Binding var interactionSoundPreset: InteractionSoundPreset
    let onTrySound: () -> Void

    var body: some View {
        GeneralSettingsCard(title: "Audio") {
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

            Toggle("Mute other media audio while recording", isOn: $muteSystemAudioWhileRecording)
            Text("When enabled, Voxt requests system audio recording permission so it can mute other apps' media audio during recording and restore it after transcription completes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let systemAudioPermissionMessage {
                Text(systemAudioPermissionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Sound Preset")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Sound Preset", selection: $interactionSoundPreset) {
                    ForEach(InteractionSoundPreset.allCases, id: \.rawValue) { preset in
                        Text(preset.titleKey).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.regular)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)

                Button("Try Sound", action: onTrySound)
                    .controlSize(.regular)
            }
        }
    }
}

struct AgentMCPSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let statusTitle: String
    let statusDetail: String
    let endpoint: String
    let claudeCommand: String
    let codexCommand: String
    let testMessage: String?
    let isTestingConnection: Bool
    let copiedClaudeCommand: Bool
    let copiedCodexCommand: Bool
    @Binding var port: Int
    @Binding var historyEnabled: Bool
    let onRefreshStatus: () -> Void
    let onCopyClaudeCommand: () -> Void
    let onCopyCodexCommand: () -> Void
    let onTestConnection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(AppLocalization.localizedString("MCP Server"))
                    .font(.title3.weight(.semibold))
                statusBadge
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(AppLocalization.localizedString("Close"), systemImage: "xmark")
                }
                .controlSize(.small)
            }

            GeneralSettingsCard(
                title: "Server",
                spacing: 10,
                headerAccessory: {
                    Button(action: onRefreshStatus) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(AppLocalization.localizedString("Refresh Status")))
                    .help(AppLocalization.localizedString("Refresh Status"))
                }
            ) {
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline) {
                    Text(AppLocalization.localizedString("Port"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ClampedIntegerTextField(
                        value: $port,
                        range: 1024...65535,
                        width: 110
                    )
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(AppLocalization.localizedString("Endpoint"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(endpoint)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }

                Divider()

                HStack(alignment: .center, spacing: 8) {
                    Toggle(AppLocalization.localizedString("Save agent answers to History"), isOn: $historyEnabled)

                    InfoPopoverButton(
                        message: AppLocalization.localizedString("Agent answers never go back into the current input field. Enable this only if you want voice answers kept in Voxt history.")
                    )
                }
            }

            GeneralSettingsCard(title: "Connect", spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        onTestConnection()
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(
                                isTestingConnection
                                    ? AppLocalization.localizedString("Testing...")
                                    : AppLocalization.localizedString("Test Connection")
                            )
                        }
                    }
                    .disabled(isTestingConnection)

                    if let testMessage, !testMessage.isEmpty {
                        Text(testMessage)
                            .font(.caption)
                            .foregroundStyle(testMessageColor)
                            .lineLimit(2)
                    }
                }

                commandBlock(
                    title: AppLocalization.localizedString("Claude Code"),
                    command: claudeCommand,
                    isCopied: copiedClaudeCommand,
                    onCopy: onCopyClaudeCommand
                )
                commandBlock(
                    title: AppLocalization.localizedString("Codex"),
                    command: codexCommand,
                    isCopied: copiedCodexCommand,
                    onCopy: onCopyCodexCommand
                )

                Divider()

                Text(AppLocalization.localizedString("Enable this server to let Claude Code or Codex ask you questions in Voxt and receive your spoken answer as text."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(AppLocalization.localizedString("After it shows Running, add the endpoint to your client with one of the commands above. If startup fails, the status here will show the reason directly."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 560)
    }

    private var statusBadge: some View {
        Text(statusTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(statusBadgeForegroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(statusBadgeBackgroundColor)
            )
            .overlay(
                Capsule()
                    .stroke(statusBadgeStrokeColor, lineWidth: 1)
            )
    }

    private func commandBlock(
        title: String,
        command: String,
        isCopied: Bool,
        onCopy: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                AnswerHeaderActionButton(
                    accessibilityLabel: AppLocalization.localizedString("Copy"),
                    action: onCopy
                ) {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "document.on.document")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isCopied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

    private var statusBadgeBackgroundColor: Color {
        switch normalizedStatusKind {
        case .running:
            return Color.green.opacity(0.14)
        case .starting:
            return Color.orange.opacity(0.14)
        case .portInUse, .permissionBlocked, .error:
            return Color.red.opacity(0.12)
        case .stopped:
            return Color.secondary.opacity(0.12)
        }
    }

    private var statusBadgeStrokeColor: Color {
        switch normalizedStatusKind {
        case .running:
            return Color.green.opacity(0.35)
        case .starting:
            return Color.orange.opacity(0.35)
        case .portInUse, .permissionBlocked, .error:
            return Color.red.opacity(0.3)
        case .stopped:
            return Color.secondary.opacity(0.24)
        }
    }

    private var statusBadgeForegroundColor: Color {
        switch normalizedStatusKind {
        case .running:
            return Color.green
        case .starting:
            return Color.orange
        case .portInUse, .permissionBlocked, .error:
            return Color.red
        case .stopped:
            return Color.secondary
        }
    }

    private var testMessageColor: Color {
        let lowercased = testMessage?.lowercased() ?? ""
        if lowercased.contains("succeeded") || lowercased.contains("成功") || lowercased.contains("成功しました") {
            return .green
        }
        if isTestingConnection {
            return .secondary
        }
        return .secondary
    }

    private var normalizedStatusKind: MCPStatusKind {
        switch statusTitle {
        case AppLocalization.localizedString("Running"):
            return .running
        case AppLocalization.localizedString("Starting"):
            return .starting
        case AppLocalization.localizedString("Port in Use"):
            return .portInUse
        case AppLocalization.localizedString("Permission Blocked"):
            return .permissionBlocked
        case AppLocalization.localizedString("Error"):
            return .error
        default:
            return .stopped
        }
    }
}

private struct InfoPopoverButton: View {
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.leading)
                .frame(width: 260, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
    }
}

private enum MCPStatusKind {
    case stopped
    case starting
    case running
    case portInUse
    case permissionBlocked
    case error
}

struct GeneralTranscriptionUICard: View {
    @Binding var overlayPosition: OverlayPosition
    @Binding var overlayCardOpacity: Int
    @Binding var overlayCardCornerRadius: Int
    @Binding var overlayScreenEdgeInset: Int

    var body: some View {
        GeneralSettingsCard(title: "Transcription UI") {
            HStack(alignment: .firstTextBaseline) {
                Text("Position")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Position", selection: $overlayPosition) {
                    ForEach(OverlayPosition.allCases, id: \.rawValue) { position in
                        Text(position.titleKey).tag(position)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180, alignment: .trailing)
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
        }
    }

    private func overlayNumberField(
        title: LocalizedStringKey,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        width: CGFloat,
        unit: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
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
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
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
    @Binding var translationTargetLanguage: TranslationTargetLanguage
    let userMainLanguageSummary: String
    let onEditUserMainLanguage: () -> Void

    var body: some View {
        GeneralSettingsCard(title: "Languages", spacing: 14) {
            GeneralLanguageSettingBlock(
                title: "Interface Language",
                description: "Supports English, Chinese, and Japanese. Unsupported system languages default to English."
            ) {
                Picker("Language", selection: $interfaceLanguage) {
                    ForEach(AppInterfaceLanguage.allCases, id: \.rawValue) { language in
                        Text(language.titleKey).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            Divider()

            GeneralLanguageSettingBlock(
                title: "User Main Language",
                description: "Used for the {{USER_MAIN_LANGUAGE}} prompt variable in enhancement and translation. You can select multiple languages and mark one as primary."
            ) {
                Button(action: onEditUserMainLanguage) {
                    HStack(spacing: 8) {
                        Text(userMainLanguageSummary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()

            GeneralLanguageSettingBlock(
                title: "Translation",
                description: "Used by the dedicated translation shortcut (fn + Left Shift)."
            ) {
                Picker("Target language", selection: $translationTargetLanguage) {
                    ForEach(TranslationTargetLanguage.allCases, id: \.rawValue) { language in
                        Text(language.titleKey).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
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
                .buttonStyle(.plain)
                .help("Open folder")

                Button("Choose", action: onChoose)
                    .controlSize(.small)
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
    @Binding var appEnhancementEnabled: Bool
    @Binding var agentMCPEnabled: Bool
    let showMCPSettingsButton: Bool
    let onOpenMCPSettings: () -> Void

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

            HStack(alignment: .center, spacing: 8) {
                Toggle(isOn: $agentMCPEnabled) {
                    HStack(spacing: 8) {
                        Text(AppLocalization.localizedString("MCP Server"))
                        if agentMCPEnabled {
                            Text(AppLocalization.localizedString("MCP"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.12))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }

                Spacer(minLength: 8)

                if showMCPSettingsButton {
                    Button(action: onOpenMCPSettings) {
                        Label(AppLocalization.localizedString("Settings"), systemImage: "gearshape")
                    }
                    .controlSize(.small)
                }
            }
            Text(AppLocalization.localizedString("When enabled, Voxt exposes a local MCP endpoint so Claude Code and Codex can ask you questions by voice."))
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

            HStack(alignment: .firstTextBaseline) {
                Text("Proxy")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Proxy", selection: $networkProxyMode) {
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

            if networkProxyMode == .custom {
                HStack(alignment: .firstTextBaseline) {
                    Text("Protocol")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Protocol", selection: $customProxyScheme) {
                        Text("HTTP").tag(VoxtNetworkSession.ProxyScheme.http)
                        Text("HTTPS").tag(VoxtNetworkSession.ProxyScheme.https)
                        Text("SOCKS5").tag(VoxtNetworkSession.ProxyScheme.socks5)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 160, alignment: .trailing)
                }

                proxyField(title: "Host", placeholder: "127.0.0.1", text: $customProxyHost, width: 220)
                proxyField(title: "Port", placeholder: "7890", text: $customProxyPort, width: 120)
                proxyField(title: "Username", placeholder: "Optional", text: $customProxyUsername, width: 220)

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
    }

    private func proxyField(title: LocalizedStringKey, placeholder: String, text: Binding<String>, width: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }
}

private struct GeneralSettingsCard<Content: View, HeaderAccessory: View>: View {
    let title: LocalizedStringKey
    let spacing: CGFloat
    @ViewBuilder let headerAccessory: () -> HeaderAccessory
    @ViewBuilder let content: () -> Content

    init(
        title: LocalizedStringKey,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) where HeaderAccessory == EmptyView {
        self.title = title
        self.spacing = spacing
        self.headerAccessory = { EmptyView() }
        self.content = content
    }

    init(
        title: LocalizedStringKey,
        spacing: CGFloat = 12,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.spacing = spacing
        self.headerAccessory = headerAccessory
        self.content = content
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: spacing) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    headerAccessory()
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private struct GeneralLanguageSettingBlock<Control: View>: View {
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

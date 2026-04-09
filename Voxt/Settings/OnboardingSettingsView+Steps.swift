import SwiftUI
import AppKit

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

extension OnboardingSettingsView {
    @ViewBuilder
    var stepContent: some View {
        switch currentStep {
        case .language:
            languageStep
        case .model:
            modelStep
        case .transcription:
            transcriptionStep
        case .translation:
            translationStep
        case .rewrite:
            rewriteStep
        case .appEnhancement:
            appEnhancementStep
        case .meeting:
            meetingStep
        case .finish:
            finishStep
        }
    }

    var languageStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Language") {
                GeneralLanguageSettingBlock(
                    title: "Interface Language",
                    description: "Choose the language used by the main window and menu labels."
                ) {
                    SettingsMenuPicker(
                        selection: $interfaceLanguageRaw,
                        options: AppInterfaceLanguage.allCases.map { language in
                            SettingsMenuOption(value: language.rawValue, title: language.title)
                        },
                        selectedTitle: interfaceLanguage.title,
                        width: 220
                    )
                }

                Divider()

                GeneralLanguageSettingBlock(
                    title: "User Main Language",
                    description: "Used to bias transcription prompts, translation prompts, and text enhancement."
                ) {
                    SettingsSelectionButton(width: 220, action: { isUserMainLanguageSheetPresented = true }) {
                        HStack(spacing: 0) {
                            Text(userMainLanguageSummary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }

            }

            OnboardingSummaryCard(
                title: "Current Summary",
                lines: [
                    AppLocalization.format("Interface: %@", interfaceLanguage.title),
                    AppLocalization.format("Main language: %@", userMainLanguageSummary)
                ]
            )
        }
    }

    var modelStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            modelStorageCard

            GeneralSettingsCard(title: "ASR Model") {
                OnboardingSegmentedTabs(
                    selection: modelPathChoice,
                    items: OnboardingModelPathChoice.allCases.map { choice in
                        OnboardingTabItem(value: choice, title: choice.titleKey)
                    }
                )

                Text(modelPathDescription(modelPathChoice.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                switch modelPathChoice.wrappedValue {
                case .local:
                    localASRSetupContent
                case .remote:
                    remoteASRSetupContent
                case .dictation:
                    dictationASRSetupContent
                }
            }

            GeneralSettingsCard(title: "LLM Model") {
                OnboardingSegmentedTabs(
                    selection: llmPathChoice,
                    items: OnboardingTextModelPathChoice.allCases.map { choice in
                        OnboardingTabItem(value: choice, title: choice.titleKey)
                    }
                )

                Text(llmPathDescription(llmPathChoice.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch llmPathChoice.wrappedValue {
                case .local:
                    localLLMSetupContent
                case .remote:
                    remoteLLMSetupContent
                case .system:
                    systemLLMSetupContent
                }
            }
        }
    }

    var localASRSetupContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingSegmentedTabs(
                selection: localEngineSelection,
                items: [
                    OnboardingTabItem(value: TranscriptionEngine.mlxAudio, title: TranscriptionEngine.mlxAudio.titleKey),
                    OnboardingTabItem(value: TranscriptionEngine.whisperKit, title: TranscriptionEngine.whisperKit.titleKey)
                ]
            )

            Text(selectedLocalEngineDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if localEngineSelection.wrappedValue == .mlxAudio {
                LocalModelPickerCard(
                    title: "Speech Model",
                    selectionTitle: mlxModelManager.displayTitle(for: mlxModelRepo),
                    selectionDescription: modelDescription(for: mlxModelRepo),
                    isInstalled: mlxModelManager.isModelDownloaded(repo: mlxModelRepo),
                    showsCardSurface: false,
                    isInstalling: isSelectedMLXModelDownloading,
                    installLabel: "Download",
                    openLabel: "Open Folder",
                    downloadStatus: selectedMLXDownloadStatus,
                    errorMessage: selectedMLXDownloadErrorMessage,
                    onChoose: {},
                    pickerContent: {
                        SettingsMenuPicker(
                            selection: $mlxModelRepo,
                            options: MLXModelManager.availableModels.map { model in
                                SettingsMenuOption(value: model.id, title: model.title)
                            },
                            selectedTitle: mlxModelManager.displayTitle(for: mlxModelRepo),
                            width: 280
                        )
                    },
                    onInstall: {
                        Task { await mlxModelManager.downloadModel(repo: mlxModelRepo) }
                    },
                    onOpen: {
                        guard let folderURL = mlxModelManager.modelDirectoryURL(repo: mlxModelRepo) else { return }
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
                    },
                    onCancel: {
                        mlxModelManager.cancelDownload()
                    }
                )
            } else {
                LocalModelPickerCard(
                    title: "Speech Model",
                    selectionTitle: whisperModelManager.displayTitle(for: whisperModelID),
                    selectionDescription: whisperDescription(for: whisperModelID),
                    isInstalled: whisperModelManager.isModelDownloaded(id: whisperModelID),
                    showsCardSurface: false,
                    isInstalling: isSelectedWhisperModelDownloading,
                    installLabel: "Download",
                    openLabel: "Open Folder",
                    downloadStatus: selectedWhisperDownloadStatus,
                    errorMessage: selectedWhisperDownloadErrorMessage,
                    onChoose: {},
                    pickerContent: {
                        SettingsMenuPicker(
                            selection: $whisperModelID,
                            options: WhisperKitModelManager.availableModels.map { model in
                                SettingsMenuOption(value: model.id, title: AppLocalization.localizedString(model.title))
                            },
                            selectedTitle: whisperModelManager.displayTitle(for: whisperModelID),
                            width: 280
                        )
                    },
                    onInstall: {
                        Task { await whisperModelManager.downloadModel(id: whisperModelID) }
                    },
                    onOpen: {
                        guard let folderURL = whisperModelManager.modelDirectoryURL(id: whisperModelID) else { return }
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
                    },
                    onCancel: {
                        whisperModelManager.cancelDownload()
                    }
                )
            }
        }
    }

    var remoteASRSetupContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsMenuPicker(
                selection: Binding(
                    get: { selectedRemoteASRProvider.rawValue },
                    set: { newValue in
                        remoteASRSelectedProviderRaw = newValue
                        engineRaw = TranscriptionEngine.remote.rawValue
                    }
                ),
                options: RemoteASRProvider.allCases.map { provider in
                    SettingsMenuOption(value: provider.rawValue, title: provider.title)
                },
                selectedTitle: selectedRemoteASRProvider.title,
                width: 280
            )

            ProviderStatusRow(
                title: selectedRemoteASRProvider.title,
                status: remoteASRStatusText(for: selectedRemoteASRProvider),
                onConfigure: {
                    editingASRProvider = selectedRemoteASRProvider
                }
            )
        }
    }

    var dictationASRSetupContent: some View {
        OnboardingSummaryCard(
            title: "System ASR",
            lines: [
                localized("Uses the macOS system speech recognizer with no download required."),
                localized("Best for the fastest setup, but meeting support and language coverage are more limited.")
            ]
        )
    }

    var localLLMSetupContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsMenuPicker(
                selection: Binding(
                    get: { customLLMRepo },
                    set: { newValue in
                        customLLMRepo = newValue
                        translationCustomLLMRepo = newValue
                        rewriteCustomLLMRepo = newValue
                    }
                ),
                options: CustomLLMModelManager.availableModels.map { model in
                    SettingsMenuOption(value: model.id, title: model.title)
                },
                selectedTitle: customLLMManager.displayTitle(for: customLLMRepo),
                width: 280
            )

            Text(customLLMDescription(for: customLLMRepo))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if customLLMManager.isModelDownloaded(repo: customLLMRepo) {
                    Button(localized("Open Folder")) {
                        guard let folderURL = customLLMManager.modelDirectoryURL(repo: customLLMRepo) else { return }
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
                    }
                } else if isSelectedCustomLLMDownloading {
                    Button(localized("Cancel")) {
                        customLLMManager.cancelDownload()
                    }
                } else {
                    Button(localized("Download")) {
                        Task { await customLLMManager.downloadModel(repo: customLLMRepo) }
                    }
                }
            }
            .buttonStyle(SettingsPillButtonStyle())

            if let customLLMDownloadStatus {
                ModelDownloadStatusView(status: customLLMDownloadStatus)
            }

            if let customLLMDownloadErrorMessage {
                Text(customLLMDownloadErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var remoteLLMSetupContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsMenuPicker(
                selection: Binding(
                    get: { selectedRemoteLLMProvider.rawValue },
                    set: { newValue in
                        remoteLLMSelectedProviderRaw = newValue
                        translationRemoteLLMProviderRaw = newValue
                        rewriteRemoteLLMProviderRaw = newValue
                        enhancementModeRaw = EnhancementMode.remoteLLM.rawValue
                    }
                ),
                options: RemoteLLMProvider.allCases.map { provider in
                    SettingsMenuOption(value: provider.rawValue, title: provider.title)
                },
                selectedTitle: selectedRemoteLLMProvider.title,
                width: 280
            )

            ProviderStatusRow(
                title: selectedRemoteLLMProvider.title,
                status: remoteLLMStatusText(for: selectedRemoteLLMProvider),
                onConfigure: {
                    editingLLMProvider = selectedRemoteLLMProvider
                }
            )
        }
    }

    var systemLLMSetupContent: some View {
        OnboardingSummaryCard(
            title: "Apple Intelligence",
            lines: appleIntelligenceAvailable
                ? [
                    localized("Use the system model for cleanup, rewrite, and meeting summaries on this Mac."),
                    localized("Translation will keep using the best compatible model automatically.")
                ]
                : [
                    localized("Apple Intelligence is currently unavailable on this Mac."),
                    localized("You can still keep this selected and switch later after the system becomes available.")
                ]
        )
    }

    var modelStorageCard: some View {
        GeneralSettingsCard(title: "Model Storage") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(localized("Storage Path"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: openModelStorageInFinder) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.caption)
                        Text(modelStorageDisplayPath.isEmpty ? ModelStorageDirectoryManager.defaultRootURL.path : modelStorageDisplayPath)
                            .underline()
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                    }
                }
                .buttonStyle(SettingsInlineSelectorButtonStyle())
                .help(localized("Open folder"))

                Button(localized("Choose")) {
                    chooseModelStorageDirectory()
                }
                .buttonStyle(SettingsPillButtonStyle())
            }

            Text(localized("New model downloads are stored here. Switching the path will not move existing model files."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(localized("Use China mirror"), isOn: $useHfMirror)

            Text(localized("Use the China mirror when downloading local models during setup."))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let modelStorageSelectionError {
                Text(modelStorageSelectionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    var transcriptionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Audio") {
                HStack(alignment: .center) {
                    Text(localized("Microphone"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if microphoneState.hasAvailableDevices {
                        SettingsSelectionButton(width: 272, action: { isMicrophonePriorityDialogPresented = true }) {
                            HStack(spacing: 0) {
                                Text(microphoneState.activeDevice?.name ?? localized("No available microphone devices"))
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text(localized("No available microphone devices"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }

                Toggle(localized("Interaction Sounds"), isOn: $interactionSoundsEnabled)
                Text(localized("Play a start chime when recording begins and an end chime when processing finishes."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(localized("Mute other media audio while recording"), isOn: $muteSystemAudioWhileRecording)
                Text(localized("Requires system audio recording permission, and only affects other apps' media playback while Voxt is recording."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let systemAudioPermissionMessage {
                    Text(systemAudioPermissionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeneralSettingsCard(title: "Shortcut") {
                OnboardingSegmentedTabs(
                    selection: hotkeyPresetSelection,
                    items: [HotkeyPreference.Preset.fnCombo, .commandCombo].map { preset in
                        OnboardingTabItem(value: preset, title: LocalizedStringKey(preset.title))
                    }
                )

                SettingsMenuPicker(
                    selection: triggerModeSelection,
                    options: HotkeyPreference.TriggerMode.allCases.map { mode in
                        SettingsMenuOption(value: mode, title: mode.title)
                    },
                    selectedTitle: triggerModeSelection.wrappedValue.title,
                    width: 260
                )

                Text(hotkeyPresetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hotkeyPresetSelection.wrappedValue == .fnCombo {
                    Text(localized("On macOS, fn shortcuts may conflict with Globe or input source switching. If needed, change that shortcut in System Settings > Keyboard > Keyboard Shortcuts > Input Sources."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            OnboardingSummaryCard(
                title: "Quick Test",
                lines: [
                    AppLocalization.format("Current preset: %@", hotkeyPresetSelection.wrappedValue.title),
                    AppLocalization.format("Transcription shortcut: %@", formattedTranscriptionHotkey),
                    AppLocalization.format("Focus the textarea below, then press %@ to test transcription directly.", formattedTranscriptionHotkey)
                ]
            )

            TranscriptionTestSectionView()
        }
    }

    var translationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Translation") {
                HStack(alignment: .center) {
                    Text(localized("Target Language"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    SettingsMenuPicker(
                        selection: $translationTargetLanguageRaw,
                        options: TranslationTargetLanguage.allCases.map { language in
                            SettingsMenuOption(value: language.rawValue, title: language.title)
                        },
                        selectedTitle: translationTargetLanguage.title,
                        width: 220
                    )
                }

                Toggle(localized("Also copy result to clipboard"), isOn: $autoCopyWhenNoFocusedInput)
                Text(localized("When enabled, translated text is kept in the clipboard in addition to being inserted into the current input."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(localized("Translate selected text with translation shortcut"), isOn: $translateSelectedTextOnTranslationHotkey)
                Text(localized("If text is selected, the translation shortcut translates the selection directly instead of starting a recording."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeneralSettingsCard(title: "Test Translation") {
                Text(localized("Use the textarea below to test the translation shortcut directly."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "Quick Test",
                    lines: translationShortcutTestLines
                )

                TextEditor(text: $translationTestInput)
                    .settingsPromptEditor(height: 110, contentPadding: 6)

                HStack(spacing: 8) {
                    Button(localized("Use Sample")) {
                        translationTestInput = OnboardingTranslationTest.defaultInput
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Button(localized("Clean")) {
                        translationTestInput = ""
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                }
            }
        }
    }

    var rewriteStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Rewrite") {
                Text(localized("Use voice to rewrite selected text, or speak a full prompt when nothing is selected."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeneralSettingsCard(title: "How It Works") {
                OnboardingExampleRow(
                    title: "Rewrite Selected Text",
                    detail: "Select a paragraph, then say something like: make this shorter and more polite."
                )
                Divider()
                OnboardingExampleRow(
                    title: "Voice Prompt Mode",
                    detail: "With no selected text, say something like: write a follow-up email to the client about tomorrow's launch."
                )
            }

            GeneralSettingsCard(title: "Test Rewrite") {
                Text(localized("Use the textarea below to test the rewrite shortcut directly."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "Quick Test",
                    lines: rewriteShortcutTestLines
                )

                Text(localized("Instruction"))
                    .font(.subheadline.weight(.medium))

                TextField(localized("Make this shorter and more polite."), text: $rewriteTestPrompt)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface()

                Text(localized("Source Text"))
                    .font(.subheadline.weight(.medium))

                TextEditor(text: $rewriteTestSourceText)
                    .settingsPromptEditor(height: 120, contentPadding: 6)

                HStack(spacing: 8) {
                    Button(localized("Use Sample")) {
                        rewriteTestPrompt = OnboardingRewriteTest.defaultPrompt
                        rewriteTestSourceText = OnboardingRewriteTest.defaultSourceText
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Button(localized("Clean")) {
                        rewriteTestPrompt = ""
                        rewriteTestSourceText = ""
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                }
            }
        }
    }

    var appEnhancementStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "App Enhancement") {
                Toggle(localized("Enable App Enhancement"), isOn: $appEnhancementEnabled)
                Text(localized("App Enhancement lets Voxt switch prompts based on the current app or browser tab, so translation, rewrite, and cleanup can behave differently across contexts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeneralSettingsCard(title: "Demo Video") {
                Text(localized("Watch a short example of how App Enhancement behaves across apps and pages."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let appEnhancementDemoPlayer {
                    OnboardingVideoPlayerView(player: appEnhancementDemoPlayer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                }
            }
        }
    }

    var meetingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Meeting") {
                Toggle(localized("Enable Meeting"), isOn: meetingEnabledBinding)

                Text(localized("Turn on the dedicated meeting workflow, shortcut, overlay, and meeting-specific model settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            OnboardingSummaryCard(
                title: "Meeting Shortcut",
                lines: onboardingMeetingStatusLines
            )

            if !featureSettings.meeting.enabled {
                OnboardingSummaryCard(
                    title: "Disabled",
                    lines: [
                        localized("Meeting permissions are only required after you turn this feature on.")
                    ]
                )
            } else if meetingBlockingMessages.isEmpty {
                OnboardingSummaryCard(
                    title: "Meeting Is Ready",
                    lines: [
                        localized("The current engine and permissions satisfy the meeting requirements.")
                    ]
                )
            } else {
                OnboardingSummaryCard(
                    title: "Setup Needed",
                    lines: meetingBlockingMessages
                )
            }

            GeneralSettingsCard(title: "Demo Video") {
                Text(localized("Watch a short example of the meeting recording workflow."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let meetingDemoPlayer {
                    OnboardingVideoPlayerView(player: meetingDemoPlayer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                }
            }
        }
    }

    var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "You're Ready") {
                Text(localized("Voxt is configured enough to start. You can still refine any detail later from the normal settings pages."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "Current Setup",
                    lines: [
                        AppLocalization.format("Language: %@", interfaceLanguage.title),
                        AppLocalization.format("ASR: %@", onboardingASRSummary),
                        AppLocalization.format("LLM: %@", onboardingLLMSummary),
                        AppLocalization.format("Translation: %@", translationProviderSummary),
                        AppLocalization.format("Rewrite: %@", rewriteProviderSummary),
                        AppLocalization.format("Meeting: %@", onboardingMeetingSummary)
                    ]
                )

                HStack(spacing: 8) {
                    Button(localized("Export Configuration")) {
                        exportConfiguration()
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Button(localized("Import Configuration")) {
                        importConfiguration()
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Spacer()

                    Button(localized("Start Voxt")) {
                        onFinish()
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                }

                if let configurationTransferMessage {
                    Text(configurationTransferMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    var currentStepPermissionSection: some View {
        let permissions = currentStepRequiredPermissions
        if !permissions.isEmpty {
            GeneralSettingsCard(title: "Permissions For This Step") {
                Text(localized("Grant the permissions required for this step. If a permission is disabled, you can request it here or jump to System Settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(permissions.enumerated()), id: \.offset) { index, permission in
                    if index > 0 {
                        Divider()
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(permission.titleKey)
                                .font(.subheadline)
                            Text(permission.descriptionKey)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if permissionMonitoringKinds.contains(permission) {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        }

                        OnboardingPermissionStatusBadge(isGranted: isPermissionGranted(permission))

                        if !isPermissionGranted(permission) {
                            Button(localized("Request")) {
                                requestPermission(permission)
                            }
                            .buttonStyle(SettingsCompactActionButtonStyle())

                            Button(localized("Open Settings")) {
                                openSettings(for: permission)
                            }
                            .buttonStyle(SettingsCompactActionButtonStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    var selectedLocalEngineDescription: String {
        switch localEngineSelection.wrappedValue {
        case .mlxAudio:
            return TranscriptionEngine.mlxAudio.description
        case .whisperKit:
            return TranscriptionEngine.whisperKit.description
        case .dictation, .remote:
            return ""
        }
    }

    func modelPathDescription(_ choice: OnboardingModelPathChoice) -> String {
        switch choice {
        case .local:
            return localized("Runs speech and text models on your Mac. Better privacy, works offline after download, but needs local disk space and setup time.")
        case .remote:
            return localized("Uses cloud providers for speech and text. Fast to start, but requires network access and provider configuration.")
        case .dictation:
            return localized("Uses Apple's built-in dictation path with the lightest setup, but fewer supported scenarios.")
        }
    }

    func llmPathDescription(_ choice: OnboardingTextModelPathChoice) -> String {
        switch choice {
        case .local:
            return localized("Uses a local text model for cleanup, translation, rewrite, and summaries after download.")
        case .remote:
            return localized("Uses a cloud text model. Fast to start, but requires network access and provider configuration.")
        case .system:
            return localized("Uses the macOS system model when available, so later onboarding can stay minimal.")
        }
    }

    func modelDescription(for repo: String) -> String {
        guard let description = MLXModelManager.availableModels.first(where: { $0.id == MLXModelManager.canonicalModelRepo(repo) })?.description else {
            return ""
        }
        return AppLocalization.localizedString(description)
    }

    func whisperDescription(for modelID: String) -> String {
        guard let description = WhisperKitModelManager.availableModels.first(where: { $0.id == WhisperKitModelManager.canonicalModelID(modelID) })?.description else {
            return ""
        }
        return AppLocalization.localizedString(description)
    }

    func customLLMDescription(for repo: String) -> String {
        guard let description = CustomLLMModelManager.availableModels.first(where: { $0.id == repo })?.description else {
            return ""
        }
        return AppLocalization.localizedString(description)
    }

    var isSelectedMLXModelDownloading: Bool {
        guard case .downloading = mlxModelManager.state else { return false }
        return MLXModelManager.canonicalModelRepo(mlxModelManager.currentModelRepo) == MLXModelManager.canonicalModelRepo(mlxModelRepo)
    }

    var selectedMLXDownloadStatus: ModelDownloadStatusSnapshot? {
        guard isSelectedMLXModelDownloading else { return nil }
        return ModelDownloadStatusSnapshot.fromMLXState(mlxModelManager.state)
    }

    var selectedMLXDownloadErrorMessage: String? {
        guard MLXModelManager.canonicalModelRepo(mlxModelManager.currentModelRepo) == MLXModelManager.canonicalModelRepo(mlxModelRepo),
              case .error(let message) = mlxModelManager.state else {
            return nil
        }
        return message
    }

    var isSelectedWhisperModelDownloading: Bool {
        whisperModelManager.activeDownload?.modelID == WhisperKitModelManager.canonicalModelID(whisperModelID)
    }

    var selectedWhisperDownloadStatus: ModelDownloadStatusSnapshot? {
        guard isSelectedWhisperModelDownloading else { return nil }
        return ModelDownloadStatusSnapshot.fromWhisperDownload(whisperModelManager.activeDownload)
    }

    var selectedWhisperDownloadErrorMessage: String? {
        whisperModelManager.downloadErrorMessage(for: whisperModelID)
    }

    var isSelectedCustomLLMDownloading: Bool {
        guard case .downloading = customLLMManager.state else { return false }
        return customLLMManager.currentModelRepo == customLLMRepo
    }

    var customLLMDownloadStatus: ModelDownloadStatusSnapshot? {
        guard isSelectedCustomLLMDownloading else { return nil }
        return ModelDownloadStatusSnapshot.fromCustomLLMState(customLLMManager.state)
    }

    var customLLMDownloadErrorMessage: String? {
        guard customLLMManager.currentModelRepo == customLLMRepo,
              case .error(let message) = customLLMManager.state else {
            return nil
        }
        return message
    }

    var hotkeyPresetDescription: String {
        switch hotkeyPresetSelection.wrappedValue {
        case .fnCombo:
            return localized("Recommended default: fn for transcription, fn+shift for translation, fn+control for rewrite, and fn+option for meeting.")
        case .commandCombo:
            return localized("Useful when function-key combinations are already reserved by the system or keyboard tools.")
        case .custom:
            return localized("You can fine-tune every shortcut later from the Hotkey page.")
        }
    }

    var translationShortcutTestLines: [String] {
        var lines = [
            AppLocalization.format("Current preset: %@", hotkeyPresetSelection.wrappedValue.title),
            AppLocalization.format("Translation shortcut: %@", formattedTranslationHotkey)
        ]

        if translateSelectedTextOnTranslationHotkey {
            lines.append(AppLocalization.format("Select text in the textarea below, then press %@ to translate the selection directly.", formattedTranslationHotkey))
        } else {
            lines.append(localized("Enable “Translate selected text with translation shortcut” above if you want the shortcut to act on selected text in this textarea."))
        }

        return lines
    }

    var rewriteShortcutTestLines: [String] {
        [
            AppLocalization.format("Current preset: %@", hotkeyPresetSelection.wrappedValue.title),
            AppLocalization.format("Rewrite shortcut: %@", formattedRewriteHotkey),
            AppLocalization.format("Select text in the textarea below, then press %@ to rewrite the selection directly.", formattedRewriteHotkey),
            AppLocalization.format("If nothing is selected, %@ starts voice prompt mode instead.", formattedRewriteHotkey)
        ]
    }
}

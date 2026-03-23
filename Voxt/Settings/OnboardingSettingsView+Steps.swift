import SwiftUI
import AppKit

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
                    Picker("Language", selection: $interfaceLanguageRaw) {
                        ForEach(AppInterfaceLanguage.allCases, id: \.rawValue) { language in
                            Text(language.titleKey).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }

                Divider()

                GeneralLanguageSettingBlock(
                    title: "User Main Language",
                    description: "Used to bias transcription prompts, translation prompts, and text enhancement."
                ) {
                    Button(action: { isUserMainLanguageSheetPresented = true }) {
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
                    title: "Translation Language",
                    description: "Used by the dedicated translation shortcut and translation test."
                ) {
                    Picker("Target language", selection: $translationTargetLanguageRaw) {
                        ForEach(TranslationTargetLanguage.allCases, id: \.rawValue) { language in
                            Text(language.titleKey).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }
            }

            OnboardingSummaryCard(
                title: "Current Summary",
                lines: [
                    AppLocalization.format("Interface: %@", interfaceLanguage.title),
                    AppLocalization.format("Main language: %@", userMainLanguageSummary),
                    AppLocalization.format("Translate to: %@", translationTargetLanguage.title)
                ]
            )
        }
    }

    var modelStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Setup Path") {
                Picker("Setup Path", selection: modelPathChoice) {
                    ForEach(OnboardingModelPathChoice.allCases) { choice in
                        Text(choice.titleKey).tag(choice)
                    }
                }
                .pickerStyle(.segmented)

                Text(modelPathDescription(modelPathChoice.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch modelPathChoice.wrappedValue {
            case .local:
                localModelStepContent
            case .remote:
                remoteModelStepContent
            case .dictation:
                dictationModelStepContent
            }
        }
    }

    var localModelStepContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Local ASR") {
                Picker("Engine", selection: localEngineSelection) {
                    Text(TranscriptionEngine.mlxAudio.titleKey).tag(TranscriptionEngine.mlxAudio)
                    Text(TranscriptionEngine.whisperKit.titleKey).tag(TranscriptionEngine.whisperKit)
                }
                .pickerStyle(.segmented)

                Text(selectedLocalEngineDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if localEngineSelection.wrappedValue == .mlxAudio {
                    LocalModelPickerCard(
                        title: "Speech Model",
                        selectionTitle: mlxModelManager.displayTitle(for: mlxModelRepo),
                        selectionDescription: modelDescription(for: mlxModelRepo),
                        isInstalled: mlxModelManager.isModelDownloaded(repo: mlxModelRepo),
                        installLabel: "Download",
                        openLabel: "Open Folder",
                        onChoose: {},
                        pickerContent: {
                            Picker("MLX Model", selection: $mlxModelRepo) {
                                ForEach(MLXModelManager.availableModels) { model in
                                    Text(model.title).tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 280, alignment: .leading)
                        },
                        onInstall: {
                            Task { await mlxModelManager.downloadModel(repo: mlxModelRepo) }
                        },
                        onOpen: {
                            guard let folderURL = mlxModelManager.modelDirectoryURL(repo: mlxModelRepo) else { return }
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
                        }
                    )
                } else {
                    LocalModelPickerCard(
                        title: "Speech Model",
                        selectionTitle: whisperModelManager.displayTitle(for: whisperModelID),
                        selectionDescription: whisperDescription(for: whisperModelID),
                        isInstalled: whisperModelManager.isModelDownloaded(id: whisperModelID),
                        installLabel: "Download",
                        openLabel: "Open Folder",
                        onChoose: {},
                        pickerContent: {
                            Picker("Whisper Model", selection: $whisperModelID) {
                                ForEach(WhisperKitModelManager.availableModels) { model in
                                    Text(LocalizedStringKey(model.title)).tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 280, alignment: .leading)
                        },
                        onInstall: {
                            Task { await whisperModelManager.downloadModel(id: whisperModelID) }
                        },
                        onOpen: {
                            guard let folderURL = whisperModelManager.modelDirectoryURL(id: whisperModelID) else { return }
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
                        }
                    )
                }
            }

            GeneralSettingsCard(title: "Local Text Model") {
                Text("Used for enhancement, translation, and rewrite when you stay on the local path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Local Text Model", selection: Binding(
                    get: { customLLMRepo },
                    set: { newValue in
                        customLLMRepo = newValue
                        translationCustomLLMRepo = newValue
                        rewriteCustomLLMRepo = newValue
                    }
                )) {
                    ForEach(CustomLLMModelManager.availableModels) { model in
                        Text(model.title).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 280, alignment: .leading)

                Text(customLLMDescription(for: customLLMRepo))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if customLLMManager.isModelDownloaded(repo: customLLMRepo) {
                        Button("Open Folder") {
                            guard let folderURL = customLLMManager.modelDirectoryURL(repo: customLLMRepo) else { return }
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
                        }
                    } else {
                        Button("Download") {
                            Task { await customLLMManager.downloadModel(repo: customLLMRepo) }
                        }
                    }
                }
            }

            modelStorageCard
        }
    }

    var remoteModelStepContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Remote ASR") {
                Text("Best when you want to start quickly without downloading local speech models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Remote ASR", selection: Binding(
                    get: { selectedRemoteASRProvider.rawValue },
                    set: { newValue in
                        remoteASRSelectedProviderRaw = newValue
                        engineRaw = TranscriptionEngine.remote.rawValue
                    }
                )) {
                    ForEach(RemoteASRProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 280, alignment: .leading)

                ProviderStatusRow(
                    title: selectedRemoteASRProvider.title,
                    status: remoteASRStatusText(for: selectedRemoteASRProvider),
                    onConfigure: {
                        editingASRProvider = selectedRemoteASRProvider
                    }
                )
            }

            GeneralSettingsCard(title: "Remote LLM") {
                Text("Used for enhancement, translation, and rewrite when you stay on the remote path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Remote LLM", selection: Binding(
                    get: { selectedRemoteLLMProvider.rawValue },
                    set: { newValue in
                        remoteLLMSelectedProviderRaw = newValue
                        translationRemoteLLMProviderRaw = newValue
                        rewriteRemoteLLMProviderRaw = newValue
                        enhancementModeRaw = EnhancementMode.remoteLLM.rawValue
                        translationModelProviderRaw = TranslationModelProvider.remoteLLM.rawValue
                        translationFallbackModelProviderRaw = TranslationModelProvider.remoteLLM.rawValue
                        rewriteModelProviderRaw = RewriteModelProvider.remoteLLM.rawValue
                    }
                )) {
                    ForEach(RemoteLLMProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 280, alignment: .leading)

                ProviderStatusRow(
                    title: selectedRemoteLLMProvider.title,
                    status: remoteLLMStatusText(for: selectedRemoteLLMProvider),
                    onConfigure: {
                        editingLLMProvider = selectedRemoteLLMProvider
                    }
                )
            }
        }
    }

    var dictationModelStepContent: some View {
        GeneralSettingsCard(title: "Direct Dictation") {
            Text("Uses Apple speech recognition and works immediately with no model download. This is the lightest setup, but language coverage and meeting support are more limited.")
                .font(.caption)
                .foregroundStyle(.secondary)

            OnboardingSummaryCard(
                title: "Current Text Model Path",
                lines: [
                    AppLocalization.format("Enhancement: %@", enhancementModeTitle),
                    AppLocalization.format("Translation: %@", translationProviderSummary),
                    AppLocalization.format("Rewrite: %@", rewriteProviderSummary)
                ]
            )
        }
    }

    var modelStorageCard: some View {
        GeneralSettingsCard(title: "Model Storage") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Storage Path")
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
                .buttonStyle(.plain)
                .help("Open folder")

                Button("Choose") {
                    chooseModelStorageDirectory()
                }
                .controlSize(.small)
            }

            Text("New model downloads are stored here. Switching the path will not move existing model files.")
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
                HStack(alignment: .firstTextBaseline) {
                    Text("Microphone")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if microphoneState.hasAvailableDevices {
                        Button(action: { isMicrophonePriorityDialogPresented = true }) {
                            HStack(spacing: 8) {
                                Text(microphoneState.activeDevice?.name ?? String(localized: "No available microphone devices"))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: 320, alignment: .trailing)
                    } else {
                        Text(String(localized: "No available microphone devices"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }

                Toggle("Interaction Sounds", isOn: $interactionSoundsEnabled)
                Text("Play a start chime when recording begins and an end chime when processing finishes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Mute other media audio while recording", isOn: $muteSystemAudioWhileRecording)
                Text("Requires system audio recording permission, and only affects other apps' media playback while Voxt is recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let systemAudioPermissionMessage {
                    Text(systemAudioPermissionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeneralSettingsCard(title: "Shortcut") {
                Picker("Preset", selection: hotkeyPresetSelection) {
                    ForEach([HotkeyPreference.Preset.fnCombo, .commandCombo], id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Trigger", selection: triggerModeSelection) {
                    ForEach(HotkeyPreference.TriggerMode.allCases) { mode in
                        Text(mode.titleKey).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 260, alignment: .leading)

                Text(hotkeyPresetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            if !recordingPermissionsSatisfied {
                OnboardingSummaryCard(
                    title: "Setup Needed",
                    lines: recordingPermissionMessages
                )
            }
        }
    }

    var translationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Translation") {
                Toggle("Also copy result to clipboard", isOn: $autoCopyWhenNoFocusedInput)
                Text("When enabled, translated text is kept in the clipboard in addition to being inserted into the current input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Translate selected text with translation shortcut", isOn: $translateSelectedTextOnTranslationHotkey)
                Text("If text is selected, the translation shortcut translates the selection directly instead of starting a recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "Current Translation Chain",
                    lines: [
                        AppLocalization.format("Target language: %@", translationTargetLanguage.title),
                        AppLocalization.format("Provider: %@", translationProviderSummary)
                    ]
                )
            }

            GeneralSettingsCard(title: "Test Translation") {
                Text("Use the textarea below to test the translation shortcut directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "Quick Test",
                    lines: translationShortcutTestLines
                )

                TextEditor(text: $translationTestInput)
                    .font(.system(size: 12))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary.opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Button("Use Sample") {
                        translationTestInput = OnboardingTranslationTest.defaultInput
                    }

                    Button("Clean") {
                        translationTestInput = ""
                    }
                }
            }
        }
    }

    var rewriteStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Rewrite") {
                Text("Rewrite turns spoken instructions into generated or transformed text. If text is selected, Voxt rewrites that selection. If nothing is selected, Voxt treats your voice as the full prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "Current Rewrite Provider",
                    lines: [
                        AppLocalization.format("Provider: %@", rewriteProviderSummary),
                        rewriteIssues.isEmpty
                            ? String(localized: "Current rewrite path is ready to use.")
                            : String(localized: "Current rewrite path still needs model or provider setup.")
                    ]
                )
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
                Text("Use the textarea below to test the rewrite shortcut directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "Quick Test",
                    lines: rewriteShortcutTestLines
                )

                Text("Instruction")
                    .font(.subheadline.weight(.medium))

                TextField("Make this shorter and more polite.", text: $rewriteTestPrompt)
                    .textFieldStyle(.roundedBorder)

                Text("Source Text")
                    .font(.subheadline.weight(.medium))

                TextEditor(text: $rewriteTestSourceText)
                    .font(.system(size: 12))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary.opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Button("Use Sample") {
                        rewriteTestPrompt = OnboardingRewriteTest.defaultPrompt
                        rewriteTestSourceText = OnboardingRewriteTest.defaultSourceText
                    }

                    Button("Clean") {
                        rewriteTestPrompt = ""
                        rewriteTestSourceText = ""
                    }
                }
            }
        }
    }

    var appEnhancementStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "App Enhancement") {
                Toggle("Enable App Enhancement", isOn: $appEnhancementEnabled)
                Text("App Enhancement lets Voxt switch prompts based on the current app or browser tab, so translation, rewrite, and cleanup can behave differently across contexts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "When To Use It",
                    lines: [
                        String(localized: "Use one style in Slack and another in Mail."),
                        String(localized: "Apply different prompts for docs, chat, and support tools."),
                        String(localized: "Fine-tune later in the App Branch page.")
                    ]
                )
            }

            GeneralSettingsCard(title: "Demo Video") {
                Text("Watch a short example of how App Enhancement behaves across apps and pages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingVideoPlayerView(player: appEnhancementDemoPlayer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }

    var meetingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "Meeting Notes") {
                Toggle("Enable Meeting Notes", isOn: $meetingNotesBetaEnabled)
                Text("Meeting Notes adds a dedicated shortcut, a separate meeting overlay, and a history flow for longer live sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "What Gets Enabled",
                    lines: [
                        AppLocalization.format("Meeting shortcut: %@", formattedMeetingHotkey),
                        String(localized: "Dedicated live meeting overlay"),
                        String(localized: "Meeting permissions and meeting history")
                    ]
                )
            }

            if meetingNotesBetaEnabled {
                if meetingBlockingMessages.isEmpty {
                    OnboardingSummaryCard(
                        title: "Meeting Mode Is Ready",
                        lines: [
                            String(localized: "The current engine and permissions satisfy the meeting-mode requirements.")
                        ]
                    )
                } else {
                    OnboardingSummaryCard(
                        title: "Setup Needed",
                        lines: meetingBlockingMessages
                    )
                }
            }

            GeneralSettingsCard(title: "Demo Video") {
                Text("Watch a short example of the meeting recording workflow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingVideoPlayerView(player: meetingDemoPlayer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }

    var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeneralSettingsCard(title: "You're Ready") {
                Text("Voxt is configured enough to start. You can still refine any detail later from the normal settings pages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OnboardingSummaryCard(
                    title: "Current Setup",
                    lines: [
                        AppLocalization.format("Language: %@", interfaceLanguage.title),
                        AppLocalization.format("Transcription: %@", selectedEngine.title),
                        AppLocalization.format("Translation: %@", translationProviderSummary),
                        AppLocalization.format("Rewrite: %@", rewriteProviderSummary),
                        AppLocalization.format("Meeting Notes: %@", meetingNotesBetaEnabled ? AppLocalization.localizedString("Enabled") : AppLocalization.localizedString("Disabled"))
                    ]
                )

                HStack(spacing: 8) {
                    Button("Export Configuration") {
                        exportConfiguration()
                    }

                    Button("Import Configuration") {
                        importConfiguration()
                    }

                    Spacer()

                    Button("Start Voxt") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let configurationTransferMessage {
                    Text(configurationTransferMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            return String(localized: "Runs speech and text models on your Mac. Better privacy, works offline after download, but needs local disk space and setup time.")
        case .remote:
            return String(localized: "Uses cloud providers for speech and text. Fast to start, but requires network access and provider configuration.")
        case .dictation:
            return String(localized: "Uses Apple's built-in dictation path with the lightest setup, but fewer supported scenarios.")
        }
    }

    func modelDescription(for repo: String) -> String {
        MLXModelManager.availableModels.first(where: { $0.id == MLXModelManager.canonicalModelRepo(repo) })?.description ?? ""
    }

    func whisperDescription(for modelID: String) -> String {
        WhisperKitModelManager.availableModels.first(where: { $0.id == WhisperKitModelManager.canonicalModelID(modelID) })?.description ?? ""
    }

    func customLLMDescription(for repo: String) -> String {
        CustomLLMModelManager.availableModels.first(where: { $0.id == repo })?.description ?? ""
    }

    var hotkeyPresetDescription: String {
        switch hotkeyPresetSelection.wrappedValue {
        case .fnCombo:
            return String(localized: "Recommended default: fn for transcription, fn+shift for translation, fn+control for rewrite, and fn+option for meeting notes.")
        case .commandCombo:
            return String(localized: "Useful when function-key combinations are already reserved by the system or keyboard tools.")
        case .custom:
            return String(localized: "You can fine-tune every shortcut later from the Hotkey page.")
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
            lines.append(String(localized: "Enable “Translate selected text with translation shortcut” above if you want the shortcut to act on selected text in this textarea."))
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

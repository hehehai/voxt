import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices
import UniformTypeIdentifiers

struct OnboardingSettingsView: View {
    @Binding var currentStep: OnboardingStep

    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var whisperModelManager: WhisperKitModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager
    @ObservedObject var appUpdateManager: AppUpdateManager

    let onExit: () -> Void
    let onFinish: () -> Void

    @AppStorage(AppPreferenceKey.interactionSoundsEnabled) var interactionSoundsEnabled = true
    @AppStorage(AppPreferenceKey.muteSystemAudioWhileRecording) var muteSystemAudioWhileRecording = false
    @AppStorage(AppPreferenceKey.interfaceLanguage) var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.translationTargetLanguage) var translationTargetLanguageRaw = TranslationTargetLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.userMainLanguageCodes) var userMainLanguageCodesRaw = UserMainLanguageOption.defaultStoredSelectionValue
    @AppStorage(AppPreferenceKey.translateSelectedTextOnTranslationHotkey) var translateSelectedTextOnTranslationHotkey = true
    @AppStorage(AppPreferenceKey.autoCopyWhenNoFocusedInput) var autoCopyWhenNoFocusedInput = false
    @AppStorage(AppPreferenceKey.appEnhancementEnabled) var appEnhancementEnabled = false
    @AppStorage(AppPreferenceKey.meetingNotesBetaEnabled) var meetingNotesBetaEnabled = false
    @AppStorage(AppPreferenceKey.modelStorageRootPath) var modelStorageRootPath = ""
    @AppStorage(AppPreferenceKey.transcriptionEngine) var engineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.enhancementMode) var enhancementModeRaw = EnhancementMode.off.rawValue
    @AppStorage(AppPreferenceKey.mlxModelRepo) var mlxModelRepo = MLXModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.whisperModelID) var whisperModelID = WhisperKitModelManager.defaultModelID
    @AppStorage(AppPreferenceKey.customLLMModelRepo) var customLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationCustomLLMModelRepo) var translationCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.rewriteCustomLLMModelRepo) var rewriteCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationModelProvider) var translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.translationFallbackModelProvider) var translationFallbackModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.rewriteModelProvider) var rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.remoteASRSelectedProvider) var remoteASRSelectedProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.remoteLLMSelectedProvider) var remoteLLMSelectedProviderRaw = RemoteLLMProvider.openAI.rawValue
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.translationRemoteLLMProvider) var translationRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.rewriteRemoteLLMProvider) var rewriteRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.hotkeyPreset) var hotkeyPresetRaw = HotkeyPreference.defaultPreset.rawValue
    @AppStorage(AppPreferenceKey.hotkeyTriggerMode) var hotkeyTriggerModeRaw = HotkeyPreference.defaultTriggerMode.rawValue
    @AppStorage(AppPreferenceKey.hotkeyDistinguishModifierSides) var hotkeyDistinguishModifierSides = HotkeyPreference.defaultDistinguishModifierSides

    @State var inputDevices: [AudioInputDevice] = []
    @State var microphoneState = MicrophoneResolvedState.empty
    @State var modelStorageDisplayPath = ""
    @State var modelStorageSelectionError: String?
    @State var systemAudioPermissionMessage: String?
    @State var configurationTransferMessage: String?
    @State var isUserMainLanguageSheetPresented = false
    @State var isMicrophonePriorityDialogPresented = false
    @State var isPermissionsDialogPresented = false
    @State var editingASRProvider: RemoteASRProvider?
    @State var editingLLMProvider: RemoteLLMProvider?
    @State var translationTestInput = OnboardingTranslationTest.defaultInput
    @State var rewriteTestPrompt = OnboardingRewriteTest.defaultPrompt
    @State var rewriteTestSourceText = OnboardingRewriteTest.defaultSourceText
    @State var appEnhancementDemoPlayer = AVPlayer(url: OnboardingVideoDemo.appEnhancementURL)
    @State var meetingDemoPlayer = AVPlayer(url: OnboardingVideoDemo.meetingURL)

    var interfaceLanguage: AppInterfaceLanguage {
        AppInterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .system
    }

    var translationTargetLanguage: TranslationTargetLanguage {
        TranslationTargetLanguage(rawValue: translationTargetLanguageRaw) ?? .english
    }

    var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRaw) ?? .mlxAudio
    }

    var selectedRemoteASRProvider: RemoteASRProvider {
        RemoteASRProvider(rawValue: remoteASRSelectedProviderRaw) ?? .openAIWhisper
    }

    var selectedRemoteLLMProvider: RemoteLLMProvider {
        RemoteLLMProvider(rawValue: remoteLLMSelectedProviderRaw) ?? .openAI
    }

    var selectedRewriteProvider: RewriteModelProvider {
        RewriteModelProvider(rawValue: rewriteModelProviderRaw) ?? .customLLM
    }

    var remoteASRConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(from: remoteASRProviderConfigurationsRaw)
    }

    var remoteLLMConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(from: remoteLLMProviderConfigurationsRaw)
    }

    var selectedUserMainLanguageCodes: [String] {
        UserMainLanguageOption.storedSelection(from: userMainLanguageCodesRaw)
    }

    var userMainLanguageSummary: String {
        let codes = selectedUserMainLanguageCodes
        guard let primaryCode = codes.first,
              let primaryOption = UserMainLanguageOption.option(for: primaryCode) else {
            return UserMainLanguageOption.fallbackOption().title()
        }

        if codes.count == 1 {
            return primaryOption.title()
        }

        let format = AppLocalization.localizedString("%@ + %d more")
        return String(format: format, primaryOption.title(), codes.count - 1)
    }

    var modelPathChoice: Binding<OnboardingModelPathChoice> {
        Binding(
            get: {
                switch selectedEngine {
                case .mlxAudio, .whisperKit:
                    return .local
                case .remote:
                    return .remote
                case .dictation:
                    return .dictation
                }
            },
            set: { newValue in
                switch newValue {
                case .local:
                    if selectedEngine == .remote || selectedEngine == .dictation {
                        engineRaw = TranscriptionEngine.mlxAudio.rawValue
                    }
                    enhancementModeRaw = EnhancementMode.customLLM.rawValue
                    translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
                    translationFallbackModelProviderRaw = TranslationModelProvider.customLLM.rawValue
                    rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
                case .remote:
                    engineRaw = TranscriptionEngine.remote.rawValue
                    enhancementModeRaw = EnhancementMode.remoteLLM.rawValue
                    translationModelProviderRaw = TranslationModelProvider.remoteLLM.rawValue
                    translationFallbackModelProviderRaw = TranslationModelProvider.remoteLLM.rawValue
                    rewriteModelProviderRaw = RewriteModelProvider.remoteLLM.rawValue
                    translationRemoteLLMProviderRaw = selectedRemoteLLMProvider.rawValue
                    rewriteRemoteLLMProviderRaw = selectedRemoteLLMProvider.rawValue
                case .dictation:
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
            }
        )
    }

    var localEngineSelection: Binding<TranscriptionEngine> {
        Binding(
            get: {
                switch selectedEngine {
                case .mlxAudio, .whisperKit:
                    return selectedEngine
                case .remote, .dictation:
                    return .mlxAudio
                }
            },
            set: { engineRaw = $0.rawValue }
        )
    }

    var hotkeyPresetSelection: Binding<HotkeyPreference.Preset> {
        Binding(
            get: {
                switch HotkeyPreference.Preset(rawValue: hotkeyPresetRaw) ?? .fnCombo {
                case .commandCombo:
                    return .commandCombo
                case .fnCombo, .custom:
                    return .fnCombo
                }
            },
            set: { applyHotkeyPreset($0) }
        )
    }

    var triggerModeSelection: Binding<HotkeyPreference.TriggerMode> {
        Binding(
            get: { HotkeyPreference.TriggerMode(rawValue: hotkeyTriggerModeRaw) ?? .tap },
            set: { hotkeyTriggerModeRaw = $0.rawValue }
        )
    }

    var formattedTranscriptionHotkey: String {
        HotkeyPreference.displayString(
            for: HotkeyPreference.load(),
            distinguishModifierSides: hotkeyDistinguishModifierSides
        )
    }

    var formattedTranslationHotkey: String {
        HotkeyPreference.displayString(
            for: HotkeyPreference.loadTranslation(),
            distinguishModifierSides: hotkeyDistinguishModifierSides
        )
    }

    var formattedRewriteHotkey: String {
        HotkeyPreference.displayString(
            for: HotkeyPreference.loadRewrite(),
            distinguishModifierSides: hotkeyDistinguishModifierSides
        )
    }

    var missingConfigurationIssues: [ConfigurationTransferManager.MissingConfigurationIssue] {
        ConfigurationTransferManager.missingConfigurationIssues(
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager,
            customLLMManager: customLLMManager
        )
    }

    var rewriteIssues: [ConfigurationTransferManager.MissingConfigurationIssue] {
        missingConfigurationIssues.filter { issue in
            switch issue.scope {
            case .rewriteRemoteLLM, .rewriteCustomLLM:
                return true
            default:
                return false
            }
        }
    }

    var meetingBlockingMessages: [String] {
        guard meetingNotesBetaEnabled else { return [] }

        var messages: [String] = []
        let remoteConfiguration = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: selectedRemoteASRProvider,
            stored: remoteASRConfigurations
        )
        let decision = MeetingStartPlanner.resolve(
            selectedEngine: selectedEngine,
            mlxModelState: mlxModelManager.state,
            whisperModelState: whisperModelManager.state,
            remoteASRProvider: selectedRemoteASRProvider,
            remoteASRConfiguration: remoteConfiguration
        )
        if case .blocked(let reason) = decision {
            messages.append(reason.userMessage)
        }

        if SystemAudioCapturePermission.authorizationStatus() != .authorized {
            messages.append(String(localized: "System audio recording permission is required for Meeting Notes. Enable it in Settings > Permissions."))
        }

        return Array(Set(messages))
    }

    var onboardingStatusSnapshot: OnboardingStepStatusSnapshot {
        OnboardingStepStatusSnapshot(
            hasModelIssues: !missingConfigurationIssues.isEmpty,
            hasRecordingMicrophone: !inputDevices.isEmpty,
            hasRecordingPermissions: recordingPermissionsSatisfied,
            hasRewriteIssues: !rewriteIssues.isEmpty,
            appEnhancementEnabled: appEnhancementEnabled,
            meetingNotesEnabled: meetingNotesBetaEnabled,
            hasMeetingIssues: !meetingBlockingMessages.isEmpty
        )
    }

    var currentPermissionContext: OnboardingPermissionRequirementContext {
        OnboardingPermissionRequirementContext(
            selectedEngine: selectedEngine,
            muteSystemAudioWhileRecording: muteSystemAudioWhileRecording,
            meetingNotesEnabled: meetingNotesBetaEnabled
        )
    }

    var currentStepMissingPermissions: [OnboardingContextualPermission] {
        OnboardingPermissionRequirementResolver.requiredPermissions(
            for: currentStep,
            context: currentPermissionContext
        )
        .filter { !OnboardingPermissionGrantResolver.isGranted($0) }
    }

    var shouldShowPermissionBadge: Bool {
        !currentStepMissingPermissions.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            onboardingSidebar
                .frame(width: 184)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 12) {
                onboardingHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stepContent
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.locale, interfaceLanguage.locale)
        .onAppear {
            refreshInputDevices()
            refreshModelStorageDisplayPath()
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
        .onChange(of: modelStorageRootPath) { _, _ in
            refreshModelStorageDisplayPath()
        }
        .onChange(of: currentStep) { _, newValue in
            OnboardingPreferenceManager.saveLastStep(newValue)
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
                    focusMicrophone(uid: uid)
                },
                onAutoSwitchChanged: { isEnabled in
                    setMicrophoneAutoSwitchEnabled(isEnabled)
                },
                onReorderPriority: { orderedUIDs in
                    applyMicrophonePriorityOrder(orderedUIDs)
                }
            )
        }
        .sheet(isPresented: $isPermissionsDialogPresented) {
            ScrollView {
                PermissionsSettingsView(navigationRequest: nil)
                    .padding(16)
            }
            .frame(minWidth: 720, minHeight: 520)
        }
        .sheet(item: $editingASRProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: asrCredentialHint(for: provider),
                showsDoubaoFields: provider == .doubaoASR,
                testTarget: .asr(provider),
                configuration: RemoteModelConfigurationStore.resolvedASRConfiguration(
                    provider: provider,
                    stored: remoteASRConfigurations
                )
            ) { configuration in
                saveRemoteASRConfiguration(configuration)
            }
        }
        .sheet(item: $editingLLMProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: nil,
                showsDoubaoFields: false,
                testTarget: .llm(provider),
                configuration: RemoteModelConfigurationStore.resolvedLLMConfiguration(
                    provider: provider,
                    stored: remoteLLMConfigurations
                )
            ) { configuration in
                saveRemoteLLMConfiguration(configuration)
            }
        }
    }

    var onboardingSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Text(AppLocalization.format("%d/%d", currentStep.stepNumber, OnboardingStep.allCases.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(OnboardingStep.allCases) { step in
                    Button {
                        currentStep = step
                    } label: {
                        HStack(spacing: 1) {
                            Text("\(step.stepNumber)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(width: 12, alignment: .leading)
                                .foregroundStyle(step == currentStep ? Color.white.opacity(0.82) : .secondary)

                            Text(step.titleKey)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            OnboardingStatusBadge(status: stepStatus(for: step), isSelected: step == currentStep)
                        }
                        .foregroundStyle(step == currentStep ? .white : .primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(step == currentStep ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                if shouldShowPermissionBadge {
                    Button(action: { isPermissionsDialogPresented = true }) {
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

                HStack(spacing: 8) {
                    if let previousStep = currentStep.previous {
                        Button {
                            currentStep = previousStep
                        } label: {
                            Label("Previous", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }

                    if let nextStep = currentStep.next {
                        Button {
                            currentStep = nextStep
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }

                Button {
                    if currentStep == .finish {
                        onFinish()
                    } else {
                        onExit()
                    }
                } label: {
                    Label(
                        currentStep == .finish ? "Start Voxt" : "Exit Guide",
                        systemImage: currentStep == .finish ? "checkmark.circle" : "xmark.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .padding(.top, 18)
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

    var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentStep.titleKey)
                .font(.title3.weight(.semibold))
            Text(currentStep.subtitleKey)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    func stepStatus(for step: OnboardingStep) -> OnboardingStepStatus {
        OnboardingStepStatusResolver.resolve(step: step, snapshot: onboardingStatusSnapshot)
    }

    var recordingPermissionsSatisfied: Bool {
        OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .transcription,
            context: currentPermissionContext
        )
        .allSatisfy { permission in
            OnboardingPermissionGrantResolver.isGranted(permission)
        }
    }

    var recordingPermissionMessages: [String] {
        var messages: [String] = []
        if !OnboardingPermissionGrantResolver.isGranted(.microphone) {
            messages.append(String(localized: "Microphone permission is required. Enable it in Settings > Permissions."))
        }
        if selectedEngine == .dictation,
           !OnboardingPermissionGrantResolver.isGranted(.speechRecognition) {
            messages.append(String(localized: "Speech Recognition permission is required for Direct Dictation. Enable it in Settings > Permissions."))
        }
        if !OnboardingPermissionGrantResolver.isGranted(.accessibility) {
            messages.append(String(localized: "Accessibility permission is required to insert text into other apps."))
        }
        if !OnboardingPermissionGrantResolver.isGranted(.inputMonitoring) {
            messages.append(String(localized: "Input Monitoring permission improves global shortcut capture, especially for fn combinations."))
        }
        if muteSystemAudioWhileRecording,
           !OnboardingPermissionGrantResolver.isGranted(.systemAudioCapture) {
            messages.append(String(localized: "System audio recording permission is required when muting other media during recording."))
        }
        return messages
    }

    var enhancementModeTitle: String {
        EnhancementMode(rawValue: enhancementModeRaw)?.title ?? EnhancementMode.off.title
    }

    var translationProviderSummary: String {
        let provider = TranslationModelProvider(rawValue: translationModelProviderRaw) ?? .customLLM
        switch provider {
        case .customLLM:
            return customLLMManager.displayTitle(for: translationCustomLLMRepo)
        case .remoteLLM:
            let providerID = translationRemoteLLMProviderRaw.isEmpty ? selectedRemoteLLMProvider.rawValue : translationRemoteLLMProviderRaw
            let remoteProvider = RemoteLLMProvider(rawValue: providerID) ?? selectedRemoteLLMProvider
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: remoteProvider, stored: remoteLLMConfigurations)
            if configuration.hasUsableModel {
                return "\(remoteProvider.title) · \(configuration.model)"
            }
            return "\(remoteProvider.title) · \(String(localized: "Needs Setup"))"
        case .whisperKit:
            return whisperModelManager.displayTitle(for: whisperModelID)
        }
    }

    var rewriteProviderSummary: String {
        switch selectedRewriteProvider {
        case .customLLM:
            return customLLMManager.displayTitle(for: rewriteCustomLLMRepo)
        case .remoteLLM:
            let providerID = rewriteRemoteLLMProviderRaw.isEmpty ? selectedRemoteLLMProvider.rawValue : rewriteRemoteLLMProviderRaw
            let remoteProvider = RemoteLLMProvider(rawValue: providerID) ?? selectedRemoteLLMProvider
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: remoteProvider, stored: remoteLLMConfigurations)
            if configuration.hasUsableModel {
                return "\(remoteProvider.title) · \(configuration.model)"
            }
            return "\(remoteProvider.title) · \(String(localized: "Needs Setup"))"
        }
    }

    var formattedMeetingHotkey: String {
        let hotkey = HotkeyPreference.loadMeeting()
        return HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: hotkeyDistinguishModifierSides)
    }

    func remoteASRStatusText(for provider: RemoteASRProvider) -> String {
        let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: provider,
            stored: remoteASRConfigurations
        )
        guard configuration.isConfigured else {
            return String(localized: "Not configured")
        }

        var lines = [AppLocalization.format("Configured model: %@", configuration.model)]
        if meetingNotesBetaEnabled,
           RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(provider) {
            if configuration.hasUsableMeetingModel {
                lines.append(RemoteASRMeetingConfiguration.configuredMeetingModelStatus(configuration.meetingModel))
            } else {
                lines.append(RemoteASRMeetingConfiguration.missingMeetingModelStatus(provider: provider))
            }
        }
        return lines.joined(separator: "\n")
    }

    func remoteLLMStatusText(for provider: RemoteLLMProvider) -> String {
        let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: remoteLLMConfigurations
        )
        guard configuration.isConfigured else {
            return String(localized: "Not configured")
        }
        return AppLocalization.format("Configured model: %@", configuration.model)
    }

    func refreshInputDevices() {
        inputDevices = AudioInputDeviceManager.availableInputDevices()
        microphoneState = MicrophonePreferenceManager.syncState(
            defaults: .standard,
            availableDevices: inputDevices
        )
    }

    func refreshModelStorageDisplayPath() {
        let resolved = ModelStorageDirectoryManager.resolvedRootURL().path
        modelStorageDisplayPath = resolved
        if modelStorageRootPath != resolved {
            modelStorageRootPath = resolved
        }
    }

    func chooseModelStorageDirectory() {
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

    func openModelStorageInFinder() {
        Task { @MainActor in
            ModelStorageDirectoryManager.openRootInFinder()
        }
    }

    func applyHotkeyPreset(_ preset: HotkeyPreference.Preset) {
        hotkeyPresetRaw = preset.rawValue
        guard let values = HotkeyPreference.presetHotkeys(for: preset) else { return }

        hotkeyDistinguishModifierSides = values.distinguishSides
        HotkeyPreference.save(
            keyCode: values.transcription.keyCode,
            modifiers: values.transcription.modifiers,
            sidedModifiers: values.transcription.sidedModifiers
        )
        HotkeyPreference.saveTranslation(
            keyCode: values.translation.keyCode,
            modifiers: values.translation.modifiers,
            sidedModifiers: values.translation.sidedModifiers
        )
        HotkeyPreference.saveRewrite(
            keyCode: values.rewrite.keyCode,
            modifiers: values.rewrite.modifiers,
            sidedModifiers: values.rewrite.sidedModifiers
        )
        HotkeyPreference.saveMeeting(
            keyCode: values.meeting.keyCode,
            modifiers: values.meeting.modifiers,
            sidedModifiers: values.meeting.sidedModifiers
        )
    }

    func setMicrophoneAutoSwitchEnabled(_ isEnabled: Bool) {
        microphoneState = MicrophonePreferenceManager.setAutoSwitchEnabled(
            isEnabled,
            defaults: .standard,
            availableDevices: inputDevices
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
    }

    func applyMicrophonePriorityOrder(_ orderedUIDs: [String]) {
        microphoneState = MicrophonePreferenceManager.reorderPriority(
            orderedUIDs: orderedUIDs,
            defaults: .standard,
            availableDevices: inputDevices
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
    }

    func focusMicrophone(uid: String) {
        microphoneState = MicrophonePreferenceManager.setFocusedDevice(
            uid: uid,
            defaults: .standard,
            availableDevices: inputDevices
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
    }

    func asrCredentialHint(for provider: RemoteASRProvider) -> String? {
        switch provider {
        case .doubaoASR:
            return AppLocalization.localizedString("Doubao uses App ID + Access Token for streaming API.")
        case .aliyunBailianASR:
            return AppLocalization.localizedString("Aliyun ASR in Voxt uses realtime WebSocket only: Qwen models use /api-ws/v1/realtime, Fun/Paraformer models use /api-ws/v1/inference.")
        case .openAIWhisper, .glmASR:
            return nil
        }
    }

    func saveRemoteASRConfiguration(_ configuration: RemoteProviderConfiguration) {
        var updated = remoteASRConfigurations
        updated[configuration.providerID] = configuration
        remoteASRProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfigurations(updated)
    }

    func saveRemoteLLMConfiguration(_ configuration: RemoteProviderConfiguration) {
        var updated = remoteLLMConfigurations
        updated[configuration.providerID] = configuration
        remoteLLMProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfigurations(updated)
    }

    func exportConfiguration() {
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

    func importConfiguration() {
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
}

import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices
import UniformTypeIdentifiers

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

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
    @AppStorage(AppPreferenceKey.featureSettings) var featureSettingsRaw = ""
    @AppStorage(AppPreferenceKey.translationTargetLanguage) var translationTargetLanguageRaw = TranslationTargetLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.userMainLanguageCodes) var userMainLanguageCodesRaw = UserMainLanguageOption.defaultStoredSelectionValue
    @AppStorage(AppPreferenceKey.translateSelectedTextOnTranslationHotkey) var translateSelectedTextOnTranslationHotkey = true
    @AppStorage(AppPreferenceKey.autoCopyWhenNoFocusedInput) var autoCopyWhenNoFocusedInput = false
    @AppStorage(AppPreferenceKey.appEnhancementEnabled) var appEnhancementEnabled = false
    @AppStorage(AppPreferenceKey.modelStorageRootPath) var modelStorageRootPath = ""
    @AppStorage(AppPreferenceKey.useHfMirror) var useHfMirror = false
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
    @State var appEnhancementDemoPlayer: AVPlayer?
    @State var meetingDemoPlayer: AVPlayer?
    @State var featureSettings = FeatureSettingsStore.load(defaults: .standard)
    @State private var permissionRefreshRevision = 0
    @State var permissionMonitoringKinds: Set<OnboardingContextualPermission> = []
    @State private var permissionMonitorTasks: [OnboardingContextualPermission: Task<Void, Never>] = [:]

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

    var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return TextEnhancer.isAvailable
        }
        return false
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

    var llmPathChoice: Binding<OnboardingTextModelPathChoice> {
        Binding(
            get: {
                switch featureSettings.transcription.llmSelectionID.textSelection {
                case .remoteLLM:
                    return .remote
                case .appleIntelligence:
                    return .system
                case .localLLM, .none:
                    return .local
                }
            },
            set: { newValue in
                applyLLMPathChoice(newValue)
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
        guard featureSettings.meeting.enabled else { return [] }
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
            messages.append(localized("System audio recording permission is required for Meeting. Enable it in Settings > Permissions."))
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
            meetingNotesEnabled: featureSettings.meeting.enabled,
            hasMeetingIssues: !meetingBlockingMessages.isEmpty
        )
    }

    var currentPermissionContext: OnboardingPermissionRequirementContext {
        OnboardingPermissionRequirementContext(
            selectedEngine: selectedEngine,
            muteSystemAudioWhileRecording: muteSystemAudioWhileRecording,
            meetingNotesEnabled: featureSettings.meeting.enabled
        )
    }

    var currentStepMissingPermissions: [OnboardingContextualPermission] {
        OnboardingPermissionRequirementResolver.requiredPermissions(
            for: currentStep,
            context: currentPermissionContext
        )
        .filter { !OnboardingPermissionGrantResolver.isGranted($0) }
    }

    var currentStepRequiredPermissions: [OnboardingContextualPermission] {
        OnboardingPermissionRequirementResolver.requiredPermissions(
            for: currentStep,
            context: currentPermissionContext
        )
    }

    var shouldShowPermissionBadge: Bool {
        !currentStepMissingPermissions.isEmpty
    }

    private var onboardingBodyContent: AnyView {
        AnyView(
            HStack(alignment: .top, spacing: 8) {
                onboardingSidebar
                    .frame(width: 184)
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 12) {
                    onboardingHeader
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            stepContent
                            currentStepPermissionSection
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        )
    }

    var meetingEnabledBinding: Binding<Bool> {
        Binding(
            get: { featureSettings.meeting.enabled },
            set: { isEnabled in
                FeatureSettingsStore.update(defaults: .standard) { settings in
                    settings.meeting.enabled = isEnabled
                }
                featureSettings = FeatureSettingsStore.load(defaults: .standard)
            }
        )
    }

    private var onboardingObservedContent: AnyView {
        let localized = AnyView(onboardingBodyContent.environment(\.locale, interfaceLanguage.locale))
        let appeared = AnyView(localized.onAppear {
                refreshInputDevices()
                refreshModelStorageDisplayPath()
                syncOnboardingModelManagers()
                syncOnboardingFeatureSelections()
                prepareDemoPlayerIfNeeded(for: currentStep)
            })
        let muteObserved = AnyView(appeared.onChange(of: muteSystemAudioWhileRecording) { _, newValue in
                handleMuteSystemAudioChange(newValue)
            })
        let languageObserved = AnyView(muteObserved.onChange(of: interfaceLanguageRaw) { _, _ in
                syncLocalizedOnboardingSamples()
                NotificationCenter.default.post(name: .voxtInterfaceLanguageDidChange, object: nil)
            })
        let featureObserved = AnyView(languageObserved.onChange(of: featureSettingsRaw) { _, _ in
                featureSettings = FeatureSettingsStore.load(defaults: .standard)
            })
        let storageObserved = AnyView(featureObserved.onChange(of: modelStorageRootPath) { _, _ in
                refreshModelStorageDisplayPath()
            })
        let mlxObserved = AnyView(storageObserved.onChange(of: mlxModelRepo) { _, newValue in
                handleMLXRepoChange(newValue)
            })
        let whisperObserved = AnyView(mlxObserved.onChange(of: whisperModelID) { _, newValue in
                handleWhisperModelChange(newValue)
            })
        let llmRepoObserved = AnyView(whisperObserved.onChange(of: customLLMRepo) { _, newValue in
                handleCustomLLMRepoChange(newValue)
            })
        let engineObserved = AnyView(llmRepoObserved.onChange(of: engineRaw) { _, _ in
                syncOnboardingFeatureSelections()
            })
        let enhancementObserved = AnyView(engineObserved.onChange(of: enhancementModeRaw) { _, _ in
                syncOnboardingFeatureSelections()
            })
        let remoteASRObserved = AnyView(enhancementObserved.onChange(of: remoteASRSelectedProviderRaw) { _, _ in
                syncOnboardingFeatureSelections()
            })
        let remoteLLMObserved = AnyView(remoteASRObserved.onChange(of: remoteLLMSelectedProviderRaw) { _, _ in
                syncOnboardingFeatureSelections()
            })
        let targetLanguageObserved = AnyView(remoteLLMObserved.onChange(of: translationTargetLanguageRaw) { _, _ in
                syncOnboardingFeatureSelections()
            })
        let translationSelectionObserved = AnyView(targetLanguageObserved.onChange(of: translateSelectedTextOnTranslationHotkey) { _, _ in
                syncOnboardingFeatureSelections()
            })
        let appEnhancementObserved = AnyView(translationSelectionObserved.onChange(of: appEnhancementEnabled) { _, _ in
                syncOnboardingFeatureSelections()
            })
        let stepObserved = AnyView(appEnhancementObserved.onChange(of: currentStep) { _, newValue in
                OnboardingPreferenceManager.saveLastStep(newValue)
                prepareDemoPlayerIfNeeded(for: newValue)
            })
        let audioDevicesObserved = AnyView(stepObserved.onReceive(NotificationCenter.default.publisher(for: .voxtAudioInputDevicesDidChange)) { _ in
                refreshInputDevices()
            })
        let selectedInputObserved = AnyView(audioDevicesObserved.onReceive(NotificationCenter.default.publisher(for: .voxtSelectedInputDeviceDidChange)) { _ in
                refreshInputDevices()
            })
        return AnyView(selectedInputObserved.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permissionRefreshRevision += 1
            })
    }

    private var onboardingSheetContent: AnyView {
        let languageSheet = AnyView(onboardingObservedContent.sheet(isPresented: $isUserMainLanguageSheetPresented) {
            UserMainLanguageSelectionSheet(
                selectedCodes: selectedUserMainLanguageCodes,
                localeIdentifier: interfaceLanguage.localeIdentifier
            ) { updatedCodes in
                userMainLanguageCodesRaw = UserMainLanguageOption.storageValue(for: updatedCodes)
            }
        })
        let microphoneSheet = AnyView(languageSheet.sheet(isPresented: $isMicrophonePriorityDialogPresented) {
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
        })
        let permissionsSheet = AnyView(microphoneSheet.sheet(isPresented: $isPermissionsDialogPresented) {
            ScrollView {
                PermissionsSettingsView(navigationRequest: nil)
                    .padding(16)
            }
            .frame(minWidth: 720, minHeight: 520)
        })
        let asrSheet = AnyView(permissionsSheet.sheet(item: $editingASRProvider) { provider in
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
        })
        return AnyView(asrSheet.sheet(item: $editingLLMProvider) { provider in
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
        }.onDisappear {
            for task in permissionMonitorTasks.values {
                task.cancel()
            }
            permissionMonitorTasks.removeAll()
            permissionMonitoringKinds.removeAll()
        })
    }

    var body: some View {
        onboardingSheetContent
            .id(interfaceLanguageRaw)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsSidebarItemButtonStyle(isActive: step == currentStep))
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
                            Text(localized("Permissions Disabled"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(SettingsStatusButtonStyle(tint: .red))
                }

                HStack(spacing: 8) {
                    if let previousStep = currentStep.previous {
                        Button {
                            currentStep = previousStep
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(localized("Previous"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 9))
                        .frame(maxWidth: .infinity)
                    }

                    if let nextStep = currentStep.next {
                        Button {
                            currentStep = nextStep
                        } label: {
                            HStack(spacing: 4) {
                                Text(localized("Next"))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SettingsPrimaryButtonStyle(horizontalPadding: 10))
                        .frame(maxWidth: .infinity)
                    }
                }

                Group {
                    if currentStep == .finish {
                        Button(action: onFinish) {
                            Label(localized("Start Voxt"), systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SettingsPrimaryButtonStyle())
                    } else {
                        Button(action: onExit) {
                            Label(localized("Exit Guide"), systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SettingsPillButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .settingsSidebarSurface()
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

    func isPermissionGranted(_ permission: OnboardingContextualPermission) -> Bool {
        _ = permissionRefreshRevision
        return OnboardingPermissionGrantResolver.isGranted(permission)
    }

    func requestPermission(_ permission: OnboardingContextualPermission) {
        let initialState = isPermissionGranted(permission)
        permissionRefreshRevision += 1
        startPermissionMonitoring(permission, initialState: initialState)

        switch permission {
        case .microphone:
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                await MainActor.run { permissionRefreshRevision += 1 }
            }
        case .speechRecognition:
            SFSpeechRecognizer.requestAuthorization { _ in
                Task { @MainActor in
                    self.permissionRefreshRevision += 1
                }
            }
        case .accessibility:
            _ = AccessibilityPermissionManager.request(prompt: true)
        case .inputMonitoring:
            if #available(macOS 10.15, *) {
                _ = CGRequestListenEventAccess()
            }
        case .systemAudioCapture:
            SystemAudioCapturePermission.requestAccess { _ in
                Task { @MainActor in
                    self.permissionRefreshRevision += 1
                }
            }
        }
    }

    func openSettings(for permission: OnboardingContextualPermission) {
        let urlString: String
        switch permission {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .systemAudioCapture:
            SystemAudioCapturePermission.openSystemSettings()
            return
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPermissionMonitoring(
        _ permission: OnboardingContextualPermission,
        initialState: Bool
    ) {
        permissionMonitorTasks[permission]?.cancel()
        permissionMonitoringKinds.insert(permission)

        let task = Task { @MainActor in
            defer {
                permissionMonitorTasks[permission] = nil
                permissionMonitoringKinds.remove(permission)
            }

            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }

                let latestState = OnboardingPermissionGrantResolver.isGranted(permission)
                permissionRefreshRevision += 1
                if latestState != initialState {
                    return
                }
            }
        }

        permissionMonitorTasks[permission] = task
    }

    private func handleMuteSystemAudioChange(_ newValue: Bool) {
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

    private func handleMLXRepoChange(_ newValue: String) {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(newValue)
        if canonicalRepo != newValue {
            mlxModelRepo = canonicalRepo
            return
        }
        mlxModelManager.updateModel(repo: canonicalRepo)
        syncOnboardingFeatureSelections()
    }

    private func handleWhisperModelChange(_ newValue: String) {
        let canonicalModelID = WhisperKitModelManager.canonicalModelID(newValue)
        if canonicalModelID != newValue {
            whisperModelID = canonicalModelID
            return
        }
        whisperModelManager.updateModel(id: canonicalModelID)
        syncOnboardingFeatureSelections()
    }

    private func handleCustomLLMRepoChange(_ newValue: String) {
        let sanitizedRepo = CustomLLMModelManager.isSupportedModelRepo(newValue)
            ? newValue
            : CustomLLMModelManager.defaultModelRepo
        if sanitizedRepo != newValue {
            customLLMRepo = sanitizedRepo
            return
        }
        customLLMManager.updateModel(repo: sanitizedRepo)
        syncOnboardingFeatureSelections()
    }

    private func syncOnboardingModelManagers() {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(mlxModelRepo)
        if canonicalRepo != mlxModelRepo {
            mlxModelRepo = canonicalRepo
        }
        mlxModelManager.updateModel(repo: canonicalRepo)

        let canonicalWhisperModelID = WhisperKitModelManager.canonicalModelID(whisperModelID)
        if canonicalWhisperModelID != whisperModelID {
            whisperModelID = canonicalWhisperModelID
        }
        whisperModelManager.updateModel(id: canonicalWhisperModelID)

        let sanitizedCustomLLMRepo = CustomLLMModelManager.isSupportedModelRepo(customLLMRepo)
            ? customLLMRepo
            : CustomLLMModelManager.defaultModelRepo
        if sanitizedCustomLLMRepo != customLLMRepo {
            customLLMRepo = sanitizedCustomLLMRepo
        }
        customLLMManager.updateModel(repo: sanitizedCustomLLMRepo)
    }

    private func prepareDemoPlayerIfNeeded(for step: OnboardingStep) {
        switch step {
        case .appEnhancement:
            if appEnhancementDemoPlayer == nil {
                appEnhancementDemoPlayer = AVPlayer(url: OnboardingVideoDemo.appEnhancementURL)
            }
        case .meeting:
            if meetingDemoPlayer == nil {
                meetingDemoPlayer = AVPlayer(url: OnboardingVideoDemo.meetingURL)
            }
        default:
            break
        }
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
            messages.append(localized("Microphone permission is required. Enable it in Settings > Permissions."))
        }
        if selectedEngine == .dictation,
           !OnboardingPermissionGrantResolver.isGranted(.speechRecognition) {
            messages.append(localized("Speech Recognition permission is required for Direct Dictation. Enable it in Settings > Permissions."))
        }
        if !OnboardingPermissionGrantResolver.isGranted(.accessibility) {
            messages.append(localized("Accessibility permission is required to insert text into other apps."))
        }
        if !OnboardingPermissionGrantResolver.isGranted(.inputMonitoring) {
            messages.append(localized("Input Monitoring permission improves global shortcut capture. If fn shortcuts still conflict, change the macOS input source shortcut in Keyboard settings."))
        }
        if muteSystemAudioWhileRecording,
           !OnboardingPermissionGrantResolver.isGranted(.systemAudioCapture) {
            messages.append(localized("System audio recording permission is required when muting other media during recording."))
        }
        return messages
    }

    var enhancementModeTitle: String {
        featureSettings.transcription.llmEnabled
            ? llmSelectionSummary(featureSettings.transcription.llmSelectionID)
            : AppLocalization.localizedString("Disabled")
    }

    var translationProviderSummary: String {
        translationSelectionSummary(featureSettings.translation.modelSelectionID)
    }

    var rewriteProviderSummary: String {
        llmSelectionSummary(featureSettings.rewrite.llmSelectionID)
    }

    var onboardingASRSummary: String {
        asrSelectionSummary(featureSettings.transcription.asrSelectionID)
    }

    var onboardingLLMSummary: String {
        llmSelectionSummary(featureSettings.transcription.llmSelectionID)
    }

    var formattedMeetingHotkey: String {
        let hotkey = HotkeyPreference.loadMeeting()
        return HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: hotkeyDistinguishModifierSides)
    }

    var onboardingMeetingSummary: String {
        guard featureSettings.meeting.enabled else {
            return AppLocalization.localizedString("Disabled")
        }
        return meetingBlockingMessages.isEmpty
            ? AppLocalization.localizedString("Ready")
            : AppLocalization.localizedString("Needs Setup")
    }

    var onboardingMeetingStatusLines: [String] {
        guard featureSettings.meeting.enabled else {
            return [localized("Meeting is optional during onboarding. You can enable it later from Feature > Transcription.")]
        }

        var lines = [AppLocalization.format("Meeting shortcut: %@", formattedMeetingHotkey)]
        lines.append(localized("Meeting notes: Tap the meeting shortcut to start the dedicated meeting overlay. Tap it again to stop the meeting session."))
        return lines
    }

    private var onboardingASRSelectionID: FeatureModelSelectionID {
        switch selectedEngine {
        case .dictation:
            return .dictation
        case .mlxAudio:
            return .mlx(mlxModelRepo)
        case .whisperKit:
            return .whisper(whisperModelID)
        case .remote:
            return .remoteASR(selectedRemoteASRProvider)
        }
    }

    private var onboardingLLMSelectionID: FeatureModelSelectionID {
        switch llmPathChoice.wrappedValue {
        case .local:
            return .localLLM(customLLMRepo)
        case .remote:
            return .remoteLLM(selectedRemoteLLMProvider)
        case .system:
            return .appleIntelligence
        }
    }

    private func applyLLMPathChoice(_ choice: OnboardingTextModelPathChoice) {
        switch choice {
        case .local:
            enhancementModeRaw = EnhancementMode.customLLM.rawValue
        case .remote:
            enhancementModeRaw = EnhancementMode.remoteLLM.rawValue
        case .system:
            enhancementModeRaw = EnhancementMode.appleIntelligence.rawValue
        }
        syncOnboardingFeatureSelections(usingLLMChoice: choice)
    }

    private func syncOnboardingFeatureSelections(usingLLMChoice choice: OnboardingTextModelPathChoice? = nil) {
        let asrSelection = onboardingASRSelectionID
        let llmSelection = llmSelectionID(for: choice ?? llmPathChoice.wrappedValue)

        FeatureSettingsStore.update(defaults: .standard) { settings in
            settings.transcription.asrSelectionID = asrSelection
            settings.transcription.llmEnabled = true
            settings.transcription.llmSelectionID = llmSelection

            settings.translation.asrSelectionID = asrSelection
            settings.translation.modelSelectionID = translationSelectionID(
                from: llmSelection,
                asrSelection: asrSelection,
                existingSelection: settings.translation.modelSelectionID
            )
            settings.translation.targetLanguageRawValue = translationTargetLanguageRaw
            settings.translation.replaceSelectedText = translateSelectedTextOnTranslationHotkey

            settings.rewrite.asrSelectionID = asrSelection
            settings.rewrite.llmSelectionID = llmSelection
            settings.rewrite.appEnhancementEnabled = appEnhancementEnabled

            settings.meeting.asrSelectionID = asrSelection
            settings.meeting.summaryModelSelectionID = llmSelection
        }

        featureSettings = FeatureSettingsStore.load(defaults: .standard)
    }

    private func llmSelectionID(for choice: OnboardingTextModelPathChoice) -> FeatureModelSelectionID {
        switch choice {
        case .local:
            return .localLLM(customLLMRepo)
        case .remote:
            return .remoteLLM(selectedRemoteLLMProvider)
        case .system:
            return .appleIntelligence
        }
    }

    private func translationSelectionID(
        from llmSelection: FeatureModelSelectionID,
        asrSelection: FeatureModelSelectionID,
        existingSelection: FeatureModelSelectionID
    ) -> FeatureModelSelectionID {
        switch llmSelection.textSelection {
        case .localLLM(let repo):
            return .localLLM(repo)
        case .remoteLLM(let provider):
            return .remoteLLM(provider)
        case .appleIntelligence:
            if case .whisper = asrSelection.asrSelection {
                return .whisperDirectTranslate
            }
            switch existingSelection.translationSelection {
            case .localLLM, .remoteLLM, .whisperDirectTranslate:
                return existingSelection
            case .none:
                return .localLLM(customLLMRepo)
            }
        case .none:
            return .localLLM(customLLMRepo)
        }
    }

    func asrSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.asrSelection {
        case .dictation:
            return AppLocalization.localizedString("Direct Dictation")
        case .mlx(let repo):
            return mlxModelManager.displayTitle(for: repo)
        case .whisper(let modelID):
            return whisperModelManager.displayTitle(for: modelID)
        case .remote(let provider):
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: remoteASRConfigurations)
            if configuration.hasUsableModel {
                return "\(provider.title) · \(configuration.model)"
            }
            return "\(provider.title) · \(AppLocalization.localizedString("Needs Setup"))"
        case .none:
            return AppLocalization.localizedString("Not selected")
        }
    }

    func llmSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.textSelection {
        case .appleIntelligence:
            return AppLocalization.localizedString("Apple Intelligence")
        case .localLLM(let repo):
            return customLLMManager.displayTitle(for: repo)
        case .remoteLLM(let provider):
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: provider, stored: remoteLLMConfigurations)
            if configuration.hasUsableModel {
                return "\(provider.title) · \(configuration.model)"
            }
            return "\(provider.title) · \(AppLocalization.localizedString("Needs Setup"))"
        case .none:
            return AppLocalization.localizedString("Not selected")
        }
    }

    private func translationSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.translationSelection {
        case .whisperDirectTranslate:
            return AppLocalization.localizedString("Whisper Direct Translate")
        case .localLLM, .remoteLLM:
            return llmSelectionSummary(selectionID)
        case .none:
            return AppLocalization.localizedString("Not selected")
        }
    }

    func remoteASRStatusText(for provider: RemoteASRProvider) -> String {
        let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: provider,
            stored: remoteASRConfigurations
        )
        guard configuration.isConfigured else {
            return localized("Not configured")
        }

        var lines = [AppLocalization.format("Configured model: %@", configuration.model)]
        if RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(provider, configuration: configuration) {
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
            return localized("Not configured")
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
        panel.prompt = localized("Choose")

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        do {
            try ModelStorageDirectoryManager.saveUserSelectedRootURL(selectedURL)
            modelStorageSelectionError = nil
            refreshModelStorageDisplayPath()
        } catch {
            modelStorageSelectionError = AppLocalization.format("Failed to update model storage path: %@", error.localizedDescription)
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
            configurationTransferMessage = localized("Configuration exported successfully.")
        } catch {
            configurationTransferMessage = AppLocalization.format("Configuration export failed: %@", error.localizedDescription)
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
            configurationTransferMessage = localized("Configuration imported successfully. Included dictionary data was restored, and sensitive fields need to be filled in again if required.")
        } catch {
            configurationTransferMessage = AppLocalization.format("Configuration import failed: %@", error.localizedDescription)
        }
    }

    private func syncLocalizedOnboardingSamples() {
        let localeIdentifier = interfaceLanguage.localeIdentifier
        let englishIdentifier = AppInterfaceLanguage.english.localeIdentifier
        let chineseIdentifier = AppInterfaceLanguage.chineseSimplified.localeIdentifier
        let japaneseIdentifier = AppInterfaceLanguage.japanese.localeIdentifier

        let translationDefaults = Set([
            OnboardingTranslationTest.defaultInput(localeIdentifier: englishIdentifier),
            OnboardingTranslationTest.defaultInput(localeIdentifier: chineseIdentifier),
            OnboardingTranslationTest.defaultInput(localeIdentifier: japaneseIdentifier)
        ])
        if translationDefaults.contains(translationTestInput) {
            translationTestInput = OnboardingTranslationTest.defaultInput(localeIdentifier: localeIdentifier)
        }

        let rewritePromptDefaults = Set([
            OnboardingRewriteTest.defaultPrompt(localeIdentifier: englishIdentifier),
            OnboardingRewriteTest.defaultPrompt(localeIdentifier: chineseIdentifier),
            OnboardingRewriteTest.defaultPrompt(localeIdentifier: japaneseIdentifier)
        ])
        if rewritePromptDefaults.contains(rewriteTestPrompt) {
            rewriteTestPrompt = OnboardingRewriteTest.defaultPrompt(localeIdentifier: localeIdentifier)
        }

        let rewriteSourceDefaults = Set([
            OnboardingRewriteTest.defaultSourceText(localeIdentifier: englishIdentifier),
            OnboardingRewriteTest.defaultSourceText(localeIdentifier: chineseIdentifier),
            OnboardingRewriteTest.defaultSourceText(localeIdentifier: japaneseIdentifier)
        ])
        if rewriteSourceDefaults.contains(rewriteTestSourceText) {
            rewriteTestSourceText = OnboardingRewriteTest.defaultSourceText(localeIdentifier: localeIdentifier)
        }
    }
}

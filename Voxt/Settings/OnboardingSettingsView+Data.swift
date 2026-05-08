import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

extension OnboardingSettingsView {
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

    func handleMuteSystemAudioChange(_ newValue: Bool) {
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

    func handleMLXRepoChange(_ newValue: String) {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(newValue)
        if canonicalRepo != newValue {
            mlxModelRepo = canonicalRepo
            return
        }
        mlxModelManager.updateModel(repo: canonicalRepo)
        syncOnboardingFeatureSelections()
    }

    func handleWhisperModelChange(_ newValue: String) {
        let canonicalModelID = WhisperKitModelManager.canonicalModelID(newValue)
        if canonicalModelID != newValue {
            whisperModelID = canonicalModelID
            return
        }
        whisperModelManager.updateModel(id: canonicalModelID)
        syncOnboardingFeatureSelections()
    }

    func handleCustomLLMRepoChange(_ newValue: String) {
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

    func syncOnboardingModelManagers() {
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

    func prepareDemoPlayerIfNeeded(for step: OnboardingStep) {
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

    var onboardingASRSelectionID: FeatureModelSelectionID {
        OnboardingFeatureSelectionResolver.asrSelectionID(
            selectedEngine: selectedEngine,
            mlxModelRepo: mlxModelRepo,
            whisperModelID: whisperModelID,
            remoteASRProvider: selectedRemoteASRProvider
        )
    }

    var onboardingLLMSelectionID: FeatureModelSelectionID {
        OnboardingFeatureSelectionResolver.llmSelectionID(
            choice: llmPathChoice.wrappedValue,
            localLLMRepo: customLLMRepo,
            remoteLLMProvider: selectedRemoteLLMProvider
        )
    }

    func applyLLMPathChoice(_ choice: OnboardingTextModelPathChoice) {
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

    func syncOnboardingFeatureSelections(usingLLMChoice choice: OnboardingTextModelPathChoice? = nil) {
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

    func llmSelectionID(for choice: OnboardingTextModelPathChoice) -> FeatureModelSelectionID {
        OnboardingFeatureSelectionResolver.llmSelectionID(
            choice: choice,
            localLLMRepo: customLLMRepo,
            remoteLLMProvider: selectedRemoteLLMProvider
        )
    }

    func translationSelectionID(
        from llmSelection: FeatureModelSelectionID,
        asrSelection: FeatureModelSelectionID,
        existingSelection: FeatureModelSelectionID
    ) -> FeatureModelSelectionID {
        OnboardingFeatureSelectionResolver.translationSelectionID(
            llmSelection: llmSelection,
            asrSelection: asrSelection,
            existingSelection: existingSelection,
            fallbackLocalLLMRepo: customLLMRepo
        )
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

    func translationSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
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
            mlxModelManager.refreshStorageRoot()
            whisperModelManager.refreshStorageRoot()
            customLLMManager.refreshStorageRoot()
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
        guard let values = HotkeyPreference.applyPreset(preset) else { return }
        hotkeyDistinguishModifierSides = values.distinguishSides
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
        remoteASRProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfiguration(
            configuration,
            updating: remoteASRProviderConfigurationsRaw
        )
        NotificationCenter.default.post(name: .voxtRemoteProviderConfigurationsDidChange, object: nil)
    }

    func saveRemoteLLMConfiguration(_ configuration: RemoteProviderConfiguration) {
        remoteLLMProviderConfigurationsRaw = RemoteModelConfigurationStore.saveConfiguration(
            configuration,
            updating: remoteLLMProviderConfigurationsRaw
        )
        NotificationCenter.default.post(name: .voxtRemoteProviderConfigurationsDidChange, object: nil)
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
            refreshModelStorageDisplayPath()
            configurationTransferMessage = localized("Configuration imported successfully. Included dictionary data was restored, and sensitive fields need to be filled in again if required.")
        } catch {
            configurationTransferMessage = AppLocalization.format("Configuration import failed: %@", error.localizedDescription)
        }
    }

    func syncLocalizedOnboardingSamples() {
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

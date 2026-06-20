// OnboardingGuideView.swift
// Provides Onboarding Guide View for onboarding settings.

import SwiftUI
import AppKit
import AVFoundation
import Carbon

private func guideLocalized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct OnboardingGuideView: View {
    @Binding var currentStep: OnboardingGuideStep

    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager

    let onClose: () -> Void
    let onFinish: () -> Void

    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.modelStorageRootPath) private var modelStorageRootPath = ""
    @AppStorage(AppPreferenceKey.transcriptionEngine) private var engineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.mlxModelRepo) private var mlxModelRepo = MLXModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.customLLMModelRepo) private var customLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationCustomLLMModelRepo) private var translationCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.rewriteCustomLLMModelRepo) private var rewriteCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.enhancementMode) private var enhancementModeRaw = EnhancementMode.customLLM.rawValue
    @AppStorage(AppPreferenceKey.translationModelProvider) private var translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.translationFallbackModelProvider) private var translationFallbackModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.rewriteModelProvider) private var rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.translationTargetLanguage) private var translationTargetLanguageRaw = TranslationTargetLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.remoteASRSelectedProvider) private var remoteASRSelectedProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) private var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.remoteLLMSelectedProvider) private var remoteLLMSelectedProviderRaw = RemoteLLMProvider.openAI.rawValue
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) private var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.translationRemoteLLMProvider) private var translationRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.rewriteRemoteLLMProvider) private var rewriteRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.hotkeyPreset) private var hotkeyPresetRaw = HotkeyPreference.defaultPreset.rawValue
    @AppStorage(AppPreferenceKey.hotkeyDistinguishModifierSides) private var distinguishModifierSides = HotkeyPreference.defaultDistinguishModifierSides

    @State private var inputDevices: [AudioInputDevice] = []
    @State private var microphoneState = MicrophoneResolvedState.empty
    @State private var permissionRefreshRevision = 0
    @State private var permissionMonitoringKinds: Set<OnboardingContextualPermission> = []
    @State private var permissionMonitorTasks: [OnboardingContextualPermission: Task<Void, Never>] = [:]
    @State private var modelFocus: OnboardingGuideModelFocus = .local
    @State private var modelStorageDisplayPath = ""
    @State private var modelStorageSelectionError: String?
    @State private var featureSettings = FeatureSettingsStore.load(defaults: .standard)
    @State private var isMicrophonePriorityDialogPresented = false
    @State private var isModelStorageDialogPresented = false
    @State private var editingASRProvider: RemoteASRProvider?
    @State private var editingLLMProvider: RemoteLLMProvider?
    @State private var editingShortcut: OnboardingGuideShortcutKind?
    @State private var isPromptDialogPresented = false
    @State private var isAppPromptDialogPresented = false
    @State private var temporaryEnhancementPrompt = Self.defaultTranscriptionEnhancementPrompt
    @State private var temporaryAppEnhancementPrompt = Self.defaultAppEnhancementPrompt
    @State private var transcriptionInput = ""
    @State private var transcriptionEnhancementInput = ""
    @State private var translationInput = Self.defaultTranslationSample
    @State private var selectedTranslationRange = NSRange(location: 0, length: 0)
    @State private var rewritePromptInput = ""
    @State private var rewriteSelectionInput = Self.defaultRewriteSample
    @State private var selectedRewriteRange = NSRange(location: 0, length: 0)
    @State private var appEnhancementInput = ""
    @State private var completedInteractionSteps = Set<OnboardingGuideStep>()
    @State private var microphoneCapture: MeetingMicrophoneCapture?
    @StateObject private var waveformState = RecentAudioWaveformState(
        barCount: 24,
        historyDuration: 1.6,
        framesPerSecond: 22,
        silenceFloor: 0.015
    )

    @FocusState private var focusedField: OnboardingGuideFocusField?

    private static let localASRRepos = [
        "mlx-community/Qwen3-ASR-1.7B-6bit",
        "mlx-community/SenseVoiceSmall"
    ]

    private static let localLLMRepos = [
        "mlx-community/gemma-2-2b-it-4bit",
        "mlx-community/gemma-4-e2b-it-4bit"
    ]

    private static let defaultTranscriptionEnhancementPromptKey = """
    Clean up the dictated text while preserving meaning. Fix punctuation, casing, repeated words, spoken filler, and obvious number or unit formatting.
    """

    private static let defaultAppEnhancementPromptKey = """
    Turn the user's spoken note into a concise, professional email. Keep the tone clear, polite, and action-oriented.
    """

    private static var defaultTranscriptionEnhancementPrompt: String {
        guideLocalized(Self.defaultTranscriptionEnhancementPromptKey)
    }

    private static var defaultAppEnhancementPrompt: String {
        guideLocalized(Self.defaultAppEnhancementPromptKey)
    }

    private static let defaultTranslationSampleKey = "Please translate this sentence into the selected target language."
    private static let defaultRewriteSampleKey = "The release is delayed because the review took longer than expected. We need to tell the customer without sounding defensive."
    private static var defaultTranslationSample: String {
        guideLocalized(Self.defaultTranslationSampleKey)
    }
    private static var defaultRewriteSample: String {
        guideLocalized(Self.defaultRewriteSampleKey)
    }
    private static let windowSize = CGSize(width: 880, height: 600)
    private static let outerPadding: CGFloat = 12
    private static let outerBottomPadding: CGFloat = 12
    private static let headerHeight: CGFloat = 30
    private static let headerContentSpacing: CGFloat = 8
    private static let contentBottomCompensation: CGFloat = 30
    private static let modelCompactWidth: CGFloat = 268
    private static let compactModelContentWidth: CGFloat = 500

    private var interfaceLanguage: AppInterfaceLanguage {
        AppInterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .system
    }

    private var selectedRemoteASRProvider: RemoteASRProvider {
        RemoteASRProvider(rawValue: remoteASRSelectedProviderRaw) ?? .openAIWhisper
    }

    private var selectedRemoteLLMProvider: RemoteLLMProvider {
        RemoteLLMProvider(rawValue: remoteLLMSelectedProviderRaw) ?? .openAI
    }

    private var translationTargetLanguage: TranslationTargetLanguage {
        TranslationTargetLanguage(rawValue: translationTargetLanguageRaw) ?? .english
    }

    private var remoteASRConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(
            from: remoteASRProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
    }

    private var remoteLLMConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(
            from: remoteLLMProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
    }

    private var allRequiredPermissions: [OnboardingContextualPermission] {
        [.microphone, .accessibility, .inputMonitoring]
    }

    private var areRequiredPermissionsGranted: Bool {
        allRequiredPermissions.allSatisfy { isPermissionGranted($0) }
    }

    private var selectedLocalASRInstalled: Bool {
        mlxModelManager.isModelDownloaded(repo: mlxModelRepo)
    }

    private var selectedLocalLLMInstalled: Bool {
        customLLMManager.isModelDownloaded(repo: customLLMRepo)
    }

    private var remoteModelReady: Bool {
        isRemoteASRConfigured(selectedRemoteASRProvider) || RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
            provider: selectedRemoteLLMProvider,
            stored: remoteLLMConfigurations
        )
    }

    private var modelStepReady: Bool {
        switch modelFocus {
        case .local:
            return selectedLocalASRInstalled && selectedLocalLLMInstalled
        case .remote:
            return remoteModelReady
        }
    }

    private var canContinue: Bool {
        switch currentStep {
        case .permissions:
            return areRequiredPermissionsGranted
        case .microphone:
            return completedInteractionSteps.contains(.microphone)
        case .models:
            return modelStepReady
        case .transcriptionShortcut, .translationShortcut, .rewriteShortcut, .appEnhancement:
            return completedInteractionSteps.contains(currentStep)
        case .transcriptionEnhancement:
            return !transcriptionEnhancementInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .translationSelection:
            return selectedTranslationRange.length > 0
        case .rewriteSelection:
            return selectedRewriteRange.length > 0
        case .meeting, .finish:
            return true
        }
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let contentHeight = max(
                    0,
                    proxy.size.height
                        - Self.outerPadding
                        - Self.headerHeight
                        - Self.headerContentSpacing
                        - Self.outerBottomPadding
                        + Self.contentBottomCompensation
                )

                VStack(spacing: 0) {
                    header
                        .frame(height: Self.headerHeight)
                        .padding(.bottom, Self.headerContentSpacing)

                    content
                        .frame(maxWidth: .infinity)
                        .frame(height: contentHeight)
                }
                .padding(.top, Self.outerPadding)
                .padding(.horizontal, Self.outerPadding)
                .padding(.bottom, Self.outerBottomPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .frame(width: Self.windowSize.width, height: Self.windowSize.height)
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(SettingsUIStyle.windowBackgroundColor)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.locale, interfaceLanguage.locale)
        .groupBoxStyle(SettingsPanelGroupBoxStyle())
        .sheet(isPresented: $isMicrophonePriorityDialogPresented) {
            MicrophonePriorityDialog(
                state: microphoneState,
                onUseNow: { uid in
                    focusMicrophone(uid: uid)
                    restartMicrophoneMeterIfNeeded()
                },
                onAutoSwitchChanged: setMicrophoneAutoSwitchEnabled(_:),
                onReorderPriority: applyMicrophonePriorityOrder(_:)
            )
        }
        .sheet(isPresented: $isModelStorageDialogPresented) {
            modelStorageDialog
        }
        .sheet(item: $editingASRProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: asrCredentialHint(for: provider),
                showsDoubaoFields: provider == .doubaoASR,
                testTarget: .asr(provider),
                configuration: RemoteModelConfigurationStore.resolvedASRConfiguration(
                    provider: provider,
                    stored: RemoteModelConfigurationStore.loadConfigurations(from: remoteASRProviderConfigurationsRaw)
                ),
                onSave: saveRemoteASRConfiguration(_:)
            )
        }
        .sheet(item: $editingLLMProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: nil,
                showsDoubaoFields: false,
                testTarget: .llm(provider),
                configuration: RemoteModelConfigurationStore.resolvedLLMConfiguration(
                    provider: provider,
                    stored: RemoteModelConfigurationStore.loadConfigurations(from: remoteLLMProviderConfigurationsRaw)
                ),
                onSave: saveRemoteLLMConfiguration(_:)
            )
        }
        .sheet(item: $editingShortcut) { shortcut in
            shortcutSheet(for: shortcut)
        }
        .sheet(isPresented: $isPromptDialogPresented) {
            promptSheet(
                title: guideLocalized("Enhancement Prompt"),
                text: $temporaryEnhancementPrompt
            )
        }
        .sheet(isPresented: $isAppPromptDialogPresented) {
            promptSheet(
                title: guideLocalized("Temporary App Enhancement Prompt"),
                text: $temporaryAppEnhancementPrompt
            )
        }
        .onAppear {
            refreshInputDevices()
            refreshModelStorageDisplayPath()
            refreshLocalizedGuideSamples()
            syncModelManagers()
            syncFeatureSelections()
            updateFocusedField()
            updateMicrophoneCapture()
        }
        .onDisappear {
            stopMicrophoneMeter()
            for task in permissionMonitorTasks.values {
                task.cancel()
            }
        }
        .onChange(of: currentStep) { _, newStep in
            OnboardingPreferenceManager.saveLastGuideStep(newStep)
            refreshLocalizedGuideSamples()
            updateFocusedField()
            updateMicrophoneCapture()
        }
        .onChange(of: interfaceLanguageRaw) { _, _ in
            refreshLocalizedGuideSamples()
        }
        .onChange(of: modelStorageRootPath) { _, _ in
            refreshModelStorageDisplayPath()
        }
        .onChange(of: mlxModelRepo) { _, newValue in
            let canonicalRepo = MLXModelManager.canonicalModelRepo(newValue)
            if canonicalRepo != newValue {
                mlxModelRepo = canonicalRepo
            } else {
                mlxModelManager.updateModel(repo: canonicalRepo)
                syncFeatureSelections()
            }
        }
        .onChange(of: customLLMRepo) { _, newValue in
            let sanitizedRepo = CustomLLMModelManager.isSupportedModelRepo(newValue)
                ? newValue
                : CustomLLMModelManager.defaultModelRepo
            if sanitizedRepo != newValue {
                customLLMRepo = sanitizedRepo
            } else {
                customLLMManager.updateModel(repo: sanitizedRepo)
                syncFeatureSelections()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtAudioInputDevicesDidChange)) { _ in
            refreshInputDevices()
            restartMicrophoneMeterIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtSelectedInputDeviceDidChange)) { _ in
            refreshInputDevices()
            restartMicrophoneMeterIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voxtRemoteProviderConfigurationsDidChange)) { _ in
            syncFeatureSelections()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshRevision += 1
        }
        .background(
            OnboardingGuideHotkeyObserver { hotkeyKind in
                handleShortcutObserved(hotkeyKind)
            }
            .frame(width: 0, height: 0)
        )
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: 62, height: 1)

                Spacer(minLength: 0)

                Text(AppLocalization.format("%d/%d", currentStep.stepNumber, OnboardingGuideStep.allCases.count))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
            }

            phaseStrip
        }
    }

    private var phaseStrip: some View {
        HStack(spacing: 10) {
            ForEach(Array(OnboardingGuidePhase.allCases.enumerated()), id: \.element.id) { index, phase in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(phase.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(phase == currentStep.phase ? Color.accentColor : .secondary)
                    .frame(width: 126, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(phase == currentStep.phase ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(phase == currentStep.phase ? Color.accentColor.opacity(0.28) : SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if currentStep == .models {
            modelGuidePanel
        } else {
            regularGuidePanel
        }
    }

    private var regularGuidePanel: some View {
        HStack(spacing: 0) {
            actionPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(SettingsUIStyle.panelBorderColor)
                .frame(width: 1)

            tourPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                .fill(SettingsUIStyle.panelFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                .strokeBorder(SettingsUIStyle.panelBorderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous))
    }

    private var modelGuidePanel: some View {
        VStack(spacing: 0) {
            modelSelectionContent
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                .fill(SettingsUIStyle.panelFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                .strokeBorder(SettingsUIStyle.panelBorderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous))
    }

    private var tourPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(guideLocalized("View Tour"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            guideVisual
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SettingsUIStyle.subtleFillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                )
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(currentStep.phase.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(currentStep.title)
                        .font(.title3.weight(.semibold))
                }
                Text(currentStep.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            stepActions

            Spacer(minLength: 0)

            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var guideVisual: some View {
        switch currentStep {
        case .permissions:
            placeholderVisual(systemImage: "lock.shield", title: guideLocalized("Permission preview"))
        case .microphone:
            microphoneVisual
        case .transcriptionShortcut:
            guideTextEditor(text: $transcriptionInput, prompt: guideLocalized("Focus here, then press the transcription shortcut."))
                .focused($focusedField, equals: .transcription)
        case .transcriptionEnhancement:
            guideTextEditor(text: $transcriptionEnhancementInput, prompt: guideLocalized("Dictate or paste a test sentence here."))
                .focused($focusedField, equals: .transcriptionEnhancement)
        case .translationShortcut:
            guideTextEditor(text: $translationInput, prompt: guideLocalized("Use this input to test translation."))
                .focused($focusedField, equals: .translation)
        case .translationSelection:
            SelectableGuideTextView(text: $translationInput, selectedRange: $selectedTranslationRange)
        case .rewriteShortcut:
            guideTextEditor(text: $rewritePromptInput, prompt: guideLocalized("Ask a question or give a rewrite instruction."))
                .focused($focusedField, equals: .rewrite)
        case .rewriteSelection:
            SelectableGuideTextView(text: $rewriteSelectionInput, selectedRange: $selectedRewriteRange)
        case .appEnhancement:
            guideTextEditor(text: $appEnhancementInput, prompt: guideLocalized("Try: please draft an update email for the launch delay."))
                .focused($focusedField, equals: .appEnhancement)
        case .meeting:
            placeholderVisual(systemImage: "person.2.wave.2", title: guideLocalized("Meeting setup placeholder"))
        case .finish:
            finishVisual
        case .models:
            EmptyView()
        }
    }

    private var microphoneVisual: some View {
        VStack(spacing: 14) {
            MeetingMiniWaveform(
                waveformState: waveformState,
                isSubdued: false
            )
            .frame(height: 56)
            .padding(.horizontal, 24)

            Text(completedInteractionSteps.contains(.microphone)
                ? guideLocalized("Signal detected")
                : guideLocalized("Speak into the selected microphone"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(completedInteractionSteps.contains(.microphone) ? Color.green : .secondary)
        }
    }

    private var finishVisual: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(OnboardingGuideShortcutKind.allCases) { kind in
                HStack {
                    Text(kind.title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(shortcutDisplay(for: kind))
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
        }
        .padding(16)
    }

    private func placeholderVisual(systemImage: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.72))
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text(guideLocalized("Image placeholder"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func guideTextEditor(text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .settingsPromptEditor(height: 230, contentPadding: 8)
        }
        .padding(12)
    }

    @ViewBuilder
    private var stepActions: some View {
        switch currentStep {
        case .permissions:
            permissionsActions
        case .microphone:
            microphoneActions
        case .transcriptionShortcut:
            shortcutActions(
                kind: .transcription,
                message: guideLocalized("Press the current transcription shortcut. Voxt should show the normal floating overlay, and this guide will mark the shortcut as detected.")
            )
        case .transcriptionEnhancement:
            transcriptionEnhancementActions
        case .translationShortcut:
            translationShortcutActions
        case .translationSelection:
            selectionActions(message: guideLocalized("Select any part of the text on the right. When text is selected, Continue becomes available."))
        case .rewriteShortcut:
            shortcutActions(
                kind: .rewrite,
                message: guideLocalized("Press the rewrite shortcut, then ask a question or describe the rewrite you want.")
            )
        case .rewriteSelection:
            selectionActions(message: guideLocalized("Select the source sentence on the right, then continue to finish setup."))
        case .appEnhancement:
            appEnhancementActions
        case .meeting:
            meetingActions
        case .finish:
            finishActions
        case .models:
            EmptyView()
        }
    }

    private var permissionsActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(allRequiredPermissions, id: \.self) { permission in
                permissionRow(permission)
            }

            Text(guideLocalized("If macOS asks you to quit and reopen Voxt, leave this guide unfinished. After restart, Voxt will reopen this setup window."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(_ permission: OnboardingContextualPermission) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(permission.titleKey)
                    .font(.subheadline.weight(.medium))
                Text(permission.descriptionKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if permissionMonitoringKinds.contains(permission) {
                ProgressView()
                    .controlSize(.small)
            }

            OnboardingPermissionStatusBadge(isGranted: isPermissionGranted(permission))

            if !isPermissionGranted(permission) {
                Button(guideLocalized("Allow")) {
                    requestPermission(permission)
                }
                .buttonStyle(SettingsCompactActionButtonStyle())
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsUIStyle.controlFillColor)
        )
    }

    private var microphoneActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideInfoRow(
                title: guideLocalized("Current Microphone"),
                value: microphoneState.activeDevice?.name ?? guideLocalized("No available microphone devices")
            )
            Text(guideLocalized("Speak normally for one or two seconds. The waveform on the right should move."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutActions(kind: OnboardingGuideShortcutKind, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideInfoRow(title: guideLocalized("Shortcut"), value: shortcutDisplay(for: kind))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if completedInteractionSteps.contains(currentStep) {
                Label(guideLocalized("Shortcut detected"), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    private var transcriptionEnhancementActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(guideLocalized("Enable text enhancement for transcription"), isOn: transcriptionEnhancementEnabled)
                .toggleStyle(.switch)

            Text(guideLocalized("Enhanced transcription can:"))
                .font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 5) {
                GuideBullet(text: guideLocalized("Add punctuation and paragraph flow. Example: spoken pauses become readable sentences."))
                GuideBullet(text: guideLocalized("Normalize numbers and units. Example: two point five kilograms becomes 2.5 kg."))
                GuideBullet(text: guideLocalized("Remove filler words. Example: um, uh, repeated starts are cleaned up."))
                GuideBullet(text: guideLocalized("Preserve meaning while improving casing and names."))
            }
            Text(guideLocalized("Try entering text in the box, then continue."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var translationShortcutActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideInfoRow(title: guideLocalized("Shortcut"), value: shortcutDisplay(for: .translation))
            GuideInfoRow(title: guideLocalized("Target Language"), value: translationTargetLanguage.title)
            SettingsMenuPicker(
                selection: $translationTargetLanguageRaw,
                options: TranslationTargetLanguage.allCases.map { language in
                    SettingsMenuOption(value: language.rawValue, title: language.title)
                },
                selectedTitle: translationTargetLanguage.title,
                width: 220
            )
            Text(guideLocalized("Press the translation shortcut to test the focused input on the right."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func selectionActions(message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var appEnhancementActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideInfoRow(title: guideLocalized("Shortcut"), value: shortcutDisplay(for: .transcription))
            Text(guideLocalized("Keep Voxt focused, then press the transcription shortcut. The temporary prompt will turn your spoken note into a polished email draft."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if completedInteractionSteps.contains(.appEnhancement) {
                Label(guideLocalized("Voxt shortcut detected"), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    private var meetingActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideInfoRow(title: guideLocalized("Shortcut"), value: shortcutDisplay(for: .meeting))
            Text(guideLocalized("Meeting capture will use fn + option by default. This onboarding step is reserved for the upcoming meeting walkthrough."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var finishActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guideLocalized("Voxt is ready. You can revisit this guide from the main window at any time."))
                .font(.callout)
                .foregroundStyle(.secondary)
            GuideInfoRow(title: guideLocalized("Transcription"), value: shortcutDisplay(for: .transcription))
            GuideInfoRow(title: guideLocalized("Translation"), value: shortcutDisplay(for: .translation))
            GuideInfoRow(title: guideLocalized("Rewrite"), value: shortcutDisplay(for: .rewrite))
            GuideInfoRow(title: guideLocalized("Meeting"), value: shortcutDisplay(for: .meeting))
        }
    }

    private var modelSelectionContent: some View {
        HStack(alignment: .top, spacing: 12) {
            modelBlock(
                focus: .local,
                title: guideLocalized("Local"),
                subtitle: guideLocalized("Private, offline after download. Install one ASR and one LLM model before continuing.")
            ) {
                localModelActions
            }
            .frame(maxWidth: modelFocus == .local ? .infinity : Self.modelCompactWidth)

            modelBlock(
                focus: .remote,
                title: guideLocalized("Remote"),
                subtitle: guideLocalized("Fast to start. Configure at least one remote ASR or LLM provider.")
            ) {
                remoteModelActions
            }
            .frame(maxWidth: modelFocus == .remote ? .infinity : Self.modelCompactWidth)
        }
        .animation(.easeInOut(duration: 0.18), value: modelFocus)
    }

    private func modelBlock<Content: View>(
        focus: OnboardingGuideModelFocus,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = modelFocus == focus
        return Button {
            modelFocus = focus
            applyModelFocus(focus)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if modelFocus == focus {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(isFocused ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if isFocused {
                    ScrollView {
                        content()
                            .padding(.trailing, 2)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        content()
                            .frame(width: Self.compactModelContentWidth, alignment: .topLeading)
                            .padding(.trailing, 2)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                    .fill(isFocused ? Color.accentColor.opacity(0.08) : SettingsUIStyle.panelFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.35) : SettingsUIStyle.panelBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var localModelActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(guideLocalized("ASR"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Self.localASRRepos, id: \.self) { repo in
                localASRModelRow(repo: repo)
            }

            Divider()

            Text(guideLocalized("LLM"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Self.localLLMRepos, id: \.self) { repo in
                localLLMModelRow(repo: repo)
            }
        }
    }

    private var remoteModelActions: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(guideLocalized("ASR"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(RemoteASRProvider.allCases) { provider in
                    remoteProviderRow(
                        title: provider.title,
                        isSelected: selectedRemoteASRProvider == provider,
                        isConfigured: isRemoteASRConfigured(provider),
                        onSelect: {
                            remoteASRSelectedProviderRaw = provider.rawValue
                            engineRaw = TranscriptionEngine.remote.rawValue
                            modelFocus = .remote
                            syncFeatureSelections()
                        },
                        onConfigure: {
                            editingASRProvider = provider
                        }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(guideLocalized("LLM"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(RemoteLLMProvider.allCases) { provider in
                    remoteProviderRow(
                        title: provider.title,
                        isSelected: selectedRemoteLLMProvider == provider,
                        isConfigured: RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                            provider: provider,
                            stored: remoteLLMConfigurations
                        ),
                        onSelect: {
                            remoteLLMSelectedProviderRaw = provider.rawValue
                            translationRemoteLLMProviderRaw = provider.rawValue
                            rewriteRemoteLLMProviderRaw = provider.rawValue
                            enhancementModeRaw = EnhancementMode.remoteLLM.rawValue
                            translationModelProviderRaw = TranslationModelProvider.remoteLLM.rawValue
                            translationFallbackModelProviderRaw = TranslationModelProvider.remoteLLM.rawValue
                            rewriteModelProviderRaw = RewriteModelProvider.remoteLLM.rawValue
                            modelFocus = .remote
                            syncFeatureSelections()
                        },
                        onConfigure: {
                            editingLLMProvider = provider
                        }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let previous = currentStep.previous {
                Button {
                    currentStep = previous
                } label: {
                    Label(guideLocalized("Back"), systemImage: "chevron.left")
                }
                .buttonStyle(SettingsPillButtonStyle())
            }

            Spacer(minLength: 0)

            leadingFooterAction

            if currentStep == .finish {
                Button {
                    OnboardingPreferenceManager.markCompleted()
                    onFinish()
                } label: {
                    Label(guideLocalized("Start Voxt"), systemImage: "checkmark.circle")
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
            } else if let next = currentStep.next {
                Button {
                    currentStep = next
                } label: {
                    Label(guideLocalized("Continue"), systemImage: "chevron.right")
                        .labelStyle(OnboardingGuideNextLabelStyle())
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .disabled(!canContinue)
                .help(canContinue ? "" : continueDisabledHelp)
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var leadingFooterAction: some View {
        switch currentStep {
        case .microphone:
            Button(guideLocalized("Switch Microphone")) {
                isMicrophonePriorityDialogPresented = true
            }
            .buttonStyle(SettingsPillButtonStyle())
        case .models where modelFocus == .local:
            Button(guideLocalized("Model Location")) {
                isModelStorageDialogPresented = true
            }
            .buttonStyle(SettingsPillButtonStyle())
        case .transcriptionShortcut:
            Button(guideLocalized("Change Shortcut")) {
                editingShortcut = .transcription
            }
            .buttonStyle(SettingsPillButtonStyle())
        case .transcriptionEnhancement:
            Button(guideLocalized("Edit Prompt")) {
                isPromptDialogPresented = true
            }
            .buttonStyle(SettingsPillButtonStyle())
        case .translationShortcut:
            Button(guideLocalized("Change Shortcut")) {
                editingShortcut = .translation
            }
            .buttonStyle(SettingsPillButtonStyle())
        case .rewriteShortcut:
            Button(guideLocalized("Change Shortcut")) {
                editingShortcut = .rewrite
            }
            .buttonStyle(SettingsPillButtonStyle())
        case .appEnhancement:
            Button(guideLocalized("Enhancement Prompt")) {
                isAppPromptDialogPresented = true
            }
            .buttonStyle(SettingsPillButtonStyle())
        default:
            EmptyView()
        }
    }

    private var continueDisabledHelp: String {
        switch currentStep {
        case .permissions:
            return guideLocalized("Grant all listed permissions to continue.")
        case .microphone:
            return guideLocalized("Speak into the selected microphone until a signal is detected.")
        case .models:
            return modelFocus == .local
                ? guideLocalized("Install the selected ASR and LLM local models to continue.")
                : guideLocalized("Configure at least one remote ASR or LLM provider to continue.")
        case .translationSelection, .rewriteSelection:
            return guideLocalized("Select text in the test input first.")
        default:
            return guideLocalized("Complete this test to continue.")
        }
    }
}

private enum OnboardingGuideFocusField: Hashable {
    case transcription
    case transcriptionEnhancement
    case translation
    case rewrite
    case appEnhancement
}

private enum OnboardingGuideShortcutKind: String, CaseIterable, Identifiable {
    case transcription
    case translation
    case rewrite
    case meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcription:
            return guideLocalized("Transcription")
        case .translation:
            return guideLocalized("Translation")
        case .rewrite:
            return guideLocalized("Rewrite")
        case .meeting:
            return guideLocalized("Meeting")
        }
    }

    var defaultHotkey: HotkeyPreference.Hotkey {
        switch self {
        case .transcription:
            return HotkeyPreference.Hotkey(
                keyCode: HotkeyPreference.defaultKeyCode,
                modifiers: HotkeyPreference.defaultModifiers,
                sidedModifiers: []
            )
        case .translation:
            return HotkeyPreference.Hotkey(
                keyCode: HotkeyPreference.defaultTranslationKeyCode,
                modifiers: HotkeyPreference.defaultTranslationModifiers,
                sidedModifiers: []
            )
        case .rewrite:
            return HotkeyPreference.Hotkey(
                keyCode: HotkeyPreference.defaultRewriteKeyCode,
                modifiers: HotkeyPreference.defaultRewriteModifiers,
                sidedModifiers: []
            )
        case .meeting:
            return HotkeyPreference.Hotkey(
                keyCode: HotkeyPreference.defaultMeetingKeyCode,
                modifiers: HotkeyPreference.defaultMeetingModifiers,
                sidedModifiers: []
            )
        }
    }
}

private struct OnboardingGuideNextLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

private struct GuideInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsUIStyle.controlFillColor)
        )
    }
}

private struct GuideBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SelectableGuideTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.string = text
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            _text = text
            _selectedRange = selectedRange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selectedRange = textView.selectedRange()
        }
    }
}

private struct OnboardingGuideHotkeyObserver: NSViewRepresentable {
    let onMatch: (OnboardingGuideShortcutKind) -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMatch = onMatch
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMatch: onMatch)
    }

    final class Coordinator {
        var onMatch: (OnboardingGuideShortcutKind) -> Void
        private var localMonitor: Any?
        private var globalMonitor: Any?

        init(onMatch: @escaping (OnboardingGuideShortcutKind) -> Void) {
            self.onMatch = onMatch
        }

        deinit {
            stop()
        }

        func start() {
            guard localMonitor == nil, globalMonitor == nil else { return }
            let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .otherMouseDown]
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handle(event)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handle(event)
            }
        }

        private func stop() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
            }
            localMonitor = nil
            globalMonitor = nil
        }

        private func handle(_ event: NSEvent) {
            for kind in OnboardingGuideShortcutKind.allCases where matches(kind: kind, event: event) {
                DispatchQueue.main.async {
                    self.onMatch(kind)
                }
            }
        }

        private func matches(kind: OnboardingGuideShortcutKind, event: NSEvent) -> Bool {
            let hotkey: HotkeyPreference.Hotkey
            switch kind {
            case .transcription:
                hotkey = HotkeyPreference.load()
            case .translation:
                hotkey = HotkeyPreference.loadTranslation()
            case .rewrite:
                hotkey = HotkeyPreference.loadRewrite()
            case .meeting:
                hotkey = HotkeyPreference.loadMeeting()
            }

            switch (hotkey.input, event.type) {
            case (.mouseButton(let buttonNumber), .otherMouseDown):
                guard event.buttonNumber == buttonNumber else { return false }
            case (.keyboard(let keyCode), .keyDown):
                guard keyCode != HotkeyPreference.modifierOnlyKeyCode,
                      event.keyCode == keyCode
                else { return false }
            case (.keyboard(let keyCode), .flagsChanged):
                guard keyCode == HotkeyPreference.modifierOnlyKeyCode else { return false }
            default:
                return false
            }

            let eventFlags = event.cgEvent?.flags ?? HotkeyPreference.cgFlags(from: event.modifierFlags.intersection(.hotkeyRelevant))
            let sided = SidedModifierFlags.from(eventFlags: eventFlags)
            return HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: eventFlags,
                sidedModifiers: sided,
                distinguishModifierSides: HotkeyPreference.loadDistinguishModifierSides()
            )
        }
    }
}

private extension OnboardingGuideView {
    var transcriptionEnhancementEnabled: Binding<Bool> {
        Binding(
            get: { featureSettings.transcription.llmEnabled },
            set: { isEnabled in
                var updated = featureSettings
                updated.transcription.llmEnabled = isEnabled
                featureSettings = updated
                FeatureSettingsStore.save(updated)
            }
        )
    }

    var modelStorageDialog: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(guideLocalized("Model Location"))
                .font(.headline)
            Text(guideLocalized("Local ASR and LLM models are stored here. You can move future downloads to another folder."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(guideLocalized("Current Location"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(modelStorageDisplayPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsUIStyle.controlFillColor)
            )

            if let modelStorageSelectionError {
                Text(modelStorageSelectionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(guideLocalized("Reveal in Finder")) {
                    openModelStorageInFinder()
                }
                .buttonStyle(SettingsPillButtonStyle())
                Spacer()
                Button(guideLocalized("Choose Folder")) {
                    chooseModelStorageDirectory()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
            }
        }
        .settingsDialogChrome(width: 420)
    }

    func promptSheet(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            TextEditor(text: text)
                .settingsPromptEditor(height: 220, contentPadding: 10)
            HStack {
                Spacer()
                Button(guideLocalized("Done")) {
                    isPromptDialogPresented = false
                    isAppPromptDialogPresented = false
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
            }
        }
        .settingsDialogChrome(width: 480)
    }

    func shortcutSheet(for kind: OnboardingGuideShortcutKind) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FeatureShortcutCaptureRow(
                title: AppLocalization.format("%@ %@", kind.title, guideLocalized("Shortcut")),
                detail: guideLocalized("Capture a new shortcut for this workflow. The change is saved immediately after confirmation."),
                inputWidth: 360,
                hotkey: hotkeyBinding(for: kind),
                defaultHotkey: kind.defaultHotkey
            )

            HStack {
                Spacer()
                Button(guideLocalized("Done")) {
                    editingShortcut = nil
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
            }
        }
        .settingsDialogChrome(width: 460)
    }

    func hotkeyBinding(for kind: OnboardingGuideShortcutKind) -> Binding<HotkeyPreference.Hotkey> {
        Binding(
            get: {
                switch kind {
                case .transcription:
                    return HotkeyPreference.load()
                case .translation:
                    return HotkeyPreference.loadTranslation()
                case .rewrite:
                    return HotkeyPreference.loadRewrite()
                case .meeting:
                    return HotkeyPreference.loadMeeting()
                }
            },
            set: { hotkey in
                hotkeyPresetRaw = HotkeyPreference.Preset.custom.rawValue
                switch kind {
                case .transcription:
                    HotkeyPreference.save(hotkey)
                case .translation:
                    HotkeyPreference.saveTranslation(hotkey)
                case .rewrite:
                    HotkeyPreference.saveRewrite(hotkey)
                case .meeting:
                    HotkeyPreference.saveMeeting(hotkey)
                }
            }
        )
    }

    func localASRModelRow(repo: String) -> some View {
        localModelRow(
            title: mlxModelManager.displayTitle(for: repo),
            repo: repo,
            isSelected: MLXModelManager.canonicalModelRepo(mlxModelRepo) == MLXModelManager.canonicalModelRepo(repo),
            isInstalled: mlxModelManager.isModelDownloaded(repo: repo),
            status: mlxDownloadStatus(for: repo),
            errorMessage: mlxDownloadErrorMessage(for: repo),
            onSelect: {
                let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
                mlxModelRepo = canonicalRepo
                engineRaw = TranscriptionEngine.mlxAudio.rawValue
                modelFocus = .local
                mlxModelManager.updateModel(repo: canonicalRepo)
                syncFeatureSelections()
            },
            onInstall: {
                let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
                mlxModelRepo = canonicalRepo
                engineRaw = TranscriptionEngine.mlxAudio.rawValue
                modelFocus = .local
                syncFeatureSelections()
                Task { await mlxModelManager.downloadModel(repo: canonicalRepo) }
            },
            onPause: { mlxModelManager.pauseDownload(repo: repo) },
            onCancel: { mlxModelManager.cancelDownload(repo: repo) }
        )
    }

    func localLLMModelRow(repo: String) -> some View {
        localModelRow(
            title: customLLMManager.displayTitle(for: repo),
            repo: repo,
            isSelected: CustomLLMModelManager.canonicalModelRepo(customLLMRepo) == CustomLLMModelManager.canonicalModelRepo(repo),
            isInstalled: customLLMManager.isModelDownloaded(repo: repo),
            status: customLLMDownloadStatus(for: repo),
            errorMessage: customLLMDownloadErrorMessage(for: repo),
            onSelect: {
                let canonicalRepo = CustomLLMModelManager.canonicalModelRepo(repo)
                customLLMRepo = canonicalRepo
                translationCustomLLMRepo = canonicalRepo
                rewriteCustomLLMRepo = canonicalRepo
                enhancementModeRaw = EnhancementMode.customLLM.rawValue
                translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
                translationFallbackModelProviderRaw = TranslationModelProvider.customLLM.rawValue
                rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
                modelFocus = .local
                customLLMManager.updateModel(repo: canonicalRepo)
                syncFeatureSelections()
            },
            onInstall: {
                let canonicalRepo = CustomLLMModelManager.canonicalModelRepo(repo)
                customLLMRepo = canonicalRepo
                translationCustomLLMRepo = canonicalRepo
                rewriteCustomLLMRepo = canonicalRepo
                enhancementModeRaw = EnhancementMode.customLLM.rawValue
                translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
                translationFallbackModelProviderRaw = TranslationModelProvider.customLLM.rawValue
                rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
                modelFocus = .local
                syncFeatureSelections()
                Task { await customLLMManager.downloadModel(repo: canonicalRepo) }
            },
            onPause: { customLLMManager.pauseDownload() },
            onCancel: { customLLMManager.cancelDownload(repo: repo) }
        )
    }

    func localModelRow(
        title: String,
        repo: String,
        isSelected: Bool,
        isInstalled: Bool,
        status: ModelDownloadStatusSnapshot?,
        errorMessage: String?,
        onSelect: @escaping () -> Void,
        onInstall: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(repo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }

                if status != nil {
                    Button(guideLocalized("Cancel"), action: onCancel)
                        .buttonStyle(SettingsCompactActionButtonStyle())
                } else if isInstalled {
                    Button(isSelected ? guideLocalized("Selected") : guideLocalized("Use"), action: onSelect)
                        .buttonStyle(SettingsCompactActionButtonStyle())
                        .disabled(isSelected)
                } else {
                    Button(guideLocalized("Install"), action: onInstall)
                        .buttonStyle(SettingsCompactActionButtonStyle())
                }
            }

            if let status {
                ModelDownloadStatusView(status: status)
                Button(guideLocalized("Pause"), action: onPause)
                    .buttonStyle(SettingsPillButtonStyle())
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : SettingsUIStyle.controlFillColor)
        )
    }

    func remoteProviderRow(
        title: String,
        isSelected: Bool,
        isConfigured: Bool,
        onSelect: @escaping () -> Void,
        onConfigure: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Image(systemName: isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(isConfigured ? Color.green : .secondary)
            }
            HStack(spacing: 6) {
                Button(isSelected ? guideLocalized("Selected") : guideLocalized("Use")) {
                    onSelect()
                }
                .buttonStyle(SettingsCompactActionButtonStyle())
                .disabled(isSelected)

                Button(guideLocalized("Configure")) {
                    onConfigure()
                }
                .buttonStyle(SettingsCompactActionButtonStyle())
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : SettingsUIStyle.controlFillColor)
        )
    }

    func shortcutDisplay(for kind: OnboardingGuideShortcutKind) -> String {
        let hotkey: HotkeyPreference.Hotkey
        switch kind {
        case .transcription:
            hotkey = HotkeyPreference.load()
        case .translation:
            hotkey = HotkeyPreference.loadTranslation()
        case .rewrite:
            hotkey = HotkeyPreference.loadRewrite()
        case .meeting:
            hotkey = HotkeyPreference.loadMeeting()
        }
        return HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: distinguishModifierSides)
    }

    func handleShortcutObserved(_ kind: OnboardingGuideShortcutKind) {
        switch (currentStep, kind) {
        case (.transcriptionShortcut, .transcription):
            completedInteractionSteps.insert(.transcriptionShortcut)
        case (.translationShortcut, .translation):
            completedInteractionSteps.insert(.translationShortcut)
        case (.rewriteShortcut, .rewrite):
            completedInteractionSteps.insert(.rewriteShortcut)
        case (.appEnhancement, .transcription):
            if NSApplication.shared.isActive {
                completedInteractionSteps.insert(.appEnhancement)
            }
        default:
            break
        }
    }
}

private extension OnboardingGuideView {
    func isPermissionGranted(_ permission: OnboardingContextualPermission) -> Bool {
        _ = permissionRefreshRevision
        return OnboardingPermissionGrantResolver.isGranted(permission)
    }

    func requestPermission(_ permission: OnboardingContextualPermission) {
        permissionMonitoringKinds.insert(permission)
        switch permission {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in
                    permissionRefreshRevision += 1
                    startPermissionMonitoring(permission)
                }
            }
        case .speechRecognition:
            startPermissionMonitoring(permission)
        case .accessibility:
            let granted = AccessibilityPermissionManager.request(prompt: true)
            if !granted {
                PermissionGuidance.openSettings(for: permission)
            }
            startPermissionMonitoring(permission)
        case .inputMonitoring:
            let granted = EventListeningPermissionManager.requestInputMonitoring(prompt: true)
            if !granted {
                PermissionGuidance.openSettings(for: permission)
            }
            startPermissionMonitoring(permission)
        case .screenCapture:
            let granted = ScreenCapturePermission.requestAccess()
            if !granted {
                PermissionGuidance.openSettings(for: permission)
            }
            startPermissionMonitoring(permission)
        case .systemAudioCapture:
            SystemAudioCapturePermission.requestAccess { _ in
                Task { @MainActor in
                    permissionRefreshRevision += 1
                    startPermissionMonitoring(permission)
                }
            }
        }
    }

    func startPermissionMonitoring(_ permission: OnboardingContextualPermission) {
        permissionMonitorTasks[permission]?.cancel()
        permissionMonitorTasks[permission] = Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(500))
                permissionRefreshRevision += 1
                if isPermissionGranted(permission) {
                    permissionMonitoringKinds.remove(permission)
                    permissionMonitorTasks[permission] = nil
                    return
                }
            }
            permissionMonitoringKinds.remove(permission)
            permissionMonitorTasks[permission] = nil
        }
    }

    func refreshInputDevices() {
        inputDevices = AudioInputDeviceManager.availableInputDevices()
        microphoneState = MicrophonePreferenceManager.syncState(
            defaults: .standard,
            availableDevices: inputDevices
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

    func updateMicrophoneCapture() {
        if currentStep == .microphone {
            startMicrophoneMeter()
        } else {
            stopMicrophoneMeter()
        }
    }

    func startMicrophoneMeter() {
        guard OnboardingPermissionGrantResolver.isGranted(.microphone) else { return }

        stopMicrophoneMeter()
        waveformState.reset()
        waveformState.setActive(true)

        let capture = MeetingMicrophoneCapture()
        capture.setPreferredInputDevice(microphoneState.activeDevice?.id)
        microphoneCapture = capture

        do {
            try capture.start { _, level in
                Task { @MainActor in
                    let displayLevel = guideMicrophoneDisplayLevel(level)
                    waveformState.ingest(level: displayLevel)
                    if displayLevel > 0.035 {
                        completedInteractionSteps.insert(.microphone)
                    }
                }
            }
        } catch {
            VoxtLog.settingsWarning("Guide microphone meter failed: \(error.localizedDescription)")
            stopMicrophoneMeter()
        }
    }

    func stopMicrophoneMeter() {
        microphoneCapture?.stop()
        microphoneCapture = nil
        waveformState.setActive(false)
    }

    func restartMicrophoneMeterIfNeeded() {
        refreshInputDevices()
        if currentStep == .microphone {
            startMicrophoneMeter()
        }
    }

    func guideMicrophoneDisplayLevel(_ level: Float) -> Float {
        let clamped = max(0, min(level, 1))
        guard clamped > 0 else { return 0 }
        let emphasized = Float(pow(Double(clamped), 0.72)) * 1.12
        return min(1, max(clamped, emphasized))
    }
}

private extension OnboardingGuideView {
    func refreshModelStorageDisplayPath() {
        modelStorageDisplayPath = ModelStorageDirectoryManager.resolvedRootURL().path
    }

    func chooseModelStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = ModelStorageDirectoryManager.resolvedRootURL()
        panel.prompt = guideLocalized("Choose")

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        do {
            try ModelStorageDirectoryManager.saveUserSelectedRootURL(selectedURL)
            modelStorageSelectionError = nil
            mlxModelManager.refreshStorageRoot()
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

    func syncModelManagers() {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(mlxModelRepo)
        if canonicalRepo != mlxModelRepo {
            mlxModelRepo = canonicalRepo
        }
        mlxModelManager.updateModel(repo: canonicalRepo)

        let sanitizedCustomLLMRepo = CustomLLMModelManager.isSupportedModelRepo(customLLMRepo)
            ? customLLMRepo
            : CustomLLMModelManager.defaultModelRepo
        if sanitizedCustomLLMRepo != customLLMRepo {
            customLLMRepo = sanitizedCustomLLMRepo
        }
        customLLMManager.updateModel(repo: sanitizedCustomLLMRepo)
    }

    func applyModelFocus(_ focus: OnboardingGuideModelFocus) {
        switch focus {
        case .local:
            engineRaw = TranscriptionEngine.mlxAudio.rawValue
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
        }
        syncFeatureSelections()
    }

    func syncFeatureSelections() {
        let asrSelection: FeatureModelSelectionID
        let llmSelection: FeatureModelSelectionID

        switch modelFocus {
        case .local:
            asrSelection = .mlx(mlxModelRepo)
            llmSelection = .localLLM(customLLMRepo)
        case .remote:
            asrSelection = .remoteASR(selectedRemoteASRProvider)
            llmSelection = .remoteLLM(selectedRemoteLLMProvider)
        }

        var updated = FeatureSettingsStore.load(defaults: .standard)
        updated.transcription.asrSelectionID = asrSelection
        updated.transcription.llmSelectionID = llmSelection
        updated.transcription.notes.titleModelSelectionID = llmSelection
        updated.translation.asrSelectionID = asrSelection
        updated.translation.modelSelectionID = llmSelection
        updated.translation.targetLanguageRawValue = translationTargetLanguage.rawValue
        updated.rewrite.asrSelectionID = asrSelection
        updated.rewrite.llmSelectionID = llmSelection
        updated.meeting.asrSelectionID = asrSelection
        updated.meeting.summaryModelSelectionID = llmSelection
        FeatureSettingsStore.save(updated)
        featureSettings = FeatureSettingsStore.load(defaults: .standard)
    }

    func refreshLocalizedGuideSamples() {
        if temporaryEnhancementPrompt.isEmpty
            || temporaryEnhancementPrompt == Self.defaultTranscriptionEnhancementPromptKey {
            temporaryEnhancementPrompt = Self.defaultTranscriptionEnhancementPrompt
        }
        if temporaryAppEnhancementPrompt.isEmpty
            || temporaryAppEnhancementPrompt == Self.defaultAppEnhancementPromptKey {
            temporaryAppEnhancementPrompt = Self.defaultAppEnhancementPrompt
        }
        if translationInput.isEmpty
            || translationInput == Self.defaultTranslationSampleKey {
            translationInput = Self.defaultTranslationSample
        }
        if rewriteSelectionInput.isEmpty
            || rewriteSelectionInput == Self.defaultRewriteSampleKey {
            rewriteSelectionInput = Self.defaultRewriteSample
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

    func asrCredentialHint(for provider: RemoteASRProvider) -> String? {
        switch provider {
        case .doubaoASR:
            return guideLocalized("Doubao uses App ID + Access Token for streaming API.")
        case .aliyunBailianASR:
            return guideLocalized("Aliyun ASR in Voxt uses realtime WebSocket only: Qwen models use /api-ws/v1/realtime, Fun/Paraformer models use /api-ws/v1/inference.")
        case .openAIWhisper, .glmASR, .stepFunASR:
            return nil
        }
    }

    func isRemoteASRConfigured(_ provider: RemoteASRProvider) -> Bool {
        RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: provider,
            stored: remoteASRConfigurations
        )
        .isConfigured
    }

    func mlxDownloadStatus(for repo: String) -> ModelDownloadStatusSnapshot? {
        guard mlxModelManager.isDownloading(repo: repo) || mlxModelManager.isPaused(repo: repo) else { return nil }
        return ModelDownloadStatusSnapshot.fromMLXState(
            mlxModelManager.state(for: repo),
            pauseMessage: mlxModelManager.pausedStatusMessage(for: repo)
        )
    }

    func customLLMDownloadStatus(for repo: String) -> ModelDownloadStatusSnapshot? {
        guard customLLMManager.currentModelRepo == CustomLLMModelManager.canonicalModelRepo(repo) else { return nil }
        switch customLLMManager.state {
        case .downloading, .paused:
            return ModelDownloadStatusSnapshot.fromCustomLLMState(
                customLLMManager.state,
                pauseMessage: customLLMManager.pausedStatusMessage
            )
        default:
            return nil
        }
    }

    func mlxDownloadErrorMessage(for repo: String) -> String? {
        guard MLXModelManager.canonicalModelRepo(mlxModelManager.currentModelRepo) == MLXModelManager.canonicalModelRepo(repo),
              case .error(let message) = mlxModelManager.state
        else { return nil }
        return message
    }

    func customLLMDownloadErrorMessage(for repo: String) -> String? {
        guard CustomLLMModelManager.canonicalModelRepo(customLLMManager.currentModelRepo) == CustomLLMModelManager.canonicalModelRepo(repo),
              case .error(let message) = customLLMManager.state
        else { return nil }
        return message
    }

    func updateFocusedField() {
        switch currentStep {
        case .transcriptionShortcut:
            focusedField = .transcription
        case .transcriptionEnhancement:
            focusedField = .transcriptionEnhancement
        case .translationShortcut, .translationSelection:
            focusedField = .translation
        case .rewriteShortcut, .rewriteSelection:
            focusedField = .rewrite
        case .appEnhancement:
            focusedField = .appEnhancement
        default:
            focusedField = nil
        }
    }
}

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
    @State private var showsMoreLocalASRModels = false
    @State private var showsMoreLocalLLMModels = false
    @State private var showsMoreRemoteASRProviders = false
    @State private var showsMoreRemoteLLMProviders = false
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
    @State private var microphoneSignalFrameCount = 0
    @State private var microphoneReceivedInitialBuffer = false
    @State private var microphoneStartupRetryCount = 0
    @State private var microphoneStartupWatchdogTask: Task<Void, Never>?
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

    private static var defaultTranscriptionEnhancementPrompt: String {
        AppPromptResourceStore.requiredText(
            for: .onboardingTranscriptionEnhancement,
            language: AppLocalization.language
        )
    }

    private static var defaultAppEnhancementPrompt: String {
        AppPromptResourceStore.requiredText(
            for: .onboardingAppEnhancement,
            language: AppLocalization.language
        )
    }

    private static func isBundledGuidePrompt(
        _ text: String,
        resource: LocalizedPromptResource
    ) -> Bool {
        [.english, .chineseSimplified, .japanese].contains { language in
            AppPromptResourceStore.text(for: resource, language: language) == text
        }
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
    private static let shellHeaderHeight: CGFloat = 58
    private static let shellSideCutoutWidth: CGFloat = 58
    private static let contentBottomCompensation: CGFloat = 0
    private static let microphoneRawSignalThreshold: Float = 0.006
    private static let microphoneDisplaySignalThreshold: Float = 0.022
    private static let microphoneRequiredSignalFrames = 2
    private static let microphoneStartupWatchdogDelay: Duration = .milliseconds(1200)
    private static let defaultRemoteASRProviders: [RemoteASRProvider] = [
        .doubaoASR,
        .aliyunBailianASR,
        .stepFunASR,
        .xiaomiMiMoASR
    ]
    private static let defaultRemoteLLMProviders: [RemoteLLMProvider] = [
        .volcengine,
        .aliyunBailian,
        .stepFun,
        .xiaomiMiMo
    ]

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
        isRemoteASRConfigured(selectedRemoteASRProvider) && RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
            provider: selectedRemoteLLMProvider,
            stored: remoteLLMConfigurations
        )
    }

    private var localASRRepos: [String] {
        var repos = mlxModelManager.displayModelsIncludingInstalled()
            .map { MLXModelManager.canonicalModelRepo($0.id) }
        let selectedRepo = MLXModelManager.canonicalModelRepo(mlxModelRepo)
        if !repos.contains(selectedRepo) {
            repos.insert(selectedRepo, at: 0)
        }
        return repos
    }

    private var localLLMRepos: [String] {
        var repos = customLLMManager.displayModelsIncludingInstalled()
            .map { CustomLLMModelManager.canonicalModelRepo($0.id) }
        let selectedRepo = CustomLLMModelManager.canonicalModelRepo(customLLMRepo)
        if !repos.contains(selectedRepo) {
            repos.insert(selectedRepo, at: 0)
        }
        return repos
    }

    private var defaultLocalASRRepos: [String] {
        let qwen06Repo = localASRRepos.first { repo in
            let text = "\(repo) \(mlxModelManager.displayTitle(for: repo))".lowercased()
            return text.contains("qwen") && text.contains("0.6")
        }
        return qwen06Repo.map { [$0] } ?? Array(localASRRepos.prefix(1))
    }

    private var defaultLocalLLMRepos: [String] {
        let gemma4E2BRepo = localLLMRepos.first { repo in
            let text = "\(repo) \(customLLMManager.displayTitle(for: repo))".lowercased()
            return text.contains("gemma") && text.contains("4") && text.contains("e2b")
        }
        return gemma4E2BRepo.map { [$0] } ?? Array(localLLMRepos.prefix(1))
    }

    private var displayedLocalASRRepos: [String] {
        showsMoreLocalASRModels ? localASRRepos : defaultLocalASRRepos
    }

    private var displayedLocalLLMRepos: [String] {
        showsMoreLocalLLMModels ? localLLMRepos : defaultLocalLLMRepos
    }

    private var displayedRemoteASRProviders: [RemoteASRProvider] {
        if showsMoreRemoteASRProviders {
            return RemoteASRProvider.allCases
        }
        return Self.defaultRemoteASRProviders.filter { RemoteASRProvider.allCases.contains($0) }
    }

    private var displayedRemoteLLMProviders: [RemoteLLMProvider] {
        if showsMoreRemoteLLMProviders {
            return RemoteLLMProvider.allCases
        }
        return Self.defaultRemoteLLMProviders.filter { RemoteLLMProvider.allCases.contains($0) }
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
        guideWithNotifications
            .background(
                OnboardingGuideHotkeyObserver { hotkeyKind in
                    handleShortcutObserved(hotkeyKind)
                }
                .frame(width: 0, height: 0)
            )
    }

    private var guideShell: some View {
        ZStack {
            GeometryReader { proxy in
                let shellHeight = max(
                    0,
                    proxy.size.height
                        - Self.outerPadding
                        - Self.outerBottomPadding
                        + Self.contentBottomCompensation
                )
                let contentHeight = max(0, shellHeight - Self.shellHeaderHeight)

                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        headerNavigation
                            .frame(height: Self.shellHeaderHeight)

                        content
                            .frame(maxWidth: .infinity)
                            .frame(height: contentHeight)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: shellHeight)
                    .background(
                        OnboardingGuideShellShape(
                            headerHeight: Self.shellHeaderHeight,
                            sideCutoutWidth: Self.shellSideCutoutWidth,
                            cornerRadius: OnboardingGuideStyle.panelCornerRadius,
                            transitionRadius: OnboardingGuideStyle.headerTransitionRadius
                        )
                        .fill(OnboardingGuideStyle.panelFill)
                    )
                    .overlay(
                        OnboardingGuideShellShape(
                            headerHeight: Self.shellHeaderHeight,
                            sideCutoutWidth: Self.shellSideCutoutWidth,
                            cornerRadius: OnboardingGuideStyle.panelCornerRadius,
                            transitionRadius: OnboardingGuideStyle.headerTransitionRadius
                        )
                        .stroke(OnboardingGuideStyle.panelBorder, lineWidth: 1)
                    )
                    .clipShape(
                        OnboardingGuideShellShape(
                            headerHeight: Self.shellHeaderHeight,
                            sideCutoutWidth: Self.shellSideCutoutWidth,
                            cornerRadius: OnboardingGuideStyle.panelCornerRadius,
                            transitionRadius: OnboardingGuideStyle.headerTransitionRadius
                        )
                    )

                    topChrome
                        .frame(height: Self.shellHeaderHeight)
                }
                .padding(.top, Self.outerPadding)
                .padding(.horizontal, Self.outerPadding)
                .padding(.bottom, Self.outerBottomPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .frame(width: Self.windowSize.width, height: Self.windowSize.height)

            onboardingModalOverlay
        }
    }

    private var styledGuideShell: some View {
        guideShell
        .background(OnboardingGuideStyle.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: OnboardingGuideStyle.windowCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingGuideStyle.windowCornerRadius, style: .continuous)
                .strokeBorder(OnboardingGuideStyle.windowBorder, lineWidth: 1)
        )
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .environment(\.locale, interfaceLanguage.locale)
        .groupBoxStyle(SettingsPanelGroupBoxStyle())
    }

    private var guideWithStateLifecycle: some View {
        styledGuideShell
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
    }

    private var guideWithNotifications: some View {
        guideWithStateLifecycle
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
        .onReceive(NotificationCenter.default.publisher(for: .voxtHotkeyDidTrigger)) { notification in
            guard let rawKind = notification.userInfo?["kind"] as? String,
                  let kind = OnboardingGuideShortcutKind(rawValue: rawKind)
            else { return }
            handleShortcutObserved(kind)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshRevision += 1
        }
    }

    private var topChrome: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(OnboardingGuideIconButtonStyle())
            .help(guideLocalized("Exit Guide"))

            Spacer(minLength: 0)

            OnboardingGuideProgressRing(
                current: currentStep.stepNumber,
                total: OnboardingGuideStep.allCases.count
            )
        }
        .padding(.horizontal, 12)
    }

    private var headerNavigation: some View {
        HStack(spacing: 8) {
            if let previous = currentStep.previous {
                OnboardingGuideHeaderStepButton(
                    title: previous.title,
                    alignment: .trailing,
                    isEnabled: true,
                    action: {
                        currentStep = previous
                    }
                )
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
            }

            Text(currentStep.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingGuideStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 200)

            if let next = currentStep.next {
                OnboardingGuideHeaderStepButton(
                    title: next.title,
                    alignment: .leading,
                    isEnabled: canContinue,
                    action: {
                        guard canContinue else { return }
                        currentStep = next
                    }
                )
                .help(canContinue ? "" : continueDisabledHelp)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Self.shellSideCutoutWidth + 18)
    }

    @ViewBuilder
    private var content: some View {
        if currentStep == .permissions {
            permissionsGuidePanel
        } else if currentStep == .microphone {
            microphoneGuidePanel
        } else if currentStep == .models {
            modelGuidePanel
        } else {
            regularGuidePanel
        }
    }

    @ViewBuilder
    private var onboardingModalOverlay: some View {
        if isMicrophonePriorityDialogPresented {
            onboardingModalScrim {
                MicrophonePriorityDialog(
                    state: microphoneState,
                    onUseNow: { uid in
                        focusMicrophone(uid: uid)
                        restartMicrophoneMeterIfNeeded()
                    },
                    onAutoSwitchChanged: setMicrophoneAutoSwitchEnabled(_:),
                    onReorderPriority: applyMicrophonePriorityOrder(_:),
                    cornerRadius: OnboardingGuideStyle.modalCornerRadius,
                    onClose: {
                        isMicrophonePriorityDialogPresented = false
                    }
                )
            }
        } else if isModelStorageDialogPresented {
            onboardingModalScrim {
                modelStorageDialog
            }
        } else if let provider = editingASRProvider {
            onboardingModalScrim {
                RemoteProviderConfigurationSheet(
                    providerTitle: provider.title,
                    credentialHint: asrCredentialHint(for: provider),
                    showsDoubaoFields: provider == .doubaoASR,
                    testTarget: .asr(provider),
                    configuration: RemoteModelConfigurationStore.resolvedASRConfiguration(
                        provider: provider,
                        from: remoteASRProviderConfigurationsRaw
                    ),
                    onSave: saveRemoteASRConfiguration(_:),
                    cornerRadius: OnboardingGuideStyle.modalCornerRadius,
                    onClose: {
                        editingASRProvider = nil
                    }
                )
            }
        } else if let provider = editingLLMProvider {
            onboardingModalScrim {
                RemoteProviderConfigurationSheet(
                    providerTitle: provider.title,
                    credentialHint: nil,
                    showsDoubaoFields: false,
                    testTarget: .llm(provider),
                    configuration: RemoteModelConfigurationStore.resolvedLLMConfiguration(
                        provider: provider,
                        from: remoteLLMProviderConfigurationsRaw
                    ),
                    onSave: saveRemoteLLMConfiguration(_:),
                    cornerRadius: OnboardingGuideStyle.modalCornerRadius,
                    onClose: {
                        editingLLMProvider = nil
                    }
                )
            }
        } else if let shortcut = editingShortcut {
            onboardingModalScrim {
                shortcutSheet(for: shortcut)
            }
        } else if isPromptDialogPresented {
            onboardingModalScrim {
                promptSheet(
                    title: guideLocalized("Enhancement Prompt"),
                    text: $temporaryEnhancementPrompt
                )
            }
        } else if isAppPromptDialogPresented {
            onboardingModalScrim {
                promptSheet(
                    title: guideLocalized("Temporary App Enhancement Prompt"),
                    text: $temporaryAppEnhancementPrompt
                )
            }
        }
    }

    private func onboardingModalScrim<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            OnboardingGuideStyle.modalScrim
                .contentShape(Rectangle())

            content()
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .clipShape(RoundedRectangle(cornerRadius: OnboardingGuideStyle.windowCornerRadius, style: .continuous))
        .zIndex(10)
    }

    private var permissionsGuidePanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 16) {
                Text(currentStep.subtitle)
                    .font(.callout)
                    .foregroundStyle(OnboardingGuideStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560)

                permissionsActions
                    .frame(maxWidth: 520)
            }
            .frame(maxWidth: 560)

            Spacer(minLength: 0)

            permissionsFooter
                .frame(maxWidth: 520)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var microphoneGuidePanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                OnboardingMicrophoneWaveformView(waveformState: waveformState)
                    .frame(maxWidth: 360)

                VStack(spacing: 11) {
                    Text(currentStep.subtitle)
                        .font(.callout)
                        .foregroundStyle(OnboardingGuideStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560)

                    GuideInfoRow(
                        title: guideLocalized("Current Microphone"),
                        value: microphoneState.activeDevice?.name ?? guideLocalized("No available microphone devices")
                    )
                    .frame(maxWidth: 520)

                    Text(completedInteractionSteps.contains(.microphone)
                        ? guideLocalized("Signal detected")
                        : guideLocalized("Speak normally for one or two seconds."))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(completedInteractionSteps.contains(.microphone) ? Color.green : OnboardingGuideStyle.secondaryText)
                }
                .frame(maxWidth: 560)
            }
            .frame(maxWidth: 560)

            Spacer(minLength: 0)

            footer
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var regularGuidePanel: some View {
        HStack(spacing: 0) {
            actionPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(OnboardingGuideStyle.panelBorder)
                .frame(width: 1)

            tourPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modelGuidePanel: some View {
        VStack(spacing: 0) {
            modelSelectionContent
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            modelFooter
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tourPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            guideVisual
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            OnboardingGuideStyle.visualTopFill,
                            OnboardingGuideStyle.visualBottomFill
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: OnboardingGuideStyle.panelFill.opacity(0.20), location: 0.58),
                            .init(color: OnboardingGuideStyle.panelFill.opacity(0.84), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                )
                .clipShape(RoundedRectangle(cornerRadius: OnboardingGuideStyle.innerCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingGuideStyle.innerCornerRadius, style: .continuous)
                        .strokeBorder(OnboardingGuideStyle.subtleBorder, lineWidth: 1)
                )
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(currentStep.subtitle)
                .font(.callout)
                .foregroundStyle(OnboardingGuideStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

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
            EmptyView()
        case .microphone:
            EmptyView()
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
            meetingVisual
        case .finish:
            finishVisual
        case .models:
            EmptyView()
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

    private var meetingVisual: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(guideLocalized("Meeting Setup"))
                        .font(.headline)
                    Text(guideLocalized("These settings are used when you start meeting capture."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GuideInfoRow(title: guideLocalized("Audio Model"), value: asrSelectionSummary(featureSettings.meeting.asrSelectionID))
            GuideInfoRow(title: guideLocalized("Summary Model"), value: llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID))
            GuideInfoRow(title: guideLocalized("Segmentation Mode"), value: featureSettings.meeting.chunkingMode.title)
            GuideInfoRow(title: guideLocalized("Speaker Separation"), value: featureSettings.meeting.speakerDiarizationModel.title)
            GuideInfoRow(
                title: guideLocalized("Auto Summary"),
                value: featureSettings.meeting.summaryAutoGenerate ? guideLocalized("Enabled") : guideLocalized("Disabled")
            )
        }
        .padding(16)
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
            GuideBullet(text: guideLocalized("Meeting uses the selected speech model for live transcript capture."))
            GuideBullet(text: guideLocalized("Summaries use the selected summary model and can auto-generate after recording."))
            GuideBullet(text: guideLocalized("Speaker separation runs after recording when the selected model is ready."))

            if completedInteractionSteps.contains(.meeting) {
                Label(guideLocalized("Meeting shortcut detected"), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
            }
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
            Divider()
            GuideInfoRow(title: guideLocalized("Speech Model"), value: asrSelectionSummary(featureSettings.transcription.asrSelectionID))
            GuideInfoRow(title: guideLocalized("Text Enhancement"), value: featureSettings.transcription.llmEnabled ? llmSelectionSummary(featureSettings.transcription.llmSelectionID) : guideLocalized("Disabled"))
            GuideInfoRow(title: guideLocalized("Translation Model"), value: translationSelectionSummary(featureSettings.translation.modelSelectionID))
            GuideInfoRow(title: guideLocalized("Notes"), value: guideLocalized("Enabled"))
            GuideInfoRow(title: guideLocalized("Meeting Summary"), value: llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID))
        }
    }

    private var modelSelectionContent: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                modelTabItem(
                    focus: .local,
                    title: guideLocalized("Local"),
                    subtitle: guideLocalized("Private and offline after download. Install one speech-to-text model and one large language model before continuing.")
                )

                modelTabItem(
                    focus: .remote,
                    title: guideLocalized("Remote"),
                    subtitle: guideLocalized("Fast to start. Configure the selected remote speech-to-text and large language model providers before continuing.")
                )
            }

            ScrollView {
                Group {
                    switch modelFocus {
                    case .local:
                        localModelActions
                    case .remote:
                        remoteModelActions
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
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
        }
        .animation(.easeInOut(duration: 0.18), value: modelFocus)
    }

    private func modelTabItem(
        focus: OnboardingGuideModelFocus,
        title: String,
        subtitle: String
    ) -> some View {
        let isActive = modelFocus == focus
        return Button {
            modelFocus = focus
            applyModelFocus(focus)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(OnboardingGuideStyle.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(OnboardingGuideStyle.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : SettingsUIStyle.panelFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.35) : SettingsUIStyle.panelBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var localModelActions: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(guideLocalized("Speech-to-text Model"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(displayedLocalASRRepos, id: \.self) { repo in
                    localASRModelRow(repo: repo)
                }
                if localASRRepos.count > defaultLocalASRRepos.count {
                    moreListButton(
                        isExpanded: showsMoreLocalASRModels,
                        expandedCount: localASRRepos.count,
                        collapsedCount: defaultLocalASRRepos.count
                    ) {
                        showsMoreLocalASRModels.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                Text(guideLocalized("Large Language Model"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(displayedLocalLLMRepos, id: \.self) { repo in
                    localLLMModelRow(repo: repo)
                }
                if localLLMRepos.count > defaultLocalLLMRepos.count {
                    moreListButton(
                        isExpanded: showsMoreLocalLLMModels,
                        expandedCount: localLLMRepos.count,
                        collapsedCount: defaultLocalLLMRepos.count
                    ) {
                        showsMoreLocalLLMModels.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var remoteModelActions: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(guideLocalized("Speech-to-text Model"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(displayedRemoteASRProviders) { provider in
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
                if RemoteASRProvider.allCases.count > Self.defaultRemoteASRProviders.count {
                    moreListButton(
                        isExpanded: showsMoreRemoteASRProviders,
                        expandedCount: RemoteASRProvider.allCases.count,
                        collapsedCount: Self.defaultRemoteASRProviders.count
                    ) {
                        showsMoreRemoteASRProviders.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                Text(guideLocalized("Large Language Model"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(displayedRemoteLLMProviders) { provider in
                    remoteProviderRow(
                        title: onboardingRemoteLLMProviderTitle(provider),
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
                if RemoteLLMProvider.allCases.count > Self.defaultRemoteLLMProviders.count {
                    moreListButton(
                        isExpanded: showsMoreRemoteLLMProviders,
                        expandedCount: RemoteLLMProvider.allCases.count,
                        collapsedCount: Self.defaultRemoteLLMProviders.count
                    ) {
                        showsMoreRemoteLLMProviders.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            leadingFooterAction

            if currentStep == .finish {
                Button {
                    OnboardingPreferenceManager.markCompleted()
                    onFinish()
                } label: {
                    Label(guideLocalized("Start Voxt"), systemImage: "checkmark.circle")
                }
                .buttonStyle(OnboardingGuidePrimaryButtonStyle())
            } else if let next = currentStep.next {
                Button {
                    currentStep = next
                } label: {
                    Label(guideLocalized("Continue"), systemImage: "chevron.right")
                        .labelStyle(OnboardingGuideNextLabelStyle())
                }
                .buttonStyle(OnboardingGuidePrimaryButtonStyle())
                .disabled(!canContinue)
                .help(canContinue ? "" : continueDisabledHelp)
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OnboardingGuideStyle.panelBorder)
                .frame(height: 1)
        }
    }

    private var modelFooter: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            if modelFocus == .local {
                Button(guideLocalized("Model Location")) {
                    isModelStorageDialogPresented = true
                }
                .buttonStyle(OnboardingGuideSecondaryButtonStyle())
            }

            if let next = currentStep.next {
                Button {
                    currentStep = next
                } label: {
                    Label(guideLocalized("Continue"), systemImage: "chevron.right")
                        .labelStyle(OnboardingGuideNextLabelStyle())
                }
                .buttonStyle(OnboardingGuidePrimaryButtonStyle())
                .disabled(!canContinue)
                .help(canContinue ? "" : continueDisabledHelp)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    private var permissionsFooter: some View {
        HStack {
            Spacer(minLength: 0)

            if let next = currentStep.next {
                Button {
                    currentStep = next
                } label: {
                    Label(guideLocalized("Continue"), systemImage: "chevron.right")
                        .labelStyle(OnboardingGuideNextLabelStyle())
                }
                .buttonStyle(OnboardingGuidePrimaryButtonStyle())
                .disabled(!canContinue)
                .help(canContinue ? "" : continueDisabledHelp)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var leadingFooterAction: some View {
        switch currentStep {
        case .microphone:
            Button(guideLocalized("Switch Microphone")) {
                isMicrophonePriorityDialogPresented = true
            }
            .buttonStyle(OnboardingGuideSecondaryButtonStyle())
        case .models where modelFocus == .local:
            Button(guideLocalized("Model Location")) {
                isModelStorageDialogPresented = true
            }
            .buttonStyle(OnboardingGuideSecondaryButtonStyle())
        case .transcriptionShortcut:
            Button(guideLocalized("Change Shortcut")) {
                editingShortcut = .transcription
            }
            .buttonStyle(OnboardingGuideSecondaryButtonStyle())
        case .transcriptionEnhancement:
            Button(guideLocalized("Edit Prompt")) {
                isPromptDialogPresented = true
            }
            .buttonStyle(OnboardingGuideSecondaryButtonStyle())
        case .translationShortcut:
            Button(guideLocalized("Change Shortcut")) {
                editingShortcut = .translation
            }
            .buttonStyle(OnboardingGuideSecondaryButtonStyle())
        case .rewriteShortcut:
            Button(guideLocalized("Change Shortcut")) {
                editingShortcut = .rewrite
            }
            .buttonStyle(OnboardingGuideSecondaryButtonStyle())
        case .appEnhancement:
            Button(guideLocalized("Enhancement Prompt")) {
                isAppPromptDialogPresented = true
            }
            .buttonStyle(OnboardingGuideSecondaryButtonStyle())
        case .meeting:
            Button(guideLocalized("Change Shortcut")) {
                editingShortcut = .meeting
            }
            .buttonStyle(OnboardingGuideSecondaryButtonStyle())
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
                : guideLocalized("Configure the selected remote ASR and LLM providers to continue.")
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

private enum OnboardingGuideStyle {
    static let windowCornerRadius: CGFloat = 22
    static let panelCornerRadius: CGFloat = 20
    static let modalCornerRadius: CGFloat = 18
    static let innerCornerRadius: CGFloat = 16
    static let headerTransitionRadius: CGFloat = 24

    static let windowBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.965, green: 0.968, blue: 0.972, alpha: 1),
        dark: NSColor(calibratedRed: 0.080, green: 0.085, blue: 0.090, alpha: 1)
    )
    static let windowBorder = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.12)
    )
    static let modalScrim = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.22),
        dark: NSColor.black.withAlphaComponent(0.46)
    )
    static let panelFill = dynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.105, green: 0.110, blue: 0.120, alpha: 1)
    )
    static let panelBorder = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.065),
        dark: NSColor.white.withAlphaComponent(0.10)
    )
    static let subtleBorder = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.075),
        dark: NSColor.white.withAlphaComponent(0.12)
    )
    static let visualTopFill = dynamicColor(
        light: NSColor(calibratedRed: 0.925, green: 0.940, blue: 0.960, alpha: 1),
        dark: NSColor(calibratedRed: 0.160, green: 0.180, blue: 0.200, alpha: 1)
    )
    static let visualBottomFill = dynamicColor(
        light: NSColor(calibratedRed: 0.982, green: 0.984, blue: 0.988, alpha: 1),
        dark: NSColor(calibratedRed: 0.085, green: 0.090, blue: 0.100, alpha: 1)
    )
    static let primaryText = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.90),
        dark: NSColor.white.withAlphaComponent(0.96)
    )
    static let secondaryText = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.62),
        dark: NSColor.white.withAlphaComponent(0.68)
    )
    static let mutedText = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.42),
        dark: NSColor.white.withAlphaComponent(0.46)
    )
    static let controlFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.11)
    )
    static let controlPressedFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.095),
        dark: NSColor.white.withAlphaComponent(0.17)
    )
    static let progressTrack = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.16)
    )
    static let primaryButtonBorder = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.30),
        dark: NSColor.white.withAlphaComponent(0.20)
    )

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return dark
            default:
                return light
            }
        })
    }
}

private struct OnboardingGuideShellShape: Shape {
    let headerHeight: CGFloat
    let sideCutoutWidth: CGFloat
    let cornerRadius: CGFloat
    let transitionRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let topInset = min(max(sideCutoutWidth, 0), width / 3)
        let headerHeight = min(max(headerHeight, 0), height)
        let cornerRadius = min(max(cornerRadius, 0), width / 2, height / 2)
        let transitionRadius = min(max(transitionRadius, 0), topInset, headerHeight)

        var path = Path()
        path.move(to: CGPoint(x: topInset + cornerRadius, y: 0))
        path.addLine(to: CGPoint(x: width - topInset - cornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: width - topInset, y: cornerRadius),
            control: CGPoint(x: width - topInset, y: 0)
        )
        path.addLine(to: CGPoint(x: width - topInset, y: headerHeight - transitionRadius))
        path.addQuadCurve(
            to: CGPoint(x: width - topInset + transitionRadius, y: headerHeight),
            control: CGPoint(x: width - topInset, y: headerHeight)
        )
        path.addLine(to: CGPoint(x: width - cornerRadius, y: headerHeight))
        path.addQuadCurve(
            to: CGPoint(x: width, y: headerHeight + cornerRadius),
            control: CGPoint(x: width, y: headerHeight)
        )
        path.addLine(to: CGPoint(x: width, y: height - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: width - cornerRadius, y: height),
            control: CGPoint(x: width, y: height)
        )
        path.addLine(to: CGPoint(x: cornerRadius, y: height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: height - cornerRadius),
            control: CGPoint(x: 0, y: height)
        )
        path.addLine(to: CGPoint(x: 0, y: headerHeight + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: headerHeight),
            control: CGPoint(x: 0, y: headerHeight)
        )
        path.addLine(to: CGPoint(x: topInset - transitionRadius, y: headerHeight))
        path.addQuadCurve(
            to: CGPoint(x: topInset, y: headerHeight - transitionRadius),
            control: CGPoint(x: topInset, y: headerHeight)
        )
        path.addLine(to: CGPoint(x: topInset, y: cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: topInset + cornerRadius, y: 0),
            control: CGPoint(x: topInset, y: 0)
        )
        path.closeSubpath()
        return path
    }
}

private struct OnboardingGuideHeaderStepButton: View {
    let title: String
    let alignment: Alignment
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var opacity: Double {
        guard isEnabled else { return 0.24 }
        return isHovered ? 0.82 : 0.38
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnboardingGuideStyle.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(opacity)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .frame(maxWidth: .infinity)
    }
}

private struct OnboardingGuideProgressRing: View {
    let current: Int
    let total: Int

    private let ringSize: CGFloat = 32
    private let totalBadgeSize: CGFloat = 14

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(current) / CGFloat(total)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .stroke(OnboardingGuideStyle.progressTrack, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.74, blue: 1.0),
                                Color(red: 0.08, green: 0.48, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(current)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(OnboardingGuideStyle.primaryText)
                    .monospacedDigit()
            }
            .frame(width: ringSize, height: ringSize)

            Text("\(total)")
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(OnboardingGuideStyle.primaryText)
                .monospacedDigit()
                .frame(width: totalBadgeSize, height: totalBadgeSize)
                .background(
                    Circle()
                        .fill(OnboardingGuideStyle.panelFill)
                )
                .overlay(
                    Circle()
                        .strokeBorder(OnboardingGuideStyle.subtleBorder, lineWidth: 1)
                )
        }
        .frame(width: 32, height: 32)
        .accessibilityLabel(Text(AppLocalization.format("%d/%d", current, total)))
    }
}

private struct OnboardingGuideIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OnboardingGuideStyle.primaryText)
            .background(
                Circle()
                    .fill(configuration.isPressed ? OnboardingGuideStyle.controlPressedFill : OnboardingGuideStyle.controlFill)
            )
            .overlay(
                Circle()
                    .strokeBorder(OnboardingGuideStyle.subtleBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Circle())
    }
}

private struct OnboardingGuidePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minWidth: 86, minHeight: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 0.94))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(OnboardingGuideStyle.primaryButtonBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule(style: .continuous))
    }
}

private struct OnboardingGuideSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OnboardingGuideStyle.primaryText)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? OnboardingGuideStyle.controlPressedFill : OnboardingGuideStyle.controlFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(OnboardingGuideStyle.subtleBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule(style: .continuous))
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

private struct OnboardingMicrophoneWaveformView: View {
    @ObservedObject var waveformState: RecentAudioWaveformState

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<waveformState.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.88))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = waveformState.barLevels.indices.contains(index) ? waveformState.barLevels[index] : 0
        return WaveformBarVisuals.barHeight(
            level: level,
            minHeight: 7,
            maxHeight: 52
        )
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

private struct OnboardingShortcutCaptureRow: View {
    let title: String
    let detail: String
    @Binding var shortcut: HotkeyPreference.HotkeyBinding
    let defaultHotkey: HotkeyPreference.Hotkey

    @State private var isRecording = false
    @State private var pendingCapturedHotkey: HotkeyPreference.Hotkey?

    private var behaviorSelection: Binding<HotkeyPreference.TriggerBehavior> {
        Binding(
            get: { shortcut.behavior },
            set: { behavior in
                shortcut.behavior = behavior
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GeometryReader { proxy in
                let pickerWidth: CGFloat = 112
                HStack(alignment: .center, spacing: 8) {
                    SettingsShortcutCaptureField(
                        title: LocalizedStringKey(""),
                        hotkey: pendingCapturedHotkey ?? shortcut.hotkey,
                        isRecording: isRecording,
                        isPendingConfirmation: pendingCapturedHotkey != nil,
                        distinguishModifierSides: false,
                        showsTitle: false,
                        controlWidth: max(280, proxy.size.width - pickerWidth - 8),
                        onFocus: {
                            pendingCapturedHotkey = nil
                            isRecording = true
                        },
                        onReset: {
                            shortcut.hotkey = defaultHotkey
                            shortcut.behavior = .tap
                            pendingCapturedHotkey = nil
                            isRecording = false
                        },
                        onCancelPending: {
                            pendingCapturedHotkey = nil
                            isRecording = false
                        },
                        onConfirmPending: {
                            if let pendingCapturedHotkey {
                                shortcut.hotkey = pendingCapturedHotkey
                            }
                            pendingCapturedHotkey = nil
                            isRecording = false
                        }
                    )

                    SettingsMenuPicker(
                        selection: behaviorSelection,
                        options: HotkeyPreference.TriggerBehavior.allCases.map { behavior in
                            SettingsMenuOption(value: behavior, title: behavior.title)
                        },
                        selectedTitle: shortcut.behavior.title,
                        width: pickerWidth,
                        allowsCompactWidth: true,
                        usesCompactInsets: true
                    )
                }
            }
            .frame(height: 34)

            HotkeyRecorderView(
                isRecording: $isRecording,
                onCapture: { capturedHotkey in
                    pendingCapturedHotkey = capturedHotkey
                },
                onCancelCapture: {
                    pendingCapturedHotkey = nil
                    isRecording = false
                },
                onRecorderMessageChange: { _ in }
            )
            .frame(width: 0, height: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            bindings(for: kind).contains { binding in
                guard binding.behavior != .doubleTap else { return false }
                return matches(hotkey: binding.hotkey, event: event)
            }
        }

        private func bindings(for kind: OnboardingGuideShortcutKind) -> [HotkeyPreference.HotkeyBinding] {
            switch kind {
            case .transcription:
                return HotkeyPreference.loadTranscriptionBindings()
            case .translation:
                return HotkeyPreference.loadTranslationBindings()
            case .rewrite:
                return HotkeyPreference.loadRewriteBindings()
            case .meeting:
                return HotkeyPreference.loadMeetingBindings()
            }
        }

        private func matches(hotkey: HotkeyPreference.Hotkey, event: NSEvent) -> Bool {
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
        .settingsDialogChrome(width: 420, cornerRadius: OnboardingGuideStyle.modalCornerRadius, onClose: {
            isModelStorageDialogPresented = false
        })
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
        .settingsDialogChrome(width: 480, cornerRadius: OnboardingGuideStyle.modalCornerRadius, onClose: {
            isPromptDialogPresented = false
            isAppPromptDialogPresented = false
        })
    }

    func shortcutSheet(for kind: OnboardingGuideShortcutKind) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingShortcutCaptureRow(
                title: AppLocalization.format("%@ %@", kind.title, guideLocalized("Shortcut")),
                detail: guideLocalized("Capture a new shortcut for this workflow. The change is saved immediately after confirmation."),
                shortcut: shortcutBinding(for: kind),
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
        .settingsDialogChrome(width: 460, cornerRadius: OnboardingGuideStyle.modalCornerRadius, onClose: {
            editingShortcut = nil
        })
    }

    func shortcutBinding(for kind: OnboardingGuideShortcutKind) -> Binding<HotkeyPreference.HotkeyBinding> {
        Binding(
            get: {
                shortcutBindings(for: kind).first ?? HotkeyPreference.HotkeyBinding(
                    hotkey: kind.defaultHotkey,
                    behavior: .tap
                )
            },
            set: { binding in
                hotkeyPresetRaw = HotkeyPreference.Preset.custom.rawValue
                var bindings = shortcutBindings(for: kind)
                if bindings.isEmpty {
                    bindings = [binding]
                } else {
                    bindings[0] = binding
                }
                saveShortcutBindings(bindings, for: kind)
            }
        )
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
            sizeText: mlxModelManager.remoteSizeText(repo: repo),
            ratingText: MLXModelManager.ratingText(for: repo),
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
            sizeText: customLLMManager.remoteSizeText(repo: repo),
            ratingText: CustomLLMModelManager.ratingText(for: repo),
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
            onPause: { customLLMManager.pauseDownload(repo: repo) },
            onCancel: { customLLMManager.cancelDownload(repo: repo) }
        )
    }

    func localModelRow(
        title: String,
        repo: String,
        sizeText: String,
        ratingText: String,
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
            HStack(spacing: 10) {
                ModelLogoView(
                    key: ModelLogoKey.resolve(title: title, engine: repo),
                    fallbackTitle: title,
                    size: 24
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        modelMetaPill(text: sizeText, systemImage: "externaldrive")
                        modelInstallStatusPill(
                            text: localInstallStatusText(isInstalled: isInstalled, status: status),
                            isInstalled: isInstalled,
                            isActive: status != nil
                        )
                        modelMetaPill(text: ratingText, systemImage: "star.fill")
                    }
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

    func moreListButton(
        isExpanded: Bool,
        expandedCount: Int,
        collapsedCount: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(isExpanded ? guideLocalized("Less") : guideLocalized("More"))
                    .font(.caption.weight(.semibold))
                Text("\(isExpanded ? collapsedCount : expandedCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SettingsCompactActionButtonStyle(height: 26, horizontalPadding: 8))
    }

    func localInstallStatusText(isInstalled: Bool, status: ModelDownloadStatusSnapshot?) -> String {
        if let status {
            return status.titleText
        }
        return isInstalled ? guideLocalized("Installed") : guideLocalized("Not installed")
    }

    func onboardingRemoteLLMProviderTitle(_ provider: RemoteLLMProvider) -> String {
        switch provider {
        case .volcengine:
            return guideLocalized("Doubao")
        default:
            return provider.title
        }
    }

    func modelMetaPill(text: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(SettingsUIStyle.panelFillColor)
        )
    }

    func modelInstallStatusPill(text: String, isInstalled: Bool, isActive: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(isInstalled ? Color.green : (isActive ? Color.accentColor : .secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill((isInstalled ? Color.green : (isActive ? Color.accentColor : Color.secondary)).opacity(0.12))
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
            HStack(alignment: .top, spacing: 8) {
                ModelLogoView(
                    key: ModelLogoKey.resolve(title: title, engine: "remote"),
                    fallbackTitle: title,
                    size: 22
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(isConfigured ? guideLocalized("Configured") : guideLocalized("Not configured"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isConfigured ? Color.green : .secondary)
                        .lineLimit(1)
                }
                Spacer()

                HStack(spacing: 6) {
                    Button(isSelected ? guideLocalized("Selected") : guideLocalized("Use")) {
                        onSelect()
                    }
                    .buttonStyle(SettingsCompactActionButtonStyle(height: 24, horizontalPadding: 8))
                    .disabled(isSelected)

                    Button(guideLocalized("Configure")) {
                        onConfigure()
                    }
                    .buttonStyle(SettingsCompactActionButtonStyle(height: 24, horizontalPadding: 8))
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : SettingsUIStyle.controlFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.26) : SettingsUIStyle.subtleBorderColor, lineWidth: 1)
        )
    }

    func shortcutDisplay(for kind: OnboardingGuideShortcutKind) -> String {
        let hotkey: HotkeyPreference.Hotkey
        switch kind {
        case .transcription:
            hotkey = shortcutBindings(for: kind).first?.hotkey ?? HotkeyPreference.load()
        case .translation:
            hotkey = shortcutBindings(for: kind).first?.hotkey ?? HotkeyPreference.loadTranslation()
        case .rewrite:
            hotkey = shortcutBindings(for: kind).first?.hotkey ?? HotkeyPreference.loadRewrite()
        case .meeting:
            hotkey = shortcutBindings(for: kind).first?.hotkey ?? HotkeyPreference.loadMeeting()
        }
        return HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: distinguishModifierSides)
    }

    func shortcutBindings(for kind: OnboardingGuideShortcutKind) -> [HotkeyPreference.HotkeyBinding] {
        switch kind {
        case .transcription:
            return HotkeyPreference.loadTranscriptionBindings()
        case .translation:
            return HotkeyPreference.loadTranslationBindings()
        case .rewrite:
            return HotkeyPreference.loadRewriteBindings()
        case .meeting:
            return HotkeyPreference.loadMeetingBindings()
        }
    }

    func saveShortcutBindings(
        _ bindings: [HotkeyPreference.HotkeyBinding],
        for kind: OnboardingGuideShortcutKind
    ) {
        switch kind {
        case .transcription:
            HotkeyPreference.saveTranscriptionBindings(bindings)
        case .translation:
            HotkeyPreference.saveTranslationBindings(bindings)
        case .rewrite:
            HotkeyPreference.saveRewriteBindings(bindings)
        case .meeting:
            HotkeyPreference.saveMeetingBindings(bindings)
        }
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
        case (.meeting, .meeting):
            completedInteractionSteps.insert(.meeting)
        default:
            break
        }
    }

    func asrSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.asrSelection {
        case .dictation:
            return guideLocalized("Direct Dictation")
        case .mlx(let repo):
            return mlxModelManager.displayTitle(for: repo)
        case .sherpaOnnx(let modelID):
            return SherpaOnnxModelCatalog.displayTitle(for: modelID)
        case .remote(let provider):
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: remoteASRConfigurations)
            if configuration.hasUsableModel {
                return "\(provider.title) · \(configuration.model)"
            }
            return "\(provider.title) · \(guideLocalized("Needs Setup"))"
        case .none:
            return guideLocalized("Not selected")
        }
    }

    func llmSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.textSelection {
        case .appleIntelligence:
            return guideLocalized("Apple Intelligence")
        case .localLLM(let repo):
            return customLLMManager.displayTitle(for: repo)
        case .remoteLLM(let provider):
            guard RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                provider: provider,
                stored: remoteLLMConfigurations
            ) else {
                return "\(provider.title) · \(guideLocalized("Needs Setup"))"
            }
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: provider, stored: remoteLLMConfigurations)
            return "\(provider.title) · \(configuration.model)"
        case .none:
            return guideLocalized("Not selected")
        }
    }

    func translationSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.translationSelection {
        case .localGGUF(let modelID):
            return GGUFTranslationModelCatalog.option(for: modelID).title
        case .localLLM, .remoteLLM:
            return llmSelectionSummary(selectionID)
        case .none:
            return guideLocalized("Not selected")
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
        refreshInputDevices()
        startMicrophoneMeter(preferredDeviceID: microphoneState.activeDevice?.id, resetStartupRetry: true)
    }

    func startMicrophoneMeter(preferredDeviceID: AudioDeviceID?, resetStartupRetry: Bool) {
        guard OnboardingPermissionGrantResolver.isGranted(.microphone) else { return }

        stopMicrophoneMeter(resetStartupRetry: resetStartupRetry)
        if resetStartupRetry {
            microphoneStartupRetryCount = 0
        }
        waveformState.reset()
        waveformState.setActive(true)
        microphoneSignalFrameCount = 0
        microphoneReceivedInitialBuffer = false

        let capture = MeetingMicrophoneCapture()
        capture.setPreferredInputDevice(preferredDeviceID)
        microphoneCapture = capture

        do {
            try capture.start { _, level in
                Task { @MainActor in
                    guard currentStep == .microphone, microphoneCapture === capture else { return }
                    microphoneReceivedInitialBuffer = true
                    microphoneStartupWatchdogTask?.cancel()
                    microphoneStartupWatchdogTask = nil
                    let displayLevel = guideMicrophoneDisplayLevel(level)
                    waveformState.ingest(level: displayLevel)
                    if level >= Self.microphoneRawSignalThreshold || displayLevel >= Self.microphoneDisplaySignalThreshold {
                        microphoneSignalFrameCount += 1
                    } else {
                        microphoneSignalFrameCount = 0
                    }
                    if microphoneSignalFrameCount >= Self.microphoneRequiredSignalFrames {
                        completedInteractionSteps.insert(.microphone)
                    }
                }
            }
            scheduleMicrophoneStartupWatchdog(preferredDeviceID: preferredDeviceID)
        } catch {
            VoxtLog.settingsWarning("Guide microphone meter failed: \(error.localizedDescription)")
            stopMicrophoneMeter()
        }
    }

    func stopMicrophoneMeter(resetStartupRetry: Bool = true) {
        microphoneStartupWatchdogTask?.cancel()
        microphoneStartupWatchdogTask = nil
        microphoneCapture?.stop()
        microphoneCapture = nil
        microphoneSignalFrameCount = 0
        microphoneReceivedInitialBuffer = false
        if resetStartupRetry {
            microphoneStartupRetryCount = 0
        }
        waveformState.setActive(false)
    }

    func scheduleMicrophoneStartupWatchdog(preferredDeviceID: AudioDeviceID?) {
        microphoneStartupWatchdogTask?.cancel()
        microphoneStartupWatchdogTask = Task { @MainActor in
            do {
                try await Task.sleep(for: Self.microphoneStartupWatchdogDelay)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  currentStep == .microphone,
                  !microphoneReceivedInitialBuffer,
                  microphoneStartupRetryCount < 1
            else {
                return
            }

            microphoneStartupRetryCount += 1
            VoxtLog.settingsWarning("Guide microphone meter restarting after missing initial callback.")
            startMicrophoneMeter(preferredDeviceID: nil, resetStartupRetry: false)
        }
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
            || Self.isBundledGuidePrompt(
                temporaryEnhancementPrompt,
                resource: .onboardingTranscriptionEnhancement
            ) {
            temporaryEnhancementPrompt = Self.defaultTranscriptionEnhancementPrompt
        }
        if temporaryAppEnhancementPrompt.isEmpty
            || Self.isBundledGuidePrompt(
                temporaryAppEnhancementPrompt,
                resource: .onboardingAppEnhancement
            ) {
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

    func saveRemoteASRConfiguration(
        _ configuration: RemoteProviderConfiguration
    ) -> Result<Void, RemoteModelConfigurationStore.SaveError> {
        let result = RemoteModelConfigurationStore.saveConfiguration(
            configuration,
            updating: remoteASRProviderConfigurationsRaw
        )
        switch result {
        case .success(let raw):
            remoteASRProviderConfigurationsRaw = raw
            NotificationCenter.default.post(name: .voxtRemoteProviderConfigurationsDidChange, object: nil)
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func saveRemoteLLMConfiguration(
        _ configuration: RemoteProviderConfiguration
    ) -> Result<Void, RemoteModelConfigurationStore.SaveError> {
        let result = RemoteModelConfigurationStore.saveConfiguration(
            configuration,
            updating: remoteLLMProviderConfigurationsRaw
        )
        switch result {
        case .success(let raw):
            remoteLLMProviderConfigurationsRaw = raw
            NotificationCenter.default.post(name: .voxtRemoteProviderConfigurationsDidChange, object: nil)
            NotificationCenter.default.post(name: .voxtRemoteLLMProviderConfigurationsDidChange, object: nil)
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func asrCredentialHint(for provider: RemoteASRProvider) -> String? {
        switch provider {
        case .doubaoASR:
            return guideLocalized("Doubao uses App ID + Access Token for streaming API.")
        case .aliyunBailianASR:
            return guideLocalized("Aliyun ASR in Voxt uses realtime WebSocket only: Qwen models use /api-ws/v1/realtime, Fun/Paraformer models use /api-ws/v1/inference.")
        case .xiaomiMiMoASR:
            return guideLocalized("Xiaomi MiMo ASR uses a MiMo API Key and the OpenAI-compatible chat completions audio endpoint.")
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
        switch customLLMManager.state(for: repo) {
        case .downloading, .paused:
            return ModelDownloadStatusSnapshot.fromCustomLLMState(
                customLLMManager.state(for: repo),
                pauseMessage: customLLMManager.pausedStatusMessage(for: repo)
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
        guard case .error(let message) = customLLMManager.state(for: repo)
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

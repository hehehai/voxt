import SwiftUI
import AppKit
import ApplicationServices
import CoreAudio
import AVFoundation
import Speech
import Carbon

struct VoiceEndCommandState {
    var lastDetectedCommand = false
    var didAutoStop = false
    var pendingStrippedText: String?
    let silenceDuration: TimeInterval = 1.0
}

struct MainWindowPresentationState {
    var shouldRestoreAfterUpdate = false
}

@main
struct VoxtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(AppLocalization.localizedString("General")) {
                    Task { @MainActor in
                        appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general))
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            MainWindowNavigationCommands(appDelegate: appDelegate)
            HelpNavigationCommands(appDelegate: appDelegate)
        }
    }
}

struct MainWindowNavigationCommands: Commands {
    @AppStorage(AppPreferenceKey.appEnhancementEnabled) private var appEnhancementEnabled = false
    let appDelegate: AppDelegate

    var body: some Commands {
        CommandMenu("Navigate") {
            Button(AppLocalization.localizedString("Dashboard")) {
                appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .report))
            }

            Menu(AppLocalization.localizedString("General")) {
                Button(AppLocalization.localizedString("General")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general))
                }
                Divider()
                Button(AppLocalization.localizedString("Configuration")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general, section: .generalConfiguration))
                }
                Button(AppLocalization.localizedString("Audio")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general, section: .generalAudio))
                }
                Button(AppLocalization.localizedString("Transcription UI")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general, section: .generalTranscriptionUI))
                }
                Button(AppLocalization.localizedString("Languages")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general, section: .generalLanguages))
                }
                Button(AppLocalization.localizedString("Model Storage")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general, section: .generalModelStorage))
                }
                Button(AppLocalization.localizedString("Output")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general, section: .generalOutput))
                }
                Button(AppLocalization.localizedString("Logging")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general, section: .generalLogging))
                }
                Button(AppLocalization.localizedString("App Behavior")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .general, section: .generalAppBehavior))
                }
            }

            Menu(AppLocalization.localizedString("Model")) {
                Button(AppLocalization.localizedString("Model")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .model))
                }
                Divider()
                Button(AppLocalization.localizedString("Engine")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .model, section: .modelEngine))
                }
                Button(AppLocalization.localizedString("Text Enhancement")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .model, section: .modelTextEnhancement))
                }
                Button(AppLocalization.localizedString("Translation")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .model, section: .modelTranslation))
                }
                Button(AppLocalization.localizedString("Content Rewrite")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .model, section: .modelContentRewrite))
                }
                Button(AppLocalization.localizedString("Transcription Test")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .model, section: .modelTranscriptionTest))
                }
            }

            Menu(AppLocalization.localizedString("Dictionary")) {
                Button(AppLocalization.localizedString("Dictionary")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .dictionary))
                }
                Divider()
                Button(AppLocalization.localizedString("Settings")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .dictionary, section: .dictionarySettings))
                }
                Button(AppLocalization.localizedString("Dictionary Entries")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .dictionary, section: .dictionaryEntries))
                }
            }

            if appEnhancementEnabled {
                Menu(AppLocalization.localizedString("App Branch")) {
                    Button(AppLocalization.localizedString("App Branch")) {
                        appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .appEnhancement))
                    }
                    Divider()
                    Button(AppLocalization.localizedString("Sources")) {
                        appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .appEnhancement, section: .appBranchSources))
                    }
                    Button(AppLocalization.localizedString("Groups")) {
                        appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .appEnhancement, section: .appBranchGroups))
                    }
                }
            }

            Menu(AppLocalization.localizedString("History")) {
                Button(AppLocalization.localizedString("History")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .history))
                }
                Divider()
                Button(AppLocalization.localizedString("History Settings")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .history, section: .historySettings))
                }
                Button(AppLocalization.localizedString("History Entries")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .history, section: .historyEntries))
                }
            }

            Menu(AppLocalization.localizedString("Permissions")) {
                Button(AppLocalization.localizedString("Permissions")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .permissions))
                }
                Divider()
                Button(AppLocalization.localizedString("Permissions")) {
                    appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .permissions, section: .permissionsMain))
                }
                if appEnhancementEnabled {
                    Button(AppLocalization.localizedString("App Branch URL Authorization")) {
                        appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .permissions, section: .permissionsAppBranchURLAuthorization))
                    }
                }
            }

            Button(AppLocalization.localizedString("Hotkey")) {
                appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .hotkey))
            }

        }
    }
}

struct HelpNavigationCommands: Commands {
    let appDelegate: AppDelegate
    private let projectURL = URL(string: "https://github.com/hehehai/voxt")!
    private let feedbackURL = URL(string: "https://github.com/hehehai/voxt/issues/new/choose")!
    private let authorURL = URL(string: "https://www.hehehai.cn/")!

    var body: some Commands {
        CommandGroup(after: .help) {
            Divider()
            Button(AppLocalization.localizedString("Voxt")) {
                appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .about, section: .aboutVoxt))
            }
            Button(AppLocalization.localizedString("GitHub")) {
                NSWorkspace.shared.open(projectURL)
            }
            Button(AppLocalization.localizedString("Author")) {
                NSWorkspace.shared.open(authorURL)
            }
            Button(AppLocalization.localizedString("Feedback")) {
                NSWorkspace.shared.open(feedbackURL)
            }
            Button(AppLocalization.localizedString("Logs")) {
                appDelegate.openMainWindow(target: SettingsNavigationTarget(tab: .about, section: .aboutLogs))
            }
        }
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    struct StoredBranchURLItem: Codable {
        let id: UUID
        let pattern: String
    }

    struct StoredAppBranchGroup: Codable {
        let id: UUID
        let name: String
        let prompt: String
        let appBundleIDs: [String]
        let urlPatternIDs: [UUID]
        let isExpanded: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case prompt
            case appBundleIDs
            case urlPatternIDs
            case isExpanded
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            prompt = try container.decode(String.self, forKey: .prompt)
            appBundleIDs = try container.decodeIfPresent([String].self, forKey: .appBundleIDs) ?? []
            urlPatternIDs = try container.decodeIfPresent([UUID].self, forKey: .urlPatternIDs) ?? []
            isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        }
    }

    struct StoredCustomBrowser: Codable {
        let bundleID: String
        let displayName: String
    }

    struct BrowserScriptProvider {
        let name: String
        let scripts: [String]
    }

    struct EnhancementContextSnapshot {
        let bundleID: String?
        let capturedAt: Date
    }

    struct EnhancementPromptContext {
        let focusedAppName: String?
        let matchedGroupID: UUID?
        let matchedAppGroupName: String?
        let matchedURLGroupName: String?
    }

    enum SessionOutputMode {
        case transcription
        case translation
        case rewrite
    }

    enum MeetingSessionCompletionDisposition {
        case discard
        case save
        case saveAndOpenDetail
    }

    let speechTranscriber = SpeechTranscriber()
    var mlxTranscriber: MLXTranscriber?
    var whisperTranscriber: WhisperKitTranscriber?
    let remoteASRTranscriber = RemoteASRTranscriber()
    let mlxModelManager: MLXModelManager
    let whisperModelManager: WhisperKitModelManager
    let customLLMManager: CustomLLMModelManager
    let historyStore = TranscriptionHistoryStore()
    let dictionaryStore = DictionaryStore()
    let dictionarySuggestionStore = DictionarySuggestionStore()
    let appUpdateManager = AppUpdateManager()
    let interactionSoundPlayer = InteractionSoundPlayer()
    let systemAudioMuteController = SystemAudioMuteController()

    let hotkeyManager = HotkeyManager()
    let overlayWindow = RecordingOverlayWindow()
    let meetingOverlayWindow = MeetingOverlayWindow()
    let meetingDetailWindowManager = MeetingDetailWindowManager.shared
    let overlayState = OverlayState()
    lazy var meetingSessionCoordinator = MeetingSessionCoordinator(
        whisperModelManager: whisperModelManager,
        mlxModelManager: mlxModelManager,
        preferredInputDeviceIDProvider: { [weak self] in
            self?.selectedInputDeviceID
        },
        realtimeTranslationTargetLanguageProvider: { [weak self] in
            self?.meetingRealtimeTranslationTargetLanguage
        },
        realtimeTranslationHandler: { [weak self] text, targetLanguage in
            guard let self else { return text }
            return try await self.translateMeetingRealtimeText(text, targetLanguage: targetLanguage)
        }
    )
    var statusItem: NSStatusItem?

    var enhancer: (any TextEnhancing)?
    var mainWindowController: NSWindowController?
    private var interfaceLanguageObserver: NSObjectProtocol?
    private var updateAvailabilityObserver: NSObjectProtocol?
    private var selectedInputDeviceObserver: NSObjectProtocol?
    private var workspaceWillSleepObserver: NSObjectProtocol?
    private var workspaceDidWakeObserver: NSObjectProtocol?
    private var workspaceSessionDidBecomeActiveObserver: NSObjectProtocol?
    private var workspaceSessionDidResignActiveObserver: NSObjectProtocol?
    var audioInputDevicesObserver: AudioInputDeviceObserver?
    private var globalEscapeKeyMonitor: Any?
    private var localEscapeKeyMonitor: Any?
    var inputDevicesRefreshTask: Task<Void, Never>?
    var inputDevicesSnapshot: [AudioInputDevice] = []
    var microphoneResolvedState = MicrophoneResolvedState.empty

    var isSessionActive = false
    var pendingSessionFinishTask: Task<Void, Never>?
    var stopRecordingFallbackTask: Task<Void, Never>?
    var silenceMonitorTask: Task<Void, Never>?
    var pauseLLMTask: Task<Void, Never>?
    var pendingWhisperStartupTask: Task<Void, Never>?
    var pendingMeetingStartupTask: Task<Void, Never>?
    var whisperWarmupTask: Task<Void, Never>?
    var overlayReminderTask: Task<Void, Never>?
    var overlayStatusClearTask: Task<Void, Never>?
    var pendingSystemAudioMuteTask: Task<Void, Never>?
    var lastSignificantAudioAt = Date()
    var didTriggerPauseTranscription = false
    var didTriggerPauseLLM = false
    var voiceEndCommandState = VoiceEndCommandState()
    let silenceAudioLevelThreshold: Float = 0.06
    let sessionFinishDelay: TimeInterval = 1.2
    var recordingStartedAt: Date?
    var recordingStoppedAt: Date?
    var transcriptionProcessingStartedAt: Date?
    var transcriptionResultReceivedAt: Date?
    var sessionOutputMode: SessionOutputMode = .transcription
    var isSelectedTextTranslationFlow = false
    var didCommitSessionOutput = false
    var activeRecordingSessionID = UUID()
    var isSessionCancellationRequested = false
    var sessionTargetApplicationPID: pid_t?
    var sessionTargetApplicationBundleID: String?
    var pendingTranscriptionStartTask: Task<Void, Never>?
    var enhancementContextSnapshot: EnhancementContextSnapshot?
    var lastEnhancementPromptContext: EnhancementPromptContext?
    var rewriteSessionHasSelectedSourceText = false
    var rewriteSessionHadWritableFocusedInput = false
    var rewriteSessionFallbackInjectBundleID: String?
    var sessionUsesWhisperDirectTranslation = false
    var pendingMeetingSessionCompletionDisposition: MeetingSessionCompletionDisposition = .save
    let tapStopGuardInterval: TimeInterval = 0.35
    let transcriptionStartDebounceInterval: TimeInterval = 0.08
    var mainWindowPresentationState = MainWindowPresentationState()

    override init() {
        let repo = UserDefaults.standard.string(forKey: AppPreferenceKey.mlxModelRepo)
            ?? MLXModelManager.defaultModelRepo
        let useMirror = UserDefaults.standard.bool(forKey: AppPreferenceKey.useHfMirror)
        let hubURL = useMirror ? MLXModelManager.mirrorHubBaseURL : MLXModelManager.defaultHubBaseURL
        mlxModelManager = MLXModelManager(modelRepo: repo, hubBaseURL: hubURL)
        let whisperModelID = UserDefaults.standard.string(forKey: AppPreferenceKey.whisperModelID)
            ?? WhisperKitModelManager.defaultModelID
        whisperModelManager = WhisperKitModelManager(modelID: whisperModelID, hubBaseURL: hubURL)
        let llmRepo = UserDefaults.standard.string(forKey: AppPreferenceKey.customLLMModelRepo)
            ?? CustomLLMModelManager.defaultModelRepo
        customLLMManager = CustomLLMModelManager(modelRepo: llmRepo, hubBaseURL: hubURL)
        UserDefaults.standard.register(defaults: [
            AppPreferenceKey.interactionSoundsEnabled: true,
            AppPreferenceKey.interactionSoundPreset: InteractionSoundPreset.soft.rawValue,
            AppPreferenceKey.muteSystemAudioWhileRecording: false,
            AppPreferenceKey.overlayPosition: OverlayPosition.bottom.rawValue,
            AppPreferenceKey.overlayCardOpacity: 82,
            AppPreferenceKey.overlayCardCornerRadius: 24,
            AppPreferenceKey.overlayScreenEdgeInset: 30,
            AppPreferenceKey.interfaceLanguage: AppInterfaceLanguage.system.rawValue,
            AppPreferenceKey.translationTargetLanguage: TranslationTargetLanguage.english.rawValue,
            AppPreferenceKey.userMainLanguageCodes: UserMainLanguageOption.defaultStoredSelectionValue,
            AppPreferenceKey.translationModelProvider: TranslationModelProvider.customLLM.rawValue,
            AppPreferenceKey.rewriteModelProvider: RewriteModelProvider.customLLM.rawValue,
            AppPreferenceKey.escapeKeyCancelsOverlaySession: true,
            AppPreferenceKey.translateSelectedTextOnTranslationHotkey: true,
            AppPreferenceKey.meetingNotesBetaEnabled: false,
            AppPreferenceKey.hideMeetingOverlayFromScreenSharing: false,
            AppPreferenceKey.meetingOverlayCollapsed: false,
            AppPreferenceKey.meetingRealtimeTranslateEnabled: false,
            AppPreferenceKey.meetingRealtimeTranslationTargetLanguage: "",
            AppPreferenceKey.meetingEnableSpeakerDiarization: false,
            AppPreferenceKey.meetingDiarizationVariant: "dihard3",
            AppPreferenceKey.meetingEchoMitigationEnabled: true,
            AppPreferenceKey.meetingSummaryAutoGenerate: true,
            AppPreferenceKey.meetingSummaryLength: "",
            AppPreferenceKey.meetingSummaryStyle: "",
            AppPreferenceKey.meetingSummaryPromptTemplate: AppPreferenceKey.defaultMeetingSummaryPrompt,
            AppPreferenceKey.meetingSummaryModelSelection: "",
            AppPreferenceKey.voiceEndCommandEnabled: false,
            AppPreferenceKey.voiceEndCommandPreset: VoiceEndCommandPreset.over.rawValue,
            AppPreferenceKey.voiceEndCommandText: "",
            AppPreferenceKey.autoCopyWhenNoFocusedInput: false,
            AppPreferenceKey.alwaysShowRewriteAnswerCard: false,
            AppPreferenceKey.appEnhancementEnabled: false,
            AppPreferenceKey.translationSystemPrompt: AppPreferenceKey.defaultTranslationPrompt,
            AppPreferenceKey.rewriteSystemPrompt: AppPreferenceKey.defaultRewritePrompt,
            AppPreferenceKey.asrHintSettings: ASRHintSettingsStore.defaultStoredValue(),
            AppPreferenceKey.whisperModelID: WhisperKitModelManager.defaultModelID,
            AppPreferenceKey.whisperTemperature: 0.0,
            AppPreferenceKey.whisperVADEnabled: true,
            AppPreferenceKey.whisperTimestampsEnabled: false,
            AppPreferenceKey.whisperRealtimeEnabled: true,
            AppPreferenceKey.whisperKeepResidentLoaded: true,
            AppPreferenceKey.translationFallbackModelProvider: TranslationModelProvider.customLLM.rawValue,
            AppPreferenceKey.rewriteCustomLLMModelRepo: CustomLLMModelManager.defaultModelRepo,
            AppPreferenceKey.remoteASRSelectedProvider: RemoteASRProvider.openAIWhisper.rawValue,
            AppPreferenceKey.remoteASRProviderConfigurations: "",
            AppPreferenceKey.remoteLLMSelectedProvider: RemoteLLMProvider.openAI.rawValue,
            AppPreferenceKey.remoteLLMProviderConfigurations: "",
            AppPreferenceKey.translationRemoteLLMProvider: "",
            AppPreferenceKey.rewriteRemoteLLMProvider: "",
            AppPreferenceKey.launchAtLogin: false,
            AppPreferenceKey.showInDock: false,
            AppPreferenceKey.historyEnabled: false,
            AppPreferenceKey.historyRetentionPeriod: HistoryRetentionPeriod.thirtyDays.rawValue,
            AppPreferenceKey.dictionaryRecognitionEnabled: true,
            AppPreferenceKey.dictionaryAutoLearningEnabled: true,
            AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled: true,
            AppPreferenceKey.autoCheckForUpdates: true,
            AppPreferenceKey.hotkeyDebugLoggingEnabled: false,
            AppPreferenceKey.llmDebugLoggingEnabled: false,
            AppPreferenceKey.networkProxyMode: VoxtNetworkSession.ProxyMode.system.rawValue,
            AppPreferenceKey.customProxyScheme: VoxtNetworkSession.ProxyScheme.http.rawValue,
            AppPreferenceKey.customProxyHost: "",
            AppPreferenceKey.customProxyPort: "",
            AppPreferenceKey.customProxyUsername: "",
            AppPreferenceKey.customProxyPassword: "",
        ])
        HotkeyPreference.registerDefaults()
        HotkeyPreference.migrateDefaultsIfNeeded()
        Self.migrateLegacyNetworkProxyPreferenceIfNeeded()
        super.init()
        AppDelegate.shared = self
    }

    var transcriptionEngine: TranscriptionEngine {
        get {
            let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.transcriptionEngine)
            return TranscriptionEngine(rawValue: raw ?? "") ?? .mlxAudio
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
        }
    }

    var enhancementMode: EnhancementMode {
        get {
            EnhancementMode.resolved(
                storedRawValue: UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementMode),
                appleIntelligenceAvailable: appleIntelligenceAvailableForCurrentEnvironment,
                customLLMAvailable: customEnhancementModelAvailable,
                remoteLLMAvailable: remoteEnhancementModelAvailable
            )
        }
        set {
            let previous = enhancementMode
            UserDefaults.standard.set(newValue.rawValue, forKey: AppPreferenceKey.enhancementMode)
            if previous != newValue {
                VoxtLog.info("Enhancement mode changed: \(previous.rawValue) -> \(newValue.rawValue)")
                if newValue == .off {
                    VoxtLog.info("Custom LLM downloaded models are preserved when enhancement is off.")
                }
            }
        }
    }

    var appEnhancementEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.appEnhancementEnabled)
    }

    private var appleIntelligenceAvailableForCurrentEnvironment: Bool {
        if #available(macOS 26.0, *) {
            return TextEnhancer.isAvailable
        }
        return false
    }

    private var customEnhancementModelAvailable: Bool {
        customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo)
    }

    private var remoteEnhancementModelAvailable: Bool {
        let configuration = resolvedRemoteLLMContext(forTranslation: false).configuration
        return configuration.isConfigured && configuration.hasUsableModel
    }

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var currentSystemVersionLogDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let buildString = ProcessInfo.processInfo.operatingSystemVersionString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(versionString) (\(buildString))"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        VoxtLog.info("Voxt launching.")
        VoxtLog.info("Runtime system version: \(currentSystemVersionLogDescription)")
        migrateLegacyPreferences()

        if isRunningUnitTests {
            VoxtLog.info("Voxt launch running under XCTest; skipping app startup services.")
            return
        }

        AppBehaviorController.applyDockVisibility(showInDock: showInDock)

        if #available(macOS 26.0, *), TextEnhancer.isAvailable {
            enhancer = TextEnhancer()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            if let icon = NSImage(named: "voxt") {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Voxt")
            }
            button.image?.accessibilityDescription = "Voxt"
        }
        appUpdateManager.syncAutomaticallyChecksForUpdates(autoCheckForUpdates)
        startObservingAudioInputDevices()
        refreshInputDevicesSnapshot(reason: "launch")
        buildMenu()
        appUpdateManager.onUpdatePresentationWillBegin = { [weak self] in
            self?.prepareMainWindowForUpdatePresentation()
        }
        appUpdateManager.onUpdatePresentationDidEnd = { [weak self] in
            self?.restoreMainWindowAfterUpdateSessionIfNeeded()
        }
        selectedInputDeviceObserver = NotificationCenter.default.addObserver(
            forName: .voxtSelectedInputDeviceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previousState = self.microphoneResolvedState
                self.microphoneResolvedState = MicrophonePreferenceManager.syncState(
                    defaults: .standard,
                    availableDevices: self.inputDevicesSnapshot
                )
                self.handleResolvedMicrophoneStateChange(
                    from: previousState,
                    to: self.microphoneResolvedState,
                    reason: "microphone preferences updated"
                )
                self.buildMenu()
            }
        }
        interfaceLanguageObserver = NotificationCenter.default.addObserver(
            forName: .voxtInterfaceLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.buildMenu()
            }
        }
        updateAvailabilityObserver = NotificationCenter.default.addObserver(
            forName: .voxtUpdateAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.buildMenu()
            }
        }

        setupHotkey()
        setupLifecycleRecoveryObservers()
        setupEscapeKeyMonitoring()
        overlayWindow.onRequestClose = { [weak self] in
            Task { @MainActor [weak self] in
                self?.dismissAnswerOverlay()
            }
        }
        overlayWindow.onRequestInject = { [weak self] in
            Task { @MainActor [weak self] in
                self?.injectAnswerOverlayContent()
            }
        }
        meetingOverlayWindow.onRequestClose = { [weak self] in
            Task { @MainActor [weak self] in
                self?.requestMeetingSessionCloseConfirmation()
            }
        }
        meetingOverlayWindow.onRequestCollapseToggle = { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleMeetingOverlayCollapse()
            }
        }
        meetingOverlayWindow.onRequestPauseToggle = { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleMeetingPause()
            }
        }
        meetingOverlayWindow.onRequestDetail = { [weak self] in
            Task { @MainActor [weak self] in
                self?.showLiveMeetingDetailWindow()
            }
        }
        meetingOverlayWindow.onRequestRealtimeTranslateToggle = { [weak self] isEnabled in
            Task { @MainActor [weak self] in
                self?.handleMeetingRealtimeTranslationToggle(isEnabled)
            }
        }
        meetingOverlayWindow.onRequestRealtimeTranslationLanguageConfirm = { [weak self] in
            Task { @MainActor [weak self] in
                self?.confirmMeetingRealtimeTranslationLanguageSelection()
            }
        }
        meetingOverlayWindow.onRequestRealtimeTranslationLanguageCancel = { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelMeetingRealtimeTranslationLanguageSelection()
            }
        }
        meetingOverlayWindow.onRequestCancelMeeting = { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelMeetingSessionWithoutSaving()
            }
        }
        meetingOverlayWindow.onRequestFinishMeeting = { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishMeetingSessionAndOpenDetail()
            }
        }
        meetingOverlayWindow.onRequestDismissCloseConfirmation = { [weak self] in
            Task { @MainActor [weak self] in
                self?.dismissMeetingSessionCloseConfirmation()
            }
        }
        meetingOverlayWindow.onRequestCopySegment = { [weak self] segment in
            Task { @MainActor [weak self] in
                self?.copyMeetingSegment(segment)
            }
        }

        presentMainWindowOnLaunchIfNeeded()
        scheduleWhisperIdleWarmupIfNeeded()
        VoxtLog.info("Voxt launch completed. engine=\(transcriptionEngine.rawValue), enhancement=\(enhancementMode.rawValue)")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        openMainWindow(selectTab: nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if meetingSessionCoordinator.isActive {
            meetingSessionCoordinator.stop()
        }
        pendingMeetingStartupTask?.cancel()
        meetingDetailWindowManager.closeLiveWindow()
        systemAudioMuteController.restoreSystemAudioIfNeeded()
    }

    deinit {
        if let interfaceLanguageObserver {
            NotificationCenter.default.removeObserver(interfaceLanguageObserver)
        }
        if let updateAvailabilityObserver {
            NotificationCenter.default.removeObserver(updateAvailabilityObserver)
        }
        if let selectedInputDeviceObserver {
            NotificationCenter.default.removeObserver(selectedInputDeviceObserver)
        }
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        if let workspaceWillSleepObserver {
            workspaceNotificationCenter.removeObserver(workspaceWillSleepObserver)
        }
        if let workspaceDidWakeObserver {
            workspaceNotificationCenter.removeObserver(workspaceDidWakeObserver)
        }
        if let workspaceSessionDidBecomeActiveObserver {
            workspaceNotificationCenter.removeObserver(workspaceSessionDidBecomeActiveObserver)
        }
        if let workspaceSessionDidResignActiveObserver {
            workspaceNotificationCenter.removeObserver(workspaceSessionDidResignActiveObserver)
        }
        if let globalEscapeKeyMonitor {
            NSEvent.removeMonitor(globalEscapeKeyMonitor)
        }
        if let localEscapeKeyMonitor {
            NSEvent.removeMonitor(localEscapeKeyMonitor)
        }
        inputDevicesRefreshTask?.cancel()
        pendingMeetingStartupTask?.cancel()
        whisperWarmupTask?.cancel()
    }

    func scheduleWhisperIdleWarmupIfNeeded() {
        whisperWarmupTask?.cancel()
        guard transcriptionEngine == .whisperKit else { return }
        guard UserDefaults.standard.object(forKey: AppPreferenceKey.whisperKeepResidentLoaded) as? Bool ?? true else { return }
        guard isWhisperReady else { return }

        whisperWarmupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.transcriptionEngine == .whisperKit else { return }
            guard UserDefaults.standard.object(forKey: AppPreferenceKey.whisperKeepResidentLoaded) as? Bool ?? true else { return }
            guard self.isWhisperReady else { return }

            self.whisperModelManager.beginActiveUse()
            defer {
                self.whisperModelManager.endActiveUse()
                self.whisperWarmupTask = nil
            }

            do {
                _ = try await self.whisperModelManager.loadWhisper()
                VoxtLog.info("Whisper idle warmup completed.", verbose: true)
            } catch {
                VoxtLog.warning("Whisper idle warmup failed: \(error.localizedDescription)")
            }
        }
    }

    private func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: AppPreferenceKey.enhancementMode) == nil,
           defaults.object(forKey: "aiEnhanceEnabled") != nil {
            let oldEnabled = defaults.bool(forKey: "aiEnhanceEnabled")
            enhancementMode = oldEnabled ? .appleIntelligence : .off
        }
    }

    private static func migrateLegacyNetworkProxyPreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: AppPreferenceKey.networkProxyMode) == nil,
              defaults.object(forKey: AppPreferenceKey.useSystemProxy) != nil else {
            return
        }

        let legacyUsesSystemProxy = defaults.bool(forKey: AppPreferenceKey.useSystemProxy)
        let mode: VoxtNetworkSession.ProxyMode = legacyUsesSystemProxy ? .system : .disabled
        defaults.set(mode.rawValue, forKey: AppPreferenceKey.networkProxyMode)
    }

    private func setupHotkey() {
        // Callback contract:
        // - HotkeyManager only emits normalized events (transcriptionDown/up, translationDown/up, rewriteDown/up).
        // - AppDelegate owns business decisions (start/stop session, selected-text fast path, mode rules).
        hotkeyManager.onKeyDown = { [weak self] in
            guard let self else { return }
            self.handleTranscriptionHotkeyDown()
        }
        hotkeyManager.onKeyUp = { [weak self] in
            guard let self else { return }
            self.handleTranscriptionHotkeyUp()
        }
        hotkeyManager.onTranslationKeyDown = { [weak self] in
            guard let self else { return }
            self.handleTranslationHotkeyDown()
        }
        hotkeyManager.onTranslationKeyUp = { [weak self] in
            guard let self else { return }
            self.handleTranslationHotkeyUp()
        }
        hotkeyManager.onRewriteKeyDown = { [weak self] in
            guard let self else { return }
            self.handleRewriteHotkeyDown()
        }
        hotkeyManager.onRewriteKeyUp = { [weak self] in
            guard let self else { return }
            self.handleRewriteHotkeyUp()
        }
        hotkeyManager.onMeetingKeyDown = { [weak self] in
            guard let self else { return }
            self.handleMeetingHotkeyDown()
        }
        hotkeyManager.start()
        VoxtLog.hotkey("Hotkey callbacks configured.")
    }

    private func setupLifecycleRecoveryObservers() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        workspaceWillSleepObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHotkeyTransientStateReset(reason: "workspaceWillSleep")
            }
        }

        workspaceDidWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHotkeyTransientStateReset(reason: "workspaceDidWake")
            }
        }

        workspaceSessionDidBecomeActiveObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHotkeyTransientStateReset(reason: "workspaceSessionDidBecomeActive")
            }
        }

        workspaceSessionDidResignActiveObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHotkeyTransientStateReset(reason: "workspaceSessionDidResignActive")
            }
        }
    }

    private func scheduleHotkeyTransientStateReset(reason: String) {
        Task { @MainActor [weak self] in
            self?.hotkeyManager.resetTransientState(reason: reason)
        }
    }

    private func setupEscapeKeyMonitoring() {
        globalEscapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.handleEscapeKeyEvent(event)
            }
        }
        localEscapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEscapeKeyEvent(event)
            return event
        }
    }

    private func handleEscapeKeyEvent(_ event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Escape) else { return }
        guard UserDefaults.standard.object(forKey: AppPreferenceKey.escapeKeyCancelsOverlaySession) as? Bool ?? true else {
            return
        }
        if overlayState.displayMode == .answer {
            dismissAnswerOverlay()
            return
        }
        if meetingSessionCoordinator.isActive {
            if meetingSessionCoordinator.overlayState.isCloseConfirmationPresented {
                dismissMeetingSessionCloseConfirmation()
            } else {
                requestMeetingSessionCloseConfirmation()
            }
            return
        }
        guard HotkeyPreference.loadTriggerMode() == .tap else { return }
        guard isSessionActive else { return }
        guard !isSelectedTextTranslationFlow else { return }
        cancelActiveRecordingSession()
    }

    private func shouldIgnoreTapStop() -> Bool {
        guard let startedAt = recordingStartedAt else { return false }
        let elapsed = Date().timeIntervalSince(startedAt)
        return elapsed < tapStopGuardInterval
    }

    private var isSessionStopInProgress: Bool {
        isSessionActive && recordingStoppedAt != nil
    }

    private func handleTranscriptionTapDown() {
        if meetingSessionCoordinator.isActive {
            if meetingSessionCoordinator.overlayState.isCloseConfirmationPresented {
                dismissMeetingSessionCloseConfirmation()
            } else {
                requestMeetingSessionCloseConfirmation()
            }
            return
        }
        if isSessionActive {
            // In tap mode, fn is the unified "toggle stop" key.
            // This intentionally allows ending active translation sessions with fn.
            guard !shouldIgnoreTapStop() else { return }
            endRecording()
            return
        }
        beginRecording(outputMode: .transcription)
    }

    private func handleTranslationTapDown() {
        if isSessionActive {
            guard sessionOutputMode == .translation else {
                VoxtLog.info("Tap translation down ignored: active session belongs to transcription.", verbose: true)
                return
            }
            guard !shouldIgnoreTapStop() else { return }
            endRecording()
            return
        }
        beginRecording(outputMode: .translation)
    }

    private func handleTranscriptionHotkeyDown() {
        if meetingSessionCoordinator.isActive {
            if meetingSessionCoordinator.overlayState.isCloseConfirmationPresented {
                dismissMeetingSessionCloseConfirmation()
            } else {
                requestMeetingSessionCloseConfirmation()
            }
            return
        }
        let triggerMode = HotkeyPreference.loadTriggerMode()
        VoxtLog.hotkey(
            "Hotkey callback transcriptionDown. mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )
        let actions = HotkeyActionResolver.resolveTranscriptionDown(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop() && !isSessionStopInProgress
            )
        )
        for action in actions {
            performHotkeyAction(action)
        }
    }

    private func handleTranscriptionHotkeyUp() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        guard triggerMode == .longPress else { return }
        VoxtLog.hotkey(
            "Hotkey callback transcriptionUp. isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )
        let actions = HotkeyActionResolver.resolveTranscriptionUp(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop() && !isSessionStopInProgress
            )
        )
        for action in actions {
            performHotkeyAction(action)
        }
    }

    private func handleTranslationHotkeyDown() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        VoxtLog.hotkey(
            "Hotkey callback translationDown. mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )
        let actions = HotkeyActionResolver.resolveTranslationDown(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop() && !isSessionStopInProgress
            )
        )
        for action in actions where action == .cancelPendingTranscriptionStart {
            performHotkeyAction(action)
        }
        guard !meetingSessionCoordinator.isActive else {
            showOverlayStatus(
                String(localized: "Meeting Notes is currently active. Close it before starting another recording."),
                clearAfter: 2.2
            )
            return
        }
        guard !isSessionActive else {
            VoxtLog.hotkey("Translation down ignored: session already active.")
            return
        }

        // Highest priority branch:
        // if user has selected text, fn+shift should run selected-text translation directly,
        // without opening microphone recording flow.
        if beginSelectedTextTranslationIfPossible() {
            VoxtLog.hotkey("Translation down handled by selected-text translation flow.")
            return
        }

        for action in actions {
            guard action != .cancelPendingTranscriptionStart else { continue }
            performHotkeyAction(action)
        }
    }

    private func handleTranslationHotkeyUp() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        guard triggerMode == .longPress else { return }
        VoxtLog.hotkey(
            "Hotkey callback translationUp. isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), selectedTextFlow=\(isSelectedTextTranslationFlow)",
        )
        let actions = HotkeyActionResolver.resolveTranslationUp(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop() && !isSessionStopInProgress
            )
        )
        for action in actions {
            performHotkeyAction(action)
        }
    }

    private func handleRewriteHotkeyDown() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        VoxtLog.hotkey(
            "Hotkey callback rewriteDown. mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputModeLabel), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )

        cancelPendingTranscriptionStart()
        if isSessionActive {
            if sessionOutputMode == .transcription && shouldIgnoreTapStop() {
                VoxtLog.hotkey("Rewrite down reinterpreting freshly started transcription session as rewrite.")
                cancelActiveRecordingSession()
                beginRecording(outputMode: .rewrite)
                return
            }

            VoxtLog.hotkey("Rewrite down ignored: session already active.")
            return
        }

        beginRecording(outputMode: .rewrite)
    }

    private func handleRewriteHotkeyUp() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        guard triggerMode == .longPress else { return }
        VoxtLog.hotkey(
            "Hotkey callback rewriteUp. isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputModeLabel)",
        )
        guard isSessionActive, sessionOutputMode == .rewrite else { return }
        endRecording()
    }

    private func performHotkeyAction(_ action: HotkeyActionResolver.Action) {
        switch action {
        case .ignore:
            return
        case .stopRecording:
            endRecording()
        case .startTranscription:
            beginRecording(outputMode: .transcription)
        case .startTranslation:
            beginRecording(outputMode: .translation)
        case .scheduleTranscriptionStart:
            schedulePendingTranscriptionStart()
        case .cancelPendingTranscriptionStart:
            cancelPendingTranscriptionStart()
        }
    }

    private func schedulePendingTranscriptionStart() {
        VoxtLog.hotkey("Scheduling pending transcription start. delaySec=\(transcriptionStartDebounceInterval)")
        pendingTranscriptionStartTask?.cancel()
        pendingTranscriptionStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(self.transcriptionStartDebounceInterval))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard !self.isSessionActive else {
                VoxtLog.hotkey("Pending transcription start dropped: session already active.")
                self.pendingTranscriptionStartTask = nil
                return
            }
            self.pendingTranscriptionStartTask = nil
            VoxtLog.hotkey("Pending transcription start fired.")
            self.beginRecording(outputMode: .transcription)
        }
    }

    func cancelPendingTranscriptionStart() {
        if pendingTranscriptionStartTask != nil {
            VoxtLog.hotkey("Canceled pending transcription start.")
        }
        pendingTranscriptionStartTask?.cancel()
        pendingTranscriptionStartTask = nil
    }

    func shouldHandleCallbacks(for sessionID: UUID) -> Bool {
        guard sessionID == activeRecordingSessionID else {
            VoxtLog.info("Ignoring stale session callback. sessionID=\(sessionID.uuidString)", verbose: true)
            return false
        }
        guard !isSessionCancellationRequested else {
            VoxtLog.info("Ignoring callback for cancelled session. sessionID=\(sessionID.uuidString)", verbose: true)
            return false
        }
        return true
    }

    private var sessionOutputModeLabel: String {
        switch sessionOutputMode {
        case .transcription:
            return "transcription"
        case .translation:
            return "translation"
        case .rewrite:
            return "rewrite"
        }
    }

}

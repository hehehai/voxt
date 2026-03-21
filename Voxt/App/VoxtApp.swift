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

struct SettingsWindowPresentationState {
    var shouldRestoreAfterUpdate = false
}

@main
struct VoxtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    var body: some Scene {
        Settings {
            SettingsView(
                availableDictionaryHistoryScanModels: {
                    appDelegate.availableDictionaryHistoryScanModelOptions()
                },
                onIngestDictionarySuggestionsFromHistory: { request, persistSettings in
                    appDelegate.startDictionaryHistorySuggestionScan(
                        request: request,
                        persistSettings: persistSettings
                    )
                },
                mlxModelManager: appDelegate.mlxModelManager,
                whisperModelManager: appDelegate.whisperModelManager,
                customLLMManager: appDelegate.customLLMManager,
                historyStore: appDelegate.historyStore,
                dictionaryStore: appDelegate.dictionaryStore,
                dictionarySuggestionStore: appDelegate.dictionarySuggestionStore,
                appUpdateManager: appDelegate.appUpdateManager
            )
                .frame(width: 760, height: 560)
                .environment(\.locale, interfaceLanguage.locale)
        }
    }

    private var interfaceLanguage: AppInterfaceLanguage {
        AppInterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .system
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
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
    let overlayState = OverlayState()
    var statusItem: NSStatusItem?

    var enhancer: TextEnhancer?
    var settingsWindowController: NSWindowController?
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

    var isSessionActive = false
    var pendingSessionFinishTask: Task<Void, Never>?
    var stopRecordingFallbackTask: Task<Void, Never>?
    var silenceMonitorTask: Task<Void, Never>?
    var pauseLLMTask: Task<Void, Never>?
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
    let tapStopGuardInterval: TimeInterval = 0.35
    let transcriptionStartDebounceInterval: TimeInterval = 0.08
    var settingsWindowPresentationState = SettingsWindowPresentationState()

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
            let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementMode)
            return EnhancementMode(rawValue: raw ?? "") ?? .off
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        VoxtLog.info("Voxt launching.")
        AppBehaviorController.applyDockVisibility(showInDock: showInDock)
        migrateLegacyPreferences()

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
            self?.prepareSettingsWindowForUpdatePresentation()
        }
        appUpdateManager.onUpdatePresentationDidEnd = { [weak self] in
            self?.restoreSettingsWindowAfterUpdateSessionIfNeeded()
        }
        selectedInputDeviceObserver = NotificationCenter.default.addObserver(
            forName: .voxtSelectedInputDeviceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.buildMenu()
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

        VoxtLog.info("Voxt launch completed. engine=\(transcriptionEngine.rawValue), enhancement=\(enhancementMode.rawValue)")
    }

    func applicationWillTerminate(_ notification: Notification) {
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
            self?.scheduleHotkeyTransientStateReset(reason: "workspaceWillSleep")
        }

        workspaceDidWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleHotkeyTransientStateReset(reason: "workspaceDidWake")
        }

        workspaceSessionDidBecomeActiveObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleHotkeyTransientStateReset(reason: "workspaceSessionDidBecomeActive")
        }

        workspaceSessionDidResignActiveObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleHotkeyTransientStateReset(reason: "workspaceSessionDidResignActive")
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

    private func cancelPendingTranscriptionStart() {
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

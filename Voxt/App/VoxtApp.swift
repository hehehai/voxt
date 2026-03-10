import SwiftUI
import AppKit
import ApplicationServices
import CoreAudio
import AVFoundation
import Speech

@main
struct VoxtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    var body: some Scene {
        Settings {
            SettingsView(
                mlxModelManager: appDelegate.mlxModelManager,
                customLLMManager: appDelegate.customLLMManager,
                historyStore: appDelegate.historyStore,
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
        let matchedAppGroupName: String?
        let matchedURLGroupName: String?
    }

    enum SessionOutputMode {
        case transcription
        case translation
    }

    let speechTranscriber = SpeechTranscriber()
    var mlxTranscriber: MLXTranscriber?
    let remoteASRTranscriber = RemoteASRTranscriber()
    let mlxModelManager: MLXModelManager
    let customLLMManager: CustomLLMModelManager
    let historyStore = TranscriptionHistoryStore()
    let appUpdateManager = AppUpdateManager()
    let interactionSoundPlayer = InteractionSoundPlayer()

    let hotkeyManager = HotkeyManager()
    let overlayWindow = RecordingOverlayWindow()
    let overlayState = OverlayState()
    var statusItem: NSStatusItem?

    var enhancer: TextEnhancer?
    var settingsWindowController: NSWindowController?
    private var defaultsObserver: NSObjectProtocol?
    private var interfaceLanguageObserver: NSObjectProtocol?
    private var updateAvailabilityObserver: NSObjectProtocol?

    var isSessionActive = false
    var pendingSessionFinishTask: Task<Void, Never>?
    var stopRecordingFallbackTask: Task<Void, Never>?
    var silenceMonitorTask: Task<Void, Never>?
    var pauseLLMTask: Task<Void, Never>?
    var overlayReminderTask: Task<Void, Never>?
    var overlayStatusClearTask: Task<Void, Never>?
    var lastSignificantAudioAt = Date()
    var didTriggerPauseTranscription = false
    var didTriggerPauseLLM = false
    let silenceAudioLevelThreshold: Float = 0.06
    let sessionFinishDelay: TimeInterval = 1.2
    var recordingStartedAt: Date?
    var recordingStoppedAt: Date?
    var transcriptionProcessingStartedAt: Date?
    var transcriptionResultReceivedAt: Date?
    var sessionOutputMode: SessionOutputMode = .transcription
    var isSelectedTextTranslationFlow = false
    var didCommitSessionOutput = false
    var pendingTranscriptionStartTask: Task<Void, Never>?
    var enhancementContextSnapshot: EnhancementContextSnapshot?
    var lastEnhancementPromptContext: EnhancementPromptContext?
    let tapStopGuardInterval: TimeInterval = 0.35
    let transcriptionStartDebounceInterval: TimeInterval = 0.08

    override init() {
        let repo = UserDefaults.standard.string(forKey: AppPreferenceKey.mlxModelRepo)
            ?? MLXModelManager.defaultModelRepo
        let useMirror = UserDefaults.standard.bool(forKey: AppPreferenceKey.useHfMirror)
        let hubURL = useMirror ? MLXModelManager.mirrorHubBaseURL : MLXModelManager.defaultHubBaseURL
        mlxModelManager = MLXModelManager(modelRepo: repo, hubBaseURL: hubURL)
        let llmRepo = UserDefaults.standard.string(forKey: AppPreferenceKey.customLLMModelRepo)
            ?? CustomLLMModelManager.defaultModelRepo
        customLLMManager = CustomLLMModelManager(modelRepo: llmRepo, hubBaseURL: hubURL)
        UserDefaults.standard.register(defaults: [
            AppPreferenceKey.interactionSoundsEnabled: true,
            AppPreferenceKey.interactionSoundPreset: InteractionSoundPreset.soft.rawValue,
            AppPreferenceKey.overlayPosition: OverlayPosition.bottom.rawValue,
            AppPreferenceKey.interfaceLanguage: AppInterfaceLanguage.system.rawValue,
            AppPreferenceKey.translationTargetLanguage: TranslationTargetLanguage.english.rawValue,
            AppPreferenceKey.translationModelProvider: TranslationModelProvider.customLLM.rawValue,
            AppPreferenceKey.translateSelectedTextOnTranslationHotkey: true,
            AppPreferenceKey.autoCopyWhenNoFocusedInput: false,
            AppPreferenceKey.appEnhancementEnabled: false,
            AppPreferenceKey.translationSystemPrompt: AppPreferenceKey.defaultTranslationPrompt,
            AppPreferenceKey.remoteASRSelectedProvider: RemoteASRProvider.openAIWhisper.rawValue,
            AppPreferenceKey.remoteASRProviderConfigurations: "",
            AppPreferenceKey.remoteLLMSelectedProvider: RemoteLLMProvider.openAI.rawValue,
            AppPreferenceKey.remoteLLMProviderConfigurations: "",
            AppPreferenceKey.translationRemoteLLMProvider: "",
            AppPreferenceKey.launchAtLogin: false,
            AppPreferenceKey.showInDock: false,
            AppPreferenceKey.historyEnabled: false,
            AppPreferenceKey.historyRetentionPeriod: HistoryRetentionPeriod.thirtyDays.rawValue,
            AppPreferenceKey.autoCheckForUpdates: true,
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
        buildMenu()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.buildMenu()
                guard let self else { return }
                self.appUpdateManager.automaticallyChecksForUpdates = self.autoCheckForUpdates
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

        appUpdateManager.automaticallyChecksForUpdates = autoCheckForUpdates
        VoxtLog.info("Voxt launch completed. engine=\(transcriptionEngine.rawValue), enhancement=\(enhancementMode.rawValue)")
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        if let interfaceLanguageObserver {
            NotificationCenter.default.removeObserver(interfaceLanguageObserver)
        }
        if let updateAvailabilityObserver {
            NotificationCenter.default.removeObserver(updateAvailabilityObserver)
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
        // - HotkeyManager only emits normalized events (transcriptionDown/up, translationDown/up).
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
        hotkeyManager.start()
        VoxtLog.info("Hotkey callbacks configured.")
    }

    private func shouldIgnoreTapStop() -> Bool {
        guard let startedAt = recordingStartedAt else { return false }
        let elapsed = Date().timeIntervalSince(startedAt)
        return elapsed < tapStopGuardInterval
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
        VoxtLog.info(
            "Hotkey callback transcriptionDown. mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
            verbose: true
        )
        let actions = HotkeyActionResolver.resolveTranscriptionDown(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop()
            )
        )
        for action in actions {
            performHotkeyAction(action)
        }
    }

    private func handleTranscriptionHotkeyUp() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        guard triggerMode == .longPress else { return }
        VoxtLog.info(
            "Hotkey callback transcriptionUp. isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
            verbose: true
        )
        let actions = HotkeyActionResolver.resolveTranscriptionUp(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop()
            )
        )
        for action in actions {
            performHotkeyAction(action)
        }
    }

    private func handleTranslationHotkeyDown() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        VoxtLog.info(
            "Hotkey callback translationDown. mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
            verbose: true
        )
        let actions = HotkeyActionResolver.resolveTranslationDown(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop()
            )
        )
        for action in actions where action == .cancelPendingTranscriptionStart {
            performHotkeyAction(action)
        }
        guard !isSessionActive else {
            VoxtLog.info("Translation down ignored: session already active.", verbose: true)
            return
        }

        // Highest priority branch:
        // if user has selected text, fn+shift should run selected-text translation directly,
        // without opening microphone recording flow.
        if beginSelectedTextTranslationIfPossible() {
            VoxtLog.info("Translation down handled by selected-text translation flow.", verbose: true)
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
        VoxtLog.info(
            "Hotkey callback translationUp. isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), selectedTextFlow=\(isSelectedTextTranslationFlow)",
            verbose: true
        )
        let actions = HotkeyActionResolver.resolveTranslationUp(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop()
            )
        )
        for action in actions {
            performHotkeyAction(action)
        }
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
        VoxtLog.info("Scheduling pending transcription start. delaySec=\(transcriptionStartDebounceInterval)", verbose: true)
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
                VoxtLog.info("Pending transcription start dropped: session already active.", verbose: true)
                self.pendingTranscriptionStartTask = nil
                return
            }
            self.pendingTranscriptionStartTask = nil
            VoxtLog.info("Pending transcription start fired.", verbose: true)
            self.beginRecording(outputMode: .transcription)
        }
    }

    private func cancelPendingTranscriptionStart() {
        if pendingTranscriptionStartTask != nil {
            VoxtLog.info("Canceled pending transcription start.", verbose: true)
        }
        pendingTranscriptionStartTask?.cancel()
        pendingTranscriptionStartTask = nil
    }

}

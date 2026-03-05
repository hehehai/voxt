import SwiftUI
import AppKit
import ApplicationServices
import CoreAudio
import AVFoundation
import Speech
import HuggingFace

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case dictation
    case mlxAudio

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .dictation: return "Direct Dictation"
        case .mlxAudio: return "MLX Audio (On-device)"
        }
    }

    var title: String {
        switch self {
        case .dictation: return AppLocalization.localizedString("Direct Dictation")
        case .mlxAudio: return AppLocalization.localizedString("MLX Audio (On-device)")
        }
    }

    var description: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Uses Apple's built-in speech recognition. Works immediately with no setup.")
        case .mlxAudio:
            return AppLocalization.localizedString("Uses MLX Audio speech models running locally. Requires a one-time model download.")
        }
    }
}

enum EnhancementMode: String, CaseIterable, Identifiable {
    case off
    case appleIntelligence
    case customLLM

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .off: return "Off"
        case .appleIntelligence: return "Apple Intelligence"
        case .customLLM: return "Custom LLM"
        }
    }

    var title: String {
        switch self {
        case .off: return AppLocalization.localizedString("Off")
        case .appleIntelligence: return AppLocalization.localizedString("Apple Intelligence")
        case .customLLM: return AppLocalization.localizedString("Custom LLM")
        }
    }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case bottom
    case top

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        }
    }

    var title: String {
        switch self {
        case .bottom: return AppLocalization.localizedString("Bottom")
        case .top: return AppLocalization.localizedString("Top")
        }
    }
}

enum AppPreferenceKey {
    static let transcriptionEngine = "transcriptionEngine"
    static let enhancementMode = "enhancementMode"
    static let enhancementSystemPrompt = "enhancementSystemPrompt"
    static let translationSystemPrompt = "translationSystemPrompt"
    static let mlxModelRepo = "mlxModelRepo"
    static let customLLMModelRepo = "customLLMModelRepo"
    static let translationCustomLLMModelRepo = "translationCustomLLMModelRepo"
    static let modelStorageRootPath = "modelStorageRootPath"
    static let modelStorageRootBookmark = "modelStorageRootBookmark"
    static let useHfMirror = "useHfMirror"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let translationHotkeyKeyCode = "translationHotkeyKeyCode"
    static let translationHotkeyModifiers = "translationHotkeyModifiers"
    static let hotkeyTriggerMode = "hotkeyTriggerMode"
    static let selectedInputDeviceID = "selectedInputDeviceID"
    static let interactionSoundsEnabled = "interactionSoundsEnabled"
    static let interactionSoundPreset = "interactionSoundPreset"
    static let overlayPosition = "overlayPosition"
    static let interfaceLanguage = "interfaceLanguage"
    static let translationTargetLanguage = "translationTargetLanguage"
    static let autoCopyWhenNoFocusedInput = "autoCopyWhenNoFocusedInput"
    static let appEnhancementEnabled = "appEnhancementEnabled"
    static let appBranchGroups = "appBranchGroups"
    static let appBranchURLs = "appBranchURLs"
    static let appBranchCustomBrowsers = "appBranchCustomBrowsers"
    static let customLLMRemoteSizeCache = "customLLMRemoteSizeCache"
    static let launchAtLogin = "launchAtLogin"
    static let showInDock = "showInDock"
    static let historyEnabled = "historyEnabled"
    static let historyRetentionPeriod = "historyRetentionPeriod"
    static let autoCheckForUpdates = "autoCheckForUpdates"

    static let defaultEnhancementPrompt = """
        You are Voxt, a speech-to-text transcription assistant. Your only job is to enhance raw transcription output. Fix punctuation, add missing commas, correct capitalization, and improve formatting. Do not alter the meaning, tone, or substance of the text. Clean up non-sematic tone words，Do not add, remove, or rephrase any content. Do not add commentary or explanations. Return only the cleaned-up text. If there is a mixed language, please pay attention to keep the mixed language semantics.
        """

    static let defaultTranslationPrompt = """
        You are Voxt's translation assistant. Translate the input text to {target_language}.
        Preserve meaning, tone, names, numbers, and formatting.
        Return only the translated text.
        """
}

enum ModelStorageDirectoryManager {
    private static var securityScopedURL: URL?

    static var defaultRootURL: URL {
        HubCache.default.cacheDirectory
    }

    static func resolvedRootURL() -> URL {
        let defaults = UserDefaults.standard
        if let bookmarkData = defaults.data(forKey: AppPreferenceKey.modelStorageRootBookmark),
           let bookmarkedURL = resolveSecurityScopedURL(from: bookmarkData) {
            return bookmarkedURL
        }

        if let path = defaults.string(forKey: AppPreferenceKey.modelStorageRootPath), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return defaultRootURL
    }

    static func saveUserSelectedRootURL(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        let bookmark = try normalized.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let defaults = UserDefaults.standard
        defaults.set(normalized.path, forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.set(bookmark, forKey: AppPreferenceKey.modelStorageRootBookmark)

        _ = resolveSecurityScopedURL(from: bookmark)
    }

    static func openRootInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: resolvedRootURL().path)
    }

    private static func resolveSecurityScopedURL(from bookmarkData: Data) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if securityScopedURL?.path != resolved.path {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            if resolved.startAccessingSecurityScopedResource() {
                securityScopedURL = resolved
            }
        }

        if isStale,
           let refreshed = try? resolved.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
           ) {
            UserDefaults.standard.set(refreshed, forKey: AppPreferenceKey.modelStorageRootBookmark)
        }

        return resolved
    }
}

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
    private struct StoredBranchURLItem: Codable {
        let id: UUID
        let pattern: String
    }

    private struct StoredAppBranchGroup: Codable {
        let id: UUID
        let name: String
        let prompt: String
        let appBundleIDs: [String]
        let urlPatternIDs: [UUID]
        let isExpanded: Bool

        private enum CodingKeys: String, CodingKey {
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

    private struct StoredCustomBrowser: Codable {
        let bundleID: String
        let displayName: String
    }

    private struct BrowserScriptProvider {
        let name: String
        let scripts: [String]
    }

    private struct EnhancementContextSnapshot {
        let bundleID: String?
        let capturedAt: Date
    }

    private struct EnhancementPromptContext {
        let focusedAppName: String?
        let matchedAppGroupName: String?
        let matchedURLGroupName: String?
    }

    private enum SessionOutputMode {
        case transcription
        case translation
    }

    private let speechTranscriber = SpeechTranscriber()
    private var mlxTranscriber: MLXTranscriber?
    let mlxModelManager: MLXModelManager
    let customLLMManager: CustomLLMModelManager
    let historyStore = TranscriptionHistoryStore()
    let appUpdateManager = AppUpdateManager()
    private let interactionSoundPlayer = InteractionSoundPlayer()

    private let hotkeyManager = HotkeyManager()
    private let overlayWindow = RecordingOverlayWindow()
    private let overlayState = OverlayState()
    private var statusItem: NSStatusItem?

    private var enhancer: TextEnhancer?
    private var settingsWindowController: NSWindowController?
    private var defaultsObserver: NSObjectProtocol?
    private var interfaceLanguageObserver: NSObjectProtocol?

    private var isSessionActive = false
    private var pendingSessionFinishTask: Task<Void, Never>?
    private var stopRecordingFallbackTask: Task<Void, Never>?
    private var silenceMonitorTask: Task<Void, Never>?
    private var pauseLLMTask: Task<Void, Never>?
    private var overlayReminderTask: Task<Void, Never>?
    private var overlayStatusClearTask: Task<Void, Never>?
    private var lastSignificantAudioAt = Date()
    private var didTriggerPauseTranscription = false
    private var didTriggerPauseLLM = false
    private let silenceAudioLevelThreshold: Float = 0.06
    private let sessionFinishDelay: TimeInterval = 1.2
    private var recordingStartedAt: Date?
    private var recordingStoppedAt: Date?
    private var transcriptionProcessingStartedAt: Date?
    private var sessionOutputMode: SessionOutputMode = .transcription
    private var enhancementContextSnapshot: EnhancementContextSnapshot?
    private var lastEnhancementPromptContext: EnhancementPromptContext?

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
            AppPreferenceKey.autoCopyWhenNoFocusedInput: false,
            AppPreferenceKey.appEnhancementEnabled: false,
            AppPreferenceKey.translationSystemPrompt: AppPreferenceKey.defaultTranslationPrompt,
            AppPreferenceKey.launchAtLogin: false,
            AppPreferenceKey.showInDock: false,
            AppPreferenceKey.historyEnabled: false,
            AppPreferenceKey.historyRetentionPeriod: HistoryRetentionPeriod.thirtyDays.rawValue,
            AppPreferenceKey.autoCheckForUpdates: true,
        ])
        HotkeyPreference.registerDefaults()
        HotkeyPreference.migrateDefaultsIfNeeded()
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

    private var enhancementMode: EnhancementMode {
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

    private var appEnhancementEnabled: Bool {
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
    }

    private func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: AppPreferenceKey.enhancementMode) == nil,
           defaults.object(forKey: "aiEnhanceEnabled") != nil {
            let oldEnabled = defaults.bool(forKey: "aiEnhanceEnabled")
            enhancementMode = oldEnabled ? .appleIntelligence : .off
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: AppLocalization.localizedString("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let reportItem = NSMenuItem(title: AppLocalization.localizedString("Report"), action: #selector(openReportSettings), keyEquivalent: "")
        reportItem.target = self
        menu.addItem(reportItem)
        let checkUpdatesItem = NSMenuItem(
            title: AppLocalization.localizedString("Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: AppLocalization.localizedString("Quit Voxt"), action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func checkForUpdates() {
        VoxtLog.info("Manual update check triggered from menu.")
        appUpdateManager.checkForUpdates(source: .manual)
    }

    @objc private func openSettings() {
        openSettingsWindow(selectTab: nil)
    }

    @objc private func openReportSettings() {
        openSettingsWindow(selectTab: .report)
    }

    private func openSettingsWindow(selectTab: SettingsTab?) {
        if let window = settingsWindowController?.window {
            if let selectTab {
                NotificationCenter.default.post(
                    name: .voxtSettingsSelectTab,
                    object: nil,
                    userInfo: ["tab": selectTab.rawValue]
                )
            }
            centerAndBringWindowToFront(window)
            return
        }

        let contentView = SettingsView(
            mlxModelManager: mlxModelManager,
            customLLMManager: customLLMManager,
            historyStore: historyStore,
            appUpdateManager: appUpdateManager,
            initialTab: selectTab ?? .general
        )
            .frame(width: 760, height: 560)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.level = .normal
        positionWindowTrafficLightButtons(window)

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = false
        settingsWindowController = controller
        window.center()
        controller.showWindow(nil)
        positionWindowTrafficLightButtons(window)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.positionWindowTrafficLightButtons(window)
        }
        bringWindowToFront(window)
    }

    private func bringWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func centerAndBringWindowToFront(_ window: NSWindow) {
        window.center()
        bringWindowToFront(window)
        positionWindowTrafficLightButtons(window)
    }

    private func positionWindowTrafficLightButtons(_ window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let miniaturizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let container = closeButton.superview
        else {
            return
        }

        let leftInset: CGFloat = 22
        let topInset: CGFloat = 21
        let spacing: CGFloat = 6

        let buttonSize = closeButton.frame.size
        let y = container.bounds.height - topInset - buttonSize.height
        let closeX = leftInset
        let miniaturizeX = closeX + buttonSize.width + spacing
        let zoomX = miniaturizeX + buttonSize.width + spacing

        closeButton.translatesAutoresizingMaskIntoConstraints = true
        miniaturizeButton.translatesAutoresizingMaskIntoConstraints = true
        zoomButton.translatesAutoresizingMaskIntoConstraints = true

        closeButton.setFrameOrigin(CGPoint(x: closeX, y: y))
        miniaturizeButton.setFrameOrigin(CGPoint(x: miniaturizeX, y: y))
        zoomButton.setFrameOrigin(CGPoint(x: zoomX, y: y))
    }

    private func setupHotkey() {
        hotkeyManager.onKeyDown = { [weak self] in
            guard let self else { return }
            switch HotkeyPreference.loadTriggerMode() {
            case .longPress:
                guard !self.isSessionActive else { return }
                self.beginRecording(outputMode: .transcription)
            case .tap:
                if self.isSessionActive {
                    self.endRecording()
                } else {
                    self.beginRecording(outputMode: .transcription)
                }
            }
        }
        hotkeyManager.onKeyUp = { [weak self] in
            guard let self else { return }
            guard HotkeyPreference.loadTriggerMode() == .longPress else { return }
            guard self.isSessionActive, self.sessionOutputMode == .transcription else { return }
            self.endRecording()
        }
        hotkeyManager.onTranslationKeyDown = { [weak self] in
            guard let self else { return }
            switch HotkeyPreference.loadTriggerMode() {
            case .longPress:
                guard !self.isSessionActive else { return }
                self.beginRecording(outputMode: .translation)
            case .tap:
                if self.isSessionActive {
                    // In tap mode, translation hotkey should never mutate an active
                    // transcription session into translation mode. If a session is
                    // already running, treat this as a stop action only.
                    self.endRecording()
                } else {
                    self.beginRecording(outputMode: .translation)
                }
            }
        }
        hotkeyManager.onTranslationKeyUp = { [weak self] in
            guard let self else { return }
            guard HotkeyPreference.loadTriggerMode() == .longPress else { return }
            guard self.isSessionActive, self.sessionOutputMode == .translation else { return }
            self.endRecording()
        }
        hotkeyManager.start()
        VoxtLog.info("Hotkey callbacks configured.")
    }

    private func beginRecording(outputMode: SessionOutputMode) {
        guard !isSessionActive else { return }
        guard preflightPermissionsForRecording() else { return }
        pendingSessionFinishTask?.cancel()
        pendingSessionFinishTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        overlayState.isCompleting = false
        setEnhancingState(false)
        recordingStartedAt = Date()
        recordingStoppedAt = nil
        transcriptionProcessingStartedAt = nil
        sessionOutputMode = outputMode
        enhancementContextSnapshot = nil
        VoxtLog.info(
            "Recording started. output=\(outputMode == .translation ? "translation" : "transcription"), engine=\(transcriptionEngine.rawValue)"
        )
        applyPreferredInputDevice()
        overlayState.statusMessage = ""

        if transcriptionEngine == .mlxAudio {
            switch mlxModelManager.state {
            case .notDownloaded:
                VoxtLog.warning("MLX Audio model not downloaded, falling back to Direct Dictation")
                showOverlayStatus(
                    String(localized: "MLX model is not downloaded. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
            case .error:
                VoxtLog.warning("MLX Audio model error, falling back to Direct Dictation")
                showOverlayStatus(
                    String(localized: "MLX model is unavailable. Open Settings > Model to fix it."),
                    clearAfter: 2.5
                )
            default:
                break
            }
        }

        isSessionActive = true
        if interactionSoundsEnabled {
            interactionSoundPlayer.playStart()
        }

        if transcriptionEngine == .mlxAudio, isMLXReady {
            startMLXRecordingSession()
        } else {
            startSpeechRecordingSession()
        }

        startSilenceMonitoringIfNeeded()
    }

    private var isMLXReady: Bool {
        switch mlxModelManager.state {
        case .downloaded, .ready, .loading:
            return true
        default:
            return false
        }
    }

    private func endRecording() {
        guard isSessionActive else { return }
        VoxtLog.info("Recording stop requested.")
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        recordingStoppedAt = Date()
        if transcriptionProcessingStartedAt == nil {
            transcriptionProcessingStartedAt = recordingStoppedAt
        }
        enhancementContextSnapshot = captureEnhancementContextSnapshot()

        if transcriptionEngine == .mlxAudio, isMLXReady {
            mlxTranscriber?.stopRecording()
        } else {
            speechTranscriber.stopRecording()
        }

        // Safety fallback: some engine/device combinations may occasionally fail to
        // report completion. Ensure the session/UI can always recover.
        stopRecordingFallbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard self.isSessionActive else { return }
            VoxtLog.warning("Stop recording fallback triggered; forcing session finish.")
            self.finishSession(after: 0)
        }
    }

    private func processTranscription(_ rawText: String) {
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            VoxtLog.info("Transcription result is empty; finishing session.")
            setEnhancingState(false)
            finishSession(after: 0)
            return
        }
        VoxtLog.info("Transcription result received. characters=\(text.count), output=\(sessionOutputMode == .translation ? "translation" : "transcription")")
        VoxtLog.info("Enhancement mode=\(enhancementMode.rawValue), appEnhancementEnabled=\(appEnhancementEnabled)")

        if sessionOutputMode == .translation {
            processTranslatedTranscription(text)
            return
        }

        switch enhancementMode {
        case .off:
            setEnhancingState(false)
            commitTranscription(text, llmDurationSeconds: nil)
            finishSession()

        case .appleIntelligence:
            guard let enhancer else {
                setEnhancingState(false)
                commitTranscription(text, llmDurationSeconds: nil)
                finishSession()
                return
            }

            setEnhancingState(true)
            Task {
                defer {
                    self.setEnhancingState(false)
                    self.finishSession()
                }
                do {
                    if #available(macOS 26.0, *) {
                        let prompt = self.resolvedEnhancementPrompt()
                        let llmStartedAt = Date()
                        let enhanced = try await enhancer.enhance(text, systemPrompt: prompt)
                        let llmDuration = Date().timeIntervalSince(llmStartedAt)
                        self.commitTranscription(enhanced, llmDurationSeconds: llmDuration)
                    } else {
                        self.commitTranscription(text, llmDurationSeconds: nil)
                    }
                } catch {
                    VoxtLog.error("AI enhancement failed, using raw text: \(error)")
                    self.commitTranscription(text, llmDurationSeconds: nil)
                }
            }

        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo) else {
                VoxtLog.warning("Custom LLM selected but local model is not installed. Using raw transcription.")
                showOverlayStatus(
                    String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
                setEnhancingState(false)
                commitTranscription(text, llmDurationSeconds: nil)
                finishSession()
                return
            }

            setEnhancingState(true)
            Task {
                defer {
                    self.setEnhancingState(false)
                    self.finishSession()
                }
                let llmStartedAt = Date()
                let prompt = self.resolvedEnhancementPrompt()
                do {
                    let enhanced = try await self.customLLMManager.enhance(text, systemPrompt: prompt)
                    let llmDuration = Date().timeIntervalSince(llmStartedAt)
                    self.commitTranscription(enhanced, llmDurationSeconds: llmDuration)
                } catch {
                    VoxtLog.error("Custom LLM enhancement failed, using raw text: \(error)")
                    self.commitTranscription(text, llmDurationSeconds: nil)
                }
            }
        }
    }

    private func processTranslatedTranscription(_ text: String) {
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
                self.finishSession()
            }

            let llmStartedAt = Date()
            do {
                let enhanced = try await self.enhanceTextIfNeeded(text)
                let translated = try await self.translateText(enhanced, targetLanguage: self.translationTargetLanguage)
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                self.commitTranscription(translated, llmDurationSeconds: llmDuration)
            } catch {
                VoxtLog.warning("Translation flow failed, using raw text: \(error)")
                self.commitTranscription(text, llmDurationSeconds: nil)
            }
        }
    }

    private func enhanceTextIfNeeded(_ text: String) async throws -> String {
        switch enhancementMode {
        case .off:
            return text
        case .appleIntelligence:
            guard let enhancer else { return text }
            if #available(macOS 26.0, *) {
                let prompt = resolvedEnhancementPrompt()
                return try await enhancer.enhance(text, systemPrompt: prompt)
            }
            return text
        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo) else { return text }
            let prompt = resolvedEnhancementPrompt()
            return try await customLLMManager.enhance(text, systemPrompt: prompt)
        }
    }

    private func translateText(_ text: String, targetLanguage: TranslationTargetLanguage) async throws -> String {
        let resolvedPrompt = translationSystemPrompt.replacingOccurrences(
            of: "{target_language}",
            with: targetLanguage.instructionName
        )
        let translationRepo = translationCustomLLMRepo

        switch enhancementMode {
        case .customLLM where customLLMManager.isModelDownloaded(repo: translationRepo):
            return try await customLLMManager.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: resolvedPrompt,
                modelRepo: translationRepo
            )
        case .customLLM:
            showOverlayStatus(
                String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                clearAfter: 2.5
            )
        default:
            break
        }

        if #available(macOS 26.0, *), let enhancer {
            return try await enhancer.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: resolvedPrompt
            )
        }

        if customLLMManager.isModelDownloaded(repo: translationRepo) {
            return try await customLLMManager.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: resolvedPrompt,
                modelRepo: translationRepo
            )
        }

        return text
    }

    private func commitTranscription(_ text: String, llmDurationSeconds: TimeInterval?) {
        let normalized = normalizedOutputText(text)
        typeText(normalized)
        appendHistoryIfNeeded(text: normalized, llmDurationSeconds: llmDurationSeconds)
    }

    private func normalizedOutputText(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return value }

        // Remove paired wrapping double quotes generated by some LLM responses.
        let left = value.first
        let right = value.last
        let isWrappedByDoubleQuotes =
            (left == "\"" && right == "\"") ||
            (left == "“" && right == "”")

        if isWrappedByDoubleQuotes {
            value.removeFirst()
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    private func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string) ?? ""
        let accessibilityTrusted = AXIsProcessTrusted()
        let keepResultInClipboard = autoCopyWhenNoFocusedInput

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard accessibilityTrusted else {
            promptForAccessibilityPermission()
            VoxtLog.warning("Accessibility permission missing. Transcription copied; paste manually after granting permission.")
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            VoxtLog.error("typeText failed: unable to create CGEventSource")
            return
        }

        let vKeyCode: CGKeyCode = 0x09
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand

        guard cmdDown != nil, cmdUp != nil else {
            VoxtLog.error("typeText failed: unable to create key events")
            return
        }

        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)

        if !keepResultInClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                pasteboard.clearContents()
                if !previous.isEmpty {
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    private func promptForAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func startMLXRecordingSession() {
        let mlx = mlxTranscriber ?? MLXTranscriber(modelManager: mlxModelManager)
        mlxTranscriber = mlx
        overlayState.statusMessage = ""
        mlx.setPreferredInputDevice(selectedInputDeviceID)
        mlx.onTranscriptionFinished = { [weak self] text in
            self?.processTranscription(text)
        }
        overlayState.bind(to: mlx)
        overlayWindow.show(
            state: overlayState,
            position: overlayPosition
        )
        mlx.startRecording()
    }

    private func startSpeechRecordingSession() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.speechTranscriber.requestPermissions()
            guard granted else {
                self.showOverlayReminder(
                    String(localized: "Please enable required permissions in Settings > Permissions.")
                )
                return
            }

            self.overlayState.statusMessage = ""
            self.speechTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.processTranscription(text)
            }
            self.overlayState.bind(to: self.speechTranscriber)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition
            )
            self.speechTranscriber.startRecording()
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func preflightPermissionsForRecording() -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            VoxtLog.warning("Recording blocked: microphone permission not granted.")
            showOverlayReminder(
                String(localized: "Microphone permission is required. Enable it in Settings > Permissions.")
            )
            return false
        }

        if transcriptionEngine == .dictation && SFSpeechRecognizer.authorizationStatus() != .authorized {
            VoxtLog.warning("Recording blocked: speech recognition permission not granted for Direct Dictation.")
            showOverlayReminder(
                String(localized: "Speech Recognition permission is required for Direct Dictation. Enable it in Settings > Permissions.")
            )
            return false
        }

        if !AXIsProcessTrusted() {
            showOverlayStatus(
                String(localized: "Please enable required permissions in Settings > Permissions."),
                clearAfter: 2.2
            )
        }

        return true
    }

    private func showOverlayReminder(_ message: String, autoHideAfter seconds: TimeInterval = 2.4) {
        overlayReminderTask?.cancel()
        overlayStatusClearTask?.cancel()
        overlayState.reset()
        overlayState.statusMessage = message
        overlayWindow.show(state: overlayState, position: overlayPosition)

        overlayReminderTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self.overlayWindow.hide()
            self.overlayState.reset()
            self.overlayReminderTask = nil
        }
    }

    private func showOverlayStatus(_ message: String, clearAfter seconds: TimeInterval = 2.4) {
        overlayStatusClearTask?.cancel()
        overlayState.statusMessage = message
        overlayStatusClearTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            if self.overlayState.statusMessage == message {
                self.overlayState.statusMessage = ""
            }
            self.overlayStatusClearTask = nil
        }
    }

    private func setEnhancingState(_ isEnhancing: Bool) {
        overlayState.isEnhancing = isEnhancing
        if transcriptionEngine == .mlxAudio {
            mlxTranscriber?.isEnhancing = isEnhancing
        } else {
            speechTranscriber.isEnhancing = isEnhancing
        }
    }

    private func finishSession(after delay: TimeInterval = 0) {
        pendingSessionFinishTask?.cancel()
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil

        let resolvedDelay = delay > 0 ? delay : sessionFinishDelay
        overlayState.isCompleting = resolvedDelay > 0
        pendingSessionFinishTask = Task { [weak self] in
            guard let self else { return }

            if resolvedDelay > 0 {
                do {
                    try await Task.sleep(for: .seconds(resolvedDelay))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            self.overlayWindow.hide()
            if self.interactionSoundsEnabled {
                self.interactionSoundPlayer.playEnd()
            }
            self.isSessionActive = false
            self.sessionOutputMode = .transcription
            self.enhancementContextSnapshot = nil
            self.overlayState.isCompleting = false
            self.pendingSessionFinishTask = nil
        }
    }

    private var selectedInputDeviceID: AudioDeviceID? {
        let raw = UserDefaults.standard.integer(forKey: AppPreferenceKey.selectedInputDeviceID)
        return raw > 0 ? AudioDeviceID(raw) : nil
    }

    private var interactionSoundsEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.interactionSoundsEnabled)
    }

    private var overlayPosition: OverlayPosition {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.overlayPosition)
        return OverlayPosition(rawValue: raw ?? "") ?? .bottom
    }

    private var autoCopyWhenNoFocusedInput: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.autoCopyWhenNoFocusedInput)
    }

    private var translationTargetLanguage: TranslationTargetLanguage {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.translationTargetLanguage)
        return TranslationTargetLanguage(rawValue: raw ?? "") ?? .english
    }

    private var translationSystemPrompt: String {
        let value = UserDefaults.standard.string(forKey: AppPreferenceKey.translationSystemPrompt)
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return AppPreferenceKey.defaultTranslationPrompt
    }

    private var translationCustomLLMRepo: String {
        let value = UserDefaults.standard.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo)
        if let value, !value.isEmpty {
            return value
        }
        return UserDefaults.standard.string(forKey: AppPreferenceKey.customLLMModelRepo)
            ?? CustomLLMModelManager.defaultModelRepo
    }

    private var showInDock: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.showInDock)
    }

    private var historyEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.historyEnabled)
    }

    private var autoCheckForUpdates: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.autoCheckForUpdates)
    }

    private func appendHistoryIfNeeded(text: String, llmDurationSeconds: TimeInterval?) {
        guard historyEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let transcriptionModel: String
        switch transcriptionEngine {
        case .dictation:
            transcriptionModel = "Apple Speech Recognition"
        case .mlxAudio:
            let repo = mlxModelManager.currentModelRepo
            transcriptionModel = "\(mlxModelManager.displayTitle(for: repo)) (\(repo))"
        }

        let enhancementModel: String
        switch enhancementMode {
        case .off:
            enhancementModel = "None"
        case .appleIntelligence:
            enhancementModel = "Apple Intelligence (Foundation Models)"
        case .customLLM:
            let repo = customLLMManager.currentModelRepo
            enhancementModel = "\(customLLMManager.displayTitle(for: repo)) (\(repo))"
        }

        let now = Date()
        let audioDuration = resolvedDuration(from: recordingStartedAt, to: recordingStoppedAt ?? now)
        let processingDuration = resolvedDuration(from: transcriptionProcessingStartedAt, to: now)
        let focusedAppName = lastEnhancementPromptContext?.focusedAppName ?? NSWorkspace.shared.frontmostApplication?.localizedName

        historyStore.append(
            text: trimmed,
            transcriptionEngine: transcriptionEngine.title,
            transcriptionModel: transcriptionModel,
            enhancementMode: enhancementMode.title,
            enhancementModel: enhancementModel,
            isTranslation: sessionOutputMode == .translation,
            audioDurationSeconds: audioDuration,
            transcriptionProcessingDurationSeconds: processingDuration,
            llmDurationSeconds: llmDurationSeconds,
            focusedAppName: focusedAppName,
            matchedAppGroupName: lastEnhancementPromptContext?.matchedAppGroupName,
            matchedURLGroupName: lastEnhancementPromptContext?.matchedURLGroupName
        )
        lastEnhancementPromptContext = nil
    }

    private func resolvedDuration(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        let value = end.timeIntervalSince(start)
        guard value >= 0 else { return nil }
        return value
    }

    private func applyPreferredInputDevice() {
        speechTranscriber.setPreferredInputDevice(selectedInputDeviceID)
        mlxTranscriber?.setPreferredInputDevice(selectedInputDeviceID)
    }

    private func startSilenceMonitoringIfNeeded() {
        silenceMonitorTask?.cancel()
        pauseLLMTask?.cancel()
        pauseLLMTask = nil

        guard transcriptionEngine == .mlxAudio else { return }

        lastSignificantAudioAt = Date()
        didTriggerPauseTranscription = false
        didTriggerPauseLLM = false

        silenceMonitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isSessionActive {
                guard self.overlayState.isRecording else {
                    do {
                        try await Task.sleep(for: .milliseconds(200))
                    } catch {
                        return
                    }
                    continue
                }

                let level = self.overlayState.audioLevel
                if level > self.silenceAudioLevelThreshold {
                    self.lastSignificantAudioAt = Date()
                    self.didTriggerPauseTranscription = false
                    self.didTriggerPauseLLM = false
                    self.pauseLLMTask?.cancel()
                    self.pauseLLMTask = nil
                    self.setEnhancingState(false)
                } else {
                    let silentDuration = Date().timeIntervalSince(self.lastSignificantAudioAt)

                    if silentDuration >= 2.0, !self.didTriggerPauseTranscription {
                        self.didTriggerPauseTranscription = true
                        self.mlxTranscriber?.forceIntermediateTranscription()
                    }

                    if silentDuration >= 4.0, !self.didTriggerPauseLLM {
                        self.didTriggerPauseLLM = true
                        self.startPauseLLMIfNeeded()
                    }
                }

                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
            }
        }
    }

    private func startPauseLLMIfNeeded() {
        guard enhancementMode != .off else { return }
        let input = overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        pauseLLMTask?.cancel()
        pauseLLMTask = Task { [weak self] in
            guard let self else { return }
            self.setEnhancingState(true)
            defer {
                self.setEnhancingState(false)
                self.pauseLLMTask = nil
            }

            do {
                switch self.enhancementMode {
                case .appleIntelligence:
                    guard let enhancer else { return }
                    if #available(macOS 26.0, *) {
                        let prompt = self.resolvedEnhancementPrompt()
                        let enhanced = try await enhancer.enhance(input, systemPrompt: prompt)
                        guard !Task.isCancelled else { return }
                        guard self.isSessionActive else { return }

                        // Apply only if text has not moved forward during this pause.
                        let current = self.overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if current == input {
                            self.mlxTranscriber?.transcribedText = enhanced
                        }
                    }

                case .customLLM:
                    guard self.customLLMManager.isModelDownloaded(repo: self.customLLMManager.currentModelRepo) else {
                        return
                    }
                    let prompt = self.resolvedEnhancementPrompt()
                    let enhanced = try await self.customLLMManager.enhance(input, systemPrompt: prompt)
                    guard !Task.isCancelled else { return }
                    guard self.isSessionActive else { return }

                    // Apply only if text has not moved forward during this pause.
                    let current = self.overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if current == input {
                        self.mlxTranscriber?.transcribedText = enhanced
                    }

                case .off:
                    return
                }
            } catch {
                VoxtLog.warning("Pause-time LLM enhancement skipped: \(error)")
            }
        }
    }

    @objc private func quit() {
        VoxtLog.info("Quit requested from menu.")
        hotkeyManager.stop()
        NSApp.terminate(nil)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Permissions Required")
        alert.informativeText = String(localized: "Voxt needs Microphone access. If you use Direct Dictation, enable Speech Recognition in System Settings → Privacy & Security.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Quit"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
        }
        NSApp.terminate(nil)
    }

    private func resolvedEnhancementPrompt() -> String {
        let globalPrompt = UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementSystemPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPrompt = (globalPrompt?.isEmpty == false) ? globalPrompt! : AppPreferenceKey.defaultEnhancementPrompt

        guard appEnhancementEnabled else {
            VoxtLog.info("Enhancement prompt source: global/default (app branch disabled)")
            return fallbackPrompt
        }

        let groups = loadAppBranchGroups()
        guard !groups.isEmpty else {
            VoxtLog.info("Enhancement prompt source: global/default (no app branch groups)")
            return fallbackPrompt
        }

        let urlsByID = loadAppBranchURLsByID()
        let context = currentEnhancementContext()
        let frontmostBundleID = context.bundleID
        let focusedAppName = NSWorkspace.shared.frontmostApplication?.localizedName

        if isBrowserBundleID(frontmostBundleID) {
            let activeURL = activeBrowserTabURL(frontmostBundleID: frontmostBundleID)
            let normalizedActiveURL = normalizedURLForMatching(activeURL)

            guard let normalizedActiveURL else {
                lastEnhancementPromptContext = EnhancementPromptContext(
                    focusedAppName: focusedAppName,
                    matchedAppGroupName: nil,
                    matchedURLGroupName: nil
                )
                VoxtLog.info("Enhancement prompt source: global/default (browser url unavailable), bundleID=\(frontmostBundleID ?? "nil")")
                return fallbackPrompt
            }

            if let match = firstURLPromptMatch(groups: groups, urlsByID: urlsByID, normalizedURL: normalizedActiveURL) {
                lastEnhancementPromptContext = EnhancementPromptContext(
                    focusedAppName: focusedAppName,
                    matchedAppGroupName: nil,
                    matchedURLGroupName: match.groupName
                )
                VoxtLog.info("Enhancement prompt source: group(url) group=\(match.groupName), pattern=\(match.pattern), url=\(normalizedActiveURL)")
                return match.prompt
            }

            lastEnhancementPromptContext = EnhancementPromptContext(
                focusedAppName: focusedAppName,
                matchedAppGroupName: nil,
                matchedURLGroupName: nil
            )
            VoxtLog.info("Enhancement prompt source: global/default (browser url no group match), bundleID=\(frontmostBundleID ?? "nil"), url=\(normalizedActiveURL)")
            return fallbackPrompt
        }

        if let frontmostBundleID {
            for group in groups where group.appBundleIDs.contains(frontmostBundleID) {
                let prompt = group.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prompt.isEmpty {
                    lastEnhancementPromptContext = EnhancementPromptContext(
                        focusedAppName: focusedAppName,
                        matchedAppGroupName: group.name,
                        matchedURLGroupName: nil
                    )
                    VoxtLog.info("Enhancement prompt source: group(app) group=\(group.name), bundleID=\(frontmostBundleID)")
                    return prompt
                }
            }
        }

        lastEnhancementPromptContext = EnhancementPromptContext(
            focusedAppName: focusedAppName,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil
        )
        VoxtLog.info("Enhancement prompt source: global/default (no group match), bundleID=\(frontmostBundleID ?? "nil")")
        return fallbackPrompt
    }

    private func firstURLPromptMatch(
        groups: [StoredAppBranchGroup],
        urlsByID: [UUID: String],
        normalizedURL: String
    ) -> (prompt: String, groupName: String, pattern: String)? {
        for group in groups {
            for urlID in group.urlPatternIDs {
                guard let pattern = urlsByID[urlID], wildcardMatches(pattern: pattern, candidate: normalizedURL) else {
                    continue
                }
                let prompt = group.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prompt.isEmpty {
                    return (prompt, group.name, pattern)
                }
            }
        }
        return nil
    }

    private func loadAppBranchGroups() -> [StoredAppBranchGroup] {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.appBranchGroups) else { return [] }
        return (try? JSONDecoder().decode([StoredAppBranchGroup].self, from: data)) ?? []
    }

    private func loadAppBranchURLsByID() -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.appBranchURLs),
              let items = try? JSONDecoder().decode([StoredBranchURLItem].self, from: data)
        else {
            return [:]
        }

        var result: [UUID: String] = [:]
        for item in items {
            result[item.id] = item.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return result
    }

    private func isBrowserBundleID(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return supportedBrowserBundleIDs().contains(bundleID)
    }

    private func activeBrowserTabURL(frontmostBundleID: String?) -> String? {
        guard let frontmostBundleID else { return nil }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: frontmostBundleID)
            .contains(where: { !$0.isTerminated }) else {
            VoxtLog.info("Browser process not running while resolving active tab URL. bundleID=\(frontmostBundleID)")
            return nil
        }
        guard let provider = browserScriptProvider(for: frontmostBundleID) else { return nil }
        if let scriptedURL = runAppleScriptCandidates(provider.scripts, providerName: provider.name) {
            return scriptedURL
        }
        if let axURL = activeBrowserTabURLFromAccessibility(frontmostBundleID: frontmostBundleID) {
            VoxtLog.info("Browser active-tab URL read succeeded via AX fallback. provider=\(provider.name)")
            return axURL
        }
        return nil
    }

    private func captureEnhancementContextSnapshot() -> EnhancementContextSnapshot {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return EnhancementContextSnapshot(
            bundleID: frontmostBundleID,
            capturedAt: Date()
        )
    }

    private func currentEnhancementContext() -> EnhancementContextSnapshot {
        if let snapshot = enhancementContextSnapshot {
            let age = Date().timeIntervalSince(snapshot.capturedAt)
            if age <= 20 {
                return snapshot
            }
        }
        return captureEnhancementContextSnapshot()
    }

    private func browserScriptProvider(for bundleID: String) -> BrowserScriptProvider? {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return BrowserScriptProvider(
                name: "Safari",
                scripts: [
                    "tell application id \"\(bundleID)\" to get URL of front document",
                    "tell application id \"\(bundleID)\" to get URL of current tab of front window",
                    "tell application \"Safari\" to get URL of front document"
                ]
            )
        case "com.google.Chrome":
            return BrowserScriptProvider(
                name: "Google Chrome",
                scripts: [
                    "tell application id \"com.google.Chrome\" to get the URL of active tab of front window",
                    "tell application \"Google Chrome\" to get the URL of active tab of front window"
                ]
            )
        case "com.microsoft.edgemac":
            return BrowserScriptProvider(
                name: "Microsoft Edge",
                scripts: [
                    "tell application id \"com.microsoft.edgemac\" to get the URL of active tab of front window",
                    "tell application \"Microsoft Edge\" to get the URL of active tab of front window"
                ]
            )
        case "com.brave.Browser":
            return BrowserScriptProvider(
                name: "Brave Browser",
                scripts: [
                    "tell application id \"com.brave.Browser\" to get the URL of active tab of front window",
                    "tell application \"Brave Browser\" to get the URL of active tab of front window"
                ]
            )
        case "company.thebrowser.Browser":
            return BrowserScriptProvider(
                name: "Arc",
                scripts: [
                    "tell application id \"company.thebrowser.Browser\" to get the URL of active tab of front window",
                    "tell application id \"company.thebrowser.Browser\" to get the URL of active tab of window 1",
                    "tell application \"Arc\" to get the URL of active tab of front window"
                ]
            )
        default:
            guard let customDisplayName = customBrowserDisplayName(for: bundleID) else {
                return nil
            }
            return BrowserScriptProvider(
                name: customDisplayName,
                scripts: scriptsForCustomBrowser(bundleID: bundleID, displayName: customDisplayName)
            )
        }
    }

    private func supportedBrowserBundleIDs() -> Set<String> {
        var bundleIDs: Set<String> = [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "company.thebrowser.Browser"
        ]
        for browser in loadStoredCustomBrowsers() where !browser.bundleID.isEmpty {
            bundleIDs.insert(browser.bundleID)
        }
        return bundleIDs
    }

    private func customBrowserDisplayName(for bundleID: String) -> String? {
        loadStoredCustomBrowsers().first { $0.bundleID == bundleID }?.displayName
    }

    private func loadStoredCustomBrowsers() -> [StoredCustomBrowser] {
        guard let json = UserDefaults.standard.string(forKey: AppPreferenceKey.appBranchCustomBrowsers),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([StoredCustomBrowser].self, from: data) else {
            return []
        }
        return decoded
    }

    private func scriptsForCustomBrowser(bundleID: String, displayName: String) -> [String] {
        [
            "tell application id \"\(bundleID)\" to get URL of front document",
            "tell application id \"\(bundleID)\" to get URL of current tab of front window",
            "tell application id \"\(bundleID)\" to get the URL of active tab of front window",
            "tell application id \"\(bundleID)\" to get the URL of active tab of window 1",
            "tell application \"\(displayName)\" to get URL of front document",
            "tell application \"\(displayName)\" to get the URL of active tab of front window"
        ]
    }

    private func runAppleScriptCandidates(_ sources: [String], providerName: String) -> String? {
        var lastError: NSDictionary?
        for (index, source) in sources.enumerated() {
            var executionError: NSDictionary?
            let startedAt = Date()
            if let output = runAppleScript(source, error: &executionError, logFailure: false, timeout: 0.8),
               !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                if index > 0 {
                    VoxtLog.info("Browser active-tab URL read succeeded via fallback. provider=\(providerName), candidate=\(index + 1), elapsedMs=\(elapsedMs)")
                }
                return output
            }
            if let executionError {
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VoxtLog.info(
                    "Browser active-tab URL candidate failed. provider=\(providerName), candidate=\(index + 1), elapsedMs=\(elapsedMs), error=\(executionError)"
                )
                lastError = executionError
                if let errorNumber = executionError["NSAppleScriptErrorNumber"] as? Int, errorNumber == -600 {
                    break
                }
            } else {
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VoxtLog.info(
                    "Browser active-tab URL candidate returned empty/timed out. provider=\(providerName), candidate=\(index + 1), elapsedMs=\(elapsedMs)"
                )
            }
        }
        if let lastError {
            VoxtLog.info("Browser active-tab URL read failed. provider=\(providerName), error=\(lastError)")
        }
        return nil
    }

    private func runAppleScript(
        _ source: String,
        error: inout NSDictionary?,
        logFailure: Bool = true,
        timeout: TimeInterval? = nil
    ) -> String? {
        let wrappedSource: String
        if let timeout, timeout > 0 {
            let seconds = max(1, Int(ceil(timeout)))
            wrappedSource = """
            with timeout of \(seconds) seconds
            \(source)
            end timeout
            """
        } else {
            wrappedSource = source
        }

        guard let script = NSAppleScript(source: wrappedSource) else { return nil }
        guard let output = script.executeAndReturnError(&error).stringValue else {
            if logFailure, let error {
                VoxtLog.info("Browser active-tab URL read failed: \(error)")
            }
            return nil
        }
        return output
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        return runAppleScript(source, error: &error)
    }

    private func activeBrowserTabURLFromAccessibility(frontmostBundleID: String) -> String? {
        guard AXIsProcessTrusted() else {
            VoxtLog.info("Browser active-tab AX fallback unavailable: accessibility not trusted")
            return nil
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == frontmostBundleID
        else {
            VoxtLog.info("Browser active-tab AX fallback skipped: frontmost app changed")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )
        if focusedStatus == .success,
           let focusedWindow = focusedWindowValue {
            if let url = axDocumentURL(from: focusedWindow) {
                return url
            }
        } else {
            VoxtLog.info("Browser active-tab AX fallback focused window unavailable: status=\(focusedStatus.rawValue)")
        }

        var mainWindowValue: CFTypeRef?
        let mainStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXMainWindowAttribute as CFString,
            &mainWindowValue
        )
        if mainStatus == .success,
           let mainWindow = mainWindowValue {
            return axDocumentURL(from: mainWindow)
        }
        VoxtLog.info("Browser active-tab AX fallback main window unavailable: status=\(mainStatus.rawValue)")
        return nil
    }

    private func axDocumentURL(from windowRef: CFTypeRef) -> String? {
        guard CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let windowElement = unsafeBitCast(windowRef, to: AXUIElement.self)
        var documentValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            windowElement,
            kAXDocumentAttribute as CFString,
            &documentValue
        )
        guard status == .success, let documentValue else {
            VoxtLog.info("Browser active-tab AX fallback document attribute unavailable: status=\(status.rawValue)")
            return nil
        }
        return documentValue as? String
    }

    private func normalizedURLForMatching(_ rawURL: String?) -> String? {
        guard let rawURL else { return nil }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let components = URLComponents(string: withScheme), let host = components.host?.lowercased() {
            let path = components.path.isEmpty ? "/" : components.path.lowercased()
            return "\(host)\(path)"
        }
        return trimmed.lowercased()
    }

    private func wildcardMatches(pattern: String, candidate: String) -> Bool {
        let normalizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPattern.isEmpty else { return false }

        let escaped = NSRegularExpression.escapedPattern(for: normalizedPattern)
        let regexPattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else { return false }
        let range = NSRange(location: 0, length: (candidate as NSString).length)
        return regex.firstMatch(in: candidate.lowercased(), options: [], range: range) != nil
    }
}

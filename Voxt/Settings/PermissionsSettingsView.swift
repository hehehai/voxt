import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices
import Carbon
import UniformTypeIdentifiers
import Security

private func permissionsLocalized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct PermissionsSettingsView: View {
    let navigationRequest: SettingsNavigationRequest?

    private enum PermissionState: Equatable, Sendable {
        case enabled
        case disabled

        var titleKey: LocalizedStringKey {
            switch self {
            case .enabled: return "Enabled"
            case .disabled: return "Disabled"
            }
        }

        var tint: Color {
            switch self {
            case .enabled: return .green
            case .disabled: return .orange
            }
        }
    }

    private struct BrowserAutomationTarget: Identifiable, Hashable, Sendable {
        let bundleID: String
        let displayName: String
        let scripts: [String]
        let isCustom: Bool

        var id: String { bundleID }
    }

    private struct StoredCustomBrowser: Codable, Hashable, Sendable {
        let bundleID: String
        let displayName: String
    }

    private struct ScriptProbeResult: Sendable {
        let success: Bool
        let permissionDenied: Bool
        let appNotRunning: Bool
        let lastErrorCode: Int?
    }

    private struct BrowserTargetPreflight: Sendable {
        let appPath: String?
        let appNotFoundError: String?
        let isRunning: Bool
    }

    @State private var states: [SettingsPermissionKind: PermissionState] = [:]
    @State private var monitoringKinds: Set<SettingsPermissionKind> = []
    @State private var monitorTasks: [SettingsPermissionKind: Task<Void, Never>] = [:]

    @State private var browserTargets: [BrowserAutomationTarget] = []
    @State private var browserAutomationStates: [String: PermissionState] = [:]
    @State private var browserAutomationRequestsInFlight: Set<String> = []
    @State private var browserAutomationTestsInFlight: Set<String> = []
    @State private var browserAutomationRefreshTask: Task<Void, Never>?
    @State private var browserAutomationRequestTasks: [String: Task<Void, Never>] = [:]
    @State private var browserAutomationTestTasks: [String: Task<Void, Never>] = [:]
    @State private var browserPickerErrorMessage: String?
    @State private var permissionToastMessage = ""
    @State private var permissionToastDismissTask: Task<Void, Never>?

    @AppStorage(AppPreferenceKey.appEnhancementEnabled) private var appEnhancementEnabled = true
    @AppStorage(AppPreferenceKey.appBranchCustomBrowsers) private var appBranchCustomBrowsersJSON = "[]"
    @AppStorage(AppPreferenceKey.muteSystemAudioWhileRecording) private var muteSystemAudioWhileRecording = false
    @AppStorage(AppPreferenceKey.transcriptionEngine) private var transcriptionEngineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.featureSettings) private var featureSettingsRaw = ""

    private var transcriptionEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: transcriptionEngineRaw) ?? .mlxAudio
    }

    private var featureSettings: FeatureSettings {
        FeatureSettingsStore.load(defaults: .standard)
    }

    private var permissionRequirementContext: SettingsPermissionRequirementContext {
        SettingsPermissionRequirementResolver.requirementContext(
            selectedEngine: transcriptionEngine,
            muteSystemAudioWhileRecording: muteSystemAudioWhileRecording,
            featureSettings: featureSettings
        )
    }

    private var permissionKinds: [SettingsPermissionKind] {
        SettingsPermissionRequirementResolver.requiredPermissions(context: permissionRequirementContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PermissionsSettingsSection(
                title: "",
                description: ""
            ) {
                ForEach(permissionKinds) { kind in
                    permissionRow(kind)
                }
            }
            .settingsNavigationAnchor(.permissionsMain)

            if appEnhancementEnabled {
                Divider()

                PermissionsSettingsSection(
                    title: "",
                    description: ""
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(permissionsLocalized("App Branch Authorization"))
                                    .font(.headline)

                                Text(permissionsLocalized("Allow Voxt to read active browser URLs for app grouping."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                Button(permissionsLocalized("Add Browser")) {
                                    chooseBrowserApplication()
                                }
                                .buttonStyle(SettingsPillButtonStyle())

                                Button(permissionsLocalized("Open Settings")) {
                                    openBrowserAutomationSettings()
                                }
                                .buttonStyle(SettingsPillButtonStyle())
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }

                        ForEach(browserTargets) { target in
                            browserAuthorizationRow(target)
                        }

                        if let browserPickerErrorMessage {
                            Text(browserPickerErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .settingsNavigationAnchor(.permissionsAppBranchURLAuthorization)
            }
        }
        .onAppear {
            _ = AccessibilityPermissionManager.request(prompt: false)
            refreshStates()
            loadBrowserTargets()
            refreshBrowserAutomationStates()
        }
        .overlay(alignment: .top) {
            if !permissionToastMessage.isEmpty {
                ModelDebugToast(message: permissionToastMessage) {
                    dismissPermissionToast()
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: permissionToastMessage)
        .onChange(of: muteSystemAudioWhileRecording) { _, _ in
            refreshStates()
        }
        .onChange(of: transcriptionEngineRaw) { _, _ in
            refreshStates()
        }
        .onChange(of: featureSettingsRaw) { _, _ in
            refreshStates()
        }
        .onDisappear {
            stopAllMonitoring()
            cancelBrowserAutomationTasks()
            dismissPermissionToast()
        }
    }

    @ViewBuilder
    private func permissionRow(_ kind: SettingsPermissionKind) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.titleKey)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.92))
                Text(kind.descriptionKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                if monitoringKinds.contains(kind) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                }

                statusBadge(for: states[kind] ?? .disabled)

                Button(permissionsLocalized("Request")) {
                    requestPermission(kind)
                }
                .buttonStyle(SettingsCompactActionButtonStyle())

                Button(permissionsLocalized("Open Settings")) {
                    openSettings(for: kind)
                }
                .buttonStyle(SettingsCompactActionButtonStyle())
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func browserAuthorizationRow(_ target: BrowserAutomationTarget) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Text(target.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                if browserAutomationRequestsInFlight.contains(target.bundleID) || browserAutomationTestsInFlight.contains(target.bundleID) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                }

                statusBadge(for: browserAutomationStates[target.bundleID] ?? .disabled)

                Button(permissionsLocalized("Request")) {
                    requestBrowserAutomationPermission(target)
                }
                .buttonStyle(SettingsCompactActionButtonStyle())
                .disabled(isBrowserAutomationOperationInFlight)

                Button(permissionsLocalized("Test")) {
                    testBrowserURLRead(target)
                }
                .buttonStyle(SettingsCompactActionButtonStyle())
                .disabled(isBrowserAutomationOperationInFlight)

                if target.isCustom {
                    Button(permissionsLocalized("Delete"), role: .destructive) {
                        removeCustomBrowser(target)
                    }
                    .buttonStyle(SettingsCompactActionButtonStyle(tone: .destructive))
                    .disabled(isBrowserAutomationOperationInFlight)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var isBrowserAutomationOperationInFlight: Bool {
        !browserAutomationRequestsInFlight.isEmpty || !browserAutomationTestsInFlight.isEmpty
    }

    private func statusBadge(for state: PermissionState) -> some View {
        Text(state.titleKey)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(state.tint.opacity(0.16))
            )
            .foregroundStyle(state.tint)
    }

    private func refreshStates() {
        var snapshot: [SettingsPermissionKind: PermissionState] = [:]
        for kind in permissionKinds {
            snapshot[kind] = currentState(for: kind)
        }
        states = snapshot
        notifyPermissionStatusChanged()
        VoxtLog.info("Permission status: \(permissionSnapshotText(snapshot))")
    }

    private func currentState(for kind: SettingsPermissionKind) -> PermissionState {
        SettingsPermissionGrantResolver.isGranted(kind) ? .enabled : .disabled
    }

    private func requestPermission(_ kind: SettingsPermissionKind) {
        let initial = currentState(for: kind)
        states[kind] = initial
        VoxtLog.info("Permission request triggered: \(kind.logKey)=\(initial == .enabled ? "on" : "off")")
        startMonitoring(kind: kind, initialState: initial)

        switch kind {
        case .microphone:
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
        case .speechRecognition:
            SFSpeechRecognizer.requestAuthorization { _ in }
        case .accessibility:
            let granted = AccessibilityPermissionManager.request(prompt: true)
            if !granted {
                Task { @MainActor in
                    PermissionGuidance.openSettings(for: kind)
                }
            }
        case .inputMonitoring:
            let granted = EventListeningPermissionManager.requestInputMonitoring(prompt: true)
            if !granted {
                Task { @MainActor in
                    PermissionGuidance.openSettings(for: kind)
                }
            }
        case .systemAudioCapture:
            SystemAudioCapturePermission.requestAccess { granted in
                guard !granted else { return }
                Task { @MainActor in
                    PermissionGuidance.openSettings(for: kind)
                }
            }
        case .reminders:
            RemindersPermissionManager.requestAccess { _ in
                Task { @MainActor in
                    refreshStates()
                    let authorizationState = RemindersPermissionManager.authorizationState()
                    if authorizationState == .denied || authorizationState == .restricted {
                        PermissionGuidance.openSettings(for: kind)
                    }
                }
            }
        }
    }

    private func startMonitoring(kind: SettingsPermissionKind, initialState: PermissionState) {
        monitorTasks[kind]?.cancel()
        monitoringKinds.insert(kind)

        let task = Task { @MainActor in
            defer {
                monitorTasks[kind] = nil
                monitoringKinds.remove(kind)
            }

            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }

                let latest = currentState(for: kind)
                states[kind] = latest
                if latest != initialState {
                    notifyPermissionStatusChanged()
                    VoxtLog.info("Permission status changed: \(kind.logKey)=\(latest == .enabled ? "on" : "off")")
                    return
                }
            }
        }

        monitorTasks[kind] = task
    }

    private func stopAllMonitoring() {
        for task in monitorTasks.values {
            task.cancel()
        }
        monitorTasks.removeAll()
        monitoringKinds.removeAll()
    }

    private func notifyPermissionStatusChanged() {
        NotificationCenter.default.post(name: .voxtPermissionsDidChange, object: nil)
    }

    private func builtInBrowserTargets() -> [BrowserAutomationTarget] {
        [
            BrowserAutomationTarget(
                bundleID: "com.apple.Safari",
                displayName: "Safari",
                scripts: [
                    "tell application id \"com.apple.Safari\" to get URL of front document",
                    "tell application \"Safari\" to get URL of front document"
                ],
                isCustom: false
            ),
            BrowserAutomationTarget(
                bundleID: "com.google.Chrome",
                displayName: "Google Chrome",
                scripts: [
                    "tell application id \"com.google.Chrome\" to get the URL of active tab of front window",
                    "tell application \"Google Chrome\" to get the URL of active tab of front window"
                ],
                isCustom: false
            ),
            BrowserAutomationTarget(
                bundleID: "company.thebrowser.Browser",
                displayName: "Arc",
                scripts: [
                    "tell application id \"company.thebrowser.Browser\" to get the URL of active tab of front window",
                    "tell application \"Arc\" to get the URL of active tab of front window"
                ],
                isCustom: false
            )
        ]
    }

    private func scriptsForCustomBrowser(bundleID: String, displayName: String) -> [String] {
        BrowserAutomationScriptBuilder.customBrowserScripts(
            bundleID: bundleID,
            displayName: displayName
        )
    }

    private func loadBrowserTargets() {
        let builtIns = builtInBrowserTargets()
        let customBrowsers = loadStoredCustomBrowsers().map {
            BrowserAutomationTarget(
                bundleID: $0.bundleID,
                displayName: $0.displayName,
                scripts: scriptsForCustomBrowser(bundleID: $0.bundleID, displayName: $0.displayName),
                isCustom: true
            )
        }

        var seen: Set<String> = []
        var merged: [BrowserAutomationTarget] = []
        for target in builtIns + customBrowsers {
            guard !seen.contains(target.bundleID) else { continue }
            seen.insert(target.bundleID)
            merged.append(target)
        }

        browserTargets = merged
    }

    private func loadStoredCustomBrowsers() -> [StoredCustomBrowser] {
        guard let data = appBranchCustomBrowsersJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([StoredCustomBrowser].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveStoredCustomBrowsers(_ browsers: [StoredCustomBrowser]) {
        guard let data = try? JSONEncoder().encode(browsers),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        appBranchCustomBrowsersJSON = json
    }

    private func chooseBrowserApplication() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.applicationBundle]
        } else {
            panel.allowedFileTypes = ["app"]
        }
        panel.prompt = permissionsLocalized("Choose")

        guard panel.runModal() == .OK, let appURL = panel.url else { return }
        guard let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier,
              !bundleID.isEmpty else {
            browserPickerErrorMessage = AppLocalization.localizedString("Selected app is not a valid browser (missing bundle id).")
            return
        }

        if browserTargets.contains(where: { $0.bundleID == bundleID }) {
            browserPickerErrorMessage = AppLocalization.localizedString("Browser already added.")
            return
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
            ?? appURL.deletingPathExtension().lastPathComponent

        var custom = loadStoredCustomBrowsers()
        custom.append(StoredCustomBrowser(bundleID: bundleID, displayName: displayName))
        saveStoredCustomBrowsers(custom)
        browserPickerErrorMessage = nil
        loadBrowserTargets()
        refreshBrowserAutomationStates()
    }

    private func removeCustomBrowser(_ target: BrowserAutomationTarget) {
        guard target.isCustom else { return }
        var custom = loadStoredCustomBrowsers()
        custom.removeAll { $0.bundleID == target.bundleID }
        saveStoredCustomBrowsers(custom)
        browserAutomationStates.removeValue(forKey: target.bundleID)
        loadBrowserTargets()
        refreshBrowserAutomationStates()
    }

    private func refreshBrowserAutomationStates() {
        browserAutomationRefreshTask?.cancel()
        let targets = browserTargets
        browserAutomationRefreshTask = Task {
            let pairs = await Task.detached(priority: .userInitiated) {
                targets.map { target in
                    (target.bundleID, Self.nonPromptingBrowserAutomationState(target))
                }
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                for (bundleID, state) in pairs {
                    browserAutomationStates[bundleID] = state
                }
            }
        }
    }

    private func requestBrowserAutomationPermission(_ target: BrowserAutomationTarget) {
        guard !isBrowserAutomationOperationInFlight else { return }

        browserAutomationRequestsInFlight.insert(target.bundleID)

        let preflight = browserTargetPreflight(target)
        let task = Task {
            let result = await Task.detached(priority: .userInitiated) {
                if let integrityError = preflight.appNotFoundError
                    ?? Self.browserTargetSignatureIntegrityError(appPath: preflight.appPath) {
                    return BrowserAutomationRequestResult(
                        integrityError: integrityError,
                        enabled: false,
                        scriptProbe: nil
                    )
                }

                let status = Self.automationPermissionStatus(for: target.bundleID, askUserIfNeeded: true)
                let scriptProbe = preflight.isRunning
                    ? Self.runAppleScriptCandidates(target.scripts)
                    : ScriptProbeResult(success: false, permissionDenied: false, appNotRunning: true, lastErrorCode: nil)
                let enabled = scriptProbe.success || (status == noErr && !scriptProbe.permissionDenied)
                return BrowserAutomationRequestResult(
                    integrityError: nil,
                    enabled: enabled,
                    scriptProbe: scriptProbe
                )
            }.value

            await MainActor.run {
                guard !Task.isCancelled else { return }
                browserAutomationRequestTasks.removeValue(forKey: target.bundleID)
                browserAutomationRequestsInFlight.remove(target.bundleID)
                if let integrityError = result.integrityError {
                    browserAutomationStates[target.bundleID] = .disabled
                    showPermissionToast(integrityError, duration: 5.0)
                    return
                }

                guard let scriptProbe = result.scriptProbe else { return }
                browserAutomationStates[target.bundleID] = result.enabled ? .enabled : .disabled
                if result.enabled {
                    showPermissionToast(AppLocalization.localizedString("Authorization granted."))
                } else if scriptProbe.appNotRunning {
                    showPermissionToast(AppLocalization.localizedString("Open the browser and try again to complete the authorization check."))
                } else if scriptProbe.permissionDenied {
                    showPermissionToast(AppLocalization.localizedString("Authorization denied by macOS. Open Automation settings or reset Apple Events permission and try again."), duration: 4.0)
                } else {
                    showPermissionToast(AppLocalization.localizedString("Authorization not granted."))
                }
            }
        }
        browserAutomationRequestTasks[target.bundleID] = task
    }

    private struct BrowserAutomationRequestResult: Sendable {
        let integrityError: String?
        let enabled: Bool
        let scriptProbe: ScriptProbeResult?
    }

    private static func nonPromptingBrowserAutomationState(_ target: BrowserAutomationTarget) -> PermissionState {
        let status = automationPermissionStatus(for: target.bundleID, askUserIfNeeded: false)
        return status == noErr ? .enabled : .disabled
    }

    private static func automationPermissionStatus(for bundleID: String, askUserIfNeeded: Bool) -> OSStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let aeDesc = descriptor.aeDesc else {
            return OSStatus(errAEEventNotPermitted)
        }

        return AEDeterminePermissionToAutomateTarget(
            aeDesc,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )
    }

    private func testBrowserURLRead(_ target: BrowserAutomationTarget) {
        guard !isBrowserAutomationOperationInFlight else { return }

        browserAutomationTestsInFlight.insert(target.bundleID)

        let preflight = browserTargetPreflight(target)
        let task = Task {
            let result = await Task.detached(priority: .userInitiated) {
                if let integrityError = preflight.appNotFoundError
                    ?? Self.browserTargetSignatureIntegrityError(appPath: preflight.appPath) {
                    return BrowserAutomationTestResult(integrityError: integrityError, scriptProbe: nil)
                }
                return BrowserAutomationTestResult(
                    integrityError: nil,
                    scriptProbe: preflight.isRunning
                        ? Self.runAppleScriptCandidates(target.scripts)
                        : ScriptProbeResult(success: false, permissionDenied: false, appNotRunning: true, lastErrorCode: nil)
                )
            }.value

            await MainActor.run {
                guard !Task.isCancelled else { return }
                browserAutomationTestTasks.removeValue(forKey: target.bundleID)
                browserAutomationTestsInFlight.remove(target.bundleID)
                if let integrityError = result.integrityError {
                    browserAutomationStates[target.bundleID] = .disabled
                    showPermissionToast(integrityError, duration: 5.0)
                    return
                }

                guard let scriptProbe = result.scriptProbe else { return }
                if scriptProbe.success {
                    browserAutomationStates[target.bundleID] = .enabled
                    showPermissionToast(AppLocalization.localizedString("Browser URL read test succeeded."))
                    return
                }

                if scriptProbe.permissionDenied {
                    browserAutomationStates[target.bundleID] = .disabled
                    showPermissionToast(AppLocalization.localizedString("Browser URL read test failed: permission denied."))
                } else if scriptProbe.appNotRunning {
                    showPermissionToast(AppLocalization.localizedString("Browser URL read test failed: browser is not running."))
                } else if let lastErrorCode = scriptProbe.lastErrorCode {
                    showPermissionToast(AppLocalization.format("Browser URL read test failed (error: %@).", String(lastErrorCode)))
                } else {
                    showPermissionToast(AppLocalization.localizedString("Browser URL read test failed."))
                }
            }
        }
        browserAutomationTestTasks[target.bundleID] = task
    }

    private struct BrowserAutomationTestResult: Sendable {
        let integrityError: String?
        let scriptProbe: ScriptProbeResult?
    }

    private static func runAppleScriptCandidates(_ scripts: [String]) -> ScriptProbeResult {
        var sawPermissionDenied = false
        var sawAppNotRunning = false
        var lastErrorCode: Int?

        for source in scripts {
            var error: NSDictionary?
            let wrapped = """
            with timeout of 1 seconds
            \(source)
            end timeout
            """
            let script = NSAppleScript(source: wrapped)
            let result = script?.executeAndReturnError(&error)
            if let output = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return ScriptProbeResult(success: true, permissionDenied: false, appNotRunning: false, lastErrorCode: nil)
            }

            let code = error?[NSAppleScript.errorNumber] as? Int
            lastErrorCode = code
            if code == -1743 || code == -10004 {
                sawPermissionDenied = true
            }
            if code == -600 {
                sawAppNotRunning = true
            }
        }

        return ScriptProbeResult(
            success: false,
            permissionDenied: sawPermissionDenied,
            appNotRunning: sawAppNotRunning,
            lastErrorCode: lastErrorCode
        )
    }

    private func browserTargetPreflight(_ target: BrowserAutomationTarget) -> BrowserTargetPreflight {
        let appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID)?.path
        return BrowserTargetPreflight(
            appPath: appPath,
            appNotFoundError: appPath == nil
                ? AppLocalization.localizedString("Browser app could not be found. Reinstall or add the browser again.")
                : nil,
            isRunning: isApplicationRunning(bundleID: target.bundleID)
        )
    }

    private func isApplicationRunning(bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { !$0.isTerminated })
    }

    private static func browserTargetSignatureIntegrityError(appPath: String?) -> String? {
        guard let appPath else { return nil }

        var staticCode: SecStaticCode?
        let appURL = URL(fileURLWithPath: appPath)
        let createStatus = SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return AppLocalization.localizedString("Browser app signature could not be verified. Reinstall or update the browser, then request authorization again.")
        }

        let checkStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
        guard checkStatus == errSecSuccess else {
            return AppLocalization.localizedString("Browser app signature is invalid. Reinstall or update the browser, then request authorization again.")
        }

        return nil
    }

    private func cancelBrowserAutomationTasks() {
        browserAutomationRefreshTask?.cancel()
        browserAutomationRefreshTask = nil

        for task in browserAutomationRequestTasks.values {
            task.cancel()
        }
        browserAutomationRequestTasks.removeAll()
        browserAutomationRequestsInFlight.removeAll()

        for task in browserAutomationTestTasks.values {
            task.cancel()
        }
        browserAutomationTestTasks.removeAll()
        browserAutomationTestsInFlight.removeAll()
    }

    private func openSettings(for kind: SettingsPermissionKind) {
        PermissionGuidance.openSettings(for: kind)
    }

    private func openBrowserAutomationSettings() {
        PermissionGuidance.openBrowserAutomationSettings()
    }

    private func showPermissionToast(_ message: String, duration: TimeInterval = 2.4) {
        permissionToastDismissTask?.cancel()
        permissionToastMessage = message
        permissionToastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            permissionToastMessage = ""
        }
    }

    private func dismissPermissionToast() {
        permissionToastDismissTask?.cancel()
        permissionToastMessage = ""
    }

    private func permissionSnapshotText(_ snapshot: [SettingsPermissionKind: PermissionState]) -> String {
        permissionKinds
            .map { kind in
                let state = snapshot[kind] ?? .disabled
                return "\(kind.logKey)=\(state == .enabled ? "on" : "off")"
            }
            .joined(separator: ", ")
    }
}

private struct PermissionsSettingsSection<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty || !description.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.headline)
                    }

                    if !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

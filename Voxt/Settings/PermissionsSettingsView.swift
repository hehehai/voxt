import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices
import Carbon
import UniformTypeIdentifiers

struct PermissionsSettingsView: View {
    private enum PermissionKind: String, CaseIterable, Identifiable {
        case microphone
        case speechRecognition
        case accessibility
        case inputMonitoring

        var id: String { rawValue }

        var logKey: String {
            switch self {
            case .microphone: return "mic"
            case .speechRecognition: return "speech"
            case .accessibility: return "accessibility"
            case .inputMonitoring: return "inputMonitoring"
            }
        }

        var titleKey: LocalizedStringKey {
            switch self {
            case .microphone: return "Microphone Permission"
            case .speechRecognition: return "Speech Recognition Permission"
            case .accessibility: return "Accessibility Permission"
            case .inputMonitoring: return "Input Monitoring Permission"
            }
        }

        var descriptionKey: LocalizedStringKey {
            switch self {
            case .microphone:
                return "Required to capture audio for transcription."
            case .speechRecognition:
                return "Required for Apple Direct Dictation engine."
            case .accessibility:
                return "Required to paste transcription text into other apps."
            case .inputMonitoring:
                return "Required for reliable global modifier hotkeys (such as fn)."
            }
        }
    }

    private enum PermissionState: Equatable {
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

    private struct BrowserAutomationTarget: Identifiable, Hashable {
        let bundleID: String
        let displayName: String
        let scripts: [String]
        let isCustom: Bool

        var id: String { bundleID }
    }

    private struct StoredCustomBrowser: Codable, Hashable {
        let bundleID: String
        let displayName: String
    }

    private struct ScriptProbeResult {
        let success: Bool
        let permissionDenied: Bool
        let appNotRunning: Bool
        let lastErrorCode: Int?
    }

    @State private var states: [PermissionKind: PermissionState] = [:]
    @State private var monitoringKinds: Set<PermissionKind> = []
    @State private var monitorTasks: [PermissionKind: Task<Void, Never>] = [:]

    @State private var browserTargets: [BrowserAutomationTarget] = []
    @State private var browserAutomationStates: [String: PermissionState] = [:]
    @State private var browserAutomationRequestsInFlight: Set<String> = []
    @State private var browserAutomationTestsInFlight: Set<String> = []
    @State private var browserAutomationMessages: [String: String] = [:]
    @State private var browserPickerErrorMessage: String?

    @AppStorage(AppPreferenceKey.appEnhancementEnabled) private var appEnhancementEnabled = false
    @AppStorage(AppPreferenceKey.appBranchCustomBrowsers) private var appBranchCustomBrowsersJSON = "[]"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Permissions")
                        .font(.headline)

                    Text("Voxt needs the following permissions to support hotkeys, recording, and text insertion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(PermissionKind.allCases) { kind in
                        permissionRow(kind)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            if appEnhancementEnabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("App Branch URL Authorization")
                                .font(.headline)
                            Spacer()
                            Button("Add Browser") {
                                chooseBrowserApplication()
                            }
                            .controlSize(.small)
                            Button("Open Settings") {
                                openBrowserAutomationSettings()
                            }
                            .controlSize(.small)
                        }

                        Text("Grant browser automation permission so Voxt can read active-tab URLs for App Branch matching.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(browserTargets) { target in
                            browserAuthorizationRow(target)
                        }

                        if let browserPickerErrorMessage {
                            Text(browserPickerErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
        }
        .onAppear {
            refreshStates()
            loadBrowserTargets()
            refreshBrowserAutomationStates()
        }
        .onDisappear {
            stopAllMonitoring()
        }
    }

    @ViewBuilder
    private func permissionRow(_ kind: PermissionKind) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.titleKey)
                    .font(.subheadline)
                Text(kind.descriptionKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if monitoringKinds.contains(kind) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }

            statusBadge(for: states[kind] ?? .disabled)

            Button("Request") {
                requestPermission(kind)
            }
            .controlSize(.small)

            Button("Open Settings") {
                openSettings(for: kind)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func browserAuthorizationRow(_ target: BrowserAutomationTarget) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.displayName)
                    .font(.subheadline)
                Text(AppLocalization.format("Allow Voxt to read the active URL in %@.", target.displayName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let message = browserAutomationMessages[target.bundleID] {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if browserAutomationRequestsInFlight.contains(target.bundleID) || browserAutomationTestsInFlight.contains(target.bundleID) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }

            statusBadge(for: browserAutomationStates[target.bundleID] ?? .disabled)

            Button("Request") {
                requestBrowserAutomationPermission(target)
            }
            .controlSize(.small)

            Button("Test") {
                testBrowserURLRead(target)
            }
            .controlSize(.small)

            if target.isCustom {
                Button("Delete", role: .destructive) {
                    removeCustomBrowser(target)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
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
        var snapshot: [PermissionKind: PermissionState] = [:]
        for kind in PermissionKind.allCases {
            snapshot[kind] = currentState(for: kind)
        }
        states = snapshot
        VoxtLog.info("Permission status: \(permissionSnapshotText(snapshot))")
    }

    private func currentState(for kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .enabled : .disabled
        case .speechRecognition:
            return SFSpeechRecognizer.authorizationStatus() == .authorized ? .enabled : .disabled
        case .accessibility:
            return AXIsProcessTrusted() ? .enabled : .disabled
        case .inputMonitoring:
            if #available(macOS 10.15, *) {
                return CGPreflightListenEventAccess() ? .enabled : .disabled
            }
            return .enabled
        }
    }

    private func requestPermission(_ kind: PermissionKind) {
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
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            if #available(macOS 10.15, *) {
                _ = CGRequestListenEventAccess()
            }
        }
    }

    private func startMonitoring(kind: PermissionKind, initialState: PermissionState) {
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
        [
            "tell application id \"\(bundleID)\" to get URL of front document",
            "tell application id \"\(bundleID)\" to get URL of current tab of front window",
            "tell application id \"\(bundleID)\" to get the URL of active tab of front window",
            "tell application \"\(displayName)\" to get URL of front document"
        ]
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
        panel.prompt = String(localized: "Choose")

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
        browserAutomationMessages.removeValue(forKey: target.bundleID)
        loadBrowserTargets()
        refreshBrowserAutomationStates()
    }

    private func refreshBrowserAutomationStates() {
        for target in browserTargets {
            browserAutomationStates[target.bundleID] = probeBrowserAutomationState(target)
        }
    }

    private func requestBrowserAutomationPermission(_ target: BrowserAutomationTarget) {
        browserAutomationRequestsInFlight.insert(target.bundleID)
        VoxtLog.info("Browser automation permission request triggered: target=\(target.bundleID)")

        Task { @MainActor in
            defer { browserAutomationRequestsInFlight.remove(target.bundleID) }
            let status = automationPermissionStatus(for: target.bundleID, askUserIfNeeded: true)
            let enabled = (status == noErr)
            browserAutomationStates[target.bundleID] = enabled ? .enabled : .disabled
            if enabled {
                browserAutomationMessages[target.bundleID] = AppLocalization.localizedString("Authorization granted.")
            } else {
                browserAutomationMessages[target.bundleID] = AppLocalization.localizedString("Authorization not granted.")
            }
            VoxtLog.info(
                "Browser automation permission status: target=\(target.bundleID), state=\(enabled ? "enabled" : "disabled"), status=\(status)"
            )
        }
    }

    private func probeBrowserAutomationState(_ target: BrowserAutomationTarget) -> PermissionState {
        let status = automationPermissionStatus(for: target.bundleID, askUserIfNeeded: false)
        return status == noErr ? .enabled : .disabled
    }

    private func automationPermissionStatus(for bundleID: String, askUserIfNeeded: Bool) -> OSStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let aeDesc = descriptor.aeDesc else {
            return OSStatus(errAEEventNotPermitted)
        }

        return AEDeterminePermissionToAutomateTarget(
            aeDesc,
            AEEventClass(kCoreEventClass),
            AEEventID(kAEGetData),
            askUserIfNeeded
        )
    }

    private func testBrowserURLRead(_ target: BrowserAutomationTarget) {
        browserAutomationTestsInFlight.insert(target.bundleID)
        browserAutomationMessages[target.bundleID] = nil

        Task { @MainActor in
            defer { browserAutomationTestsInFlight.remove(target.bundleID) }
            let result = runAppleScriptCandidates(target.scripts)
            if result.success {
                browserAutomationStates[target.bundleID] = .enabled
                browserAutomationMessages[target.bundleID] = AppLocalization.localizedString("Browser URL read test succeeded.")
                return
            }

            if result.permissionDenied {
                browserAutomationStates[target.bundleID] = .disabled
                browserAutomationMessages[target.bundleID] = AppLocalization.localizedString("Browser URL read test failed: permission denied.")
            } else if result.appNotRunning {
                browserAutomationMessages[target.bundleID] = AppLocalization.localizedString("Browser URL read test failed: browser is not running.")
            } else if let lastErrorCode = result.lastErrorCode {
                browserAutomationMessages[target.bundleID] = AppLocalization.format("Browser URL read test failed (error: %@).", String(lastErrorCode))
            } else {
                browserAutomationMessages[target.bundleID] = AppLocalization.localizedString("Browser URL read test failed.")
            }
        }
    }

    private func runAppleScriptCandidates(_ scripts: [String]) -> ScriptProbeResult {
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

    private func openSettings(for kind: PermissionKind) {
        let urlString: String
        switch kind {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openBrowserAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func permissionSnapshotText(_ snapshot: [PermissionKind: PermissionState]) -> String {
        PermissionKind.allCases
            .map { kind in
                let state = snapshot[kind] ?? .disabled
                return "\(kind.logKey)=\(state == .enabled ? "on" : "off")"
            }
            .joined(separator: ", ")
    }
}

import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices
import Carbon

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

    private enum BrowserAutomationTarget: String, CaseIterable, Identifiable {
        case chrome = "com.google.Chrome"
        case safari = "com.apple.Safari"
        case arc = "company.thebrowser.Browser"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chrome: return "Google Chrome"
            case .safari: return "Safari"
            case .arc: return "Arc"
            }
        }

        var probeScript: String {
            switch self {
            case .chrome:
                return "tell application id \"com.google.Chrome\" to get the URL of active tab of front window"
            case .safari:
                return "tell application id \"com.apple.Safari\" to get URL of front document"
            case .arc:
                return "tell application id \"company.thebrowser.Browser\" to get the URL of active tab of front window"
            }
        }
    }

    @State private var states: [PermissionKind: PermissionState] = [:]
    @State private var monitoringKinds: Set<PermissionKind> = []
    @State private var monitorTasks: [PermissionKind: Task<Void, Never>] = [:]
    @State private var browserAutomationStates: [BrowserAutomationTarget: PermissionState] = [:]
    @State private var browserAutomationRequestsInFlight: Set<BrowserAutomationTarget> = []
    @AppStorage(AppPreferenceKey.appEnhancementEnabled) private var appEnhancementEnabled = false

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
                        Text("App Branch URL Authorization")
                            .font(.headline)

                        Text("Grant browser automation permission so Voxt can read active-tab URLs for App Branch matching.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(BrowserAutomationTarget.allCases) { target in
                            browserAuthorizationRow(target)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
        }
        .onAppear {
            refreshStates()
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
                Text(target.title)
                    .font(.subheadline)
                Text("Allow Voxt to read the active URL in \(target.title).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if browserAutomationRequestsInFlight.contains(target) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }

            statusBadge(for: browserAutomationStates[target] ?? .disabled)

            Button("Request") {
                requestBrowserAutomationPermission(target)
            }
            .controlSize(.small)

            Button("Open Settings") {
                openBrowserAutomationSettings()
            }
            .controlSize(.small)
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

    private func refreshBrowserAutomationStates() {
        for target in BrowserAutomationTarget.allCases {
            browserAutomationStates[target] = probeBrowserAutomationState(target)
        }
    }

    private func requestBrowserAutomationPermission(_ target: BrowserAutomationTarget) {
        browserAutomationRequestsInFlight.insert(target)
        VoxtLog.info("Browser automation permission request triggered: target=\(target.rawValue)")

        Task { @MainActor in
            defer { browserAutomationRequestsInFlight.remove(target) }
            let status = automationPermissionStatus(for: target, askUserIfNeeded: true)
            let result: PermissionState = (status == noErr) ? .enabled : .disabled
            browserAutomationStates[target] = result == .enabled ? .enabled : .disabled
            VoxtLog.info(
                "Browser automation permission status: target=\(target.rawValue), state=\(result == .enabled ? "enabled" : "disabled"), status=\(status)"
            )
        }
    }

    private func probeBrowserAutomationState(_ target: BrowserAutomationTarget) -> PermissionState {
        let status = automationPermissionStatus(for: target, askUserIfNeeded: false)
        return status == noErr ? .enabled : .disabled
    }

    private func automationPermissionStatus(for target: BrowserAutomationTarget, askUserIfNeeded: Bool) -> OSStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: target.rawValue)
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

    private func runAppleScript(_ source: String, promptIfNeeded: Bool = true) -> PermissionState {
        let scriptSource: String
        if promptIfNeeded {
            scriptSource = source
        } else {
            scriptSource = """
            with timeout of 1 seconds
            \(source)
            end timeout
            """
        }

        var error: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        _ = script?.executeAndReturnError(&error).stringValue
        guard let error else { return .enabled }

        let errorNumber = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        if errorNumber == -1743 || errorNumber == -10004 {
            return .disabled
        }
        if errorNumber == -600 {
            // App not running does not imply permission denied; keep current as disabled until requested.
            return .disabled
        }
        return .disabled
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

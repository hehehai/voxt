import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices

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

    @State private var states: [PermissionKind: PermissionState] = [:]
    @State private var monitoringKinds: Set<PermissionKind> = []
    @State private var monitorTasks: [PermissionKind: Task<Void, Never>] = [:]

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
        }
        .onAppear {
            refreshStates()
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

    private func permissionSnapshotText(_ snapshot: [PermissionKind: PermissionState]) -> String {
        PermissionKind.allCases
            .map { kind in
                let state = snapshot[kind] ?? .disabled
                return "\(kind.logKey)=\(state == .enabled ? "on" : "off")"
            }
            .joined(separator: ", ")
    }
}

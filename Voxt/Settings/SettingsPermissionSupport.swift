import SwiftUI
import AVFoundation
import Speech

enum SettingsPermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case speechRecognition
    case accessibility
    case inputMonitoring
    case systemAudioCapture

    var id: String { rawValue }

    var logKey: String {
        switch self {
        case .microphone: return "mic"
        case .speechRecognition: return "speech"
        case .accessibility: return "accessibility"
        case .inputMonitoring: return "inputMonitoring"
        case .systemAudioCapture: return "systemAudioCapture"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .microphone: return "Microphone Permission"
        case .speechRecognition: return "Speech Recognition Permission"
        case .accessibility: return "Accessibility Permission"
        case .inputMonitoring: return "Input Monitoring Permission"
        case .systemAudioCapture: return "System Audio Recording Permission"
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
        case .systemAudioCapture:
            return "Required for Meeting Notes and for muting other apps' media audio during recording."
        }
    }
}

struct SettingsPermissionRequirementContext {
    let selectedEngine: TranscriptionEngine
    let muteSystemAudioWhileRecording: Bool
    let meetingNotesEnabled: Bool
    let featureSettings: FeatureSettings?
}

enum SettingsPermissionRequirementResolver {
    static func requiredPermissions(
        context: SettingsPermissionRequirementContext
    ) -> [SettingsPermissionKind] {
        var permissions: [SettingsPermissionKind] = [
            .microphone,
            .accessibility,
            .inputMonitoring
        ]

        let featureSelections = [
            context.featureSettings?.transcription.asrSelectionID.asrSelection,
            context.featureSettings?.translation.asrSelectionID.asrSelection,
            context.featureSettings?.rewrite.asrSelectionID.asrSelection,
            context.featureSettings?.meeting.enabled == true ? context.featureSettings?.meeting.asrSelectionID.asrSelection : nil
        ]

        let needsSpeechRecognition = context.selectedEngine == .dictation || featureSelections.contains { selection in
            if case .dictation = selection {
                return true
            }
            return false
        }

        if needsSpeechRecognition {
            permissions.append(.speechRecognition)
        }

        if context.muteSystemAudioWhileRecording || context.meetingNotesEnabled || context.featureSettings?.meeting.enabled == true {
            permissions.append(.systemAudioCapture)
        }

        return permissions
    }
}

enum SettingsPermissionGrantResolver {
    static func isGranted(_ permission: SettingsPermissionKind) -> Bool {
        switch permission {
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .speechRecognition:
            return SFSpeechRecognizer.authorizationStatus() == .authorized
        case .accessibility:
            return AccessibilityPermissionManager.isTrusted()
        case .inputMonitoring:
            return EventListeningPermissionManager.isInputMonitoringGranted()
        case .systemAudioCapture:
            return SystemAudioCapturePermission.authorizationStatus() == .authorized
        }
    }
}

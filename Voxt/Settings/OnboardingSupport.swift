import SwiftUI
import Foundation
import AVFoundation
import Speech
import ApplicationServices

enum OnboardingModelPathChoice: String, CaseIterable, Identifiable {
    case local
    case remote
    case dictation

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .local:
            return "Local"
        case .remote:
            return "Remote"
        case .dictation:
            return "Direct Dictation"
        }
    }
}

enum OnboardingContextualPermission: Hashable {
    case microphone
    case speechRecognition
    case accessibility
    case inputMonitoring
    case systemAudioCapture
}

struct OnboardingPermissionRequirementContext {
    let selectedEngine: TranscriptionEngine
    let muteSystemAudioWhileRecording: Bool
    let meetingNotesEnabled: Bool
}

enum OnboardingPermissionRequirementResolver {
    static func requiredPermissions(
        for step: OnboardingStep,
        context: OnboardingPermissionRequirementContext
    ) -> [OnboardingContextualPermission] {
        switch step {
        case .transcription:
            var permissions: [OnboardingContextualPermission] = [
                .microphone,
                .accessibility,
                .inputMonitoring
            ]
            if context.selectedEngine == .dictation {
                permissions.append(.speechRecognition)
            }
            if context.muteSystemAudioWhileRecording {
                permissions.append(.systemAudioCapture)
            }
            return permissions
        case .meeting:
            guard context.meetingNotesEnabled else { return [] }
            return [
                .microphone,
                .accessibility,
                .inputMonitoring,
                .systemAudioCapture
            ]
        case .language, .model, .translation, .rewrite, .appEnhancement, .finish:
            return []
        }
    }
}

enum OnboardingPermissionGrantResolver {
    static func isGranted(_ permission: OnboardingContextualPermission) -> Bool {
        switch permission {
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .speechRecognition:
            return SFSpeechRecognizer.authorizationStatus() == .authorized
        case .accessibility:
            return AccessibilityPermissionManager.isTrusted()
        case .inputMonitoring:
            if #available(macOS 10.15, *) {
                return CGPreflightListenEventAccess()
            }
            return true
        case .systemAudioCapture:
            return SystemAudioCapturePermission.authorizationStatus() == .authorized
        }
    }
}

enum OnboardingRewriteTest {
    static let defaultPrompt = String(localized: "Make this shorter and more polite.")
    static let defaultSourceText = String(localized: "Hi team, I wanted to follow up about tomorrow's launch. We are still waiting on the final banner image, so please send it over before 3 PM if possible. Thanks.")
}

enum OnboardingTranslationTest {
    static let defaultInput = String(localized: "Thanks for joining the call. I'll send the updated timeline and action items after lunch.")
}

enum OnboardingVideoDemo {
    static let appEnhancementURL = URL(string: "https://storage.actnow.dev/common/voxt/voxt-app-branch-demo.mp4")!
    static let meetingURL = URL(string: "https://storage.actnow.dev/common/voxt/voxt-meeting-record-demo.mp4")!
}

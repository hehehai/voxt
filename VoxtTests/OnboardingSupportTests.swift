import XCTest
@testable import Voxt

final class OnboardingSupportTests: XCTestCase {
    func testTranscriptionPermissionsIncludeSpeechRecognitionForDictation() {
        let permissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .transcription,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .dictation,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .speechRecognition]
        )
    }

    func testTranscriptionPermissionsIncludeSystemAudioWhenMuteEnabled() {
        let permissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .transcription,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .mlxAudio,
                muteSystemAudioWhileRecording: true,
                meetingNotesEnabled: false
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }

    func testMeetingPermissionsOnlyAppearWhenMeetingModeEnabled() {
        let disabledPermissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .meeting,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false
            )
        )
        let enabledPermissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .meeting,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: true
            )
        )

        XCTAssertTrue(disabledPermissions.isEmpty)
        XCTAssertEqual(
            enabledPermissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }

    func testNonRecordingStepsDoNotRequirePermissions() {
        let context = OnboardingPermissionRequirementContext(
            selectedEngine: .mlxAudio,
            muteSystemAudioWhileRecording: true,
            meetingNotesEnabled: true
        )

        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .language, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .model, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .translation, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .rewrite, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .appEnhancement, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .finish, context: context).isEmpty)
    }
}

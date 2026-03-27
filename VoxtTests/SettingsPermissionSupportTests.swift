import XCTest
@testable import Voxt

final class SettingsPermissionSupportTests: XCTestCase {
    func testRequiredPermissionsDoNotIncludeConditionalItemsWhenFeaturesAreDisabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .mlxAudio,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring]
        )
    }

    func testRequiredPermissionsIncludeSpeechRecognitionForDictation() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
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

    func testRequiredPermissionsIncludeSystemAudioWhenMeetingNotesAreEnabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: true
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }
}

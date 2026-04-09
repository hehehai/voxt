import XCTest
@testable import Voxt

final class SettingsPermissionSupportTests: XCTestCase {
    func testRequiredPermissionsDoNotIncludeConditionalItemsWhenFeaturesAreDisabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .mlxAudio,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false,
                featureSettings: nil
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
                meetingNotesEnabled: false,
                featureSettings: nil
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
                meetingNotesEnabled: true,
                featureSettings: nil
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }

    func testRequiredPermissionsDoNotIncludeSystemAudioWhenMeetingFeatureIsDisabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false,
                featureSettings: FeatureSettings(
                    transcription: .init(
                        asrSelectionID: .mlx(MLXModelManager.defaultModelRepo),
                        llmEnabled: false,
                        llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                        prompt: AppPreferenceKey.defaultEnhancementPrompt
                    ),
                    translation: .init(
                        asrSelectionID: .mlx(MLXModelManager.defaultModelRepo),
                        modelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                        targetLanguageRawValue: TranslationTargetLanguage.english.rawValue,
                        prompt: AppPreferenceKey.defaultTranslationPrompt,
                        replaceSelectedText: true
                    ),
                    rewrite: .init(
                        asrSelectionID: .mlx(MLXModelManager.defaultModelRepo),
                        llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                        prompt: AppPreferenceKey.defaultRewritePrompt,
                        appEnhancementEnabled: false
                    ),
                    meeting: .init(
                        enabled: false,
                        asrSelectionID: .remoteASR(.doubaoASR),
                        summaryModelSelectionID: .remoteLLM(.openAI),
                        summaryPrompt: AppPreferenceKey.defaultMeetingSummaryPrompt,
                        summaryAutoGenerate: true,
                        realtimeTranslateEnabled: false,
                        realtimeTargetLanguageRawValue: "",
                        showOverlayInScreenShare: false
                    )
                )
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring]
        )
    }
}

import XCTest
@testable import Voxt

final class SettingsPermissionSupportTests: XCTestCase {
    private func makeFeatureSettings(
        transcriptionASR: FeatureModelSelectionID = .mlx(MLXModelManager.defaultModelRepo),
        translationASR: FeatureModelSelectionID = .mlx(MLXModelManager.defaultModelRepo),
        rewriteASR: FeatureModelSelectionID = .mlx(MLXModelManager.defaultModelRepo),
        remindersEnabled: Bool = false
    ) -> FeatureSettings {
        FeatureSettings(
            transcription: .init(
                asrSelectionID: transcriptionASR,
                llmEnabled: false,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultEnhancementPrompt,
                notes: .init(
                    enabled: false,
                    titleModelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                    remindersSync: .init(enabled: remindersEnabled)
                )
            ),
            translation: .init(
                asrSelectionID: translationASR,
                modelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                targetLanguageRawValue: TranslationTargetLanguage.english.rawValue,
                prompt: AppPreferenceKey.defaultTranslationPrompt,
                replaceSelectedText: true
            ),
            rewrite: .init(
                asrSelectionID: rewriteASR,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultRewritePrompt,
                appEnhancementEnabled: false
            )
        )
    }

    func testSidebarRequirementContextPreservesFeatureSettingsSelections() {
        let settings = makeFeatureSettings(remindersEnabled: true)
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: settings
        )

        XCTAssertEqual(context.selectedEngine, .remote)
        XCTAssertFalse(context.muteSystemAudioWhileRecording)
        XCTAssertEqual(context.featureSettings?.translation.asrSelectionID, settings.translation.asrSelectionID)
        XCTAssertTrue(context.featureSettings?.transcription.notes.remindersSync.enabled == true)
    }

    func testSidebarPermissionsExcludeSystemAudioWhenMuteIsDisabled() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings()
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(permissions, [.microphone, .accessibility, .inputMonitoring])
    }

    func testSidebarPermissionsIncludeSystemAudioWhenMuteDuringRecordingIsEnabled() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: true,
            featureSettings: makeFeatureSettings()
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(permissions, [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture])
    }

    func testSidebarPermissionsIncludeSpeechRecognitionWhenFeatureUsesDictation() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings(
                transcriptionASR: .dictation
            )
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .speechRecognition]
        )
    }

    func testSidebarPermissionsIncludeRemindersWhenTranscriptionNotesSyncReminders() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings(remindersEnabled: true)
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .reminders]
        )
    }

    func testRequiredPermissionsDoNotIncludeConditionalItemsWhenFeaturesAreDisabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .mlxAudio,
                muteSystemAudioWhileRecording: false,
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
                featureSettings: nil
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .speechRecognition]
        )
    }

    func testRequiredPermissionsIncludeSystemAudioWhenMuteDuringRecordingIsEnabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: true,
                featureSettings: nil
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }

    func testRequiredPermissionsIncludeRemindersWhenFeatureSettingsNeedIt() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: false,
                featureSettings: makeFeatureSettings(remindersEnabled: true)
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .reminders]
        )
    }
}

// SettingsPermissionSupportTests.swift
// Provides Settings Permission Support Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class SettingsPermissionSupportTests: XCTestCase {
    private func makeFeatureSettings(
        transcriptionASR: FeatureModelSelectionID = .mlx(MLXModelManager.defaultModelRepo),
        translationASR: FeatureModelSelectionID = .mlx(MLXModelManager.defaultModelRepo),
        rewriteASR: FeatureModelSelectionID = .mlx(MLXModelManager.defaultModelRepo),
        screenshotContextEnabled: Bool = false,
        notesEnabled: Bool = true,
        remindersEnabled: Bool = false
    ) -> FeatureSettings {
        FeatureSettings(
            transcription: .init(
                asrSelectionID: transcriptionASR,
                llmEnabled: false,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultEnhancementPrompt,
                notes: .init(
                    enabled: notesEnabled,
                    titleModelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                    remindersSync: .init(enabled: remindersEnabled)
                )
            ),
            translation: .init(
                asrSelectionID: translationASR,
                modelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                targetLanguageRawValue: TranslationTargetLanguage.english.rawValue,
                prompt: AppPreferenceKey.defaultTranslationPrompt
            ),
            rewrite: .init(
                asrSelectionID: rewriteASR,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultRewritePrompt,
                appContext: .init(
                    textEnabled: false,
                    screenshotEnabled: screenshotContextEnabled
                ),
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

    func testSidebarPermissionsIncludeSystemAudioForMeetingModeByDefault() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings()
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(permissions, [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring])
    }

    func testSidebarPermissionsIncludeSystemAudioWhenMuteDuringRecordingIsEnabled() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: true,
            featureSettings: makeFeatureSettings()
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(permissions, [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring])
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
            [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring, .speechRecognition]
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
            [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring, .reminders]
        )
    }

    func testSidebarPermissionsSkipRemindersWhenNotesFeatureDisabled() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings(notesEnabled: false, remindersEnabled: true)
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(
            permissions,
            [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring]
        )
    }

    func testSidebarPermissionsIncludeScreenCaptureWhenRewriteScreenshotContextIsEnabled() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings(screenshotContextEnabled: true)
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(
            permissions,
            [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring, .screenCapture]
        )
    }

    func testRequiredPermissionsIncludeBaselineCapturePermissionsWhenFeaturesAreDisabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .mlxAudio,
                muteSystemAudioWhileRecording: false,
                featureSettings: nil
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring]
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
            [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring, .speechRecognition]
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
            [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring]
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
            [.microphone, .systemAudioCapture, .accessibility, .inputMonitoring, .reminders]
        )
    }
}

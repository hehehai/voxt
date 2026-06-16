// FeatureSettingsStoreTests.swift
// Provides Feature Settings Store Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class FeatureSettingsStoreTests: XCTestCase {
    private func withEphemeralDefaults(
        _ body: (UserDefaults) throws -> Void
    ) rethrows {
        let suiteName = "FeatureSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected ephemeral UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        try body(defaults)
    }

    func testMigrateIfNeededRemovesObsoleteLatencyProfileKeys() throws {
        try withEphemeralDefaults { defaults in
            defaults.set("instant", forKey: "enhancementLatencyProfile")
            defaults.set("quality", forKey: "translationLatencyProfile")
            defaults.set("balanced", forKey: "rewriteLatencyProfile")

            FeatureSettingsStore.migrateIfNeeded(defaults: defaults)

            XCTAssertNil(defaults.object(forKey: "enhancementLatencyProfile"))
            XCTAssertNil(defaults.object(forKey: "translationLatencyProfile"))
            XCTAssertNil(defaults.object(forKey: "rewriteLatencyProfile"))
            XCTAssertNotNil(defaults.string(forKey: AppPreferenceKey.featureSettings))
        }
    }

    func testLoadRemovesObsoleteLatencyProfileKeysAndDerivesSettings() throws {
        try withEphemeralDefaults { defaults in
            defaults.set("quality", forKey: "enhancementLatencyProfile")
            defaults.set(EnhancementMode.customLLM.rawValue, forKey: AppPreferenceKey.enhancementMode)
            defaults.set("mlx-community/Qwen3.5-2B-4bit", forKey: AppPreferenceKey.customLLMModelRepo)

            let settings = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertNil(defaults.object(forKey: "enhancementLatencyProfile"))
            XCTAssertTrue(settings.transcription.llmEnabled)
            XCTAssertEqual(
                settings.transcription.llmSelectionID,
                .localLLM("mlx-community/Qwen3.5-2B-4bit")
            )
        }
    }

    func testSaveRemovesObsoleteLatencyProfileKeysWithoutAffectingStoredSettings() throws {
        try withEphemeralDefaults { defaults in
            defaults.set("instant", forKey: "enhancementLatencyProfile")
            defaults.set("balanced", forKey: "translationLatencyProfile")
            defaults.set("quality", forKey: "rewriteLatencyProfile")

            var settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)
            settings.meeting.summaryModelSelectionID = .localLLM(CustomLLMModelManager.defaultModelRepo)
            settings.meeting.summaryPrompt = AppPromptDefaults.resolvedStoredText(
                "",
                kind: .transcriptSummary,
                defaults: defaults
            )
            FeatureSettingsStore.save(settings, defaults: defaults)
            let reloaded = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertNil(defaults.object(forKey: "enhancementLatencyProfile"))
            XCTAssertNil(defaults.object(forKey: "translationLatencyProfile"))
            XCTAssertNil(defaults.object(forKey: "rewriteLatencyProfile"))
            XCTAssertEqual(reloaded, settings)
        }
    }

    func testSaveKeepsAppEnhancementEnabledForMenuVisibility() throws {
        try withEphemeralDefaults { defaults in
            var settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)
            settings.rewrite.appEnhancementEnabled = true

            FeatureSettingsStore.save(settings, defaults: defaults)

            XCTAssertTrue(defaults.bool(forKey: AppPreferenceKey.appEnhancementEnabled))

            settings.rewrite.appEnhancementEnabled = false
            FeatureSettingsStore.save(settings, defaults: defaults)
            let reloaded = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertTrue(defaults.bool(forKey: AppPreferenceKey.appEnhancementEnabled))
            XCTAssertTrue(reloaded.rewrite.appEnhancementEnabled)
        }
    }

    func testPromptSpecificSaveHelpersPersistLatestPromptText() throws {
        try withEphemeralDefaults { defaults in
            let transcriptionPrompt = "Clean this transcript, keep it compact."
            let translationPrompt = "Translate into {{TARGET_LANGUAGE}} and keep product names in English."
            let rewritePrompt = "Rewrite the text to sound polite and concise."

            FeatureSettingsStore.saveTranscriptionPrompt(transcriptionPrompt, defaults: defaults)
            FeatureSettingsStore.saveTranslationPrompt(translationPrompt, defaults: defaults)
            FeatureSettingsStore.saveRewritePrompt(rewritePrompt, defaults: defaults)

            let reloaded = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertEqual(reloaded.transcription.prompt, transcriptionPrompt)
            XCTAssertEqual(reloaded.translation.prompt, translationPrompt)
            XCTAssertEqual(reloaded.rewrite.prompt, rewritePrompt)
            XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.enhancementSystemPrompt), transcriptionPrompt)
            XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.translationSystemPrompt), translationPrompt)
            XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.rewriteSystemPrompt), rewritePrompt)
        }
    }

    func testSaveSyncsLegacyPromptKeysFromFeatureSettingsPayload() throws {
        try withEphemeralDefaults { defaults in
            var settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)
            settings.transcription.prompt = "Enhance with my custom cleanup rules."
            settings.translation.prompt = "Translate to {{TARGET_LANGUAGE}} and preserve app names."
            settings.rewrite.prompt = "Rewrite as concise release notes."

            FeatureSettingsStore.save(settings, defaults: defaults)

            XCTAssertEqual(
                defaults.string(forKey: AppPreferenceKey.enhancementSystemPrompt),
                "Enhance with my custom cleanup rules."
            )
            XCTAssertEqual(
                defaults.string(forKey: AppPreferenceKey.translationSystemPrompt),
                "Translate to {{TARGET_LANGUAGE}} and preserve app names."
            )
            XCTAssertEqual(
                defaults.string(forKey: AppPreferenceKey.rewriteSystemPrompt),
                "Rewrite as concise release notes."
            )
        }
    }

    func testLoadDefaultsRewriteAppContextToDisabled() throws {
        try withEphemeralDefaults { defaults in
            let settings = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertFalse(settings.rewrite.appContext.enabled)
            XCTAssertFalse(settings.rewrite.appContext.textEnabled)
            XCTAssertFalse(settings.rewrite.appContext.screenshotEnabled)
        }
    }

    func testSavePersistsRewriteAppContextSubsettings() throws {
        try withEphemeralDefaults { defaults in
            var settings = FeatureSettingsStore.load(defaults: defaults)
            settings.rewrite.appContext.textEnabled = true
            settings.rewrite.appContext.screenshotEnabled = false

            FeatureSettingsStore.save(settings, defaults: defaults)
            let reloaded = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertTrue(reloaded.rewrite.appContext.enabled)
            XCTAssertTrue(reloaded.rewrite.appContext.textEnabled)
            XCTAssertFalse(reloaded.rewrite.appContext.screenshotEnabled)
        }
    }

    func testLoadDoesNotBackfillRewriteAppContextFromTranscriptionSettings() throws {
        try withEphemeralDefaults { defaults in
            var settings = FeatureSettingsStore.load(defaults: defaults)
            settings.transcription.appContext.enabled = true
            settings.rewrite.appContext.enabled = false

            FeatureSettingsStore.save(settings, defaults: defaults)
            let reloaded = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertFalse(reloaded.rewrite.appContext.enabled)
            XCTAssertFalse(reloaded.rewrite.appContext.textEnabled)
            XCTAssertFalse(reloaded.rewrite.appContext.screenshotEnabled)
        }
    }

    func testAppContextSettingsEnableToggleTurnsOnBothSubsettings() {
        var settings = TranscriptionAppContextSettings()

        settings.enabled = true

        XCTAssertTrue(settings.textEnabled)
        XCTAssertTrue(settings.screenshotEnabled)
        XCTAssertTrue(settings.enabled)
    }

    func testAppContextSettingsDisableWhenBothSubsettingsAreOff() {
        var settings = TranscriptionAppContextSettings(
            textEnabled: true,
            screenshotEnabled: true
        )

        settings.textEnabled = false
        settings.screenshotEnabled = false

        XCTAssertFalse(settings.enabled)
    }

    func testMeetingChunkingModeDefaultsAndSyncsToRuntimePreference() throws {
        try withEphemeralDefaults { defaults in
            XCTAssertEqual(MeetingChunkingMode.stored(in: defaults), .quality)
            XCTAssertEqual(MeetingDiarizationMode.stored(in: defaults), .offlineVBx)

            defaults.set(MeetingChunkingMode.quality.rawValue, forKey: AppPreferenceKey.meetingChunkingMode)
            defaults.set(MeetingDiarizationMode.sortformerV2.rawValue, forKey: AppPreferenceKey.meetingRealtimeDiarizationMode)
            defaults.set("fireRed", forKey: "meetingVADMode")
            defaults.set("responsive", forKey: "meetingSileroVADSensitivity")
            defaults.set("stable", forKey: "meetingServerVADMode")
            defaults.set("sensitive", forKey: "meetingSpeakerDiarizationSensitivity")
            defaults.set("maxThree", forKey: "meetingSpeakerCountHint")
            defaults.set(true, forKey: "meetingSpeakerDiarizationDebugEnabled")
            defaults.set(false, forKey: AppPreferenceKey.meetingFinalTranscriptOptimizationEnabled)

            var settings = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertEqual(settings.meeting.chunkingMode, .quality)
            XCTAssertEqual(settings.meeting.speakerDiarizationModel, .offlineVBx)
            XCTAssertFalse(settings.meeting.finalTranscriptOptimizationEnabled)

            settings.meeting.chunkingModeRawValue = MeetingChunkingMode.realtime.rawValue
            settings.meeting.speakerDiarizationModelRawValue = MeetingDiarizationMode.offlineVBx.rawValue
            settings.meeting.finalTranscriptOptimizationEnabled = false
            FeatureSettingsStore.save(settings, defaults: defaults)
            FeatureSettingsStore.prepareMeetingRuntime(from: settings, defaults: defaults)

            XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.meetingChunkingMode), MeetingChunkingMode.realtime.rawValue)
            XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.meetingSpeakerDiarizationModel), MeetingDiarizationMode.offlineVBx.rawValue)
            XCTAssertEqual(defaults.string(forKey: "meetingVADMode"), "fireRed")
            XCTAssertEqual(defaults.string(forKey: "meetingSileroVADSensitivity"), "responsive")
            XCTAssertEqual(defaults.string(forKey: "meetingServerVADMode"), "stable")
            XCTAssertEqual(defaults.string(forKey: "meetingSpeakerDiarizationSensitivity"), "sensitive")
            XCTAssertEqual(defaults.string(forKey: "meetingSpeakerCountHint"), "maxThree")
            XCTAssertTrue(defaults.bool(forKey: "meetingSpeakerDiarizationDebugEnabled"))
            XCTAssertFalse(defaults.bool(forKey: AppPreferenceKey.meetingFinalTranscriptOptimizationEnabled))
            XCTAssertEqual(FeatureSettingsStore.load(defaults: defaults).meeting.chunkingMode, .realtime)
            XCTAssertEqual(FeatureSettingsStore.load(defaults: defaults).meeting.speakerDiarizationModel, .offlineVBx)
            XCTAssertFalse(FeatureSettingsStore.load(defaults: defaults).meeting.finalTranscriptOptimizationEnabled)
        }
    }

    func testMeetingSettingsDecodeLegacyPayloadWithoutChunkingMode() throws {
        let payload = """
        {
          "asrSelectionID": "mlx:mlx-community/SenseVoiceSmall",
          "summaryModelSelectionID": "local-llm:mlx-community/Qwen3.5-2B-4bit",
          "summaryPrompt": "",
          "summaryAutoGenerate": true,
          "realtimeTranslateEnabled": false,
          "realtimeTargetLanguageRawValue": "",
          "hideOverlayFromScreenSharing": false
        }
        """
        let data = try XCTUnwrap(payload.data(using: .utf8))

        let settings = try JSONDecoder().decode(MeetingFeatureSettings.self, from: data)

        XCTAssertEqual(settings.chunkingMode, .quality)
        XCTAssertEqual(settings.speakerDiarizationModel, .offlineVBx)
        XCTAssertTrue(settings.finalTranscriptOptimizationEnabled)
    }

    func testMeetingDiarizationModeIgnoresLegacyRealtimeKey() throws {
        try withEphemeralDefaults { defaults in
            defaults.set(MeetingDiarizationMode.sortformerV2.rawValue, forKey: AppPreferenceKey.meetingRealtimeDiarizationMode)
            XCTAssertEqual(MeetingDiarizationMode.stored(in: defaults), .offlineVBx)

            defaults.set(MeetingDiarizationMode.sortformerV2.rawValue, forKey: AppPreferenceKey.meetingSpeakerDiarizationModel)
            XCTAssertEqual(MeetingDiarizationMode.stored(in: defaults), .sortformerV2)
        }
    }

    func testMeetingSpeakerRuntimeOptionsIgnoreLegacyPreferences() throws {
        try withEphemeralDefaults { defaults in
            defaults.set(MeetingSpeakerDiarizationSensitivity.sensitive.rawValue, forKey: "meetingSpeakerDiarizationSensitivity")
            defaults.set(MeetingSpeakerCountHint.maxFour.rawValue, forKey: "meetingSpeakerCountHint")
            defaults.set(true, forKey: "meetingSpeakerDiarizationDebugEnabled")

            let options = MeetingSpeakerDiarizationOptions.fromPreferences(defaults: defaults)

            XCTAssertEqual(options.sensitivity, .balanced)
            XCTAssertEqual(options.speakerCountHint, .auto)
            XCTAssertFalse(options.debugLoggingEnabled)
            XCTAssertEqual(options.minimumSpeakerConfidence, MeetingSpeakerDiarizationSensitivity.balanced.minimumSpeakerConfidence)
            XCTAssertEqual(options.smoothing, MeetingSpeakerDiarizationSensitivity.balanced.smootherOptions)
            XCTAssertEqual(options.transcriptAssembly, MeetingSpeakerDiarizationSensitivity.balanced.transcriptAssemblyOptions)
        }
    }
}

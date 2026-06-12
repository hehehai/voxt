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

    func testMeetingChunkingModeDefaultsAndSyncsToRuntimePreference() throws {
        try withEphemeralDefaults { defaults in
            XCTAssertEqual(MeetingChunkingMode.stored(in: defaults), .quality)
            XCTAssertEqual(MeetingServerVADMode.stored(in: defaults), .automatic)
            XCTAssertEqual(MeetingSpeakerDiarizationSensitivity.stored(in: defaults), .balanced)
            XCTAssertFalse(defaults.bool(forKey: AppPreferenceKey.meetingSpeakerDiarizationDebugEnabled))

            defaults.set(MeetingChunkingMode.quality.rawValue, forKey: AppPreferenceKey.meetingChunkingMode)
            defaults.set(MeetingServerVADMode.stable.rawValue, forKey: AppPreferenceKey.meetingServerVADMode)
            defaults.set(MeetingSpeakerDiarizationSensitivity.sensitive.rawValue, forKey: AppPreferenceKey.meetingSpeakerDiarizationSensitivity)
            defaults.set(true, forKey: AppPreferenceKey.meetingSpeakerDiarizationDebugEnabled)
            defaults.set(false, forKey: AppPreferenceKey.meetingFinalTranscriptOptimizationEnabled)

            var settings = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertEqual(settings.meeting.chunkingMode, .quality)
            XCTAssertEqual(settings.meeting.serverVADMode, .stable)
            XCTAssertEqual(settings.meeting.speakerDiarizationSensitivity, .sensitive)
            XCTAssertTrue(settings.meeting.speakerDiarizationDebugEnabled)
            XCTAssertFalse(settings.meeting.finalTranscriptOptimizationEnabled)

            settings.meeting.chunkingModeRawValue = MeetingChunkingMode.realtime.rawValue
            settings.meeting.serverVADModeRawValue = MeetingServerVADMode.responsive.rawValue
            settings.meeting.speakerDiarizationSensitivityRawValue = MeetingSpeakerDiarizationSensitivity.stable.rawValue
            settings.meeting.speakerDiarizationDebugEnabled = false
            settings.meeting.finalTranscriptOptimizationEnabled = false
            FeatureSettingsStore.save(settings, defaults: defaults)
            FeatureSettingsStore.prepareMeetingRuntime(from: settings, defaults: defaults)

            XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.meetingChunkingMode), MeetingChunkingMode.realtime.rawValue)
            XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.meetingServerVADMode), MeetingServerVADMode.responsive.rawValue)
            XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.meetingSpeakerDiarizationSensitivity), MeetingSpeakerDiarizationSensitivity.stable.rawValue)
            XCTAssertFalse(defaults.bool(forKey: AppPreferenceKey.meetingSpeakerDiarizationDebugEnabled))
            XCTAssertFalse(defaults.bool(forKey: AppPreferenceKey.meetingFinalTranscriptOptimizationEnabled))
            XCTAssertEqual(FeatureSettingsStore.load(defaults: defaults).meeting.chunkingMode, .realtime)
            XCTAssertEqual(FeatureSettingsStore.load(defaults: defaults).meeting.serverVADMode, .responsive)
            XCTAssertEqual(FeatureSettingsStore.load(defaults: defaults).meeting.speakerDiarizationSensitivity, .stable)
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
        XCTAssertEqual(settings.serverVADMode, .automatic)
        XCTAssertEqual(settings.speakerDiarizationSensitivity, .balanced)
        XCTAssertFalse(settings.speakerDiarizationDebugEnabled)
        XCTAssertTrue(settings.finalTranscriptOptimizationEnabled)
    }

    func testMeetingSpeakerSensitivityBuildsRuntimeOptionsFromPreferences() throws {
        try withEphemeralDefaults { defaults in
            defaults.set(MeetingSpeakerDiarizationSensitivity.sensitive.rawValue, forKey: AppPreferenceKey.meetingSpeakerDiarizationSensitivity)
            defaults.set(true, forKey: AppPreferenceKey.meetingSpeakerDiarizationDebugEnabled)

            let options = MeetingSpeakerDiarizationOptions.fromPreferences(defaults: defaults)

            XCTAssertEqual(options.sensitivity, .sensitive)
            XCTAssertTrue(options.debugLoggingEnabled)
            XCTAssertLessThan(options.minimumSpeakerConfidence, MeetingSpeakerDiarizationSensitivity.stable.minimumSpeakerConfidence)
            XCTAssertLessThan(
                options.smoothing.minimumTurnDurationSeconds,
                MeetingSpeakerDiarizationSensitivity.stable.smootherOptions.minimumTurnDurationSeconds
            )
            XCTAssertLessThan(
                options.transcriptAssembly.minimumSecondarySpeakerOverlapSeconds,
                MeetingSpeakerDiarizationSensitivity.stable.transcriptAssemblyOptions.minimumSecondarySpeakerOverlapSeconds
            )
        }
    }
}

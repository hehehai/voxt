import XCTest
@testable import Voxt

final class SettingsTypesTests: XCTestCase {
    func testUserMainLanguageSanitizedSelectionDeduplicatesAndFallsBack() {
        XCTAssertEqual(
            UserMainLanguageOption.sanitizedSelection(["zh-CN", "zh-Hans", "EN", "unknown", "en"]),
            ["zh-hans", "en"]
        )
        XCTAssertEqual(
            UserMainLanguageOption.sanitizedSelection(["unknown"]),
            UserMainLanguageOption.defaultSelectionCodes()
        )
    }

    func testStoredSelectionAndStorageValueRoundTrip() {
        let raw = UserMainLanguageOption.storageValue(for: ["zh-Hant", "en"])

        XCTAssertEqual(UserMainLanguageOption.storedSelection(from: raw), ["zh-hant", "en"])
    }

    func testFallbackOptionUsesPreferredLanguages() {
        let option = UserMainLanguageOption.fallbackOption(preferredLanguages: ["zh-TW", "en-US"])

        XCTAssertEqual(option.code, "zh-hant")
        XCTAssertTrue(option.isChinese)
        XCTAssertTrue(option.isTraditionalChinese)
        XCTAssertEqual(option.baseLanguageCode, "zh")
    }

    func testDictionarySuggestionFilterSettingsSanitizedClampsAndDefaultsPrompt() {
        let sanitized = DictionarySuggestionFilterSettings(
            prompt: "   ",
            batchSize: 999,
            maxCandidatesPerBatch: 0
        ).sanitized()

        XCTAssertEqual(sanitized.prompt, DictionarySuggestionFilterSettings.defaultPrompt)
        XCTAssertEqual(sanitized.batchSize, DictionarySuggestionFilterSettings.maximumBatchSize)
        XCTAssertEqual(sanitized.maxCandidatesPerBatch, DictionarySuggestionFilterSettings.minimumMaxCandidates)
    }

    func testOnboardingStepStatusResolverMatchesExpectedRules() {
        let readySnapshot = OnboardingStepStatusSnapshot(
            hasModelIssues: false,
            hasRecordingMicrophone: true,
            hasRecordingPermissions: true,
            hasRewriteIssues: false,
            appEnhancementEnabled: true,
            meetingNotesEnabled: true,
            hasMeetingIssues: false
        )
        let blockedSnapshot = OnboardingStepStatusSnapshot(
            hasModelIssues: true,
            hasRecordingMicrophone: false,
            hasRecordingPermissions: false,
            hasRewriteIssues: true,
            appEnhancementEnabled: false,
            meetingNotesEnabled: true,
            hasMeetingIssues: true
        )

        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .language, snapshot: blockedSnapshot), .ready)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .model, snapshot: blockedSnapshot), .needsSetup)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .transcription, snapshot: blockedSnapshot), .needsSetup)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .translation, snapshot: blockedSnapshot), .ready)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .rewrite, snapshot: blockedSnapshot), .needsSetup)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .appEnhancement, snapshot: blockedSnapshot), .optional)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .meeting, snapshot: blockedSnapshot), .needsSetup)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .finish, snapshot: blockedSnapshot), .done)
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .meeting, snapshot: readySnapshot), .ready)

        let meetingDisabledSnapshot = OnboardingStepStatusSnapshot(
            hasModelIssues: false,
            hasRecordingMicrophone: true,
            hasRecordingPermissions: true,
            hasRewriteIssues: false,
            appEnhancementEnabled: false,
            meetingNotesEnabled: false,
            hasMeetingIssues: true
        )
        XCTAssertEqual(OnboardingStepStatusResolver.resolve(step: .meeting, snapshot: meetingDisabledSnapshot), .optional)
    }

    func testVisibleTabsHideAppEnhancementWhenFeatureDisabled() {
        XCTAssertFalse(SettingsTab.visibleTabs(appEnhancementEnabled: false).contains(.appEnhancement))
        XCTAssertFalse(SettingsTab.visibleTabs(appEnhancementEnabled: true).contains(.appEnhancement))
        XCTAssertTrue(SettingsTab.visibleTabs(appEnhancementEnabled: true).contains(.feature))
    }

    func testFeatureVisibleTabsHideAppEnhancementWhenDisabled() {
        XCTAssertFalse(FeatureSettingsTab.visibleTabs(appEnhancementEnabled: false, meetingEnabled: true).contains(.appEnhancement))
        XCTAssertTrue(FeatureSettingsTab.visibleTabs(appEnhancementEnabled: true, meetingEnabled: true).contains(.appEnhancement))
    }

    func testFeatureVisibleTabsHideMeetingWhenDisabled() {
        XCTAssertFalse(FeatureSettingsTab.visibleTabs(appEnhancementEnabled: true, meetingEnabled: false).contains(.meeting))
        XCTAssertTrue(FeatureSettingsTab.visibleTabs(appEnhancementEnabled: true, meetingEnabled: true).contains(.meeting))
    }

    func testHotkeyShortcutVisibilityHidesMeetingWhenDisabled() {
        XCTAssertEqual(
            HotkeyShortcutVisibility.visibleKinds(meetingEnabled: false),
            [.transcription, .translation, .rewrite]
        )
        XCTAssertEqual(
            HotkeyShortcutVisibility.visibleKinds(meetingEnabled: true),
            [.transcription, .translation, .rewrite, .meeting]
        )
    }

    func testFeatureNavigationTargetMapsAppBranchSectionToFeatureMode() {
        let target = SettingsNavigationTarget(tab: .feature, section: .appBranchGroups)

        XCTAssertEqual(target.tab, .feature)
        XCTAssertEqual(target.featureTab, .appEnhancement)
    }

    func testPermissionRequirementResolverAggregatesFeatureSelections() {
        let context = SettingsPermissionRequirementContext(
            selectedEngine: .mlxAudio,
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
                    asrSelectionID: .dictation,
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
                    enabled: true,
                    asrSelectionID: .mlx(MLXModelManager.defaultModelRepo),
                    summaryModelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                    summaryPrompt: AppPreferenceKey.defaultMeetingSummaryPrompt,
                    summaryAutoGenerate: true,
                    realtimeTranslateEnabled: false,
                    realtimeTargetLanguageRawValue: "",
                    showOverlayInScreenShare: false
                )
            )
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertTrue(permissions.contains(.speechRecognition))
        XCTAssertTrue(permissions.contains(.systemAudioCapture))
    }

    func testVoiceEndCommandPresetResolvesBuiltInCommands() {
        XCTAssertEqual(VoiceEndCommandPreset.over.title, "over")
        XCTAssertEqual(VoiceEndCommandPreset.over.resolvedCommand, "over")

        XCTAssertEqual(VoiceEndCommandPreset.end.title, "end")
        XCTAssertEqual(VoiceEndCommandPreset.end.resolvedCommand, "end")

        XCTAssertEqual(VoiceEndCommandPreset.wanBi.title, "完毕")
        XCTAssertEqual(VoiceEndCommandPreset.wanBi.resolvedCommand, "完毕")

        XCTAssertEqual(VoiceEndCommandPreset.haoLe.title, "好了")
        XCTAssertEqual(VoiceEndCommandPreset.haoLe.resolvedCommand, "好了")

        XCTAssertNil(VoiceEndCommandPreset.custom.resolvedCommand)
    }
}

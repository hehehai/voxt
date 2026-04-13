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

    func testDictionarySuggestionDefaultPromptTightensTermSelectionRules() {
        let prompt = DictionarySuggestionFilterSettings.defaultPrompt

        XCTAssertTrue(prompt.contains("ASR mistakes"))
        XCTAssertTrue(prompt.contains("mixed-language speech"))
        XCTAssertTrue(prompt.contains("must not exceed 6 words"))
        XCTAssertTrue(prompt.contains("must not exceed 6 characters"))
        XCTAssertTrue(prompt.contains("JSON array"))
        XCTAssertTrue(prompt.contains("{\"term\": \"accepted term\"}"))
        XCTAssertTrue(prompt.contains("Return []"))
        XCTAssertTrue(prompt.contains("Other frequently used languages"))
        XCTAssertTrue(prompt.contains("secondary language"))
        XCTAssertTrue(prompt.contains("If a word would be familiar to most ordinary speakers of that language, exclude it"))
        XCTAssertTrue(prompt.contains("Chinese, English, Japanese, Korean, Thai"))
        XCTAssertTrue(prompt.contains("Well-known cities, countries"))
        XCTAssertTrue(prompt.contains("Three Filtering Principles"))
        XCTAssertTrue(prompt.contains("Common vocabulary never belongs in the dictionary"))
        XCTAssertTrue(prompt.contains("Context-only items do not belong in the dictionary"))
        XCTAssertTrue(prompt.contains("stable correction targets"))
        XCTAssertTrue(prompt.contains("我们的规则"))
        XCTAssertTrue(prompt.contains("航班"))
        XCTAssertTrue(prompt.contains("车次"))
        XCTAssertTrue(prompt.contains("token"))
        XCTAssertTrue(prompt.contains("MU5735"))
    }

    func testDictionaryHistoryScanPromptLanguageSupportBuildsOtherLanguagesPromptValue() {
        XCTAssertEqual(
            DictionaryHistoryScanPromptLanguageSupport.otherLanguagesPromptValue(
                from: ["zh-hans", "en", "ja"]
            ),
            "English, Japanese"
        )
        XCTAssertEqual(
            DictionaryHistoryScanPromptLanguageSupport.otherLanguagesPromptValue(
                from: ["zh-hans"]
            ),
            "None"
        )
    }

    func testDictionaryHistoryScanCandidateValidatorRejectsLongOrNoisyTerms() {
        XCTAssertTrue(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "OpenAI"))
        XCTAssertTrue(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "旧金山"))
        XCTAssertTrue(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "MCP"))

        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "this is a very long generic transcript phrase"))
        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "今天我们要开会讨论一下"))
        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "20260413"))
        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "wrong term, maybe"))
        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "Company"))
        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "token"))
        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "我们的规则"))
        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "our rule"))
        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "航班"))
        XCTAssertFalse(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "车次"))
        XCTAssertTrue(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "北京"))
        XCTAssertTrue(DictionaryHistoryScanCandidateValidator.shouldAccept(term: "大同"))
    }

    func testDictionaryHistoryScanCandidateValidatorRejectsTravelRouteTermsFromContext() {
        let sample = "北京到大同今天的航班和车次有哪些？有没有 K130 航班？"

        XCTAssertFalse(
            DictionaryHistoryScanCandidateValidator.shouldAccept(
                term: "K130",
                evidenceSample: sample
            )
        )
        XCTAssertFalse(
            DictionaryHistoryScanCandidateValidator.shouldAccept(
                term: "北京",
                evidenceSample: sample
            )
        )
        XCTAssertFalse(
            DictionaryHistoryScanCandidateValidator.shouldAccept(
                term: "大同",
                evidenceSample: sample
            )
        )
        XCTAssertTrue(
            DictionaryHistoryScanCandidateValidator.shouldAccept(
                term: "OpenAI",
                evidenceSample: "我今天要给 OpenAI 的接口做联调。"
            )
        )
    }

    func testDictionaryHistoryScanResponseParserAcceptsWrappedJSONArray() throws {
        let response = """
        Here are the filtered terms:
        ```json
        [{"term":"OpenAI"},{"term":"OpenAI"},{"term":"MCP"}]
        ```
        """

        XCTAssertEqual(
            try DictionaryHistoryScanResponseParser.parseTerms(from: response),
            ["OpenAI", "MCP"]
        )
    }

    func testDictionaryHistoryScanResponseParserRejectsUnexpectedItemShape() {
        let response = """
        [{"term":"OpenAI","reason":"common company name"}]
        """

        XCTAssertThrowsError(try DictionaryHistoryScanResponseParser.parseTerms(from: response))
    }

    func testDictionaryHistoryScanResponseParserRejectsPlainTextResponse() {
        XCTAssertThrowsError(
            try DictionaryHistoryScanResponseParser.parseTerms(from: "新次元 词源数据")
        )
    }

    func testDictionaryHistoryScanResponseParserExtractsJSONArrayInsideWrapperObject() {
        let response = """
        {"terms":[{"term":"OpenAI"},{"term":"Claude"}]}
        """

        XCTAssertNoThrow(try DictionaryHistoryScanResponseParser.parseTerms(from: response))
    }

    func testDictionaryHistoryScanResponseParserFiltersRejectedJSONArrayItems() throws {
        let response = """
        [
          {"term":"OpenAI"},
          {"term":"this is a very long generic transcript phrase"},
          {"term":"今天我们要开会讨论一下"},
          {"term":"MCP"}
        ]
        """

        XCTAssertEqual(
            try DictionaryHistoryScanResponseParser.parseTerms(from: response),
            ["OpenAI", "MCP"]
        )
    }

    func testDictionaryHistoryScanResponseParserNormalizesAcceptedTermsDirectly() {
        XCTAssertEqual(
            DictionaryHistoryScanResponseParser.normalizeAcceptedTerms(
                from: ["OpenAI", "OpenAI", "今天我们要开会讨论一下", "MCP"]
            ),
            ["OpenAI", "MCP"]
        )
    }

    func testDictionaryHistoryScanResponsesSchemaUsesStrictTopLevelArray() throws {
        let payload = DictionaryHistoryScanResponseParser.responsesTextFormatPayload()
        let format = try XCTUnwrap(payload["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        let items = try XCTUnwrap(schema["items"] as? [String: Any])
        let properties = try XCTUnwrap(items["properties"] as? [String: Any])

        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(schema["type"] as? String, "array")
        XCTAssertEqual(items["type"] as? String, "object")
        XCTAssertEqual(items["additionalProperties"] as? Bool, false)
        XCTAssertNotNil(properties["term"])
        XCTAssertEqual(items["required"] as? [String], ["term"])
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

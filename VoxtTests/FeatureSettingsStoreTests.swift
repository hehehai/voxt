import XCTest
@testable import Voxt

final class FeatureSettingsStoreTests: XCTestCase {
    func testDeriveFromLegacyDefaultsMeetingToDisabledWhenUnset() {
        let defaults = TestDoubles.makeUserDefaults()

        let settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)

        XCTAssertFalse(settings.meeting.enabled)
    }

    func testDeriveFromLegacyBuildsFeatureSettings() {
        let defaults = TestDoubles.makeUserDefaults()
        defaults.set(TranscriptionEngine.whisperKit.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
        defaults.set("large-v3", forKey: AppPreferenceKey.whisperModelID)
        defaults.set(EnhancementMode.remoteLLM.rawValue, forKey: AppPreferenceKey.enhancementMode)
        defaults.set(RemoteLLMProvider.openAI.rawValue, forKey: AppPreferenceKey.remoteLLMSelectedProvider)
        defaults.set(TranslationModelProvider.remoteLLM.rawValue, forKey: AppPreferenceKey.translationModelProvider)
        defaults.set(RemoteLLMProvider.deepseek.rawValue, forKey: AppPreferenceKey.translationRemoteLLMProvider)
        defaults.set(RewriteModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.rewriteModelProvider)
        defaults.set("Qwen/Qwen2.5-7B-Instruct", forKey: AppPreferenceKey.rewriteCustomLLMModelRepo)
        defaults.set(true, forKey: AppPreferenceKey.appEnhancementEnabled)
        defaults.set(true, forKey: AppPreferenceKey.meetingNotesBetaEnabled)
        defaults.set("custom-llm:Qwen/Qwen3-8B-4bit", forKey: AppPreferenceKey.meetingSummaryModelSelection)

        let settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)

        XCTAssertEqual(settings.transcription.asrSelectionID, .whisper("large-v3"))
        XCTAssertEqual(settings.transcription.llmSelectionID, .remoteLLM(.openAI))
        XCTAssertEqual(settings.translation.modelSelectionID, .remoteLLM(.deepseek))
        XCTAssertEqual(settings.rewrite.llmSelectionID, .localLLM("Qwen/Qwen2.5-7B-Instruct"))
        XCTAssertTrue(settings.rewrite.appEnhancementEnabled)
        XCTAssertTrue(settings.meeting.enabled)
        XCTAssertEqual(settings.meeting.summaryModelSelectionID, .localLLM("Qwen/Qwen3-8B-4bit"))
    }

    func testPrepareLegacySessionUsesFeatureSpecificSelections() {
        let defaults = TestDoubles.makeUserDefaults()
        let settings = FeatureSettings(
            transcription: .init(
                asrSelectionID: .mlx("mlx-community/parakeet-tdt-0.6b-v3"),
                llmEnabled: true,
                llmSelectionID: .remoteLLM(.openAI),
                prompt: AppPreferenceKey.defaultEnhancementPrompt
            ),
            translation: .init(
                asrSelectionID: .remoteASR(.doubaoASR),
                modelSelectionID: .remoteLLM(.deepseek),
                targetLanguageRawValue: TranslationTargetLanguage.english.rawValue,
                prompt: AppPreferenceKey.defaultTranslationPrompt,
                replaceSelectedText: true
            ),
            rewrite: .init(
                asrSelectionID: .whisper("medium"),
                llmSelectionID: .localLLM("Qwen/Qwen3-8B-4bit"),
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

        FeatureSettingsStore.prepareLegacySession(from: settings, outputMode: .translation, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.transcriptionEngine), TranscriptionEngine.remote.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.remoteASRSelectedProvider), RemoteASRProvider.doubaoASR.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.translationModelProvider), TranslationModelProvider.remoteLLM.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.translationRemoteLLMProvider), RemoteLLMProvider.deepseek.rawValue)
    }

    func testPrepareLegacyMeetingUsesMeetingSpecificSelections() {
        let defaults = TestDoubles.makeUserDefaults()
        let settings = FeatureSettings(
            transcription: .init(
                asrSelectionID: .mlx(MLXModelManager.defaultModelRepo),
                llmEnabled: false,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultEnhancementPrompt
            ),
            translation: .init(
                asrSelectionID: .mlx(MLXModelManager.defaultModelRepo),
                modelSelectionID: .remoteLLM(.openAI),
                targetLanguageRawValue: TranslationTargetLanguage.japanese.rawValue,
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
                asrSelectionID: .remoteASR(.aliyunBailianASR),
                summaryModelSelectionID: .remoteLLM(.deepseek),
                summaryPrompt: "summary prompt",
                summaryAutoGenerate: false,
                realtimeTranslateEnabled: true,
                realtimeTargetLanguageRawValue: TranslationTargetLanguage.japanese.rawValue,
                showOverlayInScreenShare: true
            )
        )

        FeatureSettingsStore.prepareLegacyMeeting(from: settings, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.transcriptionEngine), TranscriptionEngine.remote.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.remoteASRSelectedProvider), RemoteASRProvider.aliyunBailianASR.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.meetingSummaryModelSelection), "remote-llm:\(RemoteLLMProvider.deepseek.rawValue)")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.meetingSummaryPromptTemplate), "summary prompt")
        XCTAssertTrue(defaults.bool(forKey: AppPreferenceKey.meetingRealtimeTranslateEnabled))
    }

    func testPrepareLegacyMeetingMirrorsDisabledMeetingState() {
        let defaults = TestDoubles.makeUserDefaults()
        let settings = FeatureSettings(
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
                asrSelectionID: .mlx(MLXModelManager.defaultModelRepo),
                summaryModelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                summaryPrompt: AppPreferenceKey.defaultMeetingSummaryPrompt,
                summaryAutoGenerate: true,
                realtimeTranslateEnabled: false,
                realtimeTargetLanguageRawValue: "",
                showOverlayInScreenShare: false
            )
        )

        FeatureSettingsStore.prepareLegacyMeeting(from: settings, defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: AppPreferenceKey.meetingNotesBetaEnabled))
    }

    func testSavePreservesDisabledMeetingState() {
        let defaults = TestDoubles.makeUserDefaults()
        let settings = FeatureSettings(
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
                asrSelectionID: .mlx(MLXModelManager.defaultModelRepo),
                summaryModelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                summaryPrompt: AppPreferenceKey.defaultMeetingSummaryPrompt,
                summaryAutoGenerate: true,
                realtimeTranslateEnabled: false,
                realtimeTargetLanguageRawValue: "",
                showOverlayInScreenShare: false
            )
        )

        FeatureSettingsStore.save(settings, defaults: defaults)

        let reloaded = FeatureSettingsStore.load(defaults: defaults)
        XCTAssertFalse(reloaded.meeting.enabled)
        XCTAssertFalse(defaults.bool(forKey: AppPreferenceKey.meetingNotesBetaEnabled))
    }
}

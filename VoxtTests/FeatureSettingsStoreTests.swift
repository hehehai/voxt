import XCTest
import Carbon
@testable import Voxt

final class FeatureSettingsStoreTests: XCTestCase {
    func testDeriveFromLegacyDefaultsMeetingToDisabledWhenUnset() {
        let defaults = TestDoubles.makeUserDefaults()

        let settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)

        XCTAssertFalse(settings.meeting.enabled)
        XCTAssertFalse(settings.transcription.notes.enabled)
        XCTAssertEqual(settings.rewrite.continueShortcut.keyCode, TranscriptionContinueShortcutSettings.defaultShortcut.keyCode)
        XCTAssertEqual(settings.transcription.notes.triggerShortcut.keyCode, TranscriptionNoteTriggerSettings.defaultShortcut.keyCode)
        XCTAssertEqual(settings.transcription.notes.obsidianSync.relativeFolder, "Voxt")
        XCTAssertEqual(settings.transcription.notes.obsidianSync.groupingMode, .file)
        XCTAssertFalse(settings.transcription.notes.remindersSync.enabled)
        XCTAssertEqual(settings.transcription.notes.remindersSync.selectedListIdentifier, "")
        XCTAssertEqual(settings.transcription.notes.remindersSync.selectedListTitle, "")
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
        XCTAssertEqual(settings.transcription.notes.titleModelSelectionID, .remoteLLM(.openAI))
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

    func testSavePreservesRewriteContinueShortcut() {
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
                appEnhancementEnabled: false,
                continueShortcut: .init(keyCode: UInt16(kVK_Return))
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
        XCTAssertEqual(reloaded.rewrite.continueShortcut.keyCode, UInt16(kVK_Return))
        XCTAssertEqual(reloaded.transcription.notes.obsidianSync.groupingMode, .file)
    }

    func testSaveSanitizesObsidianSyncPathAndFolder() {
        let defaults = TestDoubles.makeUserDefaults()
        let bookmarkData = Data([0x01, 0x02, 0x03])
        let settings = FeatureSettings(
            transcription: .init(
                asrSelectionID: .mlx(MLXModelManager.defaultModelRepo),
                llmEnabled: false,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultEnhancementPrompt,
                notes: .init(
                    enabled: true,
                    triggerShortcut: .defaultShortcut,
                    titleModelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                    soundEnabled: false,
                    soundPreset: .soft,
                    obsidianSync: .init(
                        enabled: true,
                        vaultPath: "  /Users/test/Vault  ",
                        vaultBookmarkData: bookmarkData,
                        relativeFolder: " /Voxt Inbox/ ",
                        groupingMode: .daily
                    )
                )
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
        XCTAssertEqual(reloaded.transcription.notes.obsidianSync.vaultPath, "/Users/test/Vault")
        XCTAssertEqual(reloaded.transcription.notes.obsidianSync.relativeFolder, "Voxt Inbox")
        XCTAssertEqual(reloaded.transcription.notes.obsidianSync.groupingMode, .daily)
        XCTAssertEqual(reloaded.transcription.notes.obsidianSync.vaultBookmarkData, bookmarkData)
    }

    func testLoadSanitizesModifierOnlyRewriteContinueShortcut() {
        let defaults = TestDoubles.makeUserDefaults()
        defaults.set(
            """
            {"transcription":{"asrSelectionID":"dictation","llmEnabled":false,"llmSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","prompt":"prompt","notes":{"enabled":false,"triggerShortcut":{"keyCode":49,"modifiersRawValue":0,"sidedModifiersRawValue":0},"titleModelSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","soundEnabled":false,"soundPreset":"soft"}},"translation":{"asrSelectionID":"dictation","modelSelectionID":"remote-llm:openai","targetLanguageRawValue":"english","prompt":"translation","replaceSelectedText":true},"rewrite":{"asrSelectionID":"dictation","llmSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","prompt":"rewrite","appEnhancementEnabled":false,"continueShortcut":{"keyCode":65535,"modifiersRawValue":0,"sidedModifiersRawValue":0}},"meeting":{"enabled":false,"asrSelectionID":"dictation","summaryModelSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","summaryPrompt":"meeting","summaryAutoGenerate":true,"realtimeTranslateEnabled":false,"realtimeTargetLanguageRawValue":"","showOverlayInScreenShare":false}}
            """,
            forKey: AppPreferenceKey.featureSettings
        )

        let settings = FeatureSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.rewrite.continueShortcut.keyCode, TranscriptionContinueShortcutSettings.defaultShortcut.keyCode)
    }

    func testLoadSanitizesModifierOnlyNoteTriggerShortcut() {
        let defaults = TestDoubles.makeUserDefaults()
        defaults.set(
            """
            {"transcription":{"asrSelectionID":"dictation","llmEnabled":false,"llmSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","prompt":"prompt","notes":{"enabled":true,"triggerShortcut":{"keyCode":65535,"modifiersRawValue":0,"sidedModifiersRawValue":0},"titleModelSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","soundEnabled":false,"soundPreset":"soft"}},"translation":{"asrSelectionID":"dictation","modelSelectionID":"remote-llm:openai","targetLanguageRawValue":"english","prompt":"translation","replaceSelectedText":true},"rewrite":{"asrSelectionID":"dictation","llmSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","prompt":"rewrite","appEnhancementEnabled":false,"continueShortcut":{"keyCode":49,"modifiersRawValue":0,"sidedModifiersRawValue":0}},"meeting":{"enabled":false,"asrSelectionID":"dictation","summaryModelSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","summaryPrompt":"meeting","summaryAutoGenerate":true,"realtimeTranslateEnabled":false,"realtimeTargetLanguageRawValue":"","showOverlayInScreenShare":false}}
            """,
            forKey: AppPreferenceKey.featureSettings
        )

        let settings = FeatureSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.transcription.notes.triggerShortcut.keyCode, TranscriptionNoteTriggerSettings.defaultShortcut.keyCode)
    }

    func testLoadDefaultsMissingNoteSoundFieldsSafely() {
        let defaults = TestDoubles.makeUserDefaults()
        defaults.set(
            """
            {"transcription":{"asrSelectionID":"dictation","llmEnabled":false,"llmSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","prompt":"prompt","notes":{"enabled":true,"triggerShortcut":{"keyCode":49,"modifiersRawValue":0,"sidedModifiersRawValue":0},"titleModelSelectionID":"local-llm:Qwen/Qwen3-8B-4bit"}},"translation":{"asrSelectionID":"dictation","modelSelectionID":"remote-llm:openai","targetLanguageRawValue":"english","prompt":"translation","replaceSelectedText":true},"rewrite":{"asrSelectionID":"dictation","llmSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","prompt":"rewrite","appEnhancementEnabled":false},"meeting":{"enabled":false,"asrSelectionID":"dictation","summaryModelSelectionID":"local-llm:Qwen/Qwen3-8B-4bit","summaryPrompt":"meeting","summaryAutoGenerate":true,"realtimeTranslateEnabled":false,"realtimeTargetLanguageRawValue":"","showOverlayInScreenShare":false}}
            """,
            forKey: AppPreferenceKey.featureSettings
        )

        let settings = FeatureSettingsStore.load(defaults: defaults)

        XCTAssertTrue(settings.transcription.notes.enabled)
        XCTAssertEqual(settings.rewrite.continueShortcut.keyCode, TranscriptionContinueShortcutSettings.defaultShortcut.keyCode)
        XCTAssertFalse(settings.transcription.notes.soundEnabled)
        XCTAssertEqual(settings.transcription.notes.soundPreset, .soft)
        XCTAssertFalse(settings.transcription.notes.obsidianSync.enabled)
        XCTAssertEqual(settings.transcription.notes.obsidianSync.relativeFolder, "Voxt")
        XCTAssertEqual(settings.transcription.notes.obsidianSync.groupingMode, .file)
        XCTAssertFalse(settings.transcription.notes.remindersSync.enabled)
        XCTAssertEqual(settings.transcription.notes.remindersSync.selectedListIdentifier, "")
        XCTAssertEqual(settings.transcription.notes.remindersSync.selectedListTitle, "")
    }

    func testSavePreservesObsidianSyncSettings() {
        let defaults = TestDoubles.makeUserDefaults()
        var settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)
        settings.transcription.notes.obsidianSync = ObsidianNoteSyncSettings(
            enabled: true,
            vaultPath: "/Users/test/Obsidian",
            vaultBookmarkData: Data([1, 2, 3]),
            relativeFolder: "Voxt Inbox",
            groupingMode: .daily
        )

        FeatureSettingsStore.save(settings, defaults: defaults)

        let reloaded = FeatureSettingsStore.load(defaults: defaults)
        XCTAssertTrue(reloaded.transcription.notes.obsidianSync.enabled)
        XCTAssertEqual(reloaded.transcription.notes.obsidianSync.vaultPath, "/Users/test/Obsidian")
        XCTAssertEqual(reloaded.transcription.notes.obsidianSync.vaultBookmarkData, Data([1, 2, 3]))
        XCTAssertEqual(reloaded.transcription.notes.obsidianSync.relativeFolder, "Voxt Inbox")
        XCTAssertEqual(reloaded.transcription.notes.obsidianSync.groupingMode, .daily)
    }

    func testSavePreservesRemindersSyncSettings() {
        let defaults = TestDoubles.makeUserDefaults()
        var settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)
        settings.transcription.notes.remindersSync = RemindersNoteSyncSettings(
            enabled: true,
            selectedListIdentifier: "list-123",
            selectedListTitle: "Voxt Inbox"
        )

        FeatureSettingsStore.save(settings, defaults: defaults)

        let reloaded = FeatureSettingsStore.load(defaults: defaults)
        XCTAssertTrue(reloaded.transcription.notes.remindersSync.enabled)
        XCTAssertEqual(reloaded.transcription.notes.remindersSync.selectedListIdentifier, "list-123")
        XCTAssertEqual(reloaded.transcription.notes.remindersSync.selectedListTitle, "Voxt Inbox")
    }
}

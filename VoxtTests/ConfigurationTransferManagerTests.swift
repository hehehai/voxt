import XCTest
@testable import Voxt

final class ConfigurationTransferManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VoxtSecureStorage.clearAllForTesting()
    }

    override func tearDown() {
        VoxtSecureStorage.clearAllForTesting()
        super.tearDown()
    }

    func testExportImportRoundTripUsesIsolatedEnvironmentAndSanitizesSecrets() throws {
        let sourceDefaults = TestDoubles.makeUserDefaults()
        let sourceDirectory = try TemporaryDirectory()
        let sourceEnvironment = TestEnvironmentFactory.configurationTransferEnvironment(in: sourceDirectory)

        sourceDefaults.set(AppInterfaceLanguage.english.rawValue, forKey: AppPreferenceKey.interfaceLanguage)
        sourceDefaults.set("builtin-mic", forKey: AppPreferenceKey.activeInputDeviceUID)
        sourceDefaults.set(false, forKey: AppPreferenceKey.microphoneAutoSwitchEnabled)
        sourceDefaults.set(["usb-mic", "builtin-mic"], forKey: AppPreferenceKey.microphonePriorityUIDs)
        sourceDefaults.set(
            """
            [{"uid":"usb-mic","lastKnownName":"USB Mic"},{"uid":"builtin-mic","lastKnownName":"Built-in Mic"}]
            """,
            forKey: AppPreferenceKey.trackedMicrophoneRecords
        )
        sourceDefaults.set(UserMainLanguageOption.storageValue(for: ["zh-TW", "en"]), forKey: AppPreferenceKey.userMainLanguageCodes)
        sourceDefaults.set(TranscriptionEngine.whisperKit.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
        sourceDefaults.set("mlx-community/Voxtral-Mini-4B-Realtime-2602", forKey: AppPreferenceKey.mlxModelRepo)
        sourceDefaults.set("small", forKey: AppPreferenceKey.whisperModelID)
        sourceDefaults.set(0.4, forKey: AppPreferenceKey.whisperTemperature)
        sourceDefaults.set(false, forKey: AppPreferenceKey.whisperVADEnabled)
        sourceDefaults.set(true, forKey: AppPreferenceKey.whisperTimestampsEnabled)
        sourceDefaults.set(false, forKey: AppPreferenceKey.whisperRealtimeEnabled)
        sourceDefaults.set(
            WhisperLocalTuningSettingsStore.storageValue(
                for: WhisperLocalTuningSettings(
                    preset: .accuracyFirst,
                    temperatureFallbackCount: 3,
                    temperatureIncrementOnFallback: 0.3,
                    compressionRatioThreshold: 2.1,
                    logProbThreshold: -1.4,
                    noSpeechThreshold: 0.4
                )
            ),
            forKey: AppPreferenceKey.whisperLocalASRTuningSettings
        )
        sourceDefaults.set(
            MLXLocalTuningSettingsStore.storageValue(
                for: [
                    MLXLocalTuningSettingsStore.familyKey(for: "mlx-community/Qwen3-ASR-0.6B-4bit"): MLXLocalTuningSettings(
                        preset: .accuracyFirst,
                        qwenContextBias: "OpenAI Codex",
                        granitePromptBias: "",
                        senseVoiceUseITN: false
                    )
                ]
            ),
            forKey: AppPreferenceKey.mlxLocalASRTuningSettings
        )
        sourceDefaults.set(TranslationModelProvider.remoteLLM.rawValue, forKey: AppPreferenceKey.translationFallbackModelProvider)
        sourceDefaults.set(TranslationTargetLanguage.japanese.rawValue, forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage)
        sourceDefaults.set("secret-password", forKey: AppPreferenceKey.customProxyPassword)
        sourceDefaults.set(
            RemoteModelConfigurationStore.saveConfigurations([
                RemoteASRProvider.doubaoASR.rawValue: TestFactories.makeRemoteConfiguration(
                    providerID: RemoteASRProvider.doubaoASR.rawValue,
                    model: DoubaoASRConfiguration.modelV2,
                    appID: "doubao-app",
                    accessToken: "doubao-token",
                    doubaoDictionaryMode: DoubaoDictionaryMode.requestScoped.rawValue,
                    doubaoEnableRequestHotwords: false,
                    doubaoEnableRequestCorrections: true
                )
            ]),
            forKey: AppPreferenceKey.remoteASRProviderConfigurations
        )
        sourceDefaults.set(
            RemoteModelConfigurationStore.saveConfigurations([
                RemoteLLMProvider.openAI.rawValue: TestFactories.makeRemoteConfiguration(
                    providerID: RemoteLLMProvider.openAI.rawValue,
                    model: "gpt-5.2",
                    endpoint: "https://example.com/llm",
                    apiKey: "super-secret"
                )
            ]),
            forKey: AppPreferenceKey.remoteLLMProviderConfigurations
        )

        let dictionaryEntries = [TestFactories.makeEntry(term: "OpenAI", replacementTerms: ["open ai"])]
        let dictionarySuggestions = [TestFactories.makeDictionarySuggestion(term: "Anthropic")]
        try JSONEncoder().encode(dictionaryEntries).write(
            to: sourceDirectory.url.appendingPathComponent("dictionary.json")
        )
        try JSONEncoder().encode(dictionarySuggestions).write(
            to: sourceDirectory.url.appendingPathComponent("dictionary-suggestions.json")
        )

        let exported = try ConfigurationTransferManager.exportJSONString(
            defaults: sourceDefaults,
            environment: sourceEnvironment
        )

        XCTAssertContains(exported, ConfigurationTransferManager.sensitivePlaceholder)
        XCTAssertFalse(exported.contains("secret-password"))
        XCTAssertFalse(exported.contains("super-secret"))
        XCTAssertFalse(exported.contains("doubao-token"))

        let targetDefaults = TestDoubles.makeUserDefaults()
        let targetDirectory = try TemporaryDirectory()
        let targetEnvironment = TestEnvironmentFactory.configurationTransferEnvironment(in: targetDirectory)

        try ConfigurationTransferManager.importConfiguration(
            from: exported,
            defaults: targetDefaults,
            environment: targetEnvironment
        )

        XCTAssertEqual(
            UserMainLanguageOption.storedSelection(from: targetDefaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)),
            ["zh-hant", "en"]
        )
        XCTAssertEqual(targetDefaults.string(forKey: AppPreferenceKey.activeInputDeviceUID), "builtin-mic")
        XCTAssertFalse(targetDefaults.bool(forKey: AppPreferenceKey.microphoneAutoSwitchEnabled))
        XCTAssertEqual(targetDefaults.stringArray(forKey: AppPreferenceKey.microphonePriorityUIDs), ["usb-mic", "builtin-mic"])
        XCTAssertEqual(
            MicrophonePreferenceManager.trackedRecords(defaults: targetDefaults),
            [
                TrackedMicrophoneRecord(uid: "usb-mic", lastKnownName: "USB Mic"),
                TrackedMicrophoneRecord(uid: "builtin-mic", lastKnownName: "Built-in Mic")
            ]
        )
        XCTAssertEqual(targetDefaults.string(forKey: AppPreferenceKey.transcriptionEngine), TranscriptionEngine.whisperKit.rawValue)
        XCTAssertEqual(
            targetDefaults.string(forKey: AppPreferenceKey.mlxModelRepo),
            "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"
        )
        XCTAssertEqual(targetDefaults.string(forKey: AppPreferenceKey.whisperModelID), "small")
        XCTAssertEqual(targetDefaults.double(forKey: AppPreferenceKey.whisperTemperature), 0.4, accuracy: 0.0001)
        XCTAssertFalse(targetDefaults.bool(forKey: AppPreferenceKey.whisperVADEnabled))
        XCTAssertTrue(targetDefaults.bool(forKey: AppPreferenceKey.whisperTimestampsEnabled))
        XCTAssertFalse(targetDefaults.bool(forKey: AppPreferenceKey.whisperRealtimeEnabled))
        XCTAssertEqual(
            WhisperLocalTuningSettingsStore.resolvedSettings(
                from: targetDefaults.string(forKey: AppPreferenceKey.whisperLocalASRTuningSettings)
            ),
            WhisperLocalTuningSettings(
                preset: .accuracyFirst,
                temperatureFallbackCount: 3,
                temperatureIncrementOnFallback: 0.3,
                compressionRatioThreshold: 2.1,
                logProbThreshold: -1.4,
                noSpeechThreshold: 0.4
            )
        )
        XCTAssertEqual(
            MLXLocalTuningSettingsStore.resolvedSettings(
                for: "mlx-community/Qwen3-ASR-0.6B-4bit",
                rawValue: targetDefaults.string(forKey: AppPreferenceKey.mlxLocalASRTuningSettings)
            ),
            MLXLocalTuningSettings(
                preset: .accuracyFirst,
                qwenContextBias: "OpenAI Codex",
                granitePromptBias: "",
                senseVoiceUseITN: false
            )
        )
        XCTAssertEqual(targetDefaults.string(forKey: AppPreferenceKey.translationFallbackModelProvider), TranslationModelProvider.customLLM.rawValue)
        XCTAssertEqual(targetDefaults.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage), TranslationTargetLanguage.japanese.rawValue)
        XCTAssertEqual(targetDefaults.string(forKey: AppPreferenceKey.customProxyUsername) ?? "", "")
        XCTAssertEqual(targetDefaults.string(forKey: AppPreferenceKey.customProxyPassword) ?? "", "")
        XCTAssertEqual(VoxtNetworkSession.proxyCredentials(defaults: targetDefaults).password, "")

        let importedFeatureSettings = FeatureSettingsStore.load(defaults: targetDefaults)
        XCTAssertEqual(importedFeatureSettings.translation.modelSelectionID, .localLLM(CustomLLMModelManager.defaultModelRepo))
        XCTAssertEqual(importedFeatureSettings.translation.targetLanguage, .english)

        let importedRemote = RemoteModelConfigurationStore.loadConfigurations(
            from: targetDefaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? ""
        )
        XCTAssertEqual(importedRemote[RemoteLLMProvider.openAI.rawValue]?.apiKey, "")
        let importedRemoteASR = RemoteModelConfigurationStore.loadConfigurations(
            from: targetDefaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        )
        let doubao = try XCTUnwrap(importedRemoteASR[RemoteASRProvider.doubaoASR.rawValue])
        XCTAssertEqual(doubao.accessToken, "")
        XCTAssertEqual(doubao.doubaoDictionaryMode, DoubaoDictionaryMode.requestScoped.rawValue)
        XCTAssertFalse(doubao.doubaoEnableRequestHotwords)
        XCTAssertTrue(doubao.doubaoEnableRequestCorrections)

        let importedEntries = try JSONDecoder().decode(
            [DictionaryEntry].self,
            from: Data(contentsOf: targetDirectory.url.appendingPathComponent("dictionary.json"))
        )
        let importedSuggestions = try JSONDecoder().decode(
            [DictionarySuggestion].self,
            from: Data(contentsOf: targetDirectory.url.appendingPathComponent("dictionary-suggestions.json"))
        )
        XCTAssertEqual(importedEntries, dictionaryEntries)
        XCTAssertEqual(importedSuggestions, dictionarySuggestions)
    }

    func testGeneralSettingsDecoderBackfillsNewFields() throws {
        let json = """
        {
          "interfaceLanguage": "system",
          "selectedInputDeviceID": 0,
          "activeInputDeviceUID": "usb-mic",
          "microphoneAutoSwitchEnabled": false,
          "microphonePriorityUIDs": ["usb-mic", "builtin-mic"],
          "trackedMicrophoneRecords": [
            { "uid": "usb-mic", "lastKnownName": "USB Mic" }
          ],
          "interactionSoundsEnabled": true,
          "interactionSoundPreset": "",
          "overlayPosition": "bottom",
          "translationTargetLanguage": "english",
          "translateSelectedTextOnTranslationHotkey": true,
          "autoCopyWhenNoFocusedInput": false,
          "launchAtLogin": false,
          "showInDock": true,
          "historyEnabled": true,
          "historyRetentionPeriod": "forever",
          "autoCheckForUpdates": true,
          "hotkeyDebugLoggingEnabled": false,
          "llmDebugLoggingEnabled": false,
          "useSystemProxy": true,
          "networkProxyMode": "system",
          "customProxyScheme": "",
          "customProxyHost": "",
          "customProxyPort": "",
          "customProxyUsername": "",
          "customProxyPassword": ""
        }
        """

        let decoded = try JSONDecoder().decode(
            ConfigurationTransferManager.GeneralSettings.self,
            from: Data(json.utf8)
        )

        XCTAssertFalse(decoded.muteSystemAudioWhileRecording)
        XCTAssertEqual(decoded.activeInputDeviceUID, "usb-mic")
        XCTAssertFalse(decoded.microphoneAutoSwitchEnabled)
        XCTAssertEqual(decoded.microphonePriorityUIDs, ["usb-mic", "builtin-mic"])
        XCTAssertEqual(decoded.trackedMicrophoneRecords, [TrackedMicrophoneRecord(uid: "usb-mic", lastKnownName: "USB Mic")])
        XCTAssertEqual(decoded.overlayCardOpacity, 82)
        XCTAssertEqual(decoded.userMainLanguageCodes, UserMainLanguageOption.defaultSelectionCodes())
        XCTAssertFalse(decoded.hideMeetingOverlayFromScreenSharing)
        XCTAssertEqual(decoded.meetingRealtimeTranslationTargetLanguage, "")
        XCTAssertFalse(decoded.alwaysShowRewriteAnswerCard)
        XCTAssertTrue(decoded.historyCleanupEnabled)
    }

    func testExportImportRoundTripPreservesFeatureSettings() throws {
        let sourceDefaults = TestDoubles.makeUserDefaults()
        FeatureSettingsStore.save(
            FeatureSettings(
                transcription: .init(
                    asrSelectionID: .whisper("large-v3"),
                    llmEnabled: true,
                    llmSelectionID: .remoteLLM(.deepseek),
                    prompt: "clean transcript"
                ),
                translation: .init(
                    asrSelectionID: .remoteASR(.doubaoASR),
                    modelSelectionID: .remoteLLM(.openAI),
                    targetLanguageRawValue: TranslationTargetLanguage.japanese.rawValue,
                    prompt: "translate carefully",
                    replaceSelectedText: false
                ),
                rewrite: .init(
                    asrSelectionID: .mlx("mlx-community/parakeet-tdt-0.6b-v3"),
                    llmSelectionID: .localLLM("Qwen/Qwen3-8B-4bit"),
                    prompt: "rewrite politely",
                    appEnhancementEnabled: true
                ),
                meeting: .init(
                    enabled: true,
                    asrSelectionID: .remoteASR(.aliyunBailianASR),
                    summaryModelSelectionID: .remoteLLM(.deepseek),
                    summaryPrompt: "meeting summary",
                    summaryAutoGenerate: false,
                    realtimeTranslateEnabled: true,
                    realtimeTargetLanguageRawValue: TranslationTargetLanguage.japanese.rawValue,
                    showOverlayInScreenShare: true
                )
            ),
            defaults: sourceDefaults
        )

        let sourceDirectory = try TemporaryDirectory()
        let exported = try ConfigurationTransferManager.exportJSONString(
            defaults: sourceDefaults,
            environment: TestEnvironmentFactory.configurationTransferEnvironment(in: sourceDirectory)
        )

        let targetDefaults = TestDoubles.makeUserDefaults()
        let targetDirectory = try TemporaryDirectory()
        try ConfigurationTransferManager.importConfiguration(
            from: exported,
            defaults: targetDefaults,
            environment: TestEnvironmentFactory.configurationTransferEnvironment(in: targetDirectory)
        )

        let imported = FeatureSettingsStore.load(defaults: targetDefaults)
        XCTAssertEqual(imported.transcription.asrSelectionID, .whisper("large-v3"))
        XCTAssertEqual(imported.transcription.llmSelectionID, .remoteLLM(.deepseek))
        XCTAssertEqual(imported.translation.asrSelectionID, .remoteASR(.doubaoASR))
        XCTAssertEqual(imported.translation.modelSelectionID, .remoteLLM(.openAI))
        XCTAssertEqual(imported.rewrite.llmSelectionID, .localLLM("Qwen/Qwen3-8B-4bit"))
        XCTAssertTrue(imported.rewrite.appEnhancementEnabled)
        XCTAssertEqual(imported.meeting.asrSelectionID, .remoteASR(.aliyunBailianASR))
        XCTAssertEqual(imported.meeting.summaryModelSelectionID, .remoteLLM(.deepseek))
        XCTAssertTrue(imported.meeting.showOverlayInScreenShare)
    }

    func testImportLegacyPayloadWithoutFeatureSectionDerivesFeatureSettings() throws {
        let defaults = TestDoubles.makeUserDefaults()
        let sourceDirectory = try TemporaryDirectory()
        let environment = TestEnvironmentFactory.configurationTransferEnvironment(in: sourceDirectory)

        defaults.set(TranscriptionEngine.remote.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
        defaults.set(RemoteASRProvider.doubaoASR.rawValue, forKey: AppPreferenceKey.remoteASRSelectedProvider)
        defaults.set(EnhancementMode.remoteLLM.rawValue, forKey: AppPreferenceKey.enhancementMode)
        defaults.set(RemoteLLMProvider.deepseek.rawValue, forKey: AppPreferenceKey.remoteLLMSelectedProvider)
        defaults.set(TranslationModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.translationModelProvider)
        defaults.set("Qwen/Qwen3-8B-4bit", forKey: AppPreferenceKey.translationCustomLLMModelRepo)
        defaults.set(RewriteModelProvider.remoteLLM.rawValue, forKey: AppPreferenceKey.rewriteModelProvider)
        defaults.set(RemoteLLMProvider.openAI.rawValue, forKey: AppPreferenceKey.rewriteRemoteLLMProvider)

        let exported = try ConfigurationTransferManager.exportJSONString(defaults: defaults, environment: environment)
        let data = try XCTUnwrap(exported.data(using: .utf8))
        let rawObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var legacyObject = rawObject
        legacyObject.removeValue(forKey: "feature")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
        let legacyJSON = try XCTUnwrap(String(data: legacyData, encoding: .utf8))

        let importedDefaults = TestDoubles.makeUserDefaults()
        let targetDirectory = try TemporaryDirectory()
        try ConfigurationTransferManager.importConfiguration(
            from: legacyJSON,
            defaults: importedDefaults,
            environment: TestEnvironmentFactory.configurationTransferEnvironment(in: targetDirectory)
        )

        let settings = FeatureSettingsStore.load(defaults: importedDefaults)
        XCTAssertEqual(settings.transcription.asrSelectionID, .remoteASR(.doubaoASR))
        XCTAssertEqual(settings.transcription.llmSelectionID, .remoteLLM(.deepseek))
        XCTAssertEqual(settings.translation.modelSelectionID, .localLLM("Qwen/Qwen3-8B-4bit"))
        XCTAssertEqual(settings.rewrite.llmSelectionID, .remoteLLM(.openAI))
    }

    func testDictionarySettingsDecoderBackfillsOptionalFields() throws {
        let json = """
        {
          "recognitionEnabled": true,
          "autoLearningEnabled": true,
          "highConfidenceCorrectionEnabled": true
        }
        """

        let decoded = try JSONDecoder().decode(
            ConfigurationTransferManager.DictionarySettings.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.suggestionFilterSettings, .defaultValue)
        XCTAssertEqual(decoded.suggestionIngestModelOptionID, "")
        XCTAssertTrue(decoded.entries.isEmpty)
        XCTAssertTrue(decoded.suggestions.isEmpty)
    }

    func testModelSettingsDecoderBackfillsWhisperFields() throws {
        let json = """
        {
          "transcriptionEngine": "mlxAudio",
          "enhancementMode": "off",
          "enhancementSystemPrompt": "",
          "translationSystemPrompt": "",
          "rewriteSystemPrompt": "",
          "mlxModelRepo": "mlx-community/Qwen3-ASR-0.6B-4bit",
          "customLLMModelRepo": "Qwen/Qwen2-1.5B-Instruct",
          "translationCustomLLMModelRepo": "Qwen/Qwen2-1.5B-Instruct",
          "rewriteCustomLLMModelRepo": "Qwen/Qwen2-1.5B-Instruct",
          "translationModelProvider": "customLLM",
          "rewriteModelProvider": "customLLM",
          "remoteASRSelectedProvider": "openAIWhisper",
          "remoteLLMSelectedProvider": "openAI",
          "translationRemoteLLMProvider": "",
          "rewriteRemoteLLMProvider": "",
          "useHfMirror": false,
          "remoteASRProviderConfigurations": [],
          "remoteLLMProviderConfigurations": []
        }
        """

        let decoded = try JSONDecoder().decode(
            ConfigurationTransferManager.ModelSettings.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.whisperModelID, WhisperKitModelManager.defaultModelID)
        XCTAssertEqual(decoded.whisperTemperature, 0.0, accuracy: 0.0001)
        XCTAssertTrue(decoded.whisperVADEnabled)
        XCTAssertFalse(decoded.whisperTimestampsEnabled)
        XCTAssertTrue(decoded.whisperRealtimeEnabled)
        XCTAssertEqual(
            WhisperLocalTuningSettingsStore.resolvedSettings(from: decoded.whisperLocalASRTuningSettings),
            WhisperLocalTuningSettings.defaults(for: .balanced)
        )
        XCTAssertEqual(decoded.mlxLocalASRTuningSettings, "{}")
        XCTAssertEqual(decoded.translationFallbackModelProvider, TranslationModelProvider.customLLM.rawValue)
    }

    func testModelSettingsDecoderCanonicalizesLegacyMLXRepo() throws {
        let json = """
        {
          "transcriptionEngine": "mlxAudio",
          "enhancementMode": "off",
          "enhancementSystemPrompt": "",
          "translationSystemPrompt": "",
          "rewriteSystemPrompt": "",
          "mlxModelRepo": "mlx-community/Parakeet-0.6B",
          "customLLMModelRepo": "Qwen/Qwen2-1.5B-Instruct",
          "translationCustomLLMModelRepo": "Qwen/Qwen2-1.5B-Instruct",
          "rewriteCustomLLMModelRepo": "Qwen/Qwen2-1.5B-Instruct",
          "translationModelProvider": "customLLM",
          "rewriteModelProvider": "customLLM",
          "remoteASRSelectedProvider": "openAIWhisper",
          "remoteLLMSelectedProvider": "openAI",
          "translationRemoteLLMProvider": "",
          "rewriteRemoteLLMProvider": "",
          "useHfMirror": false,
          "remoteASRProviderConfigurations": [],
          "remoteLLMProviderConfigurations": []
        }
        """

        let decoded = try JSONDecoder().decode(
            ConfigurationTransferManager.ModelSettings.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.mlxModelRepo, "mlx-community/parakeet-tdt-0.6b-v3")
    }
}

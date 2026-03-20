import XCTest
@testable import Voxt

final class ConfigurationTransferManagerTests: XCTestCase {
    func testExportImportRoundTripUsesIsolatedEnvironmentAndSanitizesSecrets() throws {
        let sourceDefaults = TestDoubles.makeUserDefaults()
        let sourceDirectory = try TemporaryDirectory()
        let sourceEnvironment = TestEnvironmentFactory.configurationTransferEnvironment(in: sourceDirectory)

        sourceDefaults.set(AppInterfaceLanguage.english.rawValue, forKey: AppPreferenceKey.interfaceLanguage)
        sourceDefaults.set(UserMainLanguageOption.storageValue(for: ["zh-TW", "en"]), forKey: AppPreferenceKey.userMainLanguageCodes)
        sourceDefaults.set("secret-password", forKey: AppPreferenceKey.customProxyPassword)
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
        XCTAssertEqual(targetDefaults.string(forKey: AppPreferenceKey.customProxyPassword), "")

        let importedRemote = RemoteModelConfigurationStore.loadConfigurations(
            from: targetDefaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? ""
        )
        XCTAssertEqual(importedRemote[RemoteLLMProvider.openAI.rawValue]?.apiKey, "")

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
        XCTAssertEqual(decoded.overlayCardOpacity, 82)
        XCTAssertEqual(decoded.userMainLanguageCodes, UserMainLanguageOption.defaultSelectionCodes())
        XCTAssertFalse(decoded.alwaysShowRewriteAnswerCard)
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
}

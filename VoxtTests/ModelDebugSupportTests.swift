import XCTest
@testable import Voxt

@MainActor
final class ModelDebugSupportTests: XCTestCase {
    func testLLMDebugPresetsIncludeBuiltinsAndSavedGroups() throws {
        let defaults = UserDefaults.standard
        let previousGroups = defaults.data(forKey: AppPreferenceKey.appBranchGroups)
        let previousPrompt = defaults.string(forKey: AppPreferenceKey.enhancementSystemPrompt)
        let previousLanguageCodes = defaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)

        let groups = [
            AppBranchGroup(
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                name: "Chrome",
                prompt: "Clean {{RAW_TRANSCRIPTION}} for browser work",
                appBundleIDs: ["com.google.Chrome"],
                appRefs: [AppBranchAppRef(bundleID: "com.google.Chrome", displayName: "Chrome")],
                urlPatternIDs: [],
                isExpanded: true
            )
        ]
        defaults.set(try JSONEncoder().encode(groups), forKey: AppPreferenceKey.appBranchGroups)
        defaults.set("Base {{RAW_TRANSCRIPTION}}", forKey: AppPreferenceKey.enhancementSystemPrompt)
        defaults.set("en", forKey: AppPreferenceKey.userMainLanguageCodes)
        addTeardownBlock {
            if let previousGroups {
                defaults.set(previousGroups, forKey: AppPreferenceKey.appBranchGroups)
            } else {
                defaults.removeObject(forKey: AppPreferenceKey.appBranchGroups)
            }
            if let previousPrompt {
                defaults.set(previousPrompt, forKey: AppPreferenceKey.enhancementSystemPrompt)
            } else {
                defaults.removeObject(forKey: AppPreferenceKey.enhancementSystemPrompt)
            }
            if let previousLanguageCodes {
                defaults.set(previousLanguageCodes, forKey: AppPreferenceKey.userMainLanguageCodes)
            } else {
                defaults.removeObject(forKey: AppPreferenceKey.userMainLanguageCodes)
            }
        }

        let presets = ModelDebugCatalog.availableLLMPresets(defaults: defaults)

        XCTAssertTrue(presets.contains(where: { $0.id == "builtin:enhancement" }))
        XCTAssertTrue(presets.contains(where: { $0.id == "builtin:translation" }))
        XCTAssertTrue(presets.contains(where: { $0.id == "builtin:rewrite" }))
        XCTAssertTrue(presets.contains(where: { $0.id == "builtin:meeting-summary" }))
        XCTAssertTrue(presets.contains(where: { $0.title.contains("Chrome") }))
    }

    func testPromptResolverInjectsEnhancementVariables() {
        let preset = LLMDebugPresetOption(
            id: "builtin:enhancement",
            title: "Enhancement",
            subtitle: "Built-in preset",
            kind: .enhancement,
            promptTemplate: "Clean {{RAW_TRANSCRIPTION}} for {{USER_MAIN_LANGUAGE}}",
            variables: ModelSettingsPromptVariables.enhancement,
            defaultValues: [
                AppDelegate.rawTranscriptionTemplateVariable: "",
                AppDelegate.userMainLanguageTemplateVariable: "English"
            ]
        )

        let resolved = ModelDebugPromptResolver.resolve(
            preset: preset,
            values: [
                AppDelegate.rawTranscriptionTemplateVariable: "hello world",
                AppDelegate.userMainLanguageTemplateVariable: "Chinese"
            ]
        )

        XCTAssertTrue(resolved.content.contains("hello world"))
        XCTAssertTrue(resolved.content.contains("Chinese"))
        XCTAssertEqual(resolved.inputSummary, "hello world")
    }

    func testPromptResolverInjectsMeetingSummaryVariables() {
        let preset = LLMDebugPresetOption(
            id: "builtin:meeting-summary",
            title: "Meeting Summary",
            subtitle: "Built-in preset",
            kind: .meetingSummary,
            promptTemplate: "Minutes: {{MEETING_RECORD}} | Lang: {{USER_MAIN_LANGUAGE}}",
            variables: [],
            defaultValues: [:]
        )

        let resolved = ModelDebugPromptResolver.resolve(
            preset: preset,
            values: [
                "{{MEETING_RECORD}}": "Discuss launch blockers",
                AppPreferenceKey.asrUserMainLanguageTemplateVariable: "Japanese"
            ]
        )

        XCTAssertTrue(resolved.content.contains("Discuss launch blockers"))
        XCTAssertTrue(resolved.content.contains("Japanese"))
        XCTAssertEqual(resolved.inputSummary, "Discuss launch blockers")
    }

    func testPromptResolverUsesRequestedTranslationTargetLanguage() {
        let preset = LLMDebugPresetOption(
            id: "builtin:translation",
            title: "Translation",
            subtitle: "Built-in preset",
            kind: .translation,
            promptTemplate: "Translate {{SOURCE_TEXT}} into {{TARGET_LANGUAGE}} for {{USER_MAIN_LANGUAGE}}",
            variables: ModelSettingsPromptVariables.translation,
            defaultValues: [
                "{{TARGET_LANGUAGE}}": "English",
                AppDelegate.userMainLanguageTemplateVariable: "Chinese",
                "{{SOURCE_TEXT}}": ""
            ]
        )

        let resolved = ModelDebugPromptResolver.resolve(
            preset: preset,
            values: [
                "{{TARGET_LANGUAGE}}": "Japanese",
                AppDelegate.userMainLanguageTemplateVariable: "English",
                "{{SOURCE_TEXT}}": "你好"
            ]
        )

        XCTAssertTrue(resolved.content.contains("Japanese"))
        XCTAssertTrue(resolved.content.contains("你好"))
        XCTAssertEqual(resolved.inputSummary, "你好")
    }

    func testPromptResolverUsesDictatedPromptSummaryWhenRewriteSourceIsEmpty() {
        let preset = LLMDebugPresetOption(
            id: "builtin:rewrite",
            title: "Rewrite",
            subtitle: "Built-in preset",
            kind: .rewrite,
            promptTemplate: "Rewrite {{SOURCE_TEXT}} with {{DICTATED_PROMPT}}",
            variables: ModelSettingsPromptVariables.rewrite,
            defaultValues: [:]
        )

        let resolved = ModelDebugPromptResolver.resolve(
            preset: preset,
            values: [
                "{{DICTATED_PROMPT}}": "write a short reply",
                "{{SOURCE_TEXT}}": ""
            ]
        )

        XCTAssertTrue(resolved.content.contains("write a short reply"))
        XCTAssertEqual(resolved.inputSummary, "write a short reply")
    }

    func testRemoteDebugModelCatalogFiltersUnavailableProviders() {
        let remoteASRConfigurations = [
            RemoteASRProvider.openAIWhisper.rawValue: RemoteProviderConfiguration(
                providerID: RemoteASRProvider.openAIWhisper.rawValue,
                model: "gpt-4o-mini-transcribe",
                endpoint: "",
                apiKey: "key"
            ),
            RemoteASRProvider.doubaoASR.rawValue: RemoteProviderConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: "",
                endpoint: "",
                apiKey: ""
            )
        ]
        let remoteLLMConfigurations = [
            RemoteLLMProvider.openAI.rawValue: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-4.1-mini",
                endpoint: "",
                apiKey: "key"
            ),
            RemoteLLMProvider.aliyunBailian.rawValue: RemoteProviderConfiguration(
                providerID: RemoteLLMProvider.aliyunBailian.rawValue,
                model: "",
                endpoint: "",
                apiKey: ""
            )
        ]

        let asrOptions = ModelDebugCatalog.availableASRModels(
            downloadedMLXRepos: [],
            downloadedWhisperModelIDs: [],
            remoteASRConfigurations: remoteASRConfigurations
        )
        let llmOptions = ModelDebugCatalog.availableLLMModels(
            downloadedLocalRepos: [],
            currentLocalRepo: CustomLLMModelManager.defaultModelRepo,
            remoteLLMConfigurations: remoteLLMConfigurations
        )

        XCTAssertTrue(asrOptions.contains(where: { $0.id == "remote-asr:\(RemoteASRProvider.openAIWhisper.rawValue)" }))
        XCTAssertFalse(asrOptions.contains(where: { $0.id == "remote-asr:\(RemoteASRProvider.doubaoASR.rawValue)" }))
        XCTAssertTrue(llmOptions.contains(where: { $0.id == "remote-llm:\(RemoteLLMProvider.openAI.rawValue)" }))
        XCTAssertFalse(llmOptions.contains(where: { $0.id == "remote-llm:\(RemoteLLMProvider.aliyunBailian.rawValue)" }))
    }
}

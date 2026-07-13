// AppPromptResourceStore.swift
// Provides App Prompt Resource Store for core app behavior.

import Foundation

enum AppPromptResourceStore {
    static func text(for kind: AppPromptKind, language: AppInterfaceLanguage) -> String? {
        let languageDirectory = resourceLanguageDirectory(for: language)
        let resourceName = "\(languageDirectory)-\(kind.promptResourceName)"
        let subdirectory = "Resources/Prompts/\(languageDirectory)"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt")
            ?? Bundle.main.url(
                forResource: kind.promptResourceName,
                withExtension: "txt",
                subdirectory: subdirectory
            ) else {
            return nil
        }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return text.removingSingleTrailingNewline()
    }

    static func presetText(
        for kind: AppPromptKind,
        presetID: String,
        language: AppInterfaceLanguage
    ) -> String? {
        let languageDirectory = resourceLanguageDirectory(for: language)
        let resourceName = "\(languageDirectory)-\(kind.promptResourceName)-\(presetID)"
        let subdirectory = "Resources/Prompts/\(languageDirectory)"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt")
            ?? Bundle.main.url(
                forResource: resourceName,
                withExtension: "txt",
                subdirectory: subdirectory
            ) else {
            return nil
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return text.removingSingleTrailingNewline()
    }

    private static func resourceLanguageDirectory(for language: AppInterfaceLanguage) -> String {
        switch language {
        case .english:
            return "en"
        case .chineseSimplified:
            return "zh-Hans"
        case .japanese:
            return "ja"
        case .system:
            return resourceLanguageDirectory(for: .resolvedSystemLanguage)
        }
    }
}

private extension AppPromptKind {
    var promptResourceName: String {
        switch self {
        case .enhancement:
            return "enhancement"
        case .translation:
            return "translation"
        case .rewrite:
            return "rewrite"
        case .transcriptSummary:
            return "transcript-summary"
        case .dictionaryIngest:
            return "dictionary-ingest"
        case .dictionaryAutoLearning:
            return "dictionary-auto-learning"
        case .qwenASRContextBias:
            return "qwen-asr-context-bias"
        case .openAIASRHint:
            return "openai-asr-hint"
        case .glmASRHint:
            return "glm-asr-hint"
        }
    }
}

private extension String {
    func removingSingleTrailingNewline() -> String {
        if hasSuffix("\r\n") {
            return String(dropLast(2))
        }
        if hasSuffix("\n") {
            return String(dropLast())
        }
        return self
    }
}

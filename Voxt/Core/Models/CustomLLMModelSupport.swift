// CustomLLMModelSupport.swift
// Provides Custom LLMModel Support for model catalog and storage support.

import Foundation
import HuggingFace

struct CustomLLMModelBehavior: Equatable {
    let family: CustomLLMModelFamily
    let disablesThinking: Bool

    static let thinkingOffAdditionalContext: [String: any Sendable] = [
        "enable_thinking": false,
        "reasoning_effort": "low"
    ]

    static let thinkingOnAdditionalContext: [String: any Sendable] = [
        "enable_thinking": true,
        "reasoning_effort": "medium"
    ]

    var additionalContext: [String: any Sendable]? {
        guard disablesThinking else { return nil }
        return Self.thinkingOffAdditionalContext
    }
}

enum CustomLLMModelBehaviorResolver {
    static func behavior(for repo: String) -> CustomLLMModelBehavior {
        let family = CustomLLMModelFamily.resolve(for: repo)
        return CustomLLMModelBehavior(
            family: family,
            disablesThinking: disablesThinking(for: repo, family: family)
        )
    }

    private static func disablesThinking(
        for repo: String,
        family: CustomLLMModelFamily
    ) -> Bool {
        if family == .qwen3 {
            return true
        }
        return false
    }
}

enum CustomLLMTaskKind: Equatable {
    case enhancement
    case translation
    case rewrite
    case dictionaryHistoryScan

    var logLabel: String {
        switch self {
        case .enhancement: return "enhance"
        case .translation: return "translate"
        case .rewrite: return "rewrite"
        case .dictionaryHistoryScan: return "dictionaryHistoryScan"
        }
    }

    var tokenBudgetMultiplier: Double {
        switch self {
        case .enhancement:
            return 1.10
        case .translation, .rewrite:
            return 1.35
        case .dictionaryHistoryScan:
            return 2.20
        }
    }
}

struct CustomLLMRepoSelection: Equatable {
    let requestedRepo: String
    let effectiveRepo: String

    var didFallback: Bool { requestedRepo != effectiveRepo }

    nonisolated static func resolve(
        requestedRepo: String,
        supportedRepos: [String],
        fallbackRepo: String
    ) -> CustomLLMRepoSelection {
        let effectiveRepo = isSupported(repo: requestedRepo, supportedRepos: supportedRepos)
            ? requestedRepo
            : fallbackRepo
        return CustomLLMRepoSelection(
            requestedRepo: requestedRepo,
            effectiveRepo: effectiveRepo
        )
    }

    nonisolated static func isSupported(repo: String, supportedRepos: [String]) -> Bool {
        supportedRepos.contains(repo)
    }
}

enum CustomLLMRemoteSizeCache {
    static let unknownText = "Unknown"

    static func cachedState(
        for repo: String,
        cache: [String: String]
    ) -> CustomLLMModelManager.ModelSizeState? {
        guard let cachedText = cache[repo], cachedText != unknownText else { return nil }
        return .ready(bytes: 0, text: cachedText)
    }

    static func shouldPrefetch(
        repo: String,
        cache: [String: String]
    ) -> Bool {
        cache[repo] == nil
    }

    static func updatedCache(
        _ cache: [String: String],
        repo: String,
        text: String
    ) -> [String: String] {
        var updated = cache
        updated[repo] = text
        return updated
    }
}

struct CustomLLMLogSection: Equatable {
    let label: String
    let content: String
}

enum CustomLLMContainerLoadSource: String, Equatable {
    case reusedLoaded
    case loadedFromDisk
}

struct CustomLLMRunDiagnostics: Equatable {
    let repo: String
    let taskLabel: String
    let containerLoadSource: CustomLLMContainerLoadSource
    let containerLoadMs: Int
    let setupMs: Int
    let modelElapsedMs: Int
    let totalElapsedMs: Int
    let firstChunkMs: Int?
    let overallFirstChunkMs: Int?
    let promptTokens: Int?
    let completionTokens: Int?
    let prefillMs: Int?
    let generationMs: Int?
    let modelOverheadMs: Int?
    let totalOverheadMs: Int?
}

struct CustomLLMGenerationTuning: Equatable {
    let prefillStepSizeOverride: Int?
    let maxTokensOverride: Int?

    static let `default` = CustomLLMGenerationTuning(prefillStepSizeOverride: nil, maxTokensOverride: nil)
}

struct LLMOutputRepetition: Equatable {
    let repeatedUnit: String
    let repetitionCount: Int
    let truncatedText: String
}

struct LLMOutputRepetitionGuard {
    var maximumUnitLength = 48
    var minimumRepetitionCount = 6
    var minimumRunCharacterCount = 48
    var shortUnitMinimumRepetitionCount = 10
    var shortUnitMinimumRunCharacterCount = 24

    func repeatedSuffix(in text: String) -> LLMOutputRepetition? {
        let characterCount = text.count
        guard characterCount >= shortUnitMinimumRunCharacterCount else { return nil }

        let longestUnit = min(maximumUnitLength, characterCount / minimumRepetitionCount)
        guard longestUnit > 0 else { return nil }

        for unitLength in 1...longestUnit {
            guard let unitStart = text.index(text.endIndex, offsetBy: -unitLength, limitedBy: text.startIndex) else {
                continue
            }
            let unit = String(text[unitStart...])
            guard !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            var repetitions = 1
            var runStart = unitStart
            while let previousStart = text.index(runStart, offsetBy: -unitLength, limitedBy: text.startIndex),
                  text[previousStart..<runStart] == text[unitStart..<text.endIndex] {
                repetitions += 1
                runStart = previousStart
            }

            let runCharacterCount = repetitions * unitLength
            let isShortUnitRun = unitLength <= 4 &&
                repetitions >= shortUnitMinimumRepetitionCount &&
                runCharacterCount >= shortUnitMinimumRunCharacterCount
            let isGeneralRun = repetitions >= minimumRepetitionCount &&
                runCharacterCount >= minimumRunCharacterCount

            guard isShortUnitRun || isGeneralRun else { continue }

            let keepEnd = text.index(text.endIndex, offsetBy: -unitLength * (repetitions - 1))
            return LLMOutputRepetition(
                repeatedUnit: unit,
                repetitionCount: repetitions,
                truncatedText: String(text[..<keepEnd])
            )
        }

        return nil
    }
}

struct CustomLLMRequestPlan: Equatable {
    let kind: CustomLLMTaskKind
    let repo: String
    let instructions: String
    let prompt: String
    let inputCharacterCount: Int
    let maxTokensOverride: Int?
    let attachments: [LLMInputAttachment]
    let conversationHistory: [RewriteConversationPromptTurn]
    let logMode: String?
    let contentLogSections: [CustomLLMLogSection]
    let resultFallback: String
    let responseExtractionMode: CustomLLMResponseExtractionMode
}

enum CustomLLMResponseExtractionMode: Equatable {
    case textResultPayloadOrNormalizedText
    case normalizedRawText
}

enum CustomLLMRequestPlanBuilder {
    static func compiled(
        request: LLMCompiledRequest,
        repo: String
    ) -> CustomLLMRequestPlan {
        let kind: CustomLLMTaskKind
        switch request.taskLabel {
        case "enhancement":
            kind = .enhancement
        case "translation":
            kind = .translation
        case "rewrite":
            kind = .rewrite
        default:
            kind = .enhancement
        }

        let usesUserMessageMode = request.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var sections: [CustomLLMLogSection] = [
            CustomLLMLogSection(
                label: "system_prompt",
                content: usesUserMessageMode ? "<empty>" : request.instructions
            ),
            CustomLLMLogSection(label: "input", content: request.debugInput)
        ]
        sections.append(
            CustomLLMLogSection(
                label: usesUserMessageMode ? "user_message_prompt" : "request_content",
                content: request.prompt
            )
        )

        return CustomLLMRequestPlan(
            kind: kind,
            repo: repo,
            instructions: request.instructions,
            prompt: request.prompt,
            inputCharacterCount: request.inputCharacterCount,
            maxTokensOverride: request.outputTokenBudgetHint,
            attachments: request.attachments,
            conversationHistory: request.conversationHistory,
            logMode: usesUserMessageMode ? "userMessage" : nil,
            contentLogSections: sections,
            resultFallback: request.fallbackText,
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func enhancement(
        input: String,
        systemPrompt: String,
        repo: String,
        resultFallback: String,
        structuredOutputPrompt: (String, String) -> String
    ) -> CustomLLMRequestPlan {
        let prompt = structuredOutputPrompt(
            "Clean up this transcription while preserving meaning and style.",
            input
        )
        return CustomLLMRequestPlan(
            kind: .enhancement,
            repo: repo,
            instructions: systemPrompt,
            prompt: prompt,
            inputCharacterCount: input.count,
            maxTokensOverride: nil,
            attachments: [],
            conversationHistory: [],
            logMode: nil,
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: systemPrompt),
                CustomLLMLogSection(label: "input", content: input),
                CustomLLMLogSection(label: "request_content", content: prompt)
            ],
            resultFallback: resultFallback,
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func userPromptEnhancement(
        prompt: String,
        repo: String
    ) -> CustomLLMRequestPlan {
        CustomLLMRequestPlan(
            kind: .enhancement,
            repo: repo,
            instructions: "",
            prompt: prompt,
            inputCharacterCount: prompt.count,
            maxTokensOverride: nil,
            attachments: [],
            conversationHistory: [],
            logMode: "userMessage",
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: "<empty>"),
                CustomLLMLogSection(label: "input", content: prompt)
            ],
            resultFallback: "",
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func translation(
        text: String,
        instructions: String,
        repo: String,
        structuredOutputPrompt: (String, String) -> String
    ) -> CustomLLMRequestPlan {
        let prompt = structuredOutputPrompt(
            "Process the input according to the instructions.",
            text
        )
        return CustomLLMRequestPlan(
            kind: .translation,
            repo: repo,
            instructions: instructions,
            prompt: prompt,
            inputCharacterCount: text.count,
            maxTokensOverride: nil,
            attachments: [],
            conversationHistory: [],
            logMode: nil,
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: instructions),
                CustomLLMLogSection(label: "input", content: text),
                CustomLLMLogSection(label: "request_content", content: prompt)
            ],
            resultFallback: "",
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func userPromptTranslation(
        prompt: String,
        repo: String,
        resultFallback: String
    ) -> CustomLLMRequestPlan {
        CustomLLMRequestPlan(
            kind: .translation,
            repo: repo,
            instructions: "",
            prompt: prompt,
            inputCharacterCount: prompt.count,
            maxTokensOverride: nil,
            attachments: [],
            conversationHistory: [],
            logMode: "userMessage",
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: "<empty>"),
                CustomLLMLogSection(label: "input", content: prompt)
            ],
            resultFallback: resultFallback,
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func rewrite(
        sourceText: String,
        dictatedPrompt: String,
        instructions: String,
        repo: String,
        structuredOutputPrompt: (String, String) -> String
    ) -> CustomLLMRequestPlan {
        let combinedInput = """
        Spoken instruction:
        \(dictatedPrompt)

        Selected source text:
        \(sourceText)
        """
        let prompt = structuredOutputPrompt(
            "Produce the final text to insert according to the instructions.",
            combinedInput
        )
        return CustomLLMRequestPlan(
            kind: .rewrite,
            repo: repo,
            instructions: instructions,
            prompt: prompt,
            inputCharacterCount: combinedInput.count,
            maxTokensOverride: nil,
            attachments: [],
            conversationHistory: [],
            logMode: nil,
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: instructions),
                CustomLLMLogSection(label: "input", content: combinedInput),
                CustomLLMLogSection(label: "request_content", content: prompt)
            ],
            resultFallback: "",
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func userPromptRewrite(
        prompt: String,
        repo: String,
        resultFallback: String
    ) -> CustomLLMRequestPlan {
        CustomLLMRequestPlan(
            kind: .rewrite,
            repo: repo,
            instructions: "",
            prompt: prompt,
            inputCharacterCount: prompt.count,
            maxTokensOverride: nil,
            attachments: [],
            conversationHistory: [],
            logMode: "userMessage",
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: "<empty>"),
                CustomLLMLogSection(label: "input", content: prompt)
            ],
            resultFallback: resultFallback,
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func dictionaryHistoryScan(
        prompt: String,
        repo: String,
        structuredOutputPrompt: (String) -> String
    ) -> CustomLLMRequestPlan {
        let requestPrompt = structuredOutputPrompt(prompt)
        return CustomLLMRequestPlan(
            kind: .dictionaryHistoryScan,
            repo: repo,
            instructions: "",
            prompt: requestPrompt,
            inputCharacterCount: prompt.count,
            maxTokensOverride: nil,
            attachments: [],
            conversationHistory: [],
            logMode: "dictionaryHistoryScan",
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: "<empty>"),
                CustomLLMLogSection(label: "input", content: prompt),
                CustomLLMLogSection(label: "request_content", content: requestPrompt)
            ],
            resultFallback: "[]",
            responseExtractionMode: .normalizedRawText
        )
    }
}

enum CustomLLMModelFamily: Equatable {
    case qwen2
    case qwen3
    case glm4
    case llama
    case mistral
    case gemma
    case other

    var logLabel: String {
        switch self {
        case .qwen2: return "qwen2"
        case .qwen3: return "qwen3"
        case .glm4: return "glm4"
        case .llama: return "llama"
        case .mistral: return "mistral"
        case .gemma: return "gemma"
        case .other: return "other"
        }
    }

    static func resolve(for repo: String) -> CustomLLMModelFamily {
        let normalizedRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRepo.contains("qwen3") { return .qwen3 }
        if normalizedRepo.contains("qwen2") { return .qwen2 }
        if normalizedRepo.contains("glm-4") || normalizedRepo.contains("glm4") {
            return .glm4
        }
        if normalizedRepo.contains("llama") { return .llama }
        if normalizedRepo.contains("mistral") || normalizedRepo.contains("ministral") { return .mistral }
        if normalizedRepo.contains("gemma") { return .gemma }
        return .other
    }
}

enum CustomLLMOutputSanitizer {
    static func normalizeResultText(_ output: String) -> String {
        LLMVisibleOutputSanitizer.sanitize(
            output,
            fallbackText: "",
            taskKind: .generic
        ).text
    }

    static func unwrapCodeFenceIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
            return trimmed
        }
        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return trimmed }
        lines.removeFirst()
        if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

struct CustomLLMModelCatalog {
    enum Visibility: String, Hashable {
        case visible
        case hiddenSupport
    }

    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let description: String
        let visibility: Visibility
    }

    private struct PresentationMetadata {
        let ratingText: String
        let tagKeys: [String]
    }

    nonisolated static let defaultModelRepo = "mlx-community/Qwen3.5-4B-OptiQ-4bit"

    nonisolated private static let compatibilityAliases: [String: String] = [
        "Qwen/Qwen3-8B-4bit": "mlx-community/Qwen3-8B-4bit",
        "Qwen/Qwen2.5-7B-Instruct": "mlx-community/Qwen2.5-7B-Instruct-4bit",
        "mlx-community/Qwen3.5-2B-MLX-4bit": "mlx-community/Qwen3.5-2B-4bit",
        "mlx-community/Qwen3.5-0.8B-4bit-OptiQ": "mlx-community/Qwen3.5-0.8B-OptiQ-4bit",
    ]

    nonisolated private static let visibleModels: [Option] = [
        Option(
            id: "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit",
            title: "Qwen3 VL 4B Instruct (4bit)",
            description: "Recommended Qwen3 multimodal model for local app screenshots and text context.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/Qwen3.5-2B-4bit",
            title: "Qwen3.5 2B (4bit)",
            description: "Official Qwen3.5 local model using the upstream-supported inference path.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/Qwen3.5-4B-OptiQ-4bit",
            title: "Qwen3.5 4B OptiQ (4bit)",
            description: "Mixed-precision Qwen3.5 variant tuned for a stronger quality-to-size balance on home Macs.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/Qwen3.5-9B-OptiQ-4bit",
            title: "Qwen3.5 9B OptiQ (4bit)",
            description: "Higher-quality Qwen3.5 option for higher-memory Macs using Apple-Silicon-optimized mixed precision.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/GLM-4-9B-0414-4bit",
            title: "GLM 4 9B",
            description: "GLM-4 model variant with strong multilingual instruction following.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/Ministral-3-3B-Instruct-2512-4bit",
            title: "Mistral 3 3B",
            description: "Current compact Mistral-family model for lightweight non-Qwen local generation.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/LFM2-1.2B-4bit",
            title: "LFM2 1.2B (4bit)",
            description: "Very lightweight LFM2 model for low-memory local generation.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/LFM2-8B-A1B-3bit-MLX",
            title: "LFM2 8B A1B (3bit)",
            description: "Compact LFM2 MoE model with a small active-parameter footprint.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/Qwen3.6-27B-4bit",
            title: "Qwen3.6 27B (4bit)",
            description: "High-end Qwen3.6 model for large-memory Macs and stronger local quality.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/gemma-4-e2b-it-4bit",
            title: "Gemma 4 E2B IT (4bit)",
            description: "Official Gemma 4 compact multimodal model that can use both text and image context.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            title: "Gemma 4 E4B IT (4bit)",
            description: "Higher-capacity Gemma 4 multimodal option for stronger local text-and-image generation quality.",
            visibility: .visible
        ),
        Option(
            id: "mlx-community/gemma-4-12B-it-OptiQ-4bit",
            title: "Gemma 4 12B IT OptiQ (4bit)",
            description: "High-end Gemma 4 unified multimodal model for stronger local quality on higher-memory Macs.",
            visibility: .visible
        ),
    ]

    nonisolated private static let hiddenSupportModels: [Option] = [
        Option(
            id: "Qwen/Qwen2-1.5B-Instruct",
            title: "Qwen2 1.5B Instruct",
            description: "Compatibility-only Qwen2 model preserved for existing selections.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "Qwen/Qwen2.5-3B-Instruct",
            title: "Qwen2.5 3B Instruct",
            description: "Compatibility-only Qwen2.5 model preserved for existing selections.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit",
            title: "Qwen2.5 VL 3B Instruct (4bit)",
            description: "Compatibility-only Qwen2.5 vision-language model hidden behind the Qwen3 VL entry.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            title: "Qwen2.5 7B Instruct (4bit)",
            description: "Compatibility-only official Qwen2.5 model preserved for existing selections.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-0.6B-4bit",
            title: "Qwen3 0.6B (4bit)",
            description: "Compatibility-only Qwen3 model hidden behind the Qwen3.5 lineup.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-1.7B-4bit",
            title: "Qwen3 1.7B (4bit)",
            description: "Compatibility-only Qwen3 model hidden behind the Qwen3.5 lineup.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-4B-4bit",
            title: "Qwen3 4B (4bit)",
            description: "Compatibility-only Qwen3 model hidden behind the Qwen3.5 4B entry.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-8B-4bit",
            title: "Qwen3 8B (4bit)",
            description: "Compatibility-only Qwen3 model hidden behind the Qwen3.5 9B entry.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3.5-4B-4bit",
            title: "Qwen3.5 4B (4bit)",
            description: "Compatibility-only plain 4bit Qwen3.5 4B variant hidden behind the OptiQ default.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3.5-0.8B-OptiQ-4bit",
            title: "Qwen3.5 0.8B OptiQ (4bit)",
            description: "Compatibility-only ultra-light Qwen3.5 model hidden behind the Qwen3.5 2B entry.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/gemma-2-2b-it-4bit",
            title: "Gemma 2 2B IT (4bit)",
            description: "Compatibility-only Gemma 2 model preserved for existing selections.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/gemma-2-9b-it-4bit",
            title: "Gemma 2 9B IT (4bit)",
            description: "Compatibility-only Gemma 2 model preserved for existing selections.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/gemma-3-1b-it-qat-4bit",
            title: "Gemma 3 1B IT QAT (4bit)",
            description: "Compatibility-only Gemma 3 model hidden behind the current Gemma 4 lineup.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/gemma-3n-E2B-it-lm-4bit",
            title: "Gemma 3n E2B IT LM (4bit)",
            description: "Compatibility-only Gemma 3n model hidden behind the current Gemma 4 lineup.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/gemma-3n-E4B-it-lm-4bit",
            title: "Gemma 3n E4B IT LM (4bit)",
            description: "Compatibility-only Gemma 3n model hidden behind the current Gemma 4 lineup.",
            visibility: .hiddenSupport
        ),
        Option(
            id: "mlx-community/Qwen3-30B-A3B-4bit",
            title: "Qwen3 30B A3B (4bit)",
            description: "Compatibility-only Qwen3 MoE model hidden from the main picker because its download size is too large for most home Macs.",
            visibility: .hiddenSupport
        ),
    ]

    nonisolated private static let allModels: [Option] = visibleModels + hiddenSupportModels

    nonisolated static let availableModels: [Option] = allModels.filter { $0.visibility == .visible }

    nonisolated static let supportedModels: [Option] = allModels

    nonisolated private static let presentationByRepo: [String: PresentationMetadata] = [
        "Qwen/Qwen2-1.5B-Instruct": PresentationMetadata(ratingText: "4.0", tagKeys: ["Fast"]),
        "Qwen/Qwen2.5-3B-Instruct": PresentationMetadata(ratingText: "4.3", tagKeys: ["Balanced"]),
        "mlx-community/Qwen2.5-VL-3B-Instruct-4bit": PresentationMetadata(ratingText: "4.5", tagKeys: ["Balanced", "Vision"]),
        "mlx-community/Qwen3-0.6B-4bit": PresentationMetadata(ratingText: "4.0", tagKeys: ["Fast"]),
        "mlx-community/Qwen3-1.7B-4bit": PresentationMetadata(ratingText: "4.2", tagKeys: ["Fast"]),
        "mlx-community/Qwen3-4B-4bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3-8B-4bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Accurate"]),
        "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Balanced", "Vision"]),
        "mlx-community/Qwen3.5-4B-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3.5-0.8B-OptiQ-4bit": PresentationMetadata(ratingText: "4.1", tagKeys: ["Fast"]),
        "mlx-community/Qwen3.5-4B-OptiQ-4bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3.5-9B-OptiQ-4bit": PresentationMetadata(ratingText: "4.9", tagKeys: ["Accurate"]),
        "mlx-community/GLM-4-9B-0414-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Accurate"]),
        "mlx-community/Ministral-3-3B-Instruct-2512-4bit": PresentationMetadata(ratingText: "4.5", tagKeys: ["Balanced", "Vision"]),
        "mlx-community/gemma-2-2b-it-4bit": PresentationMetadata(ratingText: "4.1", tagKeys: ["Fast"]),
        "mlx-community/gemma-2-9b-it-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Accurate"]),
        "mlx-community/gemma-4-e2b-it-4bit": PresentationMetadata(ratingText: "4.3", tagKeys: ["Fast", "Vision"]),
        "mlx-community/gemma-4-e4b-it-4bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Balanced", "Vision"]),
        "mlx-community/gemma-4-12B-it-OptiQ-4bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Accurate", "Vision"]),
        "mlx-community/gemma-3-1b-it-qat-4bit": PresentationMetadata(ratingText: "4.0", tagKeys: ["Fast"]),
        "mlx-community/gemma-3n-E2B-it-lm-4bit": PresentationMetadata(ratingText: "4.2", tagKeys: ["Fast"]),
        "mlx-community/gemma-3n-E4B-it-lm-4bit": PresentationMetadata(ratingText: "4.4", tagKeys: ["Balanced"]),
        "mlx-community/Qwen2.5-7B-Instruct-4bit": PresentationMetadata(ratingText: "4.5", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3-30B-A3B-4bit": PresentationMetadata(ratingText: "4.9", tagKeys: ["Accurate"]),
        "mlx-community/LFM2-1.2B-4bit": PresentationMetadata(ratingText: "4.0", tagKeys: ["Fast"]),
        "mlx-community/LFM2-8B-A1B-3bit-MLX": PresentationMetadata(ratingText: "4.4", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3.6-27B-4bit": PresentationMetadata(ratingText: "4.9", tagKeys: ["Accurate"]),
    ]

    nonisolated private static let knownRemoteSizeBytesByRepo: [String: Int64] = [
        "Qwen/Qwen2-1.5B-Instruct": 3_098_962_420,
        "Qwen/Qwen2.5-3B-Instruct": 6_183_464_935,
        "mlx-community/Qwen2.5-VL-3B-Instruct-4bit": 3_900_000_000,
        "mlx-community/Qwen2.5-7B-Instruct-4bit": 4_284_346_255,
        "mlx-community/Qwen3-0.6B-4bit": 682_323_786,
        "mlx-community/Qwen3-1.7B-4bit": 979_502_864,
        "mlx-community/Qwen3-4B-4bit": 2_278_972_183,
        "mlx-community/Qwen3-8B-4bit": 4_623_784_971,
        "mlx-community/Qwen3-30B-A3B-4bit": 17_186_203_322,
        "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit": 4_900_000_000,
        "mlx-community/Qwen3.5-0.8B-OptiQ-4bit": 886_118_292,
        "mlx-community/Qwen3.5-2B-4bit": 1_742_261_128,
        "mlx-community/Qwen3.5-4B-4bit": 3_060_000_000,
        "mlx-community/Qwen3.5-4B-OptiQ-4bit": 2_970_000_000,
        "mlx-community/Qwen3.5-9B-OptiQ-4bit": 6_040_000_000,
        "mlx-community/GLM-4-9B-0414-4bit": 5_309_031_270,
        "mlx-community/Ministral-3-3B-Instruct-2512-4bit": 2_745_210_934,
        "mlx-community/gemma-2-2b-it-4bit": 1_492_852_888,
        "mlx-community/gemma-2-9b-it-4bit": 5_217_089_310,
        "mlx-community/gemma-3-1b-it-qat-4bit": 732_577_304,
        "mlx-community/gemma-3n-E2B-it-lm-4bit": 2_507_515_399,
        "mlx-community/gemma-3n-E4B-it-lm-4bit": 3_863_598_176,
        "mlx-community/gemma-4-e2b-it-4bit": 3_581_101_896,
        "mlx-community/gemma-4-e4b-it-4bit": 5_217_361_182,
        "mlx-community/gemma-4-12B-it-OptiQ-4bit": 8_964_644_918,
        "mlx-community/LFM2-1.2B-4bit": 663_392_070,
        "mlx-community/LFM2-8B-A1B-3bit-MLX": 4_176_559_875,
        "mlx-community/Qwen3.6-27B-4bit": 16_081_490_064,
    ]

    nonisolated static func canonicalModelRepo(_ repo: String) -> String {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultModelRepo }
        return compatibilityAliases[trimmed] ?? trimmed
    }

    nonisolated static func option(for repo: String) -> Option? {
        let canonicalRepo = canonicalModelRepo(repo)
        return supportedModels.first(where: { $0.id == canonicalRepo })
    }

    nonisolated static func displayModels(including repo: String? = nil) -> [Option] {
        guard let repo else { return availableModels }
        return displayModels(includingInstalled: [repo])
    }

    nonisolated static func displayModels(includingInstalled repos: Set<String>) -> [Option] {
        let canonicalRepos = Set(repos.map(canonicalModelRepo))
        return supportedModels.filter { option in
            option.visibility == .visible || canonicalRepos.contains(canonicalModelRepo(option.id))
        }
    }

    nonisolated static func displayTitle(for repo: String) -> String {
        option(for: repo)?.title ?? repo
    }

    nonisolated static func description(for repo: String) -> String? {
        option(for: repo)?.description
    }

    nonisolated static func ratingText(for repo: String) -> String {
        presentationByRepo[canonicalModelRepo(repo)]?.ratingText ?? "4.0"
    }

    nonisolated static func catalogTagKeys(for repo: String) -> [String] {
        presentationByRepo[canonicalModelRepo(repo)]?.tagKeys ?? []
    }

    nonisolated static func isSupportedModelRepo(_ repo: String) -> Bool {
        option(for: repo) != nil
    }

    nonisolated static func supportsImageInput(repo: String) -> Bool {
        let normalized = canonicalModelRepo(repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        if normalized.contains("qwen2-vl")
            || normalized.contains("qwen2.5-vl")
            || normalized.contains("qwen3-vl")
            || normalized.contains("paligemma")
            || normalized.contains("pixtral")
            || normalized.contains("idefics")
            || normalized.contains("smolvlm")
            || normalized.contains("fastvlm")
            || normalized.contains("llava")
            || normalized.contains("lfm2-vl")
            || normalized.contains("lfm2.5-vl")
            || normalized.contains("glm-ocr")
            || normalized.contains("qvq")
            || normalized.contains("minicpm-v") {
            return true
        }

        if normalized.contains("gemma-3-") || normalized.contains("gemma-4-") {
            return true
        }

        if normalized.contains("ministral-3") || normalized.contains("mistral-3") {
            return true
        }

        return false
    }

    nonisolated static func fallbackRemoteSizeText(repo: String) -> String? {
        fallbackRemoteSizeInfo(repo: repo)?.text
    }

    nonisolated static func fallbackRemoteSizeInfo(repo: String) -> (bytes: Int64, text: String)? {
        guard let bytes = knownRemoteSizeBytesByRepo[canonicalModelRepo(repo)] else { return nil }
        return (bytes, CustomLLMModelStorageSupport.formatByteCount(bytes))
    }
}

enum CustomLLMModelStorageSupport {
    nonisolated private static let remoteSizeCachePreferenceKey = "customLLMRemoteSizeCache"

    nonisolated static func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    nonisolated static func loadPersistedRemoteSizeCache() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: remoteSizeCachePreferenceKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    nonisolated static func savePersistedRemoteSizeCache(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: remoteSizeCachePreferenceKey)
    }

    nonisolated static func destinationFileURL(for entryPath: String, under directory: URL) throws -> URL {
        let base = directory.standardizedFileURL
        let destination = base.appendingPathComponent(entryPath).standardizedFileURL
        let basePrefix = base.path.hasSuffix("/") ? base.path : "\(base.path)/"
        guard destination.path.hasPrefix(basePrefix) else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model file path: \(entryPath)"]
            )
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return destination
    }

    nonisolated static func cacheDirectory(for repo: String, rootDirectory: URL) -> URL? {
        guard let repoID = Repo.ID(rawValue: repo) else { return nil }
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        return rootDirectory
            .appendingPathComponent("mlx-llm")
            .appendingPathComponent(modelSubdir)
    }

    nonisolated static func isModelDirectoryValid(_ directory: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        let rootConfig = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: rootConfig.path),
              let rootConfigData = try? Data(contentsOf: rootConfig),
              (try? JSONSerialization.jsonObject(with: rootConfigData)) != nil
        else {
            return false
        }

        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return false
        }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "safetensors" {
            return true
        }
        return false
    }

    nonisolated static func clearHubCache(for repoID: Repo.ID, rootDirectory: URL = HubCache.default.cacheDirectory) {
        let cache = HubCache(cacheDirectory: rootDirectory)
        let repoDir = cache.repoDirectory(repo: repoID, kind: .model)
        let metadataDir = cache.metadataDirectory(repo: repoID, kind: .model)
        try? FileManager.default.removeItem(at: repoDir)
        try? FileManager.default.removeItem(at: metadataDir)
    }
}

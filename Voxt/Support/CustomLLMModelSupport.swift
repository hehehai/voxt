import Foundation
import HuggingFace

struct CustomLLMModelBehavior: Equatable {
    let family: CustomLLMModelFamily
    let disablesThinking: Bool

    var additionalContext: [String: any Sendable]? {
        guard disablesThinking else { return nil }
        return ["enable_thinking": false]
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
        let normalizedRepo = repo.lowercased()
        if family == .qwen3 {
            return true
        }
        if normalizedRepo.contains("glm-z1") || normalizedRepo.contains("glmz1") {
            return true
        }
        if normalizedRepo.contains("acereason") {
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

struct CustomLLMRequestPlan: Equatable {
    let kind: CustomLLMTaskKind
    let repo: String
    let instructions: String
    let prompt: String
    let inputCharacterCount: Int
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
        if normalizedRepo.contains("glm-4")
            || normalizedRepo.contains("glm4")
            || normalizedRepo.contains("glm-z1")
            || normalizedRepo.contains("glmz1") {
            return .glm4
        }
        if normalizedRepo.contains("llama") { return .llama }
        if normalizedRepo.contains("mistral") { return .mistral }
        if normalizedRepo.contains("gemma") { return .gemma }
        return .other
    }
}

enum CustomLLMOutputSanitizer {
    static func normalizeResultText(_ output: String) -> String {
        var cleaned = output
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: (cleaned as NSString).length)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        cleaned = unwrapCodeFenceIfNeeded(cleaned)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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
        case hiddenCompat
    }

    enum ReleaseStatus: String, Hashable {
        case standard
        case new
        case deprecatedSoon
    }

    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let description: String
        let visibility: Visibility
        let releaseStatus: ReleaseStatus
    }

    private struct PresentationMetadata {
        let ratingText: String
        let tagKeys: [String]
    }

    nonisolated static let defaultModelRepo = "Qwen/Qwen2-1.5B-Instruct"

    nonisolated private static let compatibilityAliases: [String: String] = [
        "Qwen/Qwen3-8B-4bit": "mlx-community/Qwen3-8B-4bit",
        "Qwen/Qwen2.5-7B-Instruct": "mlx-community/Qwen2.5-7B-Instruct-4bit",
        "mlx-community/Qwen3.5-2B-MLX-4bit": "mlx-community/Qwen3.5-2B-4bit",
    ]

    nonisolated private static let deprecatedSoonRepos: Set<String> = []

    nonisolated private static let visibleModels: [Option] = [
        Option(
            id: "Qwen/Qwen2-1.5B-Instruct",
            title: "Qwen2 1.5B Instruct",
            description: "General-purpose instruction model for prompt-based text cleanup.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "Qwen/Qwen2.5-3B-Instruct",
            title: "Qwen2.5 3B Instruct",
            description: "Larger instruction model with stronger reasoning and formatting quality.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/Qwen3-0.6B-4bit",
            title: "Qwen3 0.6B (4bit)",
            description: "Smallest official Qwen3 local model for fast low-memory prompts.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/Qwen3-1.7B-4bit",
            title: "Qwen3 1.7B (4bit)",
            description: "Compact Qwen3 model with better quality than 0.6B while staying lightweight.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/Qwen3-4B-4bit",
            title: "Qwen3 4B (4bit)",
            description: "Balanced Qwen3 model for quality and performance.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/Qwen3-8B-4bit",
            title: "Qwen3 8B (4bit)",
            description: "Higher-quality Qwen3 model for stronger enhancement results.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/Qwen3.5-2B-4bit",
            title: "Qwen3.5 2B (4bit)",
            description: "Official Qwen3.5 local model using the upstream-supported inference path.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/Qwen3.5-4B-4bit",
            title: "Qwen3.5 4B (4bit)",
            description: "Recommended Qwen3.5 upgrade for most home Macs with a strong quality-to-size balance.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/Qwen3.5-0.8B-4bit-OptiQ",
            title: "Qwen3.5 0.8B OptiQ (4bit)",
            description: "Ultra-light Qwen3.5 option for low-storage Macs that still benefits from mixed-precision OptiQ quantization.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/Qwen3.5-4B-OptiQ-4bit",
            title: "Qwen3.5 4B OptiQ (4bit)",
            description: "Mixed-precision Qwen3.5 variant tuned for a stronger quality-to-size balance on home Macs.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/Qwen3.5-9B-OptiQ-4bit",
            title: "Qwen3.5 9B OptiQ (4bit)",
            description: "Higher-quality Qwen3.5 option for higher-memory Macs using Apple-Silicon-optimized mixed precision.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/GLM-4-9B-0414-4bit",
            title: "GLM-4 9B (4bit)",
            description: "GLM-4 model variant with strong multilingual instruction following.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/glm-4-9b-chat-1m-4bit",
            title: "GLM-4 9B Chat 1M (4bit)",
            description: "Long-context GLM option that stays within home-Mac-friendly download size limits.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/GLM-Z1-9B-0414-4bit",
            title: "GLM-Z1 9B (4bit)",
            description: "Reasoning-oriented GLM variant that keeps bilingual quality while staying under the home-Mac size target.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            title: "Llama 3.2 3B Instruct (4bit)",
            description: "Lightweight Llama 3.2 model for fast local enhancement.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            title: "Llama 3.2 1B Instruct (4bit)",
            description: "Smallest Llama 3.2 option with minimal memory footprint.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/Meta-Llama-3-8B-Instruct-4bit",
            title: "Meta Llama 3 8B Instruct (4bit)",
            description: "General-purpose 8B instruction model with strong quality.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            title: "Meta Llama 3.1 8B Instruct (4bit)",
            description: "Refined 8B Llama 3.1 instruction model.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            title: "Mistral 7B Instruct v0.3 (4bit)",
            description: "Reliable 7B instruction model for concise formatting tasks.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/Mistral-Nemo-Instruct-2407-4bit",
            title: "Mistral Nemo Instruct 2407 (4bit)",
            description: "Nemo-based Mistral model with improved instruction quality.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/gemma-2-2b-it-4bit",
            title: "Gemma 2 2B IT (4bit)",
            description: "Compact Gemma 2 instruction-tuned model.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/gemma-2-9b-it-4bit",
            title: "Gemma 2 9B IT (4bit)",
            description: "Higher-capacity Gemma 2 model for better quality output.",
            visibility: .visible,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/gemma-4-e2b-it-4bit",
            title: "Gemma 4 E2B IT (4bit)",
            description: "Official Gemma 4 compact text model with stronger newer prompting behavior.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            title: "Gemma 4 E4B IT (4bit)",
            description: "Higher-capacity Gemma 4 option for stronger local text generation quality.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            title: "Phi 3.5 Mini Instruct (4bit)",
            description: "Compact Phi 3.5 model suitable for lightweight local generation tasks.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/Phi-3.5-MoE-instruct-4bit",
            title: "Phi 3.5 MoE Instruct (4bit)",
            description: "Phi 3.5 MoE model with stronger quality when more memory is available.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/internlm2_5-7b-chat-4bit",
            title: "InternLM2.5 7B Chat (4bit)",
            description: "Chinese-friendly 7B chat model that adds a strong new bilingual option for home Macs.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/MiniCPM4-8B-4bit",
            title: "MiniCPM4 8B (4bit)",
            description: "Recommended MiniCPM family model with practical size and strong bilingual general-purpose quality.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/granite-3.3-2b-instruct-4bit",
            title: "Granite 3.3 2B Instruct (4bit)",
            description: "Compact IBM Granite model for structured local text generation.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/MiMo-7B-SFT-4bit",
            title: "MiMo 7B SFT (4bit)",
            description: "MiMo family model newly supported by upstream MLX Swift LM.",
            visibility: .visible,
            releaseStatus: .new
        ),
        Option(
            id: "mlx-community/AceReason-Nemotron-7B-4bit",
            title: "AceReason Nemotron 7B (4bit)",
            description: "Nemotron-based reasoning model now available in the official upstream path.",
            visibility: .visible,
            releaseStatus: .new
        ),
    ]

    nonisolated private static let hiddenCompatibilityModels: [Option] = [
        Option(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            title: "Qwen2.5 7B Instruct (4bit)",
            description: "Compatibility-only official Qwen2.5 model preserved for existing selections.",
            visibility: .hiddenCompat,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/Qwen3-30B-A3B-4bit",
            title: "Qwen3 30B A3B (4bit)",
            description: "Compatibility-only Qwen3 MoE model hidden from the main picker because its download size is too large for most home Macs.",
            visibility: .hiddenCompat,
            releaseStatus: .standard
        ),
        Option(
            id: "mlx-community/GLM-4.7-Flash-4bit",
            title: "GLM-4.7 Flash (4bit)",
            description: "Compatibility-only GLM model hidden from the main picker because its download size is too large for most home Macs.",
            visibility: .hiddenCompat,
            releaseStatus: .standard
        ),
    ]

    nonisolated static let availableModels: [Option] = visibleModels

    nonisolated static let supportedModels: [Option] = visibleModels + hiddenCompatibilityModels

    nonisolated private static let presentationByRepo: [String: PresentationMetadata] = [
        "Qwen/Qwen2-1.5B-Instruct": PresentationMetadata(ratingText: "4.0", tagKeys: ["Fast"]),
        "Qwen/Qwen2.5-3B-Instruct": PresentationMetadata(ratingText: "4.3", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3-0.6B-4bit": PresentationMetadata(ratingText: "4.0", tagKeys: ["Fast"]),
        "mlx-community/Qwen3-1.7B-4bit": PresentationMetadata(ratingText: "4.2", tagKeys: ["Fast"]),
        "mlx-community/Qwen3-4B-4bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3-8B-4bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Accurate"]),
        "mlx-community/Qwen3.5-2B-4bit": PresentationMetadata(ratingText: "4.3", tagKeys: ["Fast"]),
        "mlx-community/Qwen3.5-4B-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3.5-0.8B-4bit-OptiQ": PresentationMetadata(ratingText: "4.1", tagKeys: ["Fast"]),
        "mlx-community/Qwen3.5-4B-OptiQ-4bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3.5-9B-OptiQ-4bit": PresentationMetadata(ratingText: "4.9", tagKeys: ["Accurate"]),
        "mlx-community/GLM-4-9B-0414-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Accurate"]),
        "mlx-community/glm-4-9b-chat-1m-4bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Accurate"]),
        "mlx-community/GLM-Z1-9B-0414-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Accurate"]),
        "mlx-community/Llama-3.2-3B-Instruct-4bit": PresentationMetadata(ratingText: "4.2", tagKeys: ["Balanced"]),
        "mlx-community/Llama-3.2-1B-Instruct-4bit": PresentationMetadata(ratingText: "4.0", tagKeys: ["Fast"]),
        "mlx-community/Meta-Llama-3-8B-Instruct-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Accurate"]),
        "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Accurate"]),
        "mlx-community/Mistral-7B-Instruct-v0.3-4bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Balanced"]),
        "mlx-community/Mistral-Nemo-Instruct-2407-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Accurate"]),
        "mlx-community/gemma-2-2b-it-4bit": PresentationMetadata(ratingText: "4.1", tagKeys: ["Fast"]),
        "mlx-community/gemma-2-9b-it-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Accurate"]),
        "mlx-community/gemma-4-e2b-it-4bit": PresentationMetadata(ratingText: "4.3", tagKeys: ["Fast"]),
        "mlx-community/gemma-4-e4b-it-4bit": PresentationMetadata(ratingText: "4.6", tagKeys: ["Balanced"]),
        "mlx-community/Phi-3.5-mini-instruct-4bit": PresentationMetadata(ratingText: "4.2", tagKeys: ["Fast"]),
        "mlx-community/Phi-3.5-MoE-instruct-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Accurate"]),
        "mlx-community/internlm2_5-7b-chat-4bit": PresentationMetadata(ratingText: "4.7", tagKeys: ["Accurate"]),
        "mlx-community/MiniCPM4-8B-4bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Accurate"]),
        "mlx-community/granite-3.3-2b-instruct-4bit": PresentationMetadata(ratingText: "4.1", tagKeys: ["Fast"]),
        "mlx-community/MiMo-7B-SFT-4bit": PresentationMetadata(ratingText: "4.4", tagKeys: ["Balanced"]),
        "mlx-community/AceReason-Nemotron-7B-4bit": PresentationMetadata(ratingText: "4.5", tagKeys: ["Accurate"]),
        "mlx-community/Qwen2.5-7B-Instruct-4bit": PresentationMetadata(ratingText: "4.5", tagKeys: ["Balanced"]),
        "mlx-community/Qwen3-30B-A3B-4bit": PresentationMetadata(ratingText: "4.9", tagKeys: ["Accurate"]),
        "mlx-community/GLM-4.7-Flash-4bit": PresentationMetadata(ratingText: "4.8", tagKeys: ["Accurate"]),
    ]

    nonisolated private static let knownRemoteSizeBytesByRepo: [String: Int64] = [
        "Qwen/Qwen2-1.5B-Instruct": 3_098_962_420,
        "Qwen/Qwen2.5-3B-Instruct": 6_183_464_935,
        "mlx-community/Qwen3-4B-4bit": 2_278_972_183,
        "mlx-community/Qwen3-8B-4bit": 4_623_784_971,
        "mlx-community/Qwen3.5-0.8B-4bit-OptiQ": 598_000_000,
        "mlx-community/Qwen3.5-4B-4bit": 3_060_000_000,
        "mlx-community/Qwen3.5-4B-OptiQ-4bit": 2_970_000_000,
        "mlx-community/Qwen3.5-9B-OptiQ-4bit": 6_040_000_000,
        "mlx-community/GLM-4-9B-0414-4bit": 5_309_031_270,
        "mlx-community/glm-4-9b-chat-1m-4bit": 5_360_000_000,
        "mlx-community/GLM-Z1-9B-0414-4bit": 5_290_000_000,
        "mlx-community/GLM-4.7-Flash-4bit": 16_900_000_000,
        "mlx-community/Llama-3.2-3B-Instruct-4bit": 1_824_825_759,
        "mlx-community/Llama-3.2-1B-Instruct-4bit": 712_593_855,
        "mlx-community/Meta-Llama-3-8B-Instruct-4bit": 5_281_878_323,
        "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit": 4_526_698_444,
        "mlx-community/Mistral-7B-Instruct-v0.3-4bit": 4_080_222_853,
        "mlx-community/Mistral-Nemo-Instruct-2407-4bit": 6_905_203_123,
        "mlx-community/internlm2_5-7b-chat-4bit": 4_350_000_000,
        "mlx-community/MiniCPM4-8B-4bit": 4_610_000_000,
        "mlx-community/gemma-2-2b-it-4bit": 1_492_852_888,
        "mlx-community/gemma-2-9b-it-4bit": 5_217_089_310,
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
        guard let option = option(for: repo), option.visibility == .hiddenCompat else {
            return availableModels
        }
        return availableModels + [option]
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

    nonisolated static func releaseStatus(for repo: String) -> ReleaseStatus {
        if deprecatedSoonRepos.contains(canonicalModelRepo(repo)) {
            return .deprecatedSoon
        }
        return option(for: repo)?.releaseStatus ?? .standard
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

    nonisolated static func clearHubCache(for repoID: Repo.ID) {
        let cache = HubCache.default
        let repoDir = cache.repoDirectory(repo: repoID, kind: .model)
        let metadataDir = cache.metadataDirectory(repo: repoID, kind: .model)
        try? FileManager.default.removeItem(at: repoDir)
        try? FileManager.default.removeItem(at: metadataDir)
    }
}

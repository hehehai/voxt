import Foundation

enum LLMExecutionLatencyProfile: String, CaseIterable, Equatable {
    case instant
    case balanced
    case quality
}

enum LLMExecutionDelivery: Equatable {
    case systemPrompt
    case userMessage
}

enum LLMExecutionProvider: Equatable {
    case appleIntelligence
    case customLLM(repo: String)
    case remote(provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration)
}

enum LLMContextBlockKind: String, Equatable {
    case input
    case glossary
    case conversation
    case metadata
    case app
}

enum LLMImageAttachmentDetail: String, Equatable {
    case auto
    case low
    case high
}

struct LLMImageAttachment: Equatable {
    let data: Data
    let mimeType: String
    let detail: LLMImageAttachmentDetail
    let filename: String
}

enum LLMInputAttachment: Equatable {
    case image(LLMImageAttachment)
}

extension LLMImageAttachmentDetail {
    // Heuristic budget used by routing so multimodal rewrite requests stay conservative.
    var estimatedPromptCharacterCost: Int {
        switch self {
        case .low:
            return 900
        case .auto:
            return 1_800
        case .high:
            return 2_700
        }
    }
}

extension LLMInputAttachment {
    var estimatedPromptCharacterCost: Int {
        switch self {
        case .image(let image):
            return image.detail.estimatedPromptCharacterCost
        }
    }
}

extension Array where Element == LLMInputAttachment {
    var estimatedPromptCharacterCost: Int {
        reduce(0) { $0 + $1.estimatedPromptCharacterCost }
    }
}

struct LLMContextBlock: Equatable {
    let kind: LLMContextBlockKind
    let title: String
    let content: String
    let isStablePrefixCandidate: Bool

    var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LLMExecutionTaskPayload: Equatable {
    case enhancement(rawText: String)
    case translation(sourceText: String, targetLanguage: TranslationTargetLanguage)
    case rewrite(dictatedPrompt: String, sourceText: String, structuredAnswerOutput: Bool)
    case transcriptSummary(transcript: String, request: String)
}

struct LLMExecutionPlan: Equatable {
    let task: LLMExecutionTaskPayload
    let provider: LLMExecutionProvider
    let delivery: LLMExecutionDelivery
    let promptContent: String
    let fallbackText: String
    let executionStrategy: TaskLLMExecutionStrategy
    let outputTokenBudgetHint: Int?
    let contextBlocks: [LLMContextBlock]
    let attachments: [LLMInputAttachment]
    let conversationHistory: [RewriteConversationPromptTurn]
    let previousResponseID: String?
    let responseFormat: RemoteLLMRuntimeClient.OpenAICompatibleResponseFormat?

    var promptCharacterCount: Int {
        promptContent.count
    }

    var primaryInputCharacterCount: Int {
        switch task {
        case .enhancement(let rawText):
            return rawText.count
        case .translation(let sourceText, _):
            return sourceText.count
        case .rewrite(let dictatedPrompt, let sourceText, _):
            return dictatedPrompt.count + sourceText.count
        case .transcriptSummary(let transcript, let request):
            return transcript.count + request.count
        }
    }

    var taskLabel: String {
        switch task {
        case .enhancement:
            return "enhancement"
        case .translation:
            return "translation"
        case .rewrite:
            return "rewrite"
        case .transcriptSummary:
            return "transcriptSummary"
        }
    }
}

struct LLMCompiledRequest: Equatable {
    let taskLabel: String
    let instructions: String
    let prompt: String
    let debugInput: String
    let fallbackText: String
    let inputCharacterCount: Int
    let outputTokenBudgetHint: Int?
    let attachments: [LLMInputAttachment]
    let conversationHistory: [RewriteConversationPromptTurn]
    let previousResponseID: String?
    let responseFormat: RemoteLLMRuntimeClient.OpenAICompatibleResponseFormat?
}

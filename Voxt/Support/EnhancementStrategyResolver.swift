import Foundation

enum TaskLLMKind: String, Equatable {
    case transcriptionEnhancement
    case translation
    case rewrite

    var logLabel: String { rawValue }

    var outputTokenMultiplier: Double {
        switch self {
        case .transcriptionEnhancement:
            return 1.10
        case .translation, .rewrite:
            return 1.35
        }
    }
}

enum TaskLLMExecutionMode: String, Equatable {
    case singlePass
    case segmented
}

enum TaskLLMContextBudgetPolicy: String, Equatable {
    case standard
    case reducedForLongInput
}

struct LLMProviderModelCapabilities: Equatable {
    let maxContextTokens: Int?
    let maxOutputTokens: Int?

    static let unknown = LLMProviderModelCapabilities(
        maxContextTokens: nil,
        maxOutputTokens: nil
    )
}

struct TaskLLMTruncationGuardPolicy: Equatable {
    let isEnabled: Bool
    let minimumCoverageRatio: Double
    let prefixCoverageRatio: Double
    let absoluteSlack: Int

    static let disabled = TaskLLMTruncationGuardPolicy(
        isEnabled: false,
        minimumCoverageRatio: 0,
        prefixCoverageRatio: 0,
        absoluteSlack: 0
    )
}

struct TaskLLMExecutionStrategy: Equatable {
    let taskKind: TaskLLMKind
    let rawTextCharacterCount: Int
    let promptCharacterCount: Int
    let mode: TaskLLMExecutionMode
    let contextBudgetPolicy: TaskLLMContextBudgetPolicy
    let glossarySelectionPolicy: DictionaryGlossarySelectionPolicy
    let outputTokenBudgetHint: Int?
    let segmentationCharacterLimit: Int?
    let truncationGuard: TaskLLMTruncationGuardPolicy

    var logLabel: String {
        [
            "task=\(taskKind.logLabel)",
            "rawChars=\(rawTextCharacterCount)",
            "promptChars=\(promptCharacterCount)",
            "mode=\(mode.rawValue)",
            "contextBudget=\(contextBudgetPolicy.rawValue)",
            "outputBudgetHint=\(outputTokenBudgetHint.map(String.init) ?? "n/a")",
            "segmentLimit=\(segmentationCharacterLimit.map(String.init) ?? "n/a")",
            "truncationGuard=\(truncationGuard.isEnabled)"
        ].joined(separator: ",")
    }
}

enum TaskLLMStrategyResolver {
    static let longTextThreshold = 300

    static func resolve(
        taskKind: TaskLLMKind,
        rawText: String,
        promptCharacterCount: Int,
        baseGlossarySelectionPolicy: DictionaryGlossarySelectionPolicy,
        capabilities: LLMProviderModelCapabilities
    ) -> TaskLLMExecutionStrategy {
        let rawTextCharacterCount = normalizedCharacterCount(rawText)
        let isLongText = rawTextCharacterCount > longTextThreshold
        let estimatedOutputTokens = estimatedOutputTokens(
            taskKind: taskKind,
            rawTextCharacterCount: rawTextCharacterCount
        )

        let mode: TaskLLMExecutionMode
        if isLongText,
           let maxOutputTokens = capabilities.maxOutputTokens,
           estimatedOutputTokens >= max(1, Int(Double(maxOutputTokens) * 0.85)) {
            mode = .segmented
        } else {
            mode = .singlePass
        }

        let outputTokenBudgetHint: Int?
        if let maxOutputTokens = capabilities.maxOutputTokens {
            outputTokenBudgetHint = min(maxOutputTokens, estimatedOutputTokens)
        } else {
            outputTokenBudgetHint = nil
        }

        return TaskLLMExecutionStrategy(
            taskKind: taskKind,
            rawTextCharacterCount: rawTextCharacterCount,
            promptCharacterCount: promptCharacterCount,
            mode: mode,
            contextBudgetPolicy: isLongText ? .reducedForLongInput : .standard,
            glossarySelectionPolicy: isLongText
                ? baseGlossarySelectionPolicy.reducedForLongInput()
                : baseGlossarySelectionPolicy,
            outputTokenBudgetHint: outputTokenBudgetHint,
            segmentationCharacterLimit: mode == .segmented ? max(longTextThreshold, 280) : nil,
            truncationGuard: isLongText
                ? TaskLLMTruncationGuardPolicy(
                    isEnabled: true,
                    minimumCoverageRatio: 0.72,
                    prefixCoverageRatio: 0.90,
                    absoluteSlack: 24
                )
                : .disabled
        )
    }

    static func applyTruncationGuard(
        outputText: String,
        originalText: String,
        strategy: TaskLLMExecutionStrategy
    ) -> (text: String, didFallback: Bool) {
        let policy = strategy.truncationGuard
        guard policy.isEnabled else {
            return (outputText, false)
        }

        let normalizedOriginal = normalizedComparableText(originalText)
        let normalizedOutput = normalizedComparableText(outputText)
        guard !normalizedOriginal.isEmpty, !normalizedOutput.isEmpty else {
            return (originalText, true)
        }

        let originalCount = normalizedOriginal.count
        let outputCount = normalizedOutput.count
        let minimumCoverage = max(
            Int((Double(originalCount) * policy.minimumCoverageRatio).rounded(.down)),
            originalCount - policy.absoluteSlack
        )
        let coverageRatio = Double(outputCount) / Double(max(1, originalCount))
        let isSuspiciousPrefix = normalizedOriginal.hasPrefix(normalizedOutput) &&
            coverageRatio < policy.prefixCoverageRatio
        let isSuspiciouslyShort = outputCount < minimumCoverage

        guard isSuspiciousPrefix || isSuspiciouslyShort else {
            return (outputText, false)
        }

        return (originalText, true)
    }

    private static func estimatedOutputTokens(
        taskKind: TaskLLMKind,
        rawTextCharacterCount: Int
    ) -> Int {
        let safeCharacters = max(1, rawTextCharacterCount)
        return Int((Double(safeCharacters) * taskKind.outputTokenMultiplier).rounded(.up))
    }

    private static func normalizedCharacterCount(_ text: String) -> Int {
        normalizedComparableText(text).count
    }

    private static func normalizedComparableText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

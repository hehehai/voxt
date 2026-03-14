import Foundation

extension ActionAssistantRecipeMatcher {
    static func learnedRecipeScore(
        for normalizedText: String,
        recipe: ActionAssistantRecipe,
        snapshot: ActionAssistantPerceptionSnapshot
    ) -> Double {
        let normalizedName = normalize(recipe.name.replacingOccurrences(of: "Learned - ", with: ""))
        let normalizedDescription = normalize(recipe.description)
        let contextBoost = learnedRecipeContextBoost(recipe: recipe, snapshot: snapshot, normalizedDescription: normalizedDescription)

        if normalizedName == normalizedText || normalizedDescription == normalizedText {
            return min(1.0, 1.0 + contextBoost)
        }
        if !normalizedDescription.isEmpty,
           normalizedText.contains(normalizedDescription) || normalizedDescription.contains(normalizedText) {
            return min(1.0, 0.92 + contextBoost)
        }
        if !normalizedName.isEmpty,
           normalizedText.contains(normalizedName) || normalizedName.contains(normalizedText) {
            return min(1.0, 0.85 + contextBoost)
        }

        let textTokens = Set(normalizedText.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        let descriptionTokens = Set(normalizedDescription.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        let nameTokens = Set(normalizedName.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        let descriptionScore = tokenOverlapScore(textTokens: textTokens, candidateTokens: descriptionTokens)
        let nameScore = tokenOverlapScore(textTokens: textTokens, candidateTokens: nameTokens)
        let baseScore = max(descriptionScore, nameScore) + contextBoost
        return min(1.0, max(0.0, baseScore + learnedMetricsAdjustment(recipe.learnedMetrics)))
    }

    static func tokenOverlapScore(textTokens: Set<String>, candidateTokens: Set<String>) -> Double {
        guard !textTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }
        let intersection = textTokens.intersection(candidateTokens)
        guard !intersection.isEmpty else { return 0 }
        return Double(intersection.count) / Double(max(1, min(textTokens.count, candidateTokens.count)))
    }

    static func learnedMetricsAdjustment(_ metrics: ActionAssistantRecipe.LearnedMetrics?) -> Double {
        guard let metrics else { return 0 }

        let totalResolved = metrics.successCount + metrics.failureCount
        let successRateBoost: Double
        if totalResolved > 0 {
            let successRate = Double(metrics.successCount) / Double(totalResolved)
            successRateBoost = (successRate - 0.5) * 0.35
        } else {
            successRateBoost = 0
        }

        let recencyBoost: Double
        if let lastSucceededAt = metrics.lastSucceededAt {
            let age = Date().timeIntervalSince(lastSucceededAt)
            switch age {
            case ..<86_400:
                recencyBoost = 0.12
            case ..<604_800:
                recencyBoost = 0.07
            case ..<2_592_000:
                recencyBoost = 0.03
            default:
                recencyBoost = 0
            }
        } else {
            recencyBoost = 0
        }

        let failurePenalty = min(0.18, Double(metrics.failureCount) * 0.03)
        let usageConfidenceBoost = min(0.08, Double(metrics.successCount) * 0.01)
        let reviewPenalty = metrics.consecutiveFailureCount >= 3 ? 0.25 : 0
        let diagnosisPenalty: Double
        switch metrics.lastFailureCategory?.lowercased() {
        case "target_miss":
            diagnosisPenalty = 0.08
        case "wrong_focus":
            diagnosisPenalty = 0.06
        case "target_missing":
            diagnosisPenalty = 0.1
        case "state_unchanged":
            diagnosisPenalty = 0.04
        default:
            diagnosisPenalty = 0
        }
        return successRateBoost + recencyBoost + usageConfidenceBoost - failurePenalty - reviewPenalty - diagnosisPenalty
    }

    private static func learnedRecipeContextBoost(
        recipe: ActionAssistantRecipe,
        snapshot: ActionAssistantPerceptionSnapshot,
        normalizedDescription: String
    ) -> Double {
        var contextBoost = 0.0
        if recipe.pinned {
            contextBoost += 0.2
        }
        if let app = recipe.app,
           let frontmostApp = snapshot.frontmostAppName,
           frontmostApp.localizedCaseInsensitiveContains(app) || app.localizedCaseInsensitiveContains(frontmostApp) {
            contextBoost += 0.2
        }
        if let appRunning = recipe.preconditions?.appRunning,
           let frontmostApp = snapshot.frontmostAppName,
           frontmostApp.localizedCaseInsensitiveContains(appRunning) || appRunning.localizedCaseInsensitiveContains(frontmostApp) {
            contextBoost += 0.15
        }
        if let urlContains = recipe.preconditions?.urlContains?.lowercased(),
           let currentURL = snapshot.currentURL?.lowercased(),
           currentURL.contains(urlContains) {
            contextBoost += 0.2
        }
        if let focusedTitle = snapshot.focusedWindowTitle?.lowercased(),
           !normalizedDescription.isEmpty,
           focusedTitle.contains(normalizedDescription) || normalizedDescription.contains(focusedTitle) {
            contextBoost += 0.1
        }
        return contextBoost
    }
}

import Foundation

extension ActionAssistantRecipe.LearnedMetrics {
    static var empty: Self {
        .init(
            matchCount: 0,
            successCount: 0,
            failureCount: 0,
            consecutiveFailureCount: 0,
            lastFailureCategory: nil,
            lastMatchedAt: nil,
            lastSucceededAt: nil,
            lastFailedAt: nil
        )
    }
}

extension ActionAssistantRecipeStore {
    static func updateRecipe(named name: String, _ mutate: (inout ActionAssistantRecipe) -> Void) {
        guard var recipe = loadRecipe(named: name) else { return }
        mutate(&recipe)
        try? saveRecipe(recipe)
    }

    static func resetMetrics(for recipe: inout ActionAssistantRecipe) {
        recipe.learnedMetrics = .empty
    }

    static func nextUniqueRecipeName(startingWith baseName: String) -> String {
        var candidate = baseName
        var index = 2
        while FileManager.default.fileExists(atPath: recipeURL(named: candidate).path) {
            candidate = "\(baseName) \(index)"
            index += 1
        }
        return candidate
    }

    static func createRecipesDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: recipesDirectoryURL,
            withIntermediateDirectories: true
        )
    }
}

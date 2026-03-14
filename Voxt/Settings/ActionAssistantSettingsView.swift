import SwiftUI
import AppKit

struct ActionAssistantSettingsView: View {
    @AppStorage(AppPreferenceKey.actionAssistantRequiresConfirmation) private var actionAssistantRequiresConfirmation = false
    @AppStorage(AppPreferenceKey.actionAssistantVisualSnapshotsEnabled) private var actionAssistantVisualSnapshotsEnabled = false
    @AppStorage(AppPreferenceKey.actionAssistantLearnSuccessfulPlansEnabled) private var actionAssistantLearnSuccessfulPlansEnabled = false
    @AppStorage(AppPreferenceKey.actionAssistantTeachModeEnabled) private var actionAssistantTeachModeEnabled = false
    @AppStorage(AppPreferenceKey.actionAssistantTeachModeAutoOpenDraft) private var actionAssistantTeachModeAutoOpenDraft = true
    @State private var recipes: [ActionAssistantRecipe] = []
    @State private var recipePendingDeletion: ActionAssistantRecipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ActionAssistantOverviewSection(
                requiresConfirmation: $actionAssistantRequiresConfirmation,
                visualSnapshotsEnabled: $actionAssistantVisualSnapshotsEnabled,
                learnSuccessfulPlansEnabled: $actionAssistantLearnSuccessfulPlansEnabled,
                teachModeEnabled: $actionAssistantTeachModeEnabled,
                teachModeAutoOpenDraft: $actionAssistantTeachModeAutoOpenDraft,
                recipeCount: recipes.count,
                builtInRecipeCount: recipes.filter(isBuiltIn).count
            )

            ActionAssistantRecipeLibrarySection(
                recipes: recipes,
                recipePendingDeletion: $recipePendingDeletion,
                onRefresh: reloadRecipes,
                onRevealFolder: revealRecipeFolder,
                onCreateRecipe: createRecipeTemplate,
                onRestoreBuiltIns: restoreBuiltIns,
                onResetAllLearnedMetrics: resetAllLearnedMetrics,
                onResetBuiltIn: resetBuiltInRecipe,
                onToggleEnabled: toggleRecipeEnabled,
                onDuplicate: duplicateRecipe,
                onEditJSON: editRecipeJSON,
                onTogglePinned: toggleRecipePinned,
                onResetMetrics: resetRecipeMetrics
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            ActionAssistantRecipeStore.ensureBuiltInRecipesInstalled()
            reloadRecipes()
        }
        .alert(AppLocalization.localizedString("Delete custom recipe?"), isPresented: Binding(
            get: { recipePendingDeletion != nil },
            set: { if !$0 { recipePendingDeletion = nil } }
        )) {
            Button(AppLocalization.localizedString("Cancel"), role: .cancel) {
                recipePendingDeletion = nil
            }
            Button(AppLocalization.localizedString("Delete"), role: .destructive) {
                guard let recipePendingDeletion else { return }
                try? ActionAssistantRecipeStore.deleteRecipe(named: recipePendingDeletion.name)
                self.recipePendingDeletion = nil
                reloadRecipes()
            }
        } message: {
            Text(AppLocalization.localizedString("This removes the selected custom recipe from Voxt's recipe library."))
        }
    }

    private func reloadRecipes() {
        recipes = ActionAssistantRecipeStore.listRecipes()
            .sorted(by: recipeSort)
    }

    private func isBuiltIn(_ recipe: ActionAssistantRecipe) -> Bool {
        ActionAssistantBuiltInRecipes.names.contains(recipe.name)
    }

    private func isLearned(_ recipe: ActionAssistantRecipe) -> Bool {
        ActionAssistantRecipeStore.isLearnedRecipe(recipe)
    }

    private func recipeSort(_ lhs: ActionAssistantRecipe, _ rhs: ActionAssistantRecipe) -> Bool {
        let lhsCategory = recipeSortCategory(for: lhs)
        let rhsCategory = recipeSortCategory(for: rhs)
        if lhsCategory != rhsCategory {
            return lhsCategory < rhsCategory
        }
        if isLearned(lhs) && isLearned(rhs) {
            let lhsScore = learnedRecipeSortScore(for: lhs)
            let rhsScore = learnedRecipeSortScore(for: rhs)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func recipeSortCategory(for recipe: ActionAssistantRecipe) -> Int {
        if !recipe.enabled {
            return 5
        }
        if ActionAssistantRecipeStore.needsReview(recipe) {
            return 2
        }
        if recipe.pinned {
            return 0
        }
        if isLearned(recipe) {
            return 1
        }
        if isBuiltIn(recipe) {
            return 3
        }
        return 4
    }

    private func learnedRecipeSortScore(for recipe: ActionAssistantRecipe) -> Double {
        guard let metrics = recipe.learnedMetrics else { return 0 }
        let totalAttempts = metrics.successCount + metrics.failureCount
        let successRate = totalAttempts > 0 ? Double(metrics.successCount) / Double(totalAttempts) : 0
        let confidenceBoost = min(Double(metrics.successCount) * 0.05, 0.5)
        let usageBoost = min(Double(metrics.matchCount) * 0.01, 0.25)
        let failurePenalty = min(Double(metrics.failureCount) * 0.03, 0.45)
        return successRate + confidenceBoost + usageBoost - failurePenalty
    }

    private func revealRecipeFolder() {
        NSWorkspace.shared.open(ActionAssistantRecipeStore.recipesDirectoryURL)
    }

    private func createRecipeTemplate() {
        if let recipeName = try? ActionAssistantRecipeStore.createRecipeTemplate() {
            NSWorkspace.shared.open(ActionAssistantRecipeStore.recipeURL(named: recipeName))
            reloadRecipes()
        }
    }

    private func restoreBuiltIns() {
        ActionAssistantRecipeStore.restoreBuiltInRecipes()
        reloadRecipes()
    }

    private func resetAllLearnedMetrics() {
        ActionAssistantRecipeStore.resetAllLearnedRecipeMetrics()
        reloadRecipes()
    }

    private func resetBuiltInRecipe(_ recipe: ActionAssistantRecipe) {
        guard let builtIn = ActionAssistantBuiltInRecipes.recipe(named: recipe.name) else { return }
        try? ActionAssistantRecipeStore.saveRecipe(builtIn)
        reloadRecipes()
    }

    private func toggleRecipeEnabled(_ recipe: ActionAssistantRecipe) {
        ActionAssistantRecipeStore.setRecipeEnabled(named: recipe.name, enabled: !recipe.enabled)
        reloadRecipes()
    }

    private func duplicateRecipe(_ recipe: ActionAssistantRecipe) {
        _ = try? ActionAssistantRecipeStore.duplicateRecipe(named: recipe.name)
        reloadRecipes()
    }

    private func editRecipeJSON(_ recipe: ActionAssistantRecipe) {
        NSWorkspace.shared.open(ActionAssistantRecipeStore.recipeURL(named: recipe.name))
    }

    private func toggleRecipePinned(_ recipe: ActionAssistantRecipe) {
        ActionAssistantRecipeStore.setRecipePinned(named: recipe.name, pinned: !recipe.pinned)
        reloadRecipes()
    }

    private func resetRecipeMetrics(_ recipe: ActionAssistantRecipe) {
        ActionAssistantRecipeStore.resetLearnedRecipeMetrics(named: recipe.name)
        reloadRecipes()
    }
}

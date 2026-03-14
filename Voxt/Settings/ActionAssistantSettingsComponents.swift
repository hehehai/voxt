import SwiftUI
import AppKit

struct ActionAssistantOverviewSection: View {
    let requiresConfirmation: Binding<Bool>
    let visualSnapshotsEnabled: Binding<Bool>
    let learnSuccessfulPlansEnabled: Binding<Bool>
    let teachModeEnabled: Binding<Bool>
    let teachModeAutoOpenDraft: Binding<Bool>
    let recipeCount: Int
    let builtInRecipeCount: Int

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.localizedString("Action Assistant"))
                    .font(.headline)

                ToggleWithInfo(
                    title: AppLocalization.localizedString("Require confirmation before execution"),
                    message: AppLocalization.localizedString("When enabled, use the configured Action Assistant shortcut to start assistant dictation. Voxt will prepare the spoken task and execute supported actions using the embedded action runtime."),
                    isOn: requiresConfirmation
                )
                ToggleWithInfo(
                    title: AppLocalization.localizedString("Capture visual snapshots for planning"),
                    message: AppLocalization.localizedString("Visual snapshots capture the focused window as a temporary screenshot and include it in Action Assistant context for debugging and future multimodal planning."),
                    isOn: visualSnapshotsEnabled
                )
                ToggleWithInfo(
                    title: AppLocalization.localizedString("Learn successful plans as recipes"),
                    message: AppLocalization.localizedString("When enabled, successful multi-step assistant plans are saved to the recipe library as learned recipes for later reuse and inspection."),
                    isOn: learnSuccessfulPlansEnabled
                )
                ToggleWithInfo(
                    title: AppLocalization.localizedString("Teach mode records editable recipe drafts"),
                    message: AppLocalization.localizedString("When enabled, each successful assistant run is saved as an editable draft recipe so you can refine or pin it manually."),
                    isOn: teachModeEnabled
                )
                if teachModeEnabled.wrappedValue {
                    ToggleWithInfo(
                        title: AppLocalization.localizedString("Auto-open teach drafts after capture"),
                        message: AppLocalization.localizedString("When enabled, newly captured teach mode drafts are opened immediately in your default JSON editor."),
                        isOn: teachModeAutoOpenDraft
                    )
                }

                Divider()

                HStack(alignment: .top, spacing: 24) {
                    ActionAssistantMetricColumn(
                        label: {
                            InlineInfoLabel(
                                title: AppLocalization.localizedString("Execution Engine"),
                                message: AppLocalization.localizedString("Action Assistant is being migrated from the external Ghost MCP prototype to an embedded Voxt runtime. The current preview uses built-in actions for supported tasks.")
                            )
                        },
                        value: AppLocalization.localizedString("Embedded Preview")
                    )
                    Spacer()
                    ActionAssistantMetricColumn(
                        label: { Text(AppLocalization.localizedString("Installed Recipes")) },
                        value: "\(recipeCount)"
                    )
                    Spacer()
                    ActionAssistantMetricColumn(
                        label: { Text(AppLocalization.localizedString("Built-in Recipes")) },
                        value: "\(builtInRecipeCount)"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private struct ToggleWithInfo: View {
    let title: String
    let message: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle(isOn: isOn) {
                Text(title)
            }
            InfoPopoverButton(message: message)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActionAssistantRecipeLibrarySection: View {
    let recipes: [ActionAssistantRecipe]
    let recipePendingDeletion: Binding<ActionAssistantRecipe?>
    let onRefresh: () -> Void
    let onRevealFolder: () -> Void
    let onCreateRecipe: () -> Void
    let onRestoreBuiltIns: () -> Void
    let onResetAllLearnedMetrics: () -> Void
    let onResetBuiltIn: (ActionAssistantRecipe) -> Void
    let onToggleEnabled: (ActionAssistantRecipe) -> Void
    let onDuplicate: (ActionAssistantRecipe) -> Void
    let onEditJSON: (ActionAssistantRecipe) -> Void
    let onTogglePinned: (ActionAssistantRecipe) -> Void
    let onResetMetrics: (ActionAssistantRecipe) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    InlineInfoLabel(
                        title: AppLocalization.localizedString("Recipe Library"),
                        message: AppLocalization.localizedString("Recipes are stored in Voxt Application Support. Built-in recipes can be restored at any time, and custom recipes can be managed from the same folder."),
                        font: .headline,
                        color: .primary
                    )
                    Spacer()
                    ActionAssistantRecipeToolbar(
                        hasLearnedRecipes: recipes.contains { recipe in
                            ActionAssistantRecipeStore.isLearnedRecipe(recipe)
                        },
                        onRefresh: onRefresh,
                        onRevealFolder: onRevealFolder,
                        onCreateRecipe: onCreateRecipe,
                        onRestoreBuiltIns: onRestoreBuiltIns,
                        onResetAllLearnedMetrics: onResetAllLearnedMetrics
                    )
                }

                if recipes.isEmpty {
                    Text(AppLocalization.localizedString("No recipes installed yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(recipes) { recipe in
                                ActionAssistantRecipeRow(
                                    recipe: recipe,
                                    recipePendingDeletion: recipePendingDeletion,
                                    onResetBuiltIn: onResetBuiltIn,
                                    onToggleEnabled: onToggleEnabled,
                                    onDuplicate: onDuplicate,
                                    onEditJSON: onEditJSON,
                                    onTogglePinned: onTogglePinned,
                                    onResetMetrics: onResetMetrics
                                )
                                if recipe.id != recipes.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 264, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private struct ActionAssistantRecipeToolbar: View {
    let hasLearnedRecipes: Bool
    let onRefresh: () -> Void
    let onRevealFolder: () -> Void
    let onCreateRecipe: () -> Void
    let onRestoreBuiltIns: () -> Void
    let onResetAllLearnedMetrics: () -> Void

    var body: some View {
        Group {
            Button(AppLocalization.localizedString("Refresh"), action: onRefresh)
            Button(AppLocalization.localizedString("Reveal Folder"), action: onRevealFolder)
            Button(AppLocalization.localizedString("New Recipe"), action: onCreateRecipe)
            Button(AppLocalization.localizedString("Restore Built-ins"), action: onRestoreBuiltIns)
            Button(AppLocalization.localizedString("Reset All Learned Metrics"), action: onResetAllLearnedMetrics)
                .disabled(!hasLearnedRecipes)
        }
        .controlSize(.small)
    }
}

private struct ActionAssistantRecipeRow: View {
    let recipe: ActionAssistantRecipe
    let recipePendingDeletion: Binding<ActionAssistantRecipe?>
    let onResetBuiltIn: (ActionAssistantRecipe) -> Void
    let onToggleEnabled: (ActionAssistantRecipe) -> Void
    let onDuplicate: (ActionAssistantRecipe) -> Void
    let onEditJSON: (ActionAssistantRecipe) -> Void
    let onTogglePinned: (ActionAssistantRecipe) -> Void
    let onResetMetrics: (ActionAssistantRecipe) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayTitle)
                    .font(.subheadline.weight(.medium))
                RecipeBadge(title: badgeTitle, tint: badgeColor)
                Spacer()
                Text(AppLocalization.format("%d step(s)", recipe.steps.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                actionButtons
            }

            Text(displayDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(AppLocalization.format("App: %@", recipe.app ?? AppLocalization.localizedString("Any")))
                Text(AppLocalization.format("Params: %d", recipe.params?.count ?? 0))
                if let learnedStats {
                    Text(learnedStats)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isBuiltIn {
            Button(AppLocalization.localizedString("Reset")) { onResetBuiltIn(recipe) }
                .controlSize(.small)
        } else if isLearned {
            commonEditableButtons
            Button(recipe.pinned ? AppLocalization.localizedString("Unpin") : AppLocalization.localizedString("Pin")) {
                onTogglePinned(recipe)
            }
            .controlSize(.small)
            Button(AppLocalization.localizedString("Reset Metrics")) {
                onResetMetrics(recipe)
            }
            .controlSize(.small)
        } else {
            commonEditableButtons
            Button(AppLocalization.localizedString("Delete"), role: .destructive) {
                recipePendingDeletion.wrappedValue = recipe
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var commonEditableButtons: some View {
        Button(recipe.enabled ? AppLocalization.localizedString("Disable") : AppLocalization.localizedString("Enable")) {
            onToggleEnabled(recipe)
        }
        .controlSize(.small)
        Button(AppLocalization.localizedString("Duplicate")) {
            onDuplicate(recipe)
        }
        .controlSize(.small)
        Button(AppLocalization.localizedString("Edit JSON")) {
            onEditJSON(recipe)
        }
        .controlSize(.small)
    }

    private var isBuiltIn: Bool {
        ActionAssistantBuiltInRecipes.names.contains(recipe.name)
    }

    private var isLearned: Bool {
        ActionAssistantRecipeStore.isLearnedRecipe(recipe)
    }

    private var displayTitle: String {
        isBuiltIn ? ActionAssistantBuiltInRecipes.localizedTitle(for: recipe) : recipe.name
    }

    private var displayDescription: String {
        isBuiltIn ? ActionAssistantBuiltInRecipes.localizedDescription(for: recipe) : recipe.description
    }

    private var badgeTitle: String {
        if !recipe.enabled { return AppLocalization.localizedString("Disabled") }
        if ActionAssistantRecipeStore.needsReview(recipe) { return AppLocalization.localizedString("Needs Review") }
        if recipe.pinned { return AppLocalization.localizedString("Pinned") }
        if isBuiltIn { return AppLocalization.localizedString("Built-in") }
        if isLearned { return AppLocalization.localizedString("Learned") }
        return AppLocalization.localizedString("Custom")
    }

    private var badgeColor: Color {
        if !recipe.enabled { return .secondary }
        if ActionAssistantRecipeStore.needsReview(recipe) { return .red }
        if recipe.pinned { return .pink }
        if isBuiltIn { return .blue }
        if isLearned { return .orange }
        return .green
    }

    private var learnedStats: String? {
        guard isLearned, let metrics = recipe.learnedMetrics else { return nil }
        var text = AppLocalization.format(
            "Matches: %d · Success: %d · Failures: %d",
            metrics.matchCount,
            metrics.successCount,
            metrics.failureCount
        )
        if metrics.consecutiveFailureCount >= 3 {
            text += " · " + AppLocalization.format("Streak: %d", metrics.consecutiveFailureCount)
        }
        if let failureCategory = metrics.lastFailureCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !failureCategory.isEmpty {
            text += " · " + AppLocalization.format("Last Failure: %@", failureCategory)
        }
        return text
    }
}

private struct ActionAssistantMetricColumn<Label: View>: View {
    let label: () -> Label
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            label()
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.medium))
                .textSelection(.enabled)
        }
    }
}

private struct RecipeBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .foregroundStyle(tint)
    }
}

private struct InlineInfoLabel: View {
    let title: String
    let message: String
    var font: Font = .caption
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            InfoPopoverButton(message: message)
        }
        .font(font)
        .foregroundStyle(color)
    }
}

private struct InfoPopoverButton: View {
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(12)
        }
    }
}

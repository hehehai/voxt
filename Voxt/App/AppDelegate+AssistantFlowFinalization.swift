import Foundation
import AppKit

extension AppDelegate {
    func completeAssistantFlow(
        text: String,
        startedAt: Date,
        summary: String,
        snapshotPath: String?
    ) {
        createAssistantTeachDraftIfNeeded(text: text, summary: summary)
        appendAssistantHistoryIfNeeded(
            text: text,
            llmDurationSeconds: Date().timeIntervalSince(startedAt),
            summary: summary,
            snapshotPath: snapshotPath
        )
        overlayState.actionItems = assistantActionStatuses.map(\.title)
        overlayState.statusMessage = ""
        finishSession(after: 1.0)
    }

    func cancelAssistantFlow(
        text: String,
        startedAt: Date,
        summary: String,
        snapshotPath: String?
    ) {
        let message = String(localized: "Assistant action cancelled.")
        assistantActionHistory.append(message)
        overlayState.actionItems = [message]
        overlayState.statusMessage = ""
        appendAssistantHistoryIfNeeded(
            text: text,
            llmDurationSeconds: Date().timeIntervalSince(startedAt),
            summary: summary,
            snapshotPath: snapshotPath
        )
        finishSession(after: 0.6)
    }

    func failAssistantFlow(
        text: String,
        startedAt: Date,
        summary: String,
        snapshotPath: String?,
        delay: TimeInterval = 0.6
    ) {
        assistantActionHistory.append(summary)
        overlayState.actionItems = [summary]
        overlayState.statusMessage = ""
        overlayWindow.show(state: overlayState, position: overlayPosition)
        appendAssistantHistoryIfNeeded(
            text: text,
            llmDurationSeconds: Date().timeIntervalSince(startedAt),
            summary: summary,
            snapshotPath: snapshotPath
        )
        finishSession(after: delay)
    }

    private func createAssistantTeachDraftIfNeeded(text: String, summary: String) {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.actionAssistantTeachModeEnabled),
              !assistantStructuredHistory.isEmpty else {
            return
        }

        do {
            let recipeName = try ActionAssistantRecipeStore.createRecipeTemplate(
                fromAssistantSummary: summary,
                spokenText: text,
                actions: assistantActionHistory,
                structuredSteps: assistantStructuredHistory,
                focusedAppName: lastEnhancementPromptContext?.focusedAppName
            )
            assistantLogInfo("Assistant teach draft saved. name=\(recipeName), steps=\(assistantStructuredHistory.count)")
            if UserDefaults.standard.bool(forKey: AppPreferenceKey.actionAssistantTeachModeAutoOpenDraft) {
                NSWorkspace.shared.open(ActionAssistantRecipeStore.recipeURL(named: recipeName))
            }
        } catch {
            assistantLogWarning("Assistant teach draft save failed. error=\(error)")
        }
    }
}

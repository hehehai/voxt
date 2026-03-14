import Foundation

extension AppDelegate {
    func recordAssistantStep(_ step: String) {
        assistantLogInfo("Assistant step. \(step)")
        assistantActionHistory.append(step)
        if assistantStructuredHistory.isEmpty {
            assistantStructuredHistory.append(AssistantHistoryStep(title: step, note: step))
        }
        assistantActionStatuses.append(AssistantActionStatus(title: step))
        assistantActionStatuses = Array(assistantActionStatuses.suffix(2))
        overlayState.actionItems = assistantActionStatuses.map(\.title)
        overlayState.statusMessage = ""
    }

    func initializeAssistantStepHistory(with titles: [String]) {
        assistantActionStatuses = titles.map { AssistantActionStatus(title: $0) }
        assistantActionHistory = titles
        assistantStructuredHistory = titles.map { AssistantHistoryStep(title: $0, note: $0) }
        overlayState.actionItems = titles
        overlayState.statusMessage = ""
    }

    func stageAssistantExecutionStep(_ title: String) {
        assistantActionStatuses.append(AssistantActionStatus(title: title))
        assistantActionStatuses = Array(assistantActionStatuses.suffix(2))
        overlayState.actionItems = assistantActionStatuses.map(\.title)
        overlayState.statusMessage = ""
    }

    func structuredHistorySteps(for recipe: ActionAssistantRecipe) -> [AssistantHistoryStep] {
        recipe.steps.map { step in
            AssistantHistoryStep(
                title: step.note ?? step.action,
                action: step.action,
                targetApp: step.targetApp,
                targetLabel: step.target?.computedNameContains,
                targetRole: step.target?.criteria?.first(where: { $0.attribute == "AXRole" })?.value,
                relativeX: step.params?["relative_x"].flatMap(Double.init),
                relativeY: step.params?["relative_y"].flatMap(Double.init),
                resolvedTargetLabel: nil,
                resolvedTargetRole: nil,
                resolvedRelativeX: nil,
                resolvedRelativeY: nil,
                success: nil,
                durationMs: nil,
                error: nil,
                diagnosisCategory: nil,
                diagnosisReason: nil,
                params: step.params,
                note: step.note,
                waitAfter: step.waitAfter.map {
                    .init(condition: $0.condition, value: $0.value, timeout: $0.timeout)
                }
            )
        }
    }

    func structuredHistorySteps(for task: ActionAssistantParsedTask) -> [AssistantHistoryStep] {
        switch task {
        case .browserNavigation(let navigationTask):
            return [
                AssistantHistoryStep(
                    title: "Open \(navigationTask.browserAppName)",
                    action: "open_app",
                    targetApp: navigationTask.browserAppName,
                    params: ["app_name": navigationTask.browserAppName],
                    note: "Open \(navigationTask.browserAppName)"
                ),
                AssistantHistoryStep(
                    title: "Navigate to \(navigationTask.url.absoluteString)",
                    action: "open_url",
                    targetApp: navigationTask.browserAppName,
                    params: ["url": navigationTask.url.absoluteString],
                    note: "Navigate to \(navigationTask.url.absoluteString)"
                )
            ]
        case .browserSearch(let searchTask):
            return [
                AssistantHistoryStep(
                    title: "Open \(searchTask.browserAppName)",
                    action: "open_app",
                    targetApp: searchTask.browserAppName,
                    params: ["app_name": searchTask.browserAppName],
                    note: "Open \(searchTask.browserAppName)"
                ),
                AssistantHistoryStep(
                    title: "Search \(searchTask.query)",
                    action: "search_web",
                    targetApp: searchTask.browserAppName,
                    params: ["query": searchTask.query],
                    note: "Search \(searchTask.query)"
                )
            ]
        case .openApp(let openAppTask):
            return [
                AssistantHistoryStep(
                    title: "Open \(openAppTask.appName)",
                    action: "open_app",
                    targetApp: openAppTask.appName,
                    params: ["app_name": openAppTask.appName],
                    note: "Open \(openAppTask.appName)"
                )
            ]
        }
    }

    func mergeAssistantExecutionMetadata(
        _ stepResults: [ActionAssistantRecipeRunResult.StepResult]
    ) -> [AssistantHistoryStep] {
        let resultsByStepID = Dictionary(uniqueKeysWithValues: stepResults.map { ($0.stepID, $0) })
        return assistantStructuredHistory.enumerated().map { index, step in
            guard let result = resultsByStepID[index + 1] else { return step }
            return AssistantHistoryStep(
                id: step.id,
                title: step.title,
                action: step.action,
                targetApp: result.targetApp ?? step.targetApp,
                targetLabel: result.targetLabel ?? step.targetLabel,
                targetRole: result.targetRole ?? step.targetRole,
                relativeX: result.relativeX ?? step.relativeX,
                relativeY: result.relativeY ?? step.relativeY,
                resolvedTargetLabel: result.resolvedTargetLabel ?? step.resolvedTargetLabel,
                resolvedTargetRole: result.resolvedTargetRole ?? step.resolvedTargetRole,
                resolvedRelativeX: result.resolvedRelativeX ?? step.resolvedRelativeX,
                resolvedRelativeY: result.resolvedRelativeY ?? step.resolvedRelativeY,
                success: result.success,
                durationMs: result.durationMs,
                error: result.error,
                diagnosisCategory: result.diagnosisCategory ?? step.diagnosisCategory,
                diagnosisReason: result.diagnosisReason ?? step.diagnosisReason,
                params: step.params,
                note: result.note ?? step.note,
                waitAfter: step.waitAfter,
                recordedAt: step.recordedAt
            )
        }
    }

    func annotateAssistantHistoryWithDiagnosis(_ diagnosis: ActionAssistantStepDiagnosis?) {
        guard let diagnosis, !assistantStructuredHistory.isEmpty else { return }
        let lastIndex = assistantStructuredHistory.index(before: assistantStructuredHistory.endIndex)
        let step = assistantStructuredHistory[lastIndex]
        assistantStructuredHistory[lastIndex] = AssistantHistoryStep(
            id: step.id,
            title: step.title,
            action: step.action,
            targetApp: step.targetApp,
            targetLabel: step.targetLabel,
            targetRole: step.targetRole,
            relativeX: step.relativeX,
            relativeY: step.relativeY,
            resolvedTargetLabel: step.resolvedTargetLabel,
            resolvedTargetRole: step.resolvedTargetRole,
            resolvedRelativeX: step.resolvedRelativeX,
            resolvedRelativeY: step.resolvedRelativeY,
            success: step.success,
            durationMs: step.durationMs,
            error: step.error,
            diagnosisCategory: diagnosis.category,
            diagnosisReason: diagnosis.reason,
            params: step.params,
            note: step.note,
            waitAfter: step.waitAfter,
            recordedAt: step.recordedAt
        )
    }
}

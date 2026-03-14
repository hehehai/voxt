import Foundation

enum ActionAssistantRecipeDraftFactory {
    static func makeBlankRecipe(named recipeName: String) -> ActionAssistantRecipe {
        ActionAssistantRecipe(
            name: recipeName,
            description: "Describe what this recipe should do.",
            app: nil,
            enabled: true,
            pinned: false,
            params: [
                "app_name": .init(
                    type: "string",
                    description: "The app to open or focus.",
                    required: false
                )
            ],
            preconditions: nil,
            steps: [
                .init(
                    id: 1,
                    action: "open_app",
                    targetApp: nil,
                    target: nil,
                    params: ["app_name": "App Name"],
                    waitAfter: .init(condition: "appFocused", value: "App Name", timeout: 5),
                    note: "Replace this step with the first action to perform.",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop",
            learnedMetrics: nil
        )
    }

    static func makeHistoryDraftRecipe(
        named recipeName: String,
        summary: String,
        spokenText: String,
        actions: [String],
        structuredSteps: [AssistantHistoryStep],
        focusedAppName: String?
    ) -> ActionAssistantRecipe {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSpokenText = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = focusedAppName?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ActionAssistantRecipe(
            name: recipeName,
            description: draftDescription(
                summary: trimmedSummary,
                spokenText: trimmedSpokenText,
                actions: actions
            ),
            app: appName?.isEmpty == false ? appName : nil,
            enabled: true,
            pinned: false,
            params: [
                "target": .init(
                    type: "string",
                    description: "Replace with the app, page, or item this draft should target.",
                    required: false
                )
            ],
            preconditions: appName?.isEmpty == false ? .init(appRunning: appName, urlContains: nil) : nil,
            steps: draftSteps(
                structuredSteps: structuredSteps,
                actions: actions,
                appName: appName
            ),
            onFailure: "stop",
            learnedMetrics: nil
        )
    }

    private static func draftDescription(summary: String, spokenText: String, actions: [String]) -> String {
        var lines: [String] = []
        if !summary.isEmpty {
            lines.append(summary)
        }
        if !spokenText.isEmpty, spokenText != summary {
            lines.append("Original request: " + spokenText)
        }
        if !actions.isEmpty {
            lines.append("Observed actions:")
            lines.append(contentsOf: actions.map { "- " + $0 })
        }
        return lines.joined(separator: "\n")
    }

    private static func draftSteps(
        structuredSteps: [AssistantHistoryStep],
        actions: [String],
        appName: String?
    ) -> [ActionAssistantRecipe.Step] {
        guard !structuredSteps.isEmpty else {
            return [
                .init(
                    id: 1,
                    action: "open_app",
                    targetApp: nil,
                    target: nil,
                    params: ["app_name": appName?.isEmpty == false ? appName! : "App Name"],
                    waitAfter: .init(
                        condition: "appFocused",
                        value: appName?.isEmpty == false ? appName! : "App Name",
                        timeout: 5
                    ),
                    note: actions.isEmpty
                        ? "Replace this placeholder with the first step from the history entry."
                        : "Observed actions: " + actions.joined(separator: " -> "),
                    onFailure: "stop"
                )
            ]
        }

        return structuredSteps.enumerated().map { index, step in
            var params = step.params ?? (index == 0 && appName?.isEmpty == false ? ["app_name": appName!] : nil)
            if let relativeX = step.resolvedRelativeX ?? step.relativeX {
                params = params ?? [:]
                params?["relative_x"] = String(relativeX)
            }
            if let relativeY = step.resolvedRelativeY ?? step.relativeY {
                params = params ?? [:]
                params?["relative_y"] = String(relativeY)
            }

            return .init(
                id: index + 1,
                action: step.action ?? (index == 0 ? "open_app" : "click"),
                targetApp: step.targetApp,
                target: makeTarget(from: step),
                params: params,
                waitAfter: step.waitAfter.map {
                    .init(condition: $0.condition, value: $0.value, timeout: $0.timeout)
                },
                note: step.note ?? step.title,
                onFailure: "stop"
            )
        }
    }

    private static func makeTarget(from step: AssistantHistoryStep) -> ActionAssistantRecipe.Step.Target? {
        let label = step.resolvedTargetLabel ?? step.targetLabel
        let role = step.resolvedTargetRole ?? step.targetRole
        guard label != nil || role != nil else { return nil }

        var criteria: [ActionAssistantRecipe.Step.Target.Criterion] = []
        if let targetRole = role, !targetRole.isEmpty {
            criteria.append(.init(attribute: "AXRole", value: targetRole))
        }

        return .init(
            criteria: criteria.isEmpty ? nil : criteria,
            computedNameContains: label
        )
    }
}

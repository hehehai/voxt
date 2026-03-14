import Foundation

enum ActionAssistantVerifier {
    static func assessOutcome(
        plan: ActionAssistantPlan,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot
    ) -> ActionAssistantOutcomeAssessment? {
        if let assessment = assessTargets(plan: plan) {
            return assessment
        }
        if let assessment = assessFocusState(plan: plan, before: before, after: after) {
            return assessment
        }
        if let assessment = assessOpenApp(plan: plan, after: after) {
            return assessment
        }
        if let assessment = assessURL(plan: plan, before: before, after: after) {
            return assessment
        }
        if let assessment = assessTitle(plan: plan, before: before, after: after) {
            return assessment
        }
        if let assessment = assessWindowState(plan: plan, before: before, after: after) {
            return assessment
        }
        if let assessment = assessSelectedText(plan: plan, before: before, after: after) {
            return assessment
        }
        return nil
    }

    static func assessVisualOutcome(
        plan: ActionAssistantPlan,
        after: ActionAssistantPerceptionSnapshot
    ) async -> ActionAssistantOutcomeAssessment? {
        guard let screenshotPath = after.visualContext?.screenshotPath,
              !screenshotPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let step = plan.steps.reversed().first(where: { $0.waitAfter?.condition.lowercased() == "elementexists" }),
           let targetDescription = visualTargetDescription(for: step, expectedOutcome: plan.expectedOutcome),
           let grounded = await ActionAssistantVisualLocator.locate(
            targetDescription: targetDescription,
            preferredAppName: step.targetApp ?? plan.app,
            screenshotPath: screenshotPath
           ),
           let assessment = visualAssessment(
            from: grounded,
            shouldExist: true,
            targetDescription: targetDescription
           ) {
            return assessment
        }

        if let step = plan.steps.reversed().first(where: { $0.waitAfter?.condition.lowercased() == "elementgone" }),
           let targetDescription = visualTargetDescription(for: step, expectedOutcome: plan.expectedOutcome),
           let grounded = await ActionAssistantVisualLocator.locate(
            targetDescription: targetDescription,
            preferredAppName: step.targetApp ?? plan.app,
            screenshotPath: screenshotPath
           ),
           let assessment = visualAssessment(
            from: grounded,
            shouldExist: false,
            targetDescription: targetDescription
           ) {
            return assessment
        }

        if let step = plan.steps.reversed().first(where: { ["click", "focus", "hover", "long_press"].contains($0.action) }),
           let targetDescription = visualTargetDescription(for: step, expectedOutcome: plan.expectedOutcome),
           let grounded = await ActionAssistantVisualLocator.locate(
            targetDescription: targetDescription,
            preferredAppName: step.targetApp ?? plan.app,
            screenshotPath: screenshotPath
           ),
           grounded.isVisible(confidenceThreshold: 0.7) {
            return ActionAssistantOutcomeAssessment(
                satisfied: true,
                reason: "Visual target '\(grounded.displayLabel(fallback: targetDescription))' is present."
            )
        }

        return nil
    }

    static func diagnoseFailure(
        plan: ActionAssistantPlan,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot
    ) async -> ActionAssistantStepDiagnosis? {
        guard let step = plan.steps.reversed().first(where: { ["click", "focus", "hover", "long_press", "drag"].contains($0.action) }) else {
            return nil
        }

        let expectedLabel = step.target?.computedNameContains?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedRole = step.target?.criteria?.first(where: { $0.attribute.caseInsensitiveCompare("AXRole") == .orderedSame })?.value

        if let expectedLabel,
           let afterName = after.focusedElementName,
           !afterName.localizedCaseInsensitiveContains(expectedLabel),
           before.focusedElementName == after.focusedElementName {
            return ActionAssistantStepDiagnosis(
                category: "target_miss",
                reason: "Last step likely missed the target '\(expectedLabel)' because focus did not move."
            )
        }

        if let expectedRole,
           let afterRole = after.focusedElementRole,
           !afterRole.localizedCaseInsensitiveContains(expectedRole),
           step.action == "focus" {
            return ActionAssistantStepDiagnosis(
                category: "wrong_focus",
                reason: "Focus changed to role '\(afterRole)' instead of the expected '\(expectedRole)'."
            )
        }

        guard let screenshotPath = after.visualContext?.screenshotPath,
              !screenshotPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let targetDescription = visualTargetDescription(for: step, expectedOutcome: plan.expectedOutcome),
              let grounded = await ActionAssistantVisualLocator.locate(
                targetDescription: targetDescription,
                preferredAppName: step.targetApp ?? plan.app,
                screenshotPath: screenshotPath
              ) else {
            return nil
        }

        if !grounded.isVisible(confidenceThreshold: 0.45) {
            return ActionAssistantStepDiagnosis(
                category: "target_missing",
                reason: "The target '\(targetDescription)' was not visible after execution."
            )
        }

        return ActionAssistantStepDiagnosis(
            category: "state_unchanged",
            reason: "The target '\(grounded.displayLabel(fallback: targetDescription))' still appears present, but the expected state change did not happen."
        )
    }

    private static func assessFocusState(
        plan: ActionAssistantPlan,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot
    ) -> ActionAssistantOutcomeAssessment? {
        if let focusStep = plan.steps.reversed().first(where: { $0.action == "focus" || $0.action == "click" }) {
            if let targetName = focusStep.target?.computedNameContains, !targetName.isEmpty,
               let afterName = after.focusedElementName, !afterName.isEmpty {
                let satisfied = afterName.localizedCaseInsensitiveContains(targetName)
                return ActionAssistantOutcomeAssessment(
                    satisfied: satisfied,
                    reason: satisfied
                        ? "Focused element is \(afterName)."
                        : "Focused element is \(afterName), expected something matching \(targetName)."
                )
            }

            if let targetCriteria = focusStep.target?.criteria,
               let roleCriterion = targetCriteria.first(where: { $0.attribute.caseInsensitiveCompare("AXRole") == .orderedSame }),
               let afterRole = after.focusedElementRole, !afterRole.isEmpty {
                let satisfied = afterRole.localizedCaseInsensitiveContains(roleCriterion.value)
                return ActionAssistantOutcomeAssessment(
                    satisfied: satisfied,
                    reason: satisfied
                        ? "Focused element role is \(afterRole)."
                        : "Focused element role is \(afterRole), expected \(roleCriterion.value)."
                )
            }
        }

        guard let expectedOutcome = plan.expectedOutcome?.lowercased(), !expectedOutcome.isEmpty else {
            return nil
        }

        if expectedOutcome.contains("focus") || expectedOutcome.contains("cursor") || expectedOutcome.contains("input") {
            if let beforeName = before.focusedElementName,
               let afterName = after.focusedElementName,
               beforeName != afterName {
                return ActionAssistantOutcomeAssessment(
                    satisfied: true,
                    reason: "Focused element changed from \(beforeName) to \(afterName)."
                )
            }

            if let afterRole = after.focusedElementRole,
               (afterRole.localizedCaseInsensitiveContains("text")
                || afterRole.localizedCaseInsensitiveContains("field")
                || afterRole.localizedCaseInsensitiveContains("area")) {
                return ActionAssistantOutcomeAssessment(
                    satisfied: true,
                    reason: "Focused element role is \(afterRole)."
                )
            }
        }

        return nil
    }

    private static func assessTargets(plan: ActionAssistantPlan) -> ActionAssistantOutcomeAssessment? {
        for step in plan.steps.reversed() {
            if let waitAfter = step.waitAfter,
               let assessment = assessWaitCondition(waitAfter, step: step) {
                return assessment
            }

            if step.action == "focus",
               let target = step.target {
                let focused = ActionAssistantTargetResolver.focusedElementMatches(
                    target,
                    preferredAppName: step.targetApp ?? plan.app
                )
                return ActionAssistantOutcomeAssessment(
                    satisfied: focused,
                    reason: focused
                        ? "Focused element matches target."
                        : "Focused element does not match the expected target."
                )
            }
        }
        return nil
    }

    private static func assessWaitCondition(
        _ waitAfter: ActionAssistantRecipe.Step.WaitCondition,
        step: ActionAssistantRecipe.Step
    ) -> ActionAssistantOutcomeAssessment? {
        guard let target = step.target else { return nil }
        let preferredAppName = step.targetApp

        switch waitAfter.condition.lowercased() {
        case "elementexists":
            let exists = ActionAssistantTargetResolver.targetExists(target, preferredAppName: preferredAppName)
            return ActionAssistantOutcomeAssessment(
                satisfied: exists,
                reason: exists
                    ? "Expected element exists."
                    : "Expected element does not exist."
            )
        case "elementgone":
            let exists = ActionAssistantTargetResolver.targetExists(target, preferredAppName: preferredAppName)
            return ActionAssistantOutcomeAssessment(
                satisfied: !exists,
                reason: exists
                    ? "Element is still present."
                    : "Element is gone."
            )
        case "titlecontains":
            if let value = waitAfter.value, !value.isEmpty {
                let contains = ActionAssistantTargetResolver.appTitleContains(value, preferredAppName: preferredAppName)
                return ActionAssistantOutcomeAssessment(
                    satisfied: contains,
                    reason: contains
                        ? "Focused title contains \(value)."
                        : "Focused title does not contain \(value)."
                )
            }
            return nil
        default:
            return nil
        }
    }

    private static func assessOpenApp(
        plan: ActionAssistantPlan,
        after: ActionAssistantPerceptionSnapshot
    ) -> ActionAssistantOutcomeAssessment? {
        let openAppNames = plan.steps.compactMap { step -> String? in
            guard step.action == "open_app" else { return nil }
            return step.params?["app_name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let expectedApp = openAppNames.last, !expectedApp.isEmpty else { return nil }

        let satisfied = after.frontmostAppName?.localizedCaseInsensitiveContains(expectedApp) == true
        return ActionAssistantOutcomeAssessment(
            satisfied: satisfied,
            reason: satisfied
                ? "Frontmost app is \(after.frontmostAppName ?? expectedApp)."
                : "Frontmost app is \(after.frontmostAppName ?? "unknown"), expected \(expectedApp)."
        )
    }

    private static func assessURL(
        plan: ActionAssistantPlan,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot
    ) -> ActionAssistantOutcomeAssessment? {
        if let expectedURLString = plan.steps.reversed().first(where: { $0.action == "open_url" })?.params?["url"],
           let expectedURL = URL(string: expectedURLString),
           let actualURLString = after.currentURL {
            let normalizedActual = actualURLString.lowercased()
            let normalizedExpected = expectedURL.absoluteString.lowercased()
            let hostMatches = expectedURL.host.map { normalizedActual.contains($0.lowercased()) } ?? false
            let exactOrPrefix = normalizedActual == normalizedExpected || normalizedActual.hasPrefix(normalizedExpected)
            let satisfied = hostMatches || exactOrPrefix
            return ActionAssistantOutcomeAssessment(
                satisfied: satisfied,
                reason: satisfied
                    ? "Current URL is \(actualURLString)."
                    : "Current URL is \(actualURLString), expected \(expectedURL.absoluteString)."
            )
        }

        if plan.steps.contains(where: { $0.action == "search_web" }),
           let beforeURL = before.currentURL,
           let afterURL = after.currentURL {
            let changed = beforeURL != afterURL
            return ActionAssistantOutcomeAssessment(
                satisfied: changed,
                reason: changed
                    ? "Current URL changed to \(afterURL)."
                    : "Current URL did not change."
            )
        }

        return nil
    }

    private static func assessTitle(
        plan: ActionAssistantPlan,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot
    ) -> ActionAssistantOutcomeAssessment? {
        guard let expectedOutcome = plan.expectedOutcome?.lowercased(), !expectedOutcome.isEmpty else {
            return nil
        }
        guard let afterTitle = after.focusedWindowTitle, !afterTitle.isEmpty else {
            return nil
        }

        let extractedHints = extractQuotedHints(from: expectedOutcome)
        if let matchingHint = extractedHints.first(where: { afterTitle.localizedCaseInsensitiveContains($0) }) {
            return ActionAssistantOutcomeAssessment(
                satisfied: true,
                reason: "Focused title matches '\(matchingHint)'."
            )
        }

        if let beforeTitle = before.focusedWindowTitle,
           beforeTitle != afterTitle,
           (expectedOutcome.contains("title") || expectedOutcome.contains("window") || expectedOutcome.contains("page")) {
            return ActionAssistantOutcomeAssessment(
                satisfied: true,
                reason: "Focused title changed from \(beforeTitle) to \(afterTitle)."
            )
        }

        return nil
    }

    private static func assessSelectedText(
        plan: ActionAssistantPlan,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot
    ) -> ActionAssistantOutcomeAssessment? {
        guard let expectedOutcome = plan.expectedOutcome?.lowercased(), !expectedOutcome.isEmpty else {
            return nil
        }
        if expectedOutcome.contains("selected text") || expectedOutcome.contains("selection") {
            let changed = before.selectedText != after.selectedText
            return ActionAssistantOutcomeAssessment(
                satisfied: changed,
                reason: changed
                    ? "Selected text changed."
                    : "Selected text did not change."
            )
        }
        return nil
    }

    private static func assessWindowState(
        plan: ActionAssistantPlan,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot
    ) -> ActionAssistantOutcomeAssessment? {
        guard let expectedOutcome = plan.expectedOutcome?.lowercased(), !expectedOutcome.isEmpty else {
            return nil
        }

        if expectedOutcome.contains("window") || expectedOutcome.contains("frontmost") || expectedOutcome.contains("screen") {
            if before.focusedWindowOrigin != after.focusedWindowOrigin || before.focusedWindowSize != after.focusedWindowSize {
                return ActionAssistantOutcomeAssessment(
                    satisfied: true,
                    reason: "Focused window geometry changed."
                )
            }
        }

        return nil
    }

    private static func extractQuotedHints(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: "\"'“”‘’")
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
    }

    private static func visualTargetDescription(
        for step: ActionAssistantRecipe.Step,
        expectedOutcome: String?
    ) -> String? {
        let direct = step.target?.computedNameContains?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct, !direct.isEmpty {
            return direct
        }

        let note = step.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note, !note.isEmpty {
            return note
        }

        if let expectedOutcome {
            return extractQuotedHints(from: expectedOutcome).first
        }

        return nil
    }

    private static func visualAssessment(
        from grounded: ActionAssistantVisualGroundingResult,
        shouldExist: Bool,
        targetDescription: String
    ) -> ActionAssistantOutcomeAssessment? {
        let visible = grounded.isVisible()
        if shouldExist {
            return ActionAssistantOutcomeAssessment(
                satisfied: visible,
                reason: visible
                    ? "Visual target '\(grounded.displayLabel(fallback: targetDescription))' is present."
                    : "Visual target '\(targetDescription)' is not confidently visible."
            )
        }

        return ActionAssistantOutcomeAssessment(
            satisfied: !visible,
            reason: visible
                ? "Visual target '\(grounded.displayLabel(fallback: targetDescription))' is still visible."
                : "Visual target '\(targetDescription)' is gone."
        )
    }
}

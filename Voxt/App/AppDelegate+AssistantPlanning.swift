import Foundation

extension AppDelegate {
    func runAssistantPlanAttempt(
        _ plan: ActionAssistantPlan,
        originalRequest: String,
        runtime: ActionAssistantExecuting,
        sessionID: UUID,
        attempt: Int
    ) async throws -> String {
        let preExecutionSnapshot = await ActionAssistantPlanner.captureSnapshot()
        assistantLogInfo(
            "Assistant execution attempt. sessionID=\(sessionID.uuidString), attempt=\(attempt), summary=\(plan.summary), steps=\(plan.steps.count)"
        )

        let summary = try await executeAssistantPlan(plan, runtime: runtime, sessionID: sessionID)
        let postSnapshot = await ActionAssistantPlanner.captureSnapshot()
        assistantLogInfo(
            "Assistant post-execution snapshot. sessionID=\(sessionID.uuidString), attempt=\(attempt), frontmostApp=\(postSnapshot.frontmostAppName ?? "nil"), title=\(postSnapshot.focusedWindowTitle ?? "nil"), focusedElement=\(postSnapshot.focusedElementName ?? "nil"), focusedRole=\(postSnapshot.focusedElementRole ?? "nil"), url=\(postSnapshot.currentURL ?? "nil")"
        )

        try await verifyAssistantPlanOutcomeIfNeeded(
            originalRequest: originalRequest,
            plan: plan,
            before: preExecutionSnapshot,
            after: postSnapshot,
            sessionID: sessionID,
            attempt: attempt
        )
        return summary
    }

    func recoverAssistantPlan(
        originalRequest: String,
        currentPlan: ActionAssistantPlan,
        failureMessage: String,
        attempt: Int,
        sessionID: UUID
    ) async throws -> ActionAssistantPlan? {
        let repairedSnapshot = await ActionAssistantPlanner.captureSnapshot()
        assistantLogInfo(
            "Assistant repair snapshot. sessionID=\(sessionID.uuidString), attempt=\(attempt), frontmostApp=\(repairedSnapshot.frontmostAppName ?? "nil"), title=\(repairedSnapshot.focusedWindowTitle ?? "nil"), focusedElement=\(repairedSnapshot.focusedElementName ?? "nil"), focusedRole=\(repairedSnapshot.focusedElementRole ?? "nil"), url=\(repairedSnapshot.currentURL ?? "nil")"
        )

        guard let repairedPlan = try await generateAssistantRepairPlan(
            for: originalRequest,
            previousPlan: currentPlan,
            failure: failureMessage,
            snapshot: repairedSnapshot,
            attempt: attempt + 1,
            recentSteps: Array(assistantActionHistory.suffix(8)),
            sessionID: sessionID
        ) else {
            return nil
        }

        assistantLogInfo(
            "Assistant planner produced repaired plan. sessionID=\(sessionID.uuidString), attempt=\(attempt + 1), summary=\(repairedPlan.summary), steps=\(repairedPlan.steps.count), app=\(repairedPlan.app ?? "nil")"
        )
        recordAssistantStep("Replan \(attempt + 1)")
        return repairedPlan
    }

    func verifyAssistantPlanOutcomeIfNeeded(
        originalRequest: String,
        plan: ActionAssistantPlan,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot,
        sessionID: UUID,
        attempt: Int
    ) async throws {
        guard let expectedOutcome = plan.expectedOutcome, !expectedOutcome.isEmpty else {
            return
        }

        let assessment = try await verifyAssistantOutcome(
            originalRequest: originalRequest,
            expectedOutcome: expectedOutcome,
            plan: plan,
            before: before,
            after: after,
            sessionID: sessionID
        )
        assistantLogInfo(
            "Assistant outcome verification. sessionID=\(sessionID.uuidString), attempt=\(attempt), satisfied=\(assessment.satisfied), reason=\(assessment.reason)"
        )
        guard assessment.satisfied else {
            let diagnosis = await ActionAssistantVerifier.diagnoseFailure(
                plan: plan,
                before: before,
                after: after
            )
            assistantLastDiagnosis = diagnosis
            annotateAssistantHistoryWithDiagnosis(diagnosis)
            if let diagnosis {
                assistantLogWarning(
                    "Assistant step diagnosis. sessionID=\(sessionID.uuidString), attempt=\(attempt), category=\(diagnosis.category), reason=\(diagnosis.reason)"
                )
            }
            let failureReason = [assessment.reason, diagnosis?.reason]
                .compactMap { $0 }
                .joined(separator: " Diagnosis: ")
            throw NSError(
                domain: "Voxt.ActionAssistantOutcome",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Expected outcome not satisfied: \(failureReason)"]
            )
        }
    }
}

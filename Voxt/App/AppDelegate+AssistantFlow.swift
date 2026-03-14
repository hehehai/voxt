import Foundation
import AppKit

extension AppDelegate {
    private var assistantLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.actionAssistantLoggingEnabled)
    }

    func assistantLogInfo(_ message: @autoclosure () -> String) {
        guard assistantLoggingEnabled else { return }
        VoxtLog.info(message())
    }

    func assistantLogWarning(_ message: @autoclosure () -> String) {
        guard assistantLoggingEnabled else { return }
        VoxtLog.warning(message())
    }

    func processAssistantTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        assistantLogInfo("Assistant flow started. sessionID=\(sessionID.uuidString), inputChars=\(text.count)")
        setEnhancingState(true)
        overlayState.displayMode = .statusOnly
        overlayState.statusMessage = String(localized: "Preparing assistant task…")

        Task {
            defer {
                self.setEnhancingState(false)
            }

            let llmStartedAt = Date()
            var assistantHistorySnapshotPath: String?
            var matchedLearnedRecipeName: String?
            do {
                let enhanced = try await self.enhanceTextForCurrentMode(text)
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                assistantLogInfo("Assistant flow normalized spoken task. sessionID=\(sessionID.uuidString), outputChars=\(enhanced.count)")

                self.initializeAssistantStepHistory(with: [
                    "Normalize spoken task",
                    "Prepare Action Runtime"
                ])

                let runtime = EmbeddedActionAssistantRuntime()
                try await runtime.prepare()
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                assistantLogInfo("Assistant runtime prepared. sessionID=\(sessionID.uuidString)")

                let perceptionSnapshot = await ActionAssistantPlanner.captureSnapshot()
                assistantHistorySnapshotPath = perceptionSnapshot.visualContext?.screenshotPath
                assistantLogInfo(
                    "Assistant perception snapshot. sessionID=\(sessionID.uuidString), frontmostApp=\(perceptionSnapshot.frontmostAppName ?? "nil"), title=\(perceptionSnapshot.focusedWindowTitle ?? "nil"), focusedElement=\(perceptionSnapshot.focusedElementName ?? "nil"), focusedRole=\(perceptionSnapshot.focusedElementRole ?? "nil"), url=\(perceptionSnapshot.currentURL ?? "nil"), selectedTextChars=\(perceptionSnapshot.selectedText?.count ?? 0), screenshot=\(perceptionSnapshot.visualContext?.screenshotPath ?? "nil"), screenshotSize=\(perceptionSnapshot.visualContext?.width ?? 0)x\(perceptionSnapshot.visualContext?.height ?? 0)"
                )

                ActionAssistantRecipeStore.ensureBuiltInRecipesInstalled()
                if let matchedLearnedRecipe = ActionAssistantRecipeMatcher.matchLearnedRecipe(for: enhanced, snapshot: perceptionSnapshot) {
                    matchedLearnedRecipeName = matchedLearnedRecipe.recipe.name
                    assistantLogInfo("Assistant learned recipe matched. sessionID=\(sessionID.uuidString), recipe=\(matchedLearnedRecipe.recipe.name)")
                    let shouldRunRecipe = await MainActor.run {
                        self.confirmAssistantExecutionIfNeeded(summary: self.executionSummary(for: matchedLearnedRecipe))
                    }
                    guard shouldRunRecipe else {
                        assistantLogInfo("Assistant learned recipe cancelled by user. sessionID=\(sessionID.uuidString), recipe=\(matchedLearnedRecipe.recipe.name)")
                        self.cancelAssistantFlow(
                            text: enhanced,
                            startedAt: llmStartedAt,
                            summary: matchedLearnedRecipe.recipe.description,
                            snapshotPath: assistantHistorySnapshotPath
                        )
                        return
                    }
                    self.stageAssistantExecutionStep("Run \(matchedLearnedRecipe.recipe.name)")
                    self.assistantStructuredHistory = structuredHistorySteps(for: matchedLearnedRecipe.recipe)

                    let executionSummary = try await self.executeAssistantRecipe(
                        matchedLearnedRecipe,
                        runtime: runtime,
                        sessionID: sessionID
                    )
                    ActionAssistantRecipeStore.recordLearnedRecipeUsage(named: matchedLearnedRecipe.recipe.name, succeeded: true)
                    guard self.shouldHandleCallbacks(for: sessionID) else { return }

                    let llmDuration = Date().timeIntervalSince(llmStartedAt)
                    assistantLogInfo(
                        "Assistant learned recipe execution succeeded. sessionID=\(sessionID.uuidString), recipe=\(matchedLearnedRecipe.recipe.name), llmDurationSec=\(String(format: "%.3f", llmDuration)), summary=\(executionSummary)"
                    )
                    self.completeAssistantFlow(
                        text: enhanced,
                        startedAt: llmStartedAt,
                        summary: matchedLearnedRecipe.recipe.description,
                        snapshotPath: assistantHistorySnapshotPath
                    )
                    return
                }

                if let plan = try await self.generateAssistantPlan(
                    for: enhanced,
                    snapshot: perceptionSnapshot,
                    sessionID: sessionID
                ) {
                    assistantLogInfo(
                        "Assistant planner produced plan. sessionID=\(sessionID.uuidString), summary=\(plan.summary), steps=\(plan.steps.count), app=\(plan.app ?? "nil")"
                    )
                    let shouldRunPlan = await MainActor.run {
                        self.confirmAssistantExecutionIfNeeded(summary: self.executionSummary(for: plan))
                    }
                    guard shouldRunPlan else {
                        assistantLogInfo("Assistant plan cancelled by user. sessionID=\(sessionID.uuidString), summary=\(plan.summary)")
                        self.cancelAssistantFlow(
                            text: enhanced,
                            startedAt: llmStartedAt,
                            summary: plan.summary,
                            snapshotPath: assistantHistorySnapshotPath
                        )
                        return
                    }

                    let executionSummary = try await self.executeAssistantPlanWithRecovery(
                        plan,
                        originalRequest: enhanced,
                        runtime: runtime,
                        sessionID: sessionID
                    )
                    guard self.shouldHandleCallbacks(for: sessionID) else { return }

                    let llmDuration = Date().timeIntervalSince(llmStartedAt)
                    assistantLogInfo(
                        "Assistant planner execution succeeded. sessionID=\(sessionID.uuidString), inputChars=\(text.count), outputChars=\(enhanced.count), llmDurationSec=\(String(format: "%.3f", llmDuration)), summary=\(executionSummary)"
                    )
                    self.completeAssistantFlow(
                        text: enhanced,
                        startedAt: llmStartedAt,
                        summary: plan.summary,
                        snapshotPath: assistantHistorySnapshotPath
                    )
                    self.learnAssistantPlanIfNeeded(plan, originalRequest: enhanced)
                    return
                }

                if let matchedRecipe = ActionAssistantRecipeMatcher.matchRecipe(for: enhanced) {
                    assistantLogInfo("Assistant recipe matched. sessionID=\(sessionID.uuidString), recipe=\(matchedRecipe.recipe.name), substitutions=\(matchedRecipe.substitutions)")
                    let shouldRunRecipe = await MainActor.run {
                        self.confirmAssistantExecutionIfNeeded(summary: self.executionSummary(for: matchedRecipe))
                    }
                    guard shouldRunRecipe else {
                        assistantLogInfo("Assistant recipe cancelled by user. sessionID=\(sessionID.uuidString), recipe=\(matchedRecipe.recipe.name)")
                        self.cancelAssistantFlow(
                            text: enhanced,
                            startedAt: llmStartedAt,
                            summary: matchedRecipe.recipe.description,
                            snapshotPath: assistantHistorySnapshotPath
                        )
                        return
                    }
                    self.stageAssistantExecutionStep("Run \(matchedRecipe.recipe.name)")
                    self.assistantStructuredHistory = structuredHistorySteps(for: matchedRecipe.recipe)

                    let executionSummary = try await self.executeAssistantRecipe(
                        matchedRecipe,
                        runtime: runtime,
                        sessionID: sessionID
                    )
                    guard self.shouldHandleCallbacks(for: sessionID) else { return }

                    let llmDuration = Date().timeIntervalSince(llmStartedAt)
                    assistantLogInfo(
                        "Assistant recipe prepared. inputChars=\(text.count), outputChars=\(enhanced.count), llmDurationSec=\(String(format: "%.3f", llmDuration))"
                    )
                    assistantLogInfo(
                        "Embedded action runtime recipe execution succeeded. recipe=\(matchedRecipe.recipe.name), summary=\(executionSummary)"
                    )
                    self.completeAssistantFlow(
                        text: enhanced,
                        startedAt: llmStartedAt,
                        summary: matchedRecipe.recipe.description,
                        snapshotPath: assistantHistorySnapshotPath
                    )
                    return
                }

                guard let parsedTask = ActionAssistantTaskParser.parseTask(from: enhanced) else {
                    assistantLogWarning("Assistant flow produced no supported task. sessionID=\(sessionID.uuidString), normalizedText=\(VoxtLog.llmPreview(enhanced, limit: 300))")
                    self.failAssistantFlow(
                        text: enhanced,
                        startedAt: llmStartedAt,
                        summary: String(localized: "No supported assistant action detected."),
                        snapshotPath: assistantHistorySnapshotPath
                    )
                    return
                }
                assistantLogInfo("Assistant task parsed. sessionID=\(sessionID.uuidString), summary=\(self.executionSummary(for: parsedTask))")
                let shouldRunTask = await MainActor.run {
                    self.confirmAssistantExecutionIfNeeded(summary: self.executionSummary(for: parsedTask))
                }
                guard shouldRunTask else {
                    assistantLogInfo("Assistant task cancelled by user. sessionID=\(sessionID.uuidString), summary=\(self.executionSummary(for: parsedTask))")
                    self.cancelAssistantFlow(
                        text: enhanced,
                        startedAt: llmStartedAt,
                        summary: self.executionSummary(for: parsedTask),
                        snapshotPath: assistantHistorySnapshotPath
                    )
                    return
                }
                let executionSummary = try await self.executeAssistantTask(
                    parsedTask,
                    runtime: runtime,
                    sessionID: sessionID
                )
                guard self.shouldHandleCallbacks(for: sessionID) else { return }

                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                assistantLogInfo(
                    "Assistant task prepared. inputChars=\(text.count), outputChars=\(enhanced.count), llmDurationSec=\(String(format: "%.3f", llmDuration))"
                )
                assistantLogInfo(
                    "Embedded action runtime execution succeeded. summary=\(executionSummary)"
                )
                self.completeAssistantFlow(
                    text: enhanced,
                    startedAt: llmStartedAt,
                    summary: self.executionSummary(for: parsedTask),
                    snapshotPath: assistantHistorySnapshotPath
                )
            } catch {
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                if let learnedRecipeName = matchedLearnedRecipeName,
                   ActionAssistantRecipeStore.isLearnedRecipeName(learnedRecipeName) {
                    ActionAssistantRecipeStore.recordLearnedRecipeUsage(
                        named: learnedRecipeName,
                        succeeded: false,
                        diagnosisCategory: assistantLastDiagnosis?.category
                    )
                }
                let overlayMessage = String(localized: "Assistant task preparation failed.")
                assistantLogWarning("Assistant flow failed. sessionID=\(sessionID.uuidString), error=\(error), overlayMessage=\(overlayMessage)")
                self.failAssistantFlow(
                    text: text,
                    startedAt: llmStartedAt,
                    summary: overlayMessage,
                    snapshotPath: assistantHistorySnapshotPath
                )
            }
        }
    }

    private func executeAssistantTask(
        _ task: ActionAssistantParsedTask,
        runtime: ActionAssistantExecuting,
        sessionID: UUID
    ) async throws -> String {
        assistantStructuredHistory = structuredHistorySteps(for: task)
        assistantLogInfo("Assistant task execution started. sessionID=\(sessionID.uuidString), summary=\(executionSummary(for: task))")
        let execution = try await runtime.execute(task) { step in
            Task { @MainActor [weak self] in
                self?.recordAssistantStep(step)
            }
        }
        guard shouldHandleCallbacks(for: sessionID) else { return "cancelled" }
        return execution.summary
    }

    func executeAssistantPlan(
        _ plan: ActionAssistantPlan,
        runtime: ActionAssistantExecuting,
        sessionID: UUID
    ) async throws -> String {
        assistantStructuredHistory = structuredHistorySteps(for: ActionAssistantPlanner.recipe(from: plan))
        assistantLogInfo("Assistant plan execution started. sessionID=\(sessionID.uuidString), summary=\(plan.summary), steps=\(plan.steps.count)")
        let execution = try await runtime.execute(plan: plan) { step in
            Task { @MainActor [weak self] in
                self?.recordAssistantStep(step)
            }
        }
        if let stepResults = execution.stepResults {
            assistantStructuredHistory = mergeAssistantExecutionMetadata(stepResults)
        }
        guard shouldHandleCallbacks(for: sessionID) else { return "cancelled" }
        return execution.summary
    }

    private func executeAssistantPlanWithRecovery(
        _ plan: ActionAssistantPlan,
        originalRequest: String,
        runtime: ActionAssistantExecuting,
        sessionID: UUID
    ) async throws -> String {
        let maxPlanAttempts = 3
        var currentPlan = plan
        var lastError: Error?

        for attempt in 1...maxPlanAttempts {
            do {
                let summary = try await runAssistantPlanAttempt(
                    currentPlan,
                    originalRequest: originalRequest,
                    runtime: runtime,
                    sessionID: sessionID,
                    attempt: attempt
                )
                return summary
            } catch {
                guard shouldHandleCallbacks(for: sessionID) else { throw error }
                lastError = error
                let failureMessage = error.localizedDescription
                assistantLogWarning(
                    "Assistant plan execution failed. sessionID=\(sessionID.uuidString), attempt=\(attempt), summary=\(currentPlan.summary), error=\(failureMessage)"
                )

                guard attempt < maxPlanAttempts else {
                    break
                }

                guard let repairedPlan = try await recoverAssistantPlan(
                    originalRequest: originalRequest,
                    currentPlan: currentPlan,
                    failureMessage: failureMessage,
                    attempt: attempt,
                    sessionID: sessionID
                ) else {
                    throw error
                }
                currentPlan = repairedPlan
            }
        }

        throw lastError ?? NSError(
            domain: "Voxt.ActionAssistantPlan",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Action plan failed after multiple attempts."]
        )
    }

    private func executeAssistantRecipe(
        _ matchedRecipe: ActionAssistantMatchedRecipe,
        runtime: ActionAssistantExecuting,
        sessionID: UUID
    ) async throws -> String {
        assistantStructuredHistory = structuredHistorySteps(for: matchedRecipe.recipe)
        assistantLogInfo("Assistant recipe execution started. sessionID=\(sessionID.uuidString), recipe=\(matchedRecipe.recipe.name)")
        let execution = try await runtime.execute(
            recipe: matchedRecipe.recipe,
            substitutions: matchedRecipe.substitutions
        ) { step in
            Task { @MainActor [weak self] in
                self?.recordAssistantStep(step)
            }
        }
        assistantStructuredHistory = mergeAssistantExecutionMetadata(execution.stepResults)
        guard shouldHandleCallbacks(for: sessionID) else { return "cancelled" }
        return "recipe:\(execution.recipeName):\(execution.stepsCompleted)"
    }

    @MainActor
    private func confirmAssistantExecutionIfNeeded(summary: String) -> Bool {
        let requiresConfirmation = UserDefaults.standard.bool(forKey: AppPreferenceKey.actionAssistantRequiresConfirmation)
        guard requiresConfirmation else { return true }

        let alert = NSAlert()
        alert.messageText = String(localized: "Run Action Assistant?")
        alert.informativeText = summary
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Run"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func executionSummary(for matchedRecipe: ActionAssistantMatchedRecipe) -> String {
        let substitutions = matchedRecipe.substitutions
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        if substitutions.isEmpty {
            return "\(matchedRecipe.recipe.description)\n\nRecipe: \(matchedRecipe.recipe.name)"
        }
        return "\(matchedRecipe.recipe.description)\n\nRecipe: \(matchedRecipe.recipe.name)\n\(substitutions)"
    }

    private func executionSummary(for plan: ActionAssistantPlan) -> String {
        var sections: [String] = [plan.summary]

        if let app = plan.app, !app.isEmpty {
            sections.append("App: \(app)")
        }
        if let expectedOutcome = plan.expectedOutcome, !expectedOutcome.isEmpty {
            sections.append("Expected: \(expectedOutcome)")
        }
        if let preconditions = plan.preconditions {
            var preconditionLines: [String] = []
            if let appRunning = preconditions.appRunning, !appRunning.isEmpty {
                preconditionLines.append("App running: \(appRunning)")
            }
            if let urlContains = preconditions.urlContains, !urlContains.isEmpty {
                preconditionLines.append("URL contains: \(urlContains)")
            }
            if !preconditionLines.isEmpty {
                sections.append(preconditionLines.joined(separator: "\n"))
            }
        }

        let stepLines = plan.steps.map { step in
            let label = step.note ?? step.action
            return "\(step.id). \(label)"
        }.joined(separator: "\n")

        if stepLines.isEmpty {
            return sections.joined(separator: "\n\n")
        }
        sections.append(stepLines)
        return sections.joined(separator: "\n\n")
    }

    private func executionSummary(for task: ActionAssistantParsedTask) -> String {
        switch task {
        case .browserNavigation(let navigationTask):
            return "Open \(navigationTask.browserAppName)\nURL: \(navigationTask.url.absoluteString)"
        case .browserSearch(let searchTask):
            return "Open \(searchTask.browserAppName)\nSearch: \(searchTask.query)"
        case .openApp(let openAppTask):
            return "Open app: \(openAppTask.appName)"
        }
    }

    private func generateAssistantPlan(
        for text: String,
        snapshot: ActionAssistantPerceptionSnapshot,
        sessionID: UUID
    ) async throws -> ActionAssistantPlan? {
        let planningPrompt = ActionAssistantPlanner.prompt(for: text, snapshot: snapshot)
        let plannerOutput = try await requestAssistantPlannerOutput(
            prompt: planningPrompt,
            sessionID: sessionID,
            imageFileURL: snapshot.visualContext?.screenshotPath.map { URL(fileURLWithPath: $0) }
        )
        let preview = VoxtLog.llmPreview(plannerOutput, limit: 900)
        assistantLogInfo("Assistant planner raw output. sessionID=\(sessionID.uuidString), output=\(preview)")
        guard let plan = ActionAssistantPlanner.decodePlan(from: plannerOutput),
              !plan.steps.isEmpty,
              plan.summary.lowercased() != "unsupported" else {
            assistantLogWarning("Assistant planner produced no executable plan. sessionID=\(sessionID.uuidString), output=\(preview)")
            return nil
        }
        return plan
    }

    func generateAssistantRepairPlan(
        for text: String,
        previousPlan: ActionAssistantPlan,
        failure: String,
        snapshot: ActionAssistantPerceptionSnapshot,
        attempt: Int,
        recentSteps: [String],
        sessionID: UUID
    ) async throws -> ActionAssistantPlan? {
        let planningPrompt = ActionAssistantPlanner.repairPrompt(
            for: text,
            snapshot: snapshot,
            previousPlan: previousPlan,
            failure: failure,
            attempt: attempt,
            recentSteps: recentSteps
        )
        let plannerOutput = try await requestAssistantPlannerOutput(
            prompt: planningPrompt,
            sessionID: sessionID,
            imageFileURL: snapshot.visualContext?.screenshotPath.map { URL(fileURLWithPath: $0) }
        )
        let preview = VoxtLog.llmPreview(plannerOutput, limit: 900)
        assistantLogInfo("Assistant repair planner raw output. sessionID=\(sessionID.uuidString), output=\(preview)")
        guard let plan = ActionAssistantPlanner.decodePlan(from: plannerOutput),
              !plan.steps.isEmpty,
              plan.summary.lowercased() != "unsupported" else {
            assistantLogWarning("Assistant repair planner produced no executable plan. sessionID=\(sessionID.uuidString), output=\(preview)")
            return nil
        }
        return plan
    }

    private func requestAssistantPlannerOutput(
        prompt: String,
        sessionID: UUID,
        purpose: String = "planner",
        imageFileURL: URL? = nil
    ) async throws -> String {
        let plannerOutput: String

        switch enhancementMode {
        case .off:
            return ""
        case .appleIntelligence:
            guard let enhancer else { return "" }
            if #available(macOS 26.0, *) {
                plannerOutput = try await enhancer.enhance(userPrompt: prompt)
            } else {
                return ""
            }
        case .customLLM:
            plannerOutput = try await customLLMManager.enhance(userPrompt: prompt)
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: false)
            plannerOutput = try await RemoteLLMRuntimeClient().enhance(
                userPrompt: prompt,
                provider: context.provider,
                configuration: context.configuration,
                imageFileURL: imageFileURL
            )
        }
        assistantLogInfo("Assistant LLM output ready. sessionID=\(sessionID.uuidString), purpose=\(purpose), chars=\(plannerOutput.count)")
        return plannerOutput
    }

    func verifyAssistantOutcome(
        originalRequest: String,
        expectedOutcome: String,
        plan: ActionAssistantPlan,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot,
        sessionID: UUID
    ) async throws -> ActionAssistantOutcomeAssessment {
        if let localAssessment = ActionAssistantVerifier.assessOutcome(
            plan: plan,
            before: before,
            after: after
        ) {
            assistantLogInfo(
                "Assistant outcome verifier local assessment. sessionID=\(sessionID.uuidString), satisfied=\(localAssessment.satisfied), reason=\(localAssessment.reason)"
            )
            return localAssessment
        }

        if let visualAssessment = await ActionAssistantVerifier.assessVisualOutcome(
            plan: plan,
            after: after
        ) {
            assistantLogInfo(
                "Assistant outcome verifier visual assessment. sessionID=\(sessionID.uuidString), satisfied=\(visualAssessment.satisfied), reason=\(visualAssessment.reason)"
            )
            return visualAssessment
        }

        let prompt = ActionAssistantPlanner.outcomeVerificationPrompt(
            for: originalRequest,
            expectedOutcome: expectedOutcome,
            before: before,
            after: after
        )
        let output = try await requestAssistantPlannerOutput(
            prompt: prompt,
            sessionID: sessionID,
            purpose: "outcome_verification",
            imageFileURL: after.visualContext?.screenshotPath.map { URL(fileURLWithPath: $0) }
        )
        let preview = VoxtLog.llmPreview(output, limit: 300)
        assistantLogInfo("Assistant outcome verifier raw output. sessionID=\(sessionID.uuidString), output=\(preview)")
        return ActionAssistantPlanner.decodeOutcomeAssessment(from: output)
            ?? ActionAssistantOutcomeAssessment(satisfied: true, reason: "Verifier output unavailable; defaulting to success.")
    }

    private func learnAssistantPlanIfNeeded(_ plan: ActionAssistantPlan, originalRequest: String) {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.actionAssistantLearnSuccessfulPlansEnabled) else {
            return
        }
        do {
            if let recipeName = try ActionAssistantRecipeStore.saveLearnedRecipe(from: plan, userRequest: originalRequest) {
                assistantLogInfo("Assistant learned recipe saved. name=\(recipeName), steps=\(plan.steps.count)")
            }
        } catch {
            assistantLogWarning("Assistant learned recipe save failed. error=\(error)")
        }
    }
}

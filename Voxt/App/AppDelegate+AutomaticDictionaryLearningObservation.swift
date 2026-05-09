import Foundation
import AppKit

extension AppDelegate {
    func scheduleAutomaticDictionaryLearningIfNeeded(
        insertedText rawInsertedText: String,
        outputMode: SessionOutputMode,
        didInject: Bool,
        historyEntryID: UUID?
    ) {
        guard didInject else {
            VoxtLog.info("Automatic dictionary learning skipped: text was not injected.")
            return
        }
        guard outputMode == .transcription else {
            VoxtLog.info(
                "Automatic dictionary learning skipped: output mode is \(RecordingSessionSupport.outputLabel(for: outputMode))."
            )
            return
        }
        guard dictionaryAutoLearningEnabled else {
            VoxtLog.info("Automatic dictionary learning skipped: feature disabled.")
            return
        }

        let insertedText = rawInsertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !insertedText.isEmpty else {
            VoxtLog.info("Automatic dictionary learning skipped: inserted text is empty.")
            return
        }

        let scope = currentDictionaryScope()
        let expectedBundleID = sessionTargetApplicationBundleID
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        VoxtLog.info(
            "Automatic dictionary learning scheduled. chars=\(insertedText.count), expectedBundleID=\(expectedBundleID ?? "nil"), historyEntryID=\(historyEntryID?.uuidString ?? "nil"), windowSec=\(Int(AutomaticDictionaryLearningMonitor.observationWindowSeconds)), idleSec=\(Int(AutomaticDictionaryLearningMonitor.idleSettleSeconds))"
        )

        pendingAutomaticDictionaryLearningTask?.cancel()
        pendingAutomaticDictionaryLearningTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pendingAutomaticDictionaryLearningTask = nil }
            await self.runAutomaticDictionaryLearningObservation(
                insertedText: insertedText,
                expectedBundleID: expectedBundleID,
                groupID: scope.groupID,
                groupNameSnapshot: scope.groupName,
                historyEntryID: historyEntryID
            )
        }
    }

    private func runAutomaticDictionaryLearningObservation(
        insertedText: String,
        expectedBundleID: String?,
        groupID: UUID?,
        groupNameSnapshot: String?,
        historyEntryID: UUID?
    ) async {
        do {
            VoxtLog.info(
                "Automatic dictionary learning observation started. expectedBundleID=\(expectedBundleID ?? "nil"), historyEntryID=\(historyEntryID?.uuidString ?? "nil")"
            )
            guard let baselineSnapshot = try await automaticDictionaryLearningBaselineSnapshot(
                expectedBundleID: expectedBundleID
            ) else {
                VoxtLog.info("Automatic dictionary learning stopped: baseline snapshot unavailable.")
                return
            }
            let baselineScopedText = AutomaticDictionaryLearningMonitor.observationScopedText(
                insertedText: insertedText,
                baselineText: baselineSnapshot.text,
                currentText: baselineSnapshot.text
            )
            VoxtLog.info(
                "Automatic dictionary learning baseline captured. chars=\(baselineSnapshot.text.count), scopedChars=\(baselineScopedText.count), role=\(baselineSnapshot.role ?? "unknown"), bundleID=\(baselineSnapshot.bundleIdentifier ?? "nil"), editable=\(baselineSnapshot.isEditable), focused=\(baselineSnapshot.isFocusedTarget), textSource=\(baselineSnapshot.textSource ?? "nil")"
            )

            let observation = try await automaticDictionaryLearningObservationResult(
                insertedText: insertedText,
                baselineSnapshot: baselineSnapshot,
                baselineScopedText: baselineScopedText,
                expectedBundleID: expectedBundleID
            )
            guard observation.didObserveChange else {
                VoxtLog.info("Automatic dictionary learning finished without detected user edits in observation window.")
                return
            }

            let requestOutcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
                insertedText: insertedText,
                baselineText: baselineScopedText,
                finalText: observation.finalText
            )
            guard case .ready(let request) = requestOutcome else {
                if case .skipped(let reason) = requestOutcome {
                    VoxtLog.info("Automatic dictionary learning skipped after diff analysis: \(reason)")
                }
                return
            }
            VoxtLog.info(
                "Automatic dictionary learning request ready. editRatio=\(String(format: "%.3f", request.editRatio)), changedBeforeChars=\(request.baselineChangedFragment.count), changedAfterChars=\(request.finalChangedFragment.count)"
            )

            try await analyzeAutomaticDictionaryLearningRequest(
                request,
                groupID: groupID,
                groupNameSnapshot: groupNameSnapshot,
                historyEntryID: historyEntryID
            )
        } catch is CancellationError {
            VoxtLog.info("Automatic dictionary learning cancelled.")
        } catch {
            VoxtLog.warning("Automatic dictionary learning failed: \(error)")
        }
    }

    private func automaticDictionaryLearningObservationResult(
        insertedText: String,
        baselineSnapshot: FocusedInputTextSnapshot,
        baselineScopedText: String,
        expectedBundleID: String?
    ) async throws -> AutomaticDictionaryLearningObservation {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: baselineScopedText
        )
        var lastChangeAt: Date?
        var didLogDeferredAnalysis = false
        let deadline = Date().addingTimeInterval(
            AutomaticDictionaryLearningMonitor.observationWindowSeconds
        )

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(
                nanoseconds: AutomaticDictionaryLearningMonitor.pollIntervalNanoseconds
            )

            let elapsedSinceLastChange = lastChangeAt.map { Date().timeIntervalSince($0) }
            state.lastChangeElapsedSeconds = elapsedSinceLastChange
            var shouldTerminateObservation = false

            if let snapshot = await currentFocusedInputTextSnapshotForAutomaticDictionaryLearning(
                expectedBundleID: expectedBundleID
            ) {
                let scopedText = AutomaticDictionaryLearningMonitor.observationScopedText(
                    insertedText: insertedText,
                    baselineText: baselineSnapshot.text,
                    currentText: snapshot.text
                )
                let previousText = state.latestText
                switch AutomaticDictionaryLearningMonitor.observeSnapshot(
                    text: scopedText,
                    elapsedSinceLastChange: elapsedSinceLastChange,
                    state: &state
                ) {
                case .continueObserving:
                    if scopedText == state.latestText, state.didObserveChange,
                       let elapsedSinceLastChange,
                       elapsedSinceLastChange >= AutomaticDictionaryLearningMonitor.idleSettleSeconds,
                       AutomaticDictionaryLearningMonitor.shouldContinueObservingForPotentialReplacement(
                            baselineText: baselineScopedText,
                            currentFinalText: state.latestText
                       ) {
                        if !didLogDeferredAnalysis {
                            VoxtLog.info(
                                "Automatic dictionary learning deferred analysis: latest observed edit still looks like an incomplete deletion/replacement."
                            )
                            didLogDeferredAnalysis = true
                        }
                        continue
                    }

                    if scopedText == previousText {
                        continue
                    }

                    VoxtLog.info(
                        "Automatic dictionary learning observed input change. previousChars=\(previousText.count), currentChars=\(scopedText.count), role=\(snapshot.role ?? "unknown"), editable=\(snapshot.isEditable), focused=\(snapshot.isFocusedTarget), textSource=\(snapshot.textSource ?? "nil")"
                    )
                    didLogDeferredAnalysis = false
                    lastChangeAt = Date()
                case .stopWithoutAnalysis:
                    shouldTerminateObservation = true
                case .settleForAnalysis:
                    shouldTerminateObservation = AutomaticDictionaryLearningMonitor.shouldFinalizeWhileFocused(
                        decision: .settleForAnalysis(finalText: state.latestText)
                    )
                }
            } else {
                switch AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state) {
                case .continueObserving:
                    continue
                case .stopWithoutAnalysis:
                    VoxtLog.info(
                        "Automatic dictionary learning stopped early: focused input missing for \(state.consecutiveMissingSnapshots) consecutive polls before any user edit."
                    )
                    shouldTerminateObservation = true
                case .settleForAnalysis:
                    VoxtLog.info(
                        "Automatic dictionary learning settled after observed edit while focus was missing for \(state.consecutiveMissingSnapshots) consecutive polls."
                    )
                    shouldTerminateObservation = true
                }
            }

            if shouldTerminateObservation {
                break
            }
        }

        if state.didObserveChange,
           AutomaticDictionaryLearningMonitor.shouldContinueObservingForPotentialReplacement(
                baselineText: state.baselineText,
                currentFinalText: state.latestText
           ) {
            VoxtLog.info(
                "Automatic dictionary learning finished without completed replacement inside observed text scope."
            )
            return AutomaticDictionaryLearningObservation(
                finalText: state.latestText,
                didObserveChange: false
            )
        }

        return AutomaticDictionaryLearningObservation(
            finalText: state.latestText,
            didObserveChange: state.didObserveChange
        )
    }

    private func automaticDictionaryLearningBaselineSnapshot(
        expectedBundleID: String?
    ) async throws -> FocusedInputTextSnapshot? {
        try await Task.sleep(
            nanoseconds: AutomaticDictionaryLearningMonitor.startupDelayNanoseconds
        )

        for attempt in 0..<AutomaticDictionaryLearningMonitor.initialSnapshotRetryCount {
            try Task.checkCancellation()
            if let snapshot = await currentFocusedInputTextSnapshotForAutomaticDictionaryLearning(
                expectedBundleID: expectedBundleID
            ) {
                return snapshot
            }
            guard attempt + 1 < AutomaticDictionaryLearningMonitor.initialSnapshotRetryCount else {
                break
            }
            try await Task.sleep(
                nanoseconds: AutomaticDictionaryLearningMonitor.initialSnapshotRetryNanoseconds
            )
        }

        return nil
    }
}

private struct AutomaticDictionaryLearningObservation {
    let finalText: String
    let didObserveChange: Bool
}

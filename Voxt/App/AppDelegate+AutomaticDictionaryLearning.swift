import Foundation
import AppKit

extension AppDelegate {
    private enum AutomaticDictionaryLearningModel {
        case appleIntelligence
        case customLLM(repo: String)
        case remoteLLM(provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration)
    }

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
            VoxtLog.info(
                "Automatic dictionary learning baseline captured. chars=\(baselineSnapshot.text.count), role=\(baselineSnapshot.role ?? "unknown"), bundleID=\(baselineSnapshot.bundleIdentifier ?? "nil"), editable=\(baselineSnapshot.isEditable), focused=\(baselineSnapshot.isFocusedTarget), textSource=\(baselineSnapshot.textSource ?? "nil")"
            )

            var latestText = baselineSnapshot.text
            var didObserveChange = false
            var lastChangeAt: Date?
            let deadline = Date().addingTimeInterval(
                AutomaticDictionaryLearningMonitor.observationWindowSeconds
            )

            while Date() < deadline {
                try Task.checkCancellation()
                try await Task.sleep(
                    nanoseconds: AutomaticDictionaryLearningMonitor.pollIntervalNanoseconds
                )

                guard let snapshot = await currentFocusedInputTextSnapshotForAutomaticDictionaryLearning(
                    expectedBundleID: expectedBundleID
                ) else {
                    VoxtLog.info("Automatic dictionary learning poll skipped: no focused input snapshot.")
                    continue
                }
                guard snapshot.text != latestText else {
                    if didObserveChange,
                       let lastChangeAt,
                       Date().timeIntervalSince(lastChangeAt)
                            >= AutomaticDictionaryLearningMonitor.idleSettleSeconds {
                        VoxtLog.info("Automatic dictionary learning settled after observed edit.")
                        break
                    }
                    continue
                }

                VoxtLog.info(
                    "Automatic dictionary learning observed input change. previousChars=\(latestText.count), currentChars=\(snapshot.text.count), role=\(snapshot.role ?? "unknown"), editable=\(snapshot.isEditable), focused=\(snapshot.isFocusedTarget), textSource=\(snapshot.textSource ?? "nil")"
                )
                latestText = snapshot.text
                didObserveChange = true
                lastChangeAt = Date()
            }

            guard didObserveChange else {
                VoxtLog.info("Automatic dictionary learning finished without detected user edits in observation window.")
                return
            }
            let requestOutcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
                insertedText: insertedText,
                baselineText: baselineSnapshot.text,
                finalText: latestText
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

    private func analyzeAutomaticDictionaryLearningRequest(
        _ request: AutomaticDictionaryLearningRequest,
        groupID: UUID?,
        groupNameSnapshot: String?,
        historyEntryID: UUID?
    ) async throws {
        let model = try resolvedAutomaticDictionaryLearningModel()
        VoxtLog.info(
            "Automatic dictionary learning analysis started. model=\(automaticDictionaryLearningModelDescription(model)), historyEntryID=\(historyEntryID?.uuidString ?? "nil")"
        )
        let existingTerms = dictionaryStore.entries.map(\.term)
        let prompt = AutomaticDictionaryLearningMonitor.buildPrompt(
            template: dictionaryAutoLearningPrompt,
            for: request,
            existingTerms: existingTerms,
            userMainLanguage: userMainLanguagePromptValue,
            userOtherLanguages: userOtherMainLanguagesPromptValue
        )
        let scannedTerms = try await runAutomaticDictionaryLearningPrompt(prompt, model: model)
        VoxtLog.info(
            "Automatic dictionary learning model returned \(scannedTerms.count) candidate terms: \(scannedTerms.joined(separator: ", "))"
        )

        var addedTerms: [String] = []
        for term in scannedTerms {
            let normalized = DictionaryStore.normalizeTerm(term)
            guard !normalized.isEmpty else {
                VoxtLog.info("Automatic dictionary learning ignored blank/invalid term candidate.")
                continue
            }
            guard !dictionaryStore.hasEntry(normalizedTerm: normalized, activeGroupID: groupID) else {
                VoxtLog.info("Automatic dictionary learning skipped existing term: \(term)")
                continue
            }
            do {
                try dictionaryStore.createAutoEntry(
                    term: term,
                    groupID: groupID,
                    groupNameSnapshot: groupNameSnapshot
                )
                addedTerms.append(term)
            } catch DictionaryStoreError.duplicateTerm {
                continue
            } catch {
                VoxtLog.warning("Automatic dictionary learning skipped term due to store error: \(error)")
            }
        }

        guard !addedTerms.isEmpty else {
            VoxtLog.info("Automatic dictionary learning finished with no new dictionary entries.")
            return
        }
        if let historyEntryID {
            historyStore.applyDictionaryCorrectedTerms([historyEntryID: addedTerms])
            VoxtLog.info(
                "Automatic dictionary learning recorded terms into history. historyEntryID=\(historyEntryID.uuidString), terms=\(addedTerms.joined(separator: ", "))"
            )
        } else {
            VoxtLog.info("Automatic dictionary learning added terms but history entry is unavailable.")
        }
        let message: String
        if addedTerms.count == 1 {
            message = AppLocalization.format(
                "Added 1 corrected term to the dictionary: %@",
                addedTerms[0]
            )
        } else {
            message = AppLocalization.format(
                "Added %d corrected terms to the dictionary: %@",
                addedTerms.count,
                addedTerms.joined(separator: ", ")
            )
        }
        showOverlayStatus(message, clearAfter: 3.2)
        VoxtLog.info("Automatic dictionary learning added terms: \(addedTerms.joined(separator: ", "))")
    }

    private func runAutomaticDictionaryLearningPrompt(
        _ prompt: String,
        model: AutomaticDictionaryLearningModel
    ) async throws -> [String] {
        switch model {
        case .appleIntelligence:
            guard let enhancer else {
                throw NSError(
                    domain: "Voxt.AutomaticDictionaryLearning",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Apple Intelligence is unavailable.")]
                )
            }
            if #available(macOS 26.0, *) {
                return try await enhancer.dictionaryHistoryScanTerms(userPrompt: prompt)
            }
            throw NSError(
                domain: "Voxt.AutomaticDictionaryLearning",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Apple Intelligence requires macOS 26 or later.")]
            )
        case .customLLM(let repo):
            return try await customLLMManager.dictionaryHistoryScanTerms(
                userPrompt: prompt,
                repo: repo
            )
        case .remoteLLM(let provider, let configuration):
            return try await RemoteLLMRuntimeClient().dictionaryHistoryScanTerms(
                userPrompt: prompt,
                provider: provider,
                configuration: configuration
            )
        }
    }

    private func automaticDictionaryLearningModelDescription(
        _ model: AutomaticDictionaryLearningModel
    ) -> String {
        switch model {
        case .appleIntelligence:
            return "apple-intelligence"
        case .customLLM(let repo):
            return "local:\(repo)"
        case .remoteLLM(let provider, let configuration):
            return "remote:\(provider.rawValue):\(configuration.model)"
        }
    }

    private func resolvedAutomaticDictionaryLearningModel() throws -> AutomaticDictionaryLearningModel {
        if let saved = savedAutomaticDictionaryLearningModel() {
            return saved
        }

        if let firstOption = availableDictionaryHistoryScanModelOptions().first {
            return try automaticDictionaryLearningModel(for: firstOption.id)
        }

        if #available(macOS 26.0, *), enhancer != nil, TextEnhancer.isAvailable {
            return .appleIntelligence
        }

        throw NSError(
            domain: "Voxt.AutomaticDictionaryLearning",
            code: -3,
            userInfo: [
                NSLocalizedDescriptionKey: AppLocalization.localizedString(
                    "No usable LLM is available for automatic dictionary learning."
                )
            ]
        )
    }

    private func savedAutomaticDictionaryLearningModel() -> AutomaticDictionaryLearningModel? {
        let optionID = UserDefaults.standard.string(
            forKey: AppPreferenceKey.dictionarySuggestionIngestModelOptionID
        ) ?? ""
        guard !optionID.isEmpty else { return nil }
        return try? automaticDictionaryLearningModel(for: optionID)
    }

    private func automaticDictionaryLearningModel(
        for optionID: String
    ) throws -> AutomaticDictionaryLearningModel {
        if optionID.hasPrefix("local:") {
            let repo = String(optionID.dropFirst("local:".count))
            guard customLLMManager.isModelDownloaded(repo: repo) else {
                throw NSError(
                    domain: "Voxt.AutomaticDictionaryLearning",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Selected local model is not available.")]
                )
            }
            return .customLLM(repo: repo)
        }

        if optionID.hasPrefix("remote:") {
            let rawProvider = String(optionID.dropFirst("remote:".count))
            guard let provider = RemoteLLMProvider(rawValue: rawProvider) else {
                throw NSError(
                    domain: "Voxt.AutomaticDictionaryLearning",
                    code: -5,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Selected remote model is invalid.")]
                )
            }
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            guard configuration.isConfigured else {
                throw NSError(
                    domain: "Voxt.AutomaticDictionaryLearning",
                    code: -6,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Selected remote model is not configured.")]
                )
            }
            return .remoteLLM(provider: provider, configuration: configuration)
        }

        throw NSError(
            domain: "Voxt.AutomaticDictionaryLearning",
            code: -7,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("No model was selected for automatic dictionary learning.")]
        )
    }
}

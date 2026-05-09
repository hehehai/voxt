import Foundation

extension AppDelegate {
    private enum AutomaticDictionaryLearningModel {
        case appleIntelligence
        case customLLM(repo: String)
        case remoteLLM(provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration)
    }

    func analyzeAutomaticDictionaryLearningRequest(
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
        let directCandidateTerms = AutomaticDictionaryLearningMonitor.directCandidateTerms(
            for: request,
            existingTerms: existingTerms
        )
        let scannedTerms = try await runAutomaticDictionaryLearningPrompt(prompt, model: model)
        let mergedTerms = mergeDictionaryLearningTerms(
            directCandidateTerms,
            scannedTerms,
            excludeExistingTerms: true,
            existingTerms: existingTerms
        )
        VoxtLog.info(
            "Automatic dictionary learning candidate terms merged. direct=\(directCandidateTerms.joined(separator: ", ")), model=\(scannedTerms.joined(separator: ", ")), final=\(mergedTerms.joined(separator: ", "))"
        )

        let addedTerms = persistAutomaticDictionaryLearningTerms(
            mergedTerms,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot
        )

        guard !addedTerms.isEmpty else {
            VoxtLog.info("Automatic dictionary learning finished with no new dictionary entries.")
            return
        }
        if let historyEntryID {
            applyAutomaticDictionaryLearningHistoryUpdate(
                request,
                historyEntryID: historyEntryID,
                addedTerms: addedTerms
            )
            VoxtLog.info(
                "Automatic dictionary learning recorded correction into history. historyEntryID=\(historyEntryID.uuidString), terms=\(addedTerms.joined(separator: ", "))"
            )
        } else {
            VoxtLog.info("Automatic dictionary learning added terms but history entry is unavailable.")
        }
        showOverlayStatus(automaticDictionaryLearningSuccessMessage(for: addedTerms), clearAfter: 3.2)
        VoxtLog.info("Automatic dictionary learning added terms: \(addedTerms.joined(separator: ", "))")
    }

    func applyManualDictionaryCorrection(
        entry: TranscriptionHistoryEntry,
        correctedText rawCorrectedText: String
    ) async throws -> TranscriptionHistoryEntry? {
        let correctedText = rawCorrectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baselineText = HistoryCorrectionPresentation.correctedText(
            for: entry.text,
            snapshots: entry.dictionaryCorrectionSnapshots
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard entry.kind == .normal else {
            return historyStore.entry(id: entry.id) ?? entry
        }
        guard !correctedText.isEmpty else {
            throw NSError(
                domain: "Voxt.ManualDictionaryCorrection",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Corrected text cannot be empty.")]
            )
        }
        guard correctedText != baselineText else {
            return historyStore.entry(id: entry.id) ?? entry
        }

        let existingTerms = dictionaryStore.entries.map(\.term)
        var correctedTerms: [String] = []
        var correctionSnapshots: [DictionaryCorrectionSnapshot] = []

        let requestOutcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: baselineText,
            baselineText: baselineText,
            finalText: correctedText
        )
        switch requestOutcome {
        case .ready(let request):
            let directCandidateTerms = AutomaticDictionaryLearningMonitor.directCandidateTerms(
                for: request,
                existingTerms: existingTerms
            )
            var scannedTerms: [String] = []
            if let model = try? resolvedAutomaticDictionaryLearningModel() {
                let prompt = AutomaticDictionaryLearningMonitor.buildPrompt(
                    template: dictionaryAutoLearningPrompt,
                    for: request,
                    existingTerms: existingTerms,
                    userMainLanguage: userMainLanguagePromptValue,
                    userOtherLanguages: userOtherMainLanguagesPromptValue
                )
                do {
                    scannedTerms = try await runAutomaticDictionaryLearningPrompt(prompt, model: model)
                } catch {
                    VoxtLog.warning("Manual dictionary correction term analysis failed: \(error)")
                }
            }

            correctedTerms = mergeDictionaryLearningTerms(
                directCandidateTerms,
                scannedTerms,
                excludeExistingTerms: false,
                existingTerms: existingTerms
            )
            correctionSnapshots = automaticDictionaryLearningHistorySnapshots(
                request: request,
                updatedText: correctedText
            )
        case .skipped(let reason):
            VoxtLog.info("Manual dictionary correction skipped term analysis: \(reason)")
        }

        let matchedGroupID = entry.matchedGroupID ?? currentDictionaryScope().groupID
        let matchedGroupName = entry.matchedGroupName ?? currentDictionaryScope().groupName
        let addedTerms = persistAutomaticDictionaryLearningTerms(
            correctedTerms,
            groupID: matchedGroupID,
            groupNameSnapshot: matchedGroupName
        )

        historyStore.replaceDictionaryCorrectionResult(
            historyID: entry.id,
            updatedText: correctedText,
            correctedTerms: correctedTerms,
            correctionSnapshots: correctionSnapshots
        )

        if !addedTerms.isEmpty {
            showOverlayStatus(automaticDictionaryLearningSuccessMessage(for: addedTerms), clearAfter: 3.2)
        }

        return historyStore.entry(id: entry.id)
    }

    private func persistAutomaticDictionaryLearningTerms(
        _ scannedTerms: [String],
        groupID: UUID?,
        groupNameSnapshot: String?
    ) -> [String] {
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
        return addedTerms
    }

    private func mergeDictionaryLearningTerms(
        _ directTerms: [String],
        _ modelTerms: [String],
        excludeExistingTerms: Bool,
        existingTerms: [String]
    ) -> [String] {
        let existingNormalized = Set(existingTerms.map(DictionaryStore.normalizeTerm))
        var merged: [String] = []
        var seen: Set<String> = []

        for term in directTerms + modelTerms {
            let normalized = DictionaryStore.normalizeTerm(term)
            guard !normalized.isEmpty,
                  !seen.contains(normalized) else {
                continue
            }
            if excludeExistingTerms, existingNormalized.contains(normalized) {
                continue
            }
            seen.insert(normalized)
            merged.append(term)
        }

        return merged
    }

    private func applyAutomaticDictionaryLearningHistoryUpdate(
        _ request: AutomaticDictionaryLearningRequest,
        historyEntryID: UUID,
        addedTerms: [String]
    ) {
        guard let existingEntry = historyStore.entry(id: historyEntryID) else {
            historyStore.applyDictionaryCorrectedTerms([historyEntryID: addedTerms])
            return
        }

        let updatedText = automaticDictionaryLearningUpdatedHistoryText(
            request: request,
            originalText: existingEntry.text
        )
        let correctionSnapshots = automaticDictionaryLearningHistorySnapshots(
            request: request,
            updatedText: updatedText
        )

        historyStore.applyDictionaryCorrectionResult(
            historyID: historyEntryID,
            updatedText: updatedText,
            correctedTerms: addedTerms,
            correctionSnapshots: correctionSnapshots
        )
    }

    private func automaticDictionaryLearningUpdatedHistoryText(
        request: AutomaticDictionaryLearningRequest,
        originalText: String
    ) -> String {
        let trimmedOriginal = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaselineContext = request.baselineContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFinalContext = request.finalContext.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedFinalContext.isEmpty else {
            return trimmedOriginal
        }
        if trimmedOriginal == trimmedBaselineContext || trimmedOriginal == request.insertedText {
            return trimmedFinalContext
        }
        if let range = trimmedOriginal.range(of: trimmedBaselineContext) {
            var updated = trimmedOriginal
            updated.replaceSubrange(range, with: trimmedFinalContext)
            return updated
        }
        return trimmedFinalContext
    }

    private func automaticDictionaryLearningHistorySnapshots(
        request: AutomaticDictionaryLearningRequest,
        updatedText: String
    ) -> [DictionaryCorrectionSnapshot] {
        let originalFragment = request.baselineChangedFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedFragment = request.finalChangedFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalFragment.isEmpty,
              !correctedFragment.isEmpty,
              originalFragment != correctedFragment,
              let range = updatedText.range(of: correctedFragment)
        else {
            return []
        }

        let nsRange = NSRange(range, in: updatedText)
        return [
            DictionaryCorrectionSnapshot(
                originalText: originalFragment,
                correctedText: correctedFragment,
                finalLocation: nsRange.location,
                finalLength: nsRange.length
            )
        ]
    }

    private func automaticDictionaryLearningSuccessMessage(for addedTerms: [String]) -> String {
        if addedTerms.count == 1 {
            return AppLocalization.format(
                "Added 1 corrected term to the dictionary: %@",
                addedTerms[0]
            )
        }
        return AppLocalization.format(
            "Added %d corrected terms to the dictionary: %@",
            addedTerms.count,
            addedTerms.joined(separator: ", ")
        )
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

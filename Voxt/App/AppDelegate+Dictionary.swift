import Foundation

struct DictionaryHistoryScanModelOption: Identifiable, Hashable {
    enum Source: Hashable {
        case local
        case remote
    }

    let id: String
    let source: Source
    let title: String
    let detail: String
}

struct DictionaryHistoryScanRequest: Hashable {
    let modelOptionID: String
    let filterSettings: DictionarySuggestionFilterSettings
}

extension AppDelegate {
    private enum DictionaryHistoryScanModel {
        case appleIntelligence
        case customLLM(repo: String)
        case remoteLLM(provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration)
    }

    private struct DictionaryHistoryScanPromptRecord: Encodable {
        let id: String
        let kind: String
        let groupName: String?
        let text: String
        let dictionaryHitTerms: [String]
        let dictionaryCorrectedTerms: [String]
    }

    private struct DictionaryHistoryScanResponse: Decodable {
        let candidates: [DictionaryHistoryScanResponseCandidate]
    }

    private struct DictionaryHistoryScanResponseCandidate: Decodable {
        let term: String
        let historyEntryIDs: [String]
        let confidence: String?
        let reason: String?
        let evidenceSample: String?
    }

    func appendDictionaryEnhancementGlossary(to prompt: String, sourceText: String) -> String {
        appendDictionaryGlossary(to: prompt, sourceText: sourceText, purpose: "enhancement")
    }

    func appendDictionaryTranslationGlossary(to prompt: String, sourceText: String) -> String {
        appendDictionaryGlossary(to: prompt, sourceText: sourceText, purpose: "translation")
    }

    func appendDictionaryRewriteGlossary(to prompt: String, sourceText: String) -> String {
        appendDictionaryGlossary(to: prompt, sourceText: sourceText, purpose: "rewrite")
    }

    private func appendDictionaryGlossary(
        to prompt: String,
        sourceText: String,
        purpose: String
    ) -> String {
        guard let context = dictionaryStore.glossaryContext(
            for: sourceText,
            activeGroupID: activeDictionaryGroupID()
        ) else {
            return prompt
        }

        let glossary = context.glossaryText()
        guard !glossary.isEmpty else { return prompt }

        let instruction: String
        switch purpose {
        case "enhancement":
            instruction = """
            ### Dictionary Guidance
            Prefer these exact spellings when the transcript context indicates the user meant them:
            \(glossary)

            If a nearby phrase looks like one of these terms, prefer the exact spelling above.
            """
        case "translation":
            instruction = """
            ### Dictionary Guidance
            When the source text refers to these proper nouns or product terms, preserve their exact spelling unless translation clearly requires otherwise:
            \(glossary)
            """
        default:
            instruction = """
            ### Dictionary Guidance
            Prefer these exact term spellings in the final output when relevant:
            \(glossary)
            """
        }

        VoxtLog.info("Dictionary glossary appended. purpose=\(purpose), terms=\(context.candidates.count)")
        return "\(prompt)\n\n\(instruction)"
    }

    func resolveDictionaryCorrection(for text: String) -> DictionaryCorrectionResult {
        guard let result = dictionaryStore.correctionContext(
            for: text,
            activeGroupID: activeDictionaryGroupID()
        ) else {
            return DictionaryCorrectionResult(text: text, candidates: [], correctedTerms: [])
        }

        if result.text != text {
            VoxtLog.info("Dictionary auto-correction applied. inputChars=\(text.count), outputChars=\(result.text.count), matches=\(result.candidates.count)")
        } else if !result.candidates.isEmpty {
            VoxtLog.info("Dictionary matches recorded without replacement. matches=\(result.candidates.count)")
        }
        return result
    }

    func previewDictionarySuggestions(
        for text: String,
        candidates: [DictionaryMatchCandidate],
        correctedTerms: [String]
    ) -> [DictionarySuggestionDraft] {
        _ = text
        _ = candidates
        _ = correctedTerms
        return []
    }

    func persistDictionaryEvidence(
        candidates: [DictionaryMatchCandidate],
        suggestions: [DictionarySuggestionDraft],
        historyEntryID: UUID?
    ) {
        dictionaryStore.recordMatches(candidates)
        dictionarySuggestionStore.applyDiscoveredSuggestions(suggestions, historyEntryID: historyEntryID)
    }

    private func activeDictionaryGroupID() -> UUID? {
        if let matchedGroupID = lastEnhancementPromptContext?.matchedGroupID {
            return matchedGroupID
        }
        return currentDictionaryScope().groupID
    }

    func startDictionaryHistorySuggestionScan() {
        startDictionaryHistorySuggestionScan(request: nil, persistSettings: false)
    }

    func availableDictionaryHistoryScanModelOptions() -> [DictionaryHistoryScanModelOption] {
        var options: [DictionaryHistoryScanModelOption] = []

        let localRepos = [customLLMManager.currentModelRepo, translationCustomLLMRepo, rewriteCustomLLMRepo]
        let uniqueLocalRepos = Array(Set(localRepos)).sorted {
            customLLMManager.displayTitle(for: $0).localizedCaseInsensitiveCompare(customLLMManager.displayTitle(for: $1)) == .orderedAscending
        }

        for repo in uniqueLocalRepos where customLLMManager.isModelDownloaded(repo: repo) {
            options.append(
                DictionaryHistoryScanModelOption(
                    id: "local:\(repo)",
                    source: .local,
                    title: AppLocalization.format(
                        "Local · %@",
                        customLLMManager.displayTitle(for: repo)
                    ),
                    detail: repo
                )
            )
        }

        for provider in RemoteLLMProvider.allCases {
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            guard configuration.isConfigured else { continue }
            options.append(
                DictionaryHistoryScanModelOption(
                    id: "remote:\(provider.rawValue)",
                    source: .remote,
                    title: AppLocalization.format("Remote · %@", provider.title),
                    detail: configuration.model
                )
            )
        }

        return options
    }

    func startDictionaryHistorySuggestionScan(
        request: DictionaryHistoryScanRequest?,
        persistSettings: Bool
    ) {
        guard !dictionarySuggestionStore.historyScanProgress.isRunning else { return }

        let pendingEntries = dictionarySuggestionStore.pendingHistoryEntries(in: historyStore)
        guard !pendingEntries.isEmpty else {
            dictionarySuggestionStore.finishHistoryScan(
                processedCount: 0,
                newSuggestionCount: 0,
                duplicateCount: 0,
                checkpointEntry: nil
            )
            return
        }

        if persistSettings, let request {
            dictionarySuggestionStore.saveFilterSettings(request.filterSettings)
        }

        dictionarySuggestionStore.beginHistoryScan(totalCount: pendingEntries.count)
        Task {
            await runDictionaryHistorySuggestionScan(entries: pendingEntries, request: request)
        }
    }

    private func runDictionaryHistorySuggestionScan(
        entries: [TranscriptionHistoryEntry],
        request: DictionaryHistoryScanRequest?
    ) async {
        let groups = loadDictionaryHistoryScanGroups()
        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        let groupsByLowercasedName = groups.reduce(into: [String: AppBranchGroup]()) { partialResult, group in
            partialResult[group.name.lowercased()] = group
        }
        let filterSettings = request?.filterSettings.sanitized() ?? dictionarySuggestionStore.filterSettings
        let batchSize = filterSettings.batchSize

        var processedCount = 0
        var newSuggestionCount = 0
        var duplicateCount = 0
        var lastProcessedEntry: TranscriptionHistoryEntry?

        do {
            let model = try resolvedDictionaryHistoryScanModel(for: request)
            for start in stride(from: 0, to: entries.count, by: batchSize) {
                let batch = Array(entries[start..<min(start + batchSize, entries.count)])
                let prompt = try dictionaryHistoryScanPrompt(
                    for: batch,
                    filterSettings: filterSettings,
                    groupsByID: groupsByID,
                    groupsByLowercasedName: groupsByLowercasedName
                )
                let rawResponse = try await runDictionaryHistoryScanPrompt(prompt, model: model)
                let parsedCandidates = try parseDictionaryHistoryScanCandidates(
                    from: rawResponse,
                    batch: batch,
                    groupsByID: groupsByID,
                    groupsByLowercasedName: groupsByLowercasedName
                )

                let applyResult = dictionarySuggestionStore.applyHistoryScanCandidates(
                    parsedCandidates,
                    dictionaryStore: dictionaryStore
                )
                historyStore.applyDictionarySuggestedTerms(applyResult.snapshotsByHistoryID)

                processedCount += batch.count
                newSuggestionCount += applyResult.newSuggestionCount
                duplicateCount += applyResult.duplicateCount
                lastProcessedEntry = batch.last

                if let lastProcessedEntry {
                    dictionarySuggestionStore.advanceHistoryScanCheckpoint(to: lastProcessedEntry)
                }
                dictionarySuggestionStore.updateHistoryScan(
                    processedCount: processedCount,
                    newSuggestionCount: newSuggestionCount,
                    duplicateCount: duplicateCount
                )
            }

            dictionarySuggestionStore.finishHistoryScan(
                processedCount: processedCount,
                newSuggestionCount: newSuggestionCount,
                duplicateCount: duplicateCount,
                checkpointEntry: lastProcessedEntry
            )
        } catch {
            VoxtLog.warning("Dictionary history scan failed: \(error)")
            dictionarySuggestionStore.failHistoryScan(
                processedCount: processedCount,
                totalCount: entries.count,
                newSuggestionCount: newSuggestionCount,
                duplicateCount: duplicateCount,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func runDictionaryHistoryScanPrompt(
        _ prompt: String,
        model: DictionaryHistoryScanModel
    ) async throws -> String {
        switch model {
        case .appleIntelligence:
            guard let enhancer else {
                throw NSError(
                    domain: "Voxt.DictionaryHistoryScan",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Apple Intelligence is unavailable.")]
                )
            }
            if #available(macOS 26.0, *) {
                return try await enhancer.enhance(userPrompt: prompt)
            }
            throw NSError(
                domain: "Voxt.DictionaryHistoryScan",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Apple Intelligence requires macOS 26 or later.")]
            )
        case .customLLM(let repo):
            return try await customLLMManager.enhance(userPrompt: prompt, repo: repo)
        case .remoteLLM(let provider, let configuration):
            return try await RemoteLLMRuntimeClient().enhance(
                userPrompt: prompt,
                provider: provider,
                configuration: configuration
            )
        }
    }

    private func resolvedDictionaryHistoryScanModel(for request: DictionaryHistoryScanRequest?) throws -> DictionaryHistoryScanModel {
        if let request {
            return try dictionaryHistoryScanModel(for: request.modelOptionID)
        }
        return try resolvedDictionaryHistoryScanModel()
    }

    private func resolvedDictionaryHistoryScanModel() throws -> DictionaryHistoryScanModel {
        if let preferred = preferredDictionaryHistoryScanModel() {
            return preferred
        }
        if let fallback = fallbackDictionaryHistoryScanModel() {
            return fallback
        }
        throw NSError(
            domain: "Voxt.DictionaryHistoryScan",
            code: -3,
            userInfo: [
                NSLocalizedDescriptionKey: AppLocalization.localizedString(
                    "No usable LLM is available for dictionary ingestion. Configure Apple Intelligence, a local custom LLM, or a remote LLM first."
                )
            ]
        )
    }

    private func preferredDictionaryHistoryScanModel() -> DictionaryHistoryScanModel? {
        switch enhancementMode {
        case .appleIntelligence:
            return appleDictionaryHistoryScanModel()
        case .customLLM:
            return customLLMDictionaryHistoryScanModel()
        case .remoteLLM:
            return remoteDictionaryHistoryScanModel()
        case .off:
            return nil
        }
    }

    private func fallbackDictionaryHistoryScanModel() -> DictionaryHistoryScanModel? {
        appleDictionaryHistoryScanModel()
            ?? customLLMDictionaryHistoryScanModel()
            ?? remoteDictionaryHistoryScanModel()
    }

    private func appleDictionaryHistoryScanModel() -> DictionaryHistoryScanModel? {
        guard #available(macOS 26.0, *), enhancer != nil, TextEnhancer.isAvailable else {
            return nil
        }
        return .appleIntelligence
    }

    private func customLLMDictionaryHistoryScanModel() -> DictionaryHistoryScanModel? {
        guard customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo) else {
            return nil
        }
        return .customLLM(repo: customLLMManager.currentModelRepo)
    }

    private func remoteDictionaryHistoryScanModel() -> DictionaryHistoryScanModel? {
        let context = resolvedRemoteLLMContext(forTranslation: false)
        guard context.configuration.isConfigured else { return nil }
        return .remoteLLM(provider: context.provider, configuration: context.configuration)
    }

    private func dictionaryHistoryScanModel(for optionID: String) throws -> DictionaryHistoryScanModel {
        if optionID.hasPrefix("local:") {
            let repo = String(optionID.dropFirst("local:".count))
            guard customLLMManager.isModelDownloaded(repo: repo) else {
                throw NSError(
                    domain: "Voxt.DictionaryHistoryScan",
                    code: -5,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Selected local model is not available.")]
                )
            }
            return .customLLM(repo: repo)
        }

        if optionID.hasPrefix("remote:") {
            let rawProvider = String(optionID.dropFirst("remote:".count))
            guard let provider = RemoteLLMProvider(rawValue: rawProvider) else {
                throw NSError(
                    domain: "Voxt.DictionaryHistoryScan",
                    code: -6,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Selected remote model is invalid.")]
                )
            }
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            guard configuration.isConfigured else {
                throw NSError(
                    domain: "Voxt.DictionaryHistoryScan",
                    code: -7,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Selected remote model is not configured.")]
                )
            }
            return .remoteLLM(provider: provider, configuration: configuration)
        }

        throw NSError(
            domain: "Voxt.DictionaryHistoryScan",
            code: -8,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("No model was selected for dictionary ingestion.")]
        )
    }

    private func dictionaryHistoryScanPrompt(
        for batch: [TranscriptionHistoryEntry],
        filterSettings: DictionarySuggestionFilterSettings,
        groupsByID: [UUID: AppBranchGroup],
        groupsByLowercasedName: [String: AppBranchGroup]
    ) throws -> String {
        let records = batch.map { entry in
            let scope = resolvedHistoryScope(
                for: entry,
                groupsByID: groupsByID,
                groupsByLowercasedName: groupsByLowercasedName
            )
            return DictionaryHistoryScanPromptRecord(
                id: entry.id.uuidString,
                kind: entry.kind.rawValue,
                groupName: scope.groupName,
                text: trimmedHistoryScanText(entry.text),
                dictionaryHitTerms: entry.dictionaryHitTerms,
                dictionaryCorrectedTerms: entry.dictionaryCorrectedTerms
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(records)
        let recordsJSON = String(decoding: data, as: UTF8.self)
        let settings = filterSettings.sanitized()

        return """
        \(settings.prompt)

        Return strict JSON with this exact shape:
        {"candidates":[{"term":"OpenMemory","historyEntryIDs":["UUID"],"confidence":"high","reason":"why it matters","evidenceSample":"short exact snippet"}]}

        Rules:
        - Use only historyEntryIDs from the provided records.
        - Keep evidenceSample under 80 characters.
        - Return at most \(settings.maxCandidatesPerBatch) candidates.
        - Do not include markdown, prose, or code fences outside the JSON object.

        History records:
        \(recordsJSON)
        """
    }

    private func parseDictionaryHistoryScanCandidates(
        from rawResponse: String,
        batch: [TranscriptionHistoryEntry],
        groupsByID: [UUID: AppBranchGroup],
        groupsByLowercasedName: [String: AppBranchGroup]
    ) throws -> [DictionaryHistoryScanCandidate] {
        let normalized = normalizedJSONObjectString(from: rawResponse)
        guard let data = normalized.data(using: .utf8) else {
            throw NSError(
                domain: "Voxt.DictionaryHistoryScan",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Dictionary ingestion returned invalid text.")]
            )
        }

        let decoded = try JSONDecoder().decode(DictionaryHistoryScanResponse.self, from: data)
        let entriesByID = Dictionary(uniqueKeysWithValues: batch.map { ($0.id.uuidString, $0) })

        var candidatesByKey: [String: DictionaryHistoryScanCandidate] = [:]

        for item in decoded.candidates {
            let term = item.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }

            let sourceEntries = item.historyEntryIDs.compactMap { entriesByID[$0] }
            guard !sourceEntries.isEmpty else { continue }

            let scope = resolvedCandidateScope(
                sourceEntries: sourceEntries,
                groupsByID: groupsByID,
                groupsByLowercasedName: groupsByLowercasedName
            )
            let evidenceSample = resolvedEvidenceSample(
                preferredSample: item.evidenceSample,
                term: term,
                sourceEntries: sourceEntries
            )
            let key = "\(DictionaryStore.normalizeTerm(term))|\(scope.groupID?.uuidString ?? "global")"
            let historyEntryIDs = sourceEntries.map(\.id)

            if let existing = candidatesByKey[key] {
                let mergedIDs = Array(Set(existing.historyEntryIDs + historyEntryIDs)).sorted {
                    $0.uuidString < $1.uuidString
                }
                candidatesByKey[key] = DictionaryHistoryScanCandidate(
                    term: existing.term.count >= term.count ? existing.term : term,
                    historyEntryIDs: mergedIDs,
                    groupID: existing.groupID,
                    groupNameSnapshot: existing.groupNameSnapshot ?? scope.groupName,
                    evidenceSample: existing.evidenceSample.isEmpty ? evidenceSample : existing.evidenceSample
                )
            } else {
                candidatesByKey[key] = DictionaryHistoryScanCandidate(
                    term: term,
                    historyEntryIDs: historyEntryIDs,
                    groupID: scope.groupID,
                    groupNameSnapshot: scope.groupName,
                    evidenceSample: evidenceSample
                )
            }

            if let confidence = item.confidence?.trimmingCharacters(in: .whitespacesAndNewlines),
               !confidence.isEmpty {
                VoxtLog.info("Dictionary history scan candidate confidence=\(confidence), term=\(term)")
            }
            if let reason = item.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reason.isEmpty {
                VoxtLog.info("Dictionary history scan candidate reason term=\(term): \(reason)")
            }
        }

        return candidatesByKey.values.sorted {
            $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
        }
    }

    private func resolvedCandidateScope(
        sourceEntries: [TranscriptionHistoryEntry],
        groupsByID: [UUID: AppBranchGroup],
        groupsByLowercasedName: [String: AppBranchGroup]
    ) -> (groupID: UUID?, groupName: String?) {
        let scopes = sourceEntries.map {
            resolvedHistoryScope(
                for: $0,
                groupsByID: groupsByID,
                groupsByLowercasedName: groupsByLowercasedName
            )
        }
        let uniqueScopedIDs = Array(Set(scopes.compactMap(\.groupID)))
        guard uniqueScopedIDs.count == 1, scopes.allSatisfy({ $0.groupID == uniqueScopedIDs[0] }) else {
            return (nil, nil)
        }
        return (uniqueScopedIDs[0], scopes.first?.groupName)
    }

    private func resolvedHistoryScope(
        for entry: TranscriptionHistoryEntry,
        groupsByID: [UUID: AppBranchGroup],
        groupsByLowercasedName: [String: AppBranchGroup]
    ) -> (groupID: UUID?, groupName: String?) {
        if let matchedGroupID = entry.matchedGroupID {
            let groupName = groupsByID[matchedGroupID]?.name
                ?? entry.matchedAppGroupName
                ?? entry.matchedURLGroupName
            return (matchedGroupID, groupName)
        }

        if let groupName = (entry.matchedAppGroupName ?? entry.matchedURLGroupName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !groupName.isEmpty,
           let group = groupsByLowercasedName[groupName.lowercased()] {
            return (group.id, group.name)
        }

        return (nil, nil)
    }

    private func resolvedEvidenceSample(
        preferredSample: String?,
        term: String,
        sourceEntries: [TranscriptionHistoryEntry]
    ) -> String {
        let trimmedPreferred = preferredSample?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedPreferred.isEmpty {
            return String(trimmedPreferred.prefix(80))
        }
        guard let firstEntry = sourceEntries.first else { return "" }
        return historyEvidenceSample(for: term, in: firstEntry.text)
    }

    private func historyEvidenceSample(for term: String, in text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "" }
        guard let range = trimmedText.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(trimmedText.prefix(80))
        }

        let start = trimmedText.distance(from: trimmedText.startIndex, to: range.lowerBound)
        let lowerOffset = max(0, start - 18)
        let upperOffset = min(trimmedText.count, start + term.count + 18)
        let lowerIndex = trimmedText.index(trimmedText.startIndex, offsetBy: lowerOffset)
        let upperIndex = trimmedText.index(trimmedText.startIndex, offsetBy: upperOffset)
        let snippet = trimmedText[lowerIndex..<upperIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return String(snippet.prefix(80))
    }

    private func trimmedHistoryScanText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 320 else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 320)
        return String(trimmed[..<index])
    }

    private func normalizedJSONObjectString(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced = unwrapCodeFenceIfNeeded(trimmed)
        if unfenced.first == "{", unfenced.last == "}" {
            return unfenced
        }
        if let start = unfenced.firstIndex(of: "{"),
           let end = unfenced.lastIndex(of: "}") {
            return String(unfenced[start...end])
        }
        return unfenced
    }

    private func unwrapCodeFenceIfNeeded(_ text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```") else { return text }
        var lines = text.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return text }
        lines.removeFirst()
        if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadDictionaryHistoryScanGroups() -> [AppBranchGroup] {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.appBranchGroups),
              let groups = try? JSONDecoder().decode([AppBranchGroup].self, from: data)
        else {
            return []
        }
        return groups
    }
}

import Foundation

extension AppDelegate {
    private enum MeetingSummaryModelID {
        static let appleIntelligence = "apple-intelligence"

        static func customLLM(_ repo: String) -> String {
            "custom-llm:\(repo)"
        }

        static func remoteLLM(_ provider: RemoteLLMProvider) -> String {
            "remote-llm:\(provider.rawValue)"
        }
    }

    private enum MeetingSummaryModel {
        case appleIntelligence
        case customLLM(repo: String)
        case remoteLLM(provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration)
    }

    var meetingSummaryAutoGenerateEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKey.meetingSummaryAutoGenerate) as? Bool ?? true
    }

    var meetingSummaryPromptTemplatePreference: String {
        let value = UserDefaults.standard.string(forKey: AppPreferenceKey.meetingSummaryPromptTemplate)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? AppPreferenceKey.defaultMeetingSummaryPrompt : value
    }

    var meetingSummaryModelSelectionPreference: String? {
        let rawValue = UserDefaults.standard.string(forKey: AppPreferenceKey.meetingSummaryModelSelection)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return rawValue.isEmpty ? nil : rawValue
    }

    func meetingSummaryModelOptions() -> [MeetingSummaryModelOption] {
        var options: [MeetingSummaryModelOption] = []

        if #available(macOS 26.0, *), enhancer != nil, TextEnhancer.isAvailable {
            options.append(
                MeetingSummaryModelOption(
                    id: MeetingSummaryModelID.appleIntelligence,
                    title: AppLocalization.localizedString("Apple Intelligence"),
                    subtitle: AppLocalization.localizedString("Built-in on-device summary generation")
                )
            )
        }

        let downloadedCustomOptions: [MeetingSummaryModelOption] = CustomLLMModelManager.availableModels.compactMap { model -> MeetingSummaryModelOption? in
            guard customLLMManager.isModelDownloaded(repo: model.id) else {
                return nil
            }
            return MeetingSummaryModelOption(
                id: MeetingSummaryModelID.customLLM(model.id),
                title: customLLMManager.displayTitle(for: model.id),
                subtitle: AppLocalization.localizedString("Local Custom LLM")
            )
        }
        options.append(contentsOf: downloadedCustomOptions)

        let currentCustomRepo = customLLMManager.currentModelRepo
        if customLLMManager.isModelDownloaded(repo: currentCustomRepo) {
            let currentCustomOption = MeetingSummaryModelOption(
                id: MeetingSummaryModelID.customLLM(currentCustomRepo),
                title: customLLMManager.displayTitle(for: currentCustomRepo),
                subtitle: AppLocalization.localizedString("Local Custom LLM")
            )
            if !options.contains(where: { $0.id == currentCustomOption.id }) {
                options.append(currentCustomOption)
            }
        }

        let configuredRemoteOptions: [MeetingSummaryModelOption] = RemoteLLMProvider.allCases.compactMap { provider -> MeetingSummaryModelOption? in
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            guard configuration.isConfigured, configuration.hasUsableModel else {
                return nil
            }
            return MeetingSummaryModelOption(
                id: MeetingSummaryModelID.remoteLLM(provider),
                title: "\(provider.title) · \(configuration.model)",
                subtitle: AppLocalization.localizedString("Configured Remote LLM")
            )
        }
        options.append(contentsOf: configuredRemoteOptions)

        return options
    }

    func currentMeetingSummarySettingsSnapshot() -> MeetingSummarySettingsSnapshot {
        MeetingSummarySettingsSnapshot(
            autoGenerate: meetingSummaryAutoGenerateEnabled,
            promptTemplate: meetingSummaryPromptTemplatePreference,
            modelSelectionID: resolvedMeetingSummaryModelSelectionID(
                preferredID: meetingSummaryModelSelectionPreference,
                availableOptions: meetingSummaryModelOptions()
            )
        )
    }

    func updateMeetingSummaryPreference(
        autoGenerate: Bool? = nil,
        promptTemplate: String? = nil,
        modelSelectionID: String? = nil
    ) {
        FeatureSettingsStore.update(defaults: .standard) { settings in
            if let autoGenerate {
                settings.meeting.summaryAutoGenerate = autoGenerate
            }
            if let promptTemplate {
                settings.meeting.summaryPrompt = promptTemplate
            }
            if let modelSelectionID {
                settings.meeting.summaryModelSelectionID =
                    FeatureModelSelectionID.fromLegacyMeetingSummarySelection(modelSelectionID)
                    ?? FeatureModelSelectionID(rawValue: modelSelectionID)
            }
        }
    }

    func meetingSummaryProviderStatus(settings: MeetingSummarySettingsSnapshot? = nil) -> MeetingSummaryProviderStatus {
        let options = meetingSummaryModelOptions()
        guard !options.isEmpty else {
            return MeetingSummaryProviderStatus(
                isAvailable: false,
                message: AppLocalization.localizedString("No downloaded or configured summary model is currently available.")
            )
        }

        let preferredID = settings?.modelSelectionID ?? meetingSummaryModelSelectionPreference
        guard let model = resolvedMeetingSummaryModel(
            preferredID: preferredID,
            availableOptions: options
        ) else {
            return MeetingSummaryProviderStatus(
                isAvailable: false,
                message: AppLocalization.localizedString("The selected summary model is currently unavailable.")
            )
        }

        switch model {
        case .appleIntelligence:
            return MeetingSummaryProviderStatus(
                isAvailable: true,
                message: AppLocalization.localizedString("Using Apple Intelligence for meeting summaries.")
            )
        case .customLLM(let repo):
            return MeetingSummaryProviderStatus(
                isAvailable: true,
                message: AppLocalization.format("Using local model: %@", customLLMManager.displayTitle(for: repo))
            )
        case .remoteLLM(let provider, let configuration):
            return MeetingSummaryProviderStatus(
                isAvailable: true,
                message: AppLocalization.format("Using remote model: %@ · %@", provider.title, configuration.model)
            )
        }
    }

    func generateMeetingSummary(
        transcript: String,
        settings: MeetingSummarySettingsSnapshot
    ) async throws -> MeetingSummarySnapshot {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw NSError(
                domain: "Voxt.MeetingSummary",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("No meeting transcript is available yet.")]
            )
        }
        let options = meetingSummaryModelOptions()
        guard let model = resolvedMeetingSummaryModel(
            preferredID: settings.modelSelectionID,
            availableOptions: options
        ) else {
            let status = meetingSummaryProviderStatus(settings: settings)
            throw NSError(
                domain: "Voxt.MeetingSummary",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: status.message]
            )
        }

        let prompt = MeetingSummarySupport.summaryPrompt(
            transcript: trimmedTranscript,
            settings: settings,
            userMainLanguage: userMainLanguagePromptValue
        )
        let modelLabel = meetingSummaryModelLogLabel(model)
        let startedAt = Date()
        VoxtLog.info(
            "Meeting summary generation started. model=\(modelLabel), transcriptChars=\(trimmedTranscript.count), promptChars=\(prompt.count)"
        )
        VoxtLog.llm(
            """
            Meeting summary generation content. model=\(modelLabel)
            [transcript]
            \(VoxtLog.llmPreview(trimmedTranscript, limit: 4000))
            [prompt]
            \(VoxtLog.llmPreview(prompt, limit: 4000))
            """
        )
        do {
            let output = try await runMeetingSummaryPrompt(
                prompt,
                resolvedModel: model
            )
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            VoxtLog.llm(
                """
                Meeting summary generation output. model=\(modelLabel)
                [output]
                \(VoxtLog.llmPreview(output, limit: 4000))
                """
            )

            guard let summary = MeetingSummarySupport.decodeSummary(from: output, settings: settings) else {
                VoxtLog.warning(
                    "Meeting summary generation parse failed. model=\(modelLabel), outputChars=\(output.count), elapsedMs=\(elapsedMs)"
                )
                VoxtLog.llm("Meeting summary generation parse failure output. model=\(modelLabel)\n\(VoxtLog.llmPreview(output, limit: 4000))")
                throw NSError(
                    domain: "Voxt.MeetingSummary",
                    code: -5,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Meeting summary output could not be parsed.")]
                )
            }
            VoxtLog.info(
                "Meeting summary generation succeeded. model=\(modelLabel), elapsedMs=\(elapsedMs), title=\(summary.title), todoCount=\(summary.todoItems.count), bodyChars=\(summary.body.count)"
            )
            return summary
        } catch {
            VoxtLog.warning(
                "Meeting summary generation failed. model=\(modelLabel), error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    func answerMeetingSummaryFollowUp(
        transcript: String,
        summary: MeetingSummarySnapshot?,
        history: [MeetingSummaryChatMessage],
        question: String,
        settings: MeetingSummarySettingsSnapshot
    ) async throws -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw NSError(
                domain: "Voxt.MeetingSummaryChat",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("No meeting transcript is available yet.")]
            )
        }
        guard !trimmedQuestion.isEmpty else {
            throw NSError(
                domain: "Voxt.MeetingSummaryChat",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Please enter a follow-up question.")]
            )
        }

        let options = meetingSummaryModelOptions()
        guard let model = resolvedMeetingSummaryModel(
            preferredID: settings.modelSelectionID,
            availableOptions: options
        ) else {
            let status = meetingSummaryProviderStatus(settings: settings)
            throw NSError(
                domain: "Voxt.MeetingSummaryChat",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: status.message]
            )
        }

        let prompt = MeetingSummarySupport.followUpPrompt(
            transcript: trimmedTranscript,
            summary: summary,
            history: history,
            question: trimmedQuestion,
            userMainLanguage: userMainLanguagePromptValue
        )
        let modelLabel = meetingSummaryModelLogLabel(model)
        let startedAt = Date()
        VoxtLog.info(
            "Meeting summary follow-up started. model=\(modelLabel), transcriptChars=\(trimmedTranscript.count), questionChars=\(trimmedQuestion.count), historyCount=\(history.count), hasSummary=\(summary != nil)"
        )
        VoxtLog.llm(
            """
            Meeting summary follow-up content. model=\(modelLabel)
            [question]
            \(VoxtLog.llmPreview(trimmedQuestion, limit: 2000))
            [transcript]
            \(VoxtLog.llmPreview(trimmedTranscript, limit: 4000))
            [prompt]
            \(VoxtLog.llmPreview(prompt, limit: 4000))
            """
        )
        do {
            let output = try await runMeetingSummaryPrompt(
                prompt,
                resolvedModel: model
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            VoxtLog.llm(
                """
                Meeting summary follow-up output. model=\(modelLabel)
                [output]
                \(VoxtLog.llmPreview(output, limit: 4000))
                """
            )
            VoxtLog.info(
                "Meeting summary follow-up succeeded. model=\(modelLabel), elapsedMs=\(elapsedMs), outputChars=\(output.count)"
            )
            return output
        } catch {
            VoxtLog.warning(
                "Meeting summary follow-up failed. model=\(modelLabel), error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    @discardableResult
    func persistMeetingSummary(_ summary: MeetingSummarySnapshot?, for entryID: UUID) -> TranscriptionHistoryEntry? {
        historyStore.updateMeetingSummary(summary, for: entryID)
    }

    @discardableResult
    func persistMeetingSummaryChatMessages(_ messages: [MeetingSummaryChatMessage], for entryID: UUID) -> TranscriptionHistoryEntry? {
        historyStore.updateMeetingSummaryChatMessages(messages, for: entryID)
    }

    private func runMeetingSummaryPrompt(
        _ prompt: String,
        resolvedModel: MeetingSummaryModel
    ) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "" }
        let modelLabel = meetingSummaryModelLogLabel(resolvedModel)

        switch resolvedModel {
        case .appleIntelligence:
            guard let enhancer else {
                throw NSError(
                    domain: "Voxt.MeetingSummary",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Apple Intelligence is unavailable.")]
                )
            }
            if #available(macOS 26.0, *) {
                VoxtLog.llm("Meeting summary runtime dispatch. model=\(modelLabel), runtime=apple-intelligence")
                return try await enhancer.enhance(userPrompt: trimmedPrompt)
            }
            throw NSError(
                domain: "Voxt.MeetingSummary",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Apple Intelligence requires macOS 26 or later.")]
            )
        case .customLLM(let repo):
            VoxtLog.llm("Meeting summary runtime dispatch. model=\(modelLabel), runtime=custom-llm, repo=\(repo)")
            return try await customLLMManager.enhance(userPrompt: trimmedPrompt, repo: repo)
        case .remoteLLM(let provider, let configuration):
            VoxtLog.llm(
                "Meeting summary runtime dispatch. model=\(modelLabel), runtime=remote-llm, provider=\(provider.rawValue), remoteModel=\(configuration.model)"
            )
            return try await RemoteLLMRuntimeClient().enhance(
                userPrompt: trimmedPrompt,
                provider: provider,
                configuration: configuration
            )
        }
    }

    private func resolvedMeetingSummaryModelSelectionID(
        preferredID: String?,
        availableOptions: [MeetingSummaryModelOption]
    ) -> String? {
        let trimmedPreferredID = preferredID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPreferredID,
           availableOptions.contains(where: { $0.id == trimmedPreferredID }) {
            return trimmedPreferredID
        }

        switch enhancementMode {
        case .appleIntelligence:
            if availableOptions.contains(where: { $0.id == MeetingSummaryModelID.appleIntelligence }) {
                return MeetingSummaryModelID.appleIntelligence
            }
        case .customLLM:
            let repo = customLLMManager.currentModelRepo
            let optionID = MeetingSummaryModelID.customLLM(repo)
            if availableOptions.contains(where: { $0.id == optionID }) {
                return optionID
            }
        case .remoteLLM:
            let provider = remoteLLMSelectedProvider
            let optionID = MeetingSummaryModelID.remoteLLM(provider)
            if availableOptions.contains(where: { $0.id == optionID }) {
                return optionID
            }
        case .off:
            break
        }

        return availableOptions.first?.id
    }

    private func resolvedMeetingSummaryModel(
        preferredID: String?,
        availableOptions: [MeetingSummaryModelOption]
    ) -> MeetingSummaryModel? {
        guard let selectionID = resolvedMeetingSummaryModelSelectionID(
            preferredID: preferredID,
            availableOptions: availableOptions
        ) else {
            return nil
        }

        if selectionID == MeetingSummaryModelID.appleIntelligence {
            guard #available(macOS 26.0, *), enhancer != nil, TextEnhancer.isAvailable else {
                return nil
            }
            return .appleIntelligence
        }

        if let repo = value(in: selectionID, forPrefix: "custom-llm:") {
            guard customLLMManager.isModelDownloaded(repo: repo) else { return nil }
            return .customLLM(repo: repo)
        }

        if let providerRawValue = value(in: selectionID, forPrefix: "remote-llm:"),
           let provider = RemoteLLMProvider(rawValue: providerRawValue) {
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            guard configuration.isConfigured, configuration.hasUsableModel else { return nil }
            return .remoteLLM(provider: provider, configuration: configuration)
        }

        return nil
    }

    private func value(in selectionID: String, forPrefix prefix: String) -> String? {
        guard selectionID.hasPrefix(prefix) else { return nil }
        let value = String(selectionID.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func meetingSummaryModelLogLabel(_ model: MeetingSummaryModel) -> String {
        switch model {
        case .appleIntelligence:
            return "apple-intelligence"
        case .customLLM(let repo):
            return "custom-llm:\(repo)"
        case .remoteLLM(let provider, let configuration):
            return "remote-llm:\(provider.rawValue):\(configuration.model)"
        }
    }
}

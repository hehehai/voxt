import Foundation

extension AppDelegate {
    enum VariablePromptDelivery: Equatable {
        case systemPrompt
        case userMessage
    }

    struct VariablePromptResolution: Equatable {
        let content: String
        let dictionaryGlossary: String?
        let delivery: VariablePromptDelivery
    }

    func isStoredRemoteLLMConfigured(_ provider: RemoteLLMProvider) -> Bool {
        RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
            provider: provider,
            stored: remoteLLMConfigurations
        )
    }

    func resolvedRemoteLLMContext(forTranslation: Bool) -> (provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration) {
        let provider: RemoteLLMProvider
        if forTranslation, let translationProvider = translationRemoteLLMProvider {
            provider = translationProvider
        } else {
            provider = remoteLLMSelectedProvider
        }

        let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: remoteLLMConfigurations
        )
        return (provider, configuration)
    }

    func resolvedRemoteLLMContext(forRewrite: Bool) -> (provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration) {
        let provider: RemoteLLMProvider
        if forRewrite, let rewriteProvider = rewriteRemoteLLMProvider {
            provider = rewriteProvider
        } else {
            provider = remoteLLMSelectedProvider
        }

        let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: remoteLLMConfigurations
        )
        return (provider, configuration)
    }

    func translateText(
        _ text: String,
        targetLanguage: TranslationTargetLanguage
    ) async throws -> String {
        let resolution = resolvedTranslationProviderResolution(
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: isSelectedTextTranslationFlow
        )
        let modelProvider = resolution.provider
        let providerOverride: LLMExecutionProvider?
        switch modelProvider {
        case .customLLM:
            providerOverride = .customLLM(repo: translationCustomLLMRepo)
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: true)
            providerOverride = .remote(provider: context.provider, configuration: context.configuration)
        case .whisperKit:
            providerOverride = nil
        }
        let basePolicy = DictionaryGlossaryPurpose.translation.selectionPolicy
        let provisionalStrategy = TaskLLMStrategyResolver.resolve(
            taskKind: .translation,
            rawText: text,
            promptCharacterCount: 0,
            baseGlossarySelectionPolicy: basePolicy,
            capabilities: providerOverride.map(llmProviderModelCapabilities(for:)) ?? .unknown
        )
        let promptResolution = resolvedTranslationPrompt(
            targetLanguage: targetLanguage,
            sourceText: text,
            strict: false,
            glossarySelectionPolicy: provisionalStrategy.glossarySelectionPolicy
        )
        let translationRepo = translationCustomLLMRepo
        VoxtLog.llm(
            "Translation request. promptChars=\(promptResolution.content.count), inputChars=\(text.count), provider=\(modelProvider.rawValue), selectedProvider=\(translationModelProvider.rawValue), fallbackReason=\(resolution.fallbackReason.map(String.init(describing:)) ?? "none"), translationRepo=\(translationRepo), delivery=\(String(describing: promptResolution.delivery))"
        )

        if modelProvider == .customLLM {
            guard customLLMManager.isModelDownloaded(repo: translationRepo) else {
                VoxtLog.warning("Translation provider customLLM unavailable: model not downloaded. repo=\(translationRepo)")
                showOverlayStatus(
                    String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
                return text
            }
            VoxtLog.info("Translation provider selected: customLLM")
        } else if modelProvider == .remoteLLM {
            let context = resolvedRemoteLLMContext(forTranslation: true)
            guard isStoredRemoteLLMConfigured(context.provider) else {
                VoxtLog.warning("Translation provider remoteLLM unavailable: no configured model.")
                showOverlayStatus(
                    String(localized: "No configured remote LLM model yet. Configure a provider in Settings > Model."),
                    clearAfter: 2.5
                )
                return text
            }
            VoxtLog.info("Translation provider selected: remoteLLM(\(context.provider.rawValue))")
        } else {
            return text
        }

        let strategy = TaskLLMStrategyResolver.resolve(
            taskKind: .translation,
            rawText: text,
            promptCharacterCount: promptResolution.content.count + (promptResolution.dictionaryGlossary?.count ?? 0),
            baseGlossarySelectionPolicy: basePolicy,
            capabilities: providerOverride.map(llmProviderModelCapabilities(for:)) ?? .unknown
        )
        guard let plan = buildTranslationExecutionPlan(
            sourceText: text,
            targetLanguage: targetLanguage,
            promptResolution: promptResolution,
            modelProvider: modelProvider,
            providerOverride: providerOverride,
            executionStrategy: strategy
        ) else {
            return text
        }
        let translated = try await executeLLMExecutionPlan(plan)
        return TaskLLMStrategyResolver.applyTruncationGuard(
            outputText: translated,
            originalText: text,
            strategy: strategy
        ).text
    }

    func rewriteText(
        dictatedPrompt: String,
        sourceText: String,
        conversationHistory: [RewriteConversationPromptTurn],
        structuredAnswerOutput: Bool,
        forceNonEmptyAnswer: Bool = false,
        previousConversationResponseID: String? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil,
        onResponseID: ((String) -> Void)? = nil
    ) async throws -> String {
        let directAnswerMode = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let trimmedConversationHistory = trimmedRewriteConversationHistory(
            conversationHistory
        )
        let modelProvider = rewriteModelProvider
        let remoteContext = rewriteModelProvider == .remoteLLM ? resolvedRemoteLLMContext(forRewrite: true) : nil
        let shouldUseProviderManagedConversation =
            (remoteContext?.provider.usesResponsesAPI ?? false) &&
            directAnswerMode &&
            !structuredAnswerOutput
        let shouldUseChatMessageConversation =
            modelProvider == .remoteLLM &&
            directAnswerMode &&
            !structuredAnswerOutput &&
            !trimmedConversationHistory.isEmpty &&
            !shouldUseProviderManagedConversation
        if shouldUseChatMessageConversation {
            let latestTurn = trimmedConversationHistory.last
            VoxtLog.info(
                """
                Rewrite continue conversation context prepared. turns=\(trimmedConversationHistory.count), latestTitle=\(VoxtLog.llmPreview(latestTurn?.resultTitle ?? "")), latestContent=\(VoxtLog.llmPreview(latestTurn?.resultContent ?? "")), currentPrompt=\(VoxtLog.llmPreview(dictatedPrompt))
                """
            )
        }
        let promptResolution = shouldUseChatMessageConversation
            ? VariablePromptResolution(
                content: resolvedRewriteConversationPrompt(forceNonEmptyAnswer: forceNonEmptyAnswer),
                dictionaryGlossary: nil,
                delivery: .systemPrompt
            )
            : resolvedRewritePrompt(
                dictatedPrompt: dictatedPrompt,
                sourceText: sourceText,
                conversationHistory: shouldUseProviderManagedConversation ? [] : trimmedConversationHistory,
                structuredAnswerOutput: structuredAnswerOutput,
                directAnswerMode: directAnswerMode,
                forceNonEmptyAnswer: forceNonEmptyAnswer,
                glossarySelectionPolicy: nil
            )
        let rewriteRepo = rewriteCustomLLMRepo
        VoxtLog.llm(
            "Rewrite request. promptChars=\(promptResolution.content.count), dictatedChars=\(dictatedPrompt.count), sourceChars=\(sourceText.count), provider=\(modelProvider.rawValue), rewriteRepo=\(rewriteRepo), structuredAnswerOutput=\(structuredAnswerOutput), directAnswerMode=\(directAnswerMode), forceNonEmptyAnswer=\(forceNonEmptyAnswer), delivery=\(String(describing: promptResolution.delivery))"
        )
        if shouldUseProviderManagedConversation, let remoteContext {
            VoxtLog.info(
                "Rewrite continue using Responses API. provider=\(remoteContext.provider.rawValue), endpoint=\(remoteContext.configuration.endpoint)"
            )
        } else if modelProvider == .remoteLLM,
                  directAnswerMode,
                  !structuredAnswerOutput,
                  onProgress != nil,
                  let remoteContext {
            VoxtLog.info(
                "Rewrite continue using chat completions stream. provider=\(remoteContext.provider.rawValue), endpoint=\(remoteContext.configuration.endpoint)"
            )
        }

        if modelProvider == .customLLM {
            guard customLLMManager.isModelDownloaded(repo: rewriteRepo) else {
                VoxtLog.warning("Rewrite provider customLLM unavailable: model not downloaded. repo=\(rewriteRepo)")
                showOverlayStatus(
                    String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
                return rewriteUnavailableFallbackText(
                    dictatedPrompt: dictatedPrompt,
                    sourceText: sourceText,
                    structuredAnswerOutput: structuredAnswerOutput
                )
            }
        } else {
            let context = remoteContext ?? resolvedRemoteLLMContext(forRewrite: true)
            guard isStoredRemoteLLMConfigured(context.provider) else {
                VoxtLog.warning("Rewrite provider remoteLLM unavailable: no configured model.")
                showOverlayStatus(
                    String(localized: "No configured remote LLM model yet. Configure a provider in Settings > Model."),
                    clearAfter: 2.5
                )
                return rewriteUnavailableFallbackText(
                    dictatedPrompt: dictatedPrompt,
                    sourceText: sourceText,
                    structuredAnswerOutput: structuredAnswerOutput
                )
            }
        }

        let conversationHistoryForPlan: [RewriteConversationPromptTurn]
        switch modelProvider {
        case .customLLM:
            conversationHistoryForPlan = []
        case .remoteLLM:
            switch promptResolution.delivery {
            case .systemPrompt:
                conversationHistoryForPlan = (shouldUseProviderManagedConversation || shouldUseChatMessageConversation) ? trimmedConversationHistory : []
            case .userMessage:
                conversationHistoryForPlan = shouldUseProviderManagedConversation ? trimmedConversationHistory : []
            }
        }

        let providerOverride: LLMExecutionProvider
        switch modelProvider {
        case .customLLM:
            providerOverride = .customLLM(repo: rewriteRepo)
        case .remoteLLM:
            let context = remoteContext ?? resolvedRemoteLLMContext(forRewrite: true)
            providerOverride = .remote(provider: context.provider, configuration: context.configuration)
        }
        let strategy = TaskLLMStrategyResolver.resolve(
            taskKind: .rewrite,
            rawText: directAnswerMode ? dictatedPrompt : sourceText,
            promptCharacterCount: promptResolution.content.count + (promptResolution.dictionaryGlossary?.count ?? 0),
            baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.rewrite.selectionPolicy,
            capabilities: llmProviderModelCapabilities(for: providerOverride)
        )
        let plan = buildRewriteExecutionPlan(
            dictatedPrompt: dictatedPrompt,
            sourceText: sourceText,
            promptResolution: promptResolution,
            modelProvider: modelProvider,
            conversationHistory: conversationHistoryForPlan,
            previousResponseID: shouldUseProviderManagedConversation ? previousConversationResponseID : nil,
            structuredAnswerOutput: structuredAnswerOutput,
            providerOverride: providerOverride,
            executionStrategy: strategy
        )
        let rewritten = try await executeLLMExecutionPlan(
            plan,
            onPartialText: onProgress,
            onResponseID: onResponseID
        )
        let originalText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? dictatedPrompt
            : sourceText
        return TaskLLMStrategyResolver.applyTruncationGuard(
            outputText: rewritten,
            originalText: originalText,
            strategy: strategy
        ).text
    }

    func translateTextStrict(
        _ text: String,
        targetLanguage: TranslationTargetLanguage
    ) async throws -> String {
        let resolution = resolvedTranslationProviderResolution(
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: isSelectedTextTranslationFlow
        )
        let modelProvider = resolution.provider
        let providerOverride: LLMExecutionProvider?
        switch modelProvider {
        case .customLLM:
            providerOverride = .customLLM(repo: translationCustomLLMRepo)
        case .remoteLLM:
            let context = resolvedRemoteLLMContext(forTranslation: true)
            providerOverride = .remote(provider: context.provider, configuration: context.configuration)
        case .whisperKit:
            providerOverride = nil
        }
        let basePolicy = DictionaryGlossaryPurpose.translation.selectionPolicy
        let provisionalStrategy = TaskLLMStrategyResolver.resolve(
            taskKind: .translation,
            rawText: text,
            promptCharacterCount: 0,
            baseGlossarySelectionPolicy: basePolicy,
            capabilities: providerOverride.map(llmProviderModelCapabilities(for:)) ?? .unknown
        )
        let promptResolution = resolvedTranslationPrompt(
            targetLanguage: targetLanguage,
            sourceText: text,
            strict: true,
            glossarySelectionPolicy: provisionalStrategy.glossarySelectionPolicy
        )
        let translationRepo = translationCustomLLMRepo
        VoxtLog.llm(
            "Strict translation retry. promptChars=\(promptResolution.content.count), inputChars=\(text.count), provider=\(modelProvider.rawValue), selectedProvider=\(translationModelProvider.rawValue), fallbackReason=\(resolution.fallbackReason.map(String.init(describing:)) ?? "none"), translationRepo=\(translationRepo), delivery=\(String(describing: promptResolution.delivery))"
        )

        if modelProvider == .customLLM {
            guard customLLMManager.isModelDownloaded(repo: translationRepo) else {
                return text
            }
        } else if modelProvider == .remoteLLM {
            let context = resolvedRemoteLLMContext(forTranslation: true)
            guard isStoredRemoteLLMConfigured(context.provider) else {
                return text
            }
        } else {
            return text
        }

        let strategy = TaskLLMStrategyResolver.resolve(
            taskKind: .translation,
            rawText: text,
            promptCharacterCount: promptResolution.content.count + (promptResolution.dictionaryGlossary?.count ?? 0),
            baseGlossarySelectionPolicy: basePolicy,
            capabilities: providerOverride.map(llmProviderModelCapabilities(for:)) ?? .unknown
        )
        guard let plan = buildTranslationExecutionPlan(
            sourceText: text,
            targetLanguage: targetLanguage,
            promptResolution: promptResolution,
            modelProvider: modelProvider,
            providerOverride: providerOverride,
            executionStrategy: strategy
        ) else {
            return text
        }
        let translated = try await executeLLMExecutionPlan(plan)
        return TaskLLMStrategyResolver.applyTruncationGuard(
            outputText: translated,
            originalText: text,
            strategy: strategy
        ).text
    }

    static func effectiveTranslationTargetLanguage(
        savedTargetLanguage: TranslationTargetLanguage,
        sessionOverride: TranslationTargetLanguage?,
        isSelectedTextTranslation: Bool
    ) -> TranslationTargetLanguage {
        guard !isSelectedTextTranslation, let sessionOverride else {
            return savedTargetLanguage
        }
        return sessionOverride
    }

    var effectiveSessionTranslationTargetLanguage: TranslationTargetLanguage {
        Self.effectiveTranslationTargetLanguage(
            savedTargetLanguage: translationTargetLanguage,
            sessionOverride: sessionTranslationTargetLanguageOverride,
            isSelectedTextTranslation: isSelectedTextTranslationFlow
        )
    }

    func resolvedTranslationProviderResolution(
        targetLanguage: TranslationTargetLanguage,
        isSelectedTextTranslation: Bool
    ) -> TranslationProviderResolution {
        Self.resolvedSessionTranslationProviderResolution(
            lockedResolution: activeSessionTranslationProviderResolution,
            selectedProvider: translationModelProvider,
            fallbackProvider: translationFallbackModelProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: isSelectedTextTranslation,
            whisperModelState: whisperModelManager.state
        )
    }

    static func resolvedSessionTranslationProviderResolution(
        lockedResolution: TranslationProviderResolution?,
        selectedProvider: TranslationModelProvider,
        fallbackProvider: TranslationModelProvider,
        transcriptionEngine: TranscriptionEngine,
        targetLanguage: TranslationTargetLanguage,
        isSelectedTextTranslation: Bool,
        whisperModelState: WhisperKitModelManager.ModelState
    ) -> TranslationProviderResolution {
        if !isSelectedTextTranslation,
           let lockedResolution {
            return lockedResolution
        }

        return TranslationProviderResolver.resolve(
            selectedProvider: selectedProvider,
            fallbackProvider: fallbackProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: isSelectedTextTranslation,
            whisperModelState: whisperModelState
        )
    }

    func prepareMicrophoneTranslationSessionState() {
        let persistedTargetLanguage = translationTargetLanguage
        let resolution = TranslationProviderResolver.resolve(
            selectedProvider: translationModelProvider,
            fallbackProvider: translationFallbackModelProvider,
            transcriptionEngine: transcriptionEngine,
            targetLanguage: persistedTargetLanguage,
            isSelectedTextTranslation: false,
            whisperModelState: whisperModelManager.state
        )

        sessionTranslationTargetLanguageOverride = persistedTargetLanguage
        activeSessionTranslationProviderResolution = resolution
        sessionUsesWhisperDirectTranslation = resolution.usesWhisperDirectTranslation
        overlayState.configureSessionTranslationTargetLanguage(
            persistedTargetLanguage,
            allowsSwitching: Self.shouldAllowSessionTranslationLanguageSwitching(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false,
                sessionUsesWhisperDirectTranslation: resolution.usesWhisperDirectTranslation
            )
        )
    }

    func resetSessionTranslationState() {
        cancelPendingSelectedTextTranslationRefresh()
        sessionTranslationTargetLanguageOverride = nil
        activeSessionTranslationProviderResolution = nil
        sessionUsesWhisperDirectTranslation = false
        overlayState.configureSessionTranslationTargetLanguage(nil, allowsSwitching: false)
    }

    static func shouldAllowSessionTranslationLanguageSwitching(
        sessionOutputMode: SessionOutputMode,
        isSelectedTextTranslationFlow: Bool,
        sessionUsesWhisperDirectTranslation: Bool
    ) -> Bool {
        sessionOutputMode == .translation &&
            !isSelectedTextTranslationFlow &&
            !sessionUsesWhisperDirectTranslation
    }

    func toggleSessionTranslationTargetPicker() {
        guard overlayState.allowsSessionTranslationLanguageSwitching else { return }
        if overlayState.isSessionTranslationTargetPickerPresented {
            dismissSessionTranslationTargetPicker()
        } else {
            overlayState.presentSessionTranslationTargetPicker()
        }
    }

    func selectSessionTranslationTargetLanguage(_ language: TranslationTargetLanguage) {
        guard overlayState.allowsSessionTranslationLanguageSwitching else { return }
        let previousLanguage = overlayState.sessionTranslationTargetLanguage
        let shouldRefreshDisplayedTranslation = shouldRefreshDisplayedTranslationAnswer(
            targetLanguage: language,
            previousLanguage: previousLanguage
        )

        if shouldRefreshDisplayedTranslation {
            overlayState.configureSessionTranslationTargetLanguage(language, allowsSwitching: true)
            overlayState.dismissSessionTranslationTargetPicker()
            refreshDisplayedTranslationAnswer(
                targetLanguage: language,
                previousLanguage: previousLanguage
            )
            return
        }

        if isSessionActive {
            sessionTranslationTargetLanguageOverride = language
        } else {
            UserDefaults.standard.set(language.rawValue, forKey: AppPreferenceKey.translationTargetLanguage)
        }
        overlayState.configureSessionTranslationTargetLanguage(language, allowsSwitching: true)
        overlayState.dismissSessionTranslationTargetPicker()
    }

    func dismissSessionTranslationTargetPicker() {
        overlayState.dismissSessionTranslationTargetPicker()
    }

    func shouldRefreshDisplayedTranslationAnswer(
        targetLanguage: TranslationTargetLanguage,
        previousLanguage: TranslationTargetLanguage?
    ) -> Bool {
        guard overlayState.displayMode == .answer,
              overlayState.sessionIconMode == .translation,
              overlayState.answerInteractionMode == .singleResult
        else {
            return false
        }
        guard targetLanguage != previousLanguage else { return false }
        return !overlayState.answerTranslationSourceText.isEmpty
    }

    func refreshDisplayedTranslationAnswer(
        targetLanguage: TranslationTargetLanguage,
        previousLanguage: TranslationTargetLanguage?
    ) {
        let sourceText = overlayState.answerTranslationSourceText
        guard !sourceText.isEmpty else { return }

        cancelPendingSelectedTextTranslationRefresh()
        overlayState.isRequesting = true

        let refreshID = UUID()
        selectedTextTranslationRefreshID = refreshID
        pendingSelectedTextTranslationRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                if self.selectedTextTranslationRefreshID == refreshID {
                    self.overlayState.isRequesting = false
                    self.pendingSelectedTextTranslationRefreshTask = nil
                }
            }

            do {
                let translated = try await self.runTranslationPipeline(
                    text: sourceText,
                    targetLanguage: targetLanguage,
                    allowStrictRetry: true
                )
                guard !Task.isCancelled,
                      self.selectedTextTranslationRefreshID == refreshID,
                      self.overlayState.sessionTranslationTargetLanguage == targetLanguage
                else {
                    return
                }

                self.overlayState.replaceCurrentAnswer(
                    title: String(localized: "Translation"),
                    content: translated
                )
            } catch {
                guard !Task.isCancelled,
                      self.selectedTextTranslationRefreshID == refreshID
                else {
                    return
                }

                VoxtLog.warning(
                    "Displayed translation refresh failed. sourceChars=\(sourceText.count), targetLanguage=\(targetLanguage.instructionName), error=\(error)"
                )

                if let previousLanguage {
                    if self.isSessionActive {
                        self.sessionTranslationTargetLanguageOverride = previousLanguage
                    } else {
                        UserDefaults.standard.set(
                            previousLanguage.rawValue,
                            forKey: AppPreferenceKey.translationTargetLanguage
                        )
                    }
                    self.overlayState.configureSessionTranslationTargetLanguage(
                        previousLanguage,
                        allowsSwitching: true
                    )
                }
            }
        }
    }

    func cancelPendingSelectedTextTranslationRefresh() {
        selectedTextTranslationRefreshID = UUID()
        pendingSelectedTextTranslationRefreshTask?.cancel()
        pendingSelectedTextTranslationRefreshTask = nil
        overlayState.isRequesting = false
    }

    func resolvedTranslationPrompt(
        targetLanguage: TranslationTargetLanguage,
        sourceText: String,
        strict: Bool,
        glossarySelectionPolicy: DictionaryGlossarySelectionPolicy?
    ) -> VariablePromptResolution {
        let basePrompt = TranslationPromptBuilder.build(
            systemPrompt: translationSystemPrompt,
            targetLanguage: targetLanguage,
            sourceText: sourceText,
            userMainLanguagePromptValue: userMainLanguagePromptValue,
            strict: strict
        )
        let glossary = dictionaryGlossaryText(
            for: sourceText,
            purpose: .translation,
            selectionPolicy: glossarySelectionPolicy
        )
        return VariablePromptResolution(
            content: basePrompt,
            dictionaryGlossary: glossary,
            delivery: deliveryForTemplate(
                translationSystemPrompt,
                variableTokens: ["{{SOURCE_TEXT}}"]
            )
        )
    }

    func resolvedRewritePrompt(
        dictatedPrompt: String,
        sourceText: String,
        conversationHistory: [RewriteConversationPromptTurn],
        structuredAnswerOutput: Bool,
        directAnswerMode: Bool,
        forceNonEmptyAnswer: Bool,
        glossarySelectionPolicy: DictionaryGlossarySelectionPolicy?
    ) -> VariablePromptResolution {
        let resolved = RewritePromptBuilder.build(
            systemPrompt: rewriteSystemPrompt,
            dictatedPrompt: dictatedPrompt,
            sourceText: sourceText,
            conversationHistory: conversationHistory,
            structuredAnswerOutput: structuredAnswerOutput,
            directAnswerMode: directAnswerMode,
            forceNonEmptyAnswer: forceNonEmptyAnswer
        )
        let glossary = dictionaryGlossaryText(
            for: "\(dictatedPrompt)\n\(sourceText)",
            purpose: .rewrite,
            selectionPolicy: glossarySelectionPolicy
        )
        return VariablePromptResolution(
            content: resolved,
            dictionaryGlossary: glossary,
            delivery: deliveryForTemplate(
                rewriteSystemPrompt,
                variableTokens: ["{{DICTATED_PROMPT}}", "{{SOURCE_TEXT}}"]
            )
        )
    }

    private func deliveryForTemplate(
        _ template: String,
        variableTokens: [String]
    ) -> VariablePromptDelivery {
        variableTokens.contains { template.contains($0) } ? .userMessage : .systemPrompt
    }

    func resolvedRewriteConversationPrompt(forceNonEmptyAnswer: Bool) -> String {
        let retryConstraint = forceNonEmptyAnswer
            ? """
            Retry rule:
            - A previous answer was empty, quoted-empty, or otherwise unusable.
            - This time, you must return a non-empty plain-text answer.
            - Do not return surrounding quotes.
            """
            : ""

        let base = """
        You are Voxt's follow-up voice conversation assistant.

        The previous conversation is provided as chat messages.
        Respond to the latest user message directly based on that conversation.

        Rules:
        1. Treat the latest user message as a follow-up to the previous assistant reply.
        2. If the user omits context with a short follow-up like “那大同呢”, infer the missing subject from the conversation history.
        3. Return plain text only.
        4. Do not return JSON, field names, markdown, or surrounding quotes.
        5. Do not return an empty string.
        """

        let prompt = [base, retryConstraint]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return prompt
    }

    private func trimmedRewriteConversationHistory(
        _ turns: [RewriteConversationPromptTurn]
    ) -> [RewriteConversationPromptTurn] {
        guard !turns.isEmpty else { return [] }
        let budget = (maxTurns: 4, maxCharacters: 1_600)

        let candidates = Array(turns.suffix(budget.maxTurns)).reversed()
        var selectedReversed: [RewriteConversationPromptTurn] = []
        var consumedCharacters = 0

        for turn in candidates {
            let turnCharacters = turn.userPromptText.count + turn.resultTitle.count + turn.resultContent.count
            let separatorCost = selectedReversed.isEmpty ? 0 : 4
            let nextCount = consumedCharacters + separatorCost + turnCharacters

            if !selectedReversed.isEmpty && nextCount > budget.maxCharacters {
                break
            }

            selectedReversed.append(turn)
            consumedCharacters = nextCount
        }

        return selectedReversed.reversed()
    }

    func shouldRetryStructuredRewriteAnswer(for text: String, dictatedPrompt: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if let payload = extractRewriteAnswerPayload(from: trimmed) {
            let normalizedContent = payload.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPrompt = dictatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedContent.isEmpty || normalizedContent.caseInsensitiveCompare(normalizedPrompt) == .orderedSame
        }

        let normalizedPrompt = dictatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare(normalizedPrompt) == .orderedSame {
            return true
        }

        let lowered = trimmed.lowercased()
        let looksStructuredStub =
            (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
            lowered.contains("\"title\"") ||
            lowered.contains("\"content\"") ||
            lowered.contains("title:") ||
            lowered.contains("content:")
        return looksStructuredStub
    }

    func rewriteUnavailableFallbackText(
        dictatedPrompt: String,
        sourceText: String,
        structuredAnswerOutput: Bool
    ) -> String {
        if structuredAnswerOutput {
            return serializedRewriteAnswerPayload(
                RewriteAnswerPayload(
                    title: String(localized: "AI Answer"),
                    content: String(localized: "Unable to generate answer.")
                )
            ) ?? #"{"title":"AI Answer","content":"Unable to generate answer."}"#
        }

        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSource.isEmpty {
            return sourceText
        }

        return String(localized: "Unable to generate answer.")
    }

    func serializedRewriteAnswerPayload(_ payload: RewriteAnswerPayload) -> String? {
        let object: [String: String] = [
            "title": payload.title,
            "content": payload.content
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    func runTranslationPipeline(
        text: String,
        targetLanguage: TranslationTargetLanguage,
        allowStrictRetry: Bool
    ) async throws -> String {
        let stages = TranslationSessionPipelineBuilder.makeTranslationStages(
            targetLanguage: targetLanguage,
            allowStrictRetry: allowStrictRetry,
            translate: { [weak self] value, targetLanguage in
                guard let self else { return value }
                return try await self.translateText(value, targetLanguage: targetLanguage)
            },
            shouldRetry: { [weak self] source, result in
                guard let self else { return false }
                if self.looksUntranslated(source: source, result: result) {
                    VoxtLog.warning("Selected text translation first-pass looks untranslated. Retrying with strict translation prompt.")
                    return true
                }
                return false
            },
            strictTranslate: { [weak self] value, targetLanguage in
                guard let self else { return value }
                return try await self.translateTextStrict(value, targetLanguage: targetLanguage)
            }
        )
        let runner = SessionPipelineRunner(stages: stages)
        let initial = SessionPipelineContext(originalText: text, workingText: text)
        let result = try await runner.run(initial: initial)
        return result.workingText
    }

    func runRewritePipeline(
        dictatedText: String,
        selectedSourceText: String,
        conversationHistory: [RewriteConversationPromptTurn],
        structuredAnswerOutput: Bool,
        previousConversationResponseID: String? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil,
        onResponseID: ((String) -> Void)? = nil
    ) async throws -> String {
        let stages = TranslationSessionPipelineBuilder.makeRewriteStages(
            sourceText: selectedSourceText,
            rewrite: { [weak self] dictatedPrompt, sourceText in
                guard let self else { return dictatedPrompt }
                return try await self.rewriteText(
                    dictatedPrompt: dictatedPrompt,
                    sourceText: sourceText,
                    conversationHistory: conversationHistory,
                    structuredAnswerOutput: structuredAnswerOutput,
                    previousConversationResponseID: previousConversationResponseID,
                    onProgress: onProgress,
                    onResponseID: onResponseID
                )
            }
        )
        let runner = SessionPipelineRunner(stages: stages)
        let initial = SessionPipelineContext(originalText: dictatedText, workingText: dictatedText)
        let result = try await runner.run(initial: initial)
        return result.workingText
    }

    func presentRewriteConversationPseudoStreamingPreview(
        content: String,
        sessionID: UUID
    ) async {
        let normalized = RewriteAnswerContentNormalizer.normalizePlainTextAnswer(content)
        guard !normalized.isEmpty else { return }

        // Large answers should appear immediately; dozens of staged updates stall the
        // overlay and spinner on the main thread without adding useful feedback.
        guard normalized.count < 360 else {
            guard shouldHandleCallbacks(for: sessionID) else { return }
            presentRewriteConversationStreamingPreview(content: normalized)
            return
        }

        let characters = Array(normalized)
        let stageCount = min(4, max(2, Int(ceil(Double(characters.count) / 96.0))))
        let chunkSize = max(24, Int(ceil(Double(characters.count) / Double(stageCount))))

        var rendered = ""
        var index = 0
        while index < characters.count {
            guard shouldHandleCallbacks(for: sessionID) else { return }
            let upperBound = min(index + chunkSize, characters.count)
            rendered += String(characters[index..<upperBound])
            presentRewriteConversationStreamingPreview(content: rendered)
            index = upperBound
            guard index < characters.count else { continue }
            do {
                try await Task.sleep(for: .milliseconds(45))
            } catch {
                return
            }
        }
    }

    func looksUntranslated(source: String, result: String) -> Bool {
        let sourceTrimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultTrimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceTrimmed.isEmpty, !resultTrimmed.isEmpty else { return false }
        return sourceTrimmed.caseInsensitiveCompare(resultTrimmed) == .orderedSame
    }
}

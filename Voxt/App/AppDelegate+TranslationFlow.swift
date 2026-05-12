import Foundation
import AppKit

extension AppDelegate {
    // MARK: - Translation Flow
    // Keeps translation/enhancement orchestration isolated from recording lifecycle.

    func runTranslationPreview(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let previousSelectedTextTranslationFlow = isSelectedTextTranslationFlow
        isSelectedTextTranslationFlow = false
        defer {
            isSelectedTextTranslationFlow = previousSelectedTextTranslationFlow
        }

        return try await runTranslationPipeline(
            text: trimmed,
            targetLanguage: translationTargetLanguage,
            allowStrictRetry: true
        )
    }

    func runRewritePreview(dictatedPrompt: String, sourceText: String) async throws -> String {
        let trimmedPrompt = dictatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty || !trimmedSource.isEmpty else { return "" }

        return try await runRewritePipeline(
            dictatedText: trimmedPrompt,
            selectedSourceText: trimmedSource,
            conversationHistory: [],
            structuredAnswerOutput: trimmedSource.isEmpty
        )
    }

    func processTranslatedTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        let targetLanguage = effectiveSessionTranslationTargetLanguage
        let resolution = resolvedTranslationProviderResolution(
            targetLanguage: targetLanguage,
            isSelectedTextTranslation: false
        )
        VoxtLog.info(
            "Translation flow started. inputChars=\(text.count), targetLanguage=\(targetLanguage.instructionName), translationModelProvider=\(translationModelProvider.rawValue), resolvedProvider=\(resolution.provider.rawValue)"
        )
        setEnhancingState(true)
        overlayState.transcribedText = text
        _Concurrency.Task<Void, Never> {
            defer {
                self.setEnhancingState(false)
            }

            let llmStartedAt = Date()
            do {
                let translated = try await self.runTranslationPipeline(
                    text: text,
                    targetLanguage: targetLanguage,
                    allowStrictRetry: false
                )
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Translation output may be untranslated. sourceChars=\(text.count), outputChars=\(translated.count)")
                }
                VoxtLog.info("Translation flow succeeded. outputChars=\(translated.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.commitTranscription(translated, llmDurationSeconds: llmDuration) { [weak self] in
                    guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                    self.finishSession(after: 0)
                }
            } catch {
                guard self.shouldHandleCallbacks(for: sessionID) else { return }
                VoxtLog.warning("Translation flow failed, using raw text: \(error)")
                self.commitTranscription(text, llmDurationSeconds: nil) { [weak self] in
                    guard let self, self.shouldHandleCallbacks(for: sessionID) else { return }
                    self.finishSession(after: 0)
                }
            }
        }
    }

    func processWhisperTranslatedTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        VoxtLog.info("Whisper direct translation completed. outputChars=\(text.count)")
        commitTranscription(text, llmDurationSeconds: nil) { [weak self] in
            self?.finishSession(after: 0)
        }
    }

    func beginSelectedTextTranslationIfPossible() -> Bool {
        guard translateSelectedTextOnTranslationHotkey else { return false }
        guard !isSessionActive else { return false }
        guard let selectedText = selectedTextFromSystemSelection(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        pendingSessionFinishTask?.cancel()
        pendingSessionFinishTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
        releaseResidualRecordingResources(reason: "selected-text-translation-begin")
        resetSessionTranslationState()
        overlayState.reset()
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmostApplication?.bundleIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier
        if let frontmostBundleID,
           frontmostBundleID != ownBundleID {
            sessionTargetApplicationBundleID = frontmostBundleID
        } else {
            sessionTargetApplicationBundleID = nil
        }
        sessionTargetApplicationPID = sessionTargetApplicationBundleID == nil ? nil : frontmostApplication?.processIdentifier
        selectedTextTranslationHadWritableFocusedInput = hasWritableFocusedTextInput()
        overlayState.transcribedText = selectedText
        overlayState.setAnswerTranslationSourceText(selectedText)
        overlayState.statusMessage = ""
        overlayState.presentRecording(iconMode: .translation)
        overlayWindow.show(state: overlayState, position: overlayPosition)

        let startedAt = Date()
        isSessionActive = true
        isSelectedTextTranslationFlow = true
        didCommitSessionOutput = false
        isSessionCancellationRequested = false
        activeRecordingSessionID = UUID()
        invalidateActiveLLMRequest()
        currentEndingSessionID = nil
        lastCompletedSessionEndSessionID = nil
        sessionOutputMode = .translation
        recordingRequestedAt = startedAt
        recordingStartedAt = startedAt
        recordingStoppedAt = startedAt
        transcriptionProcessingStartedAt = nil
        transcriptionResultReceivedAt = nil
        sessionFinalOutputDeliveredAt = nil
        sessionLLMExecutionTimings = []
        enhancementContextSnapshot = nil
        lastEnhancementPromptContext = nil

        if interactionSoundsEnabled {
            interactionSoundPlayer.playStart()
        }

        VoxtLog.info("Selected text translation started. inputChars=\(selectedText.count)")
        prewarmSelectedTextTranslationLLMIfNeeded(targetLanguage: effectiveSessionTranslationTargetLanguage)
        processSelectedTextTranslation(selectedText)
        return true
    }

    func processRewriteTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        let isConversationContinuation = overlayState.isRewriteConversationActive
        let selectedSourceText: String
        let conversationHistory: [RewriteConversationPromptTurn]
        let prefersStructuredAnswerOutput: Bool
        let previousConversationResponseID: String?

        if isConversationContinuation {
            selectedSourceText = ""
            conversationHistory = overlayState.rewriteConversationPromptHistory
            rewriteSessionHasSelectedSourceText = false
            prefersStructuredAnswerOutput = false
            previousConversationResponseID = overlayState.rewriteConversationRemoteResponseID
            overlayState.stageConversationUserPrompt(text)
        } else {
            selectedSourceText = selectedTextFromSystemSelection()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            rewriteSessionHasSelectedSourceText = !selectedSourceText.isEmpty
            conversationHistory = []
            prefersStructuredAnswerOutput = shouldUseStructuredRewriteAnswerOutput(
                hasSelectedSourceText: rewriteSessionHasSelectedSourceText
            )
            previousConversationResponseID = nil
        }
        VoxtLog.info(
            "Rewrite flow started. promptChars=\(text.count), selectedSourceChars=\(selectedSourceText.count), rewriteModelProvider=\(rewriteModelProvider.rawValue), structuredAnswerOutput=\(prefersStructuredAnswerOutput), conversationHistoryTurns=\(conversationHistory.count)"
        )
        setEnhancingState(true)
        let requestID = beginLLMRequest()
        let progressHandler: (@Sendable (String) -> Void)? = if isConversationContinuation {
            { [weak self] partialOutput in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.shouldHandleCallbacks(for: sessionID),
                          self.isCurrentLLMRequest(requestID)
                    else { return }
                    self.presentRewriteConversationStreamingPreview(content: partialOutput)
                }
            }
        } else {
            nil
        }

        Task {
            defer {
                if self.isCurrentLLMRequest(requestID) {
                    self.setEnhancingState(false)
                }
            }

            let llmStartedAt = Date()
            var latestConversationResponseID: String?
            do {
                var rewritten: String
                let rewriteResult = try await self.runRewritePipeline(
                    dictatedText: text,
                    selectedSourceText: selectedSourceText,
                    conversationHistory: conversationHistory,
                    structuredAnswerOutput: prefersStructuredAnswerOutput,
                    previousConversationResponseID: previousConversationResponseID,
                    onProgress: progressHandler,
                    onResponseID: { responseID in
                        guard self.isCurrentLLMRequest(requestID) else { return }
                        latestConversationResponseID = responseID
                    }
                )
                rewritten = rewriteResult
                if prefersStructuredAnswerOutput,
                   self.shouldRetryStructuredRewriteAnswer(for: rewritten, dictatedPrompt: text) {
                    VoxtLog.warning("Rewrite structured answer was missing usable content; retrying in direct-answer mode.")
                    if let retried = try? await self.rewriteText(
                        dictatedPrompt: text,
                        sourceText: "",
                        conversationHistory: conversationHistory,
                        structuredAnswerOutput: true,
                        forceNonEmptyAnswer: true,
                        previousConversationResponseID: previousConversationResponseID,
                        onProgress: nil,
                        onResponseID: { responseID in
                            guard self.isCurrentLLMRequest(requestID) else { return }
                            latestConversationResponseID = responseID
                        }
                    ) {
                        rewritten = retried
                    }
                }
                if !prefersStructuredAnswerOutput {
                    let normalized = RewriteAnswerContentNormalizer.normalizePlainTextAnswer(rewritten)
                    if normalized != rewritten.trimmingCharacters(in: .whitespacesAndNewlines) {
                        VoxtLog.warning(
                            """
                            Rewrite plain-text answer normalized before delivery.
                            [raw]
                            \(VoxtLog.llmPreview(rewritten))
                            [normalized]
                            \(VoxtLog.llmPreview(normalized))
                            """
                        )
                    }
                    rewritten = normalized
                }
                if prefersStructuredAnswerOutput,
                   self.shouldRetryStructuredRewriteAnswer(for: rewritten, dictatedPrompt: text) {
                    VoxtLog.warning("Rewrite structured answer still unusable after retry; substituting empty-answer placeholder.")
                    rewritten = self.rewriteUnavailableFallbackText(
                        dictatedPrompt: text,
                        sourceText: selectedSourceText,
                        structuredAnswerOutput: true
                    )
                }
                if !prefersStructuredAnswerOutput,
                   RewriteAnswerContentNormalizer.isUnusablePlainTextAnswer(rewritten, dictatedPrompt: text) {
                    VoxtLog.warning("Rewrite plain-text answer was empty or unusable; retrying with stricter non-empty guidance.")
                    if let retried = try? await self.rewriteText(
                        dictatedPrompt: text,
                        sourceText: selectedSourceText,
                        conversationHistory: conversationHistory,
                        structuredAnswerOutput: false,
                        forceNonEmptyAnswer: true,
                        previousConversationResponseID: previousConversationResponseID,
                        onProgress: progressHandler,
                        onResponseID: { responseID in
                            guard self.isCurrentLLMRequest(requestID) else { return }
                            latestConversationResponseID = responseID
                        }
                    ) {
                        rewritten = RewriteAnswerContentNormalizer.normalizePlainTextAnswer(retried)
                    }
                }
                if !prefersStructuredAnswerOutput,
                   RewriteAnswerContentNormalizer.isUnusablePlainTextAnswer(rewritten, dictatedPrompt: text) {
                    VoxtLog.warning("Rewrite plain-text answer remained unusable after retry; substituting fallback text.")
                    rewritten = self.rewriteUnavailableFallbackText(
                        dictatedPrompt: text,
                        sourceText: selectedSourceText,
                        structuredAnswerOutput: false
                    )
                }
                guard self.shouldHandleCallbacks(for: sessionID), self.isCurrentLLMRequest(requestID) else { return }
                if isConversationContinuation, let latestConversationResponseID {
                    self.overlayState.rewriteConversationRemoteResponseID = latestConversationResponseID
                }
                if isConversationContinuation,
                   !self.overlayState.isStreamingAnswer,
                   !rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await self.presentRewriteConversationPseudoStreamingPreview(
                        content: rewritten,
                        sessionID: sessionID
                    )
                }
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                VoxtLog.info("Rewrite flow succeeded. outputChars=\(rewritten.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.commitTranscription(rewritten, llmDurationSeconds: llmDuration) { [weak self] in
                    guard let self,
                          self.shouldHandleCallbacks(for: sessionID),
                          self.isCurrentLLMRequest(requestID)
                    else { return }
                    self.finishSession(after: 0)
                }
            } catch {
                guard self.shouldHandleCallbacks(for: sessionID), self.isCurrentLLMRequest(requestID) else { return }
                VoxtLog.warning("Rewrite flow failed, using rewrite fallback: \(error)")
                let fallback = self.rewriteUnavailableFallbackText(
                    dictatedPrompt: text,
                    sourceText: selectedSourceText,
                    structuredAnswerOutput: prefersStructuredAnswerOutput
                )
                self.commitTranscription(fallback, llmDurationSeconds: nil) { [weak self] in
                    guard let self,
                          self.shouldHandleCallbacks(for: sessionID),
                          self.isCurrentLLMRequest(requestID)
                    else { return }
                    self.finishSession(after: 0)
                }
            }
        }
    }

    private func processSelectedTextTranslation(_ text: String) {
        setEnhancingState(true)
        let requestID = beginLLMRequest()
        Task {
            defer {
                if self.isCurrentLLMRequest(requestID) {
                    self.setEnhancingState(false)
                }
            }

            let llmStartedAt = Date()
            do {
                let translated = try await self.runTranslationPipeline(
                    text: text,
                    targetLanguage: self.translationTargetLanguage,
                    allowStrictRetry: true
                )
                guard self.isCurrentLLMRequest(requestID) else { return }
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Selected text translation output may be untranslated. inputChars=\(text.count), outputChars=\(translated.count)")
                }
                VoxtLog.info("Selected text translation succeeded. outputChars=\(translated.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.overlayState.transcribedText = translated
                self.commitTranscription(translated, llmDurationSeconds: llmDuration) { [weak self] in
                    guard let self, self.isCurrentLLMRequest(requestID) else { return }
                    self.finishSession(after: 0)
                }
            } catch {
                guard self.isCurrentLLMRequest(requestID) else { return }
                VoxtLog.warning("Selected text translation failed, using original selected text: \(error)")
                self.overlayState.transcribedText = text
                self.commitTranscription(text, llmDurationSeconds: nil) { [weak self] in
                    guard let self, self.isCurrentLLMRequest(requestID) else { return }
                    self.finishSession(after: 0)
                }
            }
        }
    }

}

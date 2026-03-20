import Foundation

extension AppDelegate {
    var agentMCPHistoryEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.agentMCPHistoryEnabled)
    }

    func handleAgentMCPAskUserVoice(request: AgentPromptRequest) async -> AgentPromptToolResponse {
        guard agentMCPServerController.isEnabled else {
            return .error(.serverDisabled, message: AppLocalization.localizedString("The Voxt MCP server is disabled."))
        }

        guard activeAgentPromptRequest == nil,
              !isSessionActive,
              pendingTranscriptionStartTask == nil else {
            return .error(.busy, message: AppLocalization.localizedString("Voxt is already handling another recording session."))
        }

        return await withCheckedContinuation { continuation in
            activeAgentPromptRequest = request
            activeAgentPromptContinuation = continuation
            activeAgentPromptState = .prompting
            sessionInvocationSource = .mcp
            sessionDeliveryTarget = .mcpResponse
            didCommitSessionOutput = false
            isSessionCancellationRequested = false
            overlayState.reset()
            overlayState.presentAgentPrompt(
                title: AppLocalization.localizedString("AI needs your input"),
                contextHint: request.contextHint,
                questions: request.questions,
                shortcutKeyCode: agentMCPReplyShortcutKeyCode,
                shortcutLabel: agentMCPReplyShortcutLabel
            )
            overlayWindow.show(state: overlayState, position: overlayPosition)
            startAgentPromptTimeoutTimer(for: request)
        }
    }

    func confirmAgentPromptAndStartRecording() {
        guard activeAgentPromptRequest != nil else { return }
        activeAgentPromptState = .recording
        let started = beginRecording(
            outputMode: .transcription,
            invocationSource: .mcp,
            deliveryTarget: .mcpResponse
        )
        if !started {
            resolveAgentPromptSession(
                with: .error(
                    .permissionDenied,
                    message: AppLocalization.localizedString("Microphone permission is required before Voxt can record an answer.")
                )
            )
        }
    }

    func stopAgentPromptRecording() {
        guard activeAgentPromptRequest != nil else { return }
        guard isSessionActive else { return }
        endRecording()
    }

    func cancelAgentPromptInteraction() {
        guard activeAgentPromptRequest != nil else { return }

        if isSessionActive {
            cancelActiveRecordingSession()
            return
        }

        resolveAgentPromptSession(with: .cancelled())
    }

    func processAgentPromptTranscription(_ text: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resolveAgentPromptSession(
                with: .error(
                    .transcriptionFailed,
                    message: AppLocalization.localizedString("Voxt could not detect any spoken answer.")
                )
            )
            return
        }

        if agentMCPHistoryEnabled {
            _ = appendHistoryIfNeeded(
                text: trimmed,
                llmDurationSeconds: nil,
                dictionaryHitTerms: [],
                dictionaryCorrectedTerms: [],
                dictionarySuggestedTerms: []
            )
        }

        resolveAgentPromptSession(with: .answered(trimmed))
    }

    func resetAgentPromptState() {
        agentPromptTimeoutTask?.cancel()
        agentPromptTimeoutTask = nil
        activeAgentPromptRequest = nil
        activeAgentPromptContinuation = nil
        activeAgentPromptState = .idle
    }

    private func startAgentPromptTimeoutTimer(for request: AgentPromptRequest) {
        agentPromptTimeoutTask?.cancel()
        agentPromptTimeoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(request.timeoutSeconds))
            } catch {
                return
            }
            guard self.activeAgentPromptRequest?.id == request.id else { return }
            self.timeoutActiveAgentPrompt()
        }
    }

    private func timeoutActiveAgentPrompt() {
        if isSessionActive {
            activeRecordingSessionID = UUID()
            isSessionCancellationRequested = true
            stopActiveRecordingTranscriber()
        }
        resolveAgentPromptSession(with: .timedOut())
    }

    private func resolveAgentPromptSession(with response: AgentPromptToolResponse) {
        let continuation = activeAgentPromptContinuation
        activeAgentPromptContinuation = nil
        activeAgentPromptRequest = nil
        agentPromptTimeoutTask?.cancel()
        agentPromptTimeoutTask = nil

        switch response.status {
        case "answered":
            activeAgentPromptState = .completed
        case "cancelled":
            activeAgentPromptState = .cancelled
        case "timeout":
            activeAgentPromptState = .failed
        default:
            activeAgentPromptState = .failed
        }

        continuation?.resume(returning: response)
        executeSessionEndPipeline()
    }
}

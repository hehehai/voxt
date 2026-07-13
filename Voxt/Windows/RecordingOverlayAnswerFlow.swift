// RecordingOverlayAnswerFlow.swift
// Provides Recording Overlay Answer Flow for window and overlay UI.

import Foundation

extension OverlayState {
    func presentAnswer(title: String, content: String, canInject: Bool) {
        let payload = RewriteAnswerPayloadParser.normalize(RewriteAnswerPayload(
            title: title,
            content: content
        ))
        answerTitle = payload.title
        answerContent = payload.content
        latestRewriteResult = payload
        isStreamingAnswer = false
        canInjectAnswer = canInject
        displayMode = .answer
        isRecording = false
        audioLevel = 0
        isEnhancing = false
        isRequesting = false
        isFinalizingTranscription = false
        isCompleting = false
        isRewriteConversationTurnInProgress = false
        statusMessage = ""
        compactLeadingIconImage = nil
        dismissSessionTranslationTargetPicker()

        if isRewriteConversationActive {
            appendConversationResult(payload)
        } else {
            answerInteractionMode = .singleResult
            rewriteConversationTurns = []
            rewriteConversationRemoteResponseID = nil
            pendingConversationUserPrompt = nil
        }
    }

    func presentStreamingAnswer(title: String, content: String, canInject: Bool) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppLocalization.localizedString("AI Answer")
            : title
        let previewPayload = RewriteAnswerPayload(
            title: normalizedTitle,
            content: content
        )

        answerTitle = previewPayload.title
        answerContent = previewPayload.content
        isStreamingAnswer = true
        canInjectAnswer = canInject
        displayMode = .answer
        isRecording = false
        audioLevel = 0
        isFinalizingTranscription = false
        isCompleting = false
        statusMessage = ""
        compactLeadingIconImage = nil
        dismissSessionTranslationTargetPicker()

        if !isRewriteConversationActive {
            answerInteractionMode = .singleResult
            rewriteConversationTurns = []
            rewriteConversationRemoteResponseID = nil
            pendingConversationUserPrompt = nil
        }
    }

    func presentConversationAnswer(content: String, canInject: Bool) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        let payload = RewriteAnswerPayload(title: "", content: trimmedContent)
        answerTitle = ""
        answerContent = payload.content
        latestRewriteResult = payload
        isStreamingAnswer = false
        canInjectAnswer = canInject
        displayMode = .answer
        isRecording = false
        audioLevel = 0
        isEnhancing = false
        isRequesting = false
        isFinalizingTranscription = false
        isCompleting = false
        isRewriteConversationTurnInProgress = false
        statusMessage = ""
        compactLeadingIconImage = nil
        dismissSessionTranslationTargetPicker()

        if isRewriteConversationActive {
            appendConversationResult(payload)
        } else {
            answerInteractionMode = .conversation
            rewriteConversationTurns = [RewriteConversationTurn.seed(from: payload)]
            rewriteConversationRemoteResponseID = nil
            pendingConversationUserPrompt = nil
        }
    }

    func presentStreamingConversationAnswer(content: String, canInject: Bool) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        answerTitle = ""
        answerContent = trimmedContent
        isStreamingAnswer = true
        canInjectAnswer = canInject
        displayMode = .answer
        isRewriteConversationTurnInProgress = true
        isRecording = false
        audioLevel = 0
        isFinalizingTranscription = false
        isCompleting = false
        statusMessage = ""
        compactLeadingIconImage = nil
        dismissSessionTranslationTargetPicker()
    }

    var shouldAnimateVisuals: Bool {
        isPresented && (
            isRecording ||
                isModelInitializing ||
                displayMode == .processing ||
                isEnhancing ||
                isRequesting ||
                isFinalizingTranscription
        )
    }

    var currentAnswerPayload: RewriteAnswerPayload? {
        let draftTitle = answerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftContent = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draftTitle.isEmpty || !draftContent.isEmpty {
            return RewriteAnswerPayload(title: answerTitle, content: answerContent)
        }

        if let latestRewriteResult {
            return latestRewriteResult
        }

        let content = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return RewriteAnswerPayload(title: answerTitle, content: answerContent)
    }

    var latestCompletedAnswerPayload: RewriteAnswerPayload? {
        if let latestRewriteResult {
            return latestRewriteResult
        }

        guard displayMode == .answer, !isStreamingAnswer else { return nil }
        let content = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return RewriteAnswerPayload(title: answerTitle, content: answerContent)
    }

    var canCopyLatestAnswer: Bool {
        latestCompletedAnswerPayload != nil
    }

    var canShowLatestHistoryDetail: Bool {
        guard displayMode == .answer, !isStreamingAnswer else { return false }
        return latestHistoryEntryID != nil
    }

    var canContinueRewriteAnswer: Bool {
        guard displayMode == .answer,
              sessionIconMode == .rewrite,
              answerInteractionMode == .singleResult,
              latestCompletedAnswerPayload != nil
        else {
            return false
        }
        return true
    }

    var showsRewriteContinueButton: Bool {
        guard displayMode == .answer, sessionIconMode == .rewrite else { return false }
        switch answerInteractionMode {
        case .singleResult:
            return latestCompletedAnswerPayload != nil
        case .conversation:
            guard latestCompletedAnswerPayload != nil else { return false }
            return !isRewriteConversationTurnInProgress &&
                !isRecording &&
                !isModelInitializing &&
                !isEnhancing &&
                !isRequesting &&
                !isFinalizingTranscription &&
                !isCompleting &&
                !isStreamingAnswer
        }
    }

    var isRewriteConversationActive: Bool {
        displayMode == .answer &&
            sessionIconMode == .rewrite &&
            answerInteractionMode == .conversation
    }

    var rewriteConversationPromptHistory: [RewriteConversationPromptTurn] {
        rewriteConversationTurns.map(\.promptTurn)
    }

    var answerSpaceShortcutAction: AnswerSpaceShortcutAction? {
        guard displayMode == .answer, sessionIconMode == .rewrite else { return nil }
        switch answerInteractionMode {
        case .singleResult:
            return latestCompletedAnswerPayload == nil ? nil : .continueAndRecord
        case .conversation:
            return .toggleConversationRecording
        }
    }

    func beginRewriteConversationIfNeeded() {
        guard canContinueRewriteAnswer, let payload = latestCompletedAnswerPayload else { return }
        answerInteractionMode = .conversation
        rewriteConversationTurns = [RewriteConversationTurn.seed(from: payload)]
        latestRewriteResult = payload
        rewriteConversationRemoteResponseID = nil
        pendingConversationUserPrompt = nil
    }

    func stageConversationUserPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingConversationUserPrompt = trimmed.isEmpty ? nil : trimmed
    }

    func clearPendingConversationUserPrompt() {
        pendingConversationUserPrompt = nil
    }

    func configureSessionTranslationTargetLanguage(
        _ language: TranslationTargetLanguage?,
        allowsSwitching: Bool
    ) {
        sessionTranslationTargetLanguage = language
        sessionTranslationDraftLanguage = language
        allowsSessionTranslationLanguageSwitching = allowsSwitching
        if !allowsSwitching {
            dismissSessionTranslationTargetPicker()
            clearSessionTranslationLanguageHover()
        }
    }

    func presentSessionTranslationTargetPicker() {
        guard allowsSessionTranslationLanguageSwitching else { return }
        sessionTranslationDraftLanguage = sessionTranslationTargetLanguage
        isSessionTranslationTargetPickerPresented = true
    }

    func dismissSessionTranslationTargetPicker() {
        sessionTranslationDraftLanguage = sessionTranslationTargetLanguage
        isSessionTranslationTargetPickerPresented = false
    }

    func setSessionTranslationLanguageHovering(_ isHovering: Bool) {
        isSessionTranslationLanguageHovering = isHovering
    }

    func clearSessionTranslationLanguageHover() {
        isSessionTranslationLanguageHovering = false
    }

    func setAnswerTranslationSourceText(_ text: String) {
        answerTranslationSourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func replaceCurrentAnswer(title: String, content: String) {
        let payload = RewriteAnswerPayloadParser.normalize(
            RewriteAnswerPayload(title: title, content: content)
        )
        answerTitle = payload.title
        answerContent = payload.content
        latestRewriteResult = payload
        latestHistoryEntryID = nil
        isStreamingAnswer = false
        isEnhancing = false
        isRequesting = false
        isFinalizingTranscription = false
        compactLeadingIconImage = nil
    }

    private func appendConversationResult(_ payload: RewriteAnswerPayload) {
        latestRewriteResult = payload
        let userPrompt = pendingConversationUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pendingConversationUserPrompt = nil

        if rewriteConversationTurns.isEmpty {
            rewriteConversationTurns = [RewriteConversationTurn.seed(from: payload)]
            return
        }

        rewriteConversationTurns.append(
            RewriteConversationTurn(
                userPromptText: userPrompt,
                resultTitle: payload.title,
                resultContent: payload.content
            )
        )
    }
}

import Foundation

extension AppDelegate {
    func handleLiveASRPartialTranscription(_ rawText: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        let displayText = RecordingSessionSupport.normalizedTranscriptionDisplayText(
            rawText,
            transcriptionEngine: transcriptionEngine,
            remoteProvider: remoteASRSelectedProvider,
            userMainLanguage: userMainLanguage
        )
        let text = sanitizedFinalTranscriptionText(displayText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recordLiveASRPartialTranscription(text, sessionID: sessionID)
    }

    private func recordLiveASRPartialTranscription(_ text: String, sessionID: UUID) {
        guard recordingStoppedAt == nil else { return }
        guard transcriptionCapturePipeline.usesLiveDisplay else { return }
        guard sessionOutputMode == .transcription else { return }

        let isFirstLivePartial = firstLiveASRPartialReceivedAt == nil
        if isFirstLivePartial {
            firstLiveASRPartialReceivedAt = Date()
            VoxtLog.info(
                "Live ASR partial received. sessionID=\(sessionID.uuidString), chars=\(text.count), pipeline=\(transcriptionCapturePipeline.rawValue)",
                verbose: true
            )
        }

        if transcriptionCapturePipeline == .noteSession {
            refreshVoxtNoteTranscriptDisplay()
        }
    }

    func processTranscription(_ rawText: String) {
        processTranscription(rawText, sessionID: activeRecordingSessionID)
    }

    func processTranscription(_ rawText: String, sessionID: UUID) {
        let callbackDecision = Self.sessionCallbackHandlingDecision(
            requestedSessionID: sessionID,
            activeSessionID: activeRecordingSessionID,
            isSessionCancellationRequested: isSessionCancellationRequested
        )
        guard callbackDecision == .accept else {
            VoxtLog.info(
                """
                Dropping transcription callback before processing. reason=\(callbackDecision.logDescription), callbackSessionID=\(sessionID.uuidString), activeSessionID=\(activeRecordingSessionID.uuidString), stopped=\(recordingStoppedAt != nil), endingSessionID=\(currentEndingSessionID?.uuidString ?? "nil"), rawChars=\(rawText.count)
                """,
                verbose: true
            )
            return
        }
        if didCommitSessionOutput {
            VoxtLog.info("Ignoring transcription callback because current session output has already been committed.")
            return
        }

        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil

        transcriptionResultReceivedAt = Date()
        if let stoppedAt = recordingStoppedAt {
            let stopToResultMs = max(Int(Date().timeIntervalSince(stoppedAt) * 1000), 0)
            VoxtLog.info(
                "Transcription callback accepted after stop. sessionID=\(sessionID.uuidString), stopToResultMs=\(stopToResultMs), rawChars=\(rawText.count)",
                verbose: true
            )
        }
        let displayText = RecordingSessionSupport.normalizedTranscriptionDisplayText(
            rawText,
            transcriptionEngine: transcriptionEngine,
            remoteProvider: remoteASRSelectedProvider,
            userMainLanguage: userMainLanguage
        )
        let text = sanitizedFinalTranscriptionText(displayText)
        guard !text.isEmpty else {
            if isCurrentTranscriptionNoteSessionActive {
                _ = captureTrailingVoxtNoteIfNeeded(finalRawText: currentSessionRawTranscribedText())
            } else {
                VoxtLog.info("Transcription result is empty; finishing session.")
            }
            setEnhancingState(false)
            finishSession(after: 0)
            return
        }

        updateActiveRecordingTranscriberTranscribedText(text)
        refreshVoxtNoteTranscriptDisplay()

        VoxtLog.info("Transcription result received. characters=\(text.count), output=\(sessionOutputMode == .translation ? "translation" : "transcription")")
        VoxtLog.info("Transcription result output mode resolved as \(RecordingSessionSupport.outputLabel(for: sessionOutputMode)).", verbose: true)
        VoxtLog.model(
            "Session text model routing: \(RecordingSessionSupport.textModelRoutingDescription(outputMode: sessionOutputMode, transcriptionSettings: transcriptionFeatureSettings, translationSettings: translationFeatureSettings, rewriteSettings: rewriteFeatureSettings))"
        )

        if sessionOutputMode == .translation {
            if sessionUsesWhisperDirectTranslation {
                processWhisperTranslatedTranscription(text, sessionID: sessionID)
            } else {
                processTranslatedTranscription(text, sessionID: sessionID)
            }
            return
        }

        if sessionOutputMode == .rewrite {
            processRewriteTranscription(text, sessionID: sessionID)
            return
        }

        if isCurrentTranscriptionNoteSessionActive {
            _ = captureTrailingVoxtNoteIfNeeded(finalRawText: text)
            setEnhancingState(false)
            finishSession(after: 0)
            return
        }

        VoxtLog.info("Transcription flow dispatch: standard. characters=\(text.count), enhancementMode=\(enhancementMode.rawValue)", verbose: true)
        processStandardTranscription(text, sessionID: sessionID)
    }

    func startPauseLLMIfNeeded() {
        runPauseEnhancementIfNeeded()
    }
}

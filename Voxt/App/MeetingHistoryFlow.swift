// MeetingHistoryFlow.swift
// Provides Meeting History Flow for app lifecycle and routing.

import Foundation

extension AppDelegate {
    func handleMeetingFileTaskNotificationTap(taskID rawTaskID: String) {
        guard let taskID = UUID(uuidString: rawTaskID),
              let task = meetingFileTaskQueue.task(id: taskID)
        else {
            openMainWindow(target: SettingsNavigationTarget(tab: .feature, featureTab: .files))
            return
        }

        guard let historyEntryID = task.historyEntryID,
              let entry = historyStore.entry(id: historyEntryID)
        else {
            openMainWindow(target: SettingsNavigationTarget(tab: .feature, featureTab: .files))
            showOverlayReminder(AppLocalization.localizedString("The completed meeting details are unavailable."))
            return
        }

        showMeetingDetailWindow(for: entry)
    }

    func showMeetingFileTaskDetail(taskID: UUID) {
        guard let task = meetingFileTaskQueue.task(id: taskID),
              let historyEntryID = task.historyEntryID,
              let entry = historyStore.entry(id: historyEntryID)
        else {
            showOverlayReminder(AppLocalization.localizedString("The completed meeting details are unavailable."))
            return
        }

        showMeetingDetailWindow(for: entry)
    }

    func cancelImportedMeetingFileAnalysis() async {
        await meetingSessionCoordinator.cancelImportedFileAnalysis()
    }

    func analyzeImportedMeetingFile(
        at sourceURL: URL,
        progress: @escaping @MainActor @Sendable (MeetingFileAnalysisProgress) -> Void
    ) async throws -> TranscriptionHistoryEntry {
        guard !isSessionActive, !meetingSessionCoordinator.isActive else {
            throw MeetingFileAnalysisError.sessionAlreadyActive
        }

        prepareSettingsForMeetingRuntime()
        synchronizeRuntimeASRStateForMeeting()

        let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var displayTitle = sourceURL.deletingPathExtension().lastPathComponent
        if displayTitle.count > 37, UUID(uuidString: String(displayTitle.prefix(36))) != nil {
            displayTitle = String(displayTitle.dropFirst(37))
        }
        let originalFileName = meetingFileTaskQueue.tasks.first {
            $0.stagedFileName == sourceURL.lastPathComponent
        }?.fileName
        let title = originalFileName.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? displayTitle
        var originalSegments: [TranscriptSegment]?
        let result = try await meetingSessionCoordinator.analyzeImportedFile(
            at: sourceURL,
            transcriptReady: { [self] transcript in
                originalSegments = transcript.persistedSegments
                guard persistMeetingHistory(transcript, forceSave: true, displayTitle: title) != nil else {
                    throw CocoaError(.fileWriteUnknown)
                }
            },
            progress: progress
        )
        try Task.checkCancellation()
        guard let entryID = result.recoverySessionID else { throw CocoaError(.fileWriteUnknown) }
        var audioCopyURL: URL?
        defer {
            if let audioCopyURL { try? FileManager.default.removeItem(at: audioCopyURL) }
        }
        if historyAudioStorageEnabled, historyStore.entry(id: entryID)?.audioRelativePath == nil,
           let sourceAudio = result.archivedAudioURL {
            // Stage on the archive volume, not the queue volume: the final import
            // remains a rename even when history lives on an external disk.
            let archiveRoot = try HistoryAudioStorageDirectoryManager.ensureRootDirectoryExists()
            let copyURL = try MeetingFileArchiveCopy.stagingURL(root: archiveRoot, entryID: entryID)
            try? FileManager.default.removeItem(at: copyURL)
            audioCopyURL = copyURL
            let copyTask = Task.detached(priority: .utility) {
                try MeetingFileArchiveCopy.create(from: sourceAudio, to: copyURL)
            }
            try await withTaskCancellationHandler {
                try await copyTask.value
            } onCancel: { copyTask.cancel() }
            if !historyAudioStorageEnabled {
                try? FileManager.default.removeItem(at: copyURL)
                audioCopyURL = nil
            } else if HistoryAudioStorageDirectoryManager.resolvedRootURL().standardizedFileURL != archiveRoot.standardizedFileURL {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try Task.checkCancellation()
        let entry = try historyStore.commitFileAnalysis(
            entryID: entryID, segments: result.persistedSegments, audioCopyURL: audioCopyURL,
            originalSegments: originalSegments
        )
        progress(MeetingFileAnalysisProgress(
            stage: .saving, stageFraction: 1, historyEntryID: entry.id,
            notice: result.captureFailureMessage ?? ""
        ))
        return entry
    }

    func recoverInterruptedMeetingFinalizationIfNeeded() async {
        guard let checkpoint = await MeetingFinalizationCheckpointStore.shared.load() else { return }

        let archivedAudioURL = checkpoint.archivedAudioPath.map(URL.init(fileURLWithPath:))
        let result = MeetingSessionResult(
            recoverySessionID: checkpoint.sessionID,
            captureMode: checkpoint.captureMode,
            transcriptionEngine: TranscriptionEngine(rawValue: checkpoint.transcriptionEngineRawValue) ?? .mlxAudio,
            transcriptionModelDescription: checkpoint.transcriptionModelDescription,
            segments: checkpoint.segments,
            visibleSnapshotSegments: checkpoint.visibleSnapshotSegments,
            audioDurationSeconds: checkpoint.audioDurationSeconds,
            archivedAudioURL: archivedAudioURL
        )
        VoxtLog.meeting("Recovering interrupted meeting finalization. stage=\(checkpoint.stage.rawValue), segments=\(checkpoint.segments.count)")
        guard persistMeetingHistory(result, forceSave: true) != nil else {
            VoxtLog.meetingWarning("Interrupted meeting recovery remains pending because durable history persistence failed.")
            return
        }
        if let archivedAudioURL {
            try? FileManager.default.removeItem(at: archivedAudioURL)
        }
        await MeetingFinalizationCheckpointStore.shared.clear(sessionID: checkpoint.sessionID)
        historyStore.reloadAsync()
    }

    func showMeetingDetailWindow(for entry: TranscriptionHistoryEntry) {
        meetingDetailWindowManager.presentHistoryMeeting(
            entry: entry,
            audioURL: historyStore.audioURL(for: entry),
            initialSummarySettings: currentMeetingSummarySettingsSnapshot(),
            summaryModelOptionsProvider: { @MainActor in
                self.meetingSummaryModelOptions()
            },
            summarySettingsProvider: { @MainActor in
                self.currentMeetingSummarySettingsSnapshot()
            },
            translationHandler: { @MainActor text, targetLanguage in
                self.makeMeetingTranslationOperation(text, targetLanguage: targetLanguage)
            },
            summaryStatusProvider: { @MainActor settings in
                self.meetingSummaryProviderStatus(settings: settings)
            },
            summaryGenerator: { @MainActor transcript, settings in
                try await self.generateMeetingSummary(transcript: transcript, settings: settings)
            },
            summaryPersistence: { @MainActor entryID, summary in
                self.persistMeetingSummary(summary, for: entryID)
            },
            summaryStalePersistence: { @MainActor entryID, isStale in
                self.historyStore.updateTranscriptSummaryStale(isStale, for: entryID)
            },
            summaryChatAnswerer: { @MainActor transcript, summary, history, question, settings in
                try await self.answerMeetingSummaryFollowUp(
                    transcript: transcript,
                    summary: summary,
                    history: history,
                    question: question,
                    settings: settings
                )
            },
            summaryChatPersistence: { @MainActor entryID, messages in
                self.persistMeetingSummaryChatMessages(messages, for: entryID)
            },
            transcriptSegmentsPersistence: { @MainActor entryID, segments in
                self.historyStore.updateTranscriptSegments(
                    segments,
                    for: entryID,
                    allowsEmptyText: true
                )
            }
        )
    }

    func showMeetingDetailWindow(for entryID: UUID) {
        historyStore.loadEntry(id: entryID) { [weak self] entry in
            guard let self else { return }
            guard let entry else {
                self.showOverlayReminder(AppLocalization.localizedString("The meeting details are unavailable."))
                return
            }
            self.showMeetingDetailWindow(for: entry)
        }
    }

    func persistMeetingHistoryIfNeeded(_ result: MeetingSessionResult) -> TranscriptionHistoryEntry? {
        persistMeetingHistory(result)
    }

    func handleMeetingSessionFinished(_ result: MeetingSessionResult) -> Bool {
        defer { meetingFileTaskQueue.startIfNeeded() }
        hotkeyManager.setCommonStopKeyEnabled(false)
        let disposition = pendingMeetingSessionCompletionDisposition
        pendingMeetingSessionCompletionDisposition = .save

        switch disposition {
        case .discard:
            meetingDetailWindowManager.closeLiveWindow()
            meetingOverlayWindow.hide()
            if let archivedAudioURL = result.archivedAudioURL {
                try? FileManager.default.removeItem(at: archivedAudioURL)
            }
            return true
        case .save:
            meetingDetailWindowManager.closeLiveWindow()
            meetingOverlayWindow.hide()
            guard historyEnabled else {
                if let archivedAudioURL = result.archivedAudioURL {
                    try? FileManager.default.removeItem(at: archivedAudioURL)
                }
                return true
            }
            guard persistMeetingHistoryIfNeeded(result) != nil else {
                showOverlayReminder(
                    result.captureFailureMessage
                        ?? AppLocalization.localizedString("Couldn't save Meeting Notes history.")
                )
                return false
            }
            if let captureFailureMessage = result.captureFailureMessage {
                showOverlayReminder(captureFailureMessage)
            }
            if let archivedAudioURL = result.archivedAudioURL {
                try? FileManager.default.removeItem(at: archivedAudioURL)
            }
            return true
        case .saveAndOpenDetail:
            guard let entry = persistMeetingHistory(result, forceSave: true) else {
                VoxtLog.meetingWarning("Meeting save-and-open failed: no history entry could be created.")
                meetingDetailWindowManager.closeLiveWindow()
                meetingOverlayWindow.hide()
                showOverlayReminder(
                    result.captureFailureMessage
                        ?? AppLocalization.localizedString("Couldn't save Meeting Notes history.")
                )
                return false
            }
            if let archivedAudioURL = result.archivedAudioURL {
                try? FileManager.default.removeItem(at: archivedAudioURL)
            }
            VoxtLog.meeting("Meeting history saved. entryID=\(entry.id.uuidString), kind=\(entry.kind.rawValue)")
            meetingDetailWindowManager.closeLiveWindow()
            meetingOverlayWindow.hide { [weak self] in
                guard let appDelegate = self else { return }
                appDelegate.historyStore.reloadAsync()
                appDelegate.showMeetingDetailWindow(for: entry)
            }
            return true
        }
    }

    func persistMeetingHistory(
        _ result: MeetingSessionResult,
        forceSave: Bool = false,
        displayTitle: String? = nil
    ) -> TranscriptionHistoryEntry? {
        guard forceSave || historyEnabled else {
            VoxtLog.meeting("Meeting history persistence skipped: history is disabled.")
            return nil
        }
        if let recoverySessionID = result.recoverySessionID,
           let existingEntry = historyStore.entry(id: recoverySessionID) {
            return existingEntry
        }

        let persistedSegments = result.persistedSegments
        let persistedText = MeetingTranscriptFormatter.joinedText(for: persistedSegments)
        let hasMeaningfulText = !persistedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let archivedAudioExists = result.archivedAudioURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let storesAudioForMode = historyAudioStorageEnabled || result.captureMode == .recording
        let allowsAudioOnlyHistory = storesAudioForMode && archivedAudioExists
        guard hasMeaningfulText || allowsAudioOnlyHistory else {
            VoxtLog.meetingWarning(
                "Meeting history persistence skipped: neither meaningful transcript text nor a persistable audio asset was available."
            )
            return nil
        }

        let audioRelativePath: String?
        if storesAudioForMode, let archivedAudioURL = result.archivedAudioURL, archivedAudioExists {
            do {
                audioRelativePath = try historyStore.importAudioArchive(from: archivedAudioURL, kind: .transcript)
            } catch {
                VoxtLog.meetingWarning("Meeting audio persistence failed. error=\(error.localizedDescription)")
                return nil
            }
        } else {
            audioRelativePath = nil
        }

        guard let entryID = historyStore.append(
            entryID: result.recoverySessionID ?? UUID(),
            text: persistedText,
            transcriptionEngine: result.transcriptionEngine.title,
            transcriptionModel: result.transcriptionModelDescription,
            enhancementMode: EnhancementMode.off.title,
            enhancementModel: "None",
            kind: .transcript,
            isTranslation: false,
            audioDurationSeconds: result.audioDurationSeconds,
            transcriptionProcessingDurationSeconds: nil,
            llmDurationSeconds: nil,
            focusedAppName: nil,
            focusedAppBundleID: nil,
            matchedGroupID: nil,
            matchedGroupName: nil,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil,
            remoteASRProvider: nil,
            remoteASRModel: nil,
            remoteASREndpoint: nil,
            remoteLLMProvider: nil,
            remoteLLMModel: nil,
            remoteLLMEndpoint: nil,
            audioRelativePath: audioRelativePath,
            whisperWordTimings: nil,
            transcriptSegments: persistedSegments,
            transcriptAudioRelativePath: audioRelativePath,
            meetingCaptureMode: result.captureMode,
            displayTitle: displayTitle ?? (hasMeaningfulText ? nil : result.captureMode.title),
            dictionaryHitTerms: [],
            dictionaryCorrectedTerms: [],
            dictionarySuggestedTerms: [],
            allowEmptyTextWithAudio: !hasMeaningfulText
        ) else {
            if let audioRelativePath {
                historyStore.removeImportedAudioArchive(relativePath: audioRelativePath)
            }
            VoxtLog.meetingWarning("Meeting history persistence failed: history store rejected the meeting entry.")
            return nil
        }

        VoxtLog.meeting(
            "Meeting history persistence succeeded. entryID=\(entryID.uuidString), segments=\(persistedSegments.count), forceSave=\(forceSave)"
        )
        if hasMeaningfulText {
            cacheLatestInjectableOutputText(persistedText)
        }
        return historyStore.entry(id: entryID)
    }

    func meetingExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Voxt-Meeting-\(formatter.string(from: Date())).txt"
    }

    func resolvedMeetingRealtimeTranslationTargetLanguage() -> TranslationTargetLanguage? {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.meetingRealtimeTranslateEnabled) else {
            return nil
        }
        guard let rawValue = UserDefaults.standard.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage),
              !rawValue.isEmpty
        else {
            return .english
        }
        return TranslationTargetLanguage(rawValue: rawValue)
    }
}

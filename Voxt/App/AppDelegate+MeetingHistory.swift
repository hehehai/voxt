import Foundation
import AppKit

extension AppDelegate {
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
                try await self.translateMeetingRealtimeText(text, targetLanguage: targetLanguage)
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
            }
        )
    }

    func persistMeetingHistoryIfNeeded(_ result: MeetingSessionResult) {
        _ = persistMeetingHistory(result)
    }

    func handleMeetingSessionFinished(_ result: MeetingSessionResult) {
        let disposition = pendingMeetingSessionCompletionDisposition
        pendingMeetingSessionCompletionDisposition = .save

        switch disposition {
        case .discard:
            meetingDetailWindowManager.closeLiveWindow()
            meetingOverlayWindow.hide()
            if let archivedAudioURL = result.archivedAudioURL {
                try? FileManager.default.removeItem(at: archivedAudioURL)
            }
        case .save:
            meetingDetailWindowManager.closeLiveWindow()
            meetingOverlayWindow.hide()
            defer {
                if let archivedAudioURL = result.archivedAudioURL {
                    try? FileManager.default.removeItem(at: archivedAudioURL)
                }
            }
            persistMeetingHistoryIfNeeded(result)
        case .saveAndOpenDetail:
            defer {
                if let archivedAudioURL = result.archivedAudioURL {
                    try? FileManager.default.removeItem(at: archivedAudioURL)
                }
            }
            guard let entry = persistMeetingHistory(result, forceSave: true) else {
                VoxtLog.warning("Meeting save-and-open failed: no history entry could be created.")
                meetingDetailWindowManager.closeLiveWindow()
                meetingOverlayWindow.hide()
                showOverlayReminder(String(localized: "Couldn't save Meeting Notes history."))
                return
            }
            VoxtLog.info("Meeting history saved. entryID=\(entry.id.uuidString), kind=\(entry.kind.rawValue)")
            meetingDetailWindowManager.closeLiveWindow()
            meetingOverlayWindow.hide { [weak self] in
                guard let appDelegate = self else { return }
                appDelegate.historyStore.reload()
                appDelegate.showMeetingDetailWindow(for: entry)
            }
        }
    }

    func persistMeetingHistory(_ result: MeetingSessionResult, forceSave: Bool = false) -> TranscriptionHistoryEntry? {
        guard forceSave || historyEnabled else {
            VoxtLog.info("Meeting history persistence skipped: history is disabled.")
            return nil
        }

        let persistedSegments = result.persistedSegments
        guard !persistedSegments.isEmpty else {
            VoxtLog.warning("Meeting history persistence skipped: no meaningful meeting segments were available.")
            return nil
        }

        let persistedText = MeetingTranscriptFormatter.joinedText(for: persistedSegments)
        guard !persistedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            VoxtLog.warning("Meeting history persistence skipped: merged meeting text was empty after formatting.")
            return nil
        }

        let audioRelativePath: String?
        if historyAudioStorageEnabled, let archivedAudioURL = result.archivedAudioURL {
            audioRelativePath = try? historyStore.importAudioArchive(from: archivedAudioURL, kind: .transcript)
        } else {
            if let archivedAudioURL = result.archivedAudioURL,
               FileManager.default.fileExists(atPath: archivedAudioURL.path) {
                try? FileManager.default.removeItem(at: archivedAudioURL)
            }
            audioRelativePath = nil
        }

        guard let entryID = historyStore.append(
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
            focusedAppName: NSWorkspace.shared.frontmostApplication?.localizedName,
            focusedAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
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
            dictionaryHitTerms: [],
            dictionaryCorrectedTerms: [],
            dictionarySuggestedTerms: []
        ) else {
            VoxtLog.warning("Meeting history persistence failed: history store rejected the meeting entry.")
            return nil
        }

        VoxtLog.info(
            "Meeting history persistence succeeded. entryID=\(entryID.uuidString), segments=\(persistedSegments.count), forceSave=\(forceSave)"
        )
        cacheLatestInjectableOutputText(persistedText)
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

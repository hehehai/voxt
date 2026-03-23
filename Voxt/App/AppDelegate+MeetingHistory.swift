import Foundation
import AppKit

extension AppDelegate {
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
            let audioURL = historyStore.meetingAudioURL(for: entry)
            meetingOverlayWindow.hide { [weak self] in
                self?.historyStore.reload()
                self?.meetingDetailWindowManager.presentHistoryMeeting(
                    entry: entry,
                    audioURL: audioURL,
                    translationHandler: { @MainActor [weak self] text, targetLanguage in
                        guard let self else { return text }
                        return try await self.translateMeetingRealtimeText(text, targetLanguage: targetLanguage)
                    }
                )
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

        let meetingAudioRelativePath: String?
        if let archivedAudioURL = result.archivedAudioURL {
            meetingAudioRelativePath = try? historyStore.importMeetingAudioArchive(from: archivedAudioURL)
        } else {
            meetingAudioRelativePath = nil
        }

        guard let entryID = historyStore.append(
            text: persistedText,
            transcriptionEngine: result.transcriptionEngine.title,
            transcriptionModel: result.transcriptionModelDescription,
            enhancementMode: EnhancementMode.off.title,
            enhancementModel: "None",
            kind: .meeting,
            isTranslation: false,
            audioDurationSeconds: result.audioDurationSeconds,
            transcriptionProcessingDurationSeconds: nil,
            llmDurationSeconds: nil,
            focusedAppName: NSWorkspace.shared.frontmostApplication?.localizedName,
            matchedGroupID: nil,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil,
            remoteASRProvider: nil,
            remoteASRModel: nil,
            remoteASREndpoint: nil,
            remoteLLMProvider: nil,
            remoteLLMModel: nil,
            remoteLLMEndpoint: nil,
            whisperWordTimings: nil,
            meetingSegments: persistedSegments,
            meetingAudioRelativePath: meetingAudioRelativePath,
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
        return historyStore.entry(id: entryID)
    }

    func meetingExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Voxt-Meeting-\(formatter.string(from: Date())).txt"
    }

    func resolvedMeetingRealtimeTranslationTargetLanguage() -> TranslationTargetLanguage? {
        guard let rawValue = UserDefaults.standard.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage),
              !rawValue.isEmpty
        else {
            return nil
        }
        return TranslationTargetLanguage(rawValue: rawValue)
    }
}

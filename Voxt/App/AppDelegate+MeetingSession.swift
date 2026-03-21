import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers

extension AppDelegate {
    func handleMeetingHotkeyDown() {
        VoxtLog.hotkey(
            "Hotkey callback meetingDown. betaEnabled=\(meetingNotesBetaEnabled), isMeetingActive=\(meetingSessionCoordinator.isActive), isSessionActive=\(isSessionActive)"
        )

        guard meetingNotesBetaEnabled else {
            VoxtLog.hotkey("Meeting hotkey ignored: beta feature is disabled.")
            return
        }

        cancelPendingTranscriptionStart()

        if meetingSessionCoordinator.isActive {
            stopMeetingSession()
            return
        }

        guard !isSessionActive else {
            showOverlayStatus(
                String(localized: "Finish the current recording before starting Meeting Notes."),
                clearAfter: 2.2
            )
            return
        }

        Task { @MainActor [weak self] in
            await self?.startMeetingSession()
        }
    }

    func stopMeetingSession(
        closeOverlayImmediately: Bool = true,
        closeLiveDetailImmediately: Bool = true
    ) {
        guard meetingSessionCoordinator.isActive else {
            if closeOverlayImmediately {
                meetingOverlayWindow.hide()
            }
            return
        }
        meetingSessionCoordinator.overlayState.isCloseConfirmationPresented = false
        meetingSessionCoordinator.overlayState.isRealtimeTranslationLanguagePickerPresented = false
        if closeLiveDetailImmediately {
            meetingDetailWindowManager.closeLiveWindow()
        }
        if closeOverlayImmediately {
            meetingOverlayWindow.hide()
        }
        meetingSessionCoordinator.stop()
    }

    func requestMeetingSessionCloseConfirmation() {
        guard meetingSessionCoordinator.isActive else { return }
        meetingSessionCoordinator.overlayState.isRealtimeTranslationLanguagePickerPresented = false
        meetingSessionCoordinator.overlayState.isCloseConfirmationPresented = true
    }

    func dismissMeetingSessionCloseConfirmation() {
        guard meetingSessionCoordinator.isActive else { return }
        meetingSessionCoordinator.overlayState.isCloseConfirmationPresented = false
    }

    func cancelMeetingSessionWithoutSaving() {
        guard meetingSessionCoordinator.isActive else {
            meetingOverlayWindow.hide()
            return
        }
        pendingMeetingSessionCompletionDisposition = .discard
        stopMeetingSession()
    }

    func finishMeetingSessionAndOpenDetail() {
        guard meetingSessionCoordinator.isActive else { return }
        pendingMeetingSessionCompletionDisposition = .saveAndOpenDetail
        stopMeetingSession(closeOverlayImmediately: true, closeLiveDetailImmediately: false)
    }

    func toggleMeetingOverlayCollapse() {
        meetingSessionCoordinator.setCollapsed(!meetingSessionCoordinator.overlayState.isCollapsed)
    }

    func toggleMeetingPause() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.meetingSessionCoordinator.overlayState.isPaused {
                if let failureMessage = await self.meetingSessionCoordinator.resume() {
                    VoxtLog.warning("Meeting resume failed: \(failureMessage)")
                    self.showOverlayReminder(failureMessage)
                }
            } else {
                await self.meetingSessionCoordinator.pause()
            }
        }
    }

    func exportMeetingTranscript() {
        guard meetingSessionCoordinator.canExport else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = meetingExportFilename()
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try meetingSessionCoordinator.exportText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showOverlayReminder(AppLocalization.format("Export failed: %@", error.localizedDescription))
        }
    }

    func copyMeetingSegment(_ segment: MeetingTranscriptSegment) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(MeetingTranscriptFormatter.copyString(for: segment), forType: .string)
    }

    func showLiveMeetingDetailWindow() {
        guard meetingSessionCoordinator.isActive else { return }
        meetingDetailWindowManager.presentLiveMeeting(
            state: meetingSessionCoordinator.overlayState,
            onExport: { [weak self] in
                self?.exportMeetingTranscript()
            }
        )
    }

    func handleMeetingRealtimeTranslationToggle(_ isEnabled: Bool) {
        guard isEnabled else {
            meetingSessionCoordinator.overlayState.isRealtimeTranslationLanguagePickerPresented = false
            meetingSessionCoordinator.setRealtimeTranslateEnabled(false)
            return
        }

        if let targetLanguage = resolvedMeetingRealtimeTranslationTargetLanguage() {
            UserDefaults.standard.set(
                targetLanguage.rawValue,
                forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage
            )
            meetingSessionCoordinator.setRealtimeTranslateEnabled(true)
            return
        }

        meetingSessionCoordinator.overlayState.realtimeTranslationDraftLanguageRaw =
            (resolvedMeetingRealtimeTranslationTargetLanguage() ?? .english).rawValue
        meetingSessionCoordinator.overlayState.isRealtimeTranslationLanguagePickerPresented = true
        meetingSessionCoordinator.setRealtimeTranslateEnabled(false)
    }

    func confirmMeetingRealtimeTranslationLanguageSelection() {
        let rawValue = meetingSessionCoordinator.overlayState.realtimeTranslationDraftLanguageRaw
        guard let language = TranslationTargetLanguage(rawValue: rawValue) else {
            cancelMeetingRealtimeTranslationLanguageSelection()
            return
        }

        UserDefaults.standard.set(
            language.rawValue,
            forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage
        )
        meetingSessionCoordinator.overlayState.isRealtimeTranslationLanguagePickerPresented = false
        meetingSessionCoordinator.setRealtimeTranslateEnabled(true)
    }

    func cancelMeetingRealtimeTranslationLanguageSelection() {
        meetingSessionCoordinator.overlayState.isRealtimeTranslationLanguagePickerPresented = false
        meetingSessionCoordinator.setRealtimeTranslateEnabled(false)
    }

    private func startMeetingSession() async {
        guard preflightPermissionsForMeeting() else { return }
        pendingMeetingSessionCompletionDisposition = .save

        meetingSessionCoordinator.onSessionFinished = { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handleMeetingSessionFinished(result)
            }
        }

        if let failureMessage = await meetingSessionCoordinator.start() {
            VoxtLog.warning("Meeting start failed: \(failureMessage)")
            showOverlayReminder(failureMessage)
            return
        }

        meetingOverlayWindow.show(
            state: meetingSessionCoordinator.overlayState,
            position: overlayPosition
        )
    }

    private func preflightPermissionsForMeeting() -> Bool {
        guard meetingNotesBetaEnabled else { return false }

        if isSessionActive {
            showOverlayStatus(
                String(localized: "Finish the current recording before starting Meeting Notes."),
                clearAfter: 2.2
            )
            return false
        }

        guard isWhisperReady else {
            showOverlayReminder(
                String(localized: "Whisper model is required for Meeting Notes. Install a Whisper model first.")
            )
            return false
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            showOverlayReminder(
                String(localized: "Microphone permission is required. Enable it in Settings > Permissions.")
            )
            return false
        }

        if SystemAudioCapturePermission.authorizationStatus() != .authorized {
            showOverlayReminder(
                String(localized: "System Audio Recording permission is required for Meeting Notes. Enable it in Settings > Permissions.")
            )
            return false
        }

        if !AccessibilityPermissionManager.isTrusted() {
            showOverlayStatus(
                String(localized: "Please enable required permissions in Settings > Permissions."),
                clearAfter: 2.2
            )
        }

        return true
    }

    private func persistMeetingHistoryIfNeeded(_ result: MeetingSessionResult) {
        _ = persistMeetingHistory(result)
    }

    private func handleMeetingSessionFinished(_ result: MeetingSessionResult) {
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
                    audioURL: audioURL
                )
            }
        }
    }

    private func persistMeetingHistory(_ result: MeetingSessionResult, forceSave: Bool = false) -> TranscriptionHistoryEntry? {
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

        let modelID = whisperModelManager.currentModelID
        let transcriptionModel = "\(whisperModelManager.displayTitle(for: modelID)) (\(modelID))"
        let meetingAudioRelativePath: String?
        if let archivedAudioURL = result.archivedAudioURL {
            meetingAudioRelativePath = try? historyStore.importMeetingAudioArchive(from: archivedAudioURL)
        } else {
            meetingAudioRelativePath = nil
        }

        guard let entryID = historyStore.append(
            text: persistedText,
            transcriptionEngine: AppLocalization.localizedString("Whisper"),
            transcriptionModel: transcriptionModel,
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

    private func meetingExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Voxt-Meeting-\(formatter.string(from: Date())).txt"
    }

    private func resolvedMeetingRealtimeTranslationTargetLanguage() -> TranslationTargetLanguage? {
        guard let rawValue = UserDefaults.standard.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage),
              !rawValue.isEmpty
        else {
            return nil
        }
        return TranslationTargetLanguage(rawValue: rawValue)
    }

}

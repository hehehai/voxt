import Foundation
import AppKit
import AVFoundation

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
            if meetingSessionCoordinator.overlayState.isCloseConfirmationPresented {
                dismissMeetingSessionCloseConfirmation()
            } else {
                requestMeetingSessionCloseConfirmation()
            }
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
        pendingMeetingStartupTask?.cancel()
        pendingMeetingStartupTask = nil

        if meetingSessionCoordinator.isStartingUp &&
            !meetingSessionCoordinator.overlayState.isRecording &&
            !meetingSessionCoordinator.overlayState.isPaused {
            meetingSessionCoordinator.overlayState.isCloseConfirmationPresented = false
            meetingSessionCoordinator.overlayState.isRealtimeTranslationLanguagePickerPresented = false
            if closeLiveDetailImmediately {
                meetingDetailWindowManager.closeLiveWindow()
            }
            meetingSessionCoordinator.cancelPendingStart()
            if closeOverlayImmediately {
                meetingOverlayWindow.hide()
            }
            return
        }

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
        if meetingSessionCoordinator.overlayState.segments.isEmpty {
            cancelMeetingSessionWithoutSaving()
            return
        }
        if meetingSessionCoordinator.overlayState.isCollapsed {
            meetingSessionCoordinator.setCollapsed(false)
        }
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

        do {
            try MeetingTranscriptExporter.export(
                segments: meetingSessionCoordinator.overlayState.segments,
                defaultFilename: meetingExportFilename()
            )
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
            translationHandler: { @MainActor [weak self] text, targetLanguage in
                guard let self else { return text }
                return try await self.translateMeetingRealtimeText(text, targetLanguage: targetLanguage)
            }
        )
    }

    func handleMeetingRealtimeTranslationToggle(_ isEnabled: Bool) {
        guard isEnabled else {
            meetingSessionCoordinator.overlayState.isRealtimeTranslationLanguagePickerPresented = false
            meetingSessionCoordinator.setRealtimeTranslateEnabled(false)
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

        meetingSessionCoordinator.prepareForStart()
        meetingOverlayWindow.show(
            state: meetingSessionCoordinator.overlayState,
            position: overlayPosition
        )

        pendingMeetingStartupTask?.cancel()
        pendingMeetingStartupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.pendingMeetingStartupTask?.isCancelled != false {
                    self.pendingMeetingStartupTask = nil
                }
            }
            let failureMessage = await self.meetingSessionCoordinator.start()
            guard !Task.isCancelled else {
                self.pendingMeetingStartupTask = nil
                return
            }
            self.pendingMeetingStartupTask = nil
            if let failureMessage {
                VoxtLog.warning("Meeting start failed: \(failureMessage)")
                self.meetingOverlayWindow.hide()
                self.showOverlayReminder(failureMessage)
            }
        }
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

        let remoteConfiguration = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: remoteASRSelectedProvider,
            stored: remoteASRConfigurations
        )
        let startDecision = MeetingStartPlanner.resolve(
            selectedEngine: transcriptionEngine,
            mlxModelState: mlxModelManager.state,
            whisperModelState: whisperModelManager.state,
            remoteASRProvider: remoteASRSelectedProvider,
            remoteASRConfiguration: remoteConfiguration
        )
        guard case .start = startDecision else {
            if case .blocked(let reason) = startDecision {
                VoxtLog.warning("Meeting start blocked: \(reason.logDescription)")
                showOverlayReminder(reason.userMessage)
            }
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

}

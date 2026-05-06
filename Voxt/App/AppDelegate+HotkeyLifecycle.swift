import AppKit
import Carbon

@MainActor
extension AppDelegate {
    func setupHotkey() {
        // Callback contract:
        // - HotkeyManager only emits normalized events (transcriptionDown/up, translationDown/up, rewriteDown/up).
        // - AppDelegate owns business decisions (start/stop session, selected-text fast path, mode rules).
        hotkeyManager.onKeyDown = { [weak self] in
            guard let self else { return }
            self.handleTranscriptionHotkeyDown()
        }
        hotkeyManager.onKeyUp = { [weak self] in
            guard let self else { return }
            self.handleTranscriptionHotkeyUp()
        }
        hotkeyManager.onTranslationKeyDown = { [weak self] in
            guard let self else { return }
            self.handleTranslationHotkeyDown()
        }
        hotkeyManager.onTranslationKeyUp = { [weak self] in
            guard let self else { return }
            self.handleTranslationHotkeyUp()
        }
        hotkeyManager.onRewriteKeyDown = { [weak self] in
            guard let self else { return }
            self.handleRewriteHotkeyDown()
        }
        hotkeyManager.onRewriteKeyUp = { [weak self] in
            guard let self else { return }
            self.handleRewriteHotkeyUp()
        }
        hotkeyManager.onMeetingKeyDown = { [weak self] in
            guard let self else { return }
            self.handleMeetingHotkeyDown()
        }
        hotkeyManager.onCustomPasteKeyDown = { [weak self] in
            guard let self else { return }
            self.handleCustomPasteHotkeyDown()
        }
        hotkeyManager.onEscapeKeyDown = { [weak self] in
            self?.handleEscapeShortcut() ?? false
        }
        hotkeyManager.start()
        VoxtLog.hotkey("Hotkey callbacks configured.")
    }

    func setupLifecycleRecoveryObservers() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        workspaceWillSleepObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHotkeyTransientStateReset(reason: "workspaceWillSleep")
            }
        }

        workspaceDidWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHotkeyTransientStateReset(reason: "workspaceDidWake")
            }
        }

        workspaceSessionDidBecomeActiveObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHotkeyTransientStateReset(reason: "workspaceSessionDidBecomeActive")
            }
        }

        workspaceSessionDidResignActiveObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHotkeyTransientStateReset(reason: "workspaceSessionDidResignActive")
            }
        }
    }

    func scheduleHotkeyTransientStateReset(reason: String) {
        Task { @MainActor [weak self] in
            self?.hotkeyManager.resetTransientState(reason: reason)
        }
    }

    func setupEscapeKeyMonitoring() {
        globalEscapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.handleOverlayShortcutEvent(event)
            }
        }
        localEscapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleOverlayShortcutEvent(event, shouldConsume: true) ?? event
        }
    }

    func handleOverlayShortcutEvent(_ event: NSEvent, shouldConsume: Bool = false) -> NSEvent? {
        if shouldHandleAnswerOverlayContinueShortcut(event),
           overlayWindow.handleAnswerSpaceShortcut() {
            return shouldConsume ? nil : event
        }

        if shouldHandleLiveTranscriptNoteShortcut(event),
           captureLiveTranscriptNoteIfPossible(reason: "note-shortcut") {
            return shouldConsume ? nil : event
        }

        guard event.keyCode == UInt16(kVK_Escape) else { return event }
        guard handleEscapeShortcut() else { return event }
        return shouldConsume ? nil : event
    }

    func handleEscapeShortcut() -> Bool {
        guard UserDefaults.standard.object(forKey: AppPreferenceKey.escapeKeyCancelsOverlaySession) as? Bool ?? true else {
            return false
        }
        if overlayState.displayMode == .answer {
            dismissAnswerOverlay()
            return true
        }
        if meetingSessionCoordinator.isActive {
            if meetingSessionCoordinator.overlayState.isCloseConfirmationPresented {
                dismissMeetingSessionCloseConfirmation()
            } else {
                requestMeetingSessionCloseConfirmation()
            }
            return true
        }
        guard HotkeyPreference.loadTriggerMode() == .tap else { return false }
        guard isSessionActive else { return false }
        guard !isSelectedTextTranslationFlow else { return false }
        cancelActiveRecordingSession()
        return true
    }

    func shouldHandleAnswerOverlayContinueShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard !event.isARepeat else { return false }
        let shortcut = rewriteContinueShortcutSettings.hotkey
        guard event.keyCode == shortcut.keyCode else { return false }
        let modifiers = event.modifierFlags.intersection(.hotkeyRelevant)
        guard modifiers == shortcut.modifiers else { return false }
        return overlayState.answerSpaceShortcutAction != nil
    }

    func shouldIgnoreTapStop() -> Bool {
        guard let startedAt = recordingStartedAt else { return false }
        let elapsed = Date().timeIntervalSince(startedAt)
        return elapsed < tapStopGuardInterval
    }

    var isSessionStopInProgress: Bool {
        isSessionActive && recordingStoppedAt != nil
    }

    func handleTranscriptionTapDown() {
        if meetingSessionCoordinator.isActive {
            if meetingSessionCoordinator.overlayState.isCloseConfirmationPresented {
                dismissMeetingSessionCloseConfirmation()
            } else {
                requestMeetingSessionCloseConfirmation()
            }
            return
        }
        if isSessionActive {
            guard !shouldIgnoreTapStop() else { return }
            endRecording()
            return
        }
        beginRecording(outputMode: .transcription)
    }

    func handleTranslationTapDown() {
        if isSessionActive {
            guard sessionOutputMode == .translation else {
                VoxtLog.info("Tap translation down ignored: active session belongs to transcription.", verbose: true)
                return
            }
            guard !shouldIgnoreTapStop() else { return }
            endRecording()
            return
        }
        beginRecording(outputMode: .translation)
    }

    func handleTranscriptionHotkeyDown() {
        if meetingSessionCoordinator.isActive {
            if meetingSessionCoordinator.overlayState.isCloseConfirmationPresented {
                dismissMeetingSessionCloseConfirmation()
            } else {
                requestMeetingSessionCloseConfirmation()
            }
            return
        }
        let triggerMode = HotkeyPreference.loadTriggerMode()
        VoxtLog.hotkey(
            "Hotkey callback transcriptionDown. mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )
        let actions = HotkeyActionResolver.resolveTranscriptionDown(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop() && !isSessionStopInProgress
            )
        )
        for action in actions {
            performHotkeyAction(action)
        }
    }

    func handleTranscriptionHotkeyUp() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        guard triggerMode == .longPress else { return }
        VoxtLog.hotkey(
            "Hotkey callback transcriptionUp. isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )
        let actions = HotkeyActionResolver.resolveTranscriptionUp(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop() && !isSessionStopInProgress
            )
        )
        for action in actions {
            performHotkeyAction(action)
        }
    }

    func handleTranslationHotkeyDown() {
        VoxtLog.info(
            "Translation hotkey invoked. mode=\(HotkeyPreference.loadTriggerMode().rawValue), isSessionActive=\(isSessionActive), isMeetingActive=\(meetingSessionCoordinator.isActive), pendingStart=\(pendingTranscriptionStartTask != nil)"
        )
        let triggerMode = HotkeyPreference.loadTriggerMode()
        VoxtLog.hotkey(
            "Hotkey callback translationDown. mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )
        let actions = HotkeyActionResolver.resolveTranslationDown(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop() && !isSessionStopInProgress
            )
        )
        for action in actions where action == .cancelPendingTranscriptionStart {
            performHotkeyAction(action)
        }
        guard !meetingSessionCoordinator.isActive else {
            VoxtLog.info("Translation hotkey blocked because Meeting Notes is active.")
            showOverlayStatus(
                String(localized: "Meeting Notes is currently active. Close it before starting another recording."),
                clearAfter: 2.2
            )
            return
        }
        guard !isSessionActive else {
            VoxtLog.info("Translation hotkey ignored because a session is already active.")
            VoxtLog.hotkey("Translation down ignored: session already active.")
            return
        }

        if beginSelectedTextTranslationIfPossible() {
            VoxtLog.hotkey("Translation down handled by selected-text translation flow.")
            return
        }

        VoxtLog.info("Translation hotkey dispatching microphone translation start.")
        for action in actions {
            guard action != .cancelPendingTranscriptionStart else { continue }
            performHotkeyAction(action)
        }
    }

    func handleTranslationHotkeyUp() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        guard triggerMode == .longPress else { return }
        VoxtLog.hotkey(
            "Hotkey callback translationUp. isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), selectedTextFlow=\(isSelectedTextTranslationFlow)",
        )
        let actions = HotkeyActionResolver.resolveTranslationUp(
            state: HotkeyActionResolver.State(
                triggerMode: triggerMode,
                isSessionActive: isSessionActive,
                sessionOutputMode: sessionOutputMode,
                hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil,
                isSelectedTextTranslationFlow: isSelectedTextTranslationFlow,
                canStopTapSession: !shouldIgnoreTapStop() && !isSessionStopInProgress
            )
        )
        for action in actions {
            performHotkeyAction(action)
        }
    }

    func handleRewriteHotkeyDown() {
        VoxtLog.info(
            "Rewrite hotkey invoked. mode=\(HotkeyPreference.loadTriggerMode().rawValue), isSessionActive=\(isSessionActive), isMeetingActive=\(meetingSessionCoordinator.isActive), pendingStart=\(pendingTranscriptionStartTask != nil)"
        )
        let triggerMode = HotkeyPreference.loadTriggerMode()
        VoxtLog.hotkey(
            "Hotkey callback rewriteDown. mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputModeLabel), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )

        cancelPendingTranscriptionStart()
        if isSessionActive {
            if sessionOutputMode == .transcription && shouldIgnoreTapStop() {
                VoxtLog.hotkey("Rewrite down reinterpreting freshly started transcription session as rewrite.")
                cancelActiveRecordingSession()
                beginRecording(outputMode: .rewrite)
                return
            }

            VoxtLog.info("Rewrite hotkey ignored because a session is already active.")
            VoxtLog.hotkey("Rewrite down ignored: session already active.")
            return
        }

        VoxtLog.info("Rewrite hotkey dispatching rewrite recording start.")
        beginRecording(outputMode: .rewrite)
    }

    func handleRewriteHotkeyUp() {
        let triggerMode = HotkeyPreference.loadTriggerMode()
        guard triggerMode == .longPress else { return }
        VoxtLog.hotkey(
            "Hotkey callback rewriteUp. isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputModeLabel)",
        )
        guard isSessionActive, sessionOutputMode == .rewrite else { return }
        endRecording()
    }

    func handleCustomPasteHotkeyDown() {
        guard customPasteHotkeyEnabled else { return }
        injectLatestResultByCustomPasteHotkey()
    }

    func performHotkeyAction(_ action: HotkeyActionResolver.Action) {
        switch action {
        case .ignore:
            return
        case .stopRecording:
            endRecording()
        case .startTranscription:
            beginRecording(outputMode: .transcription)
        case .startTranslation:
            beginRecording(outputMode: .translation)
        case .scheduleTranscriptionStart:
            schedulePendingTranscriptionStart()
        case .cancelPendingTranscriptionStart:
            cancelPendingTranscriptionStart()
        }
    }

    func schedulePendingTranscriptionStart() {
        VoxtLog.hotkey("Scheduling pending transcription start. delaySec=\(transcriptionStartDebounceInterval)")
        pendingTranscriptionStartTask?.cancel()
        pendingTranscriptionStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(self.transcriptionStartDebounceInterval))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard !self.isSessionActive else {
                VoxtLog.hotkey("Pending transcription start dropped: session already active.")
                self.pendingTranscriptionStartTask = nil
                return
            }
            self.pendingTranscriptionStartTask = nil
            VoxtLog.hotkey("Pending transcription start fired.")
            self.beginRecording(outputMode: .transcription)
        }
    }

    func cancelPendingTranscriptionStart() {
        if pendingTranscriptionStartTask != nil {
            VoxtLog.hotkey("Canceled pending transcription start.")
        }
        pendingTranscriptionStartTask?.cancel()
        pendingTranscriptionStartTask = nil
    }

    func shouldHandleCallbacks(for sessionID: UUID) -> Bool {
        guard sessionID == activeRecordingSessionID else {
            VoxtLog.info("Ignoring stale session callback. sessionID=\(sessionID.uuidString)", verbose: true)
            return false
        }
        guard !isSessionCancellationRequested else {
            VoxtLog.info("Ignoring callback for cancelled session. sessionID=\(sessionID.uuidString)", verbose: true)
            return false
        }
        return true
    }

    var sessionOutputModeLabel: String {
        switch sessionOutputMode {
        case .transcription:
            return "transcription"
        case .translation:
            return "translation"
        case .rewrite:
            return "rewrite"
        }
    }
}

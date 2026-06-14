import AppKit
import Carbon

@MainActor
extension AppDelegate {
    enum SessionCallbackHandlingDecision: Equatable {
        case accept
        case rejectStale
        case rejectCancelled

        var logDescription: String {
            switch self {
            case .accept:
                return "accept"
            case .rejectStale:
                return "stale-session"
            case .rejectCancelled:
                return "cancelled-session"
            }
        }
    }

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
        guard !blockNonMeetingRecordingWhileMeetingIsActive(source: "transcriptionTap") else { return }
        if isSessionActive {
            guard !shouldIgnoreTapStop() else { return }
            endRecording()
            return
        }
        beginRecording(outputMode: .transcription)
    }

    func handleTranslationTapDown() {
        guard !blockNonMeetingRecordingWhileMeetingIsActive(source: "translationTap") else { return }
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
        handleTranscriptionTriggerDown(
            triggerMode: HotkeyPreference.loadTriggerMode(),
            allowsDoubleTapRewrite: true,
            source: "hotkey"
        )
    }

    private func handleTranscriptionTriggerDown(
        triggerMode: HotkeyPreference.TriggerMode,
        allowsDoubleTapRewrite: Bool,
        source: String,
        pendingStartDelay: TimeInterval? = nil,
        pendingStartShouldStart: (() -> Bool)? = nil
    ) {
        VoxtLog.hotkey(
            "Trigger callback transcriptionDown. source=\(source), mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )
        guard !blockNonMeetingRecordingWhileMeetingIsActive(source: "\(source)TranscriptionDown") else { return }
        if allowsDoubleTapRewrite {
            let doubleTapRewriteAction = TranscriptionDoubleTapRewriteResolver.resolve(
                state: TranscriptionDoubleTapRewriteResolver.State(
                    triggerMode: triggerMode,
                    rewriteActivationMode: HotkeyPreference.loadRewriteActivationMode(),
                    isSessionActive: isSessionActive,
                    hasPendingTranscriptionStart: pendingTranscriptionStartTask != nil
                )
            )
            switch doubleTapRewriteAction {
            case .useStandardHandling:
                break
            case .scheduleDelayedTranscriptionStart:
                let delay = NSEvent.doubleClickInterval
                VoxtLog.hotkey("Transcription tap entering double-tap rewrite wait window. delaySec=\(delay)")
                schedulePendingTranscriptionStart(
                    delay: delay,
                    reason: "doubleTapRewriteWait"
                )
                return
            case .startRewrite:
                VoxtLog.hotkey("Transcription second tap detected; starting rewrite instead of transcription.")
                cancelPendingTranscriptionStart()
                beginRecording(outputMode: .rewrite)
                return
            }
        }
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
            if action == .scheduleTranscriptionStart, let pendingStartDelay {
                schedulePendingTranscriptionStart(
                    delay: pendingStartDelay,
                    reason: "\(source)LongPressDebounce",
                    shouldStart: pendingStartShouldStart
                )
            } else {
                performHotkeyAction(action)
            }
        }
    }

    func handleTranscriptionHotkeyUp() {
        handleTranscriptionTriggerUp(triggerMode: HotkeyPreference.loadTriggerMode(), source: "hotkey")
    }

    private func handleTranscriptionTriggerUp(
        triggerMode: HotkeyPreference.TriggerMode,
        source: String
    ) {
        guard triggerMode == .longPress else { return }
        VoxtLog.hotkey(
            "Trigger callback transcriptionUp. source=\(source), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
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
        handleTranslationTriggerDown(triggerMode: HotkeyPreference.loadTriggerMode(), source: "hotkey")
    }

    private func handleTranslationTriggerDown(
        triggerMode: HotkeyPreference.TriggerMode,
        source: String
    ) {
        VoxtLog.info(
            "Translation trigger invoked. source=\(source), mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), pendingStart=\(pendingTranscriptionStartTask != nil)"
        )
        VoxtLog.hotkey(
            "Trigger callback translationDown. source=\(source), mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )
        guard !blockNonMeetingRecordingWhileMeetingIsActive(source: "\(source)TranslationDown") else { return }
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
        handleTranslationTriggerUp(triggerMode: HotkeyPreference.loadTriggerMode(), source: "hotkey")
    }

    private func handleTranslationTriggerUp(
        triggerMode: HotkeyPreference.TriggerMode,
        source: String
    ) {
        guard triggerMode == .longPress else { return }
        VoxtLog.hotkey(
            "Trigger callback translationUp. source=\(source), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputMode == .translation ? "translation" : "transcription"), selectedTextFlow=\(isSelectedTextTranslationFlow)",
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
        handleRewriteTriggerDown(triggerMode: HotkeyPreference.loadTriggerMode(), source: "hotkey")
    }

    private func handleRewriteTriggerDown(
        triggerMode: HotkeyPreference.TriggerMode,
        source: String
    ) {
        VoxtLog.info(
            "Rewrite trigger invoked. source=\(source), mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), pendingStart=\(pendingTranscriptionStartTask != nil)"
        )
        VoxtLog.hotkey(
            "Trigger callback rewriteDown. source=\(source), mode=\(triggerMode.rawValue), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputModeLabel), pendingStart=\(pendingTranscriptionStartTask != nil)",
        )
        guard !blockNonMeetingRecordingWhileMeetingIsActive(source: "\(source)RewriteDown") else { return }

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
        handleRewriteTriggerUp(triggerMode: HotkeyPreference.loadTriggerMode(), source: "hotkey")
    }

    private func handleRewriteTriggerUp(
        triggerMode: HotkeyPreference.TriggerMode,
        source: String
    ) {
        guard triggerMode == .longPress else { return }
        VoxtLog.hotkey(
            "Trigger callback rewriteUp. source=\(source), isSessionActive=\(isSessionActive), sessionOutput=\(sessionOutputModeLabel)",
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
        schedulePendingTranscriptionStart(
            delay: transcriptionStartDebounceInterval,
            reason: "longPressDebounce"
        )
    }

    func schedulePendingTranscriptionStart(
        delay: TimeInterval,
        reason: String,
        shouldStart: (() -> Bool)? = nil
    ) {
        guard !blockNonMeetingRecordingWhileMeetingIsActive(source: "pendingTranscriptionStart:\(reason)") else { return }
        VoxtLog.hotkey("Scheduling pending transcription start. delaySec=\(delay), reason=\(reason)")
        pendingTranscriptionStartTask?.cancel()
        pendingTranscriptionStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard !self.isSessionActive else {
                VoxtLog.hotkey("Pending transcription start dropped: session already active.")
                self.pendingTranscriptionStartTask = nil
                return
            }
            guard !self.blockNonMeetingRecordingWhileMeetingIsActive(source: "pendingTranscriptionStartFire:\(reason)") else {
                self.pendingTranscriptionStartTask = nil
                return
            }
            if let shouldStart, !shouldStart() {
                VoxtLog.hotkey("Pending transcription start dropped: trigger is no longer active. reason=\(reason)")
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

    nonisolated static func sessionCallbackHandlingDecision(
        requestedSessionID: UUID,
        activeSessionID: UUID,
        isSessionCancellationRequested: Bool
    ) -> SessionCallbackHandlingDecision {
        guard requestedSessionID == activeSessionID else {
            return .rejectStale
        }
        guard !isSessionCancellationRequested else {
            return .rejectCancelled
        }
        return .accept
    }

    func shouldHandleCallbacks(for sessionID: UUID) -> Bool {
        switch Self.sessionCallbackHandlingDecision(
            requestedSessionID: sessionID,
            activeSessionID: activeRecordingSessionID,
            isSessionCancellationRequested: isSessionCancellationRequested
        ) {
        case .accept:
            return true
        case .rejectStale:
            VoxtLog.info("Ignoring stale session callback. sessionID=\(sessionID.uuidString)", verbose: true)
            return false
        case .rejectCancelled:
            VoxtLog.info("Ignoring callback for cancelled session. sessionID=\(sessionID.uuidString)", verbose: true)
            return false
        }
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

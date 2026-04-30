import Foundation
import Carbon
import AppKit
import ApplicationServices

/// Monitors a global hotkey via a CGEvent tap.
/// - Press and hold hotkey key  → calls `onKeyDown`
/// - Release hotkey key         → calls `onKeyUp`
@MainActor
class HotkeyManager {
    enum EventTapRecoveryResult: Equatable {
        case reenabled
        case unavailable
    }

    // Hotkey state machine notes:
    // 1) Translation shortcut has higher priority than transcription.
    // 2) For modifier-only tap mode (fn / fn+shift), we emit "down" as toggle signal.
    // 3) We intentionally delay transcription tap by 80ms when translation combo is a superset
    //    (e.g. fn vs fn+shift), so quick combo presses do not accidentally fire fn.
    // 4) We keep a short cooldown after translation transitions to suppress stray fn tap events.
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onTranslationKeyDown: (() -> Void)?
    var onTranslationKeyUp: (() -> Void)?
    var onRewriteKeyDown: (() -> Void)?
    var onRewriteKeyUp: (() -> Void)?
    var onMeetingKeyDown: (() -> Void)?
    var onCustomPasteKeyDown: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    private var activeKeyCode: UInt16?
    private var isTranslationKeyDown = false
    private var activeTranslationKeyCode: UInt16?
    private var isRewriteKeyDown = false
    private var activeRewriteKeyCode: UInt16?
    private var isMeetingKeyDown = false
    private var activeMeetingKeyCode: UInt16?
    private var isCustomPasteKeyDown = false
    private var activeCustomPasteKeyCode: UInt16?
    private var hasTranscriptionModifierTapCandidate = false
    private var hasTranslationModifierTapCandidate = false
    private var hasRewriteModifierTapCandidate = false
    private var hasMeetingModifierTapCandidate = false
    private var hasCustomPasteModifierTapCandidate = false
    private var sawNonModifierKeyDuringFunctionChord = false
    private var currentSidedModifiers: SidedModifierFlags = []
    private var suppressTranscriptionTapUntil = Date.distantPast
    private var pendingTranscriptionLongPressReleaseTask: Task<Void, Never>?
    private var pendingTranslationLongPressReleaseTask: Task<Void, Never>?
    private var pendingRewriteLongPressReleaseTask: Task<Void, Never>?
    private var pendingMeetingLongPressReleaseTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var didPromptAccessibility = false
    private var didPromptInputMonitoring = false
    private var lastEventAt: Date?
    private let staleTapStateResetIdleThreshold: TimeInterval = 2.0

    deinit {
        retryTask?.cancel()
        retryTask = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        pendingTranscriptionLongPressReleaseTask?.cancel()
        pendingTranscriptionLongPressReleaseTask = nil
        pendingTranslationLongPressReleaseTask?.cancel()
        pendingTranslationLongPressReleaseTask = nil
        pendingRewriteLongPressReleaseTask?.cancel()
        pendingRewriteLongPressReleaseTask = nil
        pendingMeetingLongPressReleaseTask?.cancel()
        pendingMeetingLongPressReleaseTask = nil
    }

    func start() {
        if eventTap != nil {
            return
        }
        let configuration = HotkeyRuntimeConfiguration.load()
        VoxtLog.info("Starting hotkey manager.")
        VoxtLog.hotkey(configuration.debugBindingsDescription)
        guard preflightAndPromptPermissionsIfNeeded() else {
            scheduleRetry()
            return
        }
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let (tap, tapLocation) = createEventTap(eventMask: eventMask) else {
            VoxtLog.error("Failed to create event tap. \(permissionStatusText())")
            scheduleRetry()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        retryTask?.cancel()
        retryTask = nil
        VoxtLog.hotkey("Hotkey event tap started successfully. location=\(tapLocation.debugName)")
    }

    func stop() {
        VoxtLog.info("Stopping hotkey manager.")
        retryTask?.cancel()
        retryTask = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        clearTransientState()
        VoxtLog.hotkey("Hotkey manager stopped.")
    }

    func resetTransientState(reason: String) {
        VoxtLog.hotkey("Hotkey transient state reset. reason=\(reason)")
        clearTransientState()
    }

    @discardableResult
    func recoverEventTapIfNeeded(disabledEventType: CGEventType) -> EventTapRecoveryResult {
        let reason: String
        switch disabledEventType {
        case .tapDisabledByTimeout:
            reason = "tapDisabledByTimeout"
        case .tapDisabledByUserInput:
            reason = "tapDisabledByUserInput"
        default:
            reason = "unknown"
        }

        resetTransientState(reason: reason)

        guard let tap = eventTap else {
            VoxtLog.warning("Hotkey event tap disabled but no active tap is available. reason=\(reason)")
            return .unavailable
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        VoxtLog.warning("Hotkey event tap re-enabled. reason=\(reason)")
        return .reenabled
    }

    private func preflightAndPromptPermissionsIfNeeded() -> Bool {
        let currentStatus = EventListeningPermissionManager.status()
        let accessibilityGranted = currentStatus.accessibilityGranted
        let inputMonitoringGranted = currentStatus.inputMonitoringGranted

        guard accessibilityGranted, inputMonitoringGranted else {
            if !accessibilityGranted, !didPromptAccessibility {
                didPromptAccessibility = true
                _ = AccessibilityPermissionManager.request(prompt: true)
            }
            if !inputMonitoringGranted, !didPromptInputMonitoring {
                didPromptInputMonitoring = true
                _ = EventListeningPermissionManager.requestInputMonitoring(prompt: true)
            }
            VoxtLog.hotkey("Hotkey preflight blocked. \(permissionStatusText())")
            return false
        }

        return true
    }

    private func permissionStatusText() -> String {
        EventListeningPermissionManager.status().description
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.eventTap == nil {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self.start()
            }
        }
    }

    private func createEventTap(eventMask: CGEventMask) -> (tap: CFMachPort, location: CGEventTapLocation)? {
        let callback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                manager.recoverEventTapIfNeeded(disabledEventType: type)
                return Unmanaged.passUnretained(event)
            }
            manager.handleEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        for tapLocation in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            if let tap = CGEvent.tapCreate(
                tap: tapLocation,
                place: .tailAppendEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                return (tap, tapLocation)
            }
        }

        return nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard !UserDefaults.standard.bool(forKey: AppPreferenceKey.hotkeyCaptureInProgress) else {
            return
        }
        handleResolvedEvent(
            type: type,
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags,
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
    }

    private func handleResolvedEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isAutoRepeat: Bool
    ) {
        defer {
            lastEventAt = Date()
        }

        let configuration = HotkeyRuntimeConfiguration.load()
        let transcriptionHotkey = configuration.transcriptionHotkey
        let translationHotkey = configuration.translationHotkey
        let rewriteHotkey = configuration.rewriteHotkey
        let activeMeetingHotkey = configuration.meetingHotkey
        let activeCustomPasteHotkey = configuration.customPasteHotkey
        let distinguishModifierSides = configuration.distinguishModifierSides
        let triggerMode = configuration.triggerMode
        let incomingSidedModifiers =
            type == .flagsChanged
            ? SidedModifierFlags.from(eventFlags: flags).filtered(by: HotkeyEventSupport.modifierFlags(from: flags))
            : currentSidedModifiers
        let transcriptionFlags = configuration.transcriptionFlags
        let translationFlags = configuration.translationFlags
        let rewriteFlags = configuration.rewriteFlags
        let meetingFlags = configuration.meetingFlags
        let customPasteFlags = configuration.customPasteFlags
        let wasTranslationKeyDown = isTranslationKeyDown
        let wasRewriteKeyDown = isRewriteKeyDown
        let wasMeetingKeyDown = isMeetingKeyDown
        let wasCustomPasteKeyDown = isCustomPasteKeyDown

        if activeMeetingHotkey == nil {
            clearMeetingTransientState()
        }
        if activeCustomPasteHotkey == nil {
            clearCustomPasteTransientState()
        }

        resetTransientStateIfIdleGapSuggestsStaleState(
            triggerMode: triggerMode,
            incomingFlags: flags,
            keyCode: keyCode
        )

        resetTransientStateIfNeededForPotentialStaleFnEvent(
            type: type,
            keyCode: keyCode,
            flags: flags,
            triggerMode: triggerMode,
            transcriptionHotkey: transcriptionHotkey,
            transcriptionFlags: transcriptionFlags
        )

        if type == .flagsChanged {
            currentSidedModifiers = incomingSidedModifiers
        }

        if triggerMode == .tap, type == .keyDown, !HotkeyEventSupport.isModifierKeyCode(keyCode) {
            if flags.contains(.maskSecondaryFn) {
                sawNonModifierKeyDuringFunctionChord = true
            }
            invalidateModifierOnlyTapCandidates(for: keyCode)
        }

        if type == .flagsChanged,
           HotkeyEventSupport.shouldLogFlagsChangedEvent(
            keyCode: keyCode,
            flags: flags,
            triggerMode: triggerMode,
            transcriptionHotkey: transcriptionHotkey,
            translationHotkey: translationHotkey,
            rewriteHotkey: rewriteHotkey,
            meetingHotkey: activeMeetingHotkey,
            isKeyDown: isKeyDown,
            isTranslationKeyDown: isTranslationKeyDown,
            isRewriteKeyDown: isRewriteKeyDown,
            isMeetingKeyDown: isMeetingKeyDown,
            hasTranscriptionModifierTapCandidate: hasTranscriptionModifierTapCandidate,
            hasTranslationModifierTapCandidate: hasTranslationModifierTapCandidate,
            hasRewriteModifierTapCandidate: hasRewriteModifierTapCandidate,
            hasMeetingModifierTapCandidate: hasMeetingModifierTapCandidate,
            sawNonModifierKeyDuringFunctionChord: sawNonModifierKeyDuringFunctionChord
           ) {
            VoxtLog.hotkey(
                "Hotkey flagsChanged(tap). keyCode=\(keyCode), flags=\(HotkeyEventSupport.debugDescription(for: flags)), tHotkey=\(HotkeyEventSupport.debugDescription(for: transcriptionFlags)), trHotkey=\(HotkeyEventSupport.debugDescription(for: translationFlags)), rwHotkey=\(HotkeyEventSupport.debugDescription(for: rewriteFlags)), mtHotkey=\(HotkeyEventSupport.debugDescription(for: meetingFlags)), isKeyDown=\(isKeyDown), isTranslationKeyDown=\(isTranslationKeyDown), isRewriteKeyDown=\(isRewriteKeyDown), isMeetingKeyDown=\(isMeetingKeyDown), sawNonModifier=\(sawNonModifierKeyDuringFunctionChord), suppressRemainingMs=\(max(Int(suppressTranscriptionTapUntil.timeIntervalSinceNow * 1000), 0))"
            )
        }

        // Translation path must be evaluated first. If this ordering changes,
        // fn-only transcription can steal fn+shift transitions and cause flicker/auto-close regressions.
        if HotkeyModifierInterpreter.isModifierOnly(translationHotkey) {
            if handleModifierOnlyTranslationEvent(
                type: type,
                keyCode: keyCode,
                flags: flags,
                currentSidedModifiers: currentSidedModifiers,
                translationHotkey: translationHotkey,
                distinguishModifierSides: distinguishModifierSides,
                triggerMode: triggerMode,
                translationFlags: translationFlags,
                wasTranslationKeyDown: wasTranslationKeyDown
            ) {
                return
            }
        } else {
            let translationFlagsMatch = HotkeyPreference.hotkeyMatches(
                translationHotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides
            )
            switch type {
            case .keyDown:
                if keyCode == translationHotkey.keyCode, translationFlagsMatch, !isAutoRepeat {
                    if triggerMode == .tap {
                        emitTranslationKeyDown()
                    } else if !isTranslationKeyDown {
                        isTranslationKeyDown = true
                        activeTranslationKeyCode = keyCode
                        emitTranslationKeyDown()
                    }
                    return
                }
            case .keyUp:
                if triggerMode == .tap {
                    if activeTranslationKeyCode == keyCode {
                        activeTranslationKeyCode = nil
                    }
                    if keyCode == translationHotkey.keyCode {
                        emitTranslationKeyUp()
                        return
                    }
                } else if isTranslationKeyDown, activeTranslationKeyCode == keyCode {
                    isTranslationKeyDown = false
                    activeTranslationKeyCode = nil
                    emitTranslationKeyUp()
                    return
                }
            default:
                break
            }
        }

        if HotkeyModifierInterpreter.isModifierOnly(rewriteHotkey) {
            if handleModifierOnlyRewriteEvent(
                type: type,
                keyCode: keyCode,
                flags: flags,
                currentSidedModifiers: currentSidedModifiers,
                rewriteHotkey: rewriteHotkey,
                distinguishModifierSides: distinguishModifierSides,
                triggerMode: triggerMode,
                rewriteFlags: rewriteFlags,
                wasRewriteKeyDown: wasRewriteKeyDown
            ) {
                return
            }
        } else {
            let rewriteFlagsMatch = HotkeyPreference.hotkeyMatches(
                rewriteHotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides
            )
            switch type {
            case .keyDown:
                if keyCode == rewriteHotkey.keyCode, rewriteFlagsMatch, !isAutoRepeat {
                    if triggerMode == .tap {
                        emitRewriteKeyDown()
                    } else if !isRewriteKeyDown {
                        isRewriteKeyDown = true
                        activeRewriteKeyCode = keyCode
                        emitRewriteKeyDown()
                    }
                    return
                }
            case .keyUp:
                if triggerMode == .tap {
                    if activeRewriteKeyCode == keyCode {
                        activeRewriteKeyCode = nil
                    }
                    if keyCode == rewriteHotkey.keyCode {
                        emitRewriteKeyUp()
                        return
                    }
                } else if isRewriteKeyDown, activeRewriteKeyCode == keyCode {
                    isRewriteKeyDown = false
                    activeRewriteKeyCode = nil
                    emitRewriteKeyUp()
                    return
                }
            default:
                break
            }
        }

        if let customPasteHotkey = activeCustomPasteHotkey,
           HotkeyModifierInterpreter.isModifierOnly(customPasteHotkey) {
            if handleModifierOnlyCustomPasteEvent(
                type: type,
                keyCode: keyCode,
                flags: flags,
                currentSidedModifiers: currentSidedModifiers,
                customPasteHotkey: customPasteHotkey,
                distinguishModifierSides: distinguishModifierSides,
                customPasteFlags: customPasteFlags,
                wasCustomPasteKeyDown: wasCustomPasteKeyDown
            ) {
                return
            }
        } else if let customPasteHotkey = activeCustomPasteHotkey {
            let customPasteFlagsMatch = HotkeyPreference.hotkeyMatches(
                customPasteHotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides
            )
            switch type {
            case .keyDown:
                if keyCode == customPasteHotkey.keyCode, customPasteFlagsMatch, !isAutoRepeat {
                    if !isCustomPasteKeyDown {
                        isCustomPasteKeyDown = true
                        activeCustomPasteKeyCode = keyCode
                    }
                    return
                }
            case .keyUp:
                if isCustomPasteKeyDown, activeCustomPasteKeyCode == keyCode {
                    isCustomPasteKeyDown = false
                    activeCustomPasteKeyCode = nil
                    emitCustomPasteKeyDown()
                    return
                }
            default:
                break
            }
        }

        if let meetingHotkey = activeMeetingHotkey,
           HotkeyModifierInterpreter.isModifierOnly(meetingHotkey) {
            if handleModifierOnlyMeetingEvent(
                type: type,
                keyCode: keyCode,
                flags: flags,
                currentSidedModifiers: currentSidedModifiers,
                meetingHotkey: meetingHotkey,
                distinguishModifierSides: distinguishModifierSides,
                triggerMode: triggerMode,
                meetingFlags: meetingFlags,
                wasMeetingKeyDown: wasMeetingKeyDown
            ) {
                return
            }
        } else if let meetingHotkey = activeMeetingHotkey {
            let meetingFlagsMatch = HotkeyPreference.hotkeyMatches(
                meetingHotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides
            )
            switch type {
            case .keyDown:
                if keyCode == meetingHotkey.keyCode, meetingFlagsMatch, !isAutoRepeat {
                    if triggerMode == .tap {
                        emitMeetingKeyDown()
                    } else if !isMeetingKeyDown {
                        isMeetingKeyDown = true
                        activeMeetingKeyCode = keyCode
                        emitMeetingKeyDown()
                    }
                    return
                }
            case .keyUp:
                if triggerMode == .tap {
                    if activeMeetingKeyCode == keyCode {
                        activeMeetingKeyCode = nil
                    }
                    return
                }
                if isMeetingKeyDown, activeMeetingKeyCode == keyCode {
                    isMeetingKeyDown = false
                    activeMeetingKeyCode = nil
                    return
                }
            default:
                break
            }
        }

        // Transcription path runs after translation handling.
        // This keeps fn+shift and fn responsibilities separated.
        if HotkeyModifierInterpreter.isModifierOnly(transcriptionHotkey) {
            if handleModifierOnlyTranscriptionEvent(
                type: type,
                keyCode: keyCode,
                flags: flags,
                triggerMode: triggerMode,
                transcriptionHotkey: transcriptionHotkey,
                translationHotkey: translationHotkey,
                rewriteHotkey: rewriteHotkey,
                meetingHotkey: activeMeetingHotkey,
                currentSidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides,
                transcriptionFlags: transcriptionFlags,
                translationFlags: translationFlags,
                rewriteFlags: rewriteFlags,
                meetingFlags: meetingFlags
            ) {
                return
            }
            return
        }

        let transcriptionFlagsMatch = HotkeyPreference.hotkeyMatches(
            transcriptionHotkey,
            eventFlags: flags,
            sidedModifiers: currentSidedModifiers,
            distinguishModifierSides: distinguishModifierSides
        )
        switch type {
        case .keyDown:
            guard keyCode == transcriptionHotkey.keyCode, transcriptionFlagsMatch, !isAutoRepeat else { return }
            if triggerMode == .tap {
                emitKeyDown()
                return
            } else if !isKeyDown {
                isKeyDown = true
                activeKeyCode = keyCode
                emitKeyDown()
                return
            }
        case .keyUp:
            if triggerMode == .tap {
                if activeKeyCode == keyCode {
                    activeKeyCode = nil
                }
                if keyCode == transcriptionHotkey.keyCode {
                    emitKeyUp()
                }
                return
            }
            if isKeyDown, activeKeyCode == keyCode {
                isKeyDown = false
                activeKeyCode = nil
                emitKeyUp()
                return
            }
        default:
            break
        }

    }
    private func resetTransientStateIfNeededForPotentialStaleFnEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        triggerMode: HotkeyPreference.TriggerMode,
        transcriptionHotkey: HotkeyPreference.Hotkey,
        transcriptionFlags: CGEventFlags
    ) {
        guard type == .flagsChanged,
              triggerMode == .tap,
              HotkeyModifierInterpreter.isModifierOnly(transcriptionHotkey),
              transcriptionFlags == .maskSecondaryFn,
              HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode)
        else {
            return
        }

        let relevantFlags = flags.intersection([.maskSecondaryFn, .maskShift, .maskControl, .maskAlternate, .maskCommand])
        let isPlainFunctionContext = relevantFlags.isEmpty || relevantFlags == .maskSecondaryFn
        guard isPlainFunctionContext else { return }

        let hasStaleHigherPriorityState =
            isTranslationKeyDown ||
            isRewriteKeyDown ||
            isMeetingKeyDown ||
            hasTranslationModifierTapCandidate ||
            hasRewriteModifierTapCandidate ||
            hasMeetingModifierTapCandidate
        let hasStaleFunctionTapState =
            flags.contains(.maskSecondaryFn) &&
            (isKeyDown || hasTranscriptionModifierTapCandidate)

        guard hasStaleHigherPriorityState || hasStaleFunctionTapState else { return }

        resetTransientState(
            reason: "staleFnEvent flags=\(HotkeyEventSupport.debugDescription(for: flags)) isKeyDown=\(isKeyDown) hasTapCandidate=\(hasTranscriptionModifierTapCandidate) isTranslationKeyDown=\(isTranslationKeyDown) isRewriteKeyDown=\(isRewriteKeyDown)"
        )
    }

    private func resetTransientStateIfIdleGapSuggestsStaleState(
        triggerMode: HotkeyPreference.TriggerMode,
        incomingFlags: CGEventFlags,
        keyCode: UInt16
    ) {
        guard triggerMode == .tap,
              let lastEventAt
        else {
            return
        }

        let idleDuration = Date().timeIntervalSince(lastEventAt)
        guard idleDuration >= staleTapStateResetIdleThreshold,
              hasTransientTapState
        else {
            return
        }

        resetTransientState(
            reason: "idleGapRecovery gapMs=\(Int(idleDuration * 1000)) keyCode=\(keyCode) flags=\(HotkeyEventSupport.debugDescription(for: incomingFlags))"
        )
    }

    private var hasTransientTapState: Bool {
        isKeyDown ||
        isTranslationKeyDown ||
        isRewriteKeyDown ||
        isMeetingKeyDown ||
        hasTranscriptionModifierTapCandidate ||
        hasTranslationModifierTapCandidate ||
        hasRewriteModifierTapCandidate ||
        hasMeetingModifierTapCandidate ||
        sawNonModifierKeyDuringFunctionChord ||
        !currentSidedModifiers.isEmpty
    }

    private struct ModifierOnlyTapTransitionResult {
        let handled: Bool
        let shouldEmitConfirmedTap: Bool
    }

    private func handleModifierOnlyTapTransition(
        triggerDown: Bool,
        comboIsDown: Bool,
        wasKeyDown: Bool,
        keyIsDown: inout Bool,
        tapCandidate: inout Bool,
        downLog: String,
        upLog: String,
        confirmLog: String
    ) -> ModifierOnlyTapTransitionResult {
        var shouldEmitConfirmedTap = false

        if triggerDown && !keyIsDown {
            VoxtLog.hotkey(downLog)
            cancelPendingTranscriptionTap(resetKeyState: true)
            keyIsDown = true
            tapCandidate = true
            suppressTranscriptionTapUntil = Date().addingTimeInterval(0.35)
        }

        if !comboIsDown && keyIsDown {
            VoxtLog.hotkey(upLog)
            if tapCandidate {
                VoxtLog.hotkey(confirmLog)
                shouldEmitConfirmedTap = true
            }
            tapCandidate = false
            keyIsDown = false
            suppressTranscriptionTapUntil = Date().addingTimeInterval(0.20)
        }

        return ModifierOnlyTapTransitionResult(
            handled: wasKeyDown != keyIsDown || comboIsDown,
            shouldEmitConfirmedTap: shouldEmitConfirmedTap
        )
    }

    private func handleModifierOnlyTranslationEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        currentSidedModifiers: SidedModifierFlags,
        translationHotkey: HotkeyPreference.Hotkey,
        distinguishModifierSides: Bool,
        triggerMode: HotkeyPreference.TriggerMode,
        translationFlags: CGEventFlags,
        wasTranslationKeyDown: Bool
    ) -> Bool {
        guard type == .flagsChanged else { return false }

        let comboIsDown = HotkeyPreference.hotkeyMatches(
            translationHotkey,
            eventFlags: flags,
            sidedModifiers: currentSidedModifiers,
            distinguishModifierSides: distinguishModifierSides
        )
        let translationTriggerDown = HotkeyModifierInterpreter.translationTriggerDown(
            keyCode: keyCode,
            comboIsDown: comboIsDown,
            eventFlags: flags,
            translationFlags: translationFlags
        )

        if triggerMode == .tap {
            // Tap semantics:
            // - Translation combo enters a candidate state on modifier press.
            // - It triggers only when modifiers are released without any other key intervening.
            // - Stop action is centralized to transcription hotkey tap (fn) in AppDelegate.
            // - We still track combo-up to enter a short suppression window for fn stray events.
            let transition = handleModifierOnlyTapTransition(
                triggerDown: translationTriggerDown,
                comboIsDown: comboIsDown,
                wasKeyDown: wasTranslationKeyDown,
                keyIsDown: &isTranslationKeyDown,
                tapCandidate: &hasTranslationModifierTapCandidate,
                downLog: "Hotkey detect translation modifier combo down (tap).",
                upLog: "Hotkey detect translation modifier combo up (tap).",
                confirmLog: "Hotkey translation modifier tap confirmed on release."
            )
            if transition.shouldEmitConfirmedTap {
                emitTranslationKeyDown()
            }
            // Consume translation combo transitions to avoid falling through
            // into transcription fn-only handling during release sequence.
            return transition.handled
        }

        if comboIsDown {
            cancelPendingTranslationLongPressRelease()
        }
        if comboIsDown && !isTranslationKeyDown {
            VoxtLog.hotkey("Hotkey detect translation modifier combo down (longPress).")
            isTranslationKeyDown = true
            emitTranslationKeyDown()
        } else if !comboIsDown && isTranslationKeyDown {
            VoxtLog.hotkey("Hotkey detect translation modifier combo up (longPress-pending).")
            scheduleTranslationLongPressRelease()
        } else if translationFlags == .maskSecondaryFn && HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode) {
            if isTranslationKeyDown {
                isTranslationKeyDown = false
                emitTranslationKeyUp()
            } else {
                isTranslationKeyDown = true
                emitTranslationKeyDown()
            }
        }
        return false
    }

    private func handleModifierOnlyRewriteEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        currentSidedModifiers: SidedModifierFlags,
        rewriteHotkey: HotkeyPreference.Hotkey,
        distinguishModifierSides: Bool,
        triggerMode: HotkeyPreference.TriggerMode,
        rewriteFlags: CGEventFlags,
        wasRewriteKeyDown: Bool
    ) -> Bool {
        guard type == .flagsChanged else { return false }

        let comboIsDown = HotkeyPreference.hotkeyMatches(
            rewriteHotkey,
            eventFlags: flags,
            sidedModifiers: currentSidedModifiers,
            distinguishModifierSides: distinguishModifierSides
        )
        let rewriteTriggerDown = HotkeyModifierInterpreter.translationTriggerDown(
            keyCode: keyCode,
            comboIsDown: comboIsDown,
            eventFlags: flags,
            translationFlags: rewriteFlags
        )

        if triggerMode == .tap {
            let transition = handleModifierOnlyTapTransition(
                triggerDown: rewriteTriggerDown,
                comboIsDown: comboIsDown,
                wasKeyDown: wasRewriteKeyDown,
                keyIsDown: &isRewriteKeyDown,
                tapCandidate: &hasRewriteModifierTapCandidate,
                downLog: "Hotkey detect rewrite modifier combo down (tap).",
                upLog: "Hotkey detect rewrite modifier combo up (tap).",
                confirmLog: "Hotkey rewrite modifier tap confirmed on release."
            )
            if transition.shouldEmitConfirmedTap {
                emitRewriteKeyDown()
            }
            return transition.handled
        }

        if comboIsDown {
            cancelPendingRewriteLongPressRelease()
        }
        if comboIsDown && !isRewriteKeyDown {
            VoxtLog.hotkey("Hotkey detect rewrite modifier combo down (longPress).")
            isRewriteKeyDown = true
            emitRewriteKeyDown()
        } else if !comboIsDown && isRewriteKeyDown {
            VoxtLog.hotkey("Hotkey detect rewrite modifier combo up (longPress-pending).")
            scheduleRewriteLongPressRelease()
        } else if rewriteFlags == .maskSecondaryFn && HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode) {
            if isRewriteKeyDown {
                isRewriteKeyDown = false
                emitRewriteKeyUp()
            } else {
                isRewriteKeyDown = true
                emitRewriteKeyDown()
            }
        }
        return false
    }

    private func handleModifierOnlyMeetingEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        currentSidedModifiers: SidedModifierFlags,
        meetingHotkey: HotkeyPreference.Hotkey,
        distinguishModifierSides: Bool,
        triggerMode: HotkeyPreference.TriggerMode,
        meetingFlags: CGEventFlags,
        wasMeetingKeyDown: Bool
    ) -> Bool {
        guard type == .flagsChanged else { return false }

        let comboIsDown = HotkeyPreference.hotkeyMatches(
            meetingHotkey,
            eventFlags: flags,
            sidedModifiers: currentSidedModifiers,
            distinguishModifierSides: distinguishModifierSides
        )
        let meetingTriggerDown = HotkeyModifierInterpreter.translationTriggerDown(
            keyCode: keyCode,
            comboIsDown: comboIsDown,
            eventFlags: flags,
            translationFlags: meetingFlags
        )

        if triggerMode == .tap {
            let transition = handleModifierOnlyTapTransition(
                triggerDown: meetingTriggerDown,
                comboIsDown: comboIsDown,
                wasKeyDown: wasMeetingKeyDown,
                keyIsDown: &isMeetingKeyDown,
                tapCandidate: &hasMeetingModifierTapCandidate,
                downLog: "Hotkey detect meeting modifier combo down (tap).",
                upLog: "Hotkey detect meeting modifier combo up (tap).",
                confirmLog: "Hotkey meeting modifier tap confirmed on release."
            )
            if transition.shouldEmitConfirmedTap {
                emitMeetingKeyDown()
            }
            return transition.handled
        }

        if comboIsDown {
            cancelPendingMeetingLongPressRelease()
        }
        if comboIsDown && !isMeetingKeyDown {
            VoxtLog.hotkey("Hotkey detect meeting modifier combo down (longPress).")
            isMeetingKeyDown = true
            emitMeetingKeyDown()
        } else if !comboIsDown && isMeetingKeyDown {
            VoxtLog.hotkey("Hotkey detect meeting modifier combo up (longPress-pending).")
            scheduleMeetingLongPressRelease()
        } else if meetingFlags == .maskSecondaryFn && HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode) {
            isMeetingKeyDown.toggle()
            if isMeetingKeyDown {
                emitMeetingKeyDown()
            }
        }
        return false
    }

    private func handleModifierOnlyCustomPasteEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        currentSidedModifiers: SidedModifierFlags,
        customPasteHotkey: HotkeyPreference.Hotkey,
        distinguishModifierSides: Bool,
        customPasteFlags: CGEventFlags,
        wasCustomPasteKeyDown: Bool
    ) -> Bool {
        guard type == .flagsChanged else { return false }

        let comboIsDown = HotkeyPreference.hotkeyMatches(
            customPasteHotkey,
            eventFlags: flags,
            sidedModifiers: currentSidedModifiers,
            distinguishModifierSides: distinguishModifierSides
        )
        let customPasteTriggerDown = HotkeyModifierInterpreter.translationTriggerDown(
            keyCode: keyCode,
            comboIsDown: comboIsDown,
            eventFlags: flags,
            translationFlags: customPasteFlags
        )

        if customPasteFlags == .maskSecondaryFn && HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode) {
            if isCustomPasteKeyDown {
                isCustomPasteKeyDown = false
                hasCustomPasteModifierTapCandidate = false
                emitCustomPasteKeyDown()
            } else {
                isCustomPasteKeyDown = true
                hasCustomPasteModifierTapCandidate = true
            }
            return true
        }

        let transition = handleModifierOnlyTapTransition(
            triggerDown: customPasteTriggerDown,
            comboIsDown: comboIsDown,
            wasKeyDown: wasCustomPasteKeyDown,
            keyIsDown: &isCustomPasteKeyDown,
            tapCandidate: &hasCustomPasteModifierTapCandidate,
            downLog: "Hotkey detect custom paste modifier combo down.",
            upLog: "Hotkey detect custom paste modifier combo up.",
            confirmLog: "Hotkey custom paste modifier combo confirmed on release."
        )
        if transition.shouldEmitConfirmedTap {
            emitCustomPasteKeyDown()
        }
        return transition.handled
    }

    private func handleModifierOnlyTranscriptionEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        triggerMode: HotkeyPreference.TriggerMode,
        transcriptionHotkey: HotkeyPreference.Hotkey,
        translationHotkey: HotkeyPreference.Hotkey,
        rewriteHotkey: HotkeyPreference.Hotkey,
        meetingHotkey: HotkeyPreference.Hotkey?,
        currentSidedModifiers: SidedModifierFlags,
        distinguishModifierSides: Bool,
        transcriptionFlags: CGEventFlags,
        translationFlags: CGEventFlags,
        rewriteFlags: CGEventFlags,
        meetingFlags: CGEventFlags
    ) -> Bool {
        guard type == .flagsChanged else { return true }

        // If translation or rewrite modifier combo is active, suppress transcription trigger.
        if (HotkeyModifierInterpreter.isModifierOnly(translationHotkey) &&
            (HotkeyPreference.hotkeyMatches(
                translationHotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides
            ) || isTranslationKeyDown)) ||
            (HotkeyModifierInterpreter.isModifierOnly(rewriteHotkey) &&
            (HotkeyPreference.hotkeyMatches(
                rewriteHotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides
            ) || isRewriteKeyDown)) {
            VoxtLog.hotkey("Hotkey suppress transcription modifier path because higher-priority combo is active.")
            cancelPendingTranscriptionTap(resetKeyState: true)
            return true
        }
        if let meetingHotkey,
           HotkeyModifierInterpreter.isModifierOnly(meetingHotkey) &&
            (HotkeyPreference.hotkeyMatches(
                meetingHotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides
            ) || isMeetingKeyDown) {
            VoxtLog.hotkey("Hotkey suppress transcription modifier path because meeting combo is active.")
            cancelPendingTranscriptionTap(resetKeyState: true)
            return true
        }

        let comboIsDown = HotkeyPreference.hotkeyMatches(
            transcriptionHotkey,
            eventFlags: flags,
            sidedModifiers: currentSidedModifiers,
            distinguishModifierSides: distinguishModifierSides
        )
        let transcriptionTriggerDown = HotkeyModifierInterpreter.transcriptionTriggerDown(
            keyCode: keyCode,
            comboIsDown: comboIsDown,
            eventFlags: flags,
            transcriptionFlags: transcriptionFlags
        )
        let activeRelevantFlags = flags.intersection([.maskSecondaryFn, .maskShift, .maskControl, .maskAlternate, .maskCommand])
        let hasUnexpectedModifiers = !activeRelevantFlags.subtracting(transcriptionFlags).isEmpty

        if triggerMode == .tap {
            // Tap semantics for modifier-only transcription hotkey:
            // enter candidate state on press and confirm only on release.
            // Translation cooldown check is critical for fn/fn+shift coexistence.
            if Date() < suppressTranscriptionTapUntil {
                VoxtLog.hotkey("Hotkey suppress transcription tap due to translation cooldown.")
                cancelPendingTranscriptionTap(resetKeyState: true)
                hasTranscriptionModifierTapCandidate = false
                if !comboIsDown && isKeyDown {
                    isKeyDown = false
                }
                if keyCode == UInt16(kVK_Function), !flags.contains(.maskSecondaryFn) {
                    sawNonModifierKeyDuringFunctionChord = false
                }
                return true
            }
            if transcriptionTriggerDown && !isKeyDown {
                if hasUnexpectedModifiers {
                    VoxtLog.hotkey("Hotkey transcription tap ignored because unexpected modifiers are active.")
                    return true
                }
                if flags.contains(translationFlags) || flags.contains(rewriteFlags) {
                    VoxtLog.hotkey("Hotkey transcription tap ignored because higher-priority flags are active.")
                    return true
                }
                isKeyDown = true
                hasTranscriptionModifierTapCandidate = true
            }
            let isFnOnlyTranscriptionHotkey = transcriptionFlags == .maskSecondaryFn
            let isFunctionReleaseEvent =
                isFnOnlyTranscriptionHotkey &&
                keyCode == UInt16(kVK_Function) &&
                !flags.contains(.maskSecondaryFn)
            if isFunctionReleaseEvent && !isKeyDown {
                if !sawNonModifierKeyDuringFunctionChord,
                   !hasUnexpectedModifiers,
                   !isTranslationKeyDown,
                   !isRewriteKeyDown,
                   !isMeetingKeyDown {
                    VoxtLog.hotkey("Hotkey transcription fn-only tap confirmed on release without non-modifier key.")
                    emitKeyDown()
                } else {
                    VoxtLog.hotkey(
                        "Hotkey transcription fn-only release ignored. sawNonModifier=\(sawNonModifierKeyDuringFunctionChord), hasUnexpectedModifiers=\(hasUnexpectedModifiers), isTranslationKeyDown=\(isTranslationKeyDown), isRewriteKeyDown=\(isRewriteKeyDown), isMeetingKeyDown=\(isMeetingKeyDown)"
                    )
                }
                sawNonModifierKeyDuringFunctionChord = false
                return true
            }
            if !comboIsDown && isKeyDown {
                if hasTranscriptionModifierTapCandidate && !hasUnexpectedModifiers {
                    VoxtLog.hotkey("Hotkey transcription modifier tap confirmed on release.")
                    emitKeyDown()
                } else if hasTranscriptionModifierTapCandidate {
                    VoxtLog.hotkey("Hotkey transcription modifier tap canceled because unexpected modifiers remained active.")
                }
                hasTranscriptionModifierTapCandidate = false
                isKeyDown = false
                if keyCode == UInt16(kVK_Function), !flags.contains(.maskSecondaryFn) {
                    sawNonModifierKeyDuringFunctionChord = false
                }
            }
            cancelPendingTranscriptionTap(resetKeyState: false)
            return true
        }

        if comboIsDown && !isKeyDown {
            cancelPendingTranscriptionLongPressRelease()
            isKeyDown = true
            emitKeyDown()
        } else if !comboIsDown && isKeyDown {
            // Long-press release is confirmed with a short delay to tolerate
            // transient flags jitter on fn/shift combinations.
            scheduleTranscriptionLongPressRelease()
        } else if transcriptionFlags == .maskSecondaryFn && HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode) {
            if isKeyDown {
                isKeyDown = false
                emitKeyUp()
            } else {
                isKeyDown = true
                emitKeyDown()
            }
        }
        return true
    }

    private func cancelPendingTranscriptionTap(resetKeyState: Bool) {
        let hadKeyState = isKeyDown
        if resetKeyState {
            if hadKeyState {
                VoxtLog.hotkey("Hotkey delayed transcription tap canceled and key state reset.")
            }
            isKeyDown = false
        }
    }

    private func cancelPendingTranslationTap(resetKeyState: Bool) {
        let hadKeyState = isTranslationKeyDown
        if resetKeyState {
            if hadKeyState {
                VoxtLog.hotkey("Hotkey delayed translation tap canceled and key state reset.")
            }
            isTranslationKeyDown = false
        }
    }

    private func cancelPendingRewriteTap(resetKeyState: Bool) {
        let hadKeyState = isRewriteKeyDown
        if resetKeyState {
            if hadKeyState {
                VoxtLog.hotkey("Hotkey delayed rewrite tap canceled and key state reset.")
            }
            isRewriteKeyDown = false
        }
    }

    private func invalidateModifierOnlyTapCandidates(for keyCode: UInt16) {
        let keyLabel = HotkeyPreference.keyCodeDisplayString(keyCode)
        if hasTranscriptionModifierTapCandidate || hasTranslationModifierTapCandidate || hasRewriteModifierTapCandidate || hasMeetingModifierTapCandidate {
            VoxtLog.hotkey("Hotkey invalidated modifier-only tap candidate because non-modifier key went down. key=\(keyLabel)")
        }
        cancelPendingTranscriptionTap(resetKeyState: true)
        cancelPendingTranslationTap(resetKeyState: true)
        cancelPendingRewriteTap(resetKeyState: true)
        hasTranscriptionModifierTapCandidate = false
        hasTranslationModifierTapCandidate = false
        hasRewriteModifierTapCandidate = false
        hasMeetingModifierTapCandidate = false
    }

    private func scheduleTranslationLongPressRelease() {
        pendingTranslationLongPressReleaseTask?.cancel()
        pendingTranslationLongPressReleaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.isTranslationKeyDown else { return }
            self.pendingTranslationLongPressReleaseTask = nil
            self.isTranslationKeyDown = false
            self.emitTranslationKeyUp()
        }
    }

    private func cancelPendingTranslationLongPressRelease() {
        pendingTranslationLongPressReleaseTask?.cancel()
        pendingTranslationLongPressReleaseTask = nil
    }

    private func scheduleRewriteLongPressRelease() {
        pendingRewriteLongPressReleaseTask?.cancel()
        pendingRewriteLongPressReleaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.isRewriteKeyDown else { return }
            self.pendingRewriteLongPressReleaseTask = nil
            self.isRewriteKeyDown = false
            self.emitRewriteKeyUp()
        }
    }

    private func cancelPendingRewriteLongPressRelease() {
        pendingRewriteLongPressReleaseTask?.cancel()
        pendingRewriteLongPressReleaseTask = nil
    }

    private func scheduleMeetingLongPressRelease() {
        pendingMeetingLongPressReleaseTask?.cancel()
        pendingMeetingLongPressReleaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.isMeetingKeyDown else { return }
            self.pendingMeetingLongPressReleaseTask = nil
            self.isMeetingKeyDown = false
        }
    }

    private func cancelPendingMeetingLongPressRelease() {
        pendingMeetingLongPressReleaseTask?.cancel()
        pendingMeetingLongPressReleaseTask = nil
    }

    private func scheduleTranscriptionLongPressRelease() {
        pendingTranscriptionLongPressReleaseTask?.cancel()
        pendingTranscriptionLongPressReleaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.isKeyDown else { return }
            self.pendingTranscriptionLongPressReleaseTask = nil
            self.isKeyDown = false
            self.emitKeyUp()
        }
    }

    private func cancelPendingTranscriptionLongPressRelease() {
        pendingTranscriptionLongPressReleaseTask?.cancel()
        pendingTranscriptionLongPressReleaseTask = nil
    }

    private func emitKeyDown() {
        onKeyDown?()
    }

    private func emitKeyUp() {
        onKeyUp?()
    }

    private func emitTranslationKeyDown() {
        onTranslationKeyDown?()
    }

    private func emitTranslationKeyUp() {
        onTranslationKeyUp?()
    }

    private func emitRewriteKeyDown() {
        onRewriteKeyDown?()
    }

    private func emitRewriteKeyUp() {
        onRewriteKeyUp?()
    }

    private func emitMeetingKeyDown() {
        onMeetingKeyDown?()
    }

    private func emitCustomPasteKeyDown() {
        onCustomPasteKeyDown?()
    }

    private func clearMeetingTransientState() {
        isMeetingKeyDown = false
        activeMeetingKeyCode = nil
        hasMeetingModifierTapCandidate = false
        cancelPendingMeetingLongPressRelease()
    }

    private func clearCustomPasteTransientState() {
        isCustomPasteKeyDown = false
        activeCustomPasteKeyCode = nil
        hasCustomPasteModifierTapCandidate = false
    }

    private func clearTransientState() {
        isKeyDown = false
        activeKeyCode = nil
        isTranslationKeyDown = false
        activeTranslationKeyCode = nil
        isRewriteKeyDown = false
        activeRewriteKeyCode = nil
        isMeetingKeyDown = false
        activeMeetingKeyCode = nil
        isCustomPasteKeyDown = false
        activeCustomPasteKeyCode = nil
        hasTranscriptionModifierTapCandidate = false
        hasTranslationModifierTapCandidate = false
        hasRewriteModifierTapCandidate = false
        hasMeetingModifierTapCandidate = false
        hasCustomPasteModifierTapCandidate = false
        sawNonModifierKeyDuringFunctionChord = false
        currentSidedModifiers = []
        suppressTranscriptionTapUntil = .distantPast
        lastEventAt = Date()
        pendingTranscriptionLongPressReleaseTask?.cancel()
        pendingTranscriptionLongPressReleaseTask = nil
        pendingTranslationLongPressReleaseTask?.cancel()
        pendingTranslationLongPressReleaseTask = nil
        pendingRewriteLongPressReleaseTask?.cancel()
        pendingRewriteLongPressReleaseTask = nil
        pendingMeetingLongPressReleaseTask?.cancel()
        pendingMeetingLongPressReleaseTask = nil
    }
}

#if DEBUG
extension HotkeyManager {
    struct TransientStateSnapshot: Equatable {
        let isKeyDown: Bool
        let isTranslationKeyDown: Bool
        let isRewriteKeyDown: Bool
        let isMeetingKeyDown: Bool
        let isCustomPasteKeyDown: Bool
        let hasTranscriptionModifierTapCandidate: Bool
        let hasTranslationModifierTapCandidate: Bool
        let hasRewriteModifierTapCandidate: Bool
        let hasMeetingModifierTapCandidate: Bool
        let hasCustomPasteModifierTapCandidate: Bool
        let sawNonModifierKeyDuringFunctionChord: Bool
        let currentSidedModifiers: SidedModifierFlags
    }

    func testingHandleEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isAutoRepeat: Bool = false
    ) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            _ = recoverEventTapIfNeeded(disabledEventType: type)
            return
        }
        handleResolvedEvent(type: type, keyCode: keyCode, flags: flags, isAutoRepeat: isAutoRepeat)
    }

    func testingSetTransientState(
        isKeyDown: Bool = false,
        isTranslationKeyDown: Bool = false,
        isRewriteKeyDown: Bool = false,
        isMeetingKeyDown: Bool = false,
        isCustomPasteKeyDown: Bool = false,
        hasTranscriptionModifierTapCandidate: Bool = false,
        hasTranslationModifierTapCandidate: Bool = false,
        hasRewriteModifierTapCandidate: Bool = false,
        hasMeetingModifierTapCandidate: Bool = false,
        hasCustomPasteModifierTapCandidate: Bool = false,
        sawNonModifierKeyDuringFunctionChord: Bool = false,
        currentSidedModifiers: SidedModifierFlags = []
    ) {
        self.isKeyDown = isKeyDown
        self.isTranslationKeyDown = isTranslationKeyDown
        self.isRewriteKeyDown = isRewriteKeyDown
        self.isMeetingKeyDown = isMeetingKeyDown
        self.isCustomPasteKeyDown = isCustomPasteKeyDown
        self.hasTranscriptionModifierTapCandidate = hasTranscriptionModifierTapCandidate
        self.hasTranslationModifierTapCandidate = hasTranslationModifierTapCandidate
        self.hasRewriteModifierTapCandidate = hasRewriteModifierTapCandidate
        self.hasMeetingModifierTapCandidate = hasMeetingModifierTapCandidate
        self.hasCustomPasteModifierTapCandidate = hasCustomPasteModifierTapCandidate
        self.sawNonModifierKeyDuringFunctionChord = sawNonModifierKeyDuringFunctionChord
        self.currentSidedModifiers = currentSidedModifiers
    }

    func testingSetLastEventAt(_ date: Date?) {
        lastEventAt = date
    }

    func testingTransientStateSnapshot() -> TransientStateSnapshot {
        TransientStateSnapshot(
            isKeyDown: isKeyDown,
            isTranslationKeyDown: isTranslationKeyDown,
            isRewriteKeyDown: isRewriteKeyDown,
            isMeetingKeyDown: isMeetingKeyDown,
            isCustomPasteKeyDown: isCustomPasteKeyDown,
            hasTranscriptionModifierTapCandidate: hasTranscriptionModifierTapCandidate,
            hasTranslationModifierTapCandidate: hasTranslationModifierTapCandidate,
            hasRewriteModifierTapCandidate: hasRewriteModifierTapCandidate,
            hasMeetingModifierTapCandidate: hasMeetingModifierTapCandidate,
            hasCustomPasteModifierTapCandidate: hasCustomPasteModifierTapCandidate,
            sawNonModifierKeyDuringFunctionChord: sawNonModifierKeyDuringFunctionChord,
            currentSidedModifiers: currentSidedModifiers
        )
    }
}
#endif

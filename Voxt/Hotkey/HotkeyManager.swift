// HotkeyManager.swift
// Provides Hotkey Manager for hotkey handling.

import Foundation
import Carbon
import AppKit
import ApplicationServices
import IOKit.hid

/// Monitors a global hotkey via a CGEvent tap.
/// - Press and hold hotkey key  → calls `onKeyDown`
/// - Release hotkey key         → calls `onKeyUp`
@MainActor
class HotkeyManager {
    enum EventTapRecoveryResult: Equatable {
        case reenabled
        case unavailable
    }

    private enum RoutedHotkeyBusiness: CaseIterable {
        case translation
        case rewrite
        case meeting
        case customPaste
        case transcription

        var priority: Int {
            switch self {
            case .translation:
                return 0
            case .rewrite:
                return 1
            case .meeting:
                return 2
            case .customPaste:
                return 3
            case .transcription:
                return 4
            }
        }
    }

    private struct RoutedHotkeyBinding {
        let business: RoutedHotkeyBusiness
        let binding: HotkeyPreference.HotkeyBinding
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
    var onEscapeKeyDown: (() -> Bool)?
    var onKeyDownWithBehavior: ((HotkeyPreference.TriggerBehavior) -> Void)?
    var onKeyUpWithBehavior: ((HotkeyPreference.TriggerBehavior) -> Void)?
    var onTranslationKeyDownWithBehavior: ((HotkeyPreference.TriggerBehavior) -> Void)?
    var onTranslationKeyUpWithBehavior: ((HotkeyPreference.TriggerBehavior) -> Void)?
    var onRewriteKeyDownWithBehavior: ((HotkeyPreference.TriggerBehavior) -> Void)?
    var onRewriteKeyUpWithBehavior: ((HotkeyPreference.TriggerBehavior) -> Void)?
    var onMeetingKeyDownWithBehavior: ((HotkeyPreference.TriggerBehavior) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    private var activeKeyCode: UInt16?
    private var activeMouseButtonNumber: Int?
    private var isTranslationKeyDown = false
    private var activeTranslationKeyCode: UInt16?
    private var activeTranslationMouseButtonNumber: Int?
    private var isRewriteKeyDown = false
    private var activeRewriteKeyCode: UInt16?
    private var activeRewriteMouseButtonNumber: Int?
    private var isMeetingKeyDown = false
    private var activeMeetingKeyCode: UInt16?
    private var activeMeetingMouseButtonNumber: Int?
    private var isCustomPasteKeyDown = false
    private var activeCustomPasteKeyCode: UInt16?
    private var activeCustomPasteMouseButtonNumber: Int?
    private var hasTranscriptionModifierTapCandidate = false
    private var hasTranslationModifierTapCandidate = false
    private var hasRewriteModifierTapCandidate = false
    private var hasMeetingModifierTapCandidate = false
    private var hasCustomPasteModifierTapCandidate = false
    private var sawNonModifierKeyDuringFunctionChord = false
    private var sawUnexpectedModifierDuringFunctionChord = false
    private var shouldIgnoreNextFunctionTranscriptionRelease = false
    private var currentSidedModifiers: SidedModifierFlags = []
    private var suppressTranscriptionTapUntil = Date.distantPast
    private var pendingTranscriptionLongPressReleaseTask: Task<Void, Never>?
    private var pendingTranslationLongPressReleaseTask: Task<Void, Never>?
    private var pendingRewriteLongPressReleaseTask: Task<Void, Never>?
    private var pendingDoubleTapBindingID: UUID?
    private var pendingDoubleTapAt: Date?
    private var retryTask: Task<Void, Never>?
    private var defaultsDidChangeObserver: NSObjectProtocol?
    private var cachedConfiguration: HotkeyRuntimeConfiguration?
    private var dispatchCallbacksAsynchronously = true
    private var lastFlagsChangedDebugLogSignature: String?
    private var lastFlagsChangedDebugLogAt = Date.distantPast
    private let flagsChangedDebugLogMinimumInterval: TimeInterval = 0.25
    private var didPromptAccessibility = false
    private var didPromptInputMonitoring = false
    private var lastEventAt: Date?
    private let staleTapStateResetIdleThreshold: TimeInterval = 2.0

    init() {
        defaultsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cachedConfiguration = nil
            }
        }
    }

    deinit {
        retryTask?.cancel()
        retryTask = nil
        if let defaultsDidChangeObserver {
            NotificationCenter.default.removeObserver(defaultsDidChangeObserver)
        }

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
    }

    func start() {
        if eventTap != nil {
            return
        }
        let configuration = runtimeConfiguration()
        VoxtLog.info("Starting hotkey manager.")
        VoxtLog.hotkey(configuration.debugBindingsDescription)
        guard preflightAndPromptPermissionsIfNeeded() else {
            scheduleRetry()
            return
        }
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

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

    private func runtimeConfiguration() -> HotkeyRuntimeConfiguration {
        if let cachedConfiguration {
            return cachedConfiguration
        }
        let configuration = HotkeyRuntimeConfiguration.load()
        cachedConfiguration = configuration
        return configuration
    }

    private func logFlagsChangedDebugEventIfNeeded(
        keyCode: UInt16,
        flags: CGEventFlags,
        transcriptionFlags: CGEventFlags,
        translationFlags: CGEventFlags,
        rewriteFlags: CGEventFlags
    ) {
        guard VoxtLog.isHotkeyDebugLoggingEnabled else { return }

        let now = Date()
        let signature = [
            "keyCode=\(keyCode)",
            "flags=\(HotkeyEventSupport.debugDescription(for: flags))",
            "isKeyDown=\(isKeyDown)",
            "isTranslationKeyDown=\(isTranslationKeyDown)",
            "isRewriteKeyDown=\(isRewriteKeyDown)",
            "sawNonModifier=\(sawNonModifierKeyDuringFunctionChord)"
        ].joined(separator: ",")
        if signature == lastFlagsChangedDebugLogSignature,
           now.timeIntervalSince(lastFlagsChangedDebugLogAt) < flagsChangedDebugLogMinimumInterval {
            return
        }

        lastFlagsChangedDebugLogSignature = signature
        lastFlagsChangedDebugLogAt = now
        VoxtLog.hotkey(
            "Hotkey flagsChanged(tap). keyCode=\(keyCode), flags=\(HotkeyEventSupport.debugDescription(for: flags)), tHotkey=\(HotkeyEventSupport.debugDescription(for: transcriptionFlags)), trHotkey=\(HotkeyEventSupport.debugDescription(for: translationFlags)), rwHotkey=\(HotkeyEventSupport.debugDescription(for: rewriteFlags)), isKeyDown=\(isKeyDown), isTranslationKeyDown=\(isTranslationKeyDown), isRewriteKeyDown=\(isRewriteKeyDown), sawNonModifier=\(sawNonModifierKeyDuringFunctionChord), suppressRemainingMs=\(max(Int(suppressTranscriptionTapUntil.timeIntervalSinceNow * 1000), 0))"
        )
    }

    private func createEventTap(eventMask: CGEventMask) -> (tap: CFMachPort, location: CGEventTapLocation)? {
        let callback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                manager.recoverEventTapIfNeeded(disabledEventType: type)
                return Unmanaged.passUnretained(event)
            }
            let consumed = manager.handleEvent(type: type, event: event)
            return consumed ? nil : Unmanaged.passUnretained(event)
        }

        for tapLocation in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            if let tap = CGEvent.tapCreate(
                tap: tapLocation,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                return (tap, tapLocation)
            }
        }

        return nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard !UserDefaults.standard.bool(forKey: AppPreferenceKey.hotkeyCaptureInProgress) else {
            return false
        }
        var eventWasConsumed = false
        switch type {
        case .otherMouseDown, .otherMouseUp:
            handleResolvedMouseEvent(
                type: type,
                buttonNumber: Int(event.getIntegerValueField(.mouseEventButtonNumber)),
                flags: event.flags,
                eventWasConsumed: &eventWasConsumed
            )
        default:
            handleResolvedEvent(
                type: type,
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                flags: event.flags,
                isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                eventWasConsumed: &eventWasConsumed
            )
        }
        return eventWasConsumed
    }

    private func handleResolvedEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isAutoRepeat: Bool,
        eventWasConsumed: inout Bool
    ) {
        defer {
            lastEventAt = Date()
        }

        let configuration = runtimeConfiguration()
        let transcriptionHotkey = configuration.transcriptionHotkey
        let translationHotkey = configuration.translationHotkey
        let rewriteHotkey = configuration.rewriteActivationMode == .dedicatedHotkey
            ? configuration.rewriteHotkey
            : nil
        let activeMeetingHotkey = configuration.meetingHotkey
        let activeCustomPasteHotkey = configuration.customPasteHotkey
        let distinguishModifierSides = configuration.distinguishModifierSides
        let triggerMode = configuration.triggerMode
        let incomingSidedModifiers =
            type == .flagsChanged
            ? resolvedSidedModifiers(
                forModifierKeyCode: keyCode,
                flags: flags,
                currentSidedModifiers: currentSidedModifiers
            )
            : currentSidedModifiers
        let transcriptionFlags = configuration.transcriptionFlags
        let translationFlags = configuration.translationFlags
        let rewriteFlags = rewriteHotkey.map { HotkeyPreference.cgFlags(from: $0.modifiers) } ?? []
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
        if rewriteHotkey == nil {
            clearRewriteTransientState()
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

        if handleBindingRoutedKeyboardEvent(
            type: type,
            keyCode: keyCode,
            flags: flags,
            isAutoRepeat: isAutoRepeat,
            configuration: configuration
        ) {
            eventWasConsumed = true
            return
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
            isKeyDown: isKeyDown,
            isTranslationKeyDown: isTranslationKeyDown,
            isRewriteKeyDown: isRewriteKeyDown,
            hasTranscriptionModifierTapCandidate: hasTranscriptionModifierTapCandidate,
            hasTranslationModifierTapCandidate: hasTranslationModifierTapCandidate,
            hasRewriteModifierTapCandidate: hasRewriteModifierTapCandidate,
            sawNonModifierKeyDuringFunctionChord: sawNonModifierKeyDuringFunctionChord
           ) {
            logFlagsChangedDebugEventIfNeeded(
                keyCode: keyCode,
                flags: flags,
                transcriptionFlags: transcriptionFlags,
                translationFlags: translationFlags,
                rewriteFlags: rewriteFlags
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
                    activeTranslationKeyCode = keyCode
                    if triggerMode == .tap {
                        emitTranslationKeyDown()
                    } else if !isTranslationKeyDown {
                        isTranslationKeyDown = true
                        emitTranslationKeyDown()
                    }
                    eventWasConsumed = true
                    return
                }
            case .keyUp:
                if triggerMode == .tap {
                    if activeTranslationKeyCode == keyCode {
                        activeTranslationKeyCode = nil
                        emitTranslationKeyUp()
                        eventWasConsumed = true
                        return
                    }
                } else if isTranslationKeyDown, activeTranslationKeyCode == keyCode {
                    isTranslationKeyDown = false
                    activeTranslationKeyCode = nil
                    emitTranslationKeyUp()
                    eventWasConsumed = true
                    return
                }
            default:
                break
            }
        }

        if let rewriteHotkey, HotkeyModifierInterpreter.isModifierOnly(rewriteHotkey) {
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
        } else if let rewriteHotkey {
            let rewriteFlagsMatch = HotkeyPreference.hotkeyMatches(
                rewriteHotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides
            )
            switch type {
            case .keyDown:
                if keyCode == rewriteHotkey.keyCode, rewriteFlagsMatch, !isAutoRepeat {
                    activeRewriteKeyCode = keyCode
                    if triggerMode == .tap {
                        emitRewriteKeyDown()
                    } else if !isRewriteKeyDown {
                        isRewriteKeyDown = true
                        emitRewriteKeyDown()
                    }
                    eventWasConsumed = true
                    return
                }
            case .keyUp:
                if triggerMode == .tap {
                    if activeRewriteKeyCode == keyCode {
                        activeRewriteKeyCode = nil
                        emitRewriteKeyUp()
                        eventWasConsumed = true
                        return
                    }
                } else if isRewriteKeyDown, activeRewriteKeyCode == keyCode {
                    isRewriteKeyDown = false
                    activeRewriteKeyCode = nil
                    emitRewriteKeyUp()
                    eventWasConsumed = true
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
                    activeMeetingKeyCode = keyCode
                    if triggerMode == .tap {
                        emitMeetingKeyDown()
                    } else if !isMeetingKeyDown {
                        isMeetingKeyDown = true
                        emitMeetingKeyDown()
                    }
                    eventWasConsumed = true
                    return
                }
            case .keyUp:
                if activeMeetingKeyCode == keyCode {
                    isMeetingKeyDown = false
                    activeMeetingKeyCode = nil
                    eventWasConsumed = true
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
                    eventWasConsumed = true
                    return
                }
            case .keyUp:
                if isCustomPasteKeyDown, activeCustomPasteKeyCode == keyCode {
                    isCustomPasteKeyDown = false
                    activeCustomPasteKeyCode = nil
                    emitCustomPasteKeyDown()
                    eventWasConsumed = true
                    return
                }
            default:
                break
            }
        }

        if type == .keyDown,
           keyCode == UInt16(kVK_Escape),
           !isAutoRepeat,
           onEscapeKeyDown?() == true {
            eventWasConsumed = true
            return
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
                currentSidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides,
                transcriptionFlags: transcriptionFlags,
                translationFlags: translationFlags,
                rewriteFlags: rewriteFlags
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
            activeKeyCode = keyCode
            if triggerMode == .tap {
                emitKeyDown()
                eventWasConsumed = true
                return
            } else if !isKeyDown {
                isKeyDown = true
                emitKeyDown()
                eventWasConsumed = true
                return
            }
        case .keyUp:
            if triggerMode == .tap {
                if activeKeyCode == keyCode {
                    activeKeyCode = nil
                    emitKeyUp()
                    eventWasConsumed = true
                    return
                }
            }
            if isKeyDown, activeKeyCode == keyCode {
                isKeyDown = false
                activeKeyCode = nil
                emitKeyUp()
                eventWasConsumed = true
                return
            }
        default:
            break
        }

    }

    private func handleResolvedMouseEvent(
        type: CGEventType,
        buttonNumber: Int,
        flags: CGEventFlags,
        eventWasConsumed: inout Bool
    ) {
        defer {
            lastEventAt = Date()
        }

        guard type == .otherMouseDown || type == .otherMouseUp else { return }
        let configuration = runtimeConfiguration()
        let rewriteHotkey = configuration.rewriteActivationMode == .dedicatedHotkey
            ? configuration.rewriteHotkey
            : nil
        let triggerMode = configuration.triggerMode
        let distinguishModifierSides = configuration.distinguishModifierSides

        if activeCustomPasteHotkeyIsDisabled(configuration.customPasteHotkey) {
            clearCustomPasteTransientState()
        }
        if rewriteHotkey == nil {
            clearRewriteTransientState()
        }

        if handleBindingRoutedMouseEvent(
            type: type,
            buttonNumber: buttonNumber,
            flags: flags,
            configuration: configuration
        ) {
            eventWasConsumed = true
            return
        }

        if handleMouseHotkey(
            type: type,
            buttonNumber: buttonNumber,
            flags: flags,
            hotkey: configuration.translationHotkey,
            distinguishModifierSides: distinguishModifierSides,
            triggerMode: triggerMode,
            isKeyDown: &isTranslationKeyDown,
            activeMouseButtonNumber: &activeTranslationMouseButtonNumber,
            onDown: { [weak self] in self?.emitTranslationKeyDown() },
            onUp: { [weak self] in self?.emitTranslationKeyUp() }
        ) {
            eventWasConsumed = true
            return
        }

        if let rewriteHotkey,
           handleMouseHotkey(
            type: type,
            buttonNumber: buttonNumber,
            flags: flags,
            hotkey: rewriteHotkey,
            distinguishModifierSides: distinguishModifierSides,
            triggerMode: triggerMode,
            isKeyDown: &isRewriteKeyDown,
            activeMouseButtonNumber: &activeRewriteMouseButtonNumber,
            onDown: { [weak self] in self?.emitRewriteKeyDown() },
            onUp: { [weak self] in self?.emitRewriteKeyUp() }
           ) {
            eventWasConsumed = true
            return
        }

        if let meetingHotkey = configuration.meetingHotkey,
           handleMouseHotkey(
            type: type,
            buttonNumber: buttonNumber,
            flags: flags,
            hotkey: meetingHotkey,
            distinguishModifierSides: distinguishModifierSides,
            triggerMode: triggerMode,
            isKeyDown: &isMeetingKeyDown,
            activeMouseButtonNumber: &activeMeetingMouseButtonNumber,
            onDown: { [weak self] in self?.emitMeetingKeyDown() },
            onUp: {}
           ) {
            eventWasConsumed = true
            return
        }

        if let customPasteHotkey = configuration.customPasteHotkey,
           handleMouseCustomPasteHotkey(
            type: type,
            buttonNumber: buttonNumber,
            flags: flags,
            hotkey: customPasteHotkey,
            distinguishModifierSides: distinguishModifierSides
           ) {
            eventWasConsumed = true
            return
        }

        if handleMouseHotkey(
            type: type,
            buttonNumber: buttonNumber,
            flags: flags,
            hotkey: configuration.transcriptionHotkey,
            distinguishModifierSides: distinguishModifierSides,
            triggerMode: triggerMode,
            isKeyDown: &isKeyDown,
            activeMouseButtonNumber: &activeMouseButtonNumber,
            onDown: { [weak self] in self?.emitKeyDown() },
            onUp: { [weak self] in self?.emitKeyUp() }
        ) {
            eventWasConsumed = true
            return
        }
    }

    private func activeCustomPasteHotkeyIsDisabled(_ hotkey: HotkeyPreference.Hotkey?) -> Bool {
        hotkey == nil
    }

    private func handleMouseHotkey(
        type: CGEventType,
        buttonNumber: Int,
        flags: CGEventFlags,
        hotkey: HotkeyPreference.Hotkey,
        distinguishModifierSides: Bool,
        triggerMode: HotkeyPreference.TriggerMode,
        isKeyDown: inout Bool,
        activeMouseButtonNumber: inout Int?,
        onDown: () -> Void,
        onUp: () -> Void
    ) -> Bool {
        guard mouseHotkey(hotkey, matchesButtonNumber: buttonNumber, flags: flags, distinguishModifierSides: distinguishModifierSides) else {
            if type == .otherMouseUp, activeMouseButtonNumber == buttonNumber {
                activeMouseButtonNumber = nil
                if isKeyDown {
                    isKeyDown = false
                    onUp()
                    return true
                }
            }
            return false
        }

        switch type {
        case .otherMouseDown:
            activeMouseButtonNumber = buttonNumber
            if triggerMode == .tap {
                onDown()
                return true
            }
            if !isKeyDown {
                isKeyDown = true
                onDown()
            }
            return true
        case .otherMouseUp:
            guard activeMouseButtonNumber == buttonNumber else { return false }
            activeMouseButtonNumber = nil
            if triggerMode == .tap {
                onUp()
                return true
            }
            guard isKeyDown else { return true }
            isKeyDown = false
            onUp()
            return true
        default:
            return false
        }
    }

    private func handleMouseCustomPasteHotkey(
        type: CGEventType,
        buttonNumber: Int,
        flags: CGEventFlags,
        hotkey: HotkeyPreference.Hotkey,
        distinguishModifierSides: Bool
    ) -> Bool {
        guard mouseHotkey(hotkey, matchesButtonNumber: buttonNumber, flags: flags, distinguishModifierSides: distinguishModifierSides) else {
            return false
        }
        switch type {
        case .otherMouseDown:
            isCustomPasteKeyDown = true
            activeCustomPasteMouseButtonNumber = buttonNumber
            return true
        case .otherMouseUp:
            guard isCustomPasteKeyDown, activeCustomPasteMouseButtonNumber == buttonNumber else { return false }
            isCustomPasteKeyDown = false
            activeCustomPasteMouseButtonNumber = nil
            emitCustomPasteKeyDown()
            return true
        default:
            return false
        }
    }

    private func mouseHotkey(
        _ hotkey: HotkeyPreference.Hotkey,
        matchesButtonNumber buttonNumber: Int,
        flags: CGEventFlags,
        distinguishModifierSides: Bool
    ) -> Bool {
        guard hotkey.mouseButtonNumber == buttonNumber else { return false }
        return HotkeyPreference.hotkeyMatches(
            hotkey,
            eventFlags: flags,
            sidedModifiers: currentSidedModifiers,
            distinguishModifierSides: distinguishModifierSides
        )
    }

    private func resolvedSidedModifiers(
        forModifierKeyCode keyCode: UInt16,
        flags: CGEventFlags,
        currentSidedModifiers: SidedModifierFlags
    ) -> SidedModifierFlags {
        let activeModifiers = HotkeyEventSupport.modifierFlags(from: flags)
        let eventSidedModifiers = SidedModifierFlags.from(eventFlags: flags).filtered(by: activeModifiers)
        let baseSidedModifiers = eventSidedModifiers.isEmpty ? currentSidedModifiers : eventSidedModifiers

        guard let representedModifier = SidedModifierFlags.fromModifierKeyCode(keyCode) else {
            return baseSidedModifiers.filtered(by: activeModifiers)
        }

        return SidedModifierFlags
            .updating(
                from: baseSidedModifiers,
                keyCode: keyCode,
                isPressed: activeModifiers.contains(representedModifier.modifiers)
            )
            .filtered(by: activeModifiers)
    }

    private func bindings(
        for business: RoutedHotkeyBusiness,
        configuration: HotkeyRuntimeConfiguration
    ) -> [HotkeyPreference.HotkeyBinding] {
        switch business {
        case .translation:
            return configuration.translationBindings
        case .rewrite:
            return configuration.rewriteBindings
        case .meeting:
            return configuration.meetingBindings
        case .customPaste:
            return configuration.customPasteHotkey.map {
                [HotkeyPreference.HotkeyBinding(hotkey: $0, behavior: .tap)]
            } ?? []
        case .transcription:
            return configuration.transcriptionBindings
        }
    }

    private func routedBindings(configuration: HotkeyRuntimeConfiguration) -> [RoutedHotkeyBinding] {
        RoutedHotkeyBusiness.allCases
            .flatMap { business in
                bindings(for: business, configuration: configuration).map {
                    RoutedHotkeyBinding(business: business, binding: $0)
                }
            }
            .sorted { lhs, rhs in
                let lhsBehaviorPriority = behaviorPriority(lhs.binding.behavior)
                let rhsBehaviorPriority = behaviorPriority(rhs.binding.behavior)
                if lhsBehaviorPriority != rhsBehaviorPriority {
                    return lhsBehaviorPriority < rhsBehaviorPriority
                }
                return lhs.business.priority < rhs.business.priority
            }
    }

    private func behaviorPriority(_ behavior: HotkeyPreference.TriggerBehavior) -> Int {
        switch behavior {
        case .doubleTap:
            return 0
        case .longPress:
            return 1
        case .tap:
            return 2
        }
    }

    private func handleBindingRoutedKeyboardEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isAutoRepeat: Bool,
        configuration: HotkeyRuntimeConfiguration
    ) -> Bool {
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return false }
        if type == .keyDown, !HotkeyEventSupport.isModifierKeyCode(keyCode) {
            invalidateModifierOnlyTapCandidates(for: keyCode)
        }

        for routedBinding in routedBindings(configuration: configuration) {
            let binding = routedBinding.binding
            let business = routedBinding.business
            if HotkeyModifierInterpreter.isModifierOnly(binding.hotkey) {
                if handleModifierOnlyBinding(
                    binding,
                    business: business,
                    type: type,
                    keyCode: keyCode,
                    flags: flags
                ) {
                    return true
                }
            } else if handleNonModifierKeyboardBinding(
                binding,
                business: business,
                type: type,
                keyCode: keyCode,
                flags: flags,
                isAutoRepeat: isAutoRepeat
            ) {
                return true
            }
        }

        return false
    }

    private func handleBindingRoutedMouseEvent(
        type: CGEventType,
        buttonNumber: Int,
        flags: CGEventFlags,
        configuration: HotkeyRuntimeConfiguration
    ) -> Bool {
        guard type == .otherMouseDown || type == .otherMouseUp else { return false }
        for routedBinding in routedBindings(configuration: configuration) {
            let binding = routedBinding.binding
            let business = routedBinding.business
            guard binding.hotkey.mouseButtonNumber == buttonNumber else { continue }
            guard HotkeyPreference.hotkeyMatches(
                binding.hotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: true
            ) else {
                continue
            }
            switch type {
            case .otherMouseDown:
                setActiveMouseButton(buttonNumber, for: business)
                if binding.behavior == .tap {
                    emitDown(for: business, behavior: binding.behavior)
                } else if binding.behavior == .longPress {
                    guard !isBusinessKeyDown(business) else { return true }
                    setBusinessKeyDown(true, for: business)
                    emitDown(for: business, behavior: binding.behavior)
                }
                return true
            case .otherMouseUp:
                guard activeMouseButtonNumber(for: business) == buttonNumber else { return false }
                setActiveMouseButton(nil, for: business)
                completeBindingRelease(binding, business: business)
                return true
            default:
                return false
            }
        }
        return false
    }

    private func handleNonModifierKeyboardBinding(
        _ binding: HotkeyPreference.HotkeyBinding,
        business: RoutedHotkeyBusiness,
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isAutoRepeat: Bool
    ) -> Bool {
        guard case .keyboard(let bindingKeyCode) = binding.hotkey.input else { return false }
        switch type {
        case .keyDown:
            guard keyCode == bindingKeyCode,
                  !isAutoRepeat,
                  HotkeyPreference.hotkeyMatches(
                    binding.hotkey,
                    eventFlags: flags,
                    sidedModifiers: currentSidedModifiers,
                    distinguishModifierSides: true
                  )
            else {
                return false
            }
            setActiveKeyCode(keyCode, for: business)
            switch binding.behavior {
            case .tap:
                if business != .customPaste {
                    emitDown(for: business, behavior: binding.behavior)
                }
            case .longPress:
                if !isBusinessKeyDown(business) {
                    setBusinessKeyDown(true, for: business)
                    emitDown(for: business, behavior: binding.behavior)
                }
            case .doubleTap:
                break
            }
            return true
        case .keyUp:
            guard activeKeyCode(for: business) == keyCode else { return false }
            setActiveKeyCode(nil, for: business)
            completeBindingRelease(binding, business: business)
            return true
        default:
            return false
        }
    }

    private func handleModifierOnlyBinding(
        _ binding: HotkeyPreference.HotkeyBinding,
        business: RoutedHotkeyBusiness,
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags
    ) -> Bool {
        guard type == .flagsChanged else { return false }

        let comboIsDown = HotkeyPreference.hotkeyMatches(
            binding.hotkey,
            eventFlags: flags,
            sidedModifiers: currentSidedModifiers,
            distinguishModifierSides: true
        )
        let triggerDown = HotkeyModifierInterpreter.translationTriggerDown(
            keyCode: keyCode,
            comboIsDown: comboIsDown,
            eventFlags: flags,
            translationFlags: HotkeyPreference.cgFlags(from: binding.hotkey.modifiers)
        )

        switch binding.behavior {
        case .tap, .doubleTap:
            if business == .transcription,
               !comboIsDown,
               HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode),
               shouldIgnoreNextFunctionTranscriptionRelease {
                shouldIgnoreNextFunctionTranscriptionRelease = false
                setModifierTapCandidate(false, for: business)
                setBusinessKeyDown(false, for: business)
                return true
            }

            if triggerDown && !isBusinessKeyDown(business) {
                cancelLowerPriorityTranscriptionCandidateIfNeeded(for: business)
                setBusinessKeyDown(true, for: business)
                setModifierTapCandidate(true, for: business)
                return true
            }

            if !comboIsDown, isBusinessKeyDown(business) {
                if modifierTapCandidate(for: business) {
                    completeBindingRelease(binding, business: business)
                }
                setModifierTapCandidate(false, for: business)
                setBusinessKeyDown(false, for: business)
                return true
            }
            return comboIsDown || isBusinessKeyDown(business)
        case .longPress:
            if comboIsDown && !isBusinessKeyDown(business) {
                cancelLowerPriorityTranscriptionCandidateIfNeeded(for: business)
                setBusinessKeyDown(true, for: business)
                emitDown(for: business, behavior: binding.behavior)
                return true
            }
            if !comboIsDown, isBusinessKeyDown(business) {
                setBusinessKeyDown(false, for: business)
                if business != .meeting {
                    emitUp(for: business, behavior: binding.behavior)
                }
                return true
            }
            return comboIsDown
        }
    }

    private func completeBindingRelease(
        _ binding: HotkeyPreference.HotkeyBinding,
        business: RoutedHotkeyBusiness
    ) {
        switch binding.behavior {
        case .tap:
            if business == .customPaste {
                emitDown(for: business, behavior: binding.behavior)
            } else if HotkeyModifierInterpreter.isModifierOnly(binding.hotkey) {
                emitDown(for: business, behavior: binding.behavior)
                if business != .transcription {
                    shouldIgnoreNextFunctionTranscriptionRelease = true
                }
            } else {
                emitUp(for: business, behavior: binding.behavior)
            }
        case .longPress:
            if business != .meeting {
                setBusinessKeyDown(false, for: business)
                emitUp(for: business, behavior: binding.behavior)
            }
        case .doubleTap:
            if completeDoubleTap(for: binding.id) {
                emitDown(for: business, behavior: binding.behavior)
            }
        }
    }

    private func completeDoubleTap(for bindingID: UUID) -> Bool {
        let now = Date()
        guard pendingDoubleTapBindingID == bindingID,
              let pendingDoubleTapAt,
              now.timeIntervalSince(pendingDoubleTapAt) <= NSEvent.doubleClickInterval
        else {
            pendingDoubleTapBindingID = bindingID
            pendingDoubleTapAt = now
            return false
        }
        pendingDoubleTapBindingID = nil
        self.pendingDoubleTapAt = nil
        return true
    }

    private func cancelLowerPriorityTranscriptionCandidateIfNeeded(for business: RoutedHotkeyBusiness) {
        guard business != .transcription else { return }
        hasTranscriptionModifierTapCandidate = false
        if isKeyDown {
            isKeyDown = false
        }
    }

    private func isBusinessKeyDown(_ business: RoutedHotkeyBusiness) -> Bool {
        switch business {
        case .translation:
            return isTranslationKeyDown
        case .rewrite:
            return isRewriteKeyDown
        case .meeting:
            return isMeetingKeyDown
        case .customPaste:
            return isCustomPasteKeyDown
        case .transcription:
            return isKeyDown
        }
    }

    private func setBusinessKeyDown(_ isDown: Bool, for business: RoutedHotkeyBusiness) {
        switch business {
        case .translation:
            isTranslationKeyDown = isDown
        case .rewrite:
            isRewriteKeyDown = isDown
        case .meeting:
            isMeetingKeyDown = isDown
        case .customPaste:
            isCustomPasteKeyDown = isDown
        case .transcription:
            isKeyDown = isDown
        }
    }

    private func modifierTapCandidate(for business: RoutedHotkeyBusiness) -> Bool {
        switch business {
        case .translation:
            return hasTranslationModifierTapCandidate
        case .rewrite:
            return hasRewriteModifierTapCandidate
        case .meeting:
            return hasMeetingModifierTapCandidate
        case .customPaste:
            return hasCustomPasteModifierTapCandidate
        case .transcription:
            return hasTranscriptionModifierTapCandidate
        }
    }

    private func setModifierTapCandidate(_ isCandidate: Bool, for business: RoutedHotkeyBusiness) {
        switch business {
        case .translation:
            hasTranslationModifierTapCandidate = isCandidate
        case .rewrite:
            hasRewriteModifierTapCandidate = isCandidate
        case .meeting:
            hasMeetingModifierTapCandidate = isCandidate
        case .customPaste:
            hasCustomPasteModifierTapCandidate = isCandidate
        case .transcription:
            hasTranscriptionModifierTapCandidate = isCandidate
        }
    }

    private func activeKeyCode(for business: RoutedHotkeyBusiness) -> UInt16? {
        switch business {
        case .translation:
            return activeTranslationKeyCode
        case .rewrite:
            return activeRewriteKeyCode
        case .meeting:
            return activeMeetingKeyCode
        case .customPaste:
            return activeCustomPasteKeyCode
        case .transcription:
            return activeKeyCode
        }
    }

    private func setActiveKeyCode(_ keyCode: UInt16?, for business: RoutedHotkeyBusiness) {
        switch business {
        case .translation:
            activeTranslationKeyCode = keyCode
        case .rewrite:
            activeRewriteKeyCode = keyCode
        case .meeting:
            activeMeetingKeyCode = keyCode
        case .customPaste:
            activeCustomPasteKeyCode = keyCode
        case .transcription:
            activeKeyCode = keyCode
        }
    }

    private func activeMouseButtonNumber(for business: RoutedHotkeyBusiness) -> Int? {
        switch business {
        case .translation:
            return activeTranslationMouseButtonNumber
        case .rewrite:
            return activeRewriteMouseButtonNumber
        case .meeting:
            return activeMeetingMouseButtonNumber
        case .customPaste:
            return activeCustomPasteMouseButtonNumber
        case .transcription:
            return activeMouseButtonNumber
        }
    }

    private func setActiveMouseButton(_ buttonNumber: Int?, for business: RoutedHotkeyBusiness) {
        switch business {
        case .translation:
            activeTranslationMouseButtonNumber = buttonNumber
        case .rewrite:
            activeRewriteMouseButtonNumber = buttonNumber
        case .meeting:
            activeMeetingMouseButtonNumber = buttonNumber
        case .customPaste:
            activeCustomPasteMouseButtonNumber = buttonNumber
        case .transcription:
            activeMouseButtonNumber = buttonNumber
        }
    }

    private func emitDown(for business: RoutedHotkeyBusiness, behavior: HotkeyPreference.TriggerBehavior) {
        switch business {
        case .translation:
            emitTranslationKeyDown(behavior: behavior)
        case .rewrite:
            emitRewriteKeyDown(behavior: behavior)
        case .meeting:
            emitMeetingKeyDown(behavior: behavior)
        case .customPaste:
            emitCustomPasteKeyDown()
        case .transcription:
            emitKeyDown(behavior: behavior)
        }
    }

    private func emitUp(for business: RoutedHotkeyBusiness, behavior: HotkeyPreference.TriggerBehavior) {
        switch business {
        case .translation:
            emitTranslationKeyUp(behavior: behavior)
        case .rewrite:
            emitRewriteKeyUp(behavior: behavior)
        case .meeting, .customPaste:
            break
        case .transcription:
            emitKeyUp(behavior: behavior)
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
        guard isPlainFunctionContext, flags.contains(.maskSecondaryFn) else { return }

        let hasStaleHigherPriorityState =
            isTranslationKeyDown ||
            isRewriteKeyDown ||
            isMeetingKeyDown ||
            hasTranslationModifierTapCandidate ||
            hasRewriteModifierTapCandidate ||
            hasMeetingModifierTapCandidate
        let hasStaleFunctionTapState =
            flags.contains(.maskSecondaryFn) &&
            (isKeyDown || hasTranscriptionModifierTapCandidate || sawUnexpectedModifierDuringFunctionChord)

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
        sawUnexpectedModifierDuringFunctionChord ||
        shouldIgnoreNextFunctionTranscriptionRelease ||
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
                shouldIgnoreNextFunctionTranscriptionRelease = true
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
                shouldIgnoreNextFunctionTranscriptionRelease = true
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
                shouldIgnoreNextFunctionTranscriptionRelease = true
            }
            return transition.handled
        }

        if comboIsDown && !isMeetingKeyDown {
            VoxtLog.hotkey("Hotkey detect meeting modifier combo down (longPress).")
            isMeetingKeyDown = true
            emitMeetingKeyDown()
            return true
        }
        if !comboIsDown && isMeetingKeyDown {
            VoxtLog.hotkey("Hotkey detect meeting modifier combo up (longPress).")
            isMeetingKeyDown = false
            return true
        }
        return comboIsDown
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
        rewriteHotkey: HotkeyPreference.Hotkey?,
        currentSidedModifiers: SidedModifierFlags,
        distinguishModifierSides: Bool,
        transcriptionFlags: CGEventFlags,
        translationFlags: CGEventFlags,
        rewriteFlags: CGEventFlags
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
            (rewriteHotkey.map {
                HotkeyModifierInterpreter.isModifierOnly($0) &&
                (HotkeyPreference.hotkeyMatches(
                    $0,
                    eventFlags: flags,
                    sidedModifiers: currentSidedModifiers,
                    distinguishModifierSides: distinguishModifierSides
                ) || isRewriteKeyDown)
            } ?? false) {
            VoxtLog.hotkey("Hotkey suppress transcription modifier path because higher-priority combo is active.")
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
        let isFnOnlyTranscriptionHotkey = transcriptionFlags == .maskSecondaryFn
        let activeRelevantFlags = flags.intersection([.maskSecondaryFn, .maskShift, .maskControl, .maskAlternate, .maskCommand])
        let hasUnexpectedModifiers = !activeRelevantFlags.subtracting(transcriptionFlags).isEmpty

        if triggerMode == .tap {
            // If fn-only transcription is the active tap trigger, any extra modifier joining the chord
            // invalidates that fn tap. This prevents retired or disabled combos such as fn+option
            // or fn+control from falling back to plain fn transcription on release.
            if isFnOnlyTranscriptionHotkey, flags.contains(.maskSecondaryFn), hasUnexpectedModifiers {
                if !sawUnexpectedModifierDuringFunctionChord {
                    VoxtLog.hotkey(
                        "Hotkey transcription fn-only tap invalidated because additional modifiers joined the chord. flags=\(HotkeyEventSupport.debugDescription(for: flags))"
                    )
                }
                sawUnexpectedModifierDuringFunctionChord = true
                hasTranscriptionModifierTapCandidate = false
                isKeyDown = false
            }

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
                    sawUnexpectedModifierDuringFunctionChord = false
                }
                return true
            }
            if transcriptionTriggerDown && !isKeyDown {
                if hasUnexpectedModifiers {
                    sawUnexpectedModifierDuringFunctionChord = true
                    VoxtLog.hotkey("Hotkey transcription tap ignored because unexpected modifiers are active.")
                    return true
                }
                if flags.contains(translationFlags) || flags.contains(rewriteFlags) {
                    VoxtLog.hotkey("Hotkey transcription tap ignored because higher-priority flags are active.")
                    return true
                }
                sawUnexpectedModifierDuringFunctionChord = false
                isKeyDown = true
                hasTranscriptionModifierTapCandidate = true
            }
            let isFunctionReleaseEvent =
                isFnOnlyTranscriptionHotkey &&
                keyCode == UInt16(kVK_Function) &&
                !flags.contains(.maskSecondaryFn)
            if isFunctionReleaseEvent && !isKeyDown {
                if shouldIgnoreNextFunctionTranscriptionRelease {
                    VoxtLog.hotkey("Hotkey transcription fn-only release ignored after higher-priority modifier tap.")
                    shouldIgnoreNextFunctionTranscriptionRelease = false
                    sawNonModifierKeyDuringFunctionChord = false
                    sawUnexpectedModifierDuringFunctionChord = false
                    return true
                }
                if !sawNonModifierKeyDuringFunctionChord,
                   !sawUnexpectedModifierDuringFunctionChord,
                   !hasUnexpectedModifiers,
                   !isTranslationKeyDown,
                   !isRewriteKeyDown {
                    VoxtLog.hotkey("Hotkey transcription fn-only tap confirmed on release without non-modifier key.")
                    emitKeyDown()
                } else {
                    VoxtLog.hotkey(
                        "Hotkey transcription fn-only release ignored. sawNonModifier=\(sawNonModifierKeyDuringFunctionChord), sawUnexpectedModifier=\(sawUnexpectedModifierDuringFunctionChord), hasUnexpectedModifiers=\(hasUnexpectedModifiers), isTranslationKeyDown=\(isTranslationKeyDown), isRewriteKeyDown=\(isRewriteKeyDown)"
                    )
                }
                sawNonModifierKeyDuringFunctionChord = false
                sawUnexpectedModifierDuringFunctionChord = false
                return true
            }
            if !comboIsDown && isKeyDown {
                if hasTranscriptionModifierTapCandidate && !hasUnexpectedModifiers && !sawUnexpectedModifierDuringFunctionChord {
                    VoxtLog.hotkey("Hotkey transcription modifier tap confirmed on release.")
                    emitKeyDown()
                } else if hasTranscriptionModifierTapCandidate {
                    VoxtLog.hotkey("Hotkey transcription modifier tap canceled because unexpected modifiers remained active.")
                }
                hasTranscriptionModifierTapCandidate = false
                isKeyDown = false
                if keyCode == UInt16(kVK_Function), !flags.contains(.maskSecondaryFn) {
                    sawNonModifierKeyDuringFunctionChord = false
                    sawUnexpectedModifierDuringFunctionChord = false
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
        scheduleLongPressRelease(
            task: \.pendingTranslationLongPressReleaseTask,
            isKeyDown: \.isTranslationKeyDown
        ) { manager in
            manager.emitTranslationKeyUp()
        }
    }

    private func cancelPendingTranslationLongPressRelease() {
        cancelPendingLongPressRelease(task: \.pendingTranslationLongPressReleaseTask)
    }

    private func scheduleRewriteLongPressRelease() {
        scheduleLongPressRelease(
            task: \.pendingRewriteLongPressReleaseTask,
            isKeyDown: \.isRewriteKeyDown
        ) { manager in
            manager.emitRewriteKeyUp()
        }
    }

    private func cancelPendingRewriteLongPressRelease() {
        cancelPendingLongPressRelease(task: \.pendingRewriteLongPressReleaseTask)
    }

    private func scheduleTranscriptionLongPressRelease() {
        scheduleLongPressRelease(
            task: \.pendingTranscriptionLongPressReleaseTask,
            isKeyDown: \.isKeyDown
        ) { manager in
            manager.emitKeyUp()
        }
    }

    private func cancelPendingTranscriptionLongPressRelease() {
        cancelPendingLongPressRelease(task: \.pendingTranscriptionLongPressReleaseTask)
    }

    private func scheduleLongPressRelease(
        task taskKeyPath: ReferenceWritableKeyPath<HotkeyManager, Task<Void, Never>?>,
        isKeyDown isKeyDownKeyPath: ReferenceWritableKeyPath<HotkeyManager, Bool>,
        delay: Duration = .milliseconds(80),
        onRelease: @escaping @MainActor (HotkeyManager) -> Void = { _ in }
    ) {
        cancelPendingLongPressRelease(task: taskKeyPath)
        self[keyPath: taskKeyPath] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self[keyPath: isKeyDownKeyPath] else { return }
            self[keyPath: taskKeyPath] = nil
            self[keyPath: isKeyDownKeyPath] = false
            onRelease(self)
        }
    }

    private func cancelPendingLongPressRelease(
        task taskKeyPath: ReferenceWritableKeyPath<HotkeyManager, Task<Void, Never>?>
    ) {
        self[keyPath: taskKeyPath]?.cancel()
        self[keyPath: taskKeyPath] = nil
    }

    private func emitKeyDown(behavior: HotkeyPreference.TriggerBehavior = .tap) {
        let onKeyDownWithBehavior = onKeyDownWithBehavior
        let onKeyDown = onKeyDown
        dispatchHotkeyCallback {
            onKeyDownWithBehavior?(behavior)
            onKeyDown?()
        }
    }

    private func emitKeyUp(behavior: HotkeyPreference.TriggerBehavior = .tap) {
        let onKeyUpWithBehavior = onKeyUpWithBehavior
        let onKeyUp = onKeyUp
        dispatchHotkeyCallback {
            onKeyUpWithBehavior?(behavior)
            onKeyUp?()
        }
    }

    private func emitTranslationKeyDown(behavior: HotkeyPreference.TriggerBehavior = .tap) {
        let onTranslationKeyDownWithBehavior = onTranslationKeyDownWithBehavior
        let onTranslationKeyDown = onTranslationKeyDown
        dispatchHotkeyCallback {
            onTranslationKeyDownWithBehavior?(behavior)
            onTranslationKeyDown?()
        }
    }

    private func emitTranslationKeyUp(behavior: HotkeyPreference.TriggerBehavior = .tap) {
        let onTranslationKeyUpWithBehavior = onTranslationKeyUpWithBehavior
        let onTranslationKeyUp = onTranslationKeyUp
        dispatchHotkeyCallback {
            onTranslationKeyUpWithBehavior?(behavior)
            onTranslationKeyUp?()
        }
    }

    private func emitRewriteKeyDown(behavior: HotkeyPreference.TriggerBehavior = .tap) {
        let onRewriteKeyDownWithBehavior = onRewriteKeyDownWithBehavior
        let onRewriteKeyDown = onRewriteKeyDown
        dispatchHotkeyCallback {
            onRewriteKeyDownWithBehavior?(behavior)
            onRewriteKeyDown?()
        }
    }

    private func emitRewriteKeyUp(behavior: HotkeyPreference.TriggerBehavior = .tap) {
        let onRewriteKeyUpWithBehavior = onRewriteKeyUpWithBehavior
        let onRewriteKeyUp = onRewriteKeyUp
        dispatchHotkeyCallback {
            onRewriteKeyUpWithBehavior?(behavior)
            onRewriteKeyUp?()
        }
    }

    private func emitMeetingKeyDown(behavior: HotkeyPreference.TriggerBehavior = .tap) {
        let onMeetingKeyDownWithBehavior = onMeetingKeyDownWithBehavior
        let onMeetingKeyDown = onMeetingKeyDown
        dispatchHotkeyCallback {
            onMeetingKeyDownWithBehavior?(behavior)
            onMeetingKeyDown?()
        }
    }

    private func emitCustomPasteKeyDown() {
        let onCustomPasteKeyDown = onCustomPasteKeyDown
        dispatchHotkeyCallback {
            onCustomPasteKeyDown?()
        }
    }

    private func dispatchHotkeyCallback(_ callback: @escaping () -> Void) {
        if dispatchCallbacksAsynchronously {
            DispatchQueue.main.async {
                callback()
            }
        } else {
            callback()
        }
    }

    private func clearMeetingTransientState() {
        isMeetingKeyDown = false
        activeMeetingKeyCode = nil
        activeMeetingMouseButtonNumber = nil
        hasMeetingModifierTapCandidate = false
    }

    private func clearRewriteTransientState() {
        isRewriteKeyDown = false
        activeRewriteKeyCode = nil
        activeRewriteMouseButtonNumber = nil
        hasRewriteModifierTapCandidate = false
        cancelPendingRewriteLongPressRelease()
    }

    private func clearCustomPasteTransientState() {
        isCustomPasteKeyDown = false
        activeCustomPasteKeyCode = nil
        activeCustomPasteMouseButtonNumber = nil
        hasCustomPasteModifierTapCandidate = false
    }

    private func clearTransientState() {
        isKeyDown = false
        activeKeyCode = nil
        activeMouseButtonNumber = nil
        isTranslationKeyDown = false
        activeTranslationKeyCode = nil
        activeTranslationMouseButtonNumber = nil
        isRewriteKeyDown = false
        activeRewriteKeyCode = nil
        activeRewriteMouseButtonNumber = nil
        isMeetingKeyDown = false
        activeMeetingKeyCode = nil
        activeMeetingMouseButtonNumber = nil
        isCustomPasteKeyDown = false
        activeCustomPasteKeyCode = nil
        activeCustomPasteMouseButtonNumber = nil
        hasTranscriptionModifierTapCandidate = false
        hasTranslationModifierTapCandidate = false
        hasRewriteModifierTapCandidate = false
        hasMeetingModifierTapCandidate = false
        hasCustomPasteModifierTapCandidate = false
        sawNonModifierKeyDuringFunctionChord = false
        sawUnexpectedModifierDuringFunctionChord = false
        shouldIgnoreNextFunctionTranscriptionRelease = false
        currentSidedModifiers = []
        suppressTranscriptionTapUntil = .distantPast
        lastEventAt = Date()
        pendingTranscriptionLongPressReleaseTask?.cancel()
        pendingTranscriptionLongPressReleaseTask = nil
        pendingTranslationLongPressReleaseTask?.cancel()
        pendingTranslationLongPressReleaseTask = nil
        pendingRewriteLongPressReleaseTask?.cancel()
        pendingRewriteLongPressReleaseTask = nil
    }
}

#if DEBUG
extension HotkeyManager {
    struct TransientStateSnapshot: Equatable {
        let isKeyDown: Bool
        let isTranslationKeyDown: Bool
        let isRewriteKeyDown: Bool
        let isCustomPasteKeyDown: Bool
        let hasTranscriptionModifierTapCandidate: Bool
        let hasTranslationModifierTapCandidate: Bool
        let hasRewriteModifierTapCandidate: Bool
        let hasCustomPasteModifierTapCandidate: Bool
        let sawNonModifierKeyDuringFunctionChord: Bool
        let currentSidedModifiers: SidedModifierFlags
    }

    @discardableResult
    func testingHandleEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isAutoRepeat: Bool = false
    ) -> Bool {
        let previousDispatchMode = dispatchCallbacksAsynchronously
        dispatchCallbacksAsynchronously = false
        defer {
            dispatchCallbacksAsynchronously = previousDispatchMode
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            _ = recoverEventTapIfNeeded(disabledEventType: type)
            return false
        }
        var eventWasConsumed = false
        handleResolvedEvent(type: type, keyCode: keyCode, flags: flags, isAutoRepeat: isAutoRepeat, eventWasConsumed: &eventWasConsumed)
        return eventWasConsumed
    }

    @discardableResult
    func testingHandleMouseEvent(
        type: CGEventType,
        buttonNumber: Int,
        flags: CGEventFlags = []
    ) -> Bool {
        let previousDispatchMode = dispatchCallbacksAsynchronously
        dispatchCallbacksAsynchronously = false
        defer {
            dispatchCallbacksAsynchronously = previousDispatchMode
        }
        var eventWasConsumed = false
        handleResolvedMouseEvent(
            type: type,
            buttonNumber: buttonNumber,
            flags: flags,
            eventWasConsumed: &eventWasConsumed
        )
        return eventWasConsumed
    }

    @discardableResult
    func testingHandleEventUsingProductionCallbackDispatch(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isAutoRepeat: Bool = false
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            _ = recoverEventTapIfNeeded(disabledEventType: type)
            return false
        }
        var eventWasConsumed = false
        handleResolvedEvent(
            type: type,
            keyCode: keyCode,
            flags: flags,
            isAutoRepeat: isAutoRepeat,
            eventWasConsumed: &eventWasConsumed
        )
        return eventWasConsumed
    }

    func testingSetTransientState(
        isKeyDown: Bool = false,
        isTranslationKeyDown: Bool = false,
        isRewriteKeyDown: Bool = false,
        isCustomPasteKeyDown: Bool = false,
        hasTranscriptionModifierTapCandidate: Bool = false,
        hasTranslationModifierTapCandidate: Bool = false,
        hasRewriteModifierTapCandidate: Bool = false,
        hasCustomPasteModifierTapCandidate: Bool = false,
        sawNonModifierKeyDuringFunctionChord: Bool = false,
        currentSidedModifiers: SidedModifierFlags = []
    ) {
        self.isKeyDown = isKeyDown
        self.isTranslationKeyDown = isTranslationKeyDown
        self.isRewriteKeyDown = isRewriteKeyDown
        self.isCustomPasteKeyDown = isCustomPasteKeyDown
        self.hasTranscriptionModifierTapCandidate = hasTranscriptionModifierTapCandidate
        self.hasTranslationModifierTapCandidate = hasTranslationModifierTapCandidate
        self.hasRewriteModifierTapCandidate = hasRewriteModifierTapCandidate
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
            isCustomPasteKeyDown: isCustomPasteKeyDown,
            hasTranscriptionModifierTapCandidate: hasTranscriptionModifierTapCandidate,
            hasTranslationModifierTapCandidate: hasTranslationModifierTapCandidate,
            hasRewriteModifierTapCandidate: hasRewriteModifierTapCandidate,
            hasCustomPasteModifierTapCandidate: hasCustomPasteModifierTapCandidate,
            sawNonModifierKeyDuringFunctionChord: sawNonModifierKeyDuringFunctionChord,
            currentSidedModifiers: currentSidedModifiers
        )
    }
}
#endif

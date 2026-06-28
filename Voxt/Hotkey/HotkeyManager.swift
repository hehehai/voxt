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
nonisolated final class HotkeyManager: @unchecked Sendable {
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

    private struct HotkeyEventSnapshot: @unchecked Sendable {
        let type: CGEventType
        let keyCode: UInt16
        let mouseButtonNumber: Int
        let flags: CGEventFlags
        let isAutoRepeat: Bool

        init(type: CGEventType, event: CGEvent) {
            self.type = type
            keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            mouseButtonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            flags = event.flags
            isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        }
    }

    private final class EventTapRunLoop: @unchecked Sendable {
        private let condition = NSCondition()
        private var thread: Thread?
        private var runLoop: CFRunLoop?
        private var keepAliveSource: CFRunLoopSource?

        func start() -> CFRunLoop? {
            condition.lock()
            if let runLoop {
                condition.unlock()
                return runLoop
            }

            let thread = Thread { [weak self] in
                self?.run()
            }
            thread.name = "VoxtHotkeyEventTap"
            thread.qualityOfService = .userInteractive
            self.thread = thread
            thread.start()

            let deadline = Date().addingTimeInterval(1)
            while runLoop == nil, Date() < deadline {
                condition.wait(until: deadline)
            }
            let resolvedRunLoop = runLoop
            condition.unlock()
            return resolvedRunLoop
        }

        func addSource(_ source: CFRunLoopSource) -> Bool {
            guard let runLoop = start() else { return false }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopAddSource(runLoop, source, .commonModes)
            }
            CFRunLoopWakeUp(runLoop)
            return true
        }

        func removeSource(_ source: CFRunLoopSource) {
            guard let runLoop = currentRunLoop() else { return }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFRunLoopWakeUp(runLoop)
        }

        func stop() {
            guard let runLoop = currentRunLoop() else { return }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)

            condition.lock()
            let deadline = Date().addingTimeInterval(1)
            while self.runLoop != nil, Date() < deadline {
                condition.wait(until: deadline)
            }
            condition.unlock()
        }

        private func currentRunLoop() -> CFRunLoop? {
            condition.lock()
            let runLoop = runLoop
            condition.unlock()
            return runLoop
        }

        private func run() {
            var context = CFRunLoopSourceContext()
            let keepAliveSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
            let currentRunLoop = CFRunLoopGetCurrent()
            if let keepAliveSource {
                CFRunLoopAddSource(currentRunLoop, keepAliveSource, .commonModes)
            }

            condition.lock()
            runLoop = currentRunLoop
            self.keepAliveSource = keepAliveSource
            condition.broadcast()
            condition.unlock()

            CFRunLoopRun()

            if let keepAliveSource {
                CFRunLoopRemoveSource(currentRunLoop, keepAliveSource, .commonModes)
            }

            condition.lock()
            runLoop = nil
            self.keepAliveSource = nil
            thread = nil
            condition.broadcast()
            condition.unlock()
        }
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
    var onCommonStopKeyDown: (() -> Void)?
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
    private let stateLock = NSRecursiveLock()
    private let eventTapRunLoop = EventTapRunLoop()
    private let captureState: HotkeyCaptureState
    private var isKeyDown = false
    private var activeTranscriptionBehavior: HotkeyPreference.TriggerBehavior?
    private var activeKeyCode: UInt16?
    private var activeMouseButtonNumber: Int?
    private var isTranslationKeyDown = false
    private var activeTranslationBehavior: HotkeyPreference.TriggerBehavior?
    private var activeTranslationKeyCode: UInt16?
    private var activeTranslationMouseButtonNumber: Int?
    private var isRewriteKeyDown = false
    private var activeRewriteBehavior: HotkeyPreference.TriggerBehavior?
    private var activeRewriteKeyCode: UInt16?
    private var activeRewriteMouseButtonNumber: Int?
    private var isMeetingKeyDown = false
    private var activeMeetingBehavior: HotkeyPreference.TriggerBehavior?
    private var activeMeetingKeyCode: UInt16?
    private var activeMeetingMouseButtonNumber: Int?
    private var isCustomPasteKeyDown = false
    private var activeCustomPasteBehavior: HotkeyPreference.TriggerBehavior?
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
    private var shouldEmitTranscriptionTapForStaleFunctionRelease = false
    private var currentSidedModifiers: SidedModifierFlags = []
    private var suppressTranscriptionTapUntil = Date.distantPast
    private var pendingModifierOnlyLongPressDownTask: Task<Void, Never>?
    private var pendingModifierOnlyLongPressBindingID: UUID?
    private var pendingModifierOnlyLongPressBusiness: RoutedHotkeyBusiness?
    private var pendingDoubleTapBindingID: UUID?
    private var pendingDoubleTapAt: Date?
    private var isCommonStopKeyEnabled = false
    private var retryTask: Task<Void, Never>?
    private var defaultsDidChangeObserver: NSObjectProtocol?
    private var cachedConfiguration: HotkeyRuntimeConfiguration?
    private var cachedRoutedBindings: [RoutedHotkeyBinding]?
    private var dispatchCallbacksAsynchronously = true
    private let eventTapRecoveryQueue = DispatchQueue(label: "com.voxt.hotkey.eventTapRecovery")
    private let deferredEventProcessingQueue = DispatchQueue(label: "com.voxt.hotkey.deferredEventProcessing")
    private let eventTapStateLockWaitTimeout: TimeInterval = 0.015
    private var didPromptAccessibility = false
    private var didPromptInputMonitoring = false
    private var lastEventAt: Date?
    private let staleTapStateResetIdleThreshold: TimeInterval = 2.0

    init(captureState: HotkeyCaptureState = .shared) {
        self.captureState = captureState
        defaultsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            self?.withStateLock {
                self?.captureState.refreshFromDefaults()
                self?.cachedConfiguration = nil
                self?.cachedRoutedBindings = nil
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
            eventTapRunLoop.removeSource(source)
        }
        eventTapRunLoop.stop()
        eventTap = nil
        runLoopSource = nil

        pendingModifierOnlyLongPressDownTask?.cancel()
        pendingModifierOnlyLongPressDownTask = nil
        pendingModifierOnlyLongPressBindingID = nil
        pendingModifierOnlyLongPressBusiness = nil
    }

    func start() {
        withStateLock {
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

            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0),
                  eventTapRunLoop.addSource(source)
            else {
                VoxtLog.error("Failed to attach hotkey event tap to dedicated run loop.")
                CGEvent.tapEnable(tap: tap, enable: false)
                scheduleRetry()
                return
            }

            eventTap = tap
            runLoopSource = source
            CGEvent.tapEnable(tap: tap, enable: true)
            retryTask?.cancel()
            retryTask = nil
            VoxtLog.hotkey("Hotkey event tap started successfully. location=\(tapLocation.debugName), runLoop=dedicated")
        }
    }

    func stop() {
        var sourceToRemove: CFRunLoopSource?
        withStateLock {
            VoxtLog.info("Stopping hotkey manager.")
            retryTask?.cancel()
            retryTask = nil
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
            sourceToRemove = runLoopSource
            eventTap = nil
            runLoopSource = nil
            clearTransientState()
            VoxtLog.hotkey("Hotkey manager stopped.")
        }
        if let sourceToRemove {
            eventTapRunLoop.removeSource(sourceToRemove)
        }
        eventTapRunLoop.stop()
    }

    func resetTransientState(reason: String) {
        withStateLock {
            VoxtLog.hotkey("Hotkey transient state reset. reason=\(reason)")
            clearTransientState()
        }
    }

    func cancelPendingDoubleTapCandidate(reason: String) {
        withStateLock {
            guard pendingDoubleTapBindingID != nil else { return }
            pendingDoubleTapBindingID = nil
            pendingDoubleTapAt = nil
            VoxtLog.hotkey("Hotkey pending double tap canceled. reason=\(reason)")
        }
    }

    func setCommonStopKeyEnabled(_ isEnabled: Bool) {
        withStateLock {
            isCommonStopKeyEnabled = isEnabled
        }
    }

    @discardableResult
    func recoverEventTapIfNeeded(disabledEventType: CGEventType) -> EventTapRecoveryResult {
        withStateLock {
            let reason: String
            switch disabledEventType {
            case .tapDisabledByTimeout:
                reason = "tapDisabledByTimeout"
            case .tapDisabledByUserInput:
                reason = "tapDisabledByUserInput"
            default:
                reason = "unknown"
            }

            VoxtLog.hotkey("Hotkey transient state reset. reason=\(reason)")
            clearTransientState()

            guard let tap = eventTap else {
                VoxtLog.warning("Hotkey event tap disabled but no active tap is available. reason=\(reason)")
                return .unavailable
            }

            CGEvent.tapEnable(tap: tap, enable: true)
            VoxtLog.warning("Hotkey event tap re-enabled. reason=\(reason)")
            return .reenabled
        }
    }

    private func scheduleEventTapRecovery(disabledEventType: CGEventType) {
        eventTapRecoveryQueue.async { [weak self] in
            _ = self?.recoverEventTapIfNeeded(disabledEventType: disabledEventType)
        }
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
            while !Task.isCancelled, self.hasNoActiveEventTap {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self.start()
            }
        }
    }

    private var hasNoActiveEventTap: Bool {
        withStateLock {
            eventTap == nil
        }
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func withEventTapStateLock<T>(_ body: () -> T) -> T? {
        guard stateLock.lock(before: Date(timeIntervalSinceNow: eventTapStateLockWaitTimeout)) else {
            return nil
        }
        defer { stateLock.unlock() }
        return body()
    }

    private func runtimeConfiguration() -> HotkeyRuntimeConfiguration {
        if let cachedConfiguration {
            return cachedConfiguration
        }
        let configuration = HotkeyRuntimeConfiguration.load()
        cachedConfiguration = configuration
        cachedRoutedBindings = nil
        return configuration
    }

    private func createEventTap(eventMask: CGEventMask) -> (tap: CFMachPort, location: CGEventTapLocation)? {
        let callback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                manager.scheduleEventTapRecovery(disabledEventType: type)
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
        let snapshot = HotkeyEventSnapshot(type: type, event: event)
        if let consumed = withEventTapStateLock({
            handleEventSnapshot(snapshot)
        }) {
            return consumed
        }

        scheduleDeferredEventHandling(snapshot)
        return false
    }

    private func scheduleDeferredEventHandling(_ snapshot: HotkeyEventSnapshot) {
        deferredEventProcessingQueue.async { [weak self] in
            self?.withStateLock {
                guard self?.eventTap != nil else { return }
                _ = self?.handleEventSnapshot(snapshot)
            }
        }
    }

    private func handleEventSnapshot(_ snapshot: HotkeyEventSnapshot) -> Bool {
        guard !captureState.isCaptureInProgress else {
            return false
        }
        var eventWasConsumed = false
        switch snapshot.type {
        case .otherMouseDown, .otherMouseUp:
            handleResolvedMouseEvent(
                type: snapshot.type,
                buttonNumber: snapshot.mouseButtonNumber,
                flags: snapshot.flags,
                eventWasConsumed: &eventWasConsumed
            )
        default:
            handleResolvedEvent(
                type: snapshot.type,
                keyCode: snapshot.keyCode,
                flags: snapshot.flags,
                isAutoRepeat: snapshot.isAutoRepeat,
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
        let activeMeetingHotkey = configuration.meetingHotkey
        let activeCustomPasteHotkey = configuration.customPasteHotkey
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

        if activeMeetingHotkey == nil {
            clearMeetingTransientState()
        }
        if activeCustomPasteHotkey == nil {
            clearCustomPasteTransientState()
        }
        if configuration.rewriteBindings.isEmpty {
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

        if type == .keyDown,
           keyCode == UInt16(kVK_Escape),
           !isAutoRepeat {
            let onEscapeKeyDown = onEscapeKeyDown
            if dispatchCallbacksAsynchronously {
                dispatchHotkeyCallback {
                    _ = onEscapeKeyDown?()
                }
            } else if onEscapeKeyDown?() == true {
                eventWasConsumed = true
            }
            return
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

        if activeCustomPasteHotkeyIsDisabled(configuration.customPasteHotkey) {
            clearCustomPasteTransientState()
        }
        if configuration.rewriteBindings.isEmpty {
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
    }

    private func activeCustomPasteHotkeyIsDisabled(_ hotkey: HotkeyPreference.Hotkey?) -> Bool {
        hotkey == nil
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
        if let cachedRoutedBindings {
            return cachedRoutedBindings
        }

        let resolvedBindings = RoutedHotkeyBusiness.allCases
            .flatMap { business in
                bindings(for: business, configuration: configuration).map {
                    RoutedHotkeyBinding(business: business, binding: $0)
                }
            }
            .sorted { lhs, rhs in
                let lhsSpecificity = hotkeySpecificity(lhs.binding.hotkey)
                let rhsSpecificity = hotkeySpecificity(rhs.binding.hotkey)
                if lhsSpecificity != rhsSpecificity {
                    return lhsSpecificity > rhsSpecificity
                }
                let lhsBehaviorPriority = behaviorPriority(lhs.binding.behavior)
                let rhsBehaviorPriority = behaviorPriority(rhs.binding.behavior)
                if lhsBehaviorPriority != rhsBehaviorPriority {
                    return lhsBehaviorPriority < rhsBehaviorPriority
                }
                return lhs.business.priority < rhs.business.priority
            }
        cachedRoutedBindings = resolvedBindings
        return resolvedBindings
    }

    private func hotkeySpecificity(_ hotkey: HotkeyPreference.Hotkey) -> Int {
        var score = modifierSpecificity(hotkey.modifiers)
        if !hotkey.sidedModifiers.isEmpty {
            score += sidedModifierSpecificity(hotkey.sidedModifiers)
        }
        if !HotkeyModifierInterpreter.isModifierOnly(hotkey) {
            score += 100
        }
        return score
    }

    private func modifierSpecificity(_ modifiers: NSEvent.ModifierFlags) -> Int {
        var score = 0
        if modifiers.contains(.function) { score += 10 }
        if modifiers.contains(.shift) { score += 10 }
        if modifiers.contains(.control) { score += 10 }
        if modifiers.contains(.option) { score += 10 }
        if modifiers.contains(.command) { score += 10 }
        return score
    }

    private func sidedModifierSpecificity(_ sidedModifiers: SidedModifierFlags) -> Int {
        var score = 0
        if sidedModifiers.contains(.leftShift) { score += 1 }
        if sidedModifiers.contains(.rightShift) { score += 1 }
        if sidedModifiers.contains(.leftControl) { score += 1 }
        if sidedModifiers.contains(.rightControl) { score += 1 }
        if sidedModifiers.contains(.leftOption) { score += 1 }
        if sidedModifiers.contains(.rightOption) { score += 1 }
        if sidedModifiers.contains(.leftCommand) { score += 1 }
        if sidedModifiers.contains(.rightCommand) { score += 1 }
        return score
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

        let routedBindings = routedBindings(configuration: configuration)
        if handleActiveModifierOnlyLongPressRelease(
            type: type,
            flags: flags,
            routedBindings: routedBindings,
            distinguishModifierSides: configuration.distinguishModifierSides
        ) {
            return true
        }

        for routedBinding in routedBindings {
            let binding = routedBinding.binding
            let business = routedBinding.business
            if HotkeyModifierInterpreter.isModifierOnly(binding.hotkey) {
                if handleModifierOnlyBinding(
                    binding,
                    business: business,
                    type: type,
                    keyCode: keyCode,
                    flags: flags,
                    allRoutedBindings: routedBindings,
                    distinguishModifierSides: configuration.distinguishModifierSides
                ) {
                    return true
                }
            } else if handleNonModifierKeyboardBinding(
                binding,
                business: business,
                type: type,
                keyCode: keyCode,
                flags: flags,
                isAutoRepeat: isAutoRepeat,
                distinguishModifierSides: configuration.distinguishModifierSides
            ) {
                return true
            }
        }

        return false
    }

    private func handleActiveModifierOnlyLongPressRelease(
        type: CGEventType,
        flags: CGEventFlags,
        routedBindings: [RoutedHotkeyBinding],
        distinguishModifierSides: Bool
    ) -> Bool {
        guard type == .flagsChanged else { return false }

        for routedBinding in routedBindings {
            let binding = routedBinding.binding
            let business = routedBinding.business
            guard binding.behavior == .longPress,
                  HotkeyModifierInterpreter.isModifierOnly(binding.hotkey),
                  activeBehavior(for: business) == .longPress,
                  isBusinessKeyDown(business),
                  activeKeyCode(for: business) == nil,
                  activeMouseButtonNumber(for: business) == nil
            else {
                continue
            }

            let comboIsDown = HotkeyPreference.hotkeyMatches(
                binding.hotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: distinguishModifierSides
            )
            guard !comboIsDown else { continue }

            let wasPending = pendingModifierOnlyLongPressBindingID == binding.id
            cancelPendingModifierOnlyLongPressDown(except: nil, resetKeyState: false)
            setBusinessKeyDown(false, for: business)
            if business != .meeting, !wasPending {
                emitUp(for: business, behavior: binding.behavior)
            }
            emitCommonStopIfNeeded(for: binding, business: business)
            setActiveBehavior(nil, for: business)
            return true
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
            if type == .otherMouseUp, activeMouseButtonNumber(for: business) == buttonNumber {
                setActiveMouseButton(nil, for: business)
                if business == .customPaste, binding.behavior == .tap {
                    setActiveBehavior(nil, for: business)
                    return true
                }
                completeBindingRelease(binding, business: business)
                return true
            }
            guard HotkeyPreference.hotkeyMatches(
                binding.hotkey,
                eventFlags: flags,
                sidedModifiers: currentSidedModifiers,
                distinguishModifierSides: configuration.distinguishModifierSides
            ) else {
                continue
            }
            switch type {
            case .otherMouseDown:
                setActiveMouseButton(buttonNumber, for: business)
                setActiveBehavior(binding.behavior, for: business)
                if binding.behavior == .tap {
                    emitDown(for: business, behavior: binding.behavior)
                } else if binding.behavior == .longPress {
                    guard !isBusinessKeyDown(business) else { return true }
                    setBusinessKeyDown(true, for: business)
                    emitDown(for: business, behavior: binding.behavior)
                }
                return true
            case .otherMouseUp:
                return false
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
        isAutoRepeat: Bool,
        distinguishModifierSides: Bool
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
                    distinguishModifierSides: distinguishModifierSides
                  )
            else {
                return false
            }
            setActiveKeyCode(keyCode, for: business)
            setActiveBehavior(binding.behavior, for: business)
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
        flags: CGEventFlags,
        allRoutedBindings: [RoutedHotkeyBinding],
        distinguishModifierSides: Bool
    ) -> Bool {
        guard type == .flagsChanged else { return false }

        let comboIsDown = HotkeyPreference.hotkeyMatches(
            binding.hotkey,
            eventFlags: flags,
            sidedModifiers: currentSidedModifiers,
            distinguishModifierSides: distinguishModifierSides
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
               binding.behavior == .tap,
               !comboIsDown,
               HotkeyPreference.cgFlags(from: binding.hotkey.modifiers) == .maskSecondaryFn,
               HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode),
               shouldEmitTranscriptionTapForStaleFunctionRelease {
                shouldEmitTranscriptionTapForStaleFunctionRelease = false
                emitDown(for: business, behavior: binding.behavior)
                return true
            }

            if business == .transcription,
               !comboIsDown,
               HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode),
               shouldIgnoreNextFunctionTranscriptionRelease {
                shouldIgnoreNextFunctionTranscriptionRelease = false
                setModifierTapCandidate(false, for: business)
                setBusinessKeyDown(false, for: business)
                return true
            }

            if triggerDown,
               !isBusinessKeyDown(business),
               !modifierTapCandidate(for: business) {
                cancelPendingModifierOnlyLongPressDown(except: binding.id, resetKeyState: true)
                cancelLowerPriorityTranscriptionCandidateIfNeeded(for: business)
                setActiveBehavior(binding.behavior, for: business)
                setModifierTapCandidate(true, for: business)
                if binding.behavior == .tap {
                    setBusinessKeyDown(true, for: business)
                }
                return true
            }

            if binding.behavior == .doubleTap,
               !comboIsDown,
               modifierTapCandidate(for: business) {
                completeBindingRelease(binding, business: business)
                setModifierTapCandidate(false, for: business)
                setActiveBehavior(nil, for: business)
                return true
            }

            if !comboIsDown, isBusinessKeyDown(business) {
                if modifierTapCandidate(for: business) {
                    completeBindingRelease(binding, business: business)
                }
                setModifierTapCandidate(false, for: business)
                setBusinessKeyDown(false, for: business)
                setActiveBehavior(nil, for: business)
                return true
            }
            return comboIsDown || isBusinessKeyDown(business)
        case .longPress:
            if comboIsDown && !isBusinessKeyDown(business) {
                cancelLowerPriorityTranscriptionCandidateIfNeeded(for: business)
                setBusinessKeyDown(true, for: business)
                setActiveBehavior(binding.behavior, for: business)
                if hasMoreSpecificModifierOnlyBinding(
                    than: binding,
                    in: allRoutedBindings,
                    distinguishModifierSides: distinguishModifierSides
                ) {
                    scheduleModifierOnlyLongPressDown(binding: binding, business: business)
                } else {
                    cancelPendingModifierOnlyLongPressDown(except: binding.id, resetKeyState: true)
                    emitDown(for: business, behavior: binding.behavior)
                }
                return true
            }
            if !comboIsDown, isBusinessKeyDown(business) {
                let wasPending = pendingModifierOnlyLongPressBindingID == binding.id
                cancelPendingModifierOnlyLongPressDown(except: nil, resetKeyState: false)
                setBusinessKeyDown(false, for: business)
                if business != .meeting, !wasPending {
                    emitUp(for: business, behavior: binding.behavior)
                }
                emitCommonStopIfNeeded(for: binding, business: business)
                setActiveBehavior(nil, for: business)
                return true
            }
            return comboIsDown
        }
    }

    private func hasMoreSpecificModifierOnlyBinding(
        than binding: HotkeyPreference.HotkeyBinding,
        in routedBindings: [RoutedHotkeyBinding],
        distinguishModifierSides: Bool
    ) -> Bool {
        routedBindings.contains {
            $0.binding.id != binding.id &&
            modifierOnlyHotkey(
                $0.binding.hotkey,
                isMoreSpecificThan: binding.hotkey,
                distinguishModifierSides: distinguishModifierSides
            )
        }
    }

    private func modifierOnlyHotkey(
        _ candidate: HotkeyPreference.Hotkey,
        isMoreSpecificThan base: HotkeyPreference.Hotkey,
        distinguishModifierSides: Bool
    ) -> Bool {
        guard HotkeyModifierInterpreter.isModifierOnly(candidate),
              HotkeyModifierInterpreter.isModifierOnly(base),
              candidate.modifiers.intersection(base.modifiers) == base.modifiers
        else {
            return false
        }

        if distinguishModifierSides, !base.sidedModifiers.isEmpty {
            guard candidate.sidedModifiers.isSuperset(of: base.sidedModifiers) else { return false }
        }

        if candidate.modifiers != base.modifiers {
            return true
        }

        guard distinguishModifierSides else { return false }
        return candidate.sidedModifiers.isStrictSuperset(of: base.sidedModifiers)
    }

    private func scheduleModifierOnlyLongPressDown(
        binding: HotkeyPreference.HotkeyBinding,
        business: RoutedHotkeyBusiness
    ) {
        cancelPendingModifierOnlyLongPressDown(except: binding.id, resetKeyState: true)
        pendingModifierOnlyLongPressBindingID = binding.id
        pendingModifierOnlyLongPressBusiness = business
        pendingModifierOnlyLongPressDownTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            guard let self else { return }
            self.withStateLock {
                guard self.pendingModifierOnlyLongPressBindingID == binding.id,
                      self.isBusinessKeyDown(business)
                else {
                    return
                }
                self.pendingModifierOnlyLongPressDownTask = nil
                self.pendingModifierOnlyLongPressBindingID = nil
                self.pendingModifierOnlyLongPressBusiness = nil
                self.emitDown(for: business, behavior: binding.behavior)
            }
        }
    }

    private func cancelPendingModifierOnlyLongPressDown(
        except bindingID: UUID?,
        resetKeyState: Bool
    ) {
        guard let pendingModifierOnlyLongPressBindingID,
              pendingModifierOnlyLongPressBindingID != bindingID
        else {
            return
        }

        let business = pendingModifierOnlyLongPressBusiness
        pendingModifierOnlyLongPressDownTask?.cancel()
        pendingModifierOnlyLongPressDownTask = nil
        self.pendingModifierOnlyLongPressBindingID = nil
        pendingModifierOnlyLongPressBusiness = nil

        if resetKeyState, let business {
            setBusinessKeyDown(false, for: business)
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
                if !emitCommonStopIfNeeded(for: binding, business: business) {
                    emitDown(for: business, behavior: binding.behavior)
                }
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
            emitCommonStopIfNeeded(for: binding, business: business)
        case .doubleTap:
            emitCommonStopIfNeeded(for: binding, business: business)
            if completeDoubleTap(for: binding.id) {
                emitDown(for: business, behavior: binding.behavior)
            }
        }
        setActiveBehavior(nil, for: business)
    }

    @discardableResult
    private func emitCommonStopIfNeeded(
        for binding: HotkeyPreference.HotkeyBinding,
        business: RoutedHotkeyBusiness
    ) -> Bool {
        guard business == .transcription,
              HotkeyModifierInterpreter.isModifierOnly(binding.hotkey),
              isCommonStopKeyEnabled
        else {
            return false
        }
        emitCommonStopKeyDown()
        return true
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
        let hadPendingTranscriptionDown =
            pendingModifierOnlyLongPressBusiness == .transcription &&
            pendingModifierOnlyLongPressBindingID != nil
        cancelPendingModifierOnlyLongPressDown(except: nil, resetKeyState: false)
        hasTranscriptionModifierTapCandidate = false
        if isKeyDown {
            if activeTranscriptionBehavior == .longPress, !hadPendingTranscriptionDown {
                emitKeyUp(behavior: .longPress)
            }
            isKeyDown = false
        }
        activeTranscriptionBehavior = nil
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

    private func setActiveBehavior(_ behavior: HotkeyPreference.TriggerBehavior?, for business: RoutedHotkeyBusiness) {
        switch business {
        case .translation:
            activeTranslationBehavior = behavior
        case .rewrite:
            activeRewriteBehavior = behavior
        case .meeting:
            activeMeetingBehavior = behavior
        case .customPaste:
            activeCustomPasteBehavior = behavior
        case .transcription:
            activeTranscriptionBehavior = behavior
        }
    }

    private func activeBehavior(for business: RoutedHotkeyBusiness) -> HotkeyPreference.TriggerBehavior? {
        switch business {
        case .translation:
            return activeTranslationBehavior
        case .rewrite:
            return activeRewriteBehavior
        case .meeting:
            return activeMeetingBehavior
        case .customPaste:
            return activeCustomPasteBehavior
        case .transcription:
            return activeTranscriptionBehavior
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

        let shouldRecoverFunctionRelease =
            HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode) &&
            !incomingFlags.contains(.maskSecondaryFn)
        resetTransientState(
            reason: "idleGapRecovery gapMs=\(Int(idleDuration * 1000)) keyCode=\(keyCode) flags=\(HotkeyEventSupport.debugDescription(for: incomingFlags))"
        )
        shouldEmitTranscriptionTapForStaleFunctionRelease = shouldRecoverFunctionRelease
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
        if hasTranscriptionModifierTapCandidate || hasTranslationModifierTapCandidate || hasRewriteModifierTapCandidate || hasMeetingModifierTapCandidate {
            VoxtLog.hotkey("Hotkey invalidated modifier-only tap candidate because non-modifier key went down. keyCode=\(keyCode)")
        }
        cancelPendingTranscriptionTap(resetKeyState: true)
        cancelPendingTranslationTap(resetKeyState: true)
        cancelPendingRewriteTap(resetKeyState: true)
        hasTranscriptionModifierTapCandidate = false
        hasTranslationModifierTapCandidate = false
        hasRewriteModifierTapCandidate = false
        hasMeetingModifierTapCandidate = false
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

    private func emitCommonStopKeyDown() {
        let onCommonStopKeyDown = onCommonStopKeyDown
        dispatchHotkeyCallback {
            onCommonStopKeyDown?()
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
        activeMeetingBehavior = nil
        activeMeetingKeyCode = nil
        activeMeetingMouseButtonNumber = nil
        hasMeetingModifierTapCandidate = false
    }

    private func clearRewriteTransientState() {
        isRewriteKeyDown = false
        activeRewriteBehavior = nil
        activeRewriteKeyCode = nil
        activeRewriteMouseButtonNumber = nil
        hasRewriteModifierTapCandidate = false
    }

    private func clearCustomPasteTransientState() {
        isCustomPasteKeyDown = false
        activeCustomPasteBehavior = nil
        activeCustomPasteKeyCode = nil
        activeCustomPasteMouseButtonNumber = nil
        hasCustomPasteModifierTapCandidate = false
    }

    private func clearTransientState() {
        isKeyDown = false
        activeTranscriptionBehavior = nil
        activeKeyCode = nil
        activeMouseButtonNumber = nil
        isTranslationKeyDown = false
        activeTranslationBehavior = nil
        activeTranslationKeyCode = nil
        activeTranslationMouseButtonNumber = nil
        isRewriteKeyDown = false
        activeRewriteBehavior = nil
        activeRewriteKeyCode = nil
        activeRewriteMouseButtonNumber = nil
        isMeetingKeyDown = false
        activeMeetingBehavior = nil
        activeMeetingKeyCode = nil
        activeMeetingMouseButtonNumber = nil
        isCustomPasteKeyDown = false
        activeCustomPasteBehavior = nil
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
        shouldEmitTranscriptionTapForStaleFunctionRelease = false
        currentSidedModifiers = []
        suppressTranscriptionTapUntil = .distantPast
        lastEventAt = Date()
        pendingModifierOnlyLongPressDownTask?.cancel()
        pendingModifierOnlyLongPressDownTask = nil
        pendingModifierOnlyLongPressBindingID = nil
        pendingModifierOnlyLongPressBusiness = nil
        isCommonStopKeyEnabled = false
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
        withStateLock {
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
    }

    @discardableResult
    func testingHandleMouseEvent(
        type: CGEventType,
        buttonNumber: Int,
        flags: CGEventFlags = []
    ) -> Bool {
        withStateLock {
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
    }

    @discardableResult
    func testingHandleEventUsingProductionCallbackDispatch(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isAutoRepeat: Bool = false
    ) -> Bool {
        withStateLock {
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
        withStateLock {
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

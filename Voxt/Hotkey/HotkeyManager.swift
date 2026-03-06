import Foundation
import Carbon
import AppKit
import ApplicationServices

/// Monitors a global hotkey via a CGEvent tap.
/// - Press and hold hotkey key  → calls `onKeyDown`
/// - Release hotkey key         → calls `onKeyUp`
@MainActor
class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onTranslationKeyDown: (() -> Void)?
    var onTranslationKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    private var activeKeyCode: UInt16?
    private var isTranslationKeyDown = false
    private var activeTranslationKeyCode: UInt16?
    private var suppressTranscriptionTapUntil = Date.distantPast
    private var pendingTranscriptionTapTask: Task<Void, Never>?
    private var pendingTranscriptionLongPressReleaseTask: Task<Void, Never>?
    private var pendingTranslationLongPressReleaseTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var didPromptAccessibility = false
    private var didPromptInputMonitoring = false

    func start() {
        if eventTap != nil {
            return
        }
        VoxtLog.info("Starting hotkey manager.")
        guard preflightAndPromptPermissionsIfNeeded() else {
            scheduleRetry()
            return
        }
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
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
        VoxtLog.info("Hotkey event tap started successfully.")
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
        isKeyDown = false
        activeKeyCode = nil
        isTranslationKeyDown = false
        activeTranslationKeyCode = nil
        pendingTranscriptionTapTask?.cancel()
        pendingTranscriptionTapTask = nil
        pendingTranscriptionLongPressReleaseTask?.cancel()
        pendingTranscriptionLongPressReleaseTask = nil
        pendingTranslationLongPressReleaseTask?.cancel()
        pendingTranslationLongPressReleaseTask = nil
        VoxtLog.info("Hotkey manager stopped.")
    }

    private func preflightAndPromptPermissionsIfNeeded() -> Bool {
        let accessibilityGranted = AXIsProcessTrusted()
        let inputMonitoringGranted: Bool
        if #available(macOS 10.15, *) {
            inputMonitoringGranted = CGPreflightListenEventAccess()
        } else {
            inputMonitoringGranted = true
        }

        guard accessibilityGranted, inputMonitoringGranted else {
            if !accessibilityGranted, !didPromptAccessibility {
                didPromptAccessibility = true
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            if !inputMonitoringGranted, !didPromptInputMonitoring {
                didPromptInputMonitoring = true
                if #available(macOS 10.15, *) {
                    _ = CGRequestListenEventAccess()
                }
            }
            VoxtLog.warning("Hotkey preflight blocked. \(permissionStatusText())")
            return false
        }

        return true
    }

    private func permissionStatusText() -> String {
        let accessibility = AXIsProcessTrusted() ? "on" : "off"
        let inputMonitoring: String
        if #available(macOS 10.15, *) {
            inputMonitoring = CGPreflightListenEventAccess() ? "on" : "off"
        } else {
            inputMonitoring = "on"
        }
        return "permissions: accessibility=\(accessibility), inputMonitoring=\(inputMonitoring)"
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

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let transcriptionHotkey = HotkeyPreference.load()
        let translationHotkey = HotkeyPreference.loadTranslation()
        let triggerMode = HotkeyPreference.loadTriggerMode()
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let transcriptionFlags = cgFlags(from: transcriptionHotkey.modifiers)
        let translationFlags = cgFlags(from: translationHotkey.modifiers)
        let wasTranslationKeyDown = isTranslationKeyDown

        // Translation hotkey path (higher priority).
        if translationHotkey.keyCode == HotkeyPreference.modifierOnlyKeyCode {
            if type == .flagsChanged {
                let comboIsDown = flags.contains(translationFlags)
                let isFnOnlyHotkey = translationFlags == .maskSecondaryFn
                let isFunctionKeyEvent = keyCode == UInt16(kVK_Function)

                if triggerMode == .tap {
                    // Tap semantics:
                    // - Translation combo emits only "down" and acts as a start trigger.
                    // - Stop action is centralized to transcription hotkey tap (fn) in AppDelegate.
                    if (comboIsDown || (isFnOnlyHotkey && isFunctionKeyEvent)) && !isTranslationKeyDown {
                        VoxtLog.info("Hotkey detect translation modifier combo down (tap).")
                        cancelPendingTranscriptionTap(resetKeyState: true)
                        isTranslationKeyDown = true
                        suppressTranscriptionTapUntil = Date().addingTimeInterval(0.35)
                        emitTranslationKeyDown()
                    }
                    if !comboIsDown && isTranslationKeyDown {
                        VoxtLog.info("Hotkey detect translation modifier combo up (tap).")
                        isTranslationKeyDown = false
                        suppressTranscriptionTapUntil = Date().addingTimeInterval(0.20)
                    }
                    // Consume translation combo transitions to avoid falling through
                    // into transcription fn-only handling during release sequence.
                    if wasTranslationKeyDown != isTranslationKeyDown || comboIsDown {
                        return
                    }
                } else {
                    if comboIsDown {
                        cancelPendingTranslationLongPressRelease()
                    }
                    if comboIsDown && !isTranslationKeyDown {
                        VoxtLog.info("Hotkey detect translation modifier combo down (longPress).")
                        isTranslationKeyDown = true
                        emitTranslationKeyDown()
                    } else if !comboIsDown && isTranslationKeyDown {
                        VoxtLog.info("Hotkey detect translation modifier combo up (longPress-pending).")
                        scheduleTranslationLongPressRelease()
                    } else if isFnOnlyHotkey && isFunctionKeyEvent {
                        if isTranslationKeyDown {
                            isTranslationKeyDown = false
                            emitTranslationKeyUp()
                        } else {
                            isTranslationKeyDown = true
                            emitTranslationKeyDown()
                        }
                    }
                }
            }
        } else {
            let translationFlagsMatch = flags.contains(translationFlags)
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

        // Transcription hotkey path.
        if transcriptionHotkey.keyCode == HotkeyPreference.modifierOnlyKeyCode {
            guard type == .flagsChanged else { return }
            // If translation modifier combo is active, suppress transcription trigger.
            if translationHotkey.keyCode == HotkeyPreference.modifierOnlyKeyCode,
               flags.contains(translationFlags) || isTranslationKeyDown {
                VoxtLog.info("Hotkey suppress transcription modifier path because translation combo is active.")
                cancelPendingTranscriptionTap(resetKeyState: true)
                return
            }
            let comboIsDown = flags.contains(transcriptionFlags)
            let isFnOnlyHotkey = transcriptionFlags == .maskSecondaryFn
            let isFunctionKeyEvent = keyCode == UInt16(kVK_Function)

            if triggerMode == .tap {
                // Tap semantics for modifier-only transcription hotkey:
                // emit only "down" as a toggle signal; release transitions are ignored.
                if Date() < suppressTranscriptionTapUntil {
                    cancelPendingTranscriptionTap(resetKeyState: true)
                    if !comboIsDown && isKeyDown {
                        isKeyDown = false
                    }
                    return
                }
                let shouldDelayTap = shouldDelayTranscriptionTap(
                    transcriptionHotkey: transcriptionHotkey,
                    translationHotkey: translationHotkey,
                    transcriptionFlags: transcriptionFlags,
                    translationFlags: translationFlags
                )
                if shouldDelayTap {
                    if (comboIsDown || (isFnOnlyHotkey && isFunctionKeyEvent)) && !isKeyDown {
                        if flags.contains(translationFlags) {
                            return
                        }
                        isKeyDown = true
                        schedulePendingTranscriptionTap()
                    }
                    if !comboIsDown && isKeyDown {
                        flushPendingTranscriptionTapIfNeeded()
                        isKeyDown = false
                    }
                    return
                }
                if (comboIsDown || (isFnOnlyHotkey && isFunctionKeyEvent)) && !isKeyDown {
                    if flags.contains(translationFlags) {
                        return
                    }
                    isKeyDown = true
                    emitKeyDown()
                }
                if !comboIsDown && isKeyDown {
                    isKeyDown = false
                }
                cancelPendingTranscriptionTap(resetKeyState: false)
                return
            }

            if comboIsDown && !isKeyDown {
                cancelPendingTranscriptionLongPressRelease()
                isKeyDown = true
                emitKeyDown()
            } else if !comboIsDown && isKeyDown {
                // Long-press release is confirmed with a short delay to tolerate
                // transient flags jitter on fn/shift combinations.
                scheduleTranscriptionLongPressRelease()
            } else if isFnOnlyHotkey && isFunctionKeyEvent {
                if isKeyDown {
                    isKeyDown = false
                    emitKeyUp()
                } else {
                    isKeyDown = true
                    emitKeyDown()
                }
            }
            return
        }

        let transcriptionFlagsMatch = flags.contains(transcriptionFlags)
        switch type {
        case .keyDown:
            guard keyCode == transcriptionHotkey.keyCode, transcriptionFlagsMatch, !isAutoRepeat else { return }
            if triggerMode == .tap {
                emitKeyDown()
            } else if !isKeyDown {
                isKeyDown = true
                activeKeyCode = keyCode
                emitKeyDown()
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
            }
        default:
            break
        }
    }

    private func cgFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private func shouldDelayTranscriptionTap(
        transcriptionHotkey: HotkeyPreference.Hotkey,
        translationHotkey: HotkeyPreference.Hotkey,
        transcriptionFlags: CGEventFlags,
        translationFlags: CGEventFlags
    ) -> Bool {
        guard transcriptionHotkey.keyCode == HotkeyPreference.modifierOnlyKeyCode else { return false }
        guard translationHotkey.keyCode == HotkeyPreference.modifierOnlyKeyCode else { return false }
        guard transcriptionFlags != translationFlags else { return false }
        return translationFlags.contains(transcriptionFlags)
    }

    private func schedulePendingTranscriptionTap() {
        pendingTranscriptionTapTask?.cancel()
        pendingTranscriptionTapTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.isKeyDown, !self.isTranslationKeyDown else { return }
            self.pendingTranscriptionTapTask = nil
            self.emitKeyDown()
        }
    }

    private func flushPendingTranscriptionTapIfNeeded() {
        guard pendingTranscriptionTapTask != nil else { return }
        pendingTranscriptionTapTask?.cancel()
        pendingTranscriptionTapTask = nil
        if isKeyDown, !isTranslationKeyDown {
            emitKeyDown()
        }
    }

    private func cancelPendingTranscriptionTap(resetKeyState: Bool) {
        pendingTranscriptionTapTask?.cancel()
        pendingTranscriptionTapTask = nil
        if resetKeyState {
            isKeyDown = false
        }
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
        VoxtLog.info("Hotkey emit transcriptionDown")
        Task { @MainActor in
            onKeyDown?()
        }
    }

    private func emitKeyUp() {
        VoxtLog.info("Hotkey emit transcriptionUp")
        Task { @MainActor in
            onKeyUp?()
        }
    }

    private func emitTranslationKeyDown() {
        VoxtLog.info("Hotkey emit translationDown")
        Task { @MainActor in
            onTranslationKeyDown?()
        }
    }

    private func emitTranslationKeyUp() {
        VoxtLog.info("Hotkey emit translationUp")
        Task { @MainActor in
            onTranslationKeyUp?()
        }
    }
}

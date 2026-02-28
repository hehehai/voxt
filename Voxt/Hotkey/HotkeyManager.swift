import Foundation
import Carbon
import AppKit

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

    func start() {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            VoxtLog.error("Failed to create event tap. Grant Accessibility permission.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
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
                    if (comboIsDown || (isFnOnlyHotkey && isFunctionKeyEvent)) && !isTranslationKeyDown {
                        isTranslationKeyDown = true
                        suppressTranscriptionTapUntil = Date().addingTimeInterval(0.35)
                        emitTranslationKeyDown()
                    }
                    if !comboIsDown && isTranslationKeyDown {
                        isTranslationKeyDown = false
                        suppressTranscriptionTapUntil = Date().addingTimeInterval(0.20)
                    }
                    // Consume translation combo transitions to avoid falling through
                    // into transcription fn-only handling during release sequence.
                    if wasTranslationKeyDown != isTranslationKeyDown || comboIsDown {
                        return
                    }
                } else {
                    if comboIsDown && !isTranslationKeyDown {
                        isTranslationKeyDown = true
                        emitTranslationKeyDown()
                    } else if !comboIsDown && isTranslationKeyDown {
                        isTranslationKeyDown = false
                        emitTranslationKeyUp()
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
                return
            }
            let comboIsDown = flags.contains(transcriptionFlags)
            let isFnOnlyHotkey = transcriptionFlags == .maskSecondaryFn
            let isFunctionKeyEvent = keyCode == UInt16(kVK_Function)

            if triggerMode == .tap {
                if Date() < suppressTranscriptionTapUntil {
                    if !comboIsDown && isKeyDown {
                        isKeyDown = false
                    }
                    return
                }
                if (comboIsDown || (isFnOnlyHotkey && isFunctionKeyEvent)) && !isKeyDown {
                    isKeyDown = true
                    emitKeyDown()
                }
                if !comboIsDown && isKeyDown {
                    isKeyDown = false
                }
                return
            }

            if comboIsDown && !isKeyDown {
                isKeyDown = true
                emitKeyDown()
            } else if !comboIsDown && isKeyDown {
                isKeyDown = false
                emitKeyUp()
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

    private func emitKeyDown() {
        Task { @MainActor in
            onKeyDown?()
        }
    }

    private func emitKeyUp() {
        Task { @MainActor in
            onKeyUp?()
        }
    }

    private func emitTranslationKeyDown() {
        Task { @MainActor in
            onTranslationKeyDown?()
        }
    }

    private func emitTranslationKeyUp() {
        Task { @MainActor in
            onTranslationKeyUp?()
        }
    }
}

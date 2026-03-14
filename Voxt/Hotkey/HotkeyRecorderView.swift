import SwiftUI
import AppKit
import Carbon
import ApplicationServices

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (HotkeyPreference.Hotkey) -> Void
    let onCancelCapture: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyCaptured = { keyCode, modifiers, sidedModifiers in
            self.onCapture(.init(keyCode: keyCode, modifiers: modifiers, sidedModifiers: sidedModifiers))
        }
        view.onCancel = {
            self.isRecording = false
            self.onCancelCapture()
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.isRecording = isRecording
        UserDefaults.standard.set(isRecording, forKey: AppPreferenceKey.hotkeyCaptureInProgress)
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class KeyCaptureView: NSView {
    var onKeyCaptured: ((UInt16, NSEvent.ModifierFlags, SidedModifierFlags) -> Void)?
    var onCancel: (() -> Void)?
    var isRecording: Bool = false {
        didSet {
            guard isRecording != oldValue else { return }
            if isRecording {
                startLocalEventMonitor()
            } else {
                stopLocalEventMonitor()
            }
        }
    }
    private var currentSidedModifiers: SidedModifierFlags = []
    private var pendingModifierCaptureTask: Task<Void, Never>?
    private var localEventMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hasCapturedChordDuringCurrentRecording = false
    private var lastModifierOnlyCaptureCount = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        stopLocalEventMonitor()
        UserDefaults.standard.set(false, forKey: AppPreferenceKey.hotkeyCaptureInProgress)
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            pendingModifierCaptureTask?.cancel()
            onCancel?()
            return
        }
        pendingModifierCaptureTask?.cancel()
        hasCapturedChordDuringCurrentRecording = true
        lastModifierOnlyCaptureCount = 0
        let mods = event.modifierFlags.intersection(.hotkeyRelevant)
        onKeyCaptured?(event.keyCode, mods, currentSidedModifiers.filtered(by: mods))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }

        currentSidedModifiers = SidedModifierFlags.toggled(from: currentSidedModifiers, keyCode: event.keyCode)
        let mods = event.modifierFlags.intersection(.hotkeyRelevant)
        guard !mods.isEmpty else {
            pendingModifierCaptureTask?.cancel()
            lastModifierOnlyCaptureCount = 0
            return
        }

        let modifierOnlyKeyCodes: Set<UInt16> = [
            UInt16(kVK_Shift), UInt16(kVK_RightShift),
            UInt16(kVK_Control), UInt16(kVK_RightControl),
            UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_Function), UInt16(kVK_CapsLock)
        ]

        guard modifierOnlyKeyCodes.contains(event.keyCode) else { return }
        let capturedModifiers = mods
        let capturedSidedModifiers = currentSidedModifiers.filtered(by: mods)
        let capturedModifierCount = modifierCount(for: capturedModifiers)
        pendingModifierCaptureTask?.cancel()
        pendingModifierCaptureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard let self, !Task.isCancelled, self.isRecording else { return }
            guard !self.hasCapturedChordDuringCurrentRecording else { return }
            guard capturedModifierCount >= self.lastModifierOnlyCaptureCount else { return }
            self.lastModifierOnlyCaptureCount = capturedModifierCount
            self.onKeyCaptured?(HotkeyPreference.modifierOnlyKeyCode, capturedModifiers, capturedSidedModifiers)
        }
    }

    private func startLocalEventMonitor() {
        stopLocalEventMonitor()
        hasCapturedChordDuringCurrentRecording = false
        lastModifierOnlyCaptureCount = 0
        startEventTap()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            switch event.type {
            case .keyDown:
                self.keyDown(with: event)
                return nil
            case .flagsChanged:
                self.flagsChanged(with: event)
                return nil
            default:
                return event
            }
        }
    }

    private func stopLocalEventMonitor() {
        pendingModifierCaptureTask?.cancel()
        pendingModifierCaptureTask = nil
        hasCapturedChordDuringCurrentRecording = false
        lastModifierOnlyCaptureCount = 0
        stopEventTap()
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func startEventTap() {
        stopEventTap()
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let view = Unmanaged<KeyCaptureView>.fromOpaque(refcon).takeUnretainedValue()
                view.handleTapEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) {
        guard isRecording else { return }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            guard let nsEvent = NSEvent(cgEvent: event) else { return }
            keyDown(with: nsEvent)
        case .flagsChanged:
            currentSidedModifiers = SidedModifierFlags.toggled(from: currentSidedModifiers, keyCode: keyCode)
            let mods = modifierFlags(from: event.flags).intersection(.hotkeyRelevant)
            guard !mods.isEmpty else { return }

            let modifierOnlyKeyCodes: Set<UInt16> = [
                UInt16(kVK_Shift), UInt16(kVK_RightShift),
                UInt16(kVK_Control), UInt16(kVK_RightControl),
                UInt16(kVK_Option), UInt16(kVK_RightOption),
                UInt16(kVK_Command), UInt16(kVK_RightCommand),
                UInt16(kVK_Function), UInt16(kVK_CapsLock)
            ]

            guard modifierOnlyKeyCodes.contains(keyCode) else { return }
            let capturedSidedModifiers = currentSidedModifiers.filtered(by: mods)
            pendingModifierCaptureTask?.cancel()
            pendingModifierCaptureTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                guard let self, !Task.isCancelled, self.isRecording else { return }
                self.onKeyCaptured?(HotkeyPreference.modifierOnlyKeyCode, mods, capturedSidedModifiers)
            }
        default:
            break
        }
    }

    private func modifierFlags(from cgFlags: CGEventFlags) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if cgFlags.contains(.maskCommand) { flags.insert(.command) }
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        if cgFlags.contains(.maskControl) { flags.insert(.control) }
        if cgFlags.contains(.maskShift) { flags.insert(.shift) }
        if cgFlags.contains(.maskSecondaryFn) { flags.insert(.function) }
        return flags
    }

    private func modifierCount(for modifiers: NSEvent.ModifierFlags) -> Int {
        var count = 0
        if modifiers.contains(.command) { count += 1 }
        if modifiers.contains(.option) { count += 1 }
        if modifiers.contains(.control) { count += 1 }
        if modifiers.contains(.shift) { count += 1 }
        if modifiers.contains(.function) { count += 1 }
        return count
    }
}

import SwiftUI
import AppKit
import Carbon
import ApplicationServices
import IOKit.hid

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (HotkeyPreference.Hotkey) -> Void
    let onCancelCapture: () -> Void
    let onRecorderMessageChange: (String?) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyCaptured = { keyCode, modifiers, sidedModifiers in
            self.onCapture(.init(keyCode: keyCode, modifiers: modifiers, sidedModifiers: sidedModifiers))
        }
        view.onCancel = {
            self.isRecording = false
            self.onCancelCapture()
        }
        view.onRecorderMessageChange = onRecorderMessageChange
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onRecorderMessageChange = onRecorderMessageChange
        UserDefaults.standard.set(isRecording, forKey: AppPreferenceKey.hotkeyCaptureInProgress)
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else {
            onRecorderMessageChange(nil)
        }
    }
}

final class KeyCaptureView: NSView {
    private struct PendingModifierCapture {
        let modifiers: NSEvent.ModifierFlags
        let sidedModifiers: SidedModifierFlags
        let count: Int
    }

    var onKeyCaptured: ((UInt16, NSEvent.ModifierFlags, SidedModifierFlags) -> Void)?
    var onCancel: (() -> Void)?
    var onRecorderMessageChange: ((String?) -> Void)?
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
    private var currentModifierFlags: NSEvent.ModifierFlags = []
    private var pendingModifierCaptureTask: Task<Void, Never>?
    private var pendingModifierCapture: PendingModifierCapture?
    private var localEventMonitor: Any?
    private var hidMonitor: HotkeyRecorderHIDMonitor?
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
        VoxtLog.hotkey("Hotkey recorder keyDown. keyCode=\(event.keyCode), modifiers=\(HotkeyPreference.modifierSymbols(for: combinedModifiers(with: event.modifierFlags.intersection(.hotkeyRelevant))))")
        captureKeyDown(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.hotkeyRelevant),
            sidedModifiers: currentSidedModifiers
        )
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

        let modifiers = updateModifierFlags(
            keyCode: event.keyCode,
            rawModifiers: event.modifierFlags.intersection(.hotkeyRelevant)
        )
        updateSidedModifiers(for: event.keyCode)
        VoxtLog.hotkey("Hotkey recorder flagsChanged(local). keyCode=\(event.keyCode), modifiers=\(HotkeyPreference.modifierSymbols(for: modifiers))")
        scheduleModifierOnlyCaptureIfNeeded(keyCode: event.keyCode, modifiers: modifiers)
    }

    private func startLocalEventMonitor() {
        stopLocalEventMonitor()
        hasCapturedChordDuringCurrentRecording = false
        lastModifierOnlyCaptureCount = 0
        currentSidedModifiers = []
        currentModifierFlags = []
        pendingModifierCapture = nil
        startHIDMonitor()
        startEventTap()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if self.eventTap != nil {
                return nil
            }
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
        currentSidedModifiers = []
        currentModifierFlags = []
        pendingModifierCapture = nil
        stopHIDMonitor()
        stopEventTap()
        onRecorderMessageChange?(nil)
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func startEventTap() {
        stopEventTap()
        guard EventListeningPermissionManager.requestInputMonitoring(prompt: true) else {
            onRecorderMessageChange?("Input Monitoring is required to capture fn-based shortcuts such as fn+space reliably.")
            return
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let (tap, tapLocation) = createEventTap(eventMask: eventMask) else {
            onRecorderMessageChange?("System-reserved shortcuts such as fn+space may still be intercepted by macOS. If capture fails, disable or remap the Globe / input source shortcut in System Settings.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        VoxtLog.hotkey("Hotkey recorder event tap started. location=\(tapLocation.debugName)")
        onRecorderMessageChange?(nil)
    }

    private func startHIDMonitor() {
        stopHIDMonitor()
        let monitor = HotkeyRecorderHIDMonitor()
        monitor.onFunctionKeyChange = { [weak self] isDown in
            self?.handleHIDFunctionKeyChange(isDown: isDown)
        }
        monitor.onSpaceKeyChange = { [weak self] isDown in
            self?.handleHIDSpaceKeyChange(isDown: isDown)
        }
        monitor.start()
        hidMonitor = monitor
    }

    private func stopHIDMonitor() {
        hidMonitor?.stop()
        hidMonitor = nil
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

    private func handleHIDFunctionKeyChange(isDown: Bool) {
        guard isRecording else { return }
        if isDown {
            currentModifierFlags.insert(.function)
            VoxtLog.hotkey("Hotkey recorder hid fn down.")
            scheduleModifierOnlyCaptureIfNeeded(keyCode: UInt16(kVK_Function), modifiers: currentModifierFlags)
        } else {
            currentModifierFlags.remove(.function)
            VoxtLog.hotkey("Hotkey recorder hid fn up.")
            if currentModifierFlags.isEmpty {
                finalizePendingModifierCaptureIfNeeded(reason: "hid modifier release")
            }
        }
    }

    private func handleHIDSpaceKeyChange(isDown: Bool) {
        guard isRecording else { return }
        guard currentModifierFlags.contains(.function) else { return }
        VoxtLog.hotkey("Hotkey recorder hid space \(isDown ? "down" : "up"). modifiers=\(HotkeyPreference.modifierSymbols(for: currentModifierFlags))")
        guard isDown else { return }
        captureKeyDown(
            keyCode: UInt16(kVK_Space),
            modifiers: currentModifierFlags,
            sidedModifiers: currentSidedModifiers
        )
    }

    private func createEventTap(eventMask: CGEventMask) -> (tap: CFMachPort, location: CGEventTapLocation)? {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let view = Unmanaged<KeyCaptureView>.fromOpaque(refcon).takeUnretainedValue()
            view.handleTapEvent(type: type, event: event)
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

    private func handleTapEvent(type: CGEventType, event: CGEvent) {
        guard isRecording else { return }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            VoxtLog.hotkey("Hotkey recorder keyDown(tap). keyCode=\(keyCode), modifiers=\(HotkeyPreference.modifierSymbols(for: combinedModifiers(with: modifierFlags(from: event.flags).intersection(.hotkeyRelevant))))")
            captureKeyDown(
                keyCode: keyCode,
                modifiers: combinedModifiers(with: modifierFlags(from: event.flags).intersection(.hotkeyRelevant)),
                sidedModifiers: currentSidedModifiers
            )
        case .flagsChanged:
            let modifiers = updateModifierFlags(
                keyCode: keyCode,
                rawModifiers: modifierFlags(from: event.flags).intersection(.hotkeyRelevant)
            )
            currentSidedModifiers = SidedModifierFlags.from(eventFlags: event.flags).filtered(by: modifiers)
            VoxtLog.hotkey("Hotkey recorder flagsChanged(tap). keyCode=\(keyCode), modifiers=\(HotkeyPreference.modifierSymbols(for: modifiers))")
            scheduleModifierOnlyCaptureIfNeeded(keyCode: keyCode, modifiers: modifiers)
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

    private func updateSidedModifiers(for keyCode: UInt16) {
        guard SidedModifierFlags.sidedFlag(for: keyCode) != nil else { return }
        currentSidedModifiers = SidedModifierFlags.snapshotFromCurrentKeyState(
            filteredBy: currentModifierFlags.intersection(.hotkeyRelevant)
        )
    }

    private func captureKeyDown(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        sidedModifiers: SidedModifierFlags
    ) {
        let capturedModifiers = combinedModifiers(with: modifiers.intersection(.hotkeyRelevant))
        pendingModifierCaptureTask?.cancel()
        pendingModifierCapture = nil
        hasCapturedChordDuringCurrentRecording = true
        lastModifierOnlyCaptureCount = 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            VoxtLog.hotkey("Hotkey recorder captured chord. keyCode=\(keyCode), modifiers=\(HotkeyPreference.modifierSymbols(for: capturedModifiers))")
            self.onKeyCaptured?(keyCode, capturedModifiers, sidedModifiers.filtered(by: capturedModifiers))
        }
    }

    private func updateModifierFlags(
        keyCode: UInt16,
        rawModifiers: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        var modifiers = rawModifiers.intersection(.hotkeyRelevant)

        if currentModifierFlags.contains(.function) {
            modifiers.insert(.function)
        }

        if HotkeyModifierInterpreter.isFunctionKeyEvent(keyCode) {
            let functionIsDown = rawModifiers.contains(.function) || !currentModifierFlags.contains(.function)
            if functionIsDown {
                modifiers.insert(.function)
            } else {
                modifiers.remove(.function)
            }
        }

        currentModifierFlags = modifiers
        return modifiers
    }

    private func combinedModifiers(with rawModifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var modifiers = rawModifiers.intersection(.hotkeyRelevant)
        if currentModifierFlags.contains(.function) {
            modifiers.insert(.function)
        }
        return modifiers
    }

    private func scheduleModifierOnlyCaptureIfNeeded(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) {
        guard !modifiers.isEmpty else {
            finalizePendingModifierCaptureIfNeeded(reason: "modifier release")
            return
        }

        let modifierOnlyKeyCodes: Set<UInt16> = [
            UInt16(kVK_Shift), UInt16(kVK_RightShift),
            UInt16(kVK_Control), UInt16(kVK_RightControl),
            UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_Function), UInt16(kVK_CapsLock)
        ]

        guard modifierOnlyKeyCodes.contains(keyCode) else { return }
        let capturedModifiers = modifiers.intersection(.hotkeyRelevant)
        let capturedSidedModifiers = currentSidedModifiers.filtered(by: capturedModifiers)
        let capturedModifierCount = modifierCount(for: capturedModifiers)
        if let pendingModifierCapture, capturedModifierCount < pendingModifierCapture.count {
            return
        }
        pendingModifierCapture = PendingModifierCapture(
            modifiers: capturedModifiers,
            sidedModifiers: capturedSidedModifiers,
            count: capturedModifierCount
        )
        pendingModifierCaptureTask?.cancel()
        pendingModifierCaptureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard let self, !Task.isCancelled, self.isRecording else { return }
            guard !self.hasCapturedChordDuringCurrentRecording else {
                self.pendingModifierCapture = nil
                return
            }
            guard capturedModifierCount >= self.lastModifierOnlyCaptureCount else {
                self.pendingModifierCapture = nil
                return
            }
            self.lastModifierOnlyCaptureCount = capturedModifierCount
            self.pendingModifierCapture = nil
            VoxtLog.hotkey("Hotkey recorder captured modifier-only after hold. modifiers=\(HotkeyPreference.modifierSymbols(for: capturedModifiers))")
            self.onKeyCaptured?(HotkeyPreference.modifierOnlyKeyCode, capturedModifiers, capturedSidedModifiers)
        }
    }

    private func finalizePendingModifierCaptureIfNeeded(reason: String) {
        pendingModifierCaptureTask?.cancel()
        pendingModifierCaptureTask = nil
        defer { pendingModifierCapture = nil }
        guard let pendingModifierCapture else { return }
        guard !hasCapturedChordDuringCurrentRecording else { return }
        guard pendingModifierCapture.count >= lastModifierOnlyCaptureCount else { return }
        lastModifierOnlyCaptureCount = pendingModifierCapture.count
        VoxtLog.hotkey("Hotkey recorder captured modifier-only on \(reason). modifiers=\(HotkeyPreference.modifierSymbols(for: pendingModifierCapture.modifiers))")
        onKeyCaptured?(HotkeyPreference.modifierOnlyKeyCode, pendingModifierCapture.modifiers, pendingModifierCapture.sidedModifiers)
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

private final class HotkeyRecorderHIDMonitor {
    var onFunctionKeyChange: ((Bool) -> Void)?
    var onSpaceKeyChange: ((Bool) -> Void)?

    private var manager: IOHIDManager?

    func start() {
        stop()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchers: [[String: Int]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keypad
            ]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchers as CFArray)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, _, _, value in
                guard let context else { return }
                let monitor = Unmanaged<HotkeyRecorderHIDMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.handleInputValue(value)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            VoxtLog.hotkey("Hotkey recorder hid monitor open failed. status=\(openResult)")
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return
        }

        self.manager = manager
        VoxtLog.hotkey("Hotkey recorder hid monitor started.")
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        VoxtLog.hotkey("Hotkey recorder hid monitor stopped.")
    }

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let isDown = IOHIDValueGetIntegerValue(value) != 0

        if usagePage == 0xFF, usage == 0x03 {
            onFunctionKeyChange?(isDown)
            return
        }

        if usagePage == kHIDPage_KeyboardOrKeypad, usage == kHIDUsage_KeyboardSpacebar {
            onSpaceKeyChange?(isDown)
        }
    }
}

import SwiftUI
import AppKit
import CoreAudio

extension AppDelegate {
    private var feedbackURL: URL {
        URL(string: "https://github.com/hehehai/voxt/issues/new/choose")!
    }

    func buildMenu() {
        let menu = NSMenu()

        let dashboardItem = NSMenuItem(title: AppLocalization.localizedString("Dashboard"), action: #selector(openDashboardFromMenu), keyEquivalent: "")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let generalItem = NSMenuItem(title: AppLocalization.localizedString("General"), action: #selector(openGeneralFromMenu), keyEquivalent: ",")
        generalItem.target = self
        menu.addItem(generalItem)

        let dictionaryItem = NSMenuItem(
            title: AppLocalization.localizedString("Dictionary"),
            action: #selector(openDictionarySettings),
            keyEquivalent: ""
        )
        dictionaryItem.target = self
        menu.addItem(dictionaryItem)

        let microphoneItem = NSMenuItem(title: AppLocalization.localizedString("Microphone"), action: nil, keyEquivalent: "")
        microphoneItem.submenu = buildMicrophoneMenu()
        menu.addItem(microphoneItem)

        menu.addItem(NSMenuItem.separator())

        let checkUpdatesItem = NSMenuItem(
            title: AppLocalization.localizedString("Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        let feedbackItem = NSMenuItem(
            title: AppLocalization.localizedString("Feedback"),
            action: #selector(openFeedbackPage),
            keyEquivalent: ""
        )
        feedbackItem.target = self
        menu.addItem(feedbackItem)

        if appUpdateManager.hasUpdate, let latestVersion = appUpdateManager.latestVersion {
            let updateInfoItem = NSMenuItem(
                title: "New version: \(latestVersion)",
                action: nil,
                keyEquivalent: ""
            )
            updateInfoItem.isEnabled = false
            menu.addItem(updateInfoItem)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: AppLocalization.localizedString("Quit Voxt"), action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func buildMicrophoneMenu() -> NSMenu {
        let submenu = NSMenu()
        let resolvedSelectedUID = selectedInputDeviceUID

        let autoSwitchItem = NSMenuItem(
            title: AppLocalization.localizedString("Auto Switch"),
            action: #selector(toggleMicrophoneAutoSwitch(_:)),
            keyEquivalent: ""
        )
        autoSwitchItem.target = self
        autoSwitchItem.state = microphoneResolvedState.autoSwitchEnabled ? .on : .off
        submenu.addItem(autoSwitchItem)
        submenu.addItem(NSMenuItem.separator())

        for device in inputDevicesSnapshot {
            let item = NSMenuItem(title: device.name, action: #selector(selectMicrophoneFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = device.uid == resolvedSelectedUID ? .on : .off
            submenu.addItem(item)
        }

        if submenu.items.isEmpty {
            let emptyItem = NSMenuItem(title: AppLocalization.localizedString("No microphone available"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        }

        return submenu
    }

    func startObservingAudioInputDevices() {
        audioInputDevicesObserver = AudioInputDeviceManager.makeDevicesObserver { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshInputDevicesSnapshot(reason: "hardware change")
            }
        }
    }

    func refreshInputDevicesSnapshot(reason: String) {
        inputDevicesRefreshTask?.cancel()

        inputDevicesRefreshTask = Task { [weak self] in
            let devices = await Task.detached(priority: .utility) {
                AudioInputDeviceManager.snapshotAvailableInputDevices()
            }.value
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.applyInputDevicesSnapshot(devices, reason: reason)
            }
        }
    }

    private func applyInputDevicesSnapshot(_ devices: [AudioInputDevice], reason: String) {
        let previousDevices = inputDevicesSnapshot
        let previousSelectedUID = selectedInputDeviceUID
        inputDevicesSnapshot = devices
        let resolvedState = MicrophonePreferenceManager.syncState(
            defaults: .standard,
            availableDevices: devices,
            previousAvailableUIDs: previousDevices.isEmpty ? nil : Set(previousDevices.map(\.uid))
        )
        microphoneResolvedState = resolvedState

        let devicesChanged = previousDevices != devices
        let selectionChanged = previousSelectedUID != resolvedState.activeUID
        guard devicesChanged || selectionChanged else { return }

        if devicesChanged {
            NotificationCenter.default.post(name: .voxtAudioInputDevicesDidChange, object: nil)
        }

        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)

        VoxtLog.info(
            "Audio input snapshot refreshed. reason=\(reason), devices=\(devices.count), selected=\(resolvedState.activeUID ?? "none"), autoSwitch=\(resolvedState.autoSwitchEnabled)",
            verbose: true
        )
        buildMenu()
    }

    @objc private func checkForUpdates() {
        performAfterStatusMenuDismissal {
            VoxtLog.info("Manual update check triggered from menu.")
            self.appUpdateManager.checkForUpdatesWithUserInterface()
        }
    }

    @objc private func openFeedbackPage() {
        performAfterStatusMenuDismissal {
            VoxtLog.info("Feedback page opened from menu.")
            NSWorkspace.shared.open(self.feedbackURL)
        }
    }

    @objc private func openDashboardFromMenu() {
        performAfterStatusMenuDismissal {
            self.openMainWindow(target: SettingsNavigationTarget(tab: .report))
        }
    }

    @objc private func openGeneralFromMenu() {
        performAfterStatusMenuDismissal {
            self.openMainWindow(target: SettingsNavigationTarget(tab: .general))
        }
    }

    @objc private func openDictionarySettings() {
        performAfterStatusMenuDismissal {
            self.openMainWindow(target: SettingsNavigationTarget(tab: .dictionary))
        }
    }

    @objc private func selectMicrophoneFromMenu(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        if let device = inputDevicesSnapshot.first(where: { $0.uid == uid }) {
            VoxtLog.info("Microphone focus changed from tray menu. uid=\(uid), name=\(device.name)")
        } else {
            VoxtLog.info("Microphone focus changed from tray menu. uid=\(uid)")
        }
        microphoneResolvedState = MicrophonePreferenceManager.setFocusedDevice(
            uid: uid,
            defaults: .standard,
            availableDevices: inputDevicesSnapshot
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
        buildMenu()
    }

    @objc private func toggleMicrophoneAutoSwitch(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        VoxtLog.info("Microphone auto switch updated from tray menu. enabled=\(newValue)")
        microphoneResolvedState = MicrophonePreferenceManager.setAutoSwitchEnabled(
            newValue,
            defaults: .standard,
            availableDevices: inputDevicesSnapshot
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
        buildMenu()
    }

    func applyMicrophonePriorityOrder(_ orderedUIDs: [String]) {
        microphoneResolvedState = MicrophonePreferenceManager.reorderPriority(
            orderedUIDs: orderedUIDs,
            defaults: .standard,
            availableDevices: inputDevicesSnapshot
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
        buildMenu()
    }

    func selectMicrophoneManually(uid: String) {
        if let device = inputDevicesSnapshot.first(where: { $0.uid == uid }) {
            VoxtLog.info("Microphone focus changed. uid=\(uid), name=\(device.name)")
        } else {
            VoxtLog.info("Microphone focus changed. uid=\(uid)")
        }
        microphoneResolvedState = MicrophonePreferenceManager.setFocusedDevice(
            uid: uid,
            defaults: .standard,
            availableDevices: inputDevicesSnapshot
        )
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
        buildMenu()
    }

    func handleResolvedMicrophoneStateChange(
        from previousState: MicrophoneResolvedState,
        to newState: MicrophoneResolvedState,
        reason: String
    ) {
        guard previousState.activeUID != newState.activeUID else {
            applyPreferredInputDevice()
            return
        }

        if let activeDevice = newState.activeDevice {
            VoxtLog.info(
                "Resolved microphone changed. reason=\(reason), uid=\(activeDevice.uid), name=\(activeDevice.name), autoSwitch=\(newState.autoSwitchEnabled)"
            )
        } else {
            VoxtLog.warning("Resolved microphone cleared. reason=\(reason)")
        }

        handlePreferredInputDeviceChange(
            previousUID: previousState.activeUID,
            newUID: newState.activeUID,
            reason: reason
        )
    }

    func presentMainWindowOnLaunchIfNeeded() {
        guard LaunchPresentationPolicy.shouldPresentMainWindowOnLaunch() else { return }
        openMainWindow()
    }

    func openMainWindow() {
        openMainWindow(target: SettingsNavigationTarget(tab: .report))
    }

    func openMainWindow(target: SettingsNavigationTarget) {
        let navigationRequest = SettingsNavigationRequest(target: target)

        if let window = mainWindowController?.window {
            NotificationCenter.default.post(
                name: .voxtSettingsNavigate,
                object: nil,
                userInfo: navigationRequest.target.userInfo
            )
            if !window.isVisible {
                centerMainWindow(window)
            }
            bringWindowToFront(window)
            return
        }

        let contentView = SettingsView(
            availableDictionaryHistoryScanModels: {
                self.availableDictionaryHistoryScanModelOptions()
            },
            onIngestDictionarySuggestionsFromHistory: { request, persistSettings in
                self.startDictionaryHistorySuggestionScan(
                    request: request,
                    persistSettings: persistSettings
                )
            },
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager,
            customLLMManager: customLLMManager,
            historyStore: historyStore,
            dictionaryStore: dictionaryStore,
            dictionarySuggestionStore: dictionarySuggestionStore,
            appUpdateManager: appUpdateManager,
            initialNavigationTarget: navigationRequest.target,
            initialDisplayMode: resolvedInitialDisplayMode(for: navigationRequest.target)
        )
        .frame(width: 760, height: 560)

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Voxt"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.delegate = self
        positionWindowTrafficLightButtons(window)

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = false
        mainWindowController = controller
        controller.showWindow(nil)
        bringWindowToFront(window)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.centerMainWindow(window)
            self.bringWindowToFront(window)
        }
        scheduleTrafficLightButtonPositionUpdate(for: window)
    }

    func openMainWindow(selectTab: SettingsTab?) {
        openMainWindow(target: SettingsNavigationTarget(tab: selectTab ?? .report))
    }

    private func resolvedInitialDisplayMode(for target: SettingsNavigationTarget) -> SettingsDisplayMode {
        if OnboardingPreferenceManager.shouldPresentOnLaunch() {
            let step = OnboardingPreferenceManager.savedLastStep() ?? .language
            return .onboarding(step: step)
        }
        return .normal
    }

    private func bringWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        positionWindowTrafficLightButtons(window)
        scheduleTrafficLightButtonPositionUpdate(for: window)
    }

    private func centerMainWindow(_ window: NSWindow) {
        guard let screen = targetScreenForMainWindow(window) else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowFrame = window.frame
        let origin = CGPoint(
            x: round(visibleFrame.midX - (windowFrame.width / 2)),
            y: round(visibleFrame.midY - (windowFrame.height / 2))
        )
        window.setFrameOrigin(origin)
    }

    private func targetScreenForMainWindow(_ window: NSWindow) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let pointerScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return pointerScreen
        }

        return window.screen ?? NSScreen.main
    }

    private func performAfterStatusMenuDismissal(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            Task { @MainActor in
                action()
            }
        }
    }

    private func positionWindowTrafficLightButtons(_ window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let miniaturizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let container = closeButton.superview
        else {
            return
        }

        let leftInset: CGFloat = 22
        let topInset: CGFloat = 21
        let spacing: CGFloat = 6

        let buttonSize = closeButton.frame.size
        let y = container.bounds.height - topInset - buttonSize.height
        let closeX = leftInset
        let miniaturizeX = closeX + buttonSize.width + spacing
        let zoomX = miniaturizeX + buttonSize.width + spacing

        closeButton.translatesAutoresizingMaskIntoConstraints = true
        miniaturizeButton.translatesAutoresizingMaskIntoConstraints = true
        zoomButton.translatesAutoresizingMaskIntoConstraints = true

        closeButton.setFrameOrigin(CGPoint(x: closeX, y: y))
        miniaturizeButton.setFrameOrigin(CGPoint(x: miniaturizeX, y: y))
        zoomButton.setFrameOrigin(CGPoint(x: zoomX, y: y))
    }

    private func scheduleTrafficLightButtonPositionUpdate(for window: NSWindow) {
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.positionWindowTrafficLightButtons(window)
        }
    }

    @objc private func quit() {
        VoxtLog.info("Quit requested from menu.")
        hotkeyManager.stop()
        NSApp.terminate(nil)
    }

    func prepareMainWindowForUpdatePresentation() {
        guard let window = mainWindowController?.window else {
            mainWindowPresentationState = MainWindowPresentationState()
            return
        }

        let shouldRestore = window.isVisible && !window.isMiniaturized
        mainWindowPresentationState.shouldRestoreAfterUpdate = shouldRestore
        guard shouldRestore else { return }

        VoxtLog.info("Temporarily hiding main window before presenting update UI.")
        window.orderOut(nil)
    }

    func restoreMainWindowAfterUpdateSessionIfNeeded() {
        guard mainWindowPresentationState.shouldRestoreAfterUpdate else { return }
        mainWindowPresentationState = MainWindowPresentationState()

        guard let window = mainWindowController?.window else { return }
        VoxtLog.info("Restoring main window after update UI finished.")
        bringWindowToFront(window)
    }

    func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Permissions Required")
        alert.informativeText = String(localized: "Voxt needs Microphone access. If you use Direct Dictation, enable Speech Recognition in System Settings → Privacy & Security.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Quit"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
        }
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender == mainWindowController?.window else { return true }
        sender.orderOut(nil)
        return false
    }
}

import SwiftUI
import AppKit
import CoreAudio

extension AppDelegate {
    private var feedbackURL: URL {
        URL(string: "https://github.com/hehehai/voxt/issues/new/choose")!
    }

    func buildMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: AppLocalization.localizedString("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let reportItem = NSMenuItem(title: AppLocalization.localizedString("Report"), action: #selector(openReportSettings), keyEquivalent: "")
        reportItem.target = self
        menu.addItem(reportItem)

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
        let resolvedSelectedID = selectedInputDeviceID

        for device in inputDevicesSnapshot {
            let item = NSMenuItem(title: device.name, action: #selector(selectMicrophoneFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(device.id)
            item.state = device.id == resolvedSelectedID ? .on : .off
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
        let previousSelectedID = selectedInputDeviceID
        inputDevicesSnapshot = devices
        let resolvedSelectedID = AudioInputDeviceManager.resolvedInputDeviceID(
            from: devices,
            preferredID: previousSelectedID
        )

        let resolvedSelectedRaw = resolvedSelectedID.map(Int.init) ?? 0
        if Int(previousSelectedID ?? 0) != resolvedSelectedRaw {
            UserDefaults.standard.set(resolvedSelectedRaw, forKey: AppPreferenceKey.selectedInputDeviceID)
        }

        let devicesChanged = previousDevices != devices
        let selectionChanged = previousSelectedID != resolvedSelectedID
        guard devicesChanged || selectionChanged else { return }

        if devicesChanged {
            NotificationCenter.default.post(name: .voxtAudioInputDevicesDidChange, object: nil)
        }

        VoxtLog.info(
            "Audio input snapshot refreshed. reason=\(reason), devices=\(devices.count), selected=\(resolvedSelectedRaw)",
            verbose: true
        )
        buildMenu()
    }

    @objc private func checkForUpdates() {
        performAfterStatusMenuDismissal {
            VoxtLog.info("Manual update check triggered from menu.")
            self.appUpdateManager.checkForUpdates(source: .manual)
        }
    }

    @objc private func openFeedbackPage() {
        performAfterStatusMenuDismissal {
            VoxtLog.info("Feedback page opened from menu.")
            NSWorkspace.shared.open(self.feedbackURL)
        }
    }

    @objc private func openSettings() {
        performAfterStatusMenuDismissal {
            self.openSettingsWindow(selectTab: nil)
        }
    }

    @objc private func openReportSettings() {
        performAfterStatusMenuDismissal {
            self.openSettingsWindow(selectTab: .report)
        }
    }

    @objc private func openDictionarySettings() {
        performAfterStatusMenuDismissal {
            self.openSettingsWindow(selectTab: .dictionary)
        }
    }

    @objc private func selectMicrophoneFromMenu(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: AppPreferenceKey.selectedInputDeviceID)
        NotificationCenter.default.post(name: .voxtSelectedInputDeviceDidChange, object: nil)
    }

    func openSettingsWindow(selectTab: SettingsTab?) {
        if let window = settingsWindowController?.window {
            if let selectTab {
                NotificationCenter.default.post(
                    name: .voxtSettingsSelectTab,
                    object: nil,
                    userInfo: ["tab": selectTab.rawValue]
                )
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
            initialTab: selectTab ?? .general
        )
        .frame(width: 760, height: 560)

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.center()
        positionWindowTrafficLightButtons(window)

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = false
        settingsWindowController = controller
        controller.showWindow(nil)
        bringWindowToFront(window)
        scheduleTrafficLightButtonPositionUpdate(for: window)
    }

    private func bringWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        positionWindowTrafficLightButtons(window)
        scheduleTrafficLightButtonPositionUpdate(for: window)
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

    func prepareSettingsWindowForUpdatePresentation() {
        guard let window = settingsWindowController?.window else {
            settingsWindowPresentationState = SettingsWindowPresentationState()
            return
        }

        let shouldRestore = window.isVisible && !window.isMiniaturized
        settingsWindowPresentationState.shouldRestoreAfterUpdate = shouldRestore
        guard shouldRestore else { return }

        VoxtLog.info("Temporarily hiding settings window before presenting update UI.")
        window.orderOut(nil)
    }

    func restoreSettingsWindowAfterUpdateSessionIfNeeded() {
        guard settingsWindowPresentationState.shouldRestoreAfterUpdate else { return }
        settingsWindowPresentationState = SettingsWindowPresentationState()

        guard let window = settingsWindowController?.window else { return }
        VoxtLog.info("Restoring settings window after update UI finished.")
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

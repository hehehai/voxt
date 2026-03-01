import AppKit
import ServiceManagement

enum AppBehaviorController {
    @MainActor
    static func applyDockVisibility(showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        VoxtLog.info("Dock visibility changed: showInDock=\(showInDock)")
    }

    @MainActor
    static func setLaunchAtLogin(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            VoxtLog.warning("Launch at login is unavailable on macOS versions below 13.0.")
            return
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        VoxtLog.info("Launch at login updated: enabled=\(enabled)")
    }

    static func launchAtLoginIsEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}

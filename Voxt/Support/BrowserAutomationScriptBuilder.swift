import Foundation

enum BrowserAutomationScriptBuilder {
    static func customBrowserPermissionProbeScripts(bundleID: String, displayName: String) -> [String] {
        // Permission probes run inside Settings, where avoiding UI freezes is
        // more important than preserving runtime ordering. Try the tab-based
        // variants first because some Chromium-like browsers return faster on
        // those forms during permission checks.
        [
            "tell application id \"\(bundleID)\" to get the URL of active tab of front window",
            "tell application id \"\(bundleID)\" to get the URL of active tab of window 1",
            "tell application \"\(displayName)\" to get the URL of active tab of front window",
            "tell application id \"\(bundleID)\" to get URL of front document",
            "tell application id \"\(bundleID)\" to get URL of current tab of front window",
            "tell application \"\(displayName)\" to get URL of front document"
        ]
    }

    static func customBrowserRuntimeScripts(bundleID: String, displayName: String) -> [String] {
        // Runtime URL reads happen on the app's normal path, so keep the more
        // conservative ordering that favors the historically successful
        // front-document / current-tab forms before falling back to others.
        [
            "tell application id \"\(bundleID)\" to get URL of front document",
            "tell application id \"\(bundleID)\" to get URL of current tab of front window",
            "tell application id \"\(bundleID)\" to get the URL of active tab of front window",
            "tell application id \"\(bundleID)\" to get the URL of active tab of window 1",
            "tell application \"\(displayName)\" to get URL of front document",
            "tell application \"\(displayName)\" to get the URL of active tab of front window"
        ]
    }
}

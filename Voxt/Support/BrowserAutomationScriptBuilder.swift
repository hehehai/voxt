import Foundation

enum BrowserAutomationScriptBuilder {
    static func customBrowserPermissionProbeScripts(bundleID: String, displayName: String) -> [String] {
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

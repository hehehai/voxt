// BrowserAutomationScriptBuilder.swift
// Provides Browser Automation Script Builder for shared utilities.

import Foundation

enum BrowserAutomationScriptBuilder {
    private static let selectionJavaScript = "window.getSelection().toString()"

    /// AppleScript candidates that read the current page selection via JavaScript.
    /// Requires "Allow JavaScript from Apple Events" in the target browser.
    static func selectionScripts(bundleID: String, displayName: String?) -> [String] {
        let js = selectionJavaScript
        let name = displayName ?? bundleID
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return [
                "tell application id \"\(bundleID)\" to tell front window to do JavaScript \"\(js)\" in current tab",
                "tell application id \"\(bundleID)\" to do JavaScript \"\(js)\" in front document",
                "tell application \"\(name)\" to tell front window to do JavaScript \"\(js)\" in current tab"
            ]
        case "com.google.Chrome",
             "com.microsoft.edgemac",
             "com.brave.Browser",
             "company.thebrowser.Browser":
            return chromiumSelectionScripts(bundleID: bundleID, displayName: name, javaScript: js)
        default:
            // Custom browsers: try Chromium then Safari-style forms.
            return chromiumSelectionScripts(bundleID: bundleID, displayName: name, javaScript: js) + [
                "tell application id \"\(bundleID)\" to tell front window to do JavaScript \"\(js)\" in current tab",
                "tell application id \"\(bundleID)\" to do JavaScript \"\(js)\" in front document",
                "tell application \"\(name)\" to tell front window to do JavaScript \"\(js)\" in current tab"
            ]
        }
    }

    private static func chromiumSelectionScripts(
        bundleID: String,
        displayName: String,
        javaScript: String
    ) -> [String] {
        [
            "tell application id \"\(bundleID)\" to tell active tab of front window to execute javascript \"\(javaScript)\"",
            "tell application id \"\(bundleID)\" to tell active tab of window 1 to execute javascript \"\(javaScript)\"",
            "tell application \"\(displayName)\" to tell active tab of front window to execute javascript \"\(javaScript)\""
        ]
    }

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

import Foundation
import AppKit

struct ActionAssistantBrowserNavigationTask {
    let browserAppName: String
    let url: URL
}

struct ActionAssistantBrowserSearchTask {
    let browserAppName: String
    let query: String
}

struct ActionAssistantOpenAppTask {
    let appName: String
    let appURL: URL
}

enum ActionAssistantParsedTask {
    case browserNavigation(ActionAssistantBrowserNavigationTask)
    case browserSearch(ActionAssistantBrowserSearchTask)
    case openApp(ActionAssistantOpenAppTask)
}

enum ActionAssistantTaskParser {
    static func parseTask(from text: String) -> ActionAssistantParsedTask? {
        if let navigation = parseBrowserNavigationTask(from: text) {
            return .browserNavigation(navigation)
        }
        if let search = parseBrowserSearchTask(from: text) {
            return .browserSearch(search)
        }
        if let openApp = parseOpenAppTask(from: text) {
            return .openApp(openApp)
        }
        return nil
    }

    static func parseBrowserNavigationTask(from text: String) -> ActionAssistantBrowserNavigationTask? {
        guard let url = extractURL(from: text) else { return nil }
        guard let browserAppName = resolveBrowserAppName(for: text, url: url) else { return nil }
        return ActionAssistantBrowserNavigationTask(browserAppName: browserAppName, url: url)
    }

    static func parseBrowserSearchTask(from text: String) -> ActionAssistantBrowserSearchTask? {
        let lowercased = text.lowercased()
        let searchTriggers = ["search", "google", "百度", "搜索", "查一下", "查找", "搜一下"]
        guard searchTriggers.contains(where: { lowercased.contains($0) }) else { return nil }
        guard extractURL(from: text) == nil else { return nil }

        let query = cleanupSearchQuery(text)
        guard !query.isEmpty else { return nil }

        let fallbackURL = URL(string: "https://www.google.com")!
        guard let browserAppName = resolveBrowserAppName(for: text, url: fallbackURL) else { return nil }
        return ActionAssistantBrowserSearchTask(browserAppName: browserAppName, query: query)
    }

    static func parseOpenAppTask(from text: String) -> ActionAssistantOpenAppTask? {
        let lowercased = text.lowercased()
        let openTriggers = ["open ", "launch ", "打开", "启动"]
        guard openTriggers.contains(where: { lowercased.contains($0) || text.contains($0) }) else { return nil }
        guard !lowercased.contains("gmail") else { return nil }

        let candidates = [
            ("Safari", "com.apple.Safari"),
            ("Google Chrome", "com.google.Chrome"),
            ("Arc", "company.thebrowser.Browser"),
            ("Brave Browser", "com.brave.Browser"),
            ("Microsoft Edge", "com.microsoft.edgemac"),
            ("Finder", "com.apple.finder"),
            ("Mail", "com.apple.mail"),
            ("Messages", "com.apple.MobileSMS"),
            ("Notes", "com.apple.Notes"),
            ("Calendar", "com.apple.iCal"),
            ("Terminal", "com.apple.Terminal"),
            ("System Settings", "com.apple.systempreferences"),
            ("Slack", "com.tinyspeck.slackmacgap"),
            ("Notion", "notion.id"),
            ("Xcode", "com.apple.dt.Xcode")
        ]

        for (displayName, bundleID) in candidates {
            if containsStandaloneAppName(displayName, in: text) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    return ActionAssistantOpenAppTask(appName: displayName, appURL: appURL)
                }
            }
        }

        return nil
    }

    private static func cleanupSearchQuery(_ text: String) -> String {
        var query = text
        let replacements = [
            "search for", "search", "google", "百度", "搜索", "查一下", "查找", "搜一下",
            "open browser and", "open the browser and", "打开浏览器并", "在浏览器中"
        ]
        for item in replacements {
            query = query.replacingOccurrences(of: item, with: "", options: [.caseInsensitive])
        }
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractURL(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: (text as NSString).length)
        if let match = detector?.firstMatch(in: text, options: [], range: range),
           let url = match.url {
            return url
        }

        let pattern = #"(?i)\b((?:[a-z0-9-]+\.)+[a-z]{2,}(?:/[^\s]*)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let value = String(text[valueRange])
        return URL(string: "https://\(value)")
    }

    private static func resolveBrowserAppName(for text: String, url: URL) -> String? {
        let lowercased = text.lowercased()
        if lowercased.contains("chrome"), isInstalled(bundleID: "com.google.Chrome") {
            return "Google Chrome"
        }
        if lowercased.contains("safari"), isInstalled(bundleID: "com.apple.Safari") {
            return "Safari"
        }
        if lowercased.contains("arc"), isInstalled(bundleID: "company.thebrowser.Browser") {
            return "Arc"
        }
        if lowercased.contains("brave"), isInstalled(bundleID: "com.brave.Browser") {
            return "Brave Browser"
        }
        if lowercased.contains("edge"), isInstalled(bundleID: "com.microsoft.edgemac") {
            return "Microsoft Edge"
        }

        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
           let bundle = Bundle(url: appURL) {
            return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
        }

        return nil
    }

    private static func isInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static func containsStandaloneAppName(_ appName: String, in text: String) -> Bool {
        if text.localizedCaseInsensitiveContains(appName) == false {
            return false
        }

        let escapedName = NSRegularExpression.escapedPattern(for: appName)
            .replacingOccurrences(of: "\\ ", with: "\\s+")
        let pattern = "(?i)(?<![A-Za-z0-9])\(escapedName)(?![A-Za-z0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.localizedCaseInsensitiveContains(appName)
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}

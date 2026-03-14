import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

enum ActionAssistantPerception {
    struct VisualContext: Hashable {
        var screenshotPath: String?
        var width: Int?
        var height: Int?
        var source: String?
        var windowFrame: CGRect
    }

    static func focusedElementName() -> String? {
        guard let focusedElement = focusedElement() else { return nil }
        return firstNonEmptyStringAttribute(
            of: focusedElement,
            attributes: [
                kAXTitleAttribute as CFString,
                kAXDescriptionAttribute as CFString,
                kAXValueAttribute as CFString,
                kAXRoleDescriptionAttribute as CFString
            ]
        )
    }

    static func focusedElementRole() -> String? {
        guard let focusedElement = focusedElement() else { return nil }
        return stringAttribute(of: focusedElement, attribute: kAXRoleAttribute as CFString)
            ?? stringAttribute(of: focusedElement, attribute: kAXRoleDescriptionAttribute as CFString)
    }

    static func selectedText() -> String? {
        guard let focusedElement = focusedElement() else { return nil }
        var selectedTextRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        guard selectedStatus == .success, let selectedTextRef else {
            return nil
        }

        if let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            return selectedText
        }
        if let selectedText = selectedTextRef as? NSAttributedString, !selectedText.string.isEmpty {
            return selectedText.string
        }
        return nil
    }

    static func focusedWindowTitle(preferredAppName: String?) -> String? {
        let app = resolveRunningApplication(preferredAppName: preferredAppName) ?? NSWorkspace.shared.frontmostApplication
        guard let app else { return nil }
        guard let focusedWindow = focusedWindowElement(for: app.processIdentifier) else {
            return app.localizedName
        }

        if let title = stringAttribute(of: focusedWindow, attribute: kAXTitleAttribute as CFString), !title.isEmpty {
            return title
        }
        return app.localizedName
    }

    static func focusedWindowFrame(preferredAppName: String?) -> CGRect? {
        let app = resolveRunningApplication(preferredAppName: preferredAppName) ?? NSWorkspace.shared.frontmostApplication
        guard let app,
              let focusedWindow = focusedWindowElement(for: app.processIdentifier) else {
            return nil
        }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(focusedWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef,
              let sizeRef else {
            return nil
        }

        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    static func focusedWindowVisualContext(preferredAppName: String?) async -> VisualContext? {
        guard #available(macOS 14.0, *) else { return nil }
        let app = resolveRunningApplication(preferredAppName: preferredAppName) ?? NSWorkspace.shared.frontmostApplication
        guard let app else { return nil }
        guard let image = try? await captureFocusedWindowImage(
            processIdentifier: app.processIdentifier,
            preferredAppName: preferredAppName
        ) else { return nil }
        let width = image.width
        let height = image.height
        let screenshotPath = persistScreenshot(image: image, processIdentifier: app.processIdentifier)
        let windowFrame = focusedWindowFrame(preferredAppName: preferredAppName) ?? .zero
        return VisualContext(
            screenshotPath: screenshotPath?.path,
            width: width > 0 ? width : nil,
            height: height > 0 ? height : nil,
            source: "focused_window",
            windowFrame: windowFrame
        )
    }

    static func currentURL(preferredAppName: String?) -> String? {
        let app = resolveRunningApplication(preferredAppName: preferredAppName) ?? NSWorkspace.shared.frontmostApplication
        guard let app, let bundleID = app.bundleIdentifier else { return nil }

        if let scripted = scriptedBrowserURL(bundleID: bundleID) {
            return scripted
        }
        return accessibilityBrowserURL(bundleID: bundleID, processIdentifier: app.processIdentifier)
    }

    private static func resolveRunningApplication(preferredAppName: String?) -> NSRunningApplication? {
        guard let preferredAppName, !preferredAppName.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.localizedCaseInsensitiveContains(preferredAppName) == true
        }
    }

    private static func scriptedBrowserURL(bundleID: String) -> String? {
        let scripts: [String]
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            scripts = [
                "tell application id \"\(bundleID)\" to get URL of front document",
                "tell application id \"\(bundleID)\" to get URL of current tab of front window"
            ]
        case "com.google.Chrome":
            scripts = [
                "tell application id \"com.google.Chrome\" to get the URL of active tab of front window"
            ]
        case "com.microsoft.edgemac":
            scripts = [
                "tell application id \"com.microsoft.edgemac\" to get the URL of active tab of front window"
            ]
        case "com.brave.Browser":
            scripts = [
                "tell application id \"com.brave.Browser\" to get the URL of active tab of front window"
            ]
        case "company.thebrowser.Browser":
            scripts = [
                "tell application id \"company.thebrowser.Browser\" to get the URL of active tab of front window"
            ]
        default:
            return nil
        }

        for script in scripts {
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            if error == nil,
               let stringValue = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !stringValue.isEmpty {
                return stringValue
            }
        }
        return nil
    }

    private static func accessibilityBrowserURL(bundleID: String, processIdentifier: pid_t) -> String? {
        guard AccessibilityPermissionManager.isTrusted() else { return nil }
        guard let windowElement = focusedWindowElement(for: processIdentifier) else { return nil }
        for attribute in ["AXDocument", "AXURL"] {
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(windowElement, attribute as CFString, &value)
            guard status == .success, let value else { continue }
            if let url = value as? URL {
                return url.absoluteString
            }
            if let stringValue = value as? String, !stringValue.isEmpty {
                return stringValue
            }
        }

        return nil
    }

    private static func focusedElement() -> AXUIElement? {
        guard AccessibilityPermissionManager.isTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedStatus == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeBitCast(focusedElementRef, to: AXUIElement.self)
    }

    private static func focusedWindowElement(for processIdentifier: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindowRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )
        guard status == .success,
              let focusedWindowRef,
              CFGetTypeID(focusedWindowRef) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(focusedWindowRef, to: AXUIElement.self)
    }

    private static func persistScreenshot(image: CGImage, processIdentifier: pid_t) -> URL? {
        let directory = screenshotDirectoryURL()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            purgeOldScreenshots(in: directory, keepingLatest: 6)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let filename = "assistant-\(processIdentifier)-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")).png"
            let url = directory.appendingPathComponent(filename)
            let representation = NSBitmapImageRep(cgImage: image)
            guard let data = representation.representation(using: .png, properties: [:]) else {
                return nil
            }
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func screenshotDirectoryURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("ActionAssistant", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
    }

    private static func purgeOldScreenshots(in directory: URL, keepingLatest limit: Int) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let sorted = urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        for url in sorted.dropFirst(limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @available(macOS 14.0, *)
    private static func captureFocusedWindowImage(
        processIdentifier: pid_t,
        preferredAppName: String?
    ) async throws -> CGImage {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let focusedTitle = focusedWindowTitle(preferredAppName: preferredAppName)
        let focusedFrame = focusedWindowFrame(preferredAppName: preferredAppName)

        let candidates = shareableContent.windows.filter { window in
            guard window.owningApplication?.processID == processIdentifier else { return false }
            return window.isOnScreen && window.windowLayer == 0
        }

        let matchedWindow =
            candidates.first(where: {
                guard let focusedTitle, let title = $0.title else { return false }
                return title.localizedCaseInsensitiveContains(focusedTitle)
            })
            ?? candidates.first(where: {
                guard let focusedFrame else { return false }
                let frame = $0.frame
                return abs(frame.origin.x - focusedFrame.origin.x) < 4
                    && abs(frame.origin.y - focusedFrame.origin.y) < 4
                    && abs(frame.size.width - focusedFrame.size.width) < 4
                    && abs(frame.size.height - focusedFrame.size.height) < 4
            })
            ?? candidates.first

        guard let matchedWindow else {
            throw NSError(domain: "Voxt.ActionAssistantVisual", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No focused window available for screenshot capture."
            ])
        }

        let filter = SCContentFilter(desktopIndependentWindow: matchedWindow)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(matchedWindow.frame.width * 2), 64)
        configuration.height = max(Int(matchedWindow.frame.height * 2), 64)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private static func firstNonEmptyStringAttribute(of element: AXUIElement, attributes: [CFString]) -> String? {
        for attribute in attributes {
            if let value = stringAttribute(of: element, attribute: attribute), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func stringAttribute(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value else { return nil }
        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return nil
    }
}

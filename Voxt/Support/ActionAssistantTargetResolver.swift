import AppKit
import ApplicationServices
import Foundation

struct ActionAssistantResolvedTarget {
    let element: AXUIElement
    let app: NSRunningApplication
}

enum ActionAssistantTargetResolver {
    static func frontmostApplication() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    static func resolve(
        target: ActionAssistantRecipe.Step.Target,
        preferredAppName: String?
    ) -> ActionAssistantResolvedTarget? {
        let app = resolveApplication(preferredAppName: preferredAppName) ?? frontmostApplication()
        guard let app,
              let applicationElement = applicationElement(for: app.processIdentifier) else {
            return nil
        }

        let elements = descendants(of: applicationElement, maxDepth: 6)
        guard let match = elements.first(where: { matches(target: target, element: $0) }) else {
            return nil
        }
        return ActionAssistantResolvedTarget(element: match, app: app)
    }

    static func targetExists(
        _ target: ActionAssistantRecipe.Step.Target,
        preferredAppName: String?
    ) -> Bool {
        resolve(target: target, preferredAppName: preferredAppName) != nil
    }

    static func focusedElementMatches(
        _ target: ActionAssistantRecipe.Step.Target,
        preferredAppName: String?
    ) -> Bool {
        let app = resolveApplication(preferredAppName: preferredAppName) ?? frontmostApplication()
        guard let app else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedStatus == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return false
        }

        let focusedElement = focusedRef as! AXUIElement
        if !belongsToApplication(focusedElement, processIdentifier: app.processIdentifier) {
            return false
        }
        return matches(target: target, element: focusedElement)
    }

    static func appTitleContains(_ value: String, preferredAppName: String?) -> Bool {
        let app = resolveApplication(preferredAppName: preferredAppName) ?? frontmostApplication()
        guard let app else { return false }
        if let windowTitle = focusedWindowTitle(for: app.processIdentifier) {
            return windowTitle.localizedCaseInsensitiveContains(value)
        }
        return app.localizedName?.localizedCaseInsensitiveContains(value) == true
    }

    static func focusedWindowCenter(preferredAppName: String?) -> CGPoint? {
        let app = resolveApplication(preferredAppName: preferredAppName) ?? frontmostApplication()
        guard let app,
              let applicationElement = applicationElement(for: app.processIdentifier),
              let focusedWindow = copyAttribute(applicationElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }
        return center(of: focusedWindow)
    }

    static func preferredScrollPoint(preferredAppName: String?) -> CGPoint? {
        let app = resolveApplication(preferredAppName: preferredAppName) ?? frontmostApplication()
        guard let app,
              let applicationElement = applicationElement(for: app.processIdentifier),
              let focusedWindow = copyAttribute(applicationElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }

        let candidates = descendants(of: focusedWindow, maxDepth: 6)
        let scrollRoles = Set(["AXScrollArea", "AXWebArea", "AXTable", "AXOutline", "AXList"])
        if let element = candidates.first(where: { element in
            guard let role = stringAttribute(of: element, attribute: kAXRoleAttribute as CFString) else {
                return false
            }
            return scrollRoles.contains(role)
        }), let center = center(of: element) {
            return center
        }

        return center(of: focusedWindow)
    }

    private static func resolveApplication(preferredAppName: String?) -> NSRunningApplication? {
        guard let preferredAppName, !preferredAppName.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.localizedCaseInsensitiveContains(preferredAppName) == true
        }
    }

    private static func applicationElement(for pid: pid_t) -> AXUIElement? {
        AXUIElementCreateApplication(pid)
    }

    private static func belongsToApplication(_ element: AXUIElement, processIdentifier: pid_t) -> Bool {
        var pid: pid_t = 0
        let status = AXUIElementGetPid(element, &pid)
        return status == .success && pid == processIdentifier
    }

    private static func focusedWindowTitle(for pid: pid_t) -> String? {
        guard let applicationElement = applicationElement(for: pid),
              let focusedWindow = copyAttribute(applicationElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }
        return stringAttribute(of: focusedWindow, attribute: kAXTitleAttribute as CFString)
    }

    private static func descendants(of root: AXUIElement, maxDepth: Int) -> [AXUIElement] {
        var results: [AXUIElement] = [root]
        guard maxDepth > 0 else { return results }

        let childAttributes: [CFString] = [
            kAXChildrenAttribute as CFString,
            kAXWindowsAttribute as CFString,
            "AXSheets" as CFString
        ]

        for attribute in childAttributes {
            if let children = copyElementArray(root, attribute: attribute) {
                for child in children {
                    results.append(contentsOf: descendants(of: child, maxDepth: maxDepth - 1))
                }
            }
        }

        return results
    }

    private static func matches(target: ActionAssistantRecipe.Step.Target, element: AXUIElement) -> Bool {
        if let criteria = target.criteria, !criteria.isEmpty {
            for criterion in criteria {
                guard attributeMatches(element: element, criterion: criterion) else {
                    return false
                }
            }
        }

        if let name = target.computedNameContains, !name.isEmpty {
            let computedName = computedName(for: element)
            guard computedName.localizedCaseInsensitiveContains(name) else {
                return false
            }
        }

        return true
    }

    private static func attributeMatches(
        element: AXUIElement,
        criterion: ActionAssistantRecipe.Step.Target.Criterion
    ) -> Bool {
        let attribute = criterion.attribute as CFString
        if let value = stringAttribute(of: element, attribute: attribute) {
            return value.localizedCaseInsensitiveCompare(criterion.value) == .orderedSame
        }

        if let numberValue = numberAttribute(of: element, attribute: attribute) {
            return "\(numberValue)" == criterion.value
        }

        return false
    }

    private static func computedName(for element: AXUIElement) -> String {
        [
            stringAttribute(of: element, attribute: kAXTitleAttribute as CFString),
            stringAttribute(of: element, attribute: kAXDescriptionAttribute as CFString),
            stringAttribute(of: element, attribute: kAXValueAttribute as CFString),
            stringAttribute(of: element, attribute: kAXRoleDescriptionAttribute as CFString)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private static func copyAttribute(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func copyElementArray(_ element: AXUIElement, attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else { return nil }
        return value as? [AXUIElement]
    }

    private static func stringAttribute(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else { return nil }
        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }

    private static func numberAttribute(of element: AXUIElement, attribute: CFString) -> Double? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else { return nil }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    private static func center(of element: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef,
              let sizeRef else {
            return nil
        }

        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }

        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }
}

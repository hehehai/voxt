import Foundation
import AppKit
import Carbon

extension EmbeddedActionAssistantRuntime {
    func requireAccessibilityPermission() throws {
        guard AccessibilityPermissionManager.isTrusted() else {
            _ = AccessibilityPermissionManager.request(prompt: true)
            throw ActionAssistantRuntimeError.accessibilityPermissionRequired
        }
    }

    func postKey(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw ActionAssistantRuntimeError.unsupportedKey(String(keyCode))
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        Thread.sleep(forTimeInterval: 0.05)
    }

    func postMouseClick(at point: CGPoint) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
              ),
              let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
              ) else {
            throw ActionAssistantRuntimeError.targetNotFound("mouse target")
        }

        mouseDown.post(tap: .cgAnnotatedSessionEventTap)
        mouseUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    func postMouseMove(to point: CGPoint) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let move = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left
              ) else {
            throw ActionAssistantRuntimeError.targetNotFound("mouse target")
        }
        move.post(tap: .cgAnnotatedSessionEventTap)
    }

    func postMouseButton(_ type: CGEventType, at point: CGPoint) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
              ) else {
            throw ActionAssistantRuntimeError.targetNotFound("mouse target")
        }
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    func postMouseDrag(from start: CGPoint, to end: CGPoint) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ActionAssistantRuntimeError.targetNotFound("drag target")
        }

        let steps = 8
        for index in 1...steps {
            let progress = CGFloat(index) / CGFloat(steps)
            let point = CGPoint(
                x: start.x + ((end.x - start.x) * progress),
                y: start.y + ((end.y - start.y) * progress)
            )
            guard let drag = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                throw ActionAssistantRuntimeError.targetNotFound("drag target")
            }
            drag.post(tap: .cgAnnotatedSessionEventTap)
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    func postScroll(direction: String, amount: Int, at point: CGPoint?) throws {
        let axisAmount = Int32(max(1, amount) * 10)
        let (deltaX, deltaY): (Int32, Int32) = switch direction {
        case "up":
            (0, axisAmount)
        case "left":
            (axisAmount, 0)
        case "right":
            (-axisAmount, 0)
        default:
            (0, -axisAmount)
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 2,
                wheel1: deltaY,
                wheel2: deltaX,
                wheel3: 0
              ) else {
            throw ActionAssistantRuntimeError.unsupportedAction("scroll")
        }

        if let point {
            event.location = point
        }
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    func openURL(_ url: URL, inBrowserNamed appName: String) async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID(forBrowserAppName: appName)) else {
            throw ActionAssistantRuntimeError.browserUnavailable(appName)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func bundleID(forBrowserAppName appName: String) -> String {
        switch appName {
        case "Google Chrome":
            return "com.google.Chrome"
        case "Safari":
            return "com.apple.Safari"
        case "Arc":
            return "company.thebrowser.Browser"
        case "Brave Browser":
            return "com.brave.Browser"
        case "Microsoft Edge":
            return "com.microsoft.edgemac"
        default:
            return ""
        }
    }
}

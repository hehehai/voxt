import Foundation
import AppKit
import Carbon

struct ActionAssistantExecutionResult {
    let completedSteps: [String]
    let summary: String
    let stepResults: [ActionAssistantRecipeRunResult.StepResult]?
}

protocol ActionAssistantExecuting {
    func prepare() async throws
    func execute(
        plan: ActionAssistantPlan,
        onStep: @escaping @Sendable (String) -> Void
    ) async throws -> ActionAssistantExecutionResult
    func execute(
        _ task: ActionAssistantParsedTask,
        onStep: @escaping @Sendable (String) -> Void
    ) async throws -> ActionAssistantExecutionResult
    func execute(
        recipe: ActionAssistantRecipe,
        substitutions: [String: String]?,
        onStep: @escaping @Sendable (String) -> Void
    ) async throws -> ActionAssistantRecipeRunResult
}

enum ActionAssistantRuntimeError: LocalizedError {
    case browserUnavailable(String)
    case appOpenFailed(String)
    case accessibilityPermissionRequired
    case unsupportedKey(String)
    case invalidHotkey(String)
    case targetNotFound(String)
    case unsupportedAction(String)

    var errorDescription: String? {
        switch self {
        case .browserUnavailable(let appName):
            return "Unable to open \(appName)."
        case .appOpenFailed(let appName):
            return "Unable to open \(appName)."
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required for keyboard automation."
        case .unsupportedKey(let key):
            return "Unsupported key: \(key)."
        case .invalidHotkey(let hotkey):
            return "Invalid hotkey: \(hotkey)."
        case .targetNotFound(let target):
            return "Unable to resolve target: \(target)."
        case .unsupportedAction(let action):
            return "Unsupported action: \(action)."
        }
    }
}

final class EmbeddedActionAssistantRuntime: ActionAssistantExecuting {
    func prepare() async throws {
        // The first embedded runtime only depends on AppKit APIs.
    }

    func execute(
        plan: ActionAssistantPlan,
        onStep: @escaping @Sendable (String) -> Void
    ) async throws -> ActionAssistantExecutionResult {
        let recipe = ActionAssistantPlanner.recipe(from: plan)
        let result = try await execute(recipe: recipe, substitutions: nil, onStep: onStep)
        if !result.success {
            throw NSError(
                domain: "Voxt.ActionAssistantPlan",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: result.error ?? "Action plan execution failed."]
            )
        }
        return ActionAssistantExecutionResult(
            completedSteps: result.stepResults.filter(\.success).map { $0.note ?? $0.action },
            summary: "plan:\(result.stepsCompleted)",
            stepResults: result.stepResults
        )
    }

    func execute(
        _ task: ActionAssistantParsedTask,
        onStep: @escaping @Sendable (String) -> Void
    ) async throws -> ActionAssistantExecutionResult {
        switch task {
        case .browserNavigation(let navigationTask):
            return try await executeBrowserNavigation(navigationTask, onStep: onStep)
        case .browserSearch(let searchTask):
            return try await executeBrowserSearch(searchTask, onStep: onStep)
        case .openApp(let openAppTask):
            return try await executeOpenApp(openAppTask, onStep: onStep)
        }
    }

    func execute(
        recipe: ActionAssistantRecipe,
        substitutions: [String: String]? = nil,
        onStep: @escaping @Sendable (String) -> Void
    ) async throws -> ActionAssistantRecipeRunResult {
        var stepResults: [ActionAssistantRecipeRunResult.StepResult] = []
        var stepsCompleted = 0
        var runtimeValues = substitutions ?? [:]

        for step in recipe.steps {
            let startedAt = Date()
            let resolvedTarget = await resolvedTargetInfo(for: step, substitutions: runtimeValues)
            do {
                try await executeRecipeStep(step, substitutions: &runtimeValues, onStep: onStep)
                try await performWait(after: step, substitutions: runtimeValues)
                let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
                stepResults.append(.init(
                    stepID: step.id,
                    action: step.action,
                    success: true,
                    durationMs: duration,
                    error: nil,
                    note: step.note,
                    targetApp: step.targetApp,
                    targetLabel: step.target?.computedNameContains,
                    targetRole: step.target?.criteria?.first(where: { $0.attribute == "AXRole" })?.value,
                    relativeX: step.params?["relative_x"].flatMap(Double.init),
                    relativeY: step.params?["relative_y"].flatMap(Double.init),
                    resolvedTargetLabel: resolvedTarget?.label,
                    resolvedTargetRole: resolvedTarget?.role,
                    resolvedRelativeX: resolvedTarget?.relativeX,
                    resolvedRelativeY: resolvedTarget?.relativeY,
                    diagnosisCategory: nil,
                    diagnosisReason: nil
                ))
                stepsCompleted += 1
            } catch {
                let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
                stepResults.append(.init(
                    stepID: step.id,
                    action: step.action,
                    success: false,
                    durationMs: duration,
                    error: error.localizedDescription,
                    note: step.note,
                    targetApp: step.targetApp,
                    targetLabel: step.target?.computedNameContains,
                    targetRole: step.target?.criteria?.first(where: { $0.attribute == "AXRole" })?.value,
                    relativeX: step.params?["relative_x"].flatMap(Double.init),
                    relativeY: step.params?["relative_y"].flatMap(Double.init),
                    resolvedTargetLabel: resolvedTarget?.label,
                    resolvedTargetRole: resolvedTarget?.role,
                    resolvedRelativeX: resolvedTarget?.relativeX,
                    resolvedRelativeY: resolvedTarget?.relativeY,
                    diagnosisCategory: nil,
                    diagnosisReason: nil
                ))
                return ActionAssistantRecipeRunResult(
                    recipeName: recipe.name,
                    success: false,
                    stepsCompleted: stepsCompleted,
                    totalSteps: recipe.steps.count,
                    stepResults: stepResults,
                    error: error.localizedDescription
                )
            }
        }

        return ActionAssistantRecipeRunResult(
            recipeName: recipe.name,
            success: true,
            stepsCompleted: stepsCompleted,
            totalSteps: recipe.steps.count,
            stepResults: stepResults,
            error: nil
        )
    }

    private func executeBrowserNavigation(
        _ task: ActionAssistantBrowserNavigationTask,
        onStep: @escaping @Sendable (String) -> Void
    ) async throws -> ActionAssistantExecutionResult {
        onStep("Open \(task.browserAppName)")
        try await openURL(task.url, inBrowserNamed: task.browserAppName)
        onStep("Navigate to \(task.url.absoluteString)")
        return ActionAssistantExecutionResult(
            completedSteps: ["Open \(task.browserAppName)", "Navigate to \(task.url.absoluteString)"],
            summary: "browserNavigation:2",
            stepResults: nil
        )
    }

    private func executeBrowserSearch(
        _ task: ActionAssistantBrowserSearchTask,
        onStep: @escaping @Sendable (String) -> Void
    ) async throws -> ActionAssistantExecutionResult {
        let query = task.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? task.query
        let searchURL = URL(string: "https://www.google.com/search?q=\(query)")!
        onStep("Open \(task.browserAppName)")
        try await openURL(searchURL, inBrowserNamed: task.browserAppName)
        onStep("Search \(task.query)")
        return ActionAssistantExecutionResult(
            completedSteps: ["Open \(task.browserAppName)", "Search \(task.query)"],
            summary: "browserSearch:2",
            stepResults: nil
        )
    }

    private func executeOpenApp(
        _ task: ActionAssistantOpenAppTask,
        onStep: @escaping @Sendable (String) -> Void
    ) async throws -> ActionAssistantExecutionResult {
        onStep("Launch \(task.appName)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            try await NSWorkspace.shared.openApplication(at: task.appURL, configuration: configuration)
        } catch {
            throw ActionAssistantRuntimeError.appOpenFailed(task.appName)
        }
        onStep("Open \(task.appName)")
        return ActionAssistantExecutionResult(
            completedSteps: ["Launch \(task.appName)", "Open \(task.appName)"],
            summary: "openApp:\(task.appName)",
            stepResults: nil
        )
    }

    private func executeRecipeStep(
        _ step: ActionAssistantRecipe.Step,
        substitutions: inout [String: String],
        onStep: @escaping @Sendable (String) -> Void
    ) async throws {
        switch step.action {
        case "open_app":
            guard let appName = resolvedValue(for: step.params?["app_name"], substitutions: substitutions),
                  let appURL = appURL(forDisplayName: appName) else {
                throw ActionAssistantRuntimeError.appOpenFailed(step.params?["app_name"] ?? "App")
            }
            _ = try await executeOpenApp(
                ActionAssistantOpenAppTask(appName: appName, appURL: appURL),
                onStep: onStep
            )
        case "open_url":
            guard let urlString = resolvedValue(for: step.params?["url"], substitutions: substitutions),
                  let url = URL(string: urlString) else {
                throw ActionAssistantRuntimeError.browserUnavailable(step.targetApp ?? "Browser")
            }
            let browserName = step.targetApp ?? "Safari"
            _ = try await executeBrowserNavigation(
                ActionAssistantBrowserNavigationTask(browserAppName: browserName, url: url),
                onStep: onStep
            )
        case "search_web":
            guard let query = resolvedValue(for: step.params?["query"], substitutions: substitutions) else {
                throw ActionAssistantRuntimeError.browserUnavailable(step.targetApp ?? "Browser")
            }
            let browserName = step.targetApp ?? "Safari"
            _ = try await executeBrowserSearch(
                ActionAssistantBrowserSearchTask(browserAppName: browserName, query: query),
                onStep: onStep
            )
        case "type_text":
            guard let text = resolvedValue(for: step.params?["text"], substitutions: substitutions) else {
                throw ActionAssistantRuntimeError.invalidHotkey("Missing text")
            }
            onStep(step.note ?? "Type text")
            try typeText(text)
        case "press_key":
            guard let key = resolvedValue(for: step.params?["key"], substitutions: substitutions) else {
                throw ActionAssistantRuntimeError.invalidHotkey("Missing key")
            }
            onStep(step.note ?? "Press \(key)")
            try pressKey(named: key)
        case "press_hotkey", "hotkey":
            guard let keys = resolvedValue(for: step.params?["keys"], substitutions: substitutions)
                ?? resolvedValue(for: step.params?["hotkey"], substitutions: substitutions) else {
                throw ActionAssistantRuntimeError.invalidHotkey("Missing keys")
            }
            onStep(step.note ?? "Press \(keys)")
            try pressHotkey(keys)
        case "read_selected_text":
            onStep(step.note ?? "Read selected text")
            let value = ActionAssistantPerception.selectedText() ?? ""
            assignReadValue(value, for: step, substitutions: &substitutions)
        case "read_current_url":
            onStep(step.note ?? "Read current URL")
            let value = ActionAssistantPerception.currentURL(preferredAppName: step.targetApp) ?? ""
            assignReadValue(value, for: step, substitutions: &substitutions)
        case "read_focused_title":
            onStep(step.note ?? "Read focused title")
            let value = ActionAssistantPerception.focusedWindowTitle(preferredAppName: step.targetApp) ?? ""
            assignReadValue(value, for: step, substitutions: &substitutions)
        case "focus":
            let targetLabel = step.note ?? step.target?.computedNameContains ?? step.targetApp ?? "target"
            onStep(targetLabel)
            try focus(step: step, substitutions: substitutions)
        case "click":
            let targetLabel = step.note ?? step.target?.computedNameContains ?? step.targetApp ?? "target"
            onStep(targetLabel)
            try await click(step: step, substitutions: substitutions)
        case "hover":
            onStep(step.note ?? "Hover")
            try await hover(step: step, substitutions: substitutions)
        case "long_press":
            onStep(step.note ?? "Long press")
            try await longPress(step: step, substitutions: substitutions)
        case "drag":
            onStep(step.note ?? "Drag")
            try await drag(step: step, substitutions: substitutions)
        case "scroll":
            onStep(step.note ?? "Scroll")
            try await scroll(step: step, substitutions: substitutions)
        case "wait":
            onStep(step.note ?? "Wait")
            let waitCondition = ActionAssistantRecipe.Step.WaitCondition(
                condition: resolvedValue(for: step.params?["condition"], substitutions: substitutions) ?? "sleep",
                value: resolvedValue(for: step.params?["value"], substitutions: substitutions),
                timeout: resolvedTimeout(for: step, substitutions: substitutions)
            )
            try await wait(for: waitCondition, step: step, substitutions: substitutions)
        default:
            throw ActionAssistantRuntimeError.unsupportedAction(step.action)
        }
    }

    private func focus(step: ActionAssistantRecipe.Step, substitutions: [String: String]) throws {
        try requireAccessibilityPermission()
        if step.target == nil {
            guard let appName = resolvedValue(for: step.params?["app_name"], substitutions: substitutions)
                ?? step.targetApp
                ?? resolvedValue(for: step.params?["app"], substitutions: substitutions) else {
                throw ActionAssistantRuntimeError.targetNotFound(step.targetApp ?? step.params?["app_name"] ?? "focus target")
            }

            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
            }) {
                _ = app.activate()
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier(forAppName: appName))
                ?? NSWorkspace.shared.fullPath(forApplication: appName).map(URL.init(fileURLWithPath:)) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
            } else {
                throw ActionAssistantRuntimeError.targetNotFound(appName)
            }
            Thread.sleep(forTimeInterval: 0.15)
            return
        }

        guard let target = resolvedTargetDescriptor(for: step, substitutions: substitutions),
              let resolvedTarget = ActionAssistantTargetResolver.resolve(target: target, preferredAppName: step.targetApp) else {
            throw ActionAssistantRuntimeError.targetNotFound(step.target?.computedNameContains ?? step.targetApp ?? "focus target")
        }

        _ = resolvedTarget.app.activate()
        AXUIElementSetAttributeValue(resolvedTarget.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(resolvedTarget.element, kAXRaiseAction as CFString)
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func click(step: ActionAssistantRecipe.Step, substitutions: [String: String]) async throws {
        try requireAccessibilityPermission()
        guard let target = resolvedTargetDescriptor(for: step, substitutions: substitutions),
              let resolvedTarget = ActionAssistantTargetResolver.resolve(target: target, preferredAppName: step.targetApp) else {
            let point = try await interactionPoint(for: step, substitutions: substitutions, fallbackLabel: "click target")
            try postMouseClick(at: point)
            try await pause(seconds: 0.1)
            return
        }

        _ = resolvedTarget.app.activate()
        let pressError = AXUIElementPerformAction(resolvedTarget.element, kAXPressAction as CFString)
        if pressError == .success {
            try await pause(seconds: 0.1)
            return
        }

        if let point = elementCenter(resolvedTarget.element) {
            try postMouseClick(at: point)
            try await pause(seconds: 0.1)
            return
        }

        throw ActionAssistantRuntimeError.targetNotFound(step.target?.computedNameContains ?? step.targetApp ?? "click target")
    }

    private func hover(step: ActionAssistantRecipe.Step, substitutions: [String: String]) async throws {
        try requireAccessibilityPermission()
        let point = try await interactionPoint(for: step, substitutions: substitutions, fallbackLabel: "hover target")
        if let app = targetApp(for: step, substitutions: substitutions) {
            _ = app.activate()
            try await pause(seconds: 0.1)
        }
        try postMouseMove(to: point)
        try await pause(seconds: 0.1)
    }

    private func longPress(step: ActionAssistantRecipe.Step, substitutions: [String: String]) async throws {
        try requireAccessibilityPermission()
        let point = try await interactionPoint(for: step, substitutions: substitutions, fallbackLabel: "long press target")
        if let app = targetApp(for: step, substitutions: substitutions) {
            _ = app.activate()
            try await pause(seconds: 0.1)
        }
        let duration = max(0.1, Double(resolvedValue(for: step.params?["duration"], substitutions: substitutions) ?? "") ?? 0.5)
        try postMouseMove(to: point)
        try postMouseButton(.leftMouseDown, at: point)
        try await pause(seconds: duration)
        try postMouseButton(.leftMouseUp, at: point)
        try await pause(seconds: 0.1)
    }

    private func drag(step: ActionAssistantRecipe.Step, substitutions: [String: String]) async throws {
        try requireAccessibilityPermission()
        let start = try await interactionPoint(for: step, substitutions: substitutions, fallbackLabel: "drag source")
        guard let destination = await dragDestination(for: step, substitutions: substitutions) else {
            throw ActionAssistantRuntimeError.invalidHotkey("Missing drag destination")
        }
        if let app = targetApp(for: step, substitutions: substitutions) {
            _ = app.activate()
            try await pause(seconds: 0.1)
        }
        let holdDuration = max(0.05, Double(resolvedValue(for: step.params?["duration"], substitutions: substitutions) ?? "") ?? 0.1)
        try postMouseMove(to: start)
        try postMouseButton(.leftMouseDown, at: start)
        try await pause(seconds: holdDuration)
        try postMouseDrag(from: start, to: destination)
        try postMouseButton(.leftMouseUp, at: destination)
        try await pause(seconds: 0.1)
    }

    private func scroll(step: ActionAssistantRecipe.Step, substitutions: [String: String]) async throws {
        try requireAccessibilityPermission()
        if let app = targetApp(for: step, substitutions: substitutions) {
            _ = app.activate()
            try await pause(seconds: 0.1)
        }
        let direction = resolvedValue(for: step.params?["direction"], substitutions: substitutions)?.lowercased() ?? "down"
        let amount = max(1, Int(resolvedValue(for: step.params?["amount"], substitutions: substitutions) ?? "") ?? 3)
        let point =
            (try? await interactionPoint(for: step, substitutions: substitutions, fallbackLabel: "scroll target"))
            ?? ActionAssistantTargetResolver.preferredScrollPoint(preferredAppName: step.targetApp)
        try postScroll(direction: direction, amount: amount, at: point)
        try await pause(seconds: 0.1)
    }

    private func performWait(
        after step: ActionAssistantRecipe.Step,
        substitutions: [String: String]
    ) async throws {
        guard let waitAfter = step.waitAfter else { return }
        try await wait(for: waitAfter, step: step, substitutions: substitutions)
    }

    private func pause(seconds: Double) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func resolvedTimeout(
        for step: ActionAssistantRecipe.Step,
        substitutions: [String: String]?
    ) -> Double? {
        if let timeout = step.params?["timeout"].flatMap({ resolvedValue(for: $0, substitutions: substitutions) }).flatMap(Double.init) {
            return timeout
        }
        return resolvedTimeout(waitAfter: step.waitAfter, substitutions: substitutions)
    }

    private func resolvedTimeout(
        waitAfter: ActionAssistantRecipe.Step.WaitCondition?,
        substitutions: [String: String]?
    ) -> Double? {
        guard let waitAfter else { return nil }
        if let timeout = waitAfter.timeout {
            return timeout
        }
        if let value = waitAfter.value.flatMap({ resolvedValue(for: $0, substitutions: substitutions) }).flatMap(Double.init) {
            return value
        }
        return nil
    }

    private func wait(
        for waitAfter: ActionAssistantRecipe.Step.WaitCondition,
        step: ActionAssistantRecipe.Step,
        substitutions: [String: String]
    ) async throws {
        let timeout = resolvedTimeout(waitAfter: waitAfter, substitutions: substitutions) ?? 0.3
        switch waitAfter.condition.lowercased() {
        case "sleep":
            try await pause(seconds: timeout)
        case "elementexists":
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let target = resolvedTargetDescriptor(for: step, substitutions: substitutions),
                   ActionAssistantTargetResolver.resolve(target: target, preferredAppName: step.targetApp) != nil {
                    return
                }
                try await pause(seconds: 0.1)
            }
            throw ActionAssistantRuntimeError.targetNotFound(waitAfter.value ?? step.target?.computedNameContains ?? "element")
        case "elementgone":
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let target = resolvedTargetDescriptor(for: step, substitutions: substitutions),
                   ActionAssistantTargetResolver.resolve(target: target, preferredAppName: step.targetApp) == nil {
                    return
                }
                try await pause(seconds: 0.1)
            }
            throw ActionAssistantRuntimeError.unsupportedAction("wait elementGone timed out")
        case "titlecontains":
            let expected = resolvedValue(for: waitAfter.value, substitutions: substitutions) ?? ""
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if ActionAssistantTargetResolver.appTitleContains(expected, preferredAppName: step.targetApp) {
                    return
                }
                try await pause(seconds: 0.1)
            }
            throw ActionAssistantRuntimeError.targetNotFound(expected)
        default:
            try await pause(seconds: timeout)
        }
    }

    private func typeText(_ text: String) throws {
        try requireAccessibilityPermission()

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        defer {
            pasteboard.clearContents()
            if let previous, !previous.isEmpty {
                pasteboard.setString(previous, forType: .string)
            }
        }

        try postKey(keyCode: 0x09, flags: .maskCommand)
    }

    private func pressKey(named key: String) throws {
        try requireAccessibilityPermission()
        guard let keyCode = keyCode(for: key) else {
            throw ActionAssistantRuntimeError.unsupportedKey(key)
        }
        try postKey(keyCode: keyCode, flags: [])
    }

    private func pressHotkey(_ keys: String) throws {
        try requireAccessibilityPermission()

        let parts = keys
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let last = parts.last, let keyCode = keyCode(for: last) else {
            throw ActionAssistantRuntimeError.invalidHotkey(keys)
        }

        var modifiers = NSEvent.ModifierFlags()
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command":
                modifiers.insert(.command)
            case "shift":
                modifiers.insert(.shift)
            case "option", "alt":
                modifiers.insert(.option)
            case "control", "ctrl":
                modifiers.insert(.control)
            case "fn", "function":
                modifiers.insert(.function)
            default:
                throw ActionAssistantRuntimeError.invalidHotkey(keys)
            }
        }

        try postKey(keyCode: keyCode, flags: HotkeyPreference.cgFlags(from: modifiers))
    }

    private func bundleIdentifier(forAppName appName: String) -> String {
        switch appName.lowercased() {
        case "safari":
            return "com.apple.Safari"
        case "google chrome", "chrome":
            return "com.google.Chrome"
        case "arc":
            return "company.thebrowser.Browser"
        case "brave", "brave browser":
            return "com.brave.Browser"
        case "microsoft edge", "edge":
            return "com.microsoft.edgemac"
        case "mail":
            return "com.apple.mail"
        case "finder":
            return "com.apple.finder"
        case "messages":
            return "com.apple.MobileSMS"
        case "notes":
            return "com.apple.Notes"
        case "calendar":
            return "com.apple.iCal"
        case "terminal":
            return "com.apple.Terminal"
        case "system settings":
            return "com.apple.systempreferences"
        case "slack":
            return "com.tinyspeck.slackmacgap"
        case "notion":
            return "notion.id"
        case "xcode":
            return "com.apple.dt.Xcode"
        default:
            return appName
        }
    }

    func elementCenter(_ element: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionValue as! AXValue) == .cgPoint,
              AXValueGetType(sizeValue as! AXValue) == .cgSize,
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }

    private func keyCode(for key: String) -> CGKeyCode? {
        switch key.lowercased() {
        case "return", "enter":
            return CGKeyCode(kVK_Return)
        case "tab":
            return CGKeyCode(kVK_Tab)
        case "escape", "esc":
            return CGKeyCode(kVK_Escape)
        case "space":
            return CGKeyCode(kVK_Space)
        case "delete", "backspace":
            return CGKeyCode(kVK_Delete)
        case "left":
            return CGKeyCode(kVK_LeftArrow)
        case "right":
            return CGKeyCode(kVK_RightArrow)
        case "up":
            return CGKeyCode(kVK_UpArrow)
        case "down":
            return CGKeyCode(kVK_DownArrow)
        case "a":
            return 0x00
        case "b":
            return 0x0B
        case "c":
            return 0x08
        case "g":
            return 0x05
        case "k":
            return 0x28
        case "l":
            return 0x25
        case "n":
            return 0x2D
        case "v":
            return 0x09
        default:
            return nil
        }
    }
}

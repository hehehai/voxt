import AppKit
import Foundation

struct ActionAssistantPerceptionSnapshot: Codable, Hashable {
    struct VisualContext: Codable, Hashable {
        var screenshotPath: String?
        var width: Int?
        var height: Int?
        var source: String?
    }

    struct Point: Codable, Hashable {
        var x: Double
        var y: Double
    }

    struct Size: Codable, Hashable {
        var width: Double
        var height: Double
    }

    var frontmostAppName: String?
    var frontmostBundleIdentifier: String?
    var focusedWindowTitle: String?
    var focusedWindowOrigin: Point?
    var focusedWindowSize: Size?
    var focusedElementName: String?
    var focusedElementRole: String?
    var currentURL: String?
    var selectedText: String?
    var runningApps: [String]
    var accessibilityTrusted: Bool
    var mouseLocation: Point?
    var screenCount: Int
    var visualContext: VisualContext?
}

struct ActionAssistantPlan: Codable, Hashable {
    var summary: String
    var app: String?
    var expectedOutcome: String?
    var preconditions: ActionAssistantRecipe.Preconditions?
    var onFailure: String?
    var steps: [ActionAssistantRecipe.Step]

    enum CodingKeys: String, CodingKey {
        case summary, app, steps, preconditions
        case expectedOutcome = "expected_outcome"
        case onFailure = "on_failure"
    }
}

struct ActionAssistantOutcomeAssessment: Codable, Hashable {
    var satisfied: Bool
    var reason: String
}

enum ActionAssistantPlanner {
    static func captureSnapshot() async -> ActionAssistantPerceptionSnapshot {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .sorted()
        let visualSnapshotsEnabled = UserDefaults.standard.bool(forKey: AppPreferenceKey.actionAssistantVisualSnapshotsEnabled)
        let visualContext = visualSnapshotsEnabled
            ? await ActionAssistantPerception.focusedWindowVisualContext(preferredAppName: nil)
            : nil

        return ActionAssistantPerceptionSnapshot(
            frontmostAppName: frontmostApp?.localizedName,
            frontmostBundleIdentifier: frontmostApp?.bundleIdentifier,
            focusedWindowTitle: ActionAssistantPerception.focusedWindowTitle(preferredAppName: nil),
            focusedWindowOrigin: ActionAssistantPerception.focusedWindowFrame(preferredAppName: nil).map {
                .init(x: $0.origin.x, y: $0.origin.y)
            },
            focusedWindowSize: ActionAssistantPerception.focusedWindowFrame(preferredAppName: nil).map {
                .init(width: $0.size.width, height: $0.size.height)
            },
            focusedElementName: ActionAssistantPerception.focusedElementName(),
            focusedElementRole: ActionAssistantPerception.focusedElementRole(),
            currentURL: ActionAssistantPerception.currentURL(preferredAppName: nil),
            selectedText: ActionAssistantPerception.selectedText(),
            runningApps: runningApps,
            accessibilityTrusted: AccessibilityPermissionManager.isTrusted(),
            mouseLocation: {
                let point = NSEvent.mouseLocation
                return .init(x: point.x, y: point.y)
            }(),
            screenCount: NSScreen.screens.count,
            visualContext: visualContext.map {
                .init(
                    screenshotPath: $0.screenshotPath,
                    width: $0.width,
                    height: $0.height,
                    source: $0.source
                )
            }
        )
    }

    static func prompt(for userRequest: String, snapshot: ActionAssistantPerceptionSnapshot) -> String {
        let contextJSON = (try? prettyJSONString(from: snapshot)) ?? "{}"
        return basePrompt(
            mode: "initial planning",
            snapshotJSON: contextJSON,
            userRequest: userRequest,
            extraInstructions: ""
        )
    }

    static func repairPrompt(
        for userRequest: String,
        snapshot: ActionAssistantPerceptionSnapshot,
        previousPlan: ActionAssistantPlan,
        failure: String,
        attempt: Int,
        recentSteps: [String]
    ) -> String {
        let contextJSON = (try? prettyJSONString(from: snapshot)) ?? "{}"
        let previousPlanJSON = (try? prettyJSONString(from: previousPlan)) ?? "{}"
        let recentStepsText = recentSteps.isEmpty
            ? "[]"
            : recentSteps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return basePrompt(
            mode: "repair planning",
            snapshotJSON: contextJSON,
            userRequest: userRequest,
            extraInstructions: """
            The previous plan failed. Use the refreshed context to recover.
            Repair attempt: \(attempt)

            Previous plan JSON:
            \(previousPlanJSON)

            Recent execution trace:
            \(recentStepsText)

            Failure:
            \(failure)

            Produce a corrected plan. Avoid repeating the same failing step sequence if the new context suggests a better next action.
            """
        )
    }

    static func outcomeVerificationPrompt(
        for userRequest: String,
        expectedOutcome: String,
        before: ActionAssistantPerceptionSnapshot,
        after: ActionAssistantPerceptionSnapshot
    ) -> String {
        let beforeJSON = (try? prettyJSONString(from: before)) ?? "{}"
        let afterJSON = (try? prettyJSONString(from: after)) ?? "{}"
        return """
        You are Voxt Action Assistant Verifier.

        Return JSON only. No markdown. No explanation.

        Decide whether the expected outcome is satisfied after the action execution.
        Be strict. Only mark satisfied=true when the post-state clearly indicates success.

        JSON schema:
        {
          "satisfied": true,
          "reason": "short explanation"
        }

        User request:
        \(userRequest)

        Expected outcome:
        \(expectedOutcome)

        Before context JSON:
        \(beforeJSON)

        After context JSON:
        \(afterJSON)
        """
    }

    private static func basePrompt(
        mode: String,
        snapshotJSON: String,
        userRequest: String,
        extraInstructions: String
    ) -> String {
        return """
        You are Voxt Action Assistant Planner. Plan GUI actions in the style of Ghost OS.

        Return JSON only. No markdown. No explanation.

        Rules:
        - Interpret the user's goal using the screen context.
        - Prefer robust GUI actions over brittle shortcuts.
        - Use these actions only: open_app, open_url, search_web, focus, click, hover, long_press, drag, scroll, type_text, press_key, press_hotkey, wait, read_selected_text, read_current_url, read_focused_title.
        - Use recipe-level preconditions when the task clearly depends on an app running or a URL being open.
        - Use expected_outcome to describe the post-condition that should be true if the plan worked.
        - Use on_failure at recipe or step level with only these values: stop or skip. Default to stop.
        - Use focus with only target_app when you just need to activate an app window. Add target only when you need to focus a specific UI element.
        - Use target_app when the step should run in a specific app.
        - For press_hotkey, put the shortcut in params.keys, not params.hotkey.
        - Use target.computedNameContains when you need to find a visible UI element by label.
        - Use target.criteria only for precise constraints like AXRole.
        - Use hover before click only when a hidden control, tooltip, or hover menu likely needs to appear.
        - Use long_press for context menus, press-and-hold interactions, or drag initiation.
        - Use drag for moving items or sliders. Provide to_x and to_y params for the destination.
        - Use scroll with params.direction = up/down/left/right and a small params.amount when more content must be revealed.
        - If visual_context is present and you can identify a target from the screenshot more reliably than AX labels, you may use relative_x and relative_y.
        - relative_x and relative_y must be normalized between 0.0 and 1.0 using the screenshot of the focused window, where 0,0 is top-left and 1,1 is bottom-right.
        - For drag destinations from screenshot understanding, use to_relative_x and to_relative_y with the same normalized coordinate system.
        - Use wait_after on action steps whenever the next UI state matters.
        - For wait steps, put condition/value/timeout in params. Supported conditions: sleep, elementExists, elementGone, titleContains.
        - For browser navigation, prefer this stable pattern:
          1. open_app or focus the browser
          2. press_hotkey with cmd,l
          3. type_text with the URL
          4. press_key enter
          5. wait_after titleContains or expected_outcome describing the page
        - Do not use click targets for the address bar when cmd+l is sufficient.
        - Keep the plan short and executable. Usually 1 to 5 steps.
        - If the request is vague, choose the most reasonable app from context.
        - If the user says "open browser", choose the current/frontmost browser if there is one, otherwise Safari.
        - If no meaningful action can be planned, return {"summary":"unsupported","app":null,"steps":[]}
        - Planning mode: \(mode).

        JSON schema:
        {
          "summary": "short human summary",
          "app": "optional app name",
          "expected_outcome": "optional post-condition summary",
          "preconditions": {
            "app_running": "optional app name",
            "url_contains": "optional URL fragment"
          },
          "on_failure": "stop",
          "steps": [
            {
              "id": 1,
              "action": "click",
              "target_app": "optional app name",
              "target": {
                "computedNameContains": "Compose",
                "criteria": [
                  { "attribute": "AXRole", "value": "AXButton" }
                ]
              },
              "params": {
                "text": "optional",
                "app_name": "optional",
                "url": "optional",
                "query": "optional",
                "keys": "optional comma-separated hotkey string like cmd,l",
                "condition": "optional",
                "value": "optional",
                "timeout": "optional",
                "direction": "optional for scroll",
                "amount": "optional for scroll",
                "duration": "optional for long_press",
                "x": "optional screen x",
                "y": "optional screen y",
                "relative_x": "optional normalized x within focused window screenshot",
                "relative_y": "optional normalized y within focused window screenshot",
                "to_x": "optional drag destination x",
                "to_y": "optional drag destination y",
                "to_relative_x": "optional normalized drag destination x within focused window screenshot",
                "to_relative_y": "optional normalized drag destination y within focused window screenshot",
                "to_target_name": "optional drag destination element label",
                "to_target_app": "optional drag destination app"
              },
              "wait_after": {
                "condition": "elementExists",
                "value": "optional",
                "timeout": 2.0
              },
              "note": "short step title",
              "on_failure": "stop"
            }
          ]
        }

        Current context JSON:
        \(snapshotJSON)

        \(extraInstructions)

        User request:
        \(userRequest)
        """
    }

}

import Foundation

enum ActionAssistantBuiltInRecipes {
    static let names = Set(all.map(\.name))

    static let all: [ActionAssistantRecipe] = [
        ActionAssistantRecipe(
            name: "open-gmail",
            description: "Open Gmail in the default browser.",
            app: "Browser",
            steps: [
                .init(
                    id: 1,
                    action: "open_url",
                    targetApp: nil,
                    params: ["url": "https://mail.google.com"],
                    waitAfter: nil,
                    note: "Open Gmail",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "open-slack",
            description: "Open Slack app.",
            app: "Slack",
            steps: [
                .init(
                    id: 1,
                    action: "open_app",
                    targetApp: "Slack",
                    params: ["app_name": "Slack"],
                    waitAfter: nil,
                    note: "Open Slack",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "open-notion",
            description: "Open Notion app.",
            app: "Notion",
            steps: [
                .init(
                    id: 1,
                    action: "open_app",
                    targetApp: "Notion",
                    params: ["app_name": "Notion"],
                    waitAfter: nil,
                    note: "Open Notion",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "open-linear",
            description: "Open Linear in the default browser.",
            app: "Browser",
            steps: [
                .init(
                    id: 1,
                    action: "open_url",
                    targetApp: nil,
                    params: ["url": "https://linear.app"],
                    waitAfter: nil,
                    note: "Open Linear",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "open-x",
            description: "Open X in the default browser.",
            app: "Browser",
            steps: [
                .init(
                    id: 1,
                    action: "open_url",
                    targetApp: nil,
                    params: ["url": "https://x.com"],
                    waitAfter: nil,
                    note: "Open X",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "open-calendar",
            description: "Open Calendar app.",
            app: "Calendar",
            steps: [
                .init(
                    id: 1,
                    action: "open_app",
                    targetApp: "Calendar",
                    params: ["app_name": "Calendar"],
                    waitAfter: nil,
                    note: "Open Calendar",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "gmail-compose",
            description: "Open a prefilled Gmail compose draft in the default browser.",
            app: "Browser",
            params: [
                "compose_url": .init(type: "string", description: "Prefilled Gmail compose URL", required: true)
            ],
            steps: [
                .init(
                    id: 1,
                    action: "open_url",
                    targetApp: nil,
                    params: ["url": "{{compose_url}}"],
                    waitAfter: nil,
                    note: "Open Gmail draft",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "gmail-compose-window",
            description: "Open Gmail and click Compose.",
            app: "Browser",
            steps: [
                .init(
                    id: 1,
                    action: "open_url",
                    targetApp: nil,
                    params: ["url": "https://mail.google.com"],
                    waitAfter: .init(condition: "titleContains", value: "Gmail", timeout: 8),
                    note: "Open Gmail",
                    onFailure: "stop"
                ),
                .init(
                    id: 2,
                    action: "click",
                    targetApp: nil,
                    target: .init(
                        criteria: [
                            .init(attribute: "AXRole", value: "AXButton")
                        ],
                        computedNameContains: "Compose"
                    ),
                    params: nil,
                    waitAfter: .init(condition: "sleep", value: nil, timeout: 0.4),
                    note: "Open compose window",
                    onFailure: "stop"
                ),
                .init(
                    id: 3,
                    action: "wait",
                    targetApp: nil,
                    target: .init(
                        criteria: nil,
                        computedNameContains: "To recipients"
                    ),
                    params: [
                        "condition": "elementExists",
                        "timeout": "5"
                    ],
                    waitAfter: nil,
                    note: "Wait for compose fields",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "slack-send",
            description: "Open a Slack channel and send a message.",
            app: "Slack",
            params: [
                "channel": .init(type: "string", description: "Slack channel name", required: true),
                "message": .init(type: "string", description: "Message text", required: true)
            ],
            steps: [
                .init(
                    id: 1,
                    action: "open_app",
                    targetApp: "Slack",
                    params: ["app_name": "Slack"],
                    waitAfter: .init(condition: "sleep", value: nil, timeout: 0.5),
                    note: "Open Slack",
                    onFailure: "stop"
                ),
                .init(
                    id: 2,
                    action: "press_hotkey",
                    targetApp: "Slack",
                    params: ["keys": "cmd,k"],
                    waitAfter: .init(condition: "sleep", value: nil, timeout: 0.3),
                    note: "Open channel switcher",
                    onFailure: "stop"
                ),
                .init(
                    id: 3,
                    action: "type_text",
                    targetApp: "Slack",
                    params: ["text": "{{channel}}"],
                    waitAfter: .init(condition: "sleep", value: nil, timeout: 0.2),
                    note: "Type channel",
                    onFailure: "stop"
                ),
                .init(
                    id: 4,
                    action: "press_key",
                    targetApp: "Slack",
                    params: ["key": "return"],
                    waitAfter: .init(condition: "sleep", value: nil, timeout: 0.5),
                    note: "Open channel",
                    onFailure: "stop"
                ),
                .init(
                    id: 5,
                    action: "wait",
                    targetApp: "Slack",
                    target: .init(
                        criteria: [
                            .init(attribute: "AXRole", value: "AXTextArea")
                        ],
                        computedNameContains: "Message"
                    ),
                    params: [
                        "condition": "elementExists",
                        "timeout": "5"
                    ],
                    waitAfter: nil,
                    note: "Wait for message input",
                    onFailure: "stop"
                ),
                .init(
                    id: 6,
                    action: "focus",
                    targetApp: "Slack",
                    target: .init(
                        criteria: [
                            .init(attribute: "AXRole", value: "AXTextArea")
                        ],
                        computedNameContains: "Message"
                    ),
                    params: nil,
                    waitAfter: .init(condition: "sleep", value: nil, timeout: 0.2),
                    note: "Focus message input",
                    onFailure: "stop"
                ),
                .init(
                    id: 7,
                    action: "type_text",
                    targetApp: "Slack",
                    params: ["text": "{{message}}"],
                    waitAfter: .init(condition: "sleep", value: nil, timeout: 0.2),
                    note: "Type message",
                    onFailure: "stop"
                ),
                .init(
                    id: 8,
                    action: "press_hotkey",
                    targetApp: "Slack",
                    params: ["keys": "cmd,return"],
                    waitAfter: nil,
                    note: "Send message",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "finder-create-folder",
            description: "Create a new folder in Finder.",
            app: "Finder",
            params: [
                "folder_name": .init(type: "string", description: "Folder name", required: true)
            ],
            steps: [
                .init(
                    id: 1,
                    action: "open_app",
                    targetApp: "Finder",
                    params: ["app_name": "Finder"],
                    waitAfter: nil,
                    note: "Open Finder",
                    onFailure: "stop"
                ),
                .init(
                    id: 2,
                    action: "press_hotkey",
                    targetApp: "Finder",
                    params: ["keys": "cmd,shift,n"],
                    waitAfter: nil,
                    note: "Create folder",
                    onFailure: "stop"
                ),
                .init(
                    id: 3,
                    action: "type_text",
                    targetApp: "Finder",
                    params: ["text": "{{folder_name}}"],
                    waitAfter: nil,
                    note: "Type folder name",
                    onFailure: "stop"
                ),
                .init(
                    id: 4,
                    action: "press_key",
                    targetApp: "Finder",
                    params: ["key": "return"],
                    waitAfter: nil,
                    note: "Confirm folder",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "search-google",
            description: "Search Google in the default browser.",
            app: "Browser",
            params: [
                "query": .init(type: "string", description: "Search terms", required: true)
            ],
            steps: [
                .init(
                    id: 1,
                    action: "search_web",
                    targetApp: nil,
                    params: ["query": "{{query}}"],
                    waitAfter: nil,
                    note: "Search the web",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        ),
        ActionAssistantRecipe(
            name: "inspect-browser-context",
            description: "Read the current browser URL and focused title into recipe variables.",
            app: "Browser",
            params: nil,
            steps: [
                .init(
                    id: 1,
                    action: "read_current_url",
                    targetApp: nil,
                    target: nil,
                    params: ["assign": "current_url"],
                    waitAfter: nil,
                    note: "Read current URL",
                    onFailure: "stop"
                ),
                .init(
                    id: 2,
                    action: "read_focused_title",
                    targetApp: nil,
                    target: nil,
                    params: ["assign": "focused_title"],
                    waitAfter: nil,
                    note: "Read focused title",
                    onFailure: "stop"
                )
            ],
            onFailure: "stop"
        )
    ]

    static func recipe(named name: String) -> ActionAssistantRecipe? {
        all.first { $0.name == name }
    }

    static func localizedTitle(for recipe: ActionAssistantRecipe) -> String {
        switch recipe.name {
        case "open-gmail": return AppLocalization.localizedString("Open Gmail")
        case "open-slack": return AppLocalization.localizedString("Open Slack")
        case "open-notion": return AppLocalization.localizedString("Open Notion")
        case "open-linear": return AppLocalization.localizedString("Open Linear")
        case "open-x": return AppLocalization.localizedString("Open X")
        case "open-calendar": return AppLocalization.localizedString("Open Calendar")
        case "gmail-compose": return AppLocalization.localizedString("Open Gmail draft")
        case "gmail-compose-window": return AppLocalization.localizedString("Open Gmail compose window")
        case "slack-send": return AppLocalization.localizedString("Send Slack message")
        case "finder-create-folder": return AppLocalization.localizedString("Create Finder folder")
        case "search-google": return AppLocalization.localizedString("Search Google")
        case "inspect-browser-context": return AppLocalization.localizedString("Inspect browser context")
        default: return recipe.name
        }
    }

    static func localizedDescription(for recipe: ActionAssistantRecipe) -> String {
        switch recipe.name {
        case "open-gmail": return AppLocalization.localizedString("Open Gmail in the default browser.")
        case "open-slack": return AppLocalization.localizedString("Open Slack app.")
        case "open-notion": return AppLocalization.localizedString("Open Notion app.")
        case "open-linear": return AppLocalization.localizedString("Open Linear in the default browser.")
        case "open-x": return AppLocalization.localizedString("Open X in the default browser.")
        case "open-calendar": return AppLocalization.localizedString("Open Calendar app.")
        case "gmail-compose": return AppLocalization.localizedString("Open a prefilled Gmail compose draft in the default browser.")
        case "gmail-compose-window": return AppLocalization.localizedString("Open Gmail and click Compose.")
        case "slack-send": return AppLocalization.localizedString("Open a Slack channel and send a message.")
        case "finder-create-folder": return AppLocalization.localizedString("Create a new folder in Finder.")
        case "search-google": return AppLocalization.localizedString("Search Google in the default browser.")
        case "inspect-browser-context": return AppLocalization.localizedString("Read the current browser URL and focused title into recipe variables.")
        default: return recipe.description
        }
    }
}

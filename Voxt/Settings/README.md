# Settings

Settings presentation layer for app configuration, feature tuning, permissions, models, and provider setup.

## Responsibilities

- Hosts the settings shell, general panes, dialogs, sheets, and shared settings controls.
- Separates large settings areas such as models, features, dictionary, history, onboarding, and enhancement.
- Keeps settings UI state and validation close to the screens that own it.

Remote provider sheets separate `RemoteProviderSheetSnapshot` (configuration/generation assembly) and `RemoteProviderSheetValidation` (endpoint and field validation) from model/credential controls and operations. State remains in the parent SwiftUI view; these extensions are not independent owners. Removed menus and old OpenAI state were unused; persisted provider compatibility fields and credential edit intent remain unchanged. Codex model-loading and connection-test task lifetimes still need a separate review.

`PermissionsSettingsView` retains permission state, cancellable refresh/request/test tasks, and persistence. `BrowserAutomationPermissionProbes` separates their inputs/results and existing nonisolated native checks; extraction does not change the prompting or authorization policy.

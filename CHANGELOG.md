# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

## [Unreleased]

## [1.5.1] - 2026-03-14

### Fixed
- Improved Hotkey settings shortcut capture so newly recorded shortcuts stay pending until the user explicitly confirms them.
- Prevented global hotkey handlers from firing while recording a shortcut in Hotkey settings.
- Improved modifier-only shortcut capture reliability, including better handling for repeated modifier changes during recording.

## [1.5.0] - 2026-03-13

### Added
- Added configurable voice end commands in Hotkey settings with presets for `over`, `end`, `完毕`, plus custom command text.
- Added automatic stop from spoken end commands when the command appears at the transcript tail and is followed by about 1 second of silence.
- Added feedback entry points in the About tab and status bar menu, both linked to the GitHub issue chooser.

### Changed
- Updated the About tab tagline to `Voice to Thought` with localized Simplified Chinese copy `思想之声`.
- Refactored voice end command handling into focused recording/session and settings components to reduce coupling across `AppDelegate` and settings views.
- Simplified remote ASR stop flows and session task cleanup by extracting reusable helpers for streaming shutdown and recording lifecycle control.

### Fixed
- Fixed trailing end-command matching so surrounding punctuation, including Asian punctuation such as `，。！？`, is ignored reliably.
- Fixed final transcription output so spoken control commands are stripped from committed text, including when the user manually stops after the command.
- Fixed remote ASR file-recording shutdown to release the microphone capture object immediately after stop instead of holding it until upload/transcription completes.

## [1.4.8] - 2026-03-11

### Added
- Added configuration export/import in General settings for app preferences, models, app branch rules, and hotkeys.
- Added model setup warning badges after configuration import to guide users to incomplete provider or model setup.

### Fixed
- Fixed Sparkle no-update results so "already up to date" no longer appears as update check failure in settings.
- Fixed app branch configuration export so group and URL entries are serialized from their stored data payloads.

## [1.4.7] - 2026-03-10

### Added
- Added localized prompt template variable chips with copy interaction and hover tips in settings.
- Added app branch prompt templating support with `{{RAW_TRANSCRIPTION}}`.
- Added LLM debug log output for prompt input and model output content.
- Added shortcut preset support for `fn` and right-side `Command` combinations.
- Added optional left/right modifier distinction for shortcuts, including recording and display support.

### Changed
- Updated app branch prompt delivery so matched branch prompts can be sent as direct user messages.
- Refined prompt variable help UI with system popover tooltip behavior and improved hover persistence.
- Improved shortcut settings UI with preset selection and left/right modifier controls.

### Fixed
- Fixed remote realtime ASR start/stop races that could desync hotkey state and recording UI.
- Fixed proxy-disabled networking so WebSocket traffic no longer relies on legacy proxy behavior alone.
- Fixed accessibility permission prompting/registration flow so installed apps register more reliably in macOS Accessibility settings.
- Fixed hotkey matching so right-side modifier shortcuts no longer trigger from left-side keys when left/right distinction is enabled.
- Fixed app branch prompt handling and prompt editor guidance to align with current enhancement behavior.

## [1.4.2] - 2026-03-09

### Added
- Added prompt template variable support for enhancement and translation:
  - Enhancement: `{{RAW_TRANSCRIPTION}}`
  - Translation: `{{TARGET_LANGUAGE}}`, `{{SOURCE_TEXT}}`
- Added prompt variable hints below prompt textareas in model settings (localized in English, Simplified Chinese, and Japanese).
- Added OpenAI ASR chunk pseudo-realtime preview option (default off) with explicit usage-cost hint.

### Changed
- Updated default enhancement prompt to the new structured instruction template with strict output constraints.
- Updated default translation prompt to the new structured template with explicit target/source variable blocks and strict translation rules.
- Improved recording overlay waveform visibility and interaction feedback (stronger amplitude response, higher dynamic range, clearer bar rendering).

### Fixed
- Fixed OpenAI ASR preview text rendering/parsing in overlay to avoid JSON-like raw payload display artifacts.
- Fixed update check/install UX to reduce disruptive failure popups and surface status via settings sidebar badge with detail action.

### Refactored
- Reduced settings-layer coupling by extracting remote provider configuration sheet from `ModelSettingsView`.
- Moved remote provider connectivity test logic to `RemoteProviderConnectivityTester` (support layer).
- Moved remote provider model/endpoint selection policy to `RemoteProviderConfigurationPolicy` (support layer).
- Simplified update state handling and notification flow in `AppUpdateManager`.

## [1.4.1] - 2026-03-09

### Fixed
- Fixed Sparkle update installer configuration and release checks to prevent package install launch failures.

## [1.4.0] - 2026-03-08

- Release v1.4.0.

## [1.3.11] - 2026-03-06

### Fixed
- Fixed Sparkle package installer launch failures (e.g. `code 4005`) by expanding Sparkle entitlements placeholders in the release signing step so `Installer.xpc` can launch with the correct bundle identifier.

## [1.3.10] - 2026-03-06

- Release v1.3.10.

## [1.3.3] - 2026-03-05

### Fixed
- Fixed the About page log export action in menu-bar/dockless contexts by using a window-attached save sheet when possible and adding explicit export status feedback.

## [1.3.2] - 2026-03-05

### Fixed
- Fixed update version comparison by aligning app `CURRENT_PROJECT_VERSION` with Sparkle `sparkle:version`, preventing `1.3.1` from repeatedly showing `1.3.1 (1003001)` as an available update.
- Added detailed Sparkle update lifecycle logs (check source, found/not found, download success/failure, cycle completion, and abort details) to support in-app log export troubleshooting.

## [1.3.1] - 2026-03-05

### Changed
- Refactored app startup and runtime logic into focused `AppDelegate` extensions for better maintainability:
  - `AppDelegate+MenuWindow`
  - `AppDelegate+PreferencesAndHistory`
  - `AppDelegate+EnhancementPrompt`
  - `AppDelegate+RecordingSession`
- Extracted shared settings/domain types and reusable UI components to reduce file size and duplication.

### Fixed
- Sparkle update channel selection now defaults to stable feed unless `VOXT_UPDATE_CHANNEL=beta` is explicitly set, avoiding accidental use of test beta appcast entries that can trigger EdDSA security warnings.

## [1.3.0-beta.1] - 2026-03-04

### Added
- App Branch source card now shows an Apps-tab drag hint in the header.
- Added custom LLM model options:
  - `mlx-community/Qwen3.5-0.8B-MLX-4bit`
  - `mlx-community/Qwen3.5-2B-MLX-4bit`

### Changed
- Upgraded `mlx-swift-lm` to a newer revision with `qwen3_5` model-type support.
- Improved App Branch localization coverage for tab content and related sheets.

### Fixed
- Fixed custom LLM download cancellation UI state not resetting reliably.
- Fixed custom LLM large-file progress display by aligning in-flight progress logic with MLX model download behavior.
- Fixed App Branch language switching inconsistency when switching to English.

## [1.1.8] - 2026-03-02

### Added
- Release v1.1.8.


## [1.1.7] - 2026-03-02

### Added
- Release v1.1.7.

## [1.1.5] - 2026-03-01

### Fixed
- Added a close action for the in-app update dialog so users can dismiss it.

## [1.1.4] - 2026-03-01

### Added
- Persistent application logs with local file storage.
- About page Logs section with last update time and export of latest 2000 entries.

### Changed
- Localized the new Logs export/status copy in English, Japanese, and Simplified Chinese.

### Fixed
- Updated app sandbox user-selected file access to read/write so save panel can be shown.

## [1.1.3] - 2026-03-01

### Added
- Release v1.1.3.


## [1.1.2] - 2026-03-01

### Added
- Release v1.1.2.


### Added
- Test release based on local Voxt.app archive package.
- In-app update checks with menu entry and optional automatic check at launch.
- Release scripts for generating `.app.zip`, `.pkg`, and update manifest.

## [1.1.1] - 2026-03-01

### Added
- Test release based on local Voxt.app archive package.

## [1.1.6] - 2026-03-01

### Added
- Added the ability to skip a specific update version in update checks.

### Fixed
- Added microphone permission checks before starting dictation recording.
- Fixed hotkey event callback ownership handling in the event tap callback.
- Fixed update installer download handling by staging the package before completion callback returns.

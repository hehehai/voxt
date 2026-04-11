# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

## [Unreleased]

## [1.9.2] - 2026-04-11

### Added
- Added a dedicated transcription detail window with chat-style history, timestamps, copy actions, and follow-up questions.

### Changed
- Reworked rewrite follow-up interactions so continue mode keeps the action available, streams updates more clearly, and follows new content more reliably.
- Improved remote LLM provider handling and streaming parsing for rewrite conversations, including better compatibility with Aliyun chat-completions style responses.

### Fixed
- Fixed feature-specific model routing so transcription, translation, rewrite, and meeting workflows use their own configured models more consistently in runtime and history.
- Fixed ASR runtime switching so changing the selected speech model no longer leaves the first recording attempt unresponsive.

## [1.9.1] - 2026-04-10

### Fixed
- Fixed remote ASR realtime sessions so Doubao and Aliyun connections release network resources more cleanly during long-running use.

## [1.9.0] - 2026-04-09

### Added
- Added filtered feature-specific model pickers so you can quickly choose installed, configured, local, remote, and in-use models for transcription, translation, rewrite, and meeting workflows.
- Added dedicated meeting workflow controls for meeting-only ASR, summary model, prompt, realtime translation target, and screen-sharing visibility in onboarding and Settings.
- Added Doubao dictionary boosting controls so active Voxt dictionary hotwords and corrections can be sent with each ASR request when needed.

### Changed
- Reworked Settings and onboarding around feature-focused flows, with clearer guidance for permissions, model setup, downloads, and shortcut configuration.
- Improved remote provider setup with endpoint presets, meeting ASR testing, and clearer provider-specific guidance.

## [1.8.6] - 2026-04-07

### Fixed
- Fixed Doubao remote ASR streaming shutdown so successful transcriptions no longer trigger protocol sequence mismatch warnings when you stop a session.

## [1.8.5] - 2026-04-07

### Added
- Added dedicated Direct Dictation settings for locale selection, contextual phrases, on-device recognition, punctuation, and partial-result preferences.
- Added live download progress, cancel actions, and clearer status details for MLX, Whisper, and custom local model downloads in Settings and onboarding.

### Changed
- Improved onboarding and model settings so download states stay visible, demo previews handle loading more gracefully, and model lists fit the available space more reliably.

### Fixed
- Fixed Doubao remote ASR live sessions so transcription and meeting captures keep streaming updates and final transcript segments more reliably.
- Fixed Doubao remote ASR retries and transcript assembly so trailing text is less likely to be dropped after interrupted uploads.
- Fixed remote ASR failure handling so network, timeout, authentication, quota, and availability problems now show clearer user-facing guidance.

## [1.8.4] - 2026-04-06

### Added
- Added a new Chinese voice end command preset for saying `好了`.

### Changed
- Expanded the built-in local MLX speech model list with more Qwen3 ASR, Voxtral, Parakeet, Granite, FireRed, and SenseVoice options.

### Fixed
- Fixed remote provider credentials so API keys and tokens are stored in the macOS keychain instead of exported preferences.
- Fixed sided modifier shortcut recording so left and right modifier keys are captured more reliably.

## [1.8.3] - 2026-03-27

### Fixed
- Fixed permission warnings so Settings only asks for permissions that are actually required by enabled features.
- Fixed App Branch matching so groups with an empty prompt no longer override the default enhancement flow.
- Fixed rewrite output handling so the answer card stays available more reliably when that mode is enabled.
- Improved meeting detail timing and summary defaults for clearer post-meeting review.

## [1.8.2] - 2026-03-26

### Fixed
- Fixed the local Whisper transcription dependency so Voxt builds reliably with the current Xcode toolchain.
- Fixed custom select controls in Settings so choosing a different option updates immediately again.

## [1.8.1] - 2026-03-25

### Changed
- Lowered the minimum supported macOS version to 15.0 so Voxt can run on more Macs.

### Fixed
- Improved compatibility on macOS 15 by gracefully falling back when Apple Intelligence features or newer system audio APIs are unavailable.
- Added clearer diagnostics around microphone connect and disconnect handling, device priority evaluation, and automatic microphone switching.

## [1.8.0] - 2026-03-24

### Added
- Added an AI meeting summary sidebar with saved summaries and follow-up chat directly inside Meeting details.
- Added a screen sharing toggle in the meeting overlay so meeting captures can include shared-screen context when needed.

### Changed
- Refreshed the settings and Meeting detail interfaces with more consistent controls, layouts, and localized guidance.

### Fixed
- Improved meeting summary and onboarding reliability with tighter prompt handling and more isolated preference test coverage.

## [1.7.1] - 2026-03-23

### Added
- Added a first-run setup guide in the main window with step-by-step onboarding for language, models, transcription, translation, rewrite, app enhancement, and meeting notes.

### Changed
- Refined the onboarding flow with simpler shortcut presets, contextual permission prompts, inline demo videos, and localized guidance across English, Simplified Chinese, and Japanese.

### Fixed
- Fixed meeting transcript translation updates so existing translated text stays visible while background refreshes complete, instead of flashing a loading state on every update.

## [1.7.0] - 2026-03-23

### Added
- Added a separate on-device Whisper engine powered by WhisperKit, with built-in Whisper model downloads and configurable realtime, VAD, timestamp, and temperature options.
- Added Meeting Notes (Beta), a dedicated long-running meeting capture flow with its own shortcut, floating meeting card, Meeting history entries, and detail window review/export support.
- Added meeting-specific Remote ASR setup for Doubao ASR and Aliyun Bailian ASR, including dedicated Meeting ASR model selection and request-path testing.

### Changed
- Refined the meeting capture experience with clearer model initialization states, pause/resume controls, timestamped segments, click-to-copy, and smoother long-running overlay behavior.
- Expanded localization and configuration transfer coverage for the new meeting workflow and Whisper settings across English, Simplified Chinese, and Japanese.

### Fixed
- Fixed `fn` hotkey recovery after idle and hardened recording start handling so shortcut-triggered capture sessions resume more reliably.
- Improved Whisper startup and meeting control stability during longer transcription sessions.

## [1.6.6] - 2026-03-20

### Added
- Added a General setting to cancel the active overlay with `Esc`, plus optional overlay appearance controls for opacity, corner radius, and screen edge distance.
- Added manual dictionary replacement match terms so custom aliases can map directly to a standard term.

### Changed
- Refined the recording waveform so the voice bars now feel like audio waves moving from left to right.

### Fixed
- Reduced idle memory after local MLX transcription or LLM use by unloading on-device models after they sit unused.
- Fixed General configuration export/import so the latest `Esc` cancel and overlay appearance settings are preserved.
- Fixed the permissions page so Speech Recognition only appears when the selected transcription engine actually needs system dictation.

## [1.6.5] - 2026-03-19

### Added
- Added built-in Doubao ASR 2.0 and 1.0 model options, with 2.0 now used as the default selection for new setups.

### Fixed
- Fixed Doubao ASR realtime routing so 2.0 now connects through the supported streaming endpoint, while file and connectivity-test flows keep using the compatible endpoint and payload format.
- Reduced extra Doubao diagnostic log noise during normal recording and settings connectivity tests.

## [1.6.4] - 2026-03-19

### Fixed
- Reduced idle and active CPU usage in the status menu and recording overlay by replacing broad menu rebuild triggers with targeted updates and by stopping hidden overlay animations from continuing to drive SwiftUI layout work.
- Improved recording waveform feedback so the voice bars animate more smoothly and remain visually clearer during transcription while keeping the lower CPU overhead.
- Removed answer card button tooltips to reduce redundant hover chrome in the rewrite result UI.

## [1.6.3] - 2026-03-19

### Fixed
- Reissued the latest patch release with Sparkle-compatible plain-text auto-update release notes so update feeds no longer depend on Markdown-formatted release bodies.
- Includes the rewrite overlay, answer injection, dictionary ingest, history UI, and `fn` hotkey fixes shipped in the 1.6.2 patch line.

## [1.6.2] - 2026-03-19

### Changed
- Simplified rewrite output behavior so rewrite always shows the answer card, while keeping the General settings UI aligned with the new fixed behavior.
- Improved dictionary ingest and history surfaces by reducing candidate-only UI noise and surfacing direct dictionary hits more clearly.

### Fixed
- Fixed rewrite answer card actions and loading feedback, including the inject action, loading spinner sizing, and icon alignment in the recording overlay.
- Fixed rewrite answer injection availability by improving focused input detection and adding a safer fallback for apps that do not expose standard accessibility focused elements.
- Fixed modifier-only hotkey handling so `fn` no longer steals unrelated combos such as `fn+1`, while preserving dedicated `fn+shift` and `fn+control` shortcuts.
- Fixed overlay session startup so stale transcription text is cleared before a new recording card appears.

## [1.6.1] - 2026-03-17

### Added
- Added a configurable dictionary ingest flow with localized settings copy and model selection controls.

### Changed
- Refined rewrite answer card behavior and related recording overlay handling for rewrite and translation result flows.

### Fixed
- Persisted dictionary ingest model selection across launches and configuration export/import.
- Localized rewrite setting labels consistently across English, Simplified Chinese, and Japanese, and fixed settings window stability issues.

## [1.6.0] - 2026-03-16

### Added
- Added a dictionary workflow with scoped terms, history-based candidate suggestions, one-click ingestion, and prompt-time dictionary guidance.
- Added user main language selection plus engine hint settings for MLX and remote ASR providers, including provider-specific language handling for OpenAI, GLM, Doubao, and Aliyun.
- Added menu bar microphone switching and a General setting that can mute other apps' media audio during recording after system audio capture permission is granted.

### Changed
- Expanded configuration export/import so it now covers dictionary data, voice end command settings, user main language, ASR hint settings, and the latest General settings additions.
- Improved settings organization and localization for the new dictionary, language, and ASR hint workflows across English, Simplified Chinese, and Japanese.

### Fixed
- Fixed custom hotkey recording so modifier-heavy shortcuts are captured more reliably and no longer leak into active global hotkey handling while recording.

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

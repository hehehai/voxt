# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

## [Unreleased]

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

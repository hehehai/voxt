<p align="center">
  <img src="Voxt/logo.svg" width="108" alt="Voxt Logo">
</p>

<h1 align="center">Voxt</h1>

<p align="center">
  A menu bar voice input and translation app for macOS.
  Press to talk, release to paste.
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-26.0%2B-black">
  <a href="https://github.com/hehehai/voxt/releases/latest">
    <img alt="Release" src="https://img.shields.io/github/v/release/hehehai/voxt?label=release&color=brightgreen">
  </a>
  <img alt="License" src="https://img.shields.io/badge/License-Apache%202.0-blue">
</p>

<p align="center">
  <a href="README.zh-CN.md">中文文档</a>
</p>

## Download

- Latest release: https://github.com/hehehai/voxt/releases/latest
- Install via Homebrew (recommended):

  ```bash
  brew tap hehehai/tap
  brew install --cask voxt
  ```

## Core Features

- Global hotkey voice input from any app.
- Two shortcut actions:
  - `Transcription`
  - `Translation` (transcribe then translate)
- Two trigger modes:
  - `Long Press (Release to End)`
  - `Tap (Press to Toggle)`
- Selected-text direct translation:
  - Press translation shortcut with selected text to translate and replace directly.
- Single-session guard:
  - Only one recording session can run at the same time.
- Overlay window:
  - Live waveform, preview text, processing state, final result.
- Clipboard-safe auto paste:
  - Restores previous clipboard content after paste.
- History:
  - Local storage with copy/delete/clear and mode tags.

## Speech-to-Text Engines

### Local

- `MLX Audio (On-device)` with downloadable models.
- `Direct Dictation` via Apple `SFSpeechRecognizer`.

### Remote ASR (OpenAI-compatible + provider-specific)

Voxt supports multiple remote providers in **Model Settings -> Remote ASR Providers**:

- OpenAI Whisper/Transcribe style endpoints
- Doubao ASR
- GLM ASR
- Aliyun Bailian ASR (Realtime WebSocket)

Notes:

- Aliyun Bailian ASR in Voxt is realtime-focused; configure the matching WS endpoint and model family.
- OpenAI ASR supports an optional **Chunk Pseudo Realtime Preview** switch:
  - Path: Remote ASR provider config sheet (OpenAI ASR)
  - Default: `OFF`
  - Meaning: segment-based pseudo realtime preview during recording
  - Cost impact: roughly doubles usage

## Text Enhancement and Translation

- `Off`
- `Apple Intelligence (FoundationModels)`
- `Custom LLM` (local)
- `Remote LLM`

Remote LLM providers are configurable in **Model Settings -> Remote LLM Providers**.
Translation can use either local Custom LLM or selected Remote LLM provider.

## Update Behavior

Voxt uses Sparkle update feed checks.

- If a new version is found:
  - A status badge appears under the left sidebar in Settings.
- If update check fails:
  - No blocking popup for routine check failure.
  - A warning badge is shown in Settings sidebar.
  - Click badge to open details and retry.

This keeps failures visible but non-disruptive during normal use.

## Network and Proxy Behavior

- Network mode can run with direct connection strategy.
- Logs include detected system proxy state for diagnostics.
- For provider test failures (403/handshake), verify:
  - endpoint correctness
  - API key/account region binding
  - local proxy/VPN/path routing

## Permissions

Voxt may request:

- Microphone
- Accessibility
- Input Monitoring
- Speech Recognition (for Dictation)
- Automation (browser active tab matching, optional)

## Build

```bash
xcodebuild -project Voxt.xcodeproj -scheme Voxt -destination 'platform=macOS' build
```

## Architecture Notes

- `AppDelegate+*` files split session flow by stage (recording, transcription, translation, finalize).
- `Support/` contains service abstractions (update, network, model config, history, enhancement).
- `Transcription/` contains local and remote transcriber implementations.
- `Settings/` contains modular SwiftUI settings sections and provider configuration UI.

## License

Apache 2.0. See [LICENSE](LICENSE).

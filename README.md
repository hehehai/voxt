<p align="center">
  <img src="Voxt/logo.svg" width="108" alt="Voxt Logo">
</p>

<h1 align="center">Voxt</h1>

<p align="center">
  A menu bar voice input and translation app for macOS. Press to talk, release to paste.
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-26.0%2B-black">
  <a href="https://github.com/hehehai/voxt/releases/latest">
    <img alt="Release" src="https://img.shields.io/github/v/release/hehehai/voxt?label=release&color=brightgreen">
  </a>
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green">
  <img alt="STT" src="https://img.shields.io/badge/STT-MLX%20Audio%20%7C%20Apple%20Speech-blue">
  <img alt="LLM" src="https://img.shields.io/badge/LLM-Apple%20Intelligence%20%7C%20Custom%20LLM-8A2BE2">
  <img alt="Type" src="https://img.shields.io/badge/App-Menu%20Bar-444">
</p>
<p align="center">
  <a href="README.zh-CN.md">中文导航</a>
</p>

## Video

https://github.com/user-attachments/assets/23d42c24-7128-4bdb-bc1d-98509e69d97e

[macos install](https://github.com/hehehai/voxt/releases/latest)

## Features

- Global hotkey voice input from any app.
- Two shortcut actions:
  - `Transcription` (normal speech-to-text)
  - `Translation` (speech-to-text then translation)
- Two trigger modes: `Long Press (Release to End)` / `Tap (Press to Toggle)`.
- Two STT engines:
  - `MLX Audio (On-device)` with local downloadable models
  - `Direct Dictation` powered by Apple Speech
- Two LLM paths:
  - `Apple Intelligence (Foundation Models)`
  - `Custom LLM` (local model)
- Translation target languages: English / Chinese (Simplified) / Japanese / Korean / Spanish / French / German.
- Live floating overlay: waveform, scrolling partial text, processing animation, completion state.
- Smart output option: copy-only when no writable text input is focused.
- Clipboard-safe paste flow: restores previous clipboard content.
- Local transcription history with pagination, copy, delete, clear-all, and `Normal / Translation` tags.
- App Branch enhancement rules with drag-and-drop grouping for apps and URL patterns.
- Browser active-tab URL matching (Chrome / Safari / Arc) with per-browser Automation permission flow.
- Model download manager with progress, cancel, delete, size display, validation, and `hf-mirror.com` support.
- System controls: microphone selection, interaction sounds, launch at login, show in Dock.

## Implementation

1. `CGEvent tap` listens for global shortcuts (transcription and translation are separate).
2. `AVAudioEngine` captures audio and updates live levels.
3. Voxt picks the STT engine based on settings:
   - MLX: staged correction (intermediate + final pass)
   - Dictation: streaming `SFSpeechRecognizer` output
4. Text pipeline by mode:
   - Transcription mode: optional enhancement (Off / Apple Intelligence / Custom LLM)
   - Translation mode: optional enhancement first, then translate to target language
5. Output is injected with clipboard + simulated `Cmd+V`, and metadata can be saved to history.

## Engines

### STT Engines

| Engine | Description | Strength | Typical Use |
| --- | --- | --- | --- |
| MLX Audio | Runs local MLX STT models | Offline, private, model-selectable | Privacy-focused and tunable setup |
| Direct Dictation | Apple Speech (`SFSpeechRecognizer`) | Zero setup | Fast onboarding without model download |

### Enhancement / Translation Engines

| Engine | Tech Path | Strength | Notes |
| --- | --- | --- | --- |
| Apple Intelligence | `FoundationModels` | Native system experience, no extra LLM download | Depends on system availability |
| Custom LLM | Local `MLXLMCommon` + Hugging Face model | Fully local, customizable prompts | Requires model download first |

## Models

### MLX STT Models

- `mlx-community/Qwen3-ASR-0.6B-4bit` (default): balanced speed and quality, lower memory usage.
- `mlx-community/Qwen3-ASR-1.7B-bf16`: quality-first, higher resource usage.
- `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16`: realtime-oriented, larger footprint.
- `mlx-community/parakeet-tdt-0.6b-v3`: lightweight and fast, especially good for English.
- `mlx-community/GLM-ASR-Nano-2512-4bit`: smallest footprint for quick drafts.

### Custom LLM Models

- `Qwen/Qwen2-1.5B-Instruct` (default): general enhancement/translation with lower resource pressure.
- `Qwen/Qwen2.5-3B-Instruct`: stronger formatting/reasoning with higher resource usage.
- `mlx-community/Qwen3.5-0.8B-MLX-4bit`: lightweight Qwen3.5 option with fast local inference.
- `mlx-community/Qwen3.5-2B-MLX-4bit`: higher-quality Qwen3.5 option with moderate resource usage.

## Model Comparison (Relative)

> Notes: this table is a relative guide based on model positioning and common usage experience, not a fixed cross-device benchmark.

### STT Model Comparison

| Model | Speed | Accuracy | Resource Usage | Recommended For |
| --- | --- | --- | --- | --- |
| Qwen3-ASR 0.6B (4bit) | Medium-High | Medium-High | Low | Daily default |
| Qwen3-ASR 1.7B (bf16) | Medium | High | High | Quality-first usage |
| Voxtral Realtime Mini 4B (fp16) | High | Medium-High | High | Realtime feedback priority |
| Parakeet 0.6B | High | Medium | Low | Fast English input |
| GLM-ASR Nano (4bit) | High | Medium-Low | Very Low | Low-resource devices / drafts |

### LLM Model Comparison

| Model | Output Quality | Speed | Resource Usage | Recommended For |
| --- | --- | --- | --- | --- |
| Qwen2 1.5B Instruct | Medium-High | High | Low-Medium | General enhancement and translation |
| Qwen2.5 3B Instruct | High | Medium | Medium-High | Better formatting and consistency |

## Install & Build

### Requirements

- macOS `26.0+`
- Microphone permission
- Accessibility permission (global hotkeys and simulated paste)
- Speech Recognition permission for `Direct Dictation`

### Distribution

- Download release directly:
  - https://github.com/hehehai/voxt/releases/latest
- Install steps:
  1. Download and unzip the latest `.zip` package from the release page.
  2. Drag `Voxt.app` into `Applications`.
  3. Launch `Voxt` and grant required permissions on first run.
  4. If Gatekeeper blocks launch, right-click `Voxt.app` -> `Open`.

### Local Build

1. Open `Voxt.xcodeproj` in Xcode and run.
2. Or build from terminal:

```bash
xcodebuild -project Voxt.xcodeproj -scheme Voxt -destination 'platform=macOS' build
```

## Thanks

- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)
- [Kaze](https://github.com/fayazara/Kaze)
- Apple `Speech` / `FoundationModels` / AppKit / SwiftUI

## License

MIT, see [LICENSE](LICENSE).

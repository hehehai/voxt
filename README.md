<div align="center"><a name="readme-top"></a>

<img src="Voxt/logo.svg" width="118" alt="Voxt Logo">

# Voxt

A macOS menu bar voice input and translation app. Hold to speak, release to paste. <br>AI transcription with different rules for different apps and URLs.

**English** · [简体中文](./docs/README.zh-CN.md) · [Report Issues][github-issues-link] · [Prompt](./docs/Prompt.md)

[![][github-release-shield]][github-release-link]
[![][macos-version-shield]][macos-version-link]
[![][license-shield]][license-link]
[![][release-date-shield]][release-date-link]

<img width="2028" height="1460" alt="image" src="https://github.com/user-attachments/assets/ee90a432-746a-457a-96b7-b67713dd49d9" />

</div>

## ✨ Feature Overview Speak, don't type

**Speak and turn voice into text** `fn`

- Live transcription while you speak, with real-time text preview.
- Result enhancement: remove filler words, add punctuation automatically, and customize prompts your own way.
- App Branch groups let different apps or URLs use different enhancement rules and prompts, for coding, chat, email, and more.
- Personal dictionary support can inject exact terms into prompts and optionally auto-correct high-confidence near matches before output.
- Multilingual support with smooth mixed-language input.

**Speak and translate right away** `fn+shift`

- AI translation immediately after transcription.
- Selected-text translation: highlight text and translate it directly with a shortcut.
- Custom translation prompts and terminology guidance, so output matches your habits.
- Separate model selection for translation, so you can pick the strongest or fastest model for the job.

**Use voice as a prompt** `fn+control`

- Example: "Help me write a 200-word self-introduction." Your speech becomes the prompt, and the result is inserted automatically.
- Rewrite selected text by voice, for example: "Make this shorter and smoother."
- Optional rewrite answer card keeps generated content visible even when no writable input is focused.
- More than voice input: it also works like a voice-driven AI assistant.

[![][back-to-top]](#readme-top)

## Download / Install

- [Latest release](https://github.com/hehehai/voxt/releases/latest)

- Install via Homebrew:

```bash
brew tap hehehai/tap
brew install --cask voxt
```

## Model Support

<img width="1041" height="744" alt="image" src="https://github.com/user-attachments/assets/30d9e4fa-d88e-44db-8ab7-9d216c6a03d8" />

Voxt separates ASR provider models and LLM provider models. They are used for speech-to-text, text enhancement, translation, and rewrite flows respectively.

> System dictation is also supported through Apple Dictation, though multilingual coverage is more limited.

### Local Models

With newer macOS versions and local model support, Voxt currently ships with:

- `MLX Audio` local ASR models
- `Whisper` via WhisperKit, as a separate local ASR engine
- a set of downloadable local LLM models for enhancement, translation, and rewriting

Whisper is not a sub-mode of `MLX Audio`. In Model Settings it appears as its own engine, with its own model list, download flow, and runtime options.

> [!NOTE]
> "Current status / errors" below comes from the current project code. "Language support / speed / recommendation" is summarized from model cards plus project descriptions. Speed and recommendation are for model selection guidance, not a unified benchmark.

Voxt also supports `Direct Dictation` via Apple `SFSpeechRecognizer`:

- Best for: quick setup when you do not want to download local models yet.
- Limitation: relatively limited multilingual support.
- Requirements: microphone permission plus speech recognition permission.
- Common error: `Speech Recognition permission is required for Direct Dictation.`

#### Local ASR Models

| Model | Repository ID | Size | Language Support | Speed | Recommendation | Current Status |
| --- | --- | --- | --- | --- | --- | --- |
| Qwen3-ASR 0.6B (4bit) | `mlx-community/Qwen3-ASR-0.6B-4bit` | 0.6B / 4bit | 30 languages including Chinese, English, Cantonese, and more | Fast | High | Default local ASR, best overall quality/speed balance |
| Qwen3-ASR 1.7B (bf16) | `mlx-community/Qwen3-ASR-1.7B-bf16` | 1.7B / bf16 | Same multilingual family as 0.6B | Medium | Very high | Accuracy-first option with higher memory and storage cost |
| Voxtral Realtime Mini 4B (fp16) | `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` | 4B / fp16 | 13 languages including Chinese, English, Japanese, Korean, and more | Medium | Medium-high | Realtime-oriented model with the largest footprint in this list |
| Parakeet 0.6B | `mlx-community/parakeet-tdt-0.6b-v3` | 0.6B / bf16 | Model card lists 25 languages; project copy positions it as lightweight English-first STT | Very fast | Medium-high | Lightweight high-speed option, especially suitable for English-heavy workflows |
| GLM-ASR Nano (4bit) | `mlx-community/GLM-ASR-Nano-2512-4bit` | MLX 4bit, about 1.28 GB | Current model card clearly states Chinese and English | Fast | High | Smallest footprint, ideal for quick drafts and low-friction deployment |

#### Whisper (WhisperKit)

Voxt also supports `Whisper` as a separate on-device ASR engine through WhisperKit.

- Built-in model list: `tiny`, `base`, `small`, `medium`, `large-v3`
- Current download source: Hugging Face style model paths via `argmaxinc/whisperkit-coreml`
- China mirror: supported through the app's mirror setting
- Common runtime options:
  - `Realtime` toggle, enabled by default
  - `VAD`
  - `Timestamps`
  - `Temperature`
- Current behavior:
  - standard transcription uses Whisper `transcribe`
  - translation hotkey can optionally use Whisper's built-in `translate-to-English` task when Translation provider is set to `Whisper`
  - if Whisper translation is unavailable for the current case, Voxt falls back to the selected LLM translation provider

Curated Whisper model list in Voxt:

| Model | Approx. Download Size | Recommendation | Notes |
| --- | --- | --- | --- |
| Whisper Tiny | about 76.6 MB | Medium | Smallest footprint, best for quick local drafts |
| Whisper Base | about 146.7 MB | High | Default Whisper balance for quality and speed |
| Whisper Small | about 486.5 MB | High | Better recognition quality with moderate local cost |
| Whisper Medium | about 1.53 GB | Very high | Accuracy-first local option with heavier download and memory use |
| Whisper Large-v3 | about 3.09 GB | Very high | Largest local Whisper option, best suited to Apple Silicon Macs with enough disk and memory headroom |

Whisper-specific notes:

- Whisper follows your selected main language for simplified/traditional Chinese output normalization.
- Whisper translation is only direct for speech-to-English scenarios; selected-text translation still uses the normal text translation flow.
- If a Whisper model download is interrupted or corrupted, Voxt now treats it as incomplete and requires a clean re-download instead of trying to load a broken model.

Common local ASR errors / states:

- `Invalid model identifier`
- `Model repository unavailable (..., HTTP 401/404)`
- `Download failed (...)`
- `Model load failed (...)`
- `Size unavailable`
- If you accidentally point to an alignment-only repo, Voxt will show `alignment-only and not supported by Voxt transcription`
- Whisper may additionally surface incomplete-download or broken-model errors if required Core ML weight files are missing

#### Local LLM Models

| Model | Repository ID | Size | Language Bias | Speed | Recommendation | Best For |
| --- | --- | --- | --- | --- | --- | --- |
| Qwen2 1.5B Instruct | `Qwen/Qwen2-1.5B-Instruct` | 1.5B | Balanced Chinese / English | Fast | High | Lightweight cleanup and simple translation |
| Qwen2.5 3B Instruct | `Qwen/Qwen2.5-3B-Instruct` | 3B | Balanced Chinese / English | Medium-fast | High | More stable enhancement and formatting |
| Qwen3 4B (4bit) | `mlx-community/Qwen3-4B-4bit` | 4B / 4bit | Chinese / English / multilingual | Medium-fast | Very high | Best overall local balance for enhancement and translation |
| Qwen3 8B (4bit) | `mlx-community/Qwen3-8B-4bit` | 8B / 4bit | Chinese / English / multilingual | Medium-slow | Very high | Stronger rewriting, translation, and structured output |
| GLM-4 9B (4bit) | `mlx-community/GLM-4-9B-0414-4bit` | 9B / 4bit | Chinese / English / multilingual | Slow | Very high | Chinese rewriting and more complex prompt workflows |
| Llama 3.2 3B Instruct (4bit) | `mlx-community/Llama-3.2-3B-Instruct-4bit` | 3B / 4bit | English-first, multilingual usable | Medium-fast | Medium-high | Lightweight local rewriting |
| Llama 3.2 1B Instruct (4bit) | `mlx-community/Llama-3.2-1B-Instruct-4bit` | 1B / 4bit | English-first, multilingual usable | Very fast | Medium | Lowest-resource local enhancement |
| Meta Llama 3 8B Instruct (4bit) | `mlx-community/Meta-Llama-3-8B-Instruct-4bit` | 8B / 4bit | English-first, multilingual usable | Medium-slow | Medium-high | General enhancement, summarization, rewriting |
| Meta Llama 3.1 8B Instruct (4bit) | `mlx-community/Meta-Llama-3.1-8B-Instruct-4bit` | 8B / 4bit | English-first, multilingual usable | Medium-slow | High | Stable general-purpose local LLM |
| Mistral 7B Instruct v0.3 (4bit) | `mlx-community/Mistral-7B-Instruct-v0.3-4bit` | 7B / 4bit | Stronger in English and European languages | Medium | High | Concise rewrites and formatting cleanup |
| Mistral Nemo Instruct 2407 (4bit) | `mlx-community/Mistral-Nemo-Instruct-2407-4bit` | Nemo family / 4bit | English-first, multilingual usable | Medium-slow | High | More complex local enhancement tasks |
| Gemma 2 2B IT (4bit) | `mlx-community/gemma-2-2b-it-4bit` | 2B / 4bit | English-first, multilingual usable | Fast | Medium-high | Lightweight text cleanup |
| Gemma 2 9B IT (4bit) | `mlx-community/gemma-2-9b-it-4bit` | 9B / 4bit | English-first, multilingual usable | Slow | High | Higher-quality local polishing and translation |

Common local LLM errors / states:

- `Custom LLM model is not installed locally.`
- `Invalid local model path.`
- `Invalid model identifier`
- `No downloadable files were found for this model.`
- `Downloaded files are incomplete.`
- `Download failed: ...`
- `Size unavailable`

### Remote Provider Models

For faster or more realtime transcription and enhancement, configure `Remote ASR` and `Remote LLM` separately in Model Settings. The tables below list only the provider entry points and recommended defaults that Voxt currently exposes in code.

> [!note]
> For the setup tutorial prompt below, you can give it to any AI assistant and let it help you complete the application and configuration process.

```txt
https://raw.githubusercontent.com/hehehai/voxt/refs/heads/main/docs/README.md
https://raw.githubusercontent.com/hehehai/voxt/refs/heads/main/docs/RemoteModel.md
How do I get started configuring remote ASR and LLM? I want to use Doubao ASR and Alibaba Cloud Bailian LLM. Please give me the full application and configuration workflow.

1. For every step that requires visiting a website, include the exact URL.
2. Point out the important notes and required configuration items.
3. Make the key steps more detailed.
```

For fuller provider notes, signup links, endpoints, and configuration examples, see [docs/RemoteModel.md](docs/RemoteModel.md).

#### Remote ASR Providers

| Provider | Built-in Model Options | Language Support | Realtime Support | Speed | Recommendation | Current Integration |
| --- | --- | --- | --- | --- | --- | --- |
| OpenAI Whisper / Transcribe | `whisper-1`, `gpt-4o-mini-transcribe`, `gpt-4o-transcribe` | Multilingual | Partial. Voxt currently uses file-based transcription, with optional chunked pseudo-realtime preview | Medium | High | `v1/audio/transcriptions` |
| Doubao ASR | `volc.seedasr.sauc.duration`, `volc.bigasr.sauc.duration` | Chinese-first, well suited to mixed Chinese/English realtime usage | Yes | Fast | High | Streaming WebSocket ASR |
| GLM ASR | `glm-asr-2512`, `glm-asr-1` | Officially positioned for broad scenarios and accents; Voxt currently integrates it as standard upload-based transcription | No (current implementation is upload transcription) | Medium | Medium-high | HTTP transcription endpoint |
| Aliyun Bailian ASR | `qwen3-asr-flash-realtime`, `fun-asr-realtime`, `paraformer-realtime-*` | Depends on model family: Qwen3 ASR is multilingual, Fun/Paraformer cover Chinese-English or broader multilingual use | Yes | Fast | High | Realtime WebSocket ASR, with separate endpoints for Qwen / Fun / Paraformer families |

Common remote ASR errors / states:

- `Needs Setup`
- Missing API key for OpenAI / GLM / Aliyun
- Missing `Access Token` or `App ID` for Doubao
- `Invalid ASR endpoint URL`
- `Invalid WebSocket endpoint URL`
- `Connection failed (HTTP %d). %@`
- `No valid ASR response packet.`
- Doubao may also fail on GZIP init / decode; Aliyun may additionally fail with `task-failed` or auth-related 403 responses

#### Remote LLM Providers

| Provider | Built-in Recommended Model | API Style | Main Use | Current Status |
| --- | --- | --- | --- | --- |
| Anthropic | `claude-sonnet-4-6` | Native Anthropic | Enhancement / translation / rewrite | Integrated |
| Google | `gemini-2.5-pro` | Native Gemini | Enhancement / translation / rewrite | Integrated |
| OpenAI | `gpt-5.2` | OpenAI-compatible | Enhancement / translation / rewrite | Integrated |
| Ollama | `qwen2.5` | OpenAI-compatible | Local or self-hosted LLM gateway | Integrated |
| DeepSeek | `deepseek-chat` | OpenAI-compatible | Enhancement / translation / rewrite | Integrated |
| OpenRouter | `openrouter/auto` | OpenAI-compatible | Auto-routing across providers | Integrated |
| xAI (Grok) | `grok-4` | OpenAI-compatible | Enhancement / translation / rewrite | Integrated |
| Z.ai | `glm-5` | OpenAI-compatible | Enhancement / translation / rewrite | Integrated |
| Volcengine | `doubao-seed-2-0-pro-260215` | OpenAI-compatible | Enhancement / translation / rewrite | Integrated |
| Kimi | `kimi-k2.5` | OpenAI-compatible | Enhancement / translation / rewrite | Integrated |
| LM Studio | `llama3.1` | OpenAI-compatible | Local or self-hosted LLM gateway | Integrated |
| MiniMax | `MiniMax-M2.5` | Native MiniMax | Enhancement / translation / rewrite | Integrated |
| Aliyun Bailian | `qwen-plus-latest` | OpenAI-compatible | Enhancement / translation / rewrite | Integrated |

Common remote LLM errors / states:

- `Needs Setup`
- Missing provider-specific API key for Anthropic / Google / MiniMax
- `Invalid endpoint URL` / `Invalid Google endpoint URL`
- `Invalid server response.`
- `Server reachable, but authentication failed (HTTP 401/403).`
- `Connection failed (HTTP %d). %@`
- Runtime failures can also appear as `Remote LLM request failed (...)` or `Remote LLM returned no text content.`

[![][back-to-top]](#readme-top)

## Shortcuts

<img width="1005" height="706" alt="image" src="https://github.com/user-attachments/assets/6c995d27-2ef6-44b6-afd8-d7dbef790b09" />


Voxt includes two built-in shortcut presets (`fn Combo` / `command Combo`) and also supports fully custom bindings. Each shortcut set can use one of two trigger styles:

- `Tap (Press to Toggle)`: press once to start, press again to stop
- `Long Press (Release to End)`: hold to start, release to stop

The examples below use the default `fn Combo` preset.

### fn Combo

| Shortcut | Action | Typical Use | Default Interaction |
| --- | --- | --- | --- |
| `fn` | Standard transcription | Voice input and speech-to-text | After recording ends, Voxt enhances and outputs the result into the current input target |
| `fn+shift` | Transcribe and translate | Speak-then-translate, multilingual input | If text is already selected, Voxt translates the selection directly instead of opening the recording flow |
| `fn+control` | Transcribe and rewrite / prompt | Voice-driven prompt generation, or rewriting selected text by voice | If text is selected, Voxt rewrites against the selection; otherwise it treats your speech as an instruction and generates the result |

You can think of them as three working modes:

- `fn`: turn what you say into text
- `fn+shift`: turn what you say into a target language, or directly translate selected text
- `fn+control`: treat your speech as a prompt and let the model generate, rewrite, or polish text

Detailed behavior:

- `fn` standard transcription
  - Tap mode: press `fn` to start recording, then press `fn` again to stop
  - Long-press mode: hold `fn` to record, release to stop
  - Best for quick input, meeting notes, chat replies, and email drafts
- `fn+shift` transcribe + translate
  - Tap mode: press `fn+shift` to start recording; to stop, either press `fn` or press `fn+shift` again
  - Long-press mode: hold `fn+shift` to record, release to stop
  - If text is already selected when triggered, Voxt translates the selection directly without using the microphone flow
  - Best for mixed-language typing, cross-language chat, and quick paragraph translation
- `fn+control` transcribe + rewrite / prompt
  - Tap mode: press `fn+control` to start recording, then press `fn` to stop
  - Long-press mode: hold `fn+control` to record, release to stop
  - Your dictated content is treated as an instruction, for example: "Make this reply more polite" or "Shorten this paragraph"
  - If text is selected, Voxt uses the selection as source material and returns a rewritten final result based on your spoken instruction
  - If nothing is selected, it behaves more like a voice-driven AI assistant input flow

Interaction details:

- In tap mode, `fn` is the unified stop key. That means once a translation session has started, pressing `fn` can also end it.
- To avoid accidental stops, Voxt ignores immediate repeated taps during the very short window right after recording starts.
- `fn+shift` and `fn+control` have higher priority than plain `fn`, so combo presses are not misclassified as regular transcription.
- All shortcuts can be remapped in Settings, and you can switch to the `command Combo` preset at any time.

[![][back-to-top]](#readme-top)

## App Settings

<img width="1000" height="731" alt="image" src="https://github.com/user-attachments/assets/7c674413-1a2a-42f0-abdc-862eb7b89a03" />


`General` controls app-level behavior and day-to-day usage preferences. Unlike the Model page, this is not where you choose which ASR or LLM to run. It is where you define how Voxt records, appears on screen, outputs results, starts with macOS, and manages network/configuration behavior.

Current General settings fall into these groups:

### Configuration

- Export current General, Model, Dictionary, Voice End Command, App Branch, and shortcut settings to JSON
- Import settings from JSON to quickly move your setup to another Mac
- Sensitive fields are replaced with placeholders during export and must be filled in again after import

Useful for:

- syncing settings across multiple devices
- backing up your current workflow
- cloning the same model / shortcut / grouping setup quickly

### Audio

- Choose the microphone input device
- Turn interaction sounds on or off
- Optionally mute other apps' media audio while recording
- Switch interaction sound presets and preview them directly

This section controls where audio comes from and whether Voxt gives you audible start/finish feedback. It matters if you use multiple microphones, external audio devices, or a specific input chain.

### Transcription UI

- Set the floating transcription overlay position

The overlay shows waveform, preview text, and processing state during recording. This setting controls where it appears so it does not block your workspace.

### Languages

- Change the app interface language
- Set `User Main Language` for prompt variables and ASR language hints
- Set the default target language for the translation shortcut

This group controls three different layers:

- Interface language affects only the app UI and currently supports English, Chinese, and Japanese
- `User Main Language` feeds the `{{USER_MAIN_LANGUAGE}}` template variable and provider-specific ASR hint behavior
- Translation target language decides which language the default `fn+shift` flow translates into

### Model Storage

- View the current model storage path
- Open the model folder in Finder
- Change where new local models are stored

This is especially important for local model users.

> [!IMPORTANT]
> After you change the model storage path, previously downloaded models are not migrated automatically, and models in the old path are not detected in the new one. In most cases, you will need to download local models again.

### Output

- `Also copy result to clipboard`
- `Always show rewrite answer card`
- `Translate selected text with translation shortcut`
- `App Enhancement (Beta)`

This section controls how Voxt returns output and whether context-aware enhancement is enabled:

- When "Also copy result to clipboard" is on, Voxt auto-pastes the result and also keeps it in the clipboard
- When "Always show rewrite answer card" is on, rewrite results always open in the answer card instead of only appearing when no writable input is focused
- When "Translate selected text with translation shortcut" is on, the translation shortcut directly translates and replaces the current selection if any text is highlighted
- When `App Enhancement` is enabled, Voxt shows and activates app- and URL-aware enhancement configuration

### Voice End Command

- Enable a spoken stop command for hands-free recording end
- Choose from built-in presets such as `over`, `end`, and `完毕`
- Provide a custom command when preset mode is switched to custom

When enabled, Voxt watches the transcript tail for the configured command and ends the current session automatically after about 1 second of following silence.

### Logging

- Toggle hotkey debug logs
- Toggle LLM debug logs

Useful when diagnosing:

- why a shortcut did not trigger
- why a combo key was misdetected
- what the local or remote LLM request actually sent
- why model output did not match expectations

Recommended default: keep logging off, and only enable it temporarily while debugging.

### App Behavior

- `Launch at Login`: start Voxt automatically at system login
- `Show in Dock`: show or hide Voxt in the macOS Dock
- `Automatically check for updates`: background update checks
- `Proxy`: follow system proxy, disable proxy, or use a custom proxy

This group is about how the app behaves on your Mac:

- If you want Voxt to stay in the menu bar all the time, enable launch at login
- If you want faster access from the Dock, enable Dock visibility
- If you use remote models in a restricted network, company network, or proxy environment, `Proxy` settings directly affect remote ASR and remote LLM connectivity

Current custom proxy support includes:

- HTTP
- HTTPS
- SOCKS5

Host, port, username, and password can be configured. However, in the current codebase, username and password are stored but not yet injected automatically into every request path, which matters in more complex proxy setups.

[![][back-to-top]](#readme-top)

## Dictionary

Voxt includes a dedicated Dictionary tab for terminology you want the app to recognize, preserve, and reuse consistently.

- Dictionary entries can be global or scoped to an App Branch group
- Matched terms are injected back into enhancement, translation, and rewrite prompts as runtime glossary guidance
- High-confidence near matches can be auto-corrected to the exact dictionary term before insertion
- You can import/export the dictionary directly
- `One-Click Ingest` scans recent history with the configured local or remote LLM, proposes candidate terms, and lets you add or dismiss them in batches

This is most useful for names, brands, products, internal project names, acronyms, and user-specific spellings that generic ASR or LLM cleanup often gets wrong.

[![][back-to-top]](#readme-top)

## Permissions

<img width="999" height="712" alt="image" src="https://github.com/user-attachments/assets/47e78969-b51e-4597-8279-37f29b638ce7" />


Voxt permissions are split by function. If you only use basic voice input, only the core permissions are needed. If you want stronger context awareness, such as URL-based `App Branch` matching, enable the extra permissions only when needed.

> [!IMPORTANT]
> If you just want to get Voxt working quickly, start with `Microphone`. If you use the default `fn` shortcut set and want results to be written back into other apps automatically, it is strongly recommended to enable both `Accessibility` and `Input Monitoring`.

### Core Permissions

| Permission | Typical Importance | Used For | What Happens If Not Granted |
| --- | --- | --- | --- |
| Microphone | Required | Recording, speech-to-text, local ASR, remote ASR, translation, rewrite flows | Recording cannot start |
| Speech Recognition | Optional / as needed | Only for `Direct Dictation` / Apple `SFSpeechRecognizer` | Only system dictation becomes unavailable; MLX and remote ASR still work |
| Accessibility | Strongly recommended | Global hotkeys, automatically pasting results back into other apps, reading some UI context | Recording still works, but auto-paste and some cross-app interactions are limited |
| Input Monitoring | Strongly recommended | More reliable global modifier hotkeys, especially `fn`, `fn+shift`, and `fn+control` | Global shortcuts may become unstable, fail, or misfire |
| Automation | Optional | Reading the current browser tab URL for App Branch URL matching | App Branch can still match by foreground app, but not by webpage URL |

Additional notes:

- Microphone permission is a hard requirement for the recording pipeline, regardless of whether you use local models, remote ASR, translation, or rewrite flows.
- Speech Recognition permission is only for Apple system dictation. If you only use `MLX Audio (On-device)` or `Remote ASR`, you can leave it off.
- Accessibility is not just for "seeing the UI". It is also used to write results back into other apps automatically. Without it, Voxt can still work, but results are more likely to stay in the clipboard for manual paste.
- Input Monitoring mainly exists to make modifier-only shortcuts more reliable, which is why it is strongly recommended for the default `fn` shortcut set.
- If you enable "Mute other media audio while recording", Voxt additionally needs macOS system audio recording permission. That permission is only required for that specific feature.

[![][back-to-top]](#readme-top)

## What Is App Branch? (Beta)

<img width="1018" height="729" alt="image" src="https://github.com/user-attachments/assets/888871a9-f5d1-4463-9fc7-91797cc2053a" />

> [!IMPORTANT]
> `App Branch` is not enabled by default. You must first turn on `App Enhancement` in `General -> Output` before App Branch groups and URL-based behavior take effect.

`App Branch` is best understood as "switch prompts and rules automatically based on the current context."

You can group apps or URLs and assign a separate prompt to each group. In different contexts, Voxt automatically switches enhancement, translation, and rewrite behavior. For example:

- in an IDE, it can bias toward code, commands, and technical terminology
- in chat apps, it can bias toward shorter, more conversational replies
- in email or document tools, it can bias toward formal wording and full sentences
- on a specific website, it can apply that site's vocabulary, format, or tone

App Branch currently supports two matching layers:

- match by foreground app: for example Xcode, Cursor, WeChat, or a browser
- match by active browser tab URL: for example `github.com/*`, `docs.google.com/*`, `mail.google.com/*`

### App Branch Permissions

App Branch itself does not always require extra permissions. It depends on how deep you want matching to go:

- If you only group by foreground app, browser automation permission is usually not needed
- If you group by browser URL, you must grant `Automation` permission to the corresponding browser so Voxt can read the active tab URL
- If scripting-based URL reads fail in some browsers, Voxt can also try `Accessibility` as a fallback path

In practice:

- app-level grouping has relatively low permission requirements
- webpage-level grouping requires additional browser automation approval

### App Branch URL Authorization

If you want to use `URL rules`, this is the most important permission area:

- Voxt requests browser automation access to read the current active tab URL
- Without access to the current URL, Voxt cannot determine whether a URL group matches
- Without this permission, Voxt still works, but falls back to the global prompt or app-only matching

> [!TIP]
> Only authorize the browsers you actually want to use for URL grouping. The safest workflow is to grant and test them one by one in `Settings > Permissions > App Branch URL Authorization`.

Built-in or supported browser URL read targets in the current project include:

- Safari / Safari Technology Preview
- Google Chrome
- Microsoft Edge
- Brave
- Arc
- plus any custom browsers you add manually in Settings

Recommendations:

- only authorize the browsers you really need for URL grouping
- grant and test them one by one in `Settings > Permissions > App Branch URL Authorization`
- if you see `Browser URL read test failed: permission denied.`, it usually means browser automation has not been approved yet

[![][back-to-top]](#readme-top)

## License

Apache 2.0. See [LICENSE](LICENSE).

[back-to-top]: https://img.shields.io/badge/-BACK_TO_TOP-151515?style=flat-square
[github-issues-link]: https://github.com/hehehai/voxt/issues/new/choose
[github-release-link]: https://github.com/hehehai/voxt/releases/latest
[macos-version-link]: https://github.com/hehehai/voxt/releases/latest
[license-link]: ./LICENSE
[release-date-link]: https://github.com/hehehai/voxt/releases/latest
[github-release-shield]: https://img.shields.io/github/v/release/hehehai/voxt?label=release&labelColor=000000&color=3fb950&style=flat-square&logo=github&logoColor=white
[macos-version-shield]: https://img.shields.io/badge/macOS-26.0%2B-58a6ff?style=flat-square&labelColor=000000&logo=apple&logoColor=white
[license-shield]: https://img.shields.io/badge/License-Apache%202.0-58a6ff.svg?style=flat-square&labelColor=000000&logo=apache&logoColor=white
[release-date-shield]: https://img.shields.io/github/release-date/hehehai/voxt?style=flat-square&labelColor=000000&color=58a6ff&logo=github&logoColor=white

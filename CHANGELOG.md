# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

## [Unreleased]

## [1.9.8] - 2026-04-20

### Changed
- EN: Improved transcription and meeting history details so they keep the full ongoing conversation in a single record, making follow-up context easier to review and continue.
- 简体中文：优化了转写和会议历史详情，现在同一轮持续对话会保存在同一条记录中，后续查看和继续追问时上下文更完整。
- 日本語：転写と会議の履歴詳細を改善し、継続中の対話全体を 1 件の履歴に保持するようにしたことで、見返しや続きを行う際の文脈がより完整になりました。
- EN: Expanded configuration import and export so more general settings and model setup can move between devices with fewer manual reconfiguration steps.
- 简体中文：扩展了配置导入导出范围，更多通用设置和模型配置现在都能一起迁移，减少了手动重新设置的步骤。
- 日本語：設定のインポートとエクスポート対象を拡張し、より多くの一般設定とモデル構成をまとめて移行できるようにして、手動での再設定を減らしました。

### Fixed
- EN: Fixed remote provider credential storage so saving one provider no longer clears the saved keys, tokens, or IDs from another provider.
- 简体中文：修复了远程服务商凭据保存逻辑，现在保存某一个服务商时，不会再清空其他服务商已保存的密钥、令牌或 ID。
- 日本語：リモートプロバイダの資格情報保存を修正し、あるプロバイダを保存した際に別のプロバイダのキー、トークン、ID が消えないようにしました。
- EN: Fixed Aliyun realtime ASR endpoint handling and model switching, so FunASR and Qwen realtime models use the correct WebSocket route more reliably.
- 简体中文：修复了阿里云实时 ASR 的端点处理和模型切换逻辑，FunASR 与 Qwen 实时模型现在会更可靠地使用正确的 WebSocket 地址。
- 日本語：Aliyun リアルタイム ASR のエンドポイント処理とモデル切り替えを修正し、FunASR と Qwen のリアルタイムモデルがより確実に正しい WebSocket ルートを使うようにしました。
- EN: Fixed the remote model selector so already configured models are recognized correctly in filters and setup prompts, reducing false "not configured" states.
- 简体中文：修复了远程模型选择器的状态判断，已配置完成的模型现在会在筛选和提示中被正确识别，减少误报“未配置”的情况。
- 日本語：リモートモデルセレクタの状態判定を修正し、設定済みモデルがフィルタや案内で正しく認識されるようにして、誤った「未設定」表示を減らしました。

## [1.9.7] - 2026-04-20

### Fixed
- EN: Improved Settings responsiveness by keeping sidebar sections warm, moving dictionary and history reload work off the main thread, and paginating large dictionary lists so switching between sections stays smoother.
- 简体中文：优化了设置页响应速度，通过保留侧边栏分区状态、将字典与历史记录的重载移出主线程，并为大词典列表加入分页，让分区切换更加顺滑。
- 日本語：Settings の応答性を改善し、サイドバー各セクションの状態を保持したまま、辞書と履歴の再読み込みをメインスレッド外へ移し、大きな辞書一覧にはページングを追加したことで、セクション切り替えがより滑らかになりました。
- EN: Fixed Settings sidebar rows so clicking anywhere across the highlighted row switches sections more reliably, and kept the Dictionary `Clear All` button at a stable width.
- 简体中文：修复了设置页侧边栏条目的点击区域，现在点击高亮整行内的任意位置都能更稳定地切换分区，并让词典里的 `清空全部` 按钮保持稳定宽度。
- 日本語：Settings サイドバーの行クリック領域を修正し、ハイライトされた行のどこをクリックしてもより確実にセクションを切り替えられるようにし、辞書内の `Clear All` ボタン幅も安定させました。
- EN: Fixed sided modifier shortcut detection so hotkeys that distinguish left and right Command, Option, Control, or Shift keys trigger more consistently.
- 简体中文：修复了区分左右修饰键的快捷键识别，现在区分左右 Command、Option、Control 或 Shift 的热键触发会更加稳定。
- 日本語：左右の修飾キーを区別するショートカット検出を修正し、左右の Command、Option、Control、Shift を区別するホットキーがより安定して発火するようにしました。

## [1.9.6] - 2026-04-19

### Added
- EN: Added the local Cohere Transcribe model to the MLX speech model library, so you can install another multilingual on-device ASR option directly from Settings.
- 简体中文：在 MLX 语音模型库中新增了本地 Cohere Transcribe 模型，现在你可以直接在设置里安装这一多语言本地 ASR 选项。
- 日本語：MLX 音声モデルライブラリにローカル版 Cohere Transcribe を追加し、Settings から多言語対応のオンデバイス ASR を新たに導入できるようにしました。

### Changed
- EN: Expanded local ASR settings with per-model tuning dialogs, including recognition presets, main-language following, and model-specific context or prompt controls where supported.
- 简体中文：扩展了本地 ASR 设置，支持按模型分别调整识别预设、跟随主语言，以及模型支持时的上下文或提示词控制。
- 日本語：ローカル ASR 設定を拡張し、モデルごとのチューニングダイアログから認識プリセット、主言語追随、対応モデルでの context / prompt 制御を調整できるようにしました。
- EN: Improved the model catalog so local ASR entries show whether they support your current primary language, making it easier to choose the right model before installing.
- 简体中文：改进了模型目录，本地 ASR 条目现在会显示是否支持你当前的主语言，安装前更容易选对模型。
- 日本語：モデルカタログを改善し、ローカル ASR エントリに現在の主言語への対応状況を表示するようにしたため、インストール前に適切なモデルを選びやすくなりました。

### Fixed
- EN: Reduced CPU usage during local model downloads and added an in-progress download badge in Settings so active installs stay visible and can jump back to the model list quickly.
- 简体中文：降低了本地模型下载过程中的 CPU 占用，并在设置中新增下载中的提示徽标，让正在安装的模型始终可见并能快速跳回模型列表。
- 日本語：ローカルモデルのダウンロード中に発生していた CPU 使用率を抑え、Settings に進行中ダウンロードのバッジを追加して、インストール状況の確認とモデル一覧への復帰をしやすくしました。
- EN: Fixed local ASR configuration sheets so Whisper and other tuning controls follow the app language more consistently across labels, presets, and helper text.
- 简体中文：修复了本地 ASR 配置弹窗的多语言显示，现在 Whisper 等调参项的标签、预设和说明文案会更一致地跟随界面语言。
- 日本語：ローカル ASR 設定シートの多言語表示を修正し、Whisper などのチューニング項目でラベル、プリセット、補助テキストがより一貫してアプリ言語に追随するようにしました。

## [1.9.5] - 2026-04-16

### Fixed
- EN: Fixed the Settings permission badge so it no longer warns about unopened permissions when the currently enabled features only require access you have already granted.
- 简体中文：修复了设置页的权限提示徽标，当当前启用的功能只依赖已授权权限时，不会再错误显示还有权限未开启。
- 日本語：設定画面の権限バッジを修正し、現在有効な機能がすでに許可済みの権限だけを必要とする場合は、未許可の警告が表示されないようにしました。
- EN: Fixed local model lists so known file sizes stay visible more reliably, and model metadata or downloads automatically retry through the mirror when the primary Hugging Face endpoint is rate-limited or unavailable.
- 简体中文：修复了本地模型列表的文件大小显示，已知大小会更稳定地展示；当 Hugging Face 主站遇到限流或不可用时，模型元数据与下载会自动改走镜像重试。
- 日本語：ローカルモデル一覧のファイルサイズ表示を修正し、既知のサイズをより安定して表示するようにしました。あわせて、Hugging Face の本家エンドポイントがレート制限または利用不可の場合は、モデル情報取得とダウンロードをミラー経由で自動再試行するようにしました。

## [1.9.4] - 2026-04-13

### Changed
- EN: Moved one-click dictionary ingest model and prompt controls into Dictionary Advanced Settings and added cancel support while a scan is running.
- 简体中文：将一键录入使用的模型和提示词移至词典高级设置，并支持在扫描过程中取消录入。
- 日本語：ワンクリック取り込みのモデルとプロンプト設定を辞書の詳細設定へ移し、走査中のキャンセルにも対応しました。
- EN: Tightened dictionary ingest term selection so common words, mixed-language filler, route details, and obvious transcript fragments are filtered out more aggressively.
- 简体中文：进一步收紧了词典录入的筛词规则，更积极地排除常见词、混合语言口语填充、路线信息和明显的转写片段。
- 日本語：辞書取り込みの語句選別をさらに厳しくし、一般語、混在言語のつなぎ語、経路情報、明らかな書き起こし断片をより強く除外するようにしました。

### Fixed
- EN: Fixed dictionary ingest parsing by requiring validated structured array output from supported language models before terms are written into the dictionary.
- 简体中文：修复了词典录入解析流程，要求受支持的大模型先返回经过校验的结构化数组结果后才写入词典。
- 日本語：辞書取り込みの解析を修正し、対応する言語モデルが検証済みの構造化配列を返した場合にのみ辞書へ書き込むようにしました。
- EN: Reduced idle memory in Settings and fixed transcription finalization work that could hit newer Swift concurrency isolation checks.
- 简体中文：降低了设置页的空闲内存占用，并修复了转写收尾流程在新版 Swift 并发隔离检查下可能出现的问题。
- 日本語：設定画面の待機時メモリ使用量を抑え、新しい Swift の並行性分離チェックで転写確定処理が不安定になる問題を修正しました。

## [1.9.3] - 2026-04-12

### Fixed
- Fixed rewrite follow-up answers so Aliyun-backed continue conversations no longer collapse into empty fallback responses.
- Improved rewrite conversation stability with safer prompt assembly and overlay teardown handling during longer answer sessions.

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

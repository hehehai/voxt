<div align="center"><a name="readme-top"></a>

<img src="../Voxt/logo.svg" width="118" alt="Voxt Logo">

# Voxt

macOS 菜单栏语音输入与翻译工具。按住说话，松开即贴，AI转写，不同 APP、URL 不同规则。

[English](./README.md) · **简体中文** · [反馈问题][github-issues-link] · [提示词](./Prompt.zh-CN.md)

[![][github-release-shield]][github-release-link]
[![][macos-version-shield]][macos-version-link]
[![][license-shield]][license-link]
[![][release-date-shield]][release-date-link]

<img width="1950" height="1510" alt="image" src="https://github.com/user-attachments/assets/9874598c-8df7-4566-8b3c-9dbbcb2e4d57" />

</div>

## ✨ 特性一览 Speak, don't type

**说出来，语音转文字** `fn`

- 边说边转文字，实时查看文本内容
- 结果增强，去除语气词，自动添加标点符号，Prompt 自定义，你的输出你来决定！
- App 分组，不同的 App 或网址 设置不同的增强规则（自定义 Prompt）Coding、Chat、Email 。。。
- 支持个人词典，可把命中的术语注入提示词，并在高置信度场景下把近似词自动纠正为准确写法
- 多语言支持，混合语言输入无压力，想怎么说，就怎么说。

**沟通无障碍，说完就翻译** `fn+shift`

- AI 翻译，说完自动翻译
- 选中翻译，选择文本，快捷键直接翻译
- 自定义翻译，自定义 Prompt 关键词，常用词自己定，你的习惯你来掌控！
- 支持独立模型，那个强用那个，那个快用那个！

**语言转写，帮我一下** `fn+control`

- “帮我写一篇 200 字的自我介绍模板吧” 你的输入就是 Prompt，结果会自动输入编辑器
- 选中文本转写 ～ “帮我把这段文本精简下，语句要通顺” 。。。
- 可选“转写答案卡片”，在当前没有可写输入框时也能稳定查看和接收长结果
- AI 助手，不止止语音输入

[![][back-to-top]](#readme-top)

## 下载/安装

- [安装包](https://github.com/hehehai/voxt/releases/latest)

- 使用 Homebrew:

```bash
brew tap hehehai/tap
brew install --cask voxt
```

## 模型支持

<img width="1015" height="724" alt="image" src="https://github.com/user-attachments/assets/2e5e71c9-5fdb-4f14-b86a-ea3f67e62c98" />


我们分为 ASR 服务商模型 和 LLM 服务商模型，他们分别用于语音转文本，以及 文本增强、翻译、转写功能

> 支持选择系统听写，使用 Apple 听写功能（多语言支持度不高）

### 本地模型

依赖新版 macOS 与本地模型能力，Voxt 当前提供：

- `MLX Audio` 本地 ASR 模型
- 通过 WhisperKit 接入的 `Whisper` 独立本地 ASR 引擎
- 一组可下载的本地 LLM 模型（用于文本增强、翻译、改写）

Whisper 不是 `MLX Audio` 的子模式，而是在模型页里独立显示的一个引擎，有自己的模型列表、下载流程和运行时配置。

> [!NOTE]
> 下表中的“当前状态 / 报错”来自当前项目代码；“语言支持 / 速度 / 推荐度”优先参考模型卡与项目内描述整理。速度与推荐度用于帮助选型，不是统一 benchmark。

另外还支持系统听写 `Direct Dictation`（Apple `SFSpeechRecognizer`）：

- 适合：不想下载本地模型时快速使用
- 限制：多语言支持度一般
- 依赖：麦克风权限 + 语音识别权限
- 常见报错：`Speech Recognition permission is required for Direct Dictation.`

#### 本地 ASR 模型

| 模型 | 仓库 ID | 大小 | 支持语言 | 速度 | 推荐度 | 当前状态 |
| --- | --- | --- | --- | --- | --- | --- |
| Qwen3-ASR 0.6B (4bit) | `mlx-community/Qwen3-ASR-0.6B-4bit` | 0.6B / 4bit | 30 种语言，含中文、英文、粤语等 | 快 | 高 | 默认本地 ASR，质量 / 速度最均衡 |
| Qwen3-ASR 1.7B (bf16) | `mlx-community/Qwen3-ASR-1.7B-bf16` | 1.7B / bf16 | 与 0.6B 同系列，多语言 | 中 | 很高 | 精度优先，内存与磁盘占用更高 |
| Voxtral Realtime Mini 4B (fp16) | `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` | 4B / fp16 | 13 种语言，含中英日韩等 | 中 | 中高 | 偏实时场景，体积最大 |
| Parakeet 0.6B | `mlx-community/parakeet-tdt-0.6b-v3` | 0.6B / bf16 | 模型卡标注 25 种语言；项目内文案按英文轻量 STT 定位 | 很快 | 中高 | 轻量高速，英文场景优先 |
| GLM-ASR Nano (4bit) | `mlx-community/GLM-ASR-Nano-2512-4bit` | MLX 4bit，约 1.28 GB | 当前模型卡明确标注中英 | 快 | 高 | 最轻量，适合快速草稿与低门槛部署 |

#### Whisper（WhisperKit）

Voxt 还支持通过 WhisperKit 使用 `Whisper` 作为独立的本地 ASR 引擎。

- 内置模型列表：`tiny`、`base`、`small`、`medium`、`large-v3`
- 当前下载源：基于 Hugging Face 风格路径的 `argmaxinc/whisperkit-coreml`
- 支持中国镜像：跟随应用里的镜像开关
- 当前可配置项：
  - `Realtime`，默认开启
  - `VAD`
  - `Timestamps`
  - `Temperature`
- 当前行为：
  - 普通转录默认使用 Whisper 的 `transcribe`
  - 翻译快捷键可选用 Whisper 内建的 `translate-to-English`
  - 如果当前场景不支持 Whisper 直翻，Voxt 会自动回退到已选的 LLM 翻译 provider

Voxt 当前内置的 Whisper 模型：

| 模型 | 约下载体积 | 推荐度 | 说明 |
| --- | --- | --- | --- |
| Whisper Tiny | 约 76.6 MB | 中 | 体积最小，适合快速本地草稿 |
| Whisper Base | 约 146.7 MB | 高 | 默认 Whisper 均衡选项 |
| Whisper Small | 约 486.5 MB | 高 | 识别质量更好，资源开销适中 |
| Whisper Medium | 约 1.53 GB | 很高 | 精度优先，本地下载与内存占用更重 |
| Whisper Large-v3 | 约 3.09 GB | 很高 | 体积最大，更适合磁盘和内存充足的 Apple Silicon Mac |

Whisper 相关说明：

- 如果主语言设置为简体中文 / 繁体中文，Whisper 输出会按主语言做简繁归一化。
- Whisper 直翻目前只适用于“语音翻到英文”的场景；选中文本翻译仍然走原有文本翻译链路。
- 如果 Whisper 模型下载中断或文件不完整，Voxt 会把它视为未完成模型，并要求重新下载，而不是继续尝试加载损坏模型。

本地 ASR 常见报错 / 状态：

- `Invalid model identifier`
- `Model repository unavailable (..., HTTP 401/404)`
- `Download failed (...)`
- `Model load failed (...)`
- `Size unavailable`
- 如果误配到对齐专用仓库，会提示 `alignment-only and not supported by Voxt transcription`
- 如果 Whisper 缺少关键 Core ML 权重文件，也可能出现“下载不完整 / 模型损坏”相关错误

#### 本地 LLM 模型

| 模型 | 仓库 ID | 大小 | 语言倾向 | 速度 | 推荐度 | 适合场景 |
| --- | --- | --- | --- | --- | --- | --- |
| Qwen2 1.5B Instruct | `Qwen/Qwen2-1.5B-Instruct` | 1.5B | 中文 / 英文均衡 | 快 | 高 | 轻量文本清洗、简单翻译 |
| Qwen2.5 3B Instruct | `Qwen/Qwen2.5-3B-Instruct` | 3B | 中文 / 英文均衡 | 中快 | 高 | 更稳的增强与格式整理 |
| Qwen3 4B (4bit) | `mlx-community/Qwen3-4B-4bit` | 4B / 4bit | 中文 / 英文 / 多语言 | 中快 | 很高 | 本地增强、翻译的均衡选项 |
| Qwen3 8B (4bit) | `mlx-community/Qwen3-8B-4bit` | 8B / 4bit | 中文 / 英文 / 多语言 | 中慢 | 很高 | 更强的改写、翻译和结构化输出 |
| GLM-4 9B (4bit) | `mlx-community/GLM-4-9B-0414-4bit` | 9B / 4bit | 中文 / 英文 / 多语言 | 慢 | 很高 | 中文改写、复杂提示词场景 |
| Llama 3.2 3B Instruct (4bit) | `mlx-community/Llama-3.2-3B-Instruct-4bit` | 3B / 4bit | 英文优先，多语言可用 | 中快 | 中高 | 轻量本地改写 |
| Llama 3.2 1B Instruct (4bit) | `mlx-community/Llama-3.2-1B-Instruct-4bit` | 1B / 4bit | 英文优先，多语言可用 | 很快 | 中 | 最省资源的本地增强 |
| Meta Llama 3 8B Instruct (4bit) | `mlx-community/Meta-Llama-3-8B-Instruct-4bit` | 8B / 4bit | 英文优先，多语言可用 | 中慢 | 中高 | 通用增强、摘要、改写 |
| Meta Llama 3.1 8B Instruct (4bit) | `mlx-community/Meta-Llama-3.1-8B-Instruct-4bit` | 8B / 4bit | 英文优先，多语言可用 | 中慢 | 高 | 比较稳妥的通用本地 LLM |
| Mistral 7B Instruct v0.3 (4bit) | `mlx-community/Mistral-7B-Instruct-v0.3-4bit` | 7B / 4bit | 英文 / 欧洲语系更强 | 中 | 高 | 简洁改写、格式修正 |
| Mistral Nemo Instruct 2407 (4bit) | `mlx-community/Mistral-Nemo-Instruct-2407-4bit` | Nemo 系列 / 4bit | 英文优先，多语言可用 | 中慢 | 高 | 更复杂的本地增强任务 |
| Gemma 2 2B IT (4bit) | `mlx-community/gemma-2-2b-it-4bit` | 2B / 4bit | 英文优先，多语言可用 | 快 | 中高 | 轻量文本整理 |
| Gemma 2 9B IT (4bit) | `mlx-community/gemma-2-9b-it-4bit` | 9B / 4bit | 英文优先，多语言可用 | 慢 | 高 | 更高质量的本地润色与翻译 |

本地 LLM 常见报错 / 状态：

- `Custom LLM model is not installed locally.`
- `Invalid local model path.`
- `Invalid model identifier`
- `No downloadable files were found for this model.`
- `Downloaded files are incomplete.`
- `Download failed: ...`
- `Size unavailable`

### 远程服务商模型

为了更快或更实时的转录 / 增强，你可以在“模型”里分别配置 `Remote ASR` 和 `Remote LLM`。下面的表格只列 Voxt 当前代码里真正提供的 provider 入口与默认推荐模型。

> [!note]
> 配置教程 Prompt，你可以喂给任何 AI 让他辅助你完成申请和配置

```txt
https://raw.githubusercontent.com/hehehai/voxt/refs/heads/main/docs/README.zh-CN.md
https://raw.githubusercontent.com/hehehai/voxt/refs/heads/main/docs/RemoteModel.zh-CN.md
我要如何开始配置远程 ASR 和 LLM，我使用豆包 ASR 和阿里云百炼 LLM，给我一个配置和申请流程

1.每一个需要点击网址的地方，请给出具体的网址
2.需要注意的地方和需要配置的地方
3.关键流程详细点可以
```

更完整的服务商介绍、申请入口、端点和配置示例见：[RemoteModel.zh-CN.md](./RemoteModel.zh-CN.md)。

#### 远程 ASR 服务商

> ⭐ 推荐 火山 豆包 ASR 效果好，速度快！

| 服务商 | 项目内置模型选项 | 支持语言 | 实时支持 | 速度 | 推荐度 | 当前接入方式 |
| --- | --- | --- | --- | --- | --- | --- |
| OpenAI Whisper / Transcribe | `whisper-1`、`gpt-4o-mini-transcribe`、`gpt-4o-transcribe` | 多语言 | 部分支持，Voxt 当前是文件转写；可开启分片伪实时预览 | 中 | 高 | `v1/audio/transcriptions` |
| Doubao ASR | `volc.seedasr.sauc.duration`、`volc.bigasr.sauc.duration` | 中文优先，适合中英混说 / 实时场景 | 是 | 快 | 高 | WebSocket 流式识别 |
| GLM ASR | `glm-asr-2512`、`glm-asr-1` | 官方定位覆盖多场景、多口音；Voxt 当前按普通转写接入 | 否（当前实现为上传转写） | 中 | 中高 | HTTP transcription endpoint |
| Aliyun Bailian ASR | `qwen3-asr-flash-realtime`、`fun-asr-realtime`、`paraformer-realtime-*` | 取决于模型：Qwen3 ASR 为多语言，Fun/Paraformer 覆盖中英或多语 | 是 | 快 | 高 | WebSocket 实时识别，Qwen / Fun / Paraformer 走不同端点 |

远程 ASR 常见报错 / 状态：

- `Needs Setup`
- OpenAI / GLM / Aliyun 缺少 API Key
- Doubao 缺少 `Access Token` 或 `App ID`
- `Invalid ASR endpoint URL`
- `Invalid WebSocket endpoint URL`
- `Connection failed (HTTP %d). %@`
- `No valid ASR response packet.`
- Doubao 还可能出现 GZIP 初始化 / 解码失败，Aliyun 还可能出现 `task-failed` 或鉴权 403

#### 远程 LLM 服务商

> ⭐ 推荐 阿里云百炼 Qwen Plus，速度非常快！

| 服务商 | 项目内置推荐模型 | 接口形态 | 用途 | 当前状态 |
| --- | --- | --- | --- | --- |
| Anthropic | `claude-sonnet-4-6` | Anthropic 原生 | 文本增强 / 翻译 / 改写 | 已集成 |
| Google | `gemini-2.5-pro` | Gemini 原生 | 文本增强 / 翻译 / 改写 | 已集成 |
| OpenAI | `gpt-5.2` | OpenAI-compatible | 文本增强 / 翻译 / 改写 | 已集成 |
| Ollama | `qwen2.5` | OpenAI-compatible | 本地 / 自建 LLM 网关 | 已集成 |
| DeepSeek | `deepseek-chat` | OpenAI-compatible | 文本增强 / 翻译 / 改写 | 已集成 |
| OpenRouter | `openrouter/auto` | OpenAI-compatible | 自动路由 | 已集成 |
| xAI (Grok) | `grok-4` | OpenAI-compatible | 文本增强 / 翻译 / 改写 | 已集成 |
| Z.ai | `glm-5` | OpenAI-compatible | 文本增强 / 翻译 / 改写 | 已集成 |
| Volcengine | `doubao-seed-2-0-pro-260215` | OpenAI-compatible | 文本增强 / 翻译 / 改写 | 已集成 |
| Kimi | `kimi-k2.5` | OpenAI-compatible | 文本增强 / 翻译 / 改写 | 已集成 |
| LM Studio | `llama3.1` | OpenAI-compatible | 本地 / 自建 LLM 网关 | 已集成 |
| MiniMax | `MiniMax-M2.5` | MiniMax 原生 | 文本增强 / 翻译 / 改写 | 已集成 |
| Aliyun Bailian | `qwen-plus-latest` | OpenAI-compatible | 文本增强 / 翻译 / 改写 | 已集成 |

远程 LLM 常见报错 / 状态：

- `Needs Setup`
- Anthropic / Google / MiniMax 缺少对应 API Key
- `Invalid endpoint URL` / `Invalid Google endpoint URL`
- `Invalid server response.`
- `Server reachable, but authentication failed (HTTP 401/403).`
- `Connection failed (HTTP %d). %@`
- 运行时还可能出现 `Remote LLM request failed (...)` 或 `Remote LLM returned no text content.`

[![][back-to-top]](#readme-top)

## 快捷键

<img width="1006" height="723" alt="image" src="https://github.com/user-attachments/assets/1f9f8451-e6bc-4003-96d2-e170412c5c56" />

我们内置了两套预设快捷键（`fn 组合` / `command 组合`），也支持完全自定义。每组快捷键都可以选择两种触发方式：

- `Tap (Press to Toggle)`：按一次开始，再按一次结束
- `Long Press (Release to End)`：按下开始，松开结束

下面先以默认的 `fn 组合` 为例说明。

### fn 组合

| 快捷键 | 动作 | 典型用途 | 默认交互 |
| --- | --- | --- | --- |
| `fn` | 普通转录 | 语音输入、语音转文字 | 录音结束后自动增强并输出到当前输入位置 |
| `fn+shift` | 转录并翻译 | 边说边翻译、跨语言输入 | 如果当前有选中文本，优先直接翻译选区，不进入录音 |
| `fn+control` | 转录并转写 / 改写 | 口述提示词生成内容，或用语音改写选中文本 | 如果当前有选区，会结合选中文本做改写；没有选区时按口述指令直接生成结果 |

推荐把它理解成三种工作模式：

- `fn`：把你说的话直接变成文字
- `fn+shift`：把你说的话变成目标语言，或者直接翻译当前选中的文字
- `fn+control`：把你说的话当作 Prompt，让模型帮你生成、改写、润色文本

具体交互如下：

- `fn` 普通转录
  - 点按模式：点按 `fn` 开始录音，再点按 `fn` 结束
  - 长按模式：按下 `fn` 开始录音，松开即结束
  - 适合：快速输入、会议记录、聊天回复、邮件草稿
- `fn+shift` 转录+翻译
  - 点按模式：点按 `fn+shift` 开始录音；结束时可以点 `fn`，也可以再次点 `fn+shift`
  - 长按模式：按下 `fn+shift` 开始录音，松开即结束
  - 如果触发时系统里已经有选中文本，Voxt 会优先直接翻译选区，不走麦克风录音流程
  - 适合：中英混输、跨语言聊天、快速翻译当前段落
- `fn+control` 转录+转写 / 改写
  - 点按模式：点按 `fn+control` 开始录音，再点 `fn` 结束
  - 长按模式：按下 `fn+control` 开始录音，松开即结束
  - 你口述的内容会被当成指令，例如“帮我写一段更礼貌的回复”或“把这段改短一点”
  - 如果当前有选中文本，Voxt 会把选区作为原文，让模型按你的口述要求输出最终结果
  - 如果没有选中文本，则更接近“语音驱动的 AI 助手输入”

交互细节：

- 在点按模式下，`fn` 是统一的结束键。也就是说，翻译模式开始后，按 `fn` 也可以结束当前会话。
- 为了避免误触，刚开始录音后的极短时间内，连续点按不会立刻触发停止。
- `fn+shift` 和 `fn+control` 的优先级高于普通 `fn`，所以组合键不会误判成普通转录。
- 所有快捷键都可以在设置里改成别的键位，也可以切到 `command 组合` 预设。

[![][back-to-top]](#readme-top)

## 应用设置

<img width="933" height="733" alt="image" src="https://github.com/user-attachments/assets/10ceea81-f8f2-4b79-85d5-955b0910c331" />

`General` 主要负责“应用级行为”和“日常使用偏好”的配置。和模型页不同，这里不是决定你用哪个 ASR / LLM，而是决定 Voxt 如何录音、如何显示、如何输出结果、如何随系统启动，以及如何管理网络和配置文件。

当前通用设置大致分成这几类：

### 配置管理

- 支持导出当前的通用、模型、词典、语音结束命令、App Branch、快捷键配置到 JSON
- 支持从 JSON 导入配置，快速迁移到另一台 Mac
- 敏感字段在导出时会被占位符替换，导入后需要重新填写

适合：

- 多台设备同步设置
- 备份当前工作流
- 快速复制同一套模型 / 快捷键 / 分组配置

### 音频

- 选择输入麦克风设备
- 开关交互音效
- 可选在录音时自动静音其他 App 的媒体音频
- 切换交互音效预设，并可直接试听

这部分决定的是“你从哪里录音”和“录音开始 / 结束时是否有声音反馈”。如果你有多个麦克风、外接声卡或特定输入设备，这里很重要。

### 转录界面

- 设置悬浮转录窗口的位置

录音时的波形、预览文本和处理中状态会显示在悬浮层里，这里可以控制它出现在屏幕的什么位置，避免挡住当前工作区域。

### 语言

- 切换应用界面语言
- 设置 `用户主语言（User Main Language）`，供提示词变量和 ASR 语言提示使用
- 设置翻译快捷键的默认目标语言

这一组控制的是三层不同能力：

- 界面语言只影响应用 UI，目前支持英文、中文、日文
- `用户主语言` 会喂给 `{{USER_MAIN_LANGUAGE}}` 变量，也会影响部分 ASR 服务商的语言提示逻辑
- 翻译目标语言决定默认 `fn+shift` 最终翻译到哪种语言

### 模型存储

- 查看当前模型存储目录
- 在 Finder 中打开模型目录
- 切换模型下载路径

这一项对本地模型用户尤其重要。需要注意的是：

> [!IMPORTANT]
> 切换存储路径后，旧路径里已下载的模型不会自动迁移，新路径下也不会自动识别旧模型。更换路径后，通常需要重新下载本地模型。

### 输出

- `Also copy result to clipboard`
- `Always show rewrite answer card`
- `Translate selected text with translation shortcut`
- `App Enhancement (Beta)`

这里控制的是结果如何输出，以及是否启用上下文增强能力：

- 开启“同时复制到剪贴板”后，Voxt 自动粘贴结果的同时，也会把结果保留在剪贴板里
- 开启“始终显示转写答案卡片”后，转写结果会固定走答案卡片，不再只在没有可写输入框时才弹出
- 开启“选中文本翻译”后，按翻译快捷键时如果已有选区，会优先直接翻译并替换选中文本
- 开启 `App Enhancement` 后，才会显示和启用基于 App / URL 的上下文增强配置

### 语音结束命令

- 可以开启“说出口令后自动结束录音”
- 内置预设包括 `over`、`end`、`完毕`
- 切到自定义模式后，也可以填写自己的结束命令

开启后，Voxt 会在转录尾部检测这个命令；如果命令后面大约有 1 秒静音，就会自动结束当前会话。

### 日志

- 开关热键调试日志
- 开关 LLM 调试日志

适合排查这些问题：

- 为什么快捷键没有触发
- 为什么组合键被误判
- 远程 / 本地 LLM 请求到底发了什么
- 模型输出为什么和预期不一致

默认建议关闭，只在排查问题时临时打开。

### 应用行为

- `Launch at Login`：开机自动启动
- `Show in Dock`：是否在 Dock 中显示
- `Automatically check for updates`：后台自动检查更新
- `Proxy`：跟随系统、关闭代理、或使用自定义代理

这里更偏“应用运行方式”：

- 如果你希望 Voxt 常驻菜单栏，通常会开启开机启动
- 如果你希望更方便从 Dock 进入设置，可以开启 Dock 显示
- 如果你在受限网络、公司网络或代理环境下使用远程模型，`Proxy` 设置会直接影响远程 ASR / Remote LLM 的连通性

当前自定义代理支持：

- HTTP
- HTTPS
- SOCKS5

并可填写主机、端口、用户名、密码。不过当前代码里用户名和密码会保存，但还没有完整自动注入到所有请求链路中，这一点在复杂代理环境下需要注意。

[![][back-to-top]](#readme-top)

## 词典

Voxt 现在有独立的词典页，用来管理那些你希望它稳定识别、稳定保留、稳定输出的术语。

- 词典词条既可以是全局的，也可以绑定到某个 App Branch 分组
- 命中的词典词会以 glossary guidance 的方式注入增强、翻译、转写 prompt
- 对于高置信度的近似命中，可以在写回前自动纠正成词典里的准确词
- 支持词典导入 / 导出
- `一键录入` 会用已配置的本地或远程 LLM 扫描历史记录，提取候选词，再由你批量添加或忽略

这套能力尤其适合人名、品牌、产品名、内部项目代号、缩写词和用户自己的特殊拼写习惯。

[![][back-to-top]](#readme-top)

## 权限

<img width="946" height="701" alt="image" src="https://github.com/user-attachments/assets/c854ceef-8b52-4a72-bc8f-e50d9feba49e" />

Voxt 的权限是按功能拆分的。你只使用基础语音输入时，只需要开启基础权限；如果你要用更强的上下文感知能力，例如 `App Branch` 的 URL 分组，再额外开启对应权限即可。

> [!IMPORTANT]
> 如果你只是想先用 Voxt 跑起来，最优先开启的是 `麦克风`。如果你使用默认的 `fn` 组合快捷键，并希望结果能自动写回其他 App，建议同时开启 `辅助功能` 和 `输入监控`。

### 基础权限

| 权限 | 是否常用 | 用于什么功能 | 未授权时的影响 |
| --- | --- | --- | --- |
| 麦克风 | 必需 | 录音、语音转文字、本地 ASR、远程 ASR、翻译、转写 / 改写 | 无法开始录音 |
| 语音识别 | 按需 | 仅 `Direct Dictation` / Apple `SFSpeechRecognizer` | 仅系统听写不可用，其它 MLX / Remote ASR 不受影响 |
| 辅助功能（Accessibility） | 强烈建议开启 | 全局快捷键、自动把结果粘贴回其他 App、读取部分界面上下文 | 可以录音，但自动粘贴与部分跨 App 交互会受限 |
| 输入监控（Input Monitoring） | 强烈建议开启 | 更稳定地监听全局修饰键快捷键，尤其是 `fn`、`fn+shift`、`fn+control` | 全局热键可能不稳定、失效或误判 |
| 自动化（Automation） | 可选 | 读取浏览器当前标签页 URL，用于 App Branch 的 URL 匹配 | App Branch 仍可按前台 App 分组，但无法按网页 URL 精准匹配 |

补充说明：

- 麦克风权限是录音链路的硬要求，不管你用本地模型、远程 ASR，还是翻译 / 改写，都离不开它。
- 语音识别权限只服务于 Apple 系统听写；如果你只用 `MLX 本地转录` 或 `Remote ASR`，可以不开。
- 辅助功能权限不只是“看界面”，它也负责把结果自动写回别的 App。没开时，Voxt 仍可工作，但结果更可能停留在剪贴板，需要手动粘贴。
- 输入监控权限主要是为了让 modifier-only 热键更可靠，这也是为什么默认 `fn` 组合建议开启它。
- 如果你开启了“录音时静音其他应用媒体音频”，Voxt 还需要 macOS 的系统音频录制权限；这个权限只对该功能本身有要求。

[![][back-to-top]](#readme-top)

## App Branch 是什么（Beta）

<img width="979" height="712" alt="image" src="https://github.com/user-attachments/assets/1217df7a-7333-4d7f-93ce-67c5b1ae8f9d" />

> [!IMPORTANT]
> `App Branch` 默认不会自动启用。需要先在“通用” -> “输出”里开启 `应用增强（App Enhancement）`，相关分组和 URL 能力才会生效。

`App Branch` 可以理解成“按当前上下文自动切换 Prompt / 规则”。

你可以把不同的 App 或 URL 归到不同分组里，为每个分组单独配置 Prompt。这样在不同场景下，Voxt 会自动切换不同的增强、翻译、转写风格。例如：

- 在 IDE 里，更偏向代码、命令、技术术语
- 在聊天工具里，更偏向简洁、口语化回复
- 在邮件或文档里，更偏向正式表达和完整句子
- 在某个网站里，使用该网站专属术语、格式或语气

App Branch 当前支持两种匹配方式：

- 按前台 App 匹配：例如 Xcode、Cursor、微信、浏览器
- 按浏览器活动标签页 URL 匹配：例如 `github.com/*`、`docs.google.com/*`、`mail.google.com/*`

### App Branch 相关权限

App Branch 本身不一定需要额外权限，取决于你使用到哪一层：

- 只按前台 App 分组：通常不需要浏览器自动化权限
- 按浏览器 URL 分组：需要给对应浏览器授予 `Automation` 权限，允许 Voxt 读取当前活动标签页 URL
- 在少数浏览器或脚本读取失败时，Voxt 还会尝试使用 `Accessibility` 作为兜底方式读取 URL

也就是说：

- 只想做“App 级别”的分组，权限要求比较低
- 想做“网页级别”的精细分组，才需要额外放行浏览器自动化权限

### App Branch URL 授权重点

如果你准备使用 `URL 规则`，这部分权限最关键：

- Voxt 会请求对浏览器的自动化授权，用来读取“当前活动标签页 URL”
- 只有读到当前 URL，Voxt 才能判断是否命中了某个 URL 分组
- 没有这个权限时，Voxt 仍然可以工作，但会退回到普通全局 Prompt，或者只按 App 分组

> [!TIP]
> 只给你真正需要做 URL 分组的浏览器授权就够了，不需要一次性全部开启。最稳妥的做法是在 `Settings > Permissions > App Branch URL Authorization` 里逐个授权、逐个测试。

当前项目中已经内置 / 支持的浏览器 URL 读取方式包括：

- Safari / Safari Technology Preview
- Google Chrome
- Microsoft Edge
- Brave
- Arc
- 以及你在设置里手动添加的自定义浏览器

建议：

- 只给你真正用于 URL 分组的浏览器授权，不需要全部开启
- 在 `Settings > Permissions > App Branch URL Authorization` 中逐个授权、逐个测试最稳妥
- 如果出现 `Browser URL read test failed: permission denied.`，通常就是浏览器自动化权限尚未放行

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

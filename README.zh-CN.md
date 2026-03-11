<p align="center">
  <img src="Voxt/logo.svg" width="108" alt="Voxt Logo">
</p>

<h1 align="center">Voxt</h1>

<p align="center">
  macOS 菜单栏语音输入与翻译工具。按住说话，松开即贴。
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-26.0%2B-black">
  <a href="https://github.com/hehehai/voxt/releases/latest">
    <img alt="Release" src="https://img.shields.io/github/v/release/hehehai/voxt?label=release&color=brightgreen">
  </a>
  <img alt="License" src="https://img.shields.io/badge/License-Apache%202.0-blue">
</p>

<p align="center">
  <a href="README.md">English</a>
</p>

## 下载

- 最新版本：https://github.com/hehehai/voxt/releases/latest
- Homebrew 安装方式（推荐）：

  ```bash
  brew tap hehehai/tap
  brew install --cask voxt
  ```

## 核心功能

- 全局快捷键语音输入，不切换应用即可转写并粘贴。
- 两类快捷键动作：
  - `Transcription`（普通转写）
  - `Translation`（转写后翻译）
- 两种触发方式：
  - `Long Press (Release to End)`
  - `Tap (Press to Toggle)`
- 选中文本直译：
  - 在有选中文本时按翻译快捷键，直接翻译并替换选区。
- 单会话保护：
  - 同时只允许一个录制会话。
- 悬浮转录 UI：
  - 波形、预览文本、处理中状态、最终结果。
- 剪贴板保护自动粘贴：
  - 粘贴后恢复原剪贴板。
- 本地历史记录：
  - 支持复制、删除、清空，区分转写/翻译模式。

## 语音识别引擎（ASR）

### 本地引擎

- `MLX Audio (On-device)`：本地模型。
- `Direct Dictation`：Apple `SFSpeechRecognizer`。

### 远程 ASR（OpenAI 兼容 + 厂商接口）

在 **Model Settings -> Remote ASR Providers** 中可配置：

- OpenAI Whisper / Transcribe 风格接口
- Doubao ASR
- GLM ASR
- 阿里云百炼 ASR（实时 WebSocket）

说明：

- 阿里云百炼 ASR 在 Voxt 中以实时 WS 为主，请保证模型与 endpoint 匹配。
- OpenAI ASR 支持可选开关 **Chunk Pseudo Realtime Preview**：
  - 入口：OpenAI ASR 配置弹窗
  - 默认：`关闭`
  - 作用：通过分段请求实现“伪实时预览”
  - 成本：大约双倍消耗

## 文本增强与翻译

增强模式支持：

- `Off`
- `Apple Intelligence (FoundationModels)`
- `Custom LLM`（本地）
- `Remote LLM`

远程 LLM 在 **Model Settings -> Remote LLM Providers** 里配置。
翻译可选择走本地 Custom LLM 或远程 LLM。

## 更新行为

Voxt 使用 Sparkle 进行更新检查。

- 检测到新版本：
  - 设置窗口左侧底部显示更新 badge。
- 检查更新失败：
  - 默认不弹阻断式失败弹窗。
  - 在设置左侧显示失败 badge。
  - 点击 badge 可查看详情并重试。

这样可以保证失败可见，同时不影响日常使用。

## 网络与代理

- 网络请求可按直连策略运行。
- 日志会记录系统代理探测结果，便于排查。
- 若遇到 403 / 握手失败，请优先核对：
  - endpoint 是否正确
  - Key 与地域是否匹配
  - 本机代理/VPN/网络路径是否干扰

## 权限

Voxt 可能需要以下权限：

- 麦克风
- 辅助功能
- 输入监控
- 语音识别（Dictation 模式）
- 自动化（浏览器标签匹配，可选）

## 构建

```bash
xcodebuild -project Voxt.xcodeproj -scheme Voxt -destination 'platform=macOS' build
```

## 架构说明

- `AppDelegate+*`：按会话阶段拆分（录制、转写、翻译、收尾）。
- `Support/`：更新、网络、模型配置、历史、增强等服务层。
- `Transcription/`：本地与远程转录实现。
- `Settings/`：模块化设置页与 provider 配置 UI。

## 协议

Apache 2.0，见 [LICENSE](LICENSE)。

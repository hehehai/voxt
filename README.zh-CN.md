<p align="center">
  <img src="Voxt/logo.svg" width="108" alt="Voxt Logo">
</p>

<h1 align="center">Voxt</h1>

<p align="center">
  菜单栏语音输入与翻译工具：按住说话，松开即贴；也可走翻译链路后再贴。
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
  <a href="README.md">English</a>
</p>

## Video

https://github.com/user-attachments/assets/23d42c24-7128-4bdb-bc1d-98509e69d97e

[Release](https://github.com/hehehai/voxt/releases/latest)

## Features

- 全局快捷键语音输入，不切应用直接转写并粘贴。
- 双快捷键动作：
  - `Transcription`（普通转写）
  - `Translation`（转写后翻译）
- 双触发模式：`Long Press (Release to End)` / `Tap (Press to Toggle)`。
- 双语音引擎：
  - `MLX Audio (On-device)`：本地模型转写
  - `Direct Dictation`：Apple Speech 实时听写
- 双 LLM 路径：
  - `Apple Intelligence (Foundation Models)`
  - `Custom LLM`（本地模型）
- 支持翻译目标语言选择：English / Chinese (Simplified) / Japanese / Korean / Spanish / French / German。
- 实时悬浮条：音量波形、滚动文本、处理中动画、完成状态反馈。
- 智能输出策略：可选“无可编辑输入框时仅复制到剪贴板”。
- 剪贴板保护：自动粘贴后恢复原剪贴板内容。
- 本地历史记录：分页、复制、删除、清空，区分 `Normal / Translation`。
- 模型下载管理：进度、取消、删除、体积展示、校验、`hf-mirror.com` 镜像切换。
- 系统级能力：麦克风选择、交互提示音、开机启动、Dock 显示开关。

## 实现方式

1. `CGEvent tap` 监听全局快捷键（转写与翻译分离）。
2. `AVAudioEngine` 采集音频并实时更新音量。
3. 根据配置选择 STT 引擎：
   - MLX：分阶段纠正（中间修正 + 停止后最终修正）
   - Dictation：`SFSpeechRecognizer` 流式结果
4. 根据模式执行文本处理：
   - 普通模式：可选增强（Off / Apple Intelligence / Custom LLM）
   - 翻译模式：可选先增强，再按目标语言翻译
5. 通过粘贴板 + `Cmd+V` 注入文本，并记录历史与耗时。

## 引擎介绍

### 语音识别（STT）引擎

| 引擎 | 说明 | 优势 | 适用场景 |
| --- | --- | --- | --- |
| MLX Audio | 本地加载 MLX STT 模型进行识别 | 离线、本地可控、模型可选 | 追求隐私和可调模型 |
| Direct Dictation | Apple Speech (`SFSpeechRecognizer`) | 零配置、开箱即用 | 不想下载模型、快速上手 |

### 增强 / 翻译引擎

| 引擎 | 技术路径 | 优势 | 注意点 |
| --- | --- | --- | --- |
| Apple Intelligence | `FoundationModels` | 系统级体验、无需额外下载 LLM | 依赖系统可用性 |
| Custom LLM | 本地 `MLXLMCommon` + Hugging Face 模型 | 完全本地、可自定义提示词 | 需要先下载模型 |

## 模型介绍

### MLX STT 模型

- `mlx-community/Qwen3-ASR-0.6B-4bit`（默认）：均衡速度与质量，内存占用较低。
- `mlx-community/Qwen3-ASR-1.7B-bf16`：准确率优先，资源占用更高。
- `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16`：实时导向，模型体积较大。
- `mlx-community/parakeet-tdt-0.6b-v3`：轻量快速，英文场景友好。
- `mlx-community/GLM-ASR-Nano-2512-4bit`：最小占用，适合快速草稿。

### Custom LLM 模型

- `Qwen/Qwen2-1.5B-Instruct`（默认）：通用增强/翻译，资源压力更低。
- `Qwen/Qwen2.5-3B-Instruct`：更强格式与推理能力，速度和占用更高。

## 模型效果对比（相对）

> 说明：下表是基于项目内置模型定位与常见体感给出的相对建议，不是统一硬件上的基准跑分。

### STT 模型效果对比

| 模型 | 速度 | 准确性 | 资源占用 | 推荐场景 |
| --- | --- | --- | --- | --- |
| Qwen3-ASR 0.6B (4bit) | 中-高 | 中-高 | 低 | 日常主力 |
| Qwen3-ASR 1.7B (bf16) | 中 | 高 | 高 | 质量优先 |
| Voxtral Realtime Mini 4B (fp16) | 高 | 中-高 | 高 | 实时反馈优先 |
| Parakeet 0.6B | 高 | 中 | 低 | 英文快速输入 |
| GLM-ASR Nano (4bit) | 高 | 中-低 | 很低 | 低资源设备/草稿 |

### LLM 模型效果对比

| 模型 | 生成质量 | 速度 | 资源占用 | 推荐场景 |
| --- | --- | --- | --- | --- |
| Qwen2 1.5B Instruct | 中-高 | 高 | 低-中 | 常规润色与翻译 |
| Qwen2.5 3B Instruct | 高 | 中 | 中-高 | 质量和格式一致性优先 |

## 安装与构建

### 系统要求

- macOS `26.0+`
- 麦克风权限
- 辅助功能权限（全局热键与自动粘贴）
- `Direct Dictation` 模式需要语音识别权限

### 安装（给朋友分发）

- 可直接下载 Release：
  - 最新版本页面：https://github.com/hehehai/voxt/releases/latest
  - 直接下载（`v1.0.0`）：https://github.com/hehehai/voxt/releases/download/v1.0.0/Voxt-v1.0.0-macOS.zip
- 安装步骤：
  1. 下载并解压 `Voxt-v1.0.0-macOS.zip`。
  2. 将 `Voxt.app` 拖到 `Applications`。
  3. 首次启动按提示授予所需权限。
  4. 若被 Gatekeeper 拦截，右键 `Voxt.app` -> `打开`。

### 本地构建

1. 使用 Xcode 打开 `Voxt.xcodeproj` 并运行。
2. 或终端构建：

```bash
xcodebuild -project Voxt.xcodeproj -scheme Voxt -destination 'platform=macOS' build
```

## Thanks

- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)
- [Kaze](https://github.com/fayazara/Kaze)
- Apple `Speech` / `FoundationModels` / AppKit / SwiftUI

## 协议

MIT，见 [LICENSE](LICENSE)。

# ASR 模型系列与模型名称清单

> 用途：整理当前 Voxt ASR 相关的模型系列名称、模型显示名称和内部 ID，方便后续统一改名、分组或精简。
>
> 来源：
> - 本地 MLX ASR：`Voxt/Transcription/MLXModelSupport.swift`
> - 本地 sherpa-onnx ASR：`Voxt/Transcription/SherpaOnnxModelSupport.swift`
> - 本地 Whisper：`Voxt/Transcription/MLXModelSupport.swift` 中的 MLX Whisper family，旧 Whisper ID 仅保留迁移解析
> - 远程 ASR：`Voxt/Core/Models/RemoteModelConfiguration.swift`

## 本地 ASR 系列总览

| 系列名称 | 引擎/来源 | 当前状态 | 说明 |
| --- | --- | --- | --- |
| System ASR | Apple 系统听写 | 可见 | 无需下载，系统内置 |
| Whisper | MLX Audio | 部分可见 | OpenAI Whisper 的 MLX 本地模型；旧 Whisper ID 会迁移到对应 MLX repo |
| Qwen3 | MLX Audio | 部分可见 | 阿里 Qwen3-ASR 本地模型 |
| Voxtral | MLX Audio | 隐藏支持 | Mistral Voxtral Realtime 系列，仅保留已有安装和旧配置兼容 |
| Cohere | MLX Audio | 隐藏支持 | Cohere Transcribe MLX 移植 |
| Canary | MLX Audio | 隐藏支持 | NVIDIA Canary 系列，仅保留已有安装和旧配置兼容 |
| Parakeet | MLX Audio | 部分可见 | NVIDIA Parakeet 系列 |
| GLM | MLX Audio | 隐藏支持 | 智谱 GLM-ASR Nano |
| Granite | MLX Audio | 隐藏支持 | IBM Granite Speech |
| Nemotron | MLX Audio | 可见 | NVIDIA Nemotron ASR Streaming |
| MOSS | MLX Audio | 可见 | OpenMOSS Transcribe Diarize（窗口式实时 + 说话人/时间戳） |
| FireRed | sherpa-onnx | 隐藏支持 | FireRed ASR 2 CTC int8；保留已有安装、旧配置和旧 MLX ID 迁移兼容 |
| FunASR Nano | sherpa-onnx | 隐藏支持 | FunASR Nano int8；保留已有安装和旧配置兼容 |
| SenseVoice | MLX Audio | 可见 | SenseVoice Small |

## 本地系统 ASR

| 系列名称 | 模型显示名称 | 内部 ID | 可见性 | 备注 |
| --- | --- | --- | --- | --- |
| System ASR | Direct Dictation / 系统听写 | `dictation` | 可见 | Apple 系统听写，无模型下载 |

## 本地 Whisper 模型

| 系列名称 | 模型显示名称 | 内部 ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| Whisper | Whisper Large v3 Turbo | `mlx-community/whisper-large-v3-turbo` | 可见 | Fast Whisper large-v3 family model with the best quality-to-latency balance. |
| Whisper | Whisper Large v3 | `mlx-community/whisper-large-v3-mlx` | 可见 | Accuracy-first Whisper model with a heavier local footprint. |
| Whisper | Whisper Small | `mlx-community/whisper-small-mlx` | 可见 | Lower-resource Whisper model for lighter local setups. |
| Whisper | Whisper Tiny | `mlx-community/whisper-tiny-mlx` | 隐藏支持 | Legacy lightweight Whisper option kept for existing installations. |
| Whisper | Whisper Base | `mlx-community/whisper-base-mlx` | 隐藏支持 | Legacy compact Whisper option kept for existing installations. |

## 本地 MLX ASR 模型

### Qwen3

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| Qwen3 | Qwen3 0.6B (4bit) | `mlx-community/Qwen3-ASR-0.6B-4bit` | 可见 | Balanced quality and speed with low memory use. |
| Qwen3 | Qwen3 0.6B (6bit) | `mlx-community/Qwen3-ASR-0.6B-6bit` | 隐藏支持 | Better accuracy than 4bit with moderate memory usage. |
| Qwen3 | Qwen3 0.6B (8bit) | `mlx-community/Qwen3-ASR-0.6B-8bit` | 隐藏支持 | Highest-precision 0.6B option with higher memory usage. |
| Qwen3 | Qwen3 0.6B (bf16) | `mlx-community/Qwen3-ASR-0.6B-bf16` | 隐藏支持 | Full-precision 0.6B model for maximum local quality. |
| Qwen3 | Qwen3 1.7B (4bit) | `mlx-community/Qwen3-ASR-1.7B-4bit` | 隐藏支持 | Larger multilingual model tuned for accuracy at lower memory cost. |
| Qwen3 | Qwen3 1.7B (6bit) | `mlx-community/Qwen3-ASR-1.7B-6bit` | 可见 | High-accuracy flagship model with a balanced memory footprint. |
| Qwen3 | Qwen3 1.7B (8bit) | `mlx-community/Qwen3-ASR-1.7B-8bit` | 可见 | High-precision 1.7B model for stronger recognition quality. |
| Qwen3 | Qwen3 1.7B (bf16) | `mlx-community/Qwen3-ASR-1.7B-bf16` | 隐藏支持 | High accuracy flagship model with higher memory usage. |

### Voxtral

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| Voxtral | Voxtral 4B (4bit) | `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit` | 隐藏支持 | Realtime-oriented multilingual model with reduced memory use. |
| Voxtral | Voxtral 4B (6bit) | `mlx-community/Voxtral-Mini-4B-Realtime-6bit` | 隐藏支持 | Realtime multilingual model with a balanced quality-to-memory tradeoff. |
| Voxtral | Voxtral 4B (fp16) | `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` | 隐藏支持 | Realtime-oriented model with larger memory footprint. |

### Cohere

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| Cohere | Cohere 03-2026 (fp16) | `beshkenadze/cohere-transcribe-03-2026-mlx-fp16` | 隐藏支持 | High-accuracy multilingual encoder-decoder model with punctuation enabled. |

### Canary

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| Canary | Canary | `Mediform/canary-1b-v2-mlx-q8` | 隐藏支持 | Canary-compatible NeMo encoder-decoder checkpoint for multilingual transcription. |

### Parakeet

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| Parakeet | Parakeet TDT CTC 110M | `mlx-community/parakeet-tdt_ctc-110m` | 隐藏支持 | Smallest Parakeet option for fast English transcription. |
| Parakeet | Parakeet TDT 0.6B v2 | `mlx-community/parakeet-tdt-0.6b-v2` | 隐藏支持 | Lightweight English TDT model for lower-memory local transcription. |
| Parakeet | Parakeet v3 | `mlx-community/parakeet-tdt-0.6b-v3` | 可见 | Fast, lightweight English STT. |
| Parakeet | Parakeet CTC 0.6B | `mlx-community/parakeet-ctc-0.6b` | 隐藏支持 | Compact English CTC model with low memory use. |
| Parakeet | Parakeet RNNT 0.6B | `mlx-community/parakeet-rnnt-0.6b` | 隐藏支持 | Compact English RNNT model for streaming-friendly decoding. |
| Parakeet | Parakeet TDT 1.1B | `mlx-community/parakeet-tdt-1.1b` | 隐藏支持 | Larger English model with improved recognition quality. |
| Parakeet | Parakeet TDT CTC 1.1B | `mlx-community/parakeet-tdt_ctc-1.1b` | 隐藏支持 | Higher-capacity Parakeet hybrid model for English transcription. |
| Parakeet | Parakeet CTC 1.1B | `mlx-community/parakeet-ctc-1.1b` | 隐藏支持 | Higher-accuracy English CTC model with increased memory usage. |
| Parakeet | Parakeet RNNT 1.1B | `mlx-community/parakeet-rnnt-1.1b` | 隐藏支持 | Higher-accuracy English RNNT model for heavier local setups. |

### GLM

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| GLM | GLM Nano (4bit) | `mlx-community/GLM-ASR-Nano-2512-4bit` | 隐藏支持 | Smallest footprint for quick drafts. |

### Granite

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| Granite | Granite 4.0 1B (5bit) | `mlx-community/granite-4.0-1b-speech-5bit` | 隐藏支持 | Speech model for English, French, German, Spanish, Portuguese, and Japanese. |

### Nemotron

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| Nemotron | Nemotron 0.6B (8bit) | `mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit` | 可见 | Streaming ASR model with cache-aware NeMo-family decoding. |

### MOSS

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| MOSS | MOSS | `OpenMOSS-Team/MOSS-Transcribe-Diarize` | 可见 | One-pass timestamped transcription and speaker-label model for meeting-style audio. |

### FireRed

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| FireRed | FireRed 2 | `mlx-community/FireRedASR2-AED-mlx` | 隐藏支持 | Legacy MLX FireRed option kept for migration to sherpa-onnx FireRed. |

### SenseVoice

| 系列名称 | 模型显示名称 | Repo ID | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- |
| SenseVoice | SenseVoice | `mlx-community/SenseVoiceSmall` | 可见 | Fast multilingual model with built-in language and event detection. |

## 本地 sherpa-onnx ASR 模型

| 系列名称 | 模型显示名称 | 内部 ID | 来源包 | 可见性 | 当前描述 |
| --- | --- | --- | --- | --- | --- |
| FireRed | FireRed ASR 2 (CTC int8) | `fire-red-asr-v2-onnx` | `sherpa-onnx-fire-red-asr2-ctc-zh_en-int8-2026-02-25` | 隐藏支持 | 中文/英文 CTC int8 离线模型；保留已有安装、旧配置和旧 MLX ID 迁移兼容。 |
| FunASR Nano | FunASR Nano (int8) | `funasr-nano-int8` | `sherpa-onnx-funasr-nano-int8-2025-12-30` | 隐藏支持 | 保留已有安装和旧配置兼容；使用 `encoder_adaptor`、`llm`、`embedding` 和 `Qwen3-0.6B` tokenizer 目录。 |

## 远程 ASR Provider 与模型选项

> 远程 ASR 的模型来自 provider 配置，不属于本地可安装模型。部分 provider 支持自定义模型，因此这里列的是内置下拉选项和默认 suggested model。

### OpenAI Transcribe

默认模型：`gpt-4o-mini-transcribe`

| Provider/系列名称 | 模型显示名称 | 模型 ID |
| --- | --- | --- |
| OpenAI Transcribe | GPT-4o Mini Transcribe | `gpt-4o-mini-transcribe` |
| OpenAI Transcribe | GPT-4o Transcribe | `gpt-4o-transcribe` |
| OpenAI Transcribe | GPT-4o Transcribe Diarize | `gpt-4o-transcribe-diarize` |
| OpenAI Transcribe | Whisper-1 | `whisper-1` |

### Doubao ASR

默认模型：`volc.seedasr.sauc.duration`

| Provider/系列名称 | 模型显示名称 | 模型 ID |
| --- | --- | --- |
| Doubao ASR | Doubao ASR 2.0 (Hourly) | `volc.seedasr.sauc.duration` |
| Doubao ASR | Doubao ASR 1.0 (Hourly) | `volc.bigasr.sauc.duration` |

### Z ai / 智普

默认模型：`glm-asr-1`

| Provider/系列名称 | 模型显示名称 | 模型 ID |
| --- | --- | --- |
| Z ai / 智普 | GLM-ASR-2512 | `glm-asr-2512` |
| Z ai / 智普 | GLM-ASR-1 | `glm-asr-1` |

### Aliyun Bailian ASR

默认模型：`fun-asr-realtime`

| Provider/系列名称 | 模型显示名称 | 模型 ID |
| --- | --- | --- |
| Aliyun Bailian ASR / Qwen3 ASR Flash Realtime | Qwen3 ASR Flash Realtime | `qwen3-asr-flash-realtime` |
| Aliyun Bailian ASR / Qwen3 ASR Flash Realtime | Qwen3 ASR Flash Realtime (2026-02-10) | `qwen3-asr-flash-realtime-2026-02-10` |
| Aliyun Bailian ASR / Qwen3 ASR Flash Realtime | Qwen3 ASR Flash Realtime (2025-10-27) | `qwen3-asr-flash-realtime-2025-10-27` |
| Aliyun Bailian ASR / Qwen3.5 Omni Realtime | Qwen3.5 Omni Flash Realtime | `qwen3.5-omni-flash-realtime` |
| Aliyun Bailian ASR / Qwen3.5 Omni Realtime | Qwen3.5 Omni Plus Realtime | `qwen3.5-omni-plus-realtime` |
| Aliyun Bailian ASR / Qwen Omni Realtime | Qwen Omni Turbo Realtime | `qwen-omni-turbo-realtime` |
| Aliyun Bailian ASR / Fun ASR Realtime | Fun ASR Realtime | `fun-asr-realtime` |
| Aliyun Bailian ASR / Fun ASR Realtime | Fun ASR Realtime (2026-02-28) | `fun-asr-realtime-2026-02-28` |
| Aliyun Bailian ASR / Fun ASR Realtime | Fun ASR Realtime (2025-11-07) | `fun-asr-realtime-2025-11-07` |
| Aliyun Bailian ASR / Fun ASR Realtime | Fun ASR Realtime (2025-09-15) | `fun-asr-realtime-2025-09-15` |
| Aliyun Bailian ASR / Fun ASR Flash 8k Realtime | Fun ASR Flash 8k Realtime | `fun-asr-flash-8k-realtime` |
| Aliyun Bailian ASR / Fun ASR Flash 8k Realtime | Fun ASR Flash 8k Realtime (2026-01-28) | `fun-asr-flash-8k-realtime-2026-01-28` |
| Aliyun Bailian ASR / Paraformer Realtime | Paraformer Realtime V2 | `paraformer-realtime-v2` |
| Aliyun Bailian ASR / Paraformer Realtime | Paraformer Realtime V1 | `paraformer-realtime-v1` |
| Aliyun Bailian ASR / Paraformer Realtime 8k | Paraformer Realtime 8k V2 | `paraformer-realtime-8k-v2` |
| Aliyun Bailian ASR / Paraformer Realtime 8k | Paraformer Realtime 8k V1 | `paraformer-realtime-8k-v1` |

### StepFun ASR

默认模型：`stepaudio-2.5-asr`

| Provider/系列名称 | 模型显示名称 | 模型 ID |
| --- | --- | --- |
| StepFun ASR | StepAudio 2.5 ASR (SSE) | `stepaudio-2.5-asr` |
| StepFun ASR | StepAudio 2 ASR Pro (SSE) | `stepaudio-2-asr-pro` |
| StepFun ASR | Step ASR 1.1 Stream (WebSocket) | `step-asr-1.1-stream` |

## 兼容旧 ID 映射

| 旧 ID | 当前 ID |
| --- | --- |
| `mlx-community/Parakeet-0.6B` | `mlx-community/parakeet-tdt-0.6b-v3` |
| `mlx-community/GLM-ASR-Nano-4bit` | `mlx-community/GLM-ASR-Nano-2512-4bit` |
| `mlx-community/Voxtral-Mini-4B-Realtime-2602` | `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` |
| `mlx-community/Voxtral-Mini-4B-Realtime-2602-6bit` | `mlx-community/Voxtral-Mini-4B-Realtime-6bit` |
| `mlx-community/FireRedASR2` | `fire-red-asr-v2-onnx` |
| `mlx-community/FireRedASR2-AED-mlx` | `fire-red-asr-v2-onnx` |

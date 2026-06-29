# 本地 LLM 模型筛选与 MLXLLM 支持评估

日期：2026-06-29

本评估只覆盖 Voxt 的本地 LLM / VLM 模型目录，不覆盖本地 ASR。相关代码入口：

- `Voxt/Core/Models/CustomLLMModelSupport.swift`
- `Voxt/Core/Models/CustomLLMModelManager.swift`
- `Voxt/Core/LLM/LLMGenerationSettings.swift`
- `Voxt/Settings/Features/FeatureModelCatalogBuilder.swift`

结论先行：

1. 当前本地 LLM 默认可见模型过多：32 个可见、3 个隐藏兼容。建议默认可见收敛到 6 个核心文本模型，另设 3 个实验 / 视觉入口。
2. 当前默认模型仍是 `Qwen/Qwen2-1.5B-Instruct`，它不是最优默认。建议迁移到 Qwen3.5 4B OptiQ。
3. 当前代码里的 `mlx-community/Qwen3.5-0.8B-4bit-OptiQ` 公开 HF API 返回不可访问；可访问 ID 是 `mlx-community/Qwen3.5-0.8B-OptiQ-4bit`。这是 P0 修正项，不应通过 fallback 规避。
4. Voxt 当前已经依赖 `mlx-swift-lm` 3.31.3；该版本已支持 Qwen3.5、Gemma 4、MiniCPM、GLM4、MiMo、SmolLM3、LFM2、EXAONE4、GPT OSS、Jamba 3B、Mistral3 等架构。多数新增架构不需要先升级 MLXLLM，但仍需要按 repo 可下载性、chat template、tokenizer、输出质量逐项验收。

## 当前状态

### 依赖状态

Voxt 当前 Xcode package pin：

| 依赖 | 当前版本 | 结论 |
|---|---:|---|
| `mlx-swift-lm` | `3.31.3` exactVersion | 已是上游最新 release |
| `MLXLLM` | 来自 `mlx-swift-lm` | 本地文本 LLM 加载路径 |
| `MLXVLM` | 来自 `mlx-swift-lm` | 本地图像输入 / VLM 加载路径 |
| `MLXLMCommon` | 来自 `mlx-swift-lm` | `loadModelContainer`、`UserInput`、生成参数等通用 API |

当前本地 LLM 能力：

- 下载源：Hugging Face / HF Mirror。
- 运行方式：从本地缓存目录调用 `loadModelContainer(from:using:)`。
- tokenizer：项目内 `LocalTokenizerLoader` 使用 `Tokenizers.AutoTokenizer.from(modelFolder:)`。
- 图像输入：目录判断命中 `supportsImageInput(repo:)` 时触发 `MLXVLM.TrampolineModelFactory.modelFactory()`，并把附件转成 `UserInput.Image`。
- 生成参数：本地 MLX 支持 temperature、topP、topK、minP、repetition penalty、thinking toggle；不支持 remote-style JSON schema / logprobs / extra body。

### 当前可见模型问题

当前目录覆盖 Qwen2/Qwen2.5、Qwen3、Qwen3.5、GLM、Llama、Mistral、Gemma、Phi、InternLM、MiniCPM、Granite、MiMo、AceReason 等系列。问题不是“模型不够”，而是默认 UI 解释成本过高：

- 同一阶段重复：Qwen2/Qwen2.5/Qwen3/Qwen3.5 同时可见，用户难以理解差异。
- 旧默认劣化：`Qwen/Qwen2-1.5B-Instruct` 体积约 3.10 GB，但质量和体积比低于 Qwen3.5 小模型。
- 视觉模型提前可见：Qwen VL / Gemma 4 VLM 有价值，但 Voxt 当前主要 LLM 工作流仍是文本清理、翻译、改写、会议总结。
- 推理向模型混入主列表：GLM-Z1、AceReason 等可能适合实验，但不适合作为默认文本处理入口。
- 大体积模型默认展示：9B 以上和部分 7B/8B 模型应该留给高质量档或实验档，而不是和入门模型平铺。

## 筛选原则

1. 先解决核心问题：默认模型目录要帮助用户做选择，而不是展示所有可加载模型。
2. 系列收敛：同一主系列只保留轻量、平衡、高质量三个阶段的优势型号。
3. 以 Voxt 任务为准：文本清理、翻译、改写、会议总结优先；纯推理、超长上下文、视觉能力按产品入口决定是否可见。
4. 兼容优先隐藏：已经支持过的旧 repo 先转隐藏兼容，保证已选 / 已下载用户还能运行、卸载、迁移。
5. 不用 fallback 掩盖 repo 错误：公开不可访问、命名错误、缺少 chat template 的模型必须修正或移出可见列表。
6. 默认可见列表保持小而清晰：建议 6 个核心文本模型 + 最多 3 个实验 / 视觉入口。

## 建议默认可见模型

### 核心文本模型

| 阶段 | 推荐模型 | repo | 角色 | 结论 |
|---|---|---|---|---|
| 超轻量 | Qwen3.5 0.8B OptiQ 4bit | `mlx-community/Qwen3.5-0.8B-OptiQ-4bit` | 低内存、低存储、快速试用 | 修正 ID 后保留 |
| 轻量质量档 | Qwen3.5 2B 4bit | `mlx-community/Qwen3.5-2B-4bit` | 低配 Mac 的最低稳定质量入口 | 保留 |
| 默认平衡档 | Qwen3.5 4B OptiQ 4bit | `mlx-community/Qwen3.5-4B-OptiQ-4bit` | 默认本地 LLM | 保留并设为默认 |
| 高质量档 | Qwen3.5 9B OptiQ 4bit | `mlx-community/Qwen3.5-9B-OptiQ-4bit` | 高内存 Mac 的质量优先入口 | 保留 |
| 非 Qwen 备用 | Gemma 4 E4B IT 4bit | `mlx-community/gemma-4-e4b-it-4bit` | 英文、通用质量、VLM 生态备用 | 保留 |
| 中文 / 多语言备用 | GLM-4 9B 0414 4bit | `mlx-community/GLM-4-9B-0414-4bit` | 中文和双语任务备用 | 保留 |

建议默认模型：`mlx-community/Qwen3.5-4B-OptiQ-4bit`。

原因：

- 体积约 2.97 GB，比当前默认 `Qwen/Qwen2-1.5B-Instruct` 的 3.10 GB 略低。
- `model_type=qwen3_5` 已被 MLXLLM 3.31.3 支持。
- 4B 对 Voxt 的文本清理、翻译、改写，比 0.8B / 2B 更稳；又不会像 9B 一样把低配用户直接挡住。

### 实验 / 视觉入口

这 3 个不建议和核心文本模型混在一起平铺，建议单独标记为“实验”或“视觉”：

| 类型 | 推荐模型 | repo | 结论 |
|---|---|---|---|
| 视觉 / App 上下文 | Qwen3 VL 4B Instruct | `lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit` | 保留为视觉入口，但默认不替代文本模型 |
| 轻量视觉 | Gemma 4 E2B IT 4bit | `mlx-community/gemma-4-e2b-it-4bit` | 可进入实验 / 视觉分组 |
| 双语备用实验 | MiniCPM4 8B 4bit | `mlx-community/MiniCPM4-8B-4bit` | 先实验，需实测中文改写、翻译、摘要 |

## 建议隐藏兼容

隐藏兼容的含义：不在默认新增选择里展示，但如果用户已经选中或已下载，仍能显示、运行、卸载，并给出迁移建议。

| 系列 | 模型 | repo | 动作 |
|---|---|---|---|
| Qwen2 | Qwen2 1.5B Instruct | `Qwen/Qwen2-1.5B-Instruct` | 隐藏兼容；默认迁移到 Qwen3.5 4B OptiQ |
| Qwen2.5 | Qwen2.5 3B Instruct | `Qwen/Qwen2.5-3B-Instruct` | 隐藏兼容 |
| Qwen2.5 VL | Qwen2.5 VL 3B | `mlx-community/Qwen2.5-VL-3B-Instruct-4bit` | 隐藏兼容或视觉分组 |
| Qwen3 | 0.6B / 1.7B / 4B / 8B | `mlx-community/Qwen3-*` | 隐藏兼容，被 Qwen3.5 覆盖 |
| Qwen3 VL | Qwen3 VL 4B | `lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit` | 从核心列表移到视觉 / 实验 |
| GLM | GLM-4 Chat 1M | `mlx-community/glm-4-9b-chat-1m-4bit` | 隐藏兼容；超长上下文不是当前核心入口 |
| GLM | GLM-Z1 9B | `mlx-community/GLM-Z1-9B-0414-4bit` | 隐藏兼容；推理向 |
| Llama | Llama 3 / 3.1 / 3.2 | `mlx-community/*Llama*` | 隐藏兼容 |
| Mistral | Mistral 7B / Nemo | `mlx-community/Mistral-*` | 隐藏兼容 |
| Gemma | Gemma 2 2B / 9B | `mlx-community/gemma-2-*` | 隐藏兼容，被 Gemma 4 覆盖 |
| Phi | Phi 3.5 Mini | `mlx-community/Phi-3.5-mini-instruct-4bit` | 隐藏兼容或移除新增入口 |
| InternLM | InternLM2.5 7B | `mlx-community/internlm2_5-7b-chat-4bit` | 隐藏兼容 |
| Granite | Granite 3.3 2B | `mlx-community/granite-3.3-2b-instruct-4bit` | 隐藏兼容 |
| MiMo | MiMo 7B SFT | `mlx-community/MiMo-7B-SFT-4bit` | 实验池；默认隐藏 |
| AceReason | AceReason Nemotron 7B | `mlx-community/AceReason-Nemotron-7B-4bit` | 实验池；默认隐藏 |
| 大体积兼容 | Qwen3 30B A3B / GLM-4.7 Flash | 现有 hiddenCompat | 继续隐藏兼容 |

## MLXLLM 新支持评估

### 已在 Voxt 当前依赖中可用的架构

上游 `mlx-swift-lm` 3.31.3 的 `LLMTypeRegistry` 已注册这些和 Voxt 相关的文本架构：

| 架构 | MLXLLM `model_type` | Voxt 处理建议 |
|---|---|---|
| Qwen3.5 dense / MoE / text | `qwen3_5`、`qwen3_5_moe`、`qwen3_5_text` | 作为主线升级方向 |
| Qwen3 Next / MoE | `qwen3_next`、`qwen3_moe` | 观察，先不默认展示 |
| Gemma 4 | `gemma4`、`gemma4_text` | 保留 E4B，E2B 做视觉 / 实验 |
| MiniCPM | `minicpm` | 实验池，重点测中文和格式稳定性 |
| GLM4 | `glm4`、`glm4_moe`、`glm4_moe_lite` | 保留 GLM-4 9B；MoE 先观察 |
| MiMo | `mimo`、`mimo_v2_flash` | 实验池 |
| SmolLM3 | `smollm3` | 低配候选，但需和 Qwen3.5 0.8B / 2B 对比 |
| LFM2 | `lfm2` | 低配候选，先观察 |
| EXAONE4 | `exaone4` | 低配 / 多语言候选，先观察 |
| GPT OSS | `gpt_oss` | 架构支持存在，但公开 MLX repo 需另行确认 |
| Jamba | `jamba_3b` | 架构支持存在，但公开可下载 repo 需另行确认 |
| Mistral3 | `mistral3` | 文本 / VLM 都可观察，但不进默认列表 |

`MLXVLM` 3.31.3 已注册这些视觉架构：

| 架构 | VLM `model_type` | Voxt 处理建议 |
|---|---|---|
| Qwen2 / Qwen2.5 / Qwen3 VL | `qwen2_vl`、`qwen2_5_vl`、`qwen3_vl` | 保留一个 Qwen3 VL 视觉入口 |
| Gemma 3 / Gemma 4 | `gemma3`、`gemma4` | Gemma 4 做视觉候选 |
| SmolVLM / FastVLM | `smolvlm`、`fastvlm` | 观察低配截图理解 |
| Pixtral / Mistral3 VLM | `pixtral`、`mistral3` | 观察，不默认展示 |
| LFM2-VL | `lfm2_vl`、`lfm2-vl` | 观察 |
| GLM OCR | `glm_ocr` | OCR 入口候选，但需产品化入口 |

### 候选 repo 快速核对

已核对公开 HF API / `config.json` 的候选：

| repo | 公开访问 | `model_type` | 初步动作 |
|---|---:|---|---|
| `mlx-community/Qwen3.5-0.8B-OptiQ-4bit` | 是 | `qwen3_5` | 修正代码中的 ID 后进入核心列表 |
| `mlx-community/Qwen3.5-2B-4bit` | 是 | `qwen3_5` | 核心列表 |
| `mlx-community/Qwen3.5-4B-OptiQ-4bit` | 是 | `qwen3_5` | 核心列表，建议默认 |
| `mlx-community/Qwen3.5-9B-OptiQ-4bit` | 是 | `qwen3_5` | 核心列表，高质量档 |
| `mlx-community/MiniCPM4-8B-4bit` | 是 | `minicpm` | 实验池 |
| `mlx-community/gemma-4-e4b-it-4bit` | 是 | `gemma4` | 核心列表或视觉备用 |
| `mlx-community/LFM2-1.2B-4bit` | 是 | `lfm2` | 观察池 |
| `mlx-community/SmolLM3-3B-4bit` | 是 | `smollm3` | 观察池 |
| `mlx-community/EXAONE-4.0-1.2B-4bit` | 是 | `exaone4` | 观察池 |
| `mlx-community/gpt-oss-20b-4bit` | 否 / 需 token | 未核对 | 不进计划 |
| `mlx-community/Jamba-Mini-1.6-4bit` | 否 / 需 token | 未核对 | 不进计划 |

## 功能与模型能力调整建议

### 本地文本 LLM

保留：

- 基础生成参数：max tokens、temperature、topP、topK、minP、repetition penalty。
- thinking toggle：继续保留，但默认关闭或 provider default，避免 Qwen / GLM 输出思考内容污染结果。
- per-repo generation settings：保留，适合高质量档调参。

收敛：

- 本地 LLM 不展示 JSON schema、logprobs、extra body、seed、stop sequences 等远端 / Ollama 风格能力。
- 本地模型 UI 不按系列平铺，改为按“轻量 / 平衡 / 高质量 / 视觉 / 实验”分组。
- 对视觉模型增加明确入口：只有包含图像附件的任务才推荐 VLM；普通文本增强默认使用文本 LLM。

新增：

- 模型健康检查：下载后读取 `config.json` 的 `model_type`，确认在 `LLMTypeRegistry` 或 `VLMTypeRegistry` 支持集中。
- chat template 检查：当前已有 `hasUsableChatTemplate`，建议在模型可见性和下载后状态中展示具体缺失原因。
- 本地 smoke matrix：每个可见模型至少跑文本清理、翻译、改写三类短输入；视觉模型额外跑一张截图输入。

## 执行计划

| 优先级 | 任务 | 说明 |
|---:|---|---|
| P0 | 修正 Qwen3.5 0.8B OptiQ repo ID | `mlx-community/Qwen3.5-0.8B-4bit-OptiQ` -> `mlx-community/Qwen3.5-0.8B-OptiQ-4bit`，增加 compatibility alias |
| P0 | 改默认本地 LLM | `Qwen/Qwen2-1.5B-Instruct` -> `mlx-community/Qwen3.5-4B-OptiQ-4bit` |
| P0 | 收敛默认可见核心列表 | 只保留 6 个核心文本模型 |
| P1 | 旧模型转 hiddenCompat | 保留历史选择、已下载显示、卸载路径 |
| P1 | 增加模型分组 | 轻量 / 平衡 / 高质量 / 视觉 / 实验 |
| P1 | 增加模型健康检查 | repo 可访问、`model_type` 支持、chat template、关键文件完整性 |
| P2 | 建立本地 LLM smoke matrix | 核心模型必须覆盖文本清理、翻译、改写、会议总结；视觉模型覆盖截图上下文 |
| P2 | 观察池 A/B | SmolLM3、LFM2、EXAONE4、MiMo、MiniCPM4、Mistral3 |

## 验收标准

1. 默认可见本地 LLM 不超过 9 个，其中核心文本模型不超过 6 个。
2. 所有可见 repo 均公开可访问，或有清晰的 gated/token 提示；不能出现点击下载后才发现 repo 不可用。
3. 每个可见模型的 `config.json.model_type` 都能被当前 `mlx-swift-lm` 版本加载。
4. 旧配置不会失效：`displayModels(including:)` 能展示隐藏兼容模型，用户可以继续使用或删除。
5. 默认模型在无额外配置时能完成 Voxt 的文本清理、翻译、改写三类任务，不输出思考过程、不重复、不包 code fence。

## 参考来源

- Voxt 当前本地 LLM 目录：`Voxt/Core/Models/CustomLLMModelSupport.swift`
- Voxt 当前 MLXLLM pin：`Voxt.xcodeproj/project.pbxproj`
- MLX Swift LM release 3.31.3：https://github.com/ml-explore/mlx-swift-lm/releases/tag/3.31.3
- MLX Swift LM README：https://github.com/ml-explore/mlx-swift-lm
- MLXLLM 3.31.3 `LLMTypeRegistry`：https://raw.githubusercontent.com/ml-explore/mlx-swift-lm/3.31.3/Libraries/MLXLLM/LLMModelFactory.swift
- MLXVLM 3.31.3 `VLMTypeRegistry`：https://raw.githubusercontent.com/ml-explore/mlx-swift-lm/3.31.3/Libraries/MLXVLM/VLMModelFactory.swift
- Hugging Face model API / raw config：逐个 repo 通过 `https://huggingface.co/api/models/<repo>` 与 `https://huggingface.co/<repo>/raw/main/config.json` 核对。

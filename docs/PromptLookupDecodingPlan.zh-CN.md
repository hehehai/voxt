# Prompt Lookup Decoding 实现方案

本文档描述 Voxt 针对本地 LLM 转写润色链路的一个性能优化方案。

核心思路是：在 ASR 得到原始转写文本后，如果后续需要用本地 Custom LLM 做保守润色，可以把原始 ASR 文本作为草稿 token 来源，让主模型在生成最终润色文本时批量验证这些候选 token，从而减少逐 token 生成的开销。

这个能力应当作为本地 LLM 的内部加速策略，而不是一个独立的用户功能。目标是不改变最终输出语义，只降低本地 LLM 生成延迟。

## 一句话结论

第一版建议只做：

```text
Local Custom LLM + transcription enhancement
```

也就是只优化“本地 LLM 转写增强 / 润色”这一条路径。

暂不建议用于：

- 纯 ASR 转录
- 远程 LLM
- Apple Intelligence
- 翻译
- 无选中文本的开放式 rewrite / direct answer
- 大幅改写类 rewrite

## 生效时间点

这个优化发生在 ASR 之后、最终文本交付之前，具体是在本地 LLM 解码生成 token 的阶段。

```text
录音结束
-> ASR 生成原始转写文本
-> 解析 enhancement prompt / app enhancement / 词典上下文
-> 构建本地 Custom LLM 请求
-> 本地 LLM 生成最终润色文本
   -> 从原始 ASR 文本中查找候选 draft tokens
   -> 主模型批量验证候选 tokens
   -> 匹配的 token 直接接受
   -> 不匹配时回退到主模型正常生成
-> 清理模型输出
-> 粘贴 / 展示 / 写入历史
```

它不会优化：

- 录音采集耗时
- ASR 推理耗时
- 远程 API 请求耗时
- Apple Intelligence 调用耗时
- 本地模型冷启动 / 加载耗时
- prompt prefill 耗时

它只优化本地 LLM 的 generation 阶段。

## 当前代码链路

当前本地转写增强的大致链路是：

1. `AppDelegate+TranscriptionFlow.swift`
   - ASR 完成后进入 enhancement 流程。
   - 解析 enhancement 策略和 prompt。
   - 构建 `LLMExecutionPlan`。
2. `AppDelegate+LLMExecutionPlanning.swift`
   - 根据 provider 分发执行。
   - `.customLLM(repo:)` 会进入 `CustomLLMModelManager.executeCompiledRequest(...)`。
3. `CustomLLMModelManager.swift`
   - `executeCompiledRequest(...)` 把 `LLMCompiledRequest` 转成 `CustomLLMRequestPlan`。
   - `runLocalPromptRequest(...)` 创建 `ChatSession`。
   - `session.streamDetails(...)` 执行当前普通 MLX 流式生成。
4. `CustomLLMModelSupport.swift`
   - `CustomLLMRequestPlan` 承载本地 LLM 请求信息。
   - `CustomLLMRequestPlanBuilder.enhancement(...)` 构建转写清理请求。

因此，Prompt Lookup Decoding 的实现落点不在 UI，也不在 prompt builder，而是在本地 LLM 最终 token generation 这一层。

## 支持范围

| 功能 | 第一版是否支持 | 原因 |
| --- | --- | --- |
| 纯 ASR 转录 | 不支持 | 没有 LLM 生成阶段，无法应用该优化。 |
| 本地 Custom LLM 转写增强 | 支持 | 最终文本通常大量复用原始 ASR 文本，命中率最高。 |
| 本地 Custom LLM 选中文本 rewrite | 后续评估 | 只适合“润色 / 修正 / 改语气”这种保守改写。 |
| 本地 Custom LLM direct answer | 不支持 | 输出不是输入文本的轻微变体。 |
| 翻译 | 默认不支持 | 输出语言变化，draft token 命中率预计较低。 |
| 远程 LLM | 不支持 | 远程 API 不开放 token 级解码控制。 |
| Apple Intelligence | 不支持 | Voxt 无法控制底层生成循环。 |

## 请求结构调整

建议给本地 LLM 请求计划增加一个显式的可选草稿来源：

```swift
struct CustomLLMRequestPlan {
    ...
    let promptLookupDraftText: String?
}
```

第一版只在 enhancement builder 中设置：

```swift
CustomLLMRequestPlanBuilder.enhancement(
    input: rawASRTranscript,
    ...
    promptLookupDraftText: rawASRTranscript
)
```

注意：`promptLookupDraftText` 不应该混进 prompt 文本，也不应该复用日志字段。它是生成阶段的元数据，不是给模型看的指令。

这样可以保持几个概念清晰分离：

- `prompt`: 模型实际看到的用户请求
- `instructions`: system prompt / app enhancement / 规则
- `contentLogSections`: 调试日志
- `promptLookupDraftText`: 解码阶段用的草稿来源

## 解码算法

Prompt Lookup Decoding 可以理解成“不使用 draft model 的 speculative decoding”。

普通 speculative decoding 是：

```text
小模型先猜 N 个 token
-> 大模型批量验证
-> 猜对就接受
-> 猜错就回退到大模型 token
```

Prompt Lookup Decoding 是：

```text
代码从原始 ASR 文本中查找 N 个候选 token
-> 主模型批量验证
-> 匹配就接受
-> 不匹配就回退到主模型 token
```

建议的 iterator 逻辑：

1. 把原始 ASR 文本 tokenize 成 `draftTokens`。
2. 维护已经生成并接受的输出 tokens。
3. 取最近一段输出 token 后缀。
4. 在 `draftTokens` 中查找这个后缀。
5. 如果找到，取后面的 `N` 个 token 作为候选。
6. 主模型一次性验证这批候选 tokens。
7. 从头接受连续匹配的 tokens。
8. 第一个不匹配的位置使用主模型自己的 token。
9. 回滚 rejected tokens 对应的 KV cache。
10. 重复直到达到 stop / max token 条件。

关键点是：输出仍然由主模型验证，draft tokens 只是候选，不是直接强行复制。

## 实现路径

### 方案 A：扩展 MLXLMCommon

在 `mlx-swift-lm` 中增加 Prompt Lookup Decoding 能力，例如：

```swift
generate(
    input: LMInput,
    parameters: GenerateParameters,
    context: ModelContext,
    promptLookupDraftTokens: [Int],
    promptLookupConfig: PromptLookupDecodingConfig
)
```

同时扩展 `ChatSession` 或提供一个并行的 stream API，让 Voxt 可以在保持现有 chat-template、tokenizer、KV cache、streaming 逻辑的基础上启用 prompt lookup。

优点：

- 解码逻辑放在模型运行时层，边界最清楚。
- 不需要在 Voxt 里复制 `ChatSession` 的内部逻辑。
- 更容易在 MLX 层做独立测试。
- 后续也可能对其他使用 `mlx-swift-lm` 的项目有价值。

缺点：

- 需要改 package 依赖，可能要 fork/tag 或推动 upstream。
- API 需要设计得通用，不能太 Voxt 特化。

### 方案 B：Voxt 本地实现一条专用生成路径

当 `promptLookupDraftText` 存在时，不走 `session.streamDetails(...)`，而是在 Voxt 里直接调用更底层的 MLX processor / tokenizer / model / cache，运行自定义 prompt lookup iterator。

大致步骤：

1. 用当前 model processor 准备 chat input。
2. 创建 KV cache。
3. 用 Voxt 自己的 prompt lookup iterator 生成 token。
4. 用 tokenizer 解码成 streaming chunks。
5. 保留现有 repetition guard、output sanitizer、diagnostics、partial preview。

优点：

- 不需要马上改上游包。
- 可以较快做出原型验证真实收益。

缺点：

- 容易复制 `ChatSession` 内部逻辑。
- 后续 `mlx-swift-lm` 更新时维护成本更高。
- 可能遗漏 tool call、chat-template、additionalContext、streaming 细节。

推荐：最终实现优先选方案 A。方案 B 只适合作为短期原型，用来先采集真实延迟和命中率数据。

## 配置策略

第一版不建议放到普通设置页。

建议初始策略：

- 只对本地 Custom LLM 的 transcription enhancement 生效。
- 对 translation、direct-answer rewrite、remote provider、Apple Intelligence 默认关闭。
- 可以先放在内部 debug flag 或隐藏偏好里。
- 输入过短时自动跳过，因为查找和验证开销可能大于收益。

建议 gate：

```text
provider == customLLM
task == enhancement
rawTranscriptCharacterCount >= 80
promptLookupAccelerationEnabled == true
```

后续可以根据真实命中率做自适应：

```text
recentAcceptanceRatio < 0.30 -> 自动关闭
recentAcceptanceRatio >= 0.60 -> 保持启用
```

## 指标设计

启用前必须先加指标，否则无法判断是否真的变快。

| 指标 | 用途 |
| --- | --- |
| `promptLookupDraftTokens` | 原始 ASR 草稿 token 数。 |
| `promptLookupProposedTokens` | 总共提议了多少候选 tokens。 |
| `promptLookupAcceptedTokens` | 被主模型接受的候选 tokens。 |
| `promptLookupAcceptanceRatio` | 核心收益指标。 |
| `firstChunkMs` | 检查首个可见输出是否变慢。 |
| `generationMs` | 主要预期优化目标。 |
| `totalElapsedMs` | 本地 LLM 总耗时。 |
| `fallbackToNormalDecoding` | 记录何时回退普通解码。 |

判断阈值建议：

- `acceptanceRatio >= 0.60`：通常值得启用。
- `acceptanceRatio < 0.30`：大概率收益有限，应该关闭或回退。
- 短文本即使命中率高，总耗时也可能无明显改善。

## 预期收益

这个优化只影响本地 LLM generation 阶段，所以端到端收益取决于 generation 在整条链路中的占比。

| 场景 | 预期收益 |
| --- | --- |
| 80 字以内短文本 | 0-10%，可能无感。 |
| 100-500 字保守转写润色 | 本地 LLM 总耗时降低 10-30%。 |
| 500+ 字长文本，且输出高度复用原文 | generation 阶段降低 25-50%，本地 LLM 总耗时降低 15-40%。 |
| 翻译 / 开放式 rewrite | 低收益或负收益。 |

更现实的目标：

- `generationMs` 降低 25-40%
- `totalElapsedMs` 降低 10-25%
- `firstChunkMs` 不一定改善，甚至可能略微变差

是否值得做，最终要看真实 app 日志里的 `promptLookupAcceptanceRatio`。

## 风险

- 命中率低时会增加额外开销。
- KV cache 回滚必须正确，否则输出可能漂移。
- 字符串相似不代表 token 相似，tokenizer 会影响命中率。
- JSON 结构化输出提取不能被破坏。
- partial preview 不能出现明显闪烁或倒退。
- repetition guard 和 output sanitizer 必须保留。
- 如果改 `mlx-swift-lm`，需要明确依赖策略，避免长期维护重 fork。

## 测试计划

单元测试：

- enhancement request plan 只在合适场景填充 draft source。
- translation / direct answer / remote path 不填充 draft source。
- prompt lookup suffix matching 能找到预期 token 窗口。
- 空输入、短输入、低命中率时能回退普通解码。
- proposed / accepted / ratio 指标计算正确。

本地运行测试：

- `docs/LocalRegressionMatrix.md` 中的 core prompt/runtime suites。
- Local LLM smoke，对比开启和关闭 prompt lookup。
- 英文、中文转写样本各跑一组。
- 长文本和短文本分开统计。

手动验证：

- 原始 ASR 文本
- 普通 LLM 润色结果
- Prompt Lookup LLM 润色结果
- `generationMs`
- `firstChunkMs`
- `totalElapsedMs`
- `acceptanceRatio`

验收标准：

- 输出语义不应比普通生成更差。
- 在确定性设置下，尽量和 baseline 输出保持一致。
- 在非确定性采样下，差异不应超过正常采样波动。
- 只有在真实日志显示稳定收益后才默认启用。

## 分阶段计划

1. 先加 request plan 字段和指标 scaffolding，但不改变生成行为。
2. 做 prompt lookup iterator 原型。
3. 用真实本地 LLM enhancement 样本跑 A/B 对比。
4. 根据 acceptance ratio 和 latency 判断是否继续。
5. 若收益稳定，决定把实现放进 `mlx-swift-lm` upstream/fork，还是保留 Voxt 本地路径。
6. 第一版只启用本地 Custom LLM transcription enhancement。
7. 后续再评估 selected-text rewrite 的保守润色场景。

## 仍需确认的问题

- 实现应该进入 upstream `mlx-swift-lm`，还是 Voxt fork/tag？
- 最小输入长度应该是多少？
- 每轮 draft window size 设为多少最合适？
- 是否按模型 repo 记录近期命中率并自动开关？
- 指标是否并入现有 session timing summary？
- 对中文、英文、混合语言文本的 token 命中率是否有明显差异？

# Local Regression Matrix

This matrix is the local-only regression entrypoint for Voxt transcription pipelines.

These suites are intended for:
- real model execution on the current Mac
- ASR / LLM / realtime / final-only regression after runtime changes
- debugging latency, tail loss, and model-specific behavior

These suites are **not** intended for CI. Public fixture integration tests skip automatically on `CI` / `GITHUB_ACTIONS`.

## Status Legend

- `green`: currently stable and suitable as a local gate
- `yellow`: useful for diagnosis, but not yet reliable as a strict gate
- `red`: known broken or intentionally not yet gated

## Current Matrix

| Area | Pipeline / Scenario | Model / Provider | Strategy | Test Coverage | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| ASR | Final-only, short official fixtures | MLX Audio | offline final | `QwenOfficialFixtureASRIntegrationTests` | green | English + Chinese + emotion anchors |
| ASR | Final-only, long official fixtures | MLX Audio | offline final | `MLXLongFormReplayIntegrationTests` | green | Baseline, tail coverage, late updates, composite tail anchors |
| ASR | Final-only(hidden), long replay final-path safety | MLX Audio | hidden intermediate + full final | `MLXFinalOnlyReplayIntegrationTests` | green | Guards the simplified `stop -> finalASR` path and verifies final-only replay no longer depends on post-stop quick preview |
| ASR | Live-display replay, public official fixtures | MLX Audio | live partial + post-stop quick preview + final | `MLXRealtimeReplayIntegrationTests` | green | Public fixture realtime replay for live partial cadence and stop preview behavior |
| Metrics | Replay-based pipeline envelope | MLX Audio | final-only + live-display official long fixtures | `MLXPipelineMetricsIntegrationTests` | green | Verifies final-only no longer emits stop-preview while live-display still tracks preview published rate, reuse eligibility proxy, preview/final divergence, and late-coverage rate |
| ASR | Final-only, short official fixtures | Whisper | offline final | `WhisperOfficialFixtureASRIntegrationTests` | red | Latest local run failed all multilingual official anchor checks; keep as diagnostic only |
| ASR | Realtime replay, long clips | Whisper | live partial + final | `WhisperRealtimeReplayIntegrationTests` | red | Latest local run failed to sustain later replay events and failed live/final event assertions |
| Metrics | Replay-based preview quality envelope | Whisper | live-display official long fixtures | `WhisperPipelineMetricsIntegrationTests` | red | Tracks preview published rate, preview reuse eligibility proxy, preview/final divergence, and late-coverage rate for diagnostic comparison against MLX |
| ASR | Final-only, installed-model long-form sanity | MLX Audio / Whisper | offline final | `InstalledASRLongFormMatrixIntegrationTests` | yellow | Mixed provider sweep; useful for ranking installed models, not a strict gate |
| Pipeline | Final-only vs live-display routing | shared | pipeline selection | `TranscriptionCapturePipelineTests` | green | Verifies stage topology |
| Metrics | Real session summary parsing and recent-N aggregation | shared | app log aggregation | `SessionTimingSummarySupportTests` | green | Validates parsing and per-ASR-provider/model plus pipeline plus LLM-provider aggregation for `llmCalls`, `stopToDeliveredMs`, `stopToASRMs`, and `captureGapMs` |
| Runtime | Session text delivery / session end | shared | post-processing | `SessionTextIOTests`, `SessionEndFlowTests` | green | Useful when changing commit / delivery behavior |
| LLM | Prompt/runtime compiler | shared | enhancement / translation / rewrite planning | `LLMExecutionPlanCompilerTests`, `EnhancementPromptResolverTests`, `PromptBuildersTests`, `AppPromptDefaultsTests`, `ModelDebugSupportTests` | green | Stable prompt/runtime regression layer |
| LLM | Real local enhancement latency | Custom LLM | instant / balanced / quality | app logs + `AppDelegate+LLMSmoke.swift` | yellow | Real behavior is best evaluated with manual smoke and session timing logs |
| End-to-end | Non-realtime transcription | MLX ASR + local LLM | stop -> final -> deliver | manual app regression + `Session timing summary` | green | Current simplified main path |
| End-to-end | Realtime transcription UI | ASR live partial + stop preview reuse | live display | manual app regression + `Session timing summary` | yellow | Needs more repeatable live UI baselines |

## Recommended Local Runs

### 1. Fast core regression

Use after changing prompt/runtime/delivery logic:

```bash
./tools/run_local_regression_matrix.sh core
```

This runs:
- `TranscriptionCapturePipelineTests`
- `SessionTimingSummarySupportTests`
- `SessionTextIOTests`
- `SessionEndFlowTests`
- `LLMExecutionPlanCompilerTests`
- `EnhancementPromptResolverTests`
- `PromptBuildersTests`
- `AppPromptDefaultsTests`
- `ModelDebugSupportTests`

### 2. MLX public fixture regression

Use after changing MLX ASR, stop/final handling, or long-form behavior:

```bash
./tools/run_local_regression_matrix.sh mlx
```

This runs:
- `QwenOfficialFixtureASRIntegrationTests`
- `MLXLongFormReplayIntegrationTests`
- `MLXFinalOnlyReplayIntegrationTests`
- `MLXRealtimeReplayIntegrationTests`
- `MLXPipelineMetricsIntegrationTests`

### 3. Whisper diagnostic regression

Use after changing Whisper runtime, but treat failures as diagnostic unless the local Whisper setup is known-good:

```bash
./tools/run_local_regression_matrix.sh whisper
```

This runs:
- `WhisperOfficialFixtureASRIntegrationTests`
- `WhisperLongFormReplayIntegrationTests`
- `WhisperRealtimeReplayIntegrationTests`
- `WhisperPipelineMetricsIntegrationTests`

### 4. Stable local gate

Use as the default local regression gate before and after runtime changes:

```bash
./tools/run_local_regression_matrix.sh all
```

This currently runs only the stable green groups:
- `core`
- `mlx`

### 5. Diagnostic matrix

Use when investigating provider/model-specific behavior that is not yet a stable gate:

```bash
./tools/run_local_regression_matrix.sh diagnostic
```

This runs:
- `WhisperOfficialFixtureASRIntegrationTests`
- `WhisperLongFormReplayIntegrationTests`
- `WhisperRealtimeReplayIntegrationTests`
- `InstalledASRLongFormMatrixIntegrationTests`

## Latest Verified Results

Latest local runs on this machine:

- `./tools/run_local_regression_matrix.sh all`
  - passed
  - stable gate currently consists of `core` + `mlx`
- `./tools/run_local_regression_matrix.sh mlx`
  - passed `14/14`
- `./tools/run_local_regression_matrix.sh diagnostic`
  - failed inside `whisper`
  - latest observed failures:
    - `WhisperOfficialFixtureASRIntegrationTests`: `3` tests failed with `6` assertion failures
    - `WhisperLongFormReplayIntegrationTests`: `5` tests executed, `2` failed
    - `WhisperRealtimeReplayIntegrationTests`: `2` tests executed, `2` failed
- `./tools/run_local_regression_matrix.sh installed`
  - failed
  - latest observed failures:
    - `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit`: collapsed on long Chinese composite fixture
    - `beshkenadze/cohere-transcribe-03-2026-mlx-fp16`: missing `tokenizer.model`
    - `mlx-community/granite-4.0-1b-speech-5bit`: ballooned badly on long English composite fixture and collapsed on long Chinese composite fixture
    - `whisper small`: collapsed on long English composite fixture
    - `whisper large-v3`: collapsed on long Chinese composite fixture

## Manual App Regression Checklist

The automated suites do not replace manual app verification. After major runtime changes, also check:

### Session timing summary aggregation

- Use `Session timing summary` lines from real app runs
- Track recent-N aggregates by `output + pipeline + asrProvider + asrModel + llmProvider`
- Watch:
  - `meanLLMCalls`
  - `meanStopToDeliveredMs`
  - `meanStopToASRMs`
  - `meanCaptureGapMs`
- These are validated structurally by `SessionTimingSummarySupportTests`; the underlying values still come from real runs

For quick local reporting without opening Xcode, you can aggregate saved logs directly:

```bash
swift ./tools/session_timing_summary_report.swift --limit 5 /path/to/voxt.log
```

The script prints one row per:
- `output`
- `pipeline`
- `asrProvider`
- `asrModel`
- `llmProvider`

### Final-only transcription

- Realtime UI disabled
- ASR provider: MLX
- LLM enhancement enabled
- Verify:
  - `llmCalls=1`
  - `stopToASRMs`
  - `stopToDeliveredMs`
  - no tail loss on a longer recording

### Live-display transcription

- Realtime UI enabled
- Verify:
  - first visible partial timing
  - partial stability / rollback behavior
  - stop-after-preview reuse
  - final reconciliation without duplicate enhancement

### Long recording tail safety

- Use a deliberately longer utterance
- Verify:
  - `capturedAudioMs`
  - `captureGapMs`
  - final transcript tail against expected ending

## Current Optimization Priorities

Based on the latest local runs:

1. `stopToASRMs` remains the main latency bottleneck.
2. `MLX + 2B instant enhancement` is fast enough that startup and final-path execution are now the main focus.
3. Whisper still needs a more deterministic local regression configuration before it can be treated as a strict gate.

# Local Regression Matrix

Use this document to choose focused local checks before a full release gate. CI remains the source of truth for broad regression coverage.

## Groups

| Group | Scope | Command |
| --- | --- | --- |
| core | Capture pipeline, session flow, prompt building, VAD planning, Feature Settings, MLX planning, model debug | `tools/run_local_regression_matrix.sh core` |
| mlx | MLX public fixture and replay tests | `VOXT_RUN_MODEL_TESTS=1 tools/run_local_regression_matrix.sh mlx` |
| vad | Local VAD mode, runtime policy, storage, debug snapshot | `tools/run_local_regression_matrix.sh vad` |
| whisper | Whisper diagnostic fixture/replay tests | `tools/run_local_regression_matrix.sh whisper` |
| installed | Installed-model long-form matrix | `tools/run_local_regression_matrix.sh installed` |
| all | core + mlx + vad | `tools/run_local_regression_matrix.sh all` |
| full | core + mlx + vad + whisper + installed | `tools/run_local_regression_matrix.sh full` |

## VAD / ASR Gate Safety

Current runtime VAD choices are global and local-only:

- `Automatic`: Voxt selects the local policy for the workflow.
- `Silero`: local `mlx-community/silero-vad`.
- `Energy`: lightweight local level detector.
- `Off`: disables local VAD gating while preserving capture and final ASR.

The VAD group must cover:

- `LocalVADMode` parsing, persistence, and default behavior.
- Runtime backend resolution for transcription, translation, rewrite, and meeting.
- Meeting frame VAD behavior for Silero, Energy, and Off.
- Local gate disabled for non-local ASR.
- Debug snapshot fields: VAD Mode, Frame VAD, Local Gate.
- Segmenter hysteresis, trailing silence, minimum speech duration, and telemetry reasons.
- Non-finite audio sample, level, rate, and timestamp normalization before model input or segment state updates.

## Phase 6 Smoke Gate

Run before manual acceptance or packaging validation:

```bash
tools/run_vad_phase6_smoke.sh --duration 300 --interval 30
```

The phase-6 smoke gate builds Release by default and then runs:

- Launch smoke with VAD/Silero fatal/error denylist.
- Privacy denylist for raw audio, full transcript, transcript text, and prompt text.
- Damaged local MLX Silero cache smoke.
- Clean preferences smoke.
- `localVADMode` smoke for `automatic`, `silero`, `energy`, and `off`.
- Acceptance report generation.

Validate a filled report with:

```bash
tools/validate_vad_acceptance_report.sh --report <report.md>
```

Use `--allow-unsigned` only for local unsigned package preflight.

## Manual Gate

Manual acceptance lives in `docs/VADManualAcceptance.zh-CN.md`. Do not promote a VAD parameter change to default until meeting, transcription, translation, rewrite, long-recording, stop/cancel, device-change, sleep/wake, and packaging scenarios pass with evidence.

# Prompt Lookup Decoding Plan

This document outlines a proposed local LLM acceleration strategy for Voxt's transcription refinement path.

The feature is based on Prompt Lookup Decoding: use the original ASR transcript as a draft-token source while the main local LLM verifies and generates the final refined text.

## Summary

Voxt often uses a local Custom LLM after ASR to clean up transcription output. In conservative cleanup, the final text is usually very close to the raw ASR transcript. Prompt Lookup Decoding can exploit that overlap by proposing likely output tokens from the raw transcript and letting the main model verify them in batches.

This should be treated as an internal local generation optimization, not as a separate user-facing feature. The intended behavior is unchanged output with lower local LLM latency.

## Pipeline Timing

The optimization happens after ASR and before final text delivery:

```text
recording stops
-> ASR produces raw transcript
-> enhancement prompt is resolved
-> local Custom LLM request is built
-> local LLM decodes final refined text
   -> prompt lookup proposes draft tokens from the raw transcript
   -> main model verifies accepted tokens
-> final text is sanitized, delivered, and saved
```

It does not accelerate audio capture, ASR, remote network requests, Apple Intelligence, model loading, or prompt prefill. It only targets the local LLM token generation phase.

## Current Voxt Entry Points

The current local enhancement path is:

1. `AppDelegate+TranscriptionFlow.swift`
   - Resolves enhancement strategy and prompt.
   - Builds the enhancement execution plan.
2. `AppDelegate+LLMExecutionPlanning.swift`
   - Dispatches `.customLLM(repo:)` plans to `CustomLLMModelManager.executeCompiledRequest(...)`.
3. `CustomLLMModelManager.swift`
   - `executeCompiledRequest(...)` converts `LLMCompiledRequest` into `CustomLLMRequestPlan`.
   - `runLocalPromptRequest(...)` creates a `ChatSession`.
   - `session.streamDetails(...)` performs normal MLX token generation.
4. `CustomLLMModelSupport.swift`
   - `CustomLLMRequestPlan` carries local request metadata.
   - `CustomLLMRequestPlanBuilder.enhancement(...)` builds the transcription cleanup request.

The proposed optimization belongs at step 3: the local token generation path.

## Supported Scope

Initial scope should be narrow.

| Flow | Support | Reason |
| --- | --- | --- |
| Plain ASR transcription without LLM enhancement | No | There is no LLM decoding stage to accelerate. |
| Local Custom LLM transcription enhancement | Yes | Output usually reuses most of the ASR transcript. |
| Local Custom LLM selected-text rewrite | Later / conditional | Useful only for conservative polish, not open-ended rewriting. |
| Local Custom LLM direct-answer rewrite | No | Output is not a transformation of source text. |
| Translation | No by default | Output language differs, so draft-token acceptance is expected to be low. |
| Remote LLM | No | Remote APIs do not expose token-level verification. |
| Apple Intelligence | No | Voxt cannot control the decoding loop. |

## Request Plan Changes

Add an explicit optional draft source to local LLM requests:

```swift
struct CustomLLMRequestPlan {
    ...
    let promptLookupDraftText: String?
}
```

Populate it only for local transcription enhancement in the first iteration:

```swift
CustomLLMRequestPlanBuilder.enhancement(
    input: rawASRTranscript,
    ...
    promptLookupDraftText: rawASRTranscript
)
```

Keep this field separate from `contentLogSections`, `debugInput`, and prompt content. The draft source is generation metadata, not instructions to the model.

## Generation Strategy

The clean long-term implementation is to add a Prompt Lookup Decoding path to the MLX generation layer.

The iterator should:

1. Tokenize the raw transcript into `draftTokens`.
2. Maintain generated/accepted output tokens.
3. Match the recent generated suffix inside `draftTokens`.
4. Propose the next `N` draft tokens after the matched position.
5. Run the main model once over the proposed tokens.
6. Accept the matching prefix.
7. Emit the first main-model token at the mismatch point.
8. Rewind any rejected cache entries.
9. Repeat until normal stop conditions are met.

This mirrors speculative decoding, but the draft source is code plus prompt text rather than a smaller draft model.

## Integration Options

### Option A: Extend MLXLMCommon

Add an upstream-style API to `mlx-swift-lm`:

```swift
generate(
    input: LMInput,
    parameters: GenerateParameters,
    context: ModelContext,
    promptLookupDraftTokens: [Int],
    promptLookupConfig: PromptLookupDecodingConfig
)
```

Then extend `ChatSession` or add a parallel stream API that accepts prompt lookup options.

Benefits:
- Keeps decoding logic in the model runtime layer.
- Avoids duplicating tokenizer, cache, streaming, and metrics behavior in Voxt.
- Easier to test independently against MLX token iterators.

Costs:
- Requires changes in the package dependency or a fork/tag.
- Needs careful API design to avoid carrying Voxt-specific behavior upstream.

### Option B: Add a Voxt-local Generation Path

Bypass `ChatSession.streamDetails(...)` only when `promptLookupDraftText` is present:

1. Prepare chat input using the same model processor.
2. Create the model cache.
3. Run a Voxt-owned prompt lookup iterator.
4. Decode chunks with the tokenizer.
5. Preserve existing streaming, repetition guard, diagnostics, and output sanitizer behavior.

Benefits:
- More contained to Voxt.
- Can be prototyped without waiting on upstream API shape.

Costs:
- Duplicates parts of `ChatSession`.
- Higher maintenance risk when `mlx-swift-lm` changes.
- Easy to diverge from existing tool-call or chat-template behavior.

Recommendation: prefer Option A for the final implementation. Use Option B only for a short-lived prototype if we need real latency data before committing to a package-level change.

## Configuration

Do not expose this as a primary user-facing feature at first.

Recommended initial behavior:

- Enabled only for local Custom LLM transcription enhancement.
- Disabled for translation, direct-answer rewrite, and remote providers.
- Hidden behind an internal preference or debug flag until metrics are stable.
- Automatically bypassed for very short inputs where matching overhead may exceed benefit.

Potential internal gate:

```text
provider == customLLM
task == enhancement
rawTranscriptCharacterCount >= 80
promptLookupAccelerationEnabled == true
```

## Metrics

Add diagnostics before enabling broadly:

| Metric | Purpose |
| --- | --- |
| `promptLookupDraftTokens` | Size of draft-token source. |
| `promptLookupProposedTokens` | Total candidate tokens proposed. |
| `promptLookupAcceptedTokens` | Tokens accepted without normal single-token generation. |
| `promptLookupAcceptanceRatio` | Main success signal. |
| `firstChunkMs` | Ensure first visible output does not regress badly. |
| `generationMs` | Main expected improvement target. |
| `totalElapsedMs` | End-to-end local LLM impact. |
| `fallbackToNormalDecoding` | Detect unsupported or low-value paths. |

Expected useful thresholds:

- `acceptanceRatio >= 0.60`: likely worth enabling for that path.
- `acceptanceRatio < 0.30`: likely not worth using.
- Short inputs may show low or no total latency gain even with good acceptance.

## Expected Impact

The optimization only affects local LLM generation time. It should not be expected to improve cold model load, ASR, remote LLM latency, or prompt prefill.

Estimated impact for local Custom LLM enhancement:

| Scenario | Expected Result |
| --- | --- |
| Short input under 80 characters | 0-10% total improvement, possibly no benefit. |
| 100-500 character conservative cleanup | 10-30% local LLM total improvement. |
| Long conservative cleanup with high overlap | 25-50% generation-phase improvement, 15-40% local LLM total improvement. |
| Rewrite/translation/open generation | Low or negative benefit. |

These estimates need validation with real app logs and local smoke runs.

## Risks

- Low acceptance ratio can add overhead.
- Cache rewind behavior must be correct, or generated text can drift.
- Tokenizer-specific behavior matters; character-level similarity does not guarantee token-level acceptance.
- Structured JSON extraction paths must continue to work.
- Streaming previews should not flicker or regress.
- Repetition guard and output sanitization must stay in place.
- Any package-level changes need a clear dependency policy, preferably upstream-friendly.

## Test Plan

Unit-level tests:

- Request plan builder populates draft source only for enhancement.
- Prompt lookup matching finds suffixes and proposes expected token windows.
- Low-match and empty-input cases fall back to normal decoding.
- Metrics calculate proposed, accepted, and ratio correctly.

Runtime/local tests:

- Existing core prompt/runtime suites from `docs/LocalRegressionMatrix.md`.
- Local LLM smoke for transcription enhancement with and without prompt lookup.
- Manual app runs comparing:
  - raw ASR text
  - final enhanced text
  - generation latency
  - acceptance ratio
  - first chunk latency

Regression acceptance:

- Output should remain semantically equivalent to normal decoding.
- If outputs differ, differences should be no worse than normal sampling variance at the configured temperature.
- For deterministic local settings, compare sanitized final output against baseline fixtures where feasible.

## Rollout Plan

1. Add metrics-only scaffolding and draft-source plumbing.
2. Prototype prompt lookup decoding in a local branch.
3. Run local smoke tests on representative English and Chinese transcripts.
4. Compare normal decoding vs prompt lookup decoding.
5. Enable internally for local Custom LLM transcription enhancement when acceptance ratio is strong.
6. Decide whether to upstream or fork/tag the MLX runtime change.
7. Consider selected-text rewrite only after enhancement proves reliable.

## Open Questions

- Should this live upstream in `mlx-swift-lm`, or as a Voxt-maintained fork patch?
- What minimum input length should enable prompt lookup?
- What draft window size gives the best latency tradeoff on Apple Silicon?
- Should the optimization auto-disable per repo if recent acceptance ratio is low?
- How should metrics be surfaced in existing session timing summaries?

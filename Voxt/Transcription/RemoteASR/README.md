# Remote ASR

Remote ASR transcriber implementations and streaming support for provider-backed transcription.

## Responsibilities

- Implements remote ASR client behavior for providers such as Aliyun, Doubao, and StepFun.
- Maintains streaming contexts, provider payload support, realtime debug helpers, and shared remote ASR contracts.
- Keeps provider-specific streaming code separate from local transcription engines.

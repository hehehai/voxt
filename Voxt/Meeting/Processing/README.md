# Meeting Processing

Post-capture meeting processing for ASR, translation, transcript assembly, and final summaries.

## Responsibilities

- Transcribes meeting segments and combines them into coherent final transcript output.
- Smooths speaker turns, assembles speaker-aware transcript text, and prepares final meeting records.
- Applies translation and summary support after audio capture is complete.

## File import and finalization

`MeetingImportedFileAnalyzer` registers import work before awaiting the previous live-session cleanup. Cancellation captures that operation rather than looking up a potentially newer task later. It remains busy through cleanup and cancels abandoned operations.

`MeetingImportedFilePipeline` owns one import's transcriber, normalized temporary audio and model use; it does not mutate live coordinator engine/transcriber fields. Failure or cancellation discards its prepared output; success transfers the audio result to the caller for history persistence.

`MeetingFinalizationContext` snapshots stop-time identity, engine/model metadata, duration and visible segments for all recovery checkpoints. The live coordinator remains occupied until final checkpoint cleanup finishes, and repeated stop calls return the same task.

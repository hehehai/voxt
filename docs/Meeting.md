# Meeting Notes

This document explains Voxt's Meeting Notes mode: what it does, how to configure it, which engines it supports, and what to expect from the current beta implementation.

## Overview

Meeting Notes is a separate long-running capture mode for meetings, calls, interviews, and podcasts.

<video src="https://github.com/user-attachments/assets/1ede04a2-1348-483e-b487-22561ad02a77" controls preload="none" width="100%"></video>

- Starts with the dedicated meeting shortcut
- Opens a floating meeting card instead of the normal transcription card
- Does not paste text into the focused input
- Saves results into a dedicated `Meeting` history type
- Can open a detail window for timeline review, translation, and export

Current beta starts with source-based separation:

- microphone audio is labeled as `Me`
- system audio is labeled as `Them`
- optional `Identify multiple remote speakers` can relabel system audio into `Remote 1`, `Remote 2`, and so on
- optional duplicate-transcript mitigation can reduce repeated remote text caused by speaker bleed

This is still not full-session diarization across both local and remote participants.

## How To Enable It

1. Open the main window, then go to `General > Output`
2. Turn on `Meeting Notes (Beta)`
3. Grant the required permissions:
   - microphone
   - accessibility / input monitoring for the hotkey path
   - system audio capture permission

After enabling it:

- the meeting shortcut appears in the main window's `Hotkey` page
- meeting-related permissions appear in the main window's `Permissions` page
- meeting history becomes available in History filters

## Supported ASR Engines

Meeting Notes follows the current global transcription engine.

### Whisper

- Supported
- Uses the current Whisper model
- Uses the existing Whisper `Realtime` setting
  - `Realtime ON`: lower-latency meeting updates
  - `Realtime OFF`: quality-first chunked meeting transcription

### MLX Audio

- Supported
- Uses the current MLX model
- Realtime-capable MLX models use lower-latency meeting updates
- Other MLX models use chunked meeting transcription

### Remote ASR

- Supported
- Uses the currently selected Remote ASR provider and configuration
- Meeting behavior now depends on provider family:
  - OpenAI: existing chunk pseudo-realtime path when enabled
  - Doubao ASR: uses a dedicated `Meeting ASR` model and chunk/file transcription path
  - Aliyun Bailian ASR: uses a dedicated `Meeting ASR` model and async/file transcription path
  - GLM ASR: chunked upload flow

For `Doubao ASR` and `Aliyun Bailian ASR`:

- `Meeting Notes` does not use the provider's live websocket path
- configure `Meeting ASR` separately in the main window under `Model > Remote ASR > [Provider]`
- if the meeting model is missing, meeting start is blocked
- use `Test Meeting ASR` to verify the meeting-specific request path

### Direct Dictation

- Not supported for meetings in the current beta

## Meeting Card

The meeting card is optimized for long-running capture.

- collapsible header-only mode
- pause / resume
- close with secondary confirmation
- per-segment timestamp list
- click to copy a segment
- optional realtime translation for remote speakers
- live detail window

If a meeting already contains transcript content, ending it from a collapsed card will auto-expand first so the confirmation dialog is easier to use.

## Realtime Translation

Meeting realtime translation follows the app's existing translation model/provider settings.

- uses the same translation provider selection as normal translation
- uses the same fallback rules
- uses its own remembered target language for meeting mode
- translates only remote-speaker segments in the current UI

If the selected translation provider cannot be used directly for text translation in meeting mode, Voxt falls back through the normal resolver behavior.

## History, Detail Window, And Export

When a meeting finishes normally:

1. the meeting card closes
2. a `Meeting` history entry is saved
3. the meeting detail window opens automatically

The detail window supports:

- transcript review
- timestamp-based navigation
- translation on existing meeting segments
- export when the current mode allows it

## Notes And Limitations

- Current beta can identify multiple remote speakers on system audio, but it does not diarize the local microphone against every participant
- Meeting mode is isolated from normal transcription / translation / rewrite sessions
- Meeting mode uses a dedicated history type and detail flow
- Cold local-model startup can still take time on first use; Voxt shows model initialization state in the overlay
- Duplicate-transcript mitigation is transcript-level cleanup, not system-level echo cancellation
- For remote providers, Voxt keeps the meeting UI uniform, but transport differs by provider capability:
  - `Doubao` / `Aliyun` meetings use provider-specific chunk/file transcription models
  - other providers stay on their existing chunk-based meeting path

## Manual Validation

Voxt still uses the currently selected ASR engine and model for meeting transcription itself.

- `Whisper`: continues to use the currently selected Whisper model and realtime setting
- `MLX Audio`: continues to use the currently selected MLX model
- `Remote ASR`: continues to use the configured meeting-capable remote provider path

`FluidAudio` is currently used only for remote-speaker attribution on system audio. It does not replace the ASR engine, and it does not perform full-system echo cancellation.

Recommended manual validation flow:

1. Open `General > Output > Meeting Notes`
2. Turn on `Identify multiple remote speakers`
3. Leave `Reduce duplicate transcript from speaker echo` enabled
4. Start a Zoom / Meet / Teams call with speaker output routed to system audio
5. Speak locally through the microphone and ask two remote people to alternate speaking

Expected results:

- your own speech still appears as `Me`
- remote speech may stay as `Them` when only one remote speaker is active
- when diarization has enough evidence for multiple remote speakers, later segments should appear as `Remote 1`, `Remote 2`, and so on
- remote-speaker translation should apply to both `Them` and `Remote n`
- obvious speaker-bleed duplicates should be dropped or trimmed on the remote side

Useful test cases:

- two remote speakers take turns every 5 to 10 seconds
- remote speaker interrupts another remote speaker
- you repeat a sentence locally while the laptop speaker is loud enough to bleed into the mic
- disable diarization and confirm everything falls back to `Me` / `Them`
- disable duplicate mitigation and confirm repeated remote transcript becomes easier to reproduce

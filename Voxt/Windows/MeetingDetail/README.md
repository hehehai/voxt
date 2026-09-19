# Meeting Detail Window

Meeting detail presentation for summaries, transcript views, icons, formatting, styles, and view model state.

## Responsibilities

- Presents saved meeting summaries, transcript sections, speaker metadata, and supporting controls.
- Formats meeting detail content for readable macOS window presentation.
- Keeps meeting-detail view state and styling separate from meeting processing logic.

## Components

- `MeetingDetailWindow`: window manager/controller ownership and AppKit setup.
- `MeetingDetailWindowView`: layout, transcript selection, dialogs and scroll synchronization.
- `MeetingDetailPlaybackController`: player/timer lifetime; still owned by the window view.
- `MeetingDetailPlaybackPane`: playback controls and local zoom/highlight/popover state; scrubbing is bound to the parent.
- `MeetingDetailViewModel`: published state, async operations and mutations.
- `MeetingDetailPresentation`: read-only display/configuration policy, without widening published setters.
- `MeetingTranscriptExporter`: AppKit save-panel integration.
- `MeetingTranscriptComponents`: shared transcript views, including the equatable virtual-list pane.

Verify playback, active-segment scrolling, search/editing and speaker presentation on macOS after UI extraction; source comparisons do not establish view-identity or accessibility correctness.

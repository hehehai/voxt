# Hotkey

Global hotkey capture, interpretation, recording UI, action resolution, and runtime configuration.

## Responsibilities

- Registers and manages global shortcuts used to start recording and trigger app actions.
- Normalizes modifier keys, key events, recorder UI state, and user-facing hotkey labels.
- Resolves hotkey actions against app settings and runtime availability.

## Ownership

`HotkeyEventTapInstallation` owns one tap, source, callback context and dedicated `HotkeyEventTapRunLoop`. The manager detaches old installations under its routing lock and stops them outside the lock, so retirement cannot stop a replacement thread. The callback context weakly references the manager; source removal retains the context through callback-thread cleanup.

Queued events/recovery and main-queue actions carry generation checks. Application callbacks run outside the state lock. `HotkeyBusinessState` pairs the six fields for each shortcut business instead of maintaining parallel scalar state; routing priorities and gesture rules are unchanged.

The run-loop tests use ordinary CF sources without installing global taps or requesting permissions. Real permission recovery and sleep/wake acceptance remain required.

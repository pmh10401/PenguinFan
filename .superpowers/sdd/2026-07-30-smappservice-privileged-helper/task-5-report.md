# Task 5 Report

Status: DONE

## Implementation

- Added Korean UI-facing privileged service status labels and action availability.
- Added approval-settings action only for approval-pending state.
- Added confirmed helper removal flow that invalidates stale mode generations and delegates to `PrivilegedServiceManager.unregister()`, whose contract restores System mode and disconnects before unregistering.
- Added diagnostics-only legacy `osascript` fallback toggle, default OFF, and wired runtime fallback selection to that explicit model setting.
- Added an explanation that the authorization dialog may display `osascript`.
- Added no password, credential, socket-path, or raw authorization-record input, storage, or display.
- Preserved stable application identifiers and packaging artifacts.

## Focused tests

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter Task5
```

Result: PASS. 4 tests executed, 0 failures.

Covered:

- service status labels and action visibility
- legacy fallback default OFF and explicit opt-in
- confirmation requirement and restore/disconnect-before-unregister ordering
- stale mode generation invalidation during helper removal

## Release build

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Result: PASS. Release product build completed successfully.

## Fix round 1/5

Addressed both Important review findings:

- Production helper removal now requires a throwing, acknowledged `restoreSystemAuto` response before heartbeat cancellation, shutdown/disconnect, and unregister.
- Restore rejection, timeout, or other preparation failure aborts unregister, refreshes and preserves the real registered service state, leaves the existing control state available for retry, and presents an actionable non-removal diagnostic.
- Removal is an explicit generation-safe state. Curve and Manual requests are blocked in the menu UI, `AppModel.selectMode`, runtime request dispatch, approval flow, and coordinator creation while removal is in progress.
- Pre-existing in-flight requests are invalidated by the removal generation and cannot reactivate custom control after removal.
- Legacy fallback remains explicit, default OFF, and no password handling was added.

Focused test command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter Task5
```

Result: PASS. 6 tests executed, 0 failures.

Focused coverage added:

- verified restore/disconnect occurs before unregister
- restore failure aborts unregister and keeps service registered/usable
- concurrent Curve/Manual selection is blocked during suspended removal
- stale in-flight custom request cannot reactivate control after removal

Release build command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Result: PASS. Release product build completed successfully.

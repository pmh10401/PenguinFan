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

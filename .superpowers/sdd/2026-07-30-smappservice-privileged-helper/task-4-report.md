# Task 4 Report: First-Control Approval Flow

## Scope

- Added pending privileged-mode state to `AppModel`.
- Kept System mode and read-only monitoring free of service registration.
- Added explicit PenguinFan approval, cancellation, and System Settings actions.
- Connected `RuntimeController` to `PrivilegedServiceManager`.
- Made privileged XPC the default control transport.
- Kept `AuthorizationLauncher` reachable only through an injected, explicit
  legacy-fallback opt-in that defaults to `false`.
- Preserved heartbeat, termination, sleep/wake, stale-sensor, and System-mode
  restoration paths.
- Added actionable Korean read-only recovery messages.
- Added no password storage or collection.

## TDD RED

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter PrivilegedServiceManagerTests
```

Result: failed as expected because the new pending-mode, approval-state,
confirmation/cancellation APIs, and `RuntimeController` service-manager
injection did not exist.

## Focused Tests

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter PrivilegedServiceManagerTests
```

First GREEN attempt: production sources compiled; the new test fixture used an
incorrect existing `HardwareCapabilities` argument label. The fixture was
corrected from `temperatureKeys` to `ftstAvailable`.

Final result:

```text
Executed 19 tests, with 0 failures (0 unexpected).
Test Suite 'Selected tests' passed.
```

## Release Build

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Result:

```text
Build of product 'FanControllerApp' complete! (2.98s)
```

## Safety Notes

- Selecting Curve or Manual while the service is not enabled only records the
  pending mode and presents the PenguinFan explanation.
- Registration starts only from the explicit `계속` action.
- Cancellation and registration/XPC failure leave settings in System mode.
- Approval-required state retains the pending mode and exposes
  `시스템 설정 열기`.
- No default-path call to `osascript` remains; the legacy launcher requires an
  explicit injected opt-in.
- Stable identifiers and packaging artifacts were not changed.

## Commit

This report is committed with the Task 4 source and test changes.

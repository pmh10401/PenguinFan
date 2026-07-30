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

## Fix Round 1/5: Stale Mode Request Ordering

### Finding

An older asynchronous Curve or Manual readiness request could complete after a
newer mode selection and overwrite the user's latest safe System choice or
newer custom mode. An old failure could also replace a newer status.

### TDD RED

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter PrivilegedServiceManagerTests
```

First result: test compilation failed because Swift 6 disallows
`DispatchSemaphore.wait` directly from an asynchronous context. The test helper
was corrected to perform the bounded wait on a synchronous Dispatch queue and
resume through a continuation.

The same command was run again.

Behavioral RED result:

```text
Executed 22 tests, with 5 failures (0 unexpected).
```

The three new regression scenarios failed as expected:

- An in-flight Curve readiness completion changed newer System state to Curve
  and connected.
- Out-of-order repeated Curve/Manual readiness left Curve active instead of
  the latest Manual request.
- A stale rejected readiness response changed newer System state to failed and
  replaced its diagnostic status.

### Implementation

- Added a monotonically increasing mode-request generation to `AppModel`.
- Bound pending privileged modes and explicit confirmations to their generation.
- Checked request freshness after service registration, XPC status readiness,
  coordinator updates, fan application, and error completion.
- Prevented stale readiness from attaching a coordinator, starting heartbeat,
  clearing pending state, applying a mode, or publishing failure.
- Restarted heartbeat with the generation of the latest successfully applied
  custom mode.
- Kept explicit confirmation and the default no-`osascript` path unchanged.

### Focused Tests

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter PrivilegedServiceManagerTests
```

Final result:

```text
Executed 22 tests, with 0 failures (0 unexpected).
Test Suite 'Selected tests' passed.
```

### Release Build

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Result:

```text
Build of product 'FanControllerApp' complete! (2.88s)
```

## Fix Round 2/5: Connection-Scoped Failure Events

### Finding

The request-generation guard did not identify the XPC connection that emitted
an interruption or invalidation. A callback from an old connection could
therefore be interpreted as a failure of the current connection and overwrite
a newer System or custom-control status.

### TDD RED

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter PrivilegedServiceManagerTests
```

Result: test compilation failed as expected because
`makeControlClient(connectionFailureHandler:)` did not exist. The manager could
only use one shared failure callback and could not bind events to individual
connections.

### Implementation

- Added a per-client failure-handler override to
  `PrivilegedServiceManager.makeControlClient`.
- Assigned a UUID to every Runtime-created control connection.
- Accepted interruption/invalidation callbacks only when their UUID matches the
  currently active connection.
- Deactivated the active connection identity and heartbeat before restoring
  System mode.
- Retained the coordinator connection identity so a later explicit custom-mode
  request can safely reactivate the retained connection.
- Cleared active and retained connection identities during failure and shutdown.
- Kept request-generation checks, watchdog behavior, explicit confirmation,
  and the default no-`osascript` path unchanged.

### Focused Tests

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter PrivilegedServiceManagerTests
```

First GREEN attempt:

```text
Executed 25 tests, with 1 failure (0 unexpected).
```

The runtime race tests passed. The connection-callback unit test released both
clients before manually firing the weak invalidation callback, so it observed
no callback. The test was corrected to retain both client lifetimes.

The same command was run again.

Final result:

```text
Executed 25 tests, with 0 failures (0 unexpected).
Test Suite 'Selected tests' passed.
```

The focused suite now deterministically covers:

- old connection invalidation after a newer System selection
- old connection invalidation after a newer successful Manual request
- per-client failure callbacks remaining isolated

### Release Build

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Result:

```text
Build of product 'FanControllerApp' complete! (2.87s)
```

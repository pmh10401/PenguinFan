# Task 3 Report: Service Registration State and XPC Control Client

## Status

Complete.

## Implementation

- Added `PrivilegedServiceState` with all brief-required states.
- Added exhaustive mapping for the known macOS 13 `SMAppService.Status`
  cases and an `@unknown default` failure state.
- Added injectable service registration, runtime restore/disconnect,
  approval-settings opener, and XPC connection factory boundaries.
- Added `register()`, `unregister()`, `refreshStatus()`,
  `openApprovalSettings()`, and `makeControlClient()`.
- Added the real daemon registration default using
  `SMAppService.daemon(plistName:)`.
- Added the real privileged connection using Mach service
  `com.local.PenguinFan.experimental.agent` and `.privileged`.
- Added request encoding/response decoding through the reviewed
  `XPCMessageAdapter` and `FanControllerXPCProtocol`.

## TDD and Verification Commands

1. Initial RED command:

   `swift test --filter PrivilegedServiceManagerTests`

   Result: exit 1 before the Task 3 tests compiled because the active
   command-line toolchain could not import `XCTest`.

2. Xcode-backed RED command:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests`

   Result: exit 1 with the expected missing Task 3 types, including
   `PrivilegedServiceManager`, `PrivilegedServiceState`,
   `XPCControlClient`, and the injected protocols. One test-double
   callback shadowing typo was also identified and corrected.

3. Clean RED rerun:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests`

   Result: exit 1 exclusively because the Task 3 production types were
   absent.

4. Focused GREEN command:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests`

   Result: exit 0. Executed 11 tests with 0 failures and 0 unexpected
   failures in 0.014 seconds.

5. Release application build:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product FanControllerApp`

   Result: exit 0. `FanControllerApp` production build completed in
   3.29 seconds.

6. Scoped review:

   `git diff --check -- Sources/FanControllerApp/PrivilegedServiceManager.swift Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`

   Result: exit 0 with no whitespace errors.

   `git diff --no-index -- /dev/null Sources/FanControllerApp/PrivilegedServiceManager.swift`

   `git diff --no-index -- /dev/null Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`

   Result: reviewed both complete new-file diffs; no blocking findings.

7. Commit:

   `git add -- Sources/FanControllerApp/PrivilegedServiceManager.swift Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`

   `git diff --cached --check`

   `git commit -m 'Implement privileged service management'`

   Result: commit `a61df3e` created with exactly the two Task 3 brief
   files, 699 insertions, and no unrelated staged files.

## Concurrency Decisions

- `PrivilegedServiceManager` is `@MainActor` isolated so registration
  state and synchronous `SMAppService` operations have one UI-facing
  executor.
- Every XPC request is keyed by its request UUID in a dictionary guarded
  by `NSLock`.
- Reply, timeout, transport error, interruption, and invalidation all
  remove the pending continuation while holding the lock, then resume it
  after releasing the lock. Only the first event obtains the
  continuation; later events become no-ops and cannot resume it twice.
- Interruption and invalidation atomically establish a terminal
  connection failure, drain all pending requests, and invoke the
  injected runtime-recovery callback once.
- A failed connection rejects later sends immediately rather than
  creating requests that can hang.
- Unregistration awaits the injected System-mode restore and disconnect
  operation before calling the service registration dependency.

## Files

- `Sources/FanControllerApp/PrivilegedServiceManager.swift`
- `Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`
- `.superpowers/sdd/2026-07-30-smappservice-privileged-helper/task-3-report.md`

## Commit

`a61df3e` (`Implement privileged service management`)

The report is intentionally outside that commit so it can contain the
exact immutable commit hash while the commit remains limited to the two
brief files.

## Concerns

- Tests use injected fakes and did not register, unregister, open
  settings, or contact the privileged daemon on this Mac, as required.
  Real signing, bundle embedding, SMAppService approval, and live Mach
  service connectivity remain integration validation for a later task.
- Swift test commands on this machine require the full Xcode
  `DEVELOPER_DIR`; the default command-line toolchain lacks `XCTest`.

## Fix Round 1: Timeout Drains Every Pending Request

### Status

Complete. Timeout is now a terminal connection failure only while its
originating request is pending. It atomically drains all pending
continuations, invalidates the connection once, and requests runtime
recovery once. Late replies, invalidation callbacks, second timers, and
timers for already completed requests cannot resume or drain again.

### TDD and Verification Commands

1. Concurrent regression RED:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests`

   Result: exit 1. The new deterministic two-request test could not
   compile because `XPCRequestTimeoutScheduling` and the
   `timeoutScheduler` initializer argument did not exist. This was the
   expected missing-production-seam failure.

2. First focused GREEN attempt:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests`

   Result: exit 1. Production compiled, but XCTest rejected
   `await task.value` inside its non-concurrent assertion autoclosure.
   Binding both task values before assertion corrected the test syntax.

3. Concurrent regression GREEN:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests`

   Result: exit 0. Executed 12 tests with 0 failures and 0 unexpected
   failures in 0.018 seconds. The two held requests both failed with
   `.timedOut`; connection invalidation and recovery each occurred once;
   both late replies and the remaining timer were ignored.

4. Stale-timer regression RED preparation:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests/testTimeoutForCompletedRequestDoesNotBreakConnection`

   First result: exit 1 because XCTest rejected an async call inside its
   assertion autoclosure. Binding the result corrected the test syntax.

5. Stale-timer valid RED:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests/testTimeoutForCompletedRequestDoesNotBreakConnection`

   Result: exit 1. Executed 1 test with 2 failures: invalidation count
   was 1 instead of 0 and recovery count was 1 instead of 0. This proved
   a completed request's scheduled timer could incorrectly break a
   healthy connection.

6. Final focused Task 3 tests:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests`

   Result: exit 0. Build completed in 1.70 seconds. Executed 13 tests
   with 0 failures and 0 unexpected failures in 0.018 seconds.

7. Final release application build:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product FanControllerApp`

   Result: exit 0. `FanControllerApp` production build completed in
   2.78 seconds.

8. Scoped commit:

   `git add -- Sources/FanControllerApp/PrivilegedServiceManager.swift Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`

   `git diff --cached --check`

   `git commit -m 'Fail all XPC requests on timeout'`

   Result: commit `918adf5` created with exactly the two Task 3 files,
   207 insertions, 16 deletions, and no unrelated staged files.

### Deterministic Regression Test

`Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`

- `testOneTimeoutDrainsAllPendingRequestsAndIgnoresLateEvents`
- `testTimeoutForCompletedRequestDoesNotBreakConnection`

The first test starts two detached pending sends, waits for both requests
and both timeout operations to be registered, manually fires only one
timeout, and then delivers all late replies and the remaining timer. The
second test proves a timer cannot terminate the connection after its own
request has already completed.

### Concurrency Decisions

- The timeout scheduler is injected, allowing deterministic tests with no
  wall-clock race.
- A timeout passes its request UUID into `failConnection`.
- Under one `NSLock` acquisition, `failConnection` verifies that the
  originating request remains pending, establishes terminal failure,
  snapshots every continuation, and clears the pending dictionary.
- Connection invalidation occurs only after terminal state and the empty
  pending dictionary are visible, so synchronous or asynchronous
  invalidation callbacks cannot drain or resume again.
- Continuations are resumed outside the lock, exactly once.
- Timers belonging to completed requests return without invalidation or
  recovery.

### Files Changed

- `Sources/FanControllerApp/PrivilegedServiceManager.swift`
- `Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`
- `.superpowers/sdd/2026-07-30-smappservice-privileged-helper/task-3-report.md`

### Commit

`918adf5` (`Fail all XPC requests on timeout`)

The report remains outside the implementation commit so it can record
the exact immutable commit hash while the commit stays limited to the
two Task 3 brief files.

### Concerns

- No live privileged daemon or `SMAppService` registration was exercised;
  tests used injected connections and timeout scheduling.
- The report is intentionally not part of commit `918adf5`.

## Fix Round 2: Bounded Concurrent Regression Test

### Status

Complete. The two-request timeout regression no longer awaits unfinished
tasks without a bound. It uses an independent one-second XCTest waiter,
invalidates the fake connection when that waiter does not complete, and
only then awaits both tasks for safe continuation cleanup. Assertions
still require both production results to be `.timedOut`.

### Mutation Proof Against the Original Bug

The production timeout callback was temporarily changed back to the
original one-request-only completion behavior solely for this mutation
run:

`/usr/bin/time -p env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests/testOneTimeoutDrainsAllPendingRequestsAndIgnoresLateEvents`

Result: exit 1 without hanging. Build completed in 1.76 seconds. The test
finished in 1.140 seconds with exactly 2 assertion failures:

- The bounded waiter returned `XCTWaiterResult(rawValue: 2)` instead of
  `.completed`.
- The cleanup-released second request returned `.invalidated` instead of
  the required `.timedOut`.

Process timing was:

```text
real 4.13
user 2.75
sys 0.75
```

The production drain-all timeout implementation was restored immediately
after this bounded RED proof.

### Final Verification Commands

1. Focused Task 3 tests:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrivilegedServiceManagerTests`

   Result: exit 0. Build completed in 1.63 seconds. Executed 13 tests
   with 0 failures and 0 unexpected failures in 0.017 seconds.

2. Release application build:

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product FanControllerApp`

   Result: exit 0. `FanControllerApp` production build completed in
   2.18 seconds.

3. Scoped review:

   `git diff --name-only -- Sources/FanControllerApp/PrivilegedServiceManager.swift Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`

   Result: only
   `Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`
   changed; the temporary production mutation was fully restored.

   `git diff --check -- Sources/FanControllerApp/PrivilegedServiceManager.swift Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`

   Result: exit 0 with no whitespace errors.

4. Test fix commit:

   `git add -- Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`

   `git diff --cached --check`

   `git commit -m 'Bound the concurrent timeout regression test'`

   Result: commit `ce58b84` created with exactly the Task 3 test file,
   18 insertions, and no unrelated staged files.

### Safe Cleanup Ordering

1. Both detached sends cross the existing request-received and
   timeout-scheduled barriers.
2. The first timeout operation is fired manually.
3. An independent XCTest waiter allows at most one second for both task
   completion expectations.
4. If the waiter expires, the fake connection is invalidated before
   either task value is awaited, draining any surviving continuation.
5. Both task values are then awaited safely.
6. The waiter must be `.completed`, and both errors must still be
   `.timedOut`; cleanup cannot make the production assertion pass.
7. Late replies and the remaining timer are delivered only after task
   cleanup.

### Files Changed

- `Tests/FanControllerAppTests/PrivilegedServiceManagerTests.swift`
- `.superpowers/sdd/2026-07-30-smappservice-privileged-helper/task-3-report.md`

### Commit

`ce58b84` (`Bound the concurrent timeout regression test`)

### Concerns

- The one-second bound is intentionally much larger than the
  deterministic in-memory completion path while still guaranteeing
  finite failure under the original bug.
- No live privileged daemon or `SMAppService` operation was exercised.

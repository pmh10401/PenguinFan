# Task 7 Report: Safety and Local Runtime Validation

## Scope and safety boundary

Validation was performed on 2026-07-30 on:

- macOS 26.5.2 (25F84), arm64
- local user UID 501
- experimental package:
  `installer/PenguinFan-Experimental-1.1.0.pkg`

No password was requested, entered, logged, or stored. The stable
`/Applications/PenguinFan.app` was not stopped, modified, or replaced. No SMC
write was attempted.

The runtime portion stopped at the exact administrator boundary because
credentialless installation was unavailable:

```text
installer: Must be run as root to install this package.
UNPRIVILEGED_INSTALL_EXIT=1
```

This is a validation blocker, not an application test failure.

## Summary

### PASS

- Stable PenguinFan 1.0.12 (build 13) existed before validation.
- Stable app deep/strict signature validation passed before and after the build.
- Stable `FanControllerApp` and its existing legacy `FanControllerAgent`
  remained running.
- No experimental app or experimental LaunchDaemon existed before validation.
- No `osascript` process existed in the final process snapshot.
- All 93 Swift tests passed with the Xcode toolchain.
- The isolated experimental package rebuilt successfully.
- The rebuilt package SHA-256 was
  `c194a89b58d354591d1d7e6feda1e95b4fe7d47a2cd0246f9e86406cbc66c275`.
- The stable app remained version 1.0.12 (build 13) after the package build.

### FAIL

- None. Runtime assertions that could not be exercised are marked BLOCKED rather
  than inferred.

### BLOCKED

- Install through macOS Installer.
- Installed experimental app identity, version, signature, and embedded daemon
  plist validation.
- Experimental app launch and UI inspection.
- System-mode launch without service registration.
- Curve/Manual explanation and approval flow.
- SMAppService approval/status and privileged XPC connection.
- Process-count validation while experimental control is active.
- Curve/Manual SMC writes and measured RPM response.
- System restoration, watchdog restoration, sleep/wake, and safe unregister.
- Unrelated local XPC client rejection.

All blocked items depend on installing the isolated app first. The instructions
prohibited credential prompts and `osascript` improvisation, so no attempt was
made to bypass this boundary.

## Evidence

### 1. Stable baseline

Command:

```bash
/usr/bin/sw_vers
/usr/bin/uname -m
/usr/bin/id
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  '/Applications/PenguinFan.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  '/Applications/PenguinFan.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  '/Applications/PenguinFan.app/Contents/Info.plist'
/usr/bin/codesign --verify --deep --strict --verbose=2 \
  '/Applications/PenguinFan.app'
/bin/launchctl print system/com.local.PenguinFan.experimental.agent
/usr/bin/sudo -n true
```

Result:

```text
ProductVersion: 26.5.2
BuildVersion: 25F84
arm64
uid=501(mac) ... groups include admin
STABLE_APP_EXISTS=yes
com.local.M2MaxFanController
1.0.12
13
/Applications/PenguinFan.app: valid on disk
/Applications/PenguinFan.app: satisfies its Designated Requirement
EXPERIMENTAL_APP_EXISTS_BEFORE=no
Could not find service "com.local.PenguinFan.experimental.agent" in domain for system
SUDO_NONINTERACTIVE=no
```

Baseline process evidence:

```text
97073 /Applications/PenguinFan.app/Contents/MacOS/FanControllerApp
97209 /Applications/PenguinFan.app/Contents/Helpers/FanControllerAgent \
  --socket ... --owner-uid 501
```

The socket value is intentionally omitted from this report. It was not used.

### 2. Full test suite

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test
```

Result:

```text
Test Suite 'All tests' passed
Executed 93 tests, with 0 failures (0 unexpected)
FULL_TEST_EXIT=0
```

The suite included agent watchdog, SMC writer, safety state machine, XPC
message, XPC client validation, privileged service state, approval flow,
concurrency, timeout, and safe unregister tests.

### 3. Experimental package rebuild

Command:

```bash
./script/build_installer.sh --experimental-helper
/usr/bin/shasum -a 256 installer/PenguinFan-Experimental-1.1.0.pkg
```

Result:

```text
Build of product 'FanControllerApp' complete
Build of product 'FanControllerAgent' complete
Build of product 'FanDiagnostics' complete
Validated experimental package: .../PenguinFan-Experimental-1.1.0.pkg
Built installer: .../installer/PenguinFan-Experimental-1.1.0.pkg
PACKAGE_BUILD_EXIT=0
c194a89b58d354591d1d7e6feda1e95b4fe7d47a2cd0246f9e86406cbc66c275
```

### 4. Administrator installation boundary

Credentialless capability probe:

```bash
/usr/bin/sudo -n true
```

Result:

```text
SUDO_NONINTERACTIVE=no
```

Noninteractive Installer boundary confirmation:

```bash
/usr/sbin/installer \
  -pkg "$PWD/installer/PenguinFan-Experimental-1.1.0.pkg" \
  -target /
```

Result:

```text
installer: Must be run as root to install this package.
UNPRIVILEGED_INSTALL_EXIT=1
```

No GUI Installer, authorization dialog, AppleScript, `osascript`, or password
entry was invoked.

### 5. Stable post-build state

Commands:

```bash
/bin/ls -ld \
  '/Applications/PenguinFan.app' \
  '/Applications/PenguinFan Experimental.app'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  '/Applications/PenguinFan.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  '/Applications/PenguinFan.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  '/Applications/PenguinFan.app/Contents/Info.plist'
/usr/bin/codesign --verify --deep --strict --verbose=2 \
  '/Applications/PenguinFan.app'
/usr/bin/pgrep -x FanControllerApp
/usr/bin/pgrep -x FanControllerAgent
/usr/bin/pgrep -x osascript
/bin/launchctl print system/com.local.PenguinFan.experimental.agent
```

Result:

```text
/Applications/PenguinFan Experimental.app: No such file or directory
/Applications/PenguinFan.app exists
com.local.M2MaxFanController
1.0.12
13
/Applications/PenguinFan.app: valid on disk
/Applications/PenguinFan.app: satisfies its Designated Requirement
FanControllerApp PID 97073, stable application path
FanControllerAgent PID 97209, stable helper path
osascript PIDS=none
Could not find service "com.local.PenguinFan.experimental.agent" in domain for system
```

Package receipts remained limited to the existing stable/legacy receipts:

```text
com.local.M2MaxFanController
com.local.fancontroller
```

## Validation matrix

| Item | Status | Evidence |
| --- | --- | --- |
| Full Xcode-toolchain tests | PASS | 93 tests, 0 failures |
| Experimental package build | PASS | Exit 0 and SHA-256 recorded |
| Install through macOS Installer | BLOCKED | Installer requires root; no credentialless privilege |
| Stable 1.0.12 remains installed/runnable | PASS | Version/signature/process verified after build |
| Installed app identity/version/signature/plist | BLOCKED | Experimental app not installed |
| System mode starts without daemon registration | BLOCKED | Pre-install daemon absence verified; experimental launch unavailable |
| Curve explanation appears first | BLOCKED | Experimental UI unavailable |
| Approval without `osascript` | BLOCKED | Registration path unavailable; final `osascript` count was zero |
| SMAppService status and XPC | BLOCKED | Service not installed or registered |
| Only UI plus experimental agent run | BLOCKED | Experimental process unavailable |
| Curve and Manual RPM response | BLOCKED | No safe verified helper/SMC path; no writes attempted |
| Return to System restores ownership | BLOCKED | No experimental control session |
| UI termination triggers watchdog restore | BLOCKED | No experimental control session |
| Sleep and wake recovery | BLOCKED | No experimental control session |
| Settings removal unregisters service | BLOCKED | Service not installed |
| Unrelated XPC client is rejected | BLOCKED | Mach service unavailable |

## Defects

No code defect was demonstrated in the portion that could be executed. Runtime
correctness remains unverified because installation required administrator
authorization.

## Required continuation boundary

Task 7 can continue only after the user installs
`PenguinFan-Experimental-1.1.0.pkg` through macOS Installer and completes the
normal macOS administrator authorization themselves. Subsequent validation must
begin by rechecking the stable process baseline and installed experimental
bundle before launching it.

---

## Resumed validation after administrator installation

The user completed installation through the macOS Installer UI. Validation
resumed at 2026-07-30 14:04 KST without requesting or handling credentials.

### Resumed PASS

- `/Applications/PenguinFan Experimental.app` exists and is owned by
  `root:wheel`.
- Installed identity is `com.local.PenguinFan.experimental`.
- Installed display name is `PenguinFan Experimental`.
- Installed version is `1.1.0` and build is `14`.
- Deep/strict signature verification passed for the installed experimental app.
- Main and helper executables exist and are executable.
- The embedded LaunchDaemon plist exists and passes `plutil -lint`.
- Embedded service values match the experimental contract.
- Stable PenguinFan remains `com.local.M2MaxFanController`, version 1.0.12,
  build 13, with a valid deep/strict signature.
- Stable app and stable legacy agent remained running throughout this resumed
  validation.
- Experimental app launch succeeded and produced one additional
  `FanControllerApp` process.
- System-mode launch did not register or launch the experimental daemon.
- No `osascript` process was present before or after experimental launch.

### Resumed FAIL

- None demonstrated.

### Resumed BLOCKED

- Curve/Manual selection and the PenguinFan explanation sheet.
- User approval of the experimental LaunchDaemon.
- SMAppService enabled state and privileged XPC readiness.
- Experimental helper process count while custom control is active.
- Bounded Curve/Manual write and measured RPM response.
- System restoration after custom control.
- Watchdog, sleep/wake, safe unregister, and unrelated-client rejection.

The blocker is UI accessibility, not administrator credentials. The installed
app is an `LSUIElement` menu-bar application with no window. Computer Use could
not attach to either the experimental bundle identifier or its executable and
therefore could not safely identify or click its status item. Coordinate
guessing was not used because it could activate the stable app or another
menu-bar item.

The next observable boundary is a user click on the experimental PenguinFan
menu-bar icon followed by selecting Curve. The validator can then inspect the
explanation/approval UI and continue without entering credentials.

## Resumed evidence

### Installed experimental bundle

Commands:

```bash
/bin/ls -ld '/Applications/PenguinFan Experimental.app'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  '/Applications/PenguinFan Experimental.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' \
  '/Applications/PenguinFan Experimental.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  '/Applications/PenguinFan Experimental.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  '/Applications/PenguinFan Experimental.app/Contents/Info.plist'
/usr/bin/codesign --verify --deep --strict --verbose=2 \
  '/Applications/PenguinFan Experimental.app'
/bin/ls -l \
  '/Applications/PenguinFan Experimental.app/Contents/MacOS/FanControllerApp' \
  '/Applications/PenguinFan Experimental.app/Contents/Helpers/FanControllerAgent' \
  '/Applications/PenguinFan Experimental.app/Contents/Library/LaunchDaemons/com.local.PenguinFan.experimental.agent.plist'
/usr/bin/plutil -lint \
  '/Applications/PenguinFan Experimental.app/Contents/Library/LaunchDaemons/com.local.PenguinFan.experimental.agent.plist'
```

Observed:

```text
drwxr-xr-x root wheel /Applications/PenguinFan Experimental.app
com.local.PenguinFan.experimental
PenguinFan Experimental
1.1.0
14
/Applications/PenguinFan Experimental.app: valid on disk
/Applications/PenguinFan Experimental.app: satisfies its Designated Requirement
FanControllerApp executable exists, root:wheel, mode 0755
FanControllerAgent executable exists, root:wheel, mode 0755
embedded LaunchDaemon plist exists, root:wheel, mode 0644
embedded LaunchDaemon plist: OK
```

Embedded plist values:

```text
Label = com.local.PenguinFan.experimental.agent
BundleProgram = Contents/Helpers/FanControllerAgent
ProcessType = Interactive
MachServices:com.local.PenguinFan.experimental.agent = true
```

Package receipt evidence:

```text
com.local.M2MaxFanController
com.local.PenguinFan.experimental
com.local.fancontroller
```

### Stable baseline after experimental installation

Commands:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  '/Applications/PenguinFan.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  '/Applications/PenguinFan.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  '/Applications/PenguinFan.app/Contents/Info.plist'
/usr/bin/codesign --verify --deep --strict --verbose=2 \
  '/Applications/PenguinFan.app'
/usr/bin/pgrep -x FanControllerApp
/usr/bin/pgrep -x FanControllerAgent
```

Observed:

```text
com.local.M2MaxFanController
1.0.12
13
/Applications/PenguinFan.app: valid on disk
/Applications/PenguinFan.app: satisfies its Designated Requirement
stable FanControllerApp PID 97073
stable legacy FanControllerAgent PID 97209
```

### System-mode experimental launch

Command:

```bash
/usr/bin/open -n '/Applications/PenguinFan Experimental.app'
/bin/sleep 3
/usr/bin/pgrep -x FanControllerApp
/usr/bin/pgrep -x FanControllerAgent
/usr/bin/pgrep -x osascript
/bin/launchctl print system/com.local.PenguinFan.experimental.agent
```

Observed:

```text
experimental FanControllerApp PID 44588, UID 501
stable FanControllerApp PID 97073, UID 501
stable legacy FanControllerAgent PID 97209, UID 0
no experimental FanControllerAgent process
osascript PIDS=none
Could not find service "com.local.PenguinFan.experimental.agent" in domain for system
```

This proves the installed experimental app can launch read-only in System mode
without registering the privileged service. It does not prove the later
approval or control path.

### GUI automation boundary

Read-only Computer Use attempts:

```text
target com.local.PenguinFan.experimental:
Computer Use server error -10005: timeoutReached

target /Applications/PenguinFan Experimental.app:
Computer Use is not active for the app

target FanControllerApp:
Invalid app: FanControllerApp
```

No menu-bar coordinate click, AppleScript, `osascript`, password input, service
registration, or SMC write was attempted.

## Resumed status

Task 7 is not fully complete. Installation and System-mode isolation are now
validated. The exact remaining interaction is for the user to open the
experimental PenguinFan menu-bar item and select Curve so the approval flow
becomes observable.

---

## Focused UX defect fix: visible launch and reopen

Validation date: 2026-07-30 KST.

Root cause: the accessory-only app had no Dock icon or window, and reopening the
running application did not explicitly present its status-item popover. The fix
adds a testable presentation coordinator, presents once after status-item setup
on initial launch, and presents again from
`applicationShouldHandleReopen`. Ordinary status-item clicks retain their
existing toggle behavior. No timer callback requests presentation.

Changed production behavior is limited to the menu-bar app delegate. No app was
installed, the stable app was not modified, and marketing files were untouched.

### Focused regression tests

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter PopoverPresentationCoordinatorTests
```

Result:

```text
Test Suite 'M2MaxFanControllerPackageTests.xctest' passed at 2026-07-30 14:13:16.551.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'Selected tests' passed at 2026-07-30 14:13:16.551.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
◇ Test run started.
↳ Testing Library Version: 1902
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
FOCUSED_TEST_EXIT=0
```

The two tests verify that initial launch presents exactly once and every reopen
requests presentation again without live GUI automation.

### Release app build

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Result:

```text
[1/3] Write swift-version--58304C5D6DBC2206.txt
[3/4] Compiling FanControllerApp AppModel.swift
[3/5] Write Objects.LinkFileList
[4/5] Linking FanControllerApp
Build of product 'FanControllerApp' complete! (3.28s)
RELEASE_BUILD_EXIT=0
```

### Transactional experimental package regeneration

Command:

```bash
./script/build_installer.sh --experimental-helper
/usr/bin/shasum -a 256 installer/PenguinFan-Experimental-1.1.0.pkg
```

Result:

```text
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.5VWT0t/dist-1.1.0/PenguinFan Experimental.app/Contents/MacOS/FanControllerApp: replacing existing signature
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.5VWT0t/dist-1.1.0/PenguinFan Experimental.app: replacing existing signature
Built: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.5VWT0t/dist-1.1.0/PenguinFan Experimental.app
pkgbuild: Inferring bundle components from contents of /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.5VWT0t/installer-root
pkgbuild: Adding component at Applications/PenguinFan Experimental.app
pkgbuild: Wrote package to /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.5VWT0t/PenguinFan-Experimental-1.1.0.pkg
Validated experimental package: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.5VWT0t/PenguinFan-Experimental-1.1.0.pkg
Built installer: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/PenguinFan-Experimental-1.1.0.pkg
62d58a5d1f80560b162bd7110619a921e33a35cff46ac429391a054bd5bd0096  installer/PenguinFan-Experimental-1.1.0.pkg
PACKAGE_BUILD_EXIT=0
```

Artifact SHA-256: `62d58a5d1f80560b162bd7110619a921e33a35cff46ac429391a054bd5bd0096`.

---

## Runtime defect fix round 1: register from notFound

Validation date: 2026-07-30 KST.

Root cause evidence showed the installed daemon plist and helper were present,
the signatures verified, and the daemon name matched, while
`SMAppService.status` returned `.notFound`. The manager previously accepted
only `.notRegistered`, so an explicit user-confirmed attempt returned before
calling the official registration API.

The focused fix permits only `.notRegistered` and `.notFound` to enter
`.registering`, invokes `service.register()` once, refreshes the official
status after success, and records the thrown localized macOS error as
`.failed(...)`. Registering, failed, enabled, and approval-pending states remain
protected from duplicate registration. No fallback is enabled or invoked, and
System mode remains the fail-closed state. Diagnostics now describe
`.notFound` as a status lookup requiring an official registration attempt,
rather than asserting the embedded service is absent.

No app was installed, the stable app was not modified, and marketing files were
untouched.

### Focused registration tests

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter PrivilegedServiceManagerTests
```

Result:

```text
Test Suite 'M2MaxFanControllerPackageTests.xctest' passed at 2026-07-30 14:22:58.777.
	 Executed 38 tests, with 0 failures (0 unexpected) in 0.040 (0.042) seconds
Test Suite 'Selected tests' passed at 2026-07-30 14:22:58.777.
	 Executed 38 tests, with 0 failures (0 unexpected) in 0.040 (0.043) seconds
◇ Test run started.
↳ Testing Library Version: 1902
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
FOCUSED_TEST_EXIT=0
```

Coverage includes registration from `.notFound`, thrown-error capture,
refresh to `.requiresApproval` and `.enabled`, and duplicate suppression
while `.registering` or `.failed`.

### Release app build

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Result:

```text
[1/3] Write swift-version--58304C5D6DBC2206.txt
[3/4] Compiling FanControllerApp AppModel.swift
[3/5] Write Objects.LinkFileList
[4/5] Linking FanControllerApp
Build of product 'FanControllerApp' complete! (3.24s)
RELEASE_BUILD_EXIT=0
```

### Transactional experimental package regeneration

Command:

```bash
./script/build_installer.sh --experimental-helper
/usr/bin/shasum -a 256 installer/PenguinFan-Experimental-1.1.0.pkg
```

Result:

```text
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.0y2FVz/dist-1.1.0/PenguinFan Experimental.app/Contents/MacOS/FanControllerApp: replacing existing signature
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.0y2FVz/dist-1.1.0/PenguinFan Experimental.app: replacing existing signature
Built: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.0y2FVz/dist-1.1.0/PenguinFan Experimental.app
pkgbuild: Inferring bundle components from contents of /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.0y2FVz/installer-root
pkgbuild: Adding component at Applications/PenguinFan Experimental.app
pkgbuild: Wrote package to /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.0y2FVz/PenguinFan-Experimental-1.1.0.pkg
Validated experimental package: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.0y2FVz/PenguinFan-Experimental-1.1.0.pkg
Built installer: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/PenguinFan-Experimental-1.1.0.pkg
490dc3564b8b13b16825be3f27b8ffaa4a9db6d32505f3ff7da57d69bbc8f7eb  installer/PenguinFan-Experimental-1.1.0.pkg
PACKAGE_BUILD_EXIT=0
```

Artifact SHA-256: `490dc3564b8b13b16825be3f27b8ffaa4a9db6d32505f3ff7da57d69bbc8f7eb`.

---

## Runtime defect fix round 2: RuntimeController registration reachability

Validation date: 2026-07-30 KST.

Review established that the manager accepted `.notFound`, but the
user-confirmed RuntimeController path called `manager.register()` only for
`.notRegistered`. The integration now treats `.notRegistered` and
`.notFound` as the two attemptable registration states after explicit
confirmation. It still performs no registration before confirmation and does
not auto-enable or enter the diagnostic legacy fallback because a lookup
returns `.notFound`.

Generation guards and System fail-closed handling remain in force. The focused
regression test also exposed that pending mode was committed before XPC
readiness; custom mode commit now occurs only after readiness succeeds in the
same generation. Registration errors remain actionable failures in System
mode, and repeated or stale confirmation cannot duplicate registration.

No app was installed and the stable app was not modified.

### Focused RuntimeController tests

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter PrivilegedServiceManagerTests
```

Result:

```text
Test Suite 'M2MaxFanControllerPackageTests.xctest' passed at 2026-07-30 14:27:47.802.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.038 (0.040) seconds
Test Suite 'Selected tests' passed at 2026-07-30 14:27:47.802.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.038 (0.041) seconds
◇ Test run started.
↳ Testing Library Version: 1902
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
FOCUSED_TEST_EXIT=0
```

Coverage includes zero calls before explicit confirmation, one call from
`.notFound`, pending-mode application only after readiness, thrown-error
fail-closed behavior, and repeated/stale confirmation suppression.

### Release app build

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Result:

```text
[1/3] Write swift-version--58304C5D6DBC2206.txt
[3/4] Compiling FanControllerApp AppModel.swift
[3/5] Write Objects.LinkFileList
[4/5] Linking FanControllerApp
Build of product 'FanControllerApp' complete! (3.63s)
RELEASE_BUILD_EXIT=0
```

### Transactional experimental package regeneration

Command:

```bash
./script/build_installer.sh --experimental-helper
/usr/bin/shasum -a 256 installer/PenguinFan-Experimental-1.1.0.pkg
```

Result:

```text
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.clkLDj/dist-1.1.0/PenguinFan Experimental.app/Contents/MacOS/FanControllerApp: replacing existing signature
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.clkLDj/dist-1.1.0/PenguinFan Experimental.app: replacing existing signature
Built: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.clkLDj/dist-1.1.0/PenguinFan Experimental.app
pkgbuild: Inferring bundle components from contents of /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.clkLDj/installer-root
pkgbuild: Adding component at Applications/PenguinFan Experimental.app
pkgbuild: Wrote package to /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.clkLDj/PenguinFan-Experimental-1.1.0.pkg
Validated experimental package: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.clkLDj/PenguinFan-Experimental-1.1.0.pkg
Built installer: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/PenguinFan-Experimental-1.1.0.pkg
48231aef0c99ea4e5098ec710015ac03a9991d19963b2c545bf68d13df214506  installer/PenguinFan-Experimental-1.1.0.pkg
PACKAGE_BUILD_EXIT=0
```

Artifact SHA-256: `48231aef0c99ea4e5098ec710015ac03a9991d19963b2c545bf68d13df214506`.

---

## Runtime defect fix round 3: constrained ad-hoc XPC fallback

Validation date: 2026-07-30 KST.

Runtime evidence showed successful SMAppService registration, approval, and
daemon launch, followed by `SecCodeCopyGuestWithAttributes` returning the
no-live-guest-code class for the ad-hoc client. The validator now retains live
SecCode process identity as the primary route and enters the experimental
fallback only for `errSecCSNoSuchCode`. Invalid live code, unavailable
metadata, identity mismatch, UID mismatch, and all other primary failures reject
without fallback.

The fallback binds the connection PID to the exact fixed executable with
`proc_pidpath` before and after validation, requires exact raw and canonical
paths, verifies the console effective UID, checks valid `SecStaticCode` at
that canonical path, requires the exact signing identifier and ad-hoc flag, and
rejects any real TeamIdentifier. It reuses the complete root ownership,
no-group-or-other-write, expected object-kind, and unsafe extended ACL checks
for every protected installation ancestor. Structured logs contain only
`route`, `outcome`, and `reason` fields.

### Security limitation

This is an option-2 experimental accommodation for an ad-hoc build, not a
replacement for Developer ID signing. PID path is sampled before and after
static validation to fail closed on exit, path change, truncation, or observed
PID reuse, and the installation chain is immutable under the checked policy.
macOS does not expose the connection audit token through the public Foundation
API used here, so the two samples cannot create the same cryptographic
process-to-code binding as successful live SecCode validation. Production
release remains gated on a real signing identity and the primary path; the
fallback refuses binaries carrying a real TeamIdentifier.

No app was installed and the stable app was not modified.

### Focused validator tests

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test --filter \
  'AgentServerTests/(testXPCClientValidator|testAdHocFallback|testInvalidLiveCode)'
```

Result:

```text
Test Suite 'M2MaxFanControllerPackageTests.xctest' passed at 2026-07-30 14:41:56.371.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.002 (0.003) seconds
Test Suite 'Selected tests' passed at 2026-07-30 14:41:56.371.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.002 (0.004) seconds
◇ Test run started.
↳ Testing Library Version: 1902
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
FOCUSED_TEST_EXIT=0
```

Executed 14 focused tests covering the fixed-path success case plus PID path
mismatch/change, canonical or symlink mismatch, mutable ancestor, unsafe ACL,
wrong UID, wrong identifier, invalid static code, TeamIdentifier presence, and
invalid live-code non-fallback behavior.

### Release builds

Commands:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerAgent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Results:

```text
[1/3] Write sources
[3/4] Compiling FanControllerAgent AgentProcessLock.swift
[3/5] Write Objects.LinkFileList
[4/5] Linking FanControllerAgent
Build of product 'FanControllerAgent' complete! (1.94s)
RELEASE_AGENT_BUILD_EXIT=0
Building for production...
[0/2] Write swift-version--58304C5D6DBC2206.txt
Build of product 'FanControllerApp' complete! (0.13s)
RELEASE_APP_BUILD_EXIT=0
```

### Transactional experimental package regeneration

Command:

```bash
./script/build_installer.sh --experimental-helper
/usr/bin/shasum -a 256 installer/PenguinFan-Experimental-1.1.0.pkg
```

Result:

```text
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.PSpuhV/dist-1.1.0/PenguinFan Experimental.app/Contents/MacOS/FanControllerApp: replacing existing signature
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.PSpuhV/dist-1.1.0/PenguinFan Experimental.app: replacing existing signature
Built: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.PSpuhV/dist-1.1.0/PenguinFan Experimental.app
pkgbuild: Inferring bundle components from contents of /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.PSpuhV/installer-root
pkgbuild: Adding component at Applications/PenguinFan Experimental.app
pkgbuild: Wrote package to /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.PSpuhV/PenguinFan-Experimental-1.1.0.pkg
Validated experimental package: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/.PenguinFan-Experimental-1.1.0.staging.PSpuhV/PenguinFan-Experimental-1.1.0.pkg
Built installer: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/PenguinFan-Experimental-1.1.0.pkg
a1b382b6b80dc19ffd9beb167dedc1c3e6a175286e46eebc6d52ee507c257663  installer/PenguinFan-Experimental-1.1.0.pkg
PACKAGE_BUILD_EXIT=0
```

Artifact SHA-256: `a1b382b6b80dc19ffd9beb167dedc1c3e6a175286e46eebc6d52ee507c257663`.

---

## Security repair round 4/5: strict live code and Personal Team pinning

Validation date: 2026-07-30 KST.

The rejected ad-hoc PID/path/static-code fallback from commit `0922fec` was
removed completely. Listener admission now fails closed unless
`SecCodeCopyGuestWithAttributes` returns a valid live guest whose
live-derived signing information contains the exact executable path, signing
identifier, and Personal Team identifier. The existing console effective UID,
root ownership, immutable group/other modes, object-kind, and extended ACL
checks remain required.

No app or package was installed. The stable app, stable package/release assets,
marketing files, and unrelated untracked files were not modified.

### Signing identity probe and discovered TeamIdentifier

Commands:

```bash
/usr/bin/security find-identity -v -p codesigning
probe_dir=$(/usr/bin/mktemp -d /tmp/penguinfan-signing-probe.XXXXXX)
/bin/cp /usr/bin/true "$probe_dir/probe"
/usr/bin/codesign --force \
  --sign 'Apple Development: pmh10401@gmail.com (33KJJV566T)' \
  --options runtime --timestamp=none "$probe_dir/probe"
/usr/bin/codesign --verify --strict --verbose=2 "$probe_dir/probe"
/usr/bin/codesign -d --verbose=4 "$probe_dir/probe"
```

Result:

```text
D10DD321B33EAB9C02DB2BEB29E077986032B04E
Authority=Apple Development: pmh10401@gmail.com (33KJJV566T)
TeamIdentifier=UUUQNVQ67B
CodeDirectory flags=0x10000(runtime)
probe: valid on disk
probe: satisfies its Designated Requirement
```

The discovered and pinned TeamIdentifier is `UUUQNVQ67B`. It was taken from
the signed probe's actual `codesign` metadata; the certificate common-name
suffix `33KJJV566T` was not treated as the Team ID.

### Validator and full test suites

Commands:

```bash
/usr/bin/env bash -n \
  script/build_and_run.sh \
  script/build_installer.sh \
  script/validate_experimental_package.sh \
  script/test_experimental_packaging.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test \
  --filter 'AgentServerTests/testXPCClientValidator'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test
```

Results:

```text
Shell syntax validation: exit 0
Selected AgentServerTests: 7 tests, 0 failures
All tests: 101 tests, 0 failures
```

The focused validator cases cover exact identity success plus effective UID,
executable path, signing identifier, missing TeamIdentifier, wrong
TeamIdentifier, unavailable/invalid live code, root ownership, immutable
modes, expected object kinds, unsafe ACLs, and every protected installation
ancestor through `/Applications`.

### Release builds

Commands:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerAgent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Results:

```text
Build of product 'FanControllerAgent' complete
Build of product 'FanControllerApp' complete
RELEASE_BUILDS_EXIT=0
```

### Transactional signing and executable artifact tests

Command:

```bash
./script/test_experimental_packaging.sh \
  --signing-identity \
  'Apple Development: pmh10401@gmail.com (33KJJV566T)'
```

Result:

```text
missing identity: rejected before final artifact mutation
ad-hoc identity "-": rejected before final artifact mutation
unavailable identity: rejected before final artifact mutation
live-lock timeout preserved the existing artifact
injected pre-publication failure preserved transactional state
concurrent and signal-injection publication checks passed
Task 7 identity-gated transactional and artifact checks passed.
```

The executable artifact checks expand the package and verify the helper, main
executable, and app with `codesign --strict` and the app with
`codesign --deep --strict`. All three report:

```text
Authority=Apple Development: pmh10401@gmail.com (33KJJV566T)
TeamIdentifier=UUUQNVQ67B
CodeDirectory flags include runtime
Signature=adhoc absent
```

The tests also prove that the package contains only
`Applications/PenguinFan Experimental.app`, contains no stable or legacy app
path, and that `proc_pidpath`, path-created `SecStaticCode`, fallback identity
types/functions, and fallback-route logging symbols are absent from the
validator source.

### Final experimental package regeneration

Commands:

```bash
./script/build_installer.sh \
  --experimental-helper \
  --signing-identity \
  'Apple Development: pmh10401@gmail.com (33KJJV566T)'
./script/validate_experimental_package.sh \
  installer/PenguinFan-Experimental-1.1.0.pkg \
  'Apple Development: pmh10401@gmail.com (33KJJV566T)' \
  UUUQNVQ67B
/usr/bin/shasum -a 256 \
  installer/PenguinFan-Experimental-1.1.0.pkg
```

Result:

```text
Build of product 'FanControllerApp' complete
Build of product 'FanControllerAgent' complete
Build of product 'FanDiagnostics' complete
Validated experimental package: staging package
Built installer: installer/PenguinFan-Experimental-1.1.0.pkg
Validated experimental package: installer/PenguinFan-Experimental-1.1.0.pkg
2ef6fe24862ac6ae8d9bce8fb18326a3d873afe2d9bc958c12a351ee53262375
```

Artifact:

```text
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/PenguinFan-Experimental-1.1.0.pkg
SHA-256: 2ef6fe24862ac6ae8d9bce8fb18326a3d873afe2d9bc958c12a351ee53262375
```

### Local-only limitation

This package embeds code signed by a local Apple Development Personal Team
identity from this Mac's keychain. It is not Developer ID signed, installer
signed, notarized, or suitable for public distribution. Rebuilding requires
the same valid local identity and exact TeamIdentifier policy. The artifact
remains Experimental-only and was not installed.

---

## Security repair round 5/5: transactional app publication and executable proof

Validation date: 2026-07-30 KST.

All three round-4 Important findings were repaired. Destructive package
transaction tests now run under a unique temporary Experimental output root
after the supplied identity passes a real signed probe. The published package
is snapshotted before the test and checked again from the EXIT/INT/TERM cleanup
path. Direct Experimental app builds perform the same non-ad-hoc signed probe
and exact TeamIdentifier gate before app-path mutation, build and sign in a
sibling staging directory, and restore the complete prior app directory if
publication fails or receives TERM after the backup move.

The package test now runs `nm`, `nm -u`, and `strings -a` against the actual
`FanControllerAgent` executable extracted from the package. It rejects
`proc_pidpath`, path-created `SecStaticCode` APIs, and the removed fallback
routes, types, functions, or strings. The source guard remains as defense in
depth.

No app or package was installed. The stable app, stable package/release assets,
marketing files, and unrelated untracked files were not modified.

### Signing identity and Team gate

Command:

```bash
/usr/bin/security find-identity -v -p codesigning
```

Result:

```text
D10DD321B33EAB9C02DB2BEB29E077986032B04E
Apple Development: pmh10401@gmail.com (33KJJV566T)
1 valid identities found
```

The identity probe used by the test, direct app builder, and installer signed
`/usr/bin/true` with hardened runtime and `--timestamp=none`, verified it with
`codesign --strict`, and required:

```text
Authority=Apple Development: pmh10401@gmail.com (33KJJV566T)
TeamIdentifier=UUUQNVQ67B
CodeDirectory flags include runtime
Signature=adhoc absent
```

Only one code-signing identity was available. The wrong-Team preservation
branch was therefore exercised with a failure-only test hook that replaces the
observed Team value with a fixed mismatch after a genuine successful signed
probe. The hook can only force rejection; it cannot make any identity pass.

### Static checks, validator suites, and release builds

Commands:

```bash
/usr/bin/env bash -n \
  script/build_and_run.sh \
  script/build_installer.sh \
  script/validate_experimental_package.sh \
  script/test_experimental_packaging.sh
git diff --check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test \
  --filter 'AgentServerTests/testXPCClientValidator'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerAgent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcrun swift build -c release --product FanControllerApp
```

Results:

```text
Shell syntax validation: exit 0
git diff --check: exit 0
Selected AgentServerTests: 7 tests, 0 failures
All tests: 101 tests, 0 failures
Build of product 'FanControllerAgent' complete
Build of product 'FanControllerApp' complete
```

### Isolated transaction and executable-artifact test

Command:

```bash
./script/test_experimental_packaging.sh \
  --signing-identity \
  'Apple Development: pmh10401@gmail.com (33KJJV566T)'
```

The first preflight invocation stopped before any artifact mutation because an
initial defense-in-depth regex rejected the benign live-guest declaration
`var staticCode: SecStaticCode?`:

```text
FAIL: unsafe XPC client fallback symbols remain
```

The guard was narrowed to the rejected path-created APIs
(`SecStaticCodeCreateWithPath`, `SecStaticCodeCheckValidity`, and
`SecStaticCodeCopySigningInformation`) while retaining the actual executable
import/symbol/string scan. The complete rerun result was:

```text
Task 7 identity-gated transactional and artifact checks passed.
TEST_EXIT=0
```

The passing assertions covered:

- missing, ad-hoc, unavailable, and forced wrong-Team package identities
  preserving the isolated pre-existing package byte-for-byte;
- the same direct-app identity failures preserving the complete prior app
  directory with an inode-independent tar snapshot;
- direct-app failure before publication and TERM immediately after the prior
  app backup move restoring the exact directory snapshot;
- direct-app helper-then-app signing, strict/deep validation, hardened runtime,
  Authority, and Team metadata;
- `nm`, undefined-import `nm -u`, and `strings -a` inspection of the actual
  helper extracted from each verified package;
- live-lock, stale-lock, pre-publication failure, concurrent publication, and
  signal-injection package rollback;
- absence of stable or legacy app payload paths and cleanup of all temporary
  app/package staging directories.

The real published package remained byte-identical throughout the isolated
test:

```text
SHA-256 before test:
2ef6fe24862ac6ae8d9bce8fb18326a3d873afe2d9bc958c12a351ee53262375
SHA-256 after test:
2ef6fe24862ac6ae8d9bce8fb18326a3d873afe2d9bc958c12a351ee53262375
```

### Final transactional package regeneration

Commands:

```bash
./script/build_installer.sh \
  --experimental-helper \
  --signing-identity \
  'Apple Development: pmh10401@gmail.com (33KJJV566T)'
./script/validate_experimental_package.sh \
  installer/PenguinFan-Experimental-1.1.0.pkg \
  'Apple Development: pmh10401@gmail.com (33KJJV566T)' \
  UUUQNVQ67B
/usr/bin/shasum -a 256 \
  installer/PenguinFan-Experimental-1.1.0.pkg
```

Result:

```text
Build of product 'FanControllerApp' complete
Build of product 'FanControllerAgent' complete
Build of product 'FanDiagnostics' complete
Validated experimental package: staging package
Built installer: installer/PenguinFan-Experimental-1.1.0.pkg
Validated experimental package: installer/PenguinFan-Experimental-1.1.0.pkg
7a9b03f7b27dcebed91e51db34470a219364dfc3522c2ef62f4b6d748bcabc7f
```

The exact helper expanded from the published package reported:

```text
CodeDirectory flags=0x10000(runtime)
Authority=Apple Development: pmh10401@gmail.com (33KJJV566T)
TeamIdentifier=UUUQNVQ67B
FINAL_HELPER_FALLBACK_SURFACE=absent
```

Artifact:

```text
/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/PenguinFan-Experimental-1.1.0.pkg
SHA-256: 7a9b03f7b27dcebed91e51db34470a219364dfc3522c2ef62f4b6d748bcabc7f
```

### Local-only limitation

The package contains code signed by this Mac's local Apple Development Personal
Team identity. The installer package itself is unsigned, the product is not
Developer ID signed or notarized, and it is not suitable for public
distribution. Rebuilding requires the same usable local identity and exact
`UUUQNVQ67B` Team policy. The artifact remains Experimental-only and was not
installed.

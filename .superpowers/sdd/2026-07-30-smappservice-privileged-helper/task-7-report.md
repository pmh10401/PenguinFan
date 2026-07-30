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

# Task 6 Report: LaunchDaemon Bundle Packaging

## Scope

Implemented only the isolated PenguinFan Experimental packaging path. No install,
launch, removal, or modification of `/Applications/PenguinFan.app` was performed.
The stable 1.0.12 build defaults and artifact names remain available when the new
flag is omitted.

## TDD evidence

### RED

Command:

```bash
/tmp/test_penguin_task6.sh "$PWD"
```

Result: failed as expected with
`FAIL: experimental LaunchDaemon plist is missing` before implementation.

### GREEN

Command:

```bash
./script/test_experimental_packaging.sh
```

Result:

```text
Task 6 packaging contract checks passed.
```

The focused contract checks validate plist syntax and values, script syntax,
the explicit experimental flag, isolated names/identifiers, the embedded
LaunchDaemon location, and the absence of stable-app removal logic.

## Experimental build and package

Command:

```bash
./script/build_installer.sh --experimental-helper
```

Results:

- Release `FanControllerApp`, `FanControllerAgent`, and `FanDiagnostics` builds succeeded.
- App created at `dist-1.1.0/PenguinFan Experimental.app`.
- Helper, diagnostics executable, main executable, then complete app were ad-hoc signed inside-out.
- Strict helper, main executable, and deep app signature verification passed.
- Bundle identifier `com.local.PenguinFan.experimental` passed validation.
- Embedded LaunchDaemon plist syntax, label, `BundleProgram`, executable target,
  and Mach service validation passed.
- Separate package payload validation passed.
- Package created at `installer/PenguinFan-Experimental-1.1.0.pkg`.
- Experimental package contains `Applications/PenguinFan Experimental.app` and
  rejects stable `PenguinFan.app` or legacy `FanController.app` payloads.
- The stable-only postinstall script is intentionally excluded from the
  experimental package.

## Artifact

`/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/PenguinFan-Experimental-1.1.0.pkg`

Runtime installation and launch are intentionally deferred to Task 7.

## Fix round 1/5: transactional publication and executable artifact tests

### RED evidence

Command:

```bash
./script/test_experimental_packaging.sh
```

Before the transactional implementation, the deliberate failure environment was
ignored, the old script published the final package, and the test failed with:

```text
FAIL: deliberate pre-publication failure unexpectedly succeeded
```

### Final focused GREEN run

Command:

```bash
./script/test_experimental_packaging.sh
```

Result: exit 0 with:

```text
Injected Task 6 failure before package publication.
Built installer: /Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/PenguinFan-Experimental-1.1.0.pkg
Task 6 executable artifact and failure-path checks passed.
```

The focused test performed two complete Release app/agent/diagnostics builds.
The first run placed a stale sentinel at the final distribution path, injected
exit 75 after all staged validations, and proved both the final package and
staging directory were absent. The second run rebuilt and validated the app and
package, then published by same-filesystem rename.

Executable artifact checks covered:

- Info.plist bundle ID, display name, version 1.1.0, and build 14
- embedded LaunchDaemon path, plist syntax, Label, BundleProgram, ProcessType,
  and MachServices
- main and helper executable presence
- strict helper/main signatures, deep app signature, ad-hoc metadata, and signed
  app/main identifier
- complete pkgutil payload allowlist
- physically expanded payload containing only
  `Payload/Applications/PenguinFan Experimental.app` and no stable or legacy app
- trap cleanup after both injected failure and successful publication

No install or launch was performed.

Regenerated artifact:

`/Users/mac/Documents/Man fan controler/.worktrees/native-fan-controller/installer/PenguinFan-Experimental-1.1.0.pkg`

SHA-256: `4179e830359693c28cdfa01924b06f017736f7341d838e63903cf710a5d473af`

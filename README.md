# PenguinFan

[English](README.md) | [한국어](README.ko.md)

PenguinFan is a free and open-source native macOS fan controller for the
M2 Max MacBook Pro. It provides a lightweight SwiftUI menu bar interface,
live temperature and RPM monitoring, manual control, and a temperature-based
fan curve.

> **Free forever:** PenguinFan is distributed at no charge under the
> [MIT License](LICENSE). You may use, study, modify, and redistribute it,
> including for commercial purposes.

## Experimental release

`v1.1.0-experimental.1` replaces the previous `osascript` administrator
launcher with a signed `SMAppService` LaunchDaemon and privileged XPC
connection.

This release is:

- Verified on one `Mac14,6` M2 Max MacBook Pro
- Signed with an Apple Development certificate
- Not notarized by Apple
- Published as a prerelease for testing

Gatekeeper may block the installer or app on another Mac. If you trust the
download, use **System Settings > Privacy & Security > Open Anyway**. Do not
use this build on unsupported hardware without reviewing the diagnostics and
fan ranges first.

## Features

- Native SwiftUI menu bar app
- Animated penguin menu bar icon that responds to fan speed
- Live maximum sensor temperature
- Dual-fan current and target RPM monitoring
- macOS automatic fan mode
- Temperature-based curve mode
- Fixed manual RPM mode
- Per-fan hardware range validation
- Root helper managed by `SMAppService`
- Privileged XPC client validation using live code identity
- LaunchDaemon `SpawnConstraint` for signing identifier, Team ID, and signing
  category
- Six-second heartbeat watchdog
- Automatic restoration to macOS fan control
- Read-only hardware diagnostics

## Verified hardware and result

The current prerelease was validated on:

| Item | Value |
| --- | --- |
| Model | `Mac14,6` |
| Chip | Apple M2 Max |
| Fan 1 range | `1350-5349 RPM` |
| Fan 2 range | `1522-5777 RPM` |
| Curve sensor | `TCMz` CPU die hotspot |
| Minimum macOS | macOS 13 |

Real hardware Curve test on July 30, 2026:

- Temperature: approximately `78 C`
- Curve target: `4873 RPM`
- Fan 1 response: `4922 RPM`
- Fan 2 response: `4921 RPM`
- System restoration: successful
- Restored readings: approximately `1990 / 2158 RPM`
- XPC validation: `accepted reason=validated`
- Privileged helper exit after restoration: exit code `0`

Other Apple Silicon models may use different SMC keys and fan ranges and are
currently unsupported.

## Download and install

1. Download `PenguinFan-Experimental-1.1.0.pkg` from
   [GitHub Releases](../../releases).
2. Open the package and complete the installer.
3. Launch `/Applications/PenguinFan Experimental.app`.
4. Select **Curve** or **Manual**, review the permission explanation, and
   choose **Continue**.
5. If macOS requests approval, enable PenguinFan under
   **System Settings > General > Login Items & Extensions**.

The app monitors temperatures without administrator privileges. The privileged
service starts only when fan control is requested.

## Safety design

- The helper accepts only status, heartbeat, bounded RPM, restore, and shutdown
  commands.
- The live client must match the expected executable path, signing identifier,
  Team ID, console user, and secure installation path.
- The LaunchDaemon only runs the expected signed helper.
- A lost heartbeat, connection failure, sleep event, sensor failure, app exit,
  or explicit System selection restores both fans to macOS automatic control.
- Critical macOS thermal pressure requests the maximum supported fan speed.

Direct fan control can affect cooling, noise, component temperature, and
hardware lifespan. This software is experimental and provided without
warranty.

## Build from source

Requirements:

- macOS 13 or later
- Apple Silicon Mac
- Xcode with Swift 6 support

Build the standard local app:

```bash
./script/build_and_run.sh --verify
```

Run tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift test
```

Run read-only diagnostics:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift run FanDiagnostics
```

The experimental privileged package requires a valid signing identity. Forks
must replace the hard-coded bundle identifiers and Team ID with their own
values before distribution.

## Uninstall

1. Select **System** mode and confirm that macOS is controlling the fans.
2. Remove the privileged service from PenguinFan settings.
3. Quit PenguinFan.
4. Remove `/Applications/PenguinFan Experimental.app`.

## Open-source references

AppleSMC access and Apple Silicon fan research were informed by:

- [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan)
- [metaspartan/mactop](https://github.com/metaspartan/mactop)
- [angristan/MacThrottle](https://github.com/angristan/MacThrottle)
- [ryyansafar/MacMonitor](https://github.com/ryyansafar/MacMonitor)

Third-party notices are included in `LICENSES/`.

## License

[MIT License](LICENSE). Free for personal and commercial use.

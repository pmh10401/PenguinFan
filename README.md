# PenguinFan

[English](README.md) | [한국어](README.ko.md)

PenguinFan is a free and open-source native macOS fan controller for the
M2 Max MacBook Pro. Its lightweight SwiftUI menu bar interface provides live
temperature and RPM monitoring, temperature-based fan curves, manual RPM
control, and one-click restoration to macOS automatic fan control.

> **Free forever:** PenguinFan is distributed at no charge under the
> [MIT License](LICENSE). You may use, study, modify, and redistribute it,
> including for commercial purposes.

## PenguinFan 1.2.2

Version `1.2.2` restores reliable Curve and Manual control after installation.
It supports localized and symbolic-link application paths, preserves an
approved `SMAppService` helper across app updates, and keeps a Curve command
stable through a brief missing-temperature sample.

- Stable app: `/Applications/PenguinFan.app`
- Package: `PenguinFan-1.2.2.pkg`
- Signed with an Apple Development certificate
- Verified on a `Mac14,6` M2 Max MacBook Pro
- Not notarized by Apple

Gatekeeper may block the installer or app on another Mac. If you trust the
download, use **System Settings > Privacy & Security > Open Anyway**. Current
hardware validation is limited to the model listed below.

## Features

- Native SwiftUI menu bar app
- Animated penguin icon whose walking speed follows fan speed
- Live maximum sensor temperature
- Dual-fan current and target RPM monitoring
- macOS System, temperature Curve, and fixed Manual modes
- Automatic macOS System control below the first curve point
- Manual RPM entry, slider, and `-50` / `+50` controls
- Per-fan hardware range validation
- Root helper managed by `SMAppService`
- Live XPC client validation using code identity and installation path
- LaunchDaemon `SpawnConstraint` for signing identifier, Team ID, and category
- Six-second heartbeat watchdog
- Automatic restoration to macOS fan control
- Read-only hardware diagnostics

## Verified hardware and result

| Item | Value |
| --- | --- |
| Model | `Mac14,6` |
| Chip | Apple M2 Max |
| Fan 1 range | `1350-5349 RPM` |
| Fan 2 range | `1522-5777 RPM` |
| Curve sensor | `TCMz` CPU die hotspot |
| Minimum macOS | macOS 13 |

Real hardware Curve test on July 31, 2026:

- Temperature: approximately `81.5 C`
- Curve target: `5063 RPM`
- Fan 1 response: `5065 RPM`
- Fan 2 response: `5048 RPM`
- XPC validation: `accepted reason=validated`
- Privileged helper: running and accepting Curve commands

Other Apple Silicon models may use different SMC keys and fan ranges and are
not currently supported.

## Download and install

1. Download `PenguinFan-1.2.2.pkg` from [GitHub Releases](../../releases).
2. Open the package and complete the installer.
3. Launch `/Applications/PenguinFan.app`.
4. Select **Curve** or **Manual**, review the permission explanation, and
   choose **Continue**.
5. If macOS requests approval, enable PenguinFan under
   **System Settings > General > Login Items & Extensions**.

Temperature monitoring does not require administrator privileges. The
privileged service starts only when fan control is requested.

## Safety design

- The helper accepts only status, heartbeat, bounded RPM, restore, and shutdown
  commands.
- The client must match the signed bundle layout under `/Applications`, signing
  identifier, Team ID, console user, and secure installation path.
- A lost heartbeat, connection failure, sleep event, sustained sensor failure,
  app exit, or explicit System selection restores both fans to macOS automatic
  control.
- Critical macOS thermal pressure requests the maximum supported fan speed.

Direct fan control can affect cooling, noise, component temperature, and
hardware lifespan. This software is provided without warranty.

## Build from source

Requirements: macOS 13 or later, Apple Silicon, and Xcode with Swift 6 support.

```bash
./script/build_and_run.sh --verify

./script/run_tests.sh
```

The privileged release package requires a valid signing identity. Forks must
replace the hard-coded bundle identifiers and Team ID before distribution.

## Uninstall

1. Select **System** mode and confirm that macOS controls the fans.
2. Remove the privileged service from PenguinFan settings.
3. Quit PenguinFan.
4. Remove `/Applications/PenguinFan.app`.

## Open-source references

- [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan)
- [metaspartan/mactop](https://github.com/metaspartan/mactop)
- [angristan/MacThrottle](https://github.com/angristan/MacThrottle)
- [ryyansafar/MacMonitor](https://github.com/ryyansafar/MacMonitor)

Third-party notices are included in `LICENSES/`.

## License

[MIT License](LICENSE). Free for personal and commercial use.

# PenguinFan

Free and open-source native macOS fan controller for the M2 Max MacBook Pro.

M2 Max MacBook Pro용 무료 오픈소스 네이티브 팬 컨트롤러입니다. SwiftUI로
작성되어 Python이나 외부 런타임이 필요하지 않습니다.

> **Free forever:** This project is distributed at no charge under the
> [MIT License](LICENSE). You may use, study, modify, and redistribute it.

## Features

- Native SwiftUI dashboard and menu bar interface
- Live CPU hotspot temperature and dual-fan RPM monitoring
- macOS system automatic mode
- Fixed manual RPM mode
- Temperature-based fan curve mode
- Per-fan hardware range validation
- Privileged write agent with local Unix socket IPC
- Heartbeat watchdog and automatic macOS control restoration
- Read-only diagnostics bundled with the app

## Verified hardware

The current release is specifically validated on:

- Mac model: `Mac14,6`
- Chip: Apple M2 Max
- Fan 1 range: `1350-5349 RPM`
- Fan 2 range: `1522-5777 RPM`
- Curve sensor: `TCMz` CPU die hotspot
- macOS: Apple Silicon

Real hardware verification performed for v1.0.3:

- Manual test: Fan 1 requested `1650 RPM` for 5 seconds and responded up to
  `1666 RPM`.
- Curve test at `87.21 C`: Fan 1 reached `5307/5349 RPM`; Fan 2 reached
  `5721/5777 RPM`.
- Both tests restored `F0Md=0` and `F1Md=0` after completion.
- The related SMCKit test suite passed all 11 tests.

Other Apple Silicon models may expose different SMC keys and fan ranges. They
should be treated as unsupported until tested.

## Download

Download the latest free installer from
[GitHub Releases](../../releases/latest).

The installer places the app at:

```text
/Applications/PenguinFan.app
```

The release is locally ad-hoc signed and is not Apple-notarized. macOS may show
a Gatekeeper warning on another Mac.

## How it works

- Monitoring is read-only and does not require administrator privileges.
- Selecting Curve or Manual mode requests administrator approval.
- The privileged agent accepts only status, heartbeat, bounded fan RPM,
  restore, and shutdown commands.
- If heartbeat is lost for 6 seconds, the sensor fails, the Mac sleeps, or the
  app exits, both fans are returned to macOS automatic control.
- Critical macOS thermal pressure always requests each fan's maximum supported
  RPM.

## Build from source

Requirements:

- macOS 13 or later
- Apple Silicon Mac
- Xcode with Swift 6 support

Build and run:

```bash
./script/build_and_run.sh
```

Build without launching:

```bash
./script/build_and_run.sh --verify
```

Run the read-only hardware diagnostic:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift run FanDiagnostics
```

Build an installer:

```bash
./script/build_installer.sh 1.0.11
open installer/PenguinFan-1.0.11.pkg
```

Run tests:

```bash
xcrun swift test
```

## Uninstall

Return to System mode and quit the app first, then remove it:

```bash
sudo rm -rf /Applications/PenguinFan.app
```

The app does not install a LaunchDaemon or persistent root helper.

## Safety warning

Direct fan control can affect cooling, noise, component temperature, and
hardware lifespan. This software is experimental and provided without warranty.
Keep macOS automatic restoration enabled, monitor temperatures, and do not use
untested builds on unsupported hardware.

## Open-source references

AppleSMC access and Apple Silicon fan research were informed by:

- [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan)
- [metaspartan/mactop](https://github.com/metaspartan/mactop)
- [angristan/MacThrottle](https://github.com/angristan/MacThrottle)
- [ryyansafar/MacMonitor](https://github.com/ryyansafar/MacMonitor)

Third-party license notices are included in `LICENSES/`.

## License

MIT License. Free for personal and commercial use.

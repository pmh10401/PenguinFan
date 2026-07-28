# Native Fan Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native SwiftUI menu bar app that reads M2 Max temperatures and fan RPM, then safely provides system-auto, temperature-curve, and fixed-RPM control modes after one local administrator authorization.

**Architecture:** A normal-user SwiftUI app reads AppleSMC through IOKit and renders a MacThrottle-style popover. Hardware writes are isolated in a short-lived root agent reached through an authenticated per-session Unix socket; heartbeat loss, sleep, stale sensors, or any write failure returns all fans to system control.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI, Charts, IOKit, Foundation, Darwin Unix sockets, XCTest, shell-based `.app` staging, ad-hoc code signing.

## Global Constraints

- Target hardware is `Mac14,6`, Apple M2 Max, with two fans expected but always probe `FNum`.
- Minimum supported OS is macOS 13.0 because the app uses `MenuBarExtra`.
- Use no third-party runtime dependency and no Python, Tkinter, `powermetrics`, or external `smc` binary.
- The app always starts in `systemAuto`; never persist or silently restore an active manual mode.
- Never request 0 RPM or a value below `F%dMn`; clamp every target to `F%dMn...F%dMx`.
- Read sensors every 1 second and retain at most 10 minutes of history.
- Treat temperature data older than 5 seconds as stale and return to `systemAuto`.
- Send a privileged-agent heartbeat every 2 seconds; the agent restores system control after 6 seconds without a heartbeat.
- Restore system control on app quit, sleep, IPC failure, sensor failure, partial fan failure, and agent termination.
- Do not perform a real SMC write until read-only diagnostics pass and the user explicitly approves the hardware-write test.
- Preserve the existing Python implementation as historical reference until the native app passes its read-only and write verification gates.

---

## File Structure

```text
Package.swift
Sources/
  FanControllerCore/
    ControlModels.swift
    CurveEngine.swift
    SafetyStateMachine.swift
    SettingsStore.swift
  SMCKit/
    SMCParamStruct.swift
    SMCDataFormat.swift
    SMCConnection.swift
    SMCKeys.swift
    HardwareProbe.swift
    SensorReader.swift
    FanWriter.swift
  FanControlIPC/
    ControlProtocol.swift
    UnixSocket.swift
  FanDiagnostics/
    main.swift
  FanControllerAgent/
    AgentServer.swift
    main.swift
  FanControllerApp/
    FanControllerApp.swift
    AppModel.swift
    SensorPoller.swift
    ControlCoordinator.swift
    AuthorizationLauncher.swift
    LaunchAtLoginController.swift
    MenuBarView.swift
    HistoryChartView.swift
    SettingsView.swift
    DiagnosticsView.swift
Tests/
  FanControllerCoreTests/
    CurveEngineTests.swift
    SafetyStateMachineTests.swift
    SettingsStoreTests.swift
  SMCKitTests/
    SMCDataFormatTests.swift
    HardwareProbeTests.swift
    FanWriterTests.swift
  FanControlIPCTests/
    ControlProtocolTests.swift
    UnixSocketTests.swift
  FanControllerAppTests/
    AppModelTests.swift
    ControlCoordinatorTests.swift
script/
  build_and_run.sh
  build_installer.sh
.codex/environments/environment.toml
LICENSES/
  macos-smc-fan-LICENSE.md
  mactop-LICENSE
  MacThrottle-LICENSE
README.md
```

## Task 1: SwiftPM Scaffold and Domain Models

**Files:**

- Create: `Package.swift`
- Create: `Sources/FanControllerCore/ControlModels.swift`
- Create: `Sources/FanControllerCore/SettingsStore.swift`
- Create: `Tests/FanControllerCoreTests/SettingsStoreTests.swift`
- Modify: `.gitignore`

**Interfaces:**

- Produces: `FanDescriptor`, `FanReading`, `SensorSnapshot`, `CurvePoint`, `FanSettings`, `ControlMode`, `ThermalPressureLevel`, and `ControlStatus`.
- Consumes: no prior application code.

- [ ] **Step 1: Write the failing model round-trip test**

```swift
import XCTest
@testable import FanControllerCore

final class SettingsStoreTests: XCTestCase {
    func testFanSettingsRoundTripKeepsCurveButStartsInSystemAuto() throws {
        let settings = FanSettings(
            mode: .manual,
            manualRPM: 3200,
            curve: [.init(temperature: 55, rpm: 2300), .init(temperature: 90, rpm: 6200)]
        )
        let data = try JSONEncoder().encode(settings.persistedCopy)
        let restored = try JSONDecoder().decode(FanSettings.self, from: data)
        XCTAssertEqual(restored.mode, .systemAuto)
        XCTAssertEqual(restored.manualRPM, 3200)
        XCTAssertEqual(restored.curve.count, 2)
    }
}
```

- [ ] **Step 2: Run the test and confirm the target does not exist**

Run: `swift test --filter SettingsStoreTests`

Expected: FAIL because `Package.swift` and `FanControllerCore` do not exist.

- [ ] **Step 3: Create the package and focused model types**

Define products `FanControllerCore`, `SMCKit`, `FanControlIPC`, `FanDiagnostics`, `FanControllerAgent`, and `FanControllerApp`. Define these exact public shapes:

```swift
public enum ControlMode: String, Codable, Sendable {
    case systemAuto
    case curve
    case manual
}

public struct CurvePoint: Codable, Equatable, Sendable {
    public var temperature: Double
    public var rpm: Int
    public init(temperature: Double, rpm: Int) {
        self.temperature = temperature
        self.rpm = rpm
    }
}

public struct FanSettings: Codable, Equatable, Sendable {
    public var mode: ControlMode
    public var manualRPM: Int
    public var curve: [CurvePoint]
    public var persistedCopy: FanSettings {
        .init(mode: .systemAuto, manualRPM: manualRPM, curve: curve)
    }
}

public struct FanDescriptor: Codable, Equatable, Sendable {
    public let index: Int
    public let minimumRPM: Int
    public let maximumRPM: Int
    public let modeKey: String
}

public struct FanReading: Codable, Equatable, Sendable {
    public let index: Int
    public let actualRPM: Int
    public let targetRPM: Int
}
```

Implement `SettingsStore` with this API:

```swift
public actor SettingsStore {
    public init(fileURL: URL? = nil)
    public func load() throws -> FanSettings
    public func save(_ settings: FanSettings) throws
}
```

The default URL is
`~/Library/Application Support/M2MaxFanController/settings.json`.
`save` always encodes `settings.persistedCopy`; `load` returns safe defaults
when the file does not exist and never restores an active control mode.

- [ ] **Step 4: Run the model test**

Run: `swift test --filter SettingsStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift .gitignore Sources/FanControllerCore Tests/FanControllerCoreTests
git commit -m "build: scaffold native fan controller package"
```

## Task 2: Curve Engine and Safety State Machine

**Files:**

- Create: `Sources/FanControllerCore/CurveEngine.swift`
- Create: `Sources/FanControllerCore/SafetyStateMachine.swift`
- Create: `Tests/FanControllerCoreTests/CurveEngineTests.swift`
- Create: `Tests/FanControllerCoreTests/SafetyStateMachineTests.swift`

**Interfaces:**

- Consumes: `CurvePoint`, `ControlMode`, and `FanSettings`.
- Produces: `CurveEngine.targetRPM(...)`, `SafetyStateMachine.handle(...)`, `SafetyAction`, and `SafetyEvent`.

- [ ] **Step 1: Write failing interpolation and monotonicity tests**

```swift
func testCurveInterpolatesAndClamps() throws {
    let points = [CurvePoint(temperature: 50, rpm: 2200), CurvePoint(temperature: 90, rpm: 6200)]
    XCTAssertEqual(try CurveEngine.targetRPM(temperature: 70, points: points, minimumRPM: 2300, maximumRPM: 6000), 4200)
    XCTAssertEqual(try CurveEngine.targetRPM(temperature: 95, points: points, minimumRPM: 2300, maximumRPM: 6000), 6000)
}

func testCurveRejectsRPMDecreaseAsTemperatureRises() {
    let points = [CurvePoint(temperature: 60, rpm: 4000), CurvePoint(temperature: 80, rpm: 3000)]
    XCTAssertThrowsError(try CurveEngine.validate(points))
}
```

- [ ] **Step 2: Run the curve tests**

Run: `swift test --filter CurveEngineTests`

Expected: FAIL because `CurveEngine` is undefined.

- [ ] **Step 3: Implement minimal curve calculation**

Use this exact API:

```swift
public enum CurveEngine {
    public static func validate(_ points: [CurvePoint]) throws
    public static func targetRPM(
        temperature: Double,
        points: [CurvePoint],
        minimumRPM: Int,
        maximumRPM: Int
    ) throws -> Int
    public static func limitedRPM(previous: Int, proposed: Int, maximumStep: Int) -> Int
}
```

Validation requires at least two points, strictly increasing temperatures, nondecreasing RPM, and finite temperatures. Linear interpolation rounds to the nearest integer and clamps to the probed fan range.

- [ ] **Step 4: Write failing safety transition tests**

```swift
func testStaleSensorForcesAutomaticControl() {
    var machine = SafetyStateMachine()
    _ = machine.handle(.controlEnabled)
    XCTAssertEqual(machine.handle(.sensorAge(seconds: 5.1)), [.restoreSystemAuto, .stopControl])
}

func testSleepForcesAutomaticControl() {
    var machine = SafetyStateMachine()
    _ = machine.handle(.controlEnabled)
    XCTAssertEqual(machine.handle(.willSleep), [.restoreSystemAuto, .stopControl])
}
```

- [ ] **Step 5: Implement and test the safety state machine**

Define:

```swift
public enum SafetyEvent: Equatable, Sendable {
    case controlEnabled
    case controlDisabled
    case sensorAge(seconds: TimeInterval)
    case heartbeatLost
    case writeFailed
    case willSleep
}

public enum SafetyAction: Equatable, Sendable {
    case restoreSystemAuto
    case stopControl
}
```

Run: `swift test --filter FanControllerCoreTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/FanControllerCore Tests/FanControllerCoreTests
git commit -m "feat: add fan curve and safety state machine"
```

## Task 3: AppleSMC Transport and Data Formats

**Files:**

- Create: `Sources/SMCKit/SMCParamStruct.swift`
- Create: `Sources/SMCKit/SMCDataFormat.swift`
- Create: `Sources/SMCKit/SMCConnection.swift`
- Create: `Sources/SMCKit/SMCKeys.swift`
- Create: `Tests/SMCKitTests/SMCDataFormatTests.swift`

**Interfaces:**

- Produces: `SMCTransport`, `SMCConnection`, `SMCValue`, `SMCError`, and `SMCDataFormat`.
- Consumes: IOKit only.

- [ ] **Step 1: Write failing binary format tests**

```swift
func testAppleSiliconFloatRoundTrip() {
    let bytes = SMCDataFormat.encodeFloat(3475, size: 4)
    XCTAssertEqual(SMCDataFormat.decodeFloat(bytes, size: 4), 3475, accuracy: 0.01)
}

func testBigEndianUInt32Decode() {
    XCTAssertEqual(SMCDataFormat.decodeUInt32([0x00, 0x00, 0x01, 0x00]), 256)
}
```

- [ ] **Step 2: Run the format tests**

Run: `swift test --filter SMCDataFormatTests`

Expected: FAIL because `SMCDataFormat` is undefined.

- [ ] **Step 3: Implement the exact 80-byte AppleSMC ABI**

Create `SMCParamStruct` with key, version, power-limit, key-info, result, status, command, data32, and 32 data bytes. Assert layout in a test:

```swift
XCTAssertEqual(MemoryLayout<SMCParamStruct>.stride, 80)
```

Use selector `2`, commands `5` read, `6` write, `8` index, and `9` key info. Use `MemoryLayout<SMCParamStruct>.stride` for `IOConnectCallStructMethod`.

- [ ] **Step 4: Implement the transport boundary**

```swift
public protocol SMCTransport: Sendable {
    func read(_ key: String) throws -> SMCValue
    func write(_ key: String, bytes: [UInt8]) throws
}

public struct SMCValue: Equatable, Sendable {
    public let bytes: [UInt8]
    public let dataSize: UInt32
    public let dataType: String
}
```

`SMCConnection` opens `AppleSMC`, checks both IOKit and firmware result codes, and never logs raw arbitrary memory.

- [ ] **Step 5: Run all SMCKit format tests**

Run: `swift test --filter SMCKitTests`

Expected: PASS without accessing real hardware.

- [ ] **Step 6: Add MIT attribution files and commit**

Copy the three reference license texts into `LICENSES/` because the SMC ABI and sensor catalogs are derived from those projects.

```bash
git add Sources/SMCKit Tests/SMCKitTests LICENSES
git commit -m "feat: add native AppleSMC transport"
```

## Task 4: Read-Only Hardware Probe and Diagnostic CLI

**Files:**

- Create: `Sources/SMCKit/HardwareProbe.swift`
- Create: `Sources/SMCKit/SensorReader.swift`
- Create: `Sources/FanDiagnostics/main.swift`
- Create: `Tests/SMCKitTests/HardwareProbeTests.swift`

**Interfaces:**

- Consumes: `SMCTransport`, `FanDescriptor`, `FanReading`, and `SensorSnapshot`.
- Produces: `HardwareProbe.probe()`, `SensorReader.snapshot()`, and JSON diagnostics.

- [ ] **Step 1: Write a fake transport probe test**

```swift
func testProbeFindsTwoFansAndUppercaseModeKey() throws {
    let fake = FakeSMC(values: [
        "FNum": .uint8(2),
        "F0Mn": .float(2317), "F0Mx": .float(7826), "F0Md": .uint8(3),
        "F1Mn": .float(2317), "F1Mx": .float(7826), "F1Md": .uint8(3)
    ])
    let result = try HardwareProbe(transport: fake).probe()
    XCTAssertEqual(result.fans.count, 2)
    XCTAssertEqual(result.fans[0].modeKey, "F0Md")
}
```

- [ ] **Step 2: Run the probe test**

Run: `swift test --filter HardwareProbeTests`

Expected: FAIL because `HardwareProbe` is undefined.

- [ ] **Step 3: Implement runtime fan and sensor discovery**

Probe `FNum`, then for every fan read `Ac`, `Tg`, `Mn`, `Mx`, and test lowercase `md` before uppercase `Md`. Probe `Ftst` as capability data only.

Use this ordered M2 Pro/Max temperature catalog:

```swift
let m2ProMaxKeys = [
    "TC10", "TC11", "TC12", "TC13", "TC20", "TC21", "TC22", "TC23",
    "TC30", "TC31", "TC32", "TC33", "TC40", "TC41", "TC42", "TC43",
    "TC50", "TC51", "TC52", "TC53",
    "Tg04", "Tg05", "Tg0C", "Tg0D", "Tg0K", "Tg0L", "Tg0S", "Tg0T"
]
```

Accept only finite temperatures in `10...120` Celsius. Cache successful keys and retry a failed full probe after 60 seconds.

Read thermal pressure through Darwin notification
`com.apple.system.thermalpressurelevel` and map states `0`, `1`, `2`, and
`3...4` to `.nominal`, `.elevated`, `.hot`, and `.critical`. This path is
read-only and does not invoke `powermetrics`.

- [ ] **Step 4: Implement the read-only diagnostics executable**

`FanDiagnostics` prints one JSON object with model identifier, SMC connection status, fan descriptors, current readings, valid temperature keys, maximum temperature, and thermal pressure. It exposes no write command.

Run: `swift run FanDiagnostics`

Expected on this Mac: model `Mac14,6`, two fan records, and at least one valid temperature key. Any failure must be represented by a nonzero exit code and a concrete JSON `error`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMCKit Sources/FanDiagnostics Tests/SMCKitTests
git commit -m "feat: add read-only M2 Max diagnostics"
```

## Task 5: Safe Fan Writer

**Files:**

- Create: `Sources/SMCKit/FanWriter.swift`
- Create: `Tests/SMCKitTests/FanWriterTests.swift`

**Interfaces:**

- Consumes: `SMCTransport` and `FanDescriptor`.
- Produces: `FanWriting`, `FanWriter.setRPM`, and `FanWriter.restoreSystemAuto`.

- [ ] **Step 1: Write a failing command-sequence test**

```swift
func testSetRPMEnablesManualBeforeWritingTarget() throws {
    let fake = RecordingSMC()
    let fan = FanDescriptor(index: 0, minimumRPM: 2300, maximumRPM: 6200, modeKey: "F0Md")
    try FanWriter(transport: fake, ftstAvailable: false).setRPM(3000, for: fan)
    XCTAssertEqual(fake.writes.map(\.key), ["F0Md", "F0Tg"])
}

func testOutOfRangeTargetIsRejected() {
    let fan = FanDescriptor(index: 0, minimumRPM: 2300, maximumRPM: 6200, modeKey: "F0Md")
    XCTAssertThrowsError(try FanWriter(transport: RecordingSMC(), ftstAvailable: false).setRPM(0, for: fan))
}
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter FanWriterTests`

Expected: FAIL because `FanWriter` is undefined.

- [ ] **Step 3: Implement direct mode and `Ftst` fallback**

```swift
public protocol FanWriting: Sendable {
    func setRPM(_ rpm: Int, for fan: FanDescriptor) throws
    func restoreSystemAuto(_ fans: [FanDescriptor]) throws
}
```

Attempt mode value `1` directly. Only after a firmware rejection and when `Ftst` exists, write `Ftst=1`, wait 500 ms, and retry the mode key every 100 ms for at most 10 seconds. Write `F%dTg` only after manual mode succeeds.

For restoration, write each fan mode to `0`; when `Ftst` was enabled, write `Ftst=0` after all fans have left manual mode. Attempt every fan even if one restoration write fails, then return the combined error.

- [ ] **Step 4: Run fan writer tests**

Run: `swift test --filter FanWriterTests`

Expected: PASS using only fake transports; no real SMC write occurs.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMCKit/FanWriter.swift Tests/SMCKitTests/FanWriterTests.swift
git commit -m "feat: add guarded fan write sequences"
```

## Task 6: Local IPC and Privileged Agent

**Files:**

- Create: `Sources/FanControlIPC/ControlProtocol.swift`
- Create: `Sources/FanControlIPC/UnixSocket.swift`
- Create: `Sources/FanControllerAgent/AgentServer.swift`
- Create: `Sources/FanControllerAgent/main.swift`
- Create: `Tests/FanControlIPCTests/ControlProtocolTests.swift`
- Create: `Tests/FanControlIPCTests/UnixSocketTests.swift`

**Interfaces:**

- Consumes: `FanWriting`, `HardwareProbe`, and `FanDescriptor`.
- Produces: `ControlRequest`, `ControlResponse`, `ControlCommand`, `UnixSocketClient`, and root-agent CLI arguments.

- [ ] **Step 1: Write failing protocol tests**

```swift
func testProtocolRoundTrip() throws {
    let request = ControlRequest(id: UUID(), command: .setRPM(fan: 1, rpm: 3400))
    let data = try JSONEncoder().encode(request)
    XCTAssertEqual(try JSONDecoder().decode(ControlRequest.self, from: data), request)
}

func testProtocolDoesNotExposeArbitrarySMCKeys() {
    XCTAssertFalse(String(describing: ControlCommand.self).contains("writeKey"))
}
```

- [ ] **Step 2: Define the allow-listed protocol**

```swift
public enum ControlCommand: Codable, Equatable, Sendable {
    case status
    case heartbeat
    case setRPM(fan: Int, rpm: Int)
    case restoreSystemAuto
    case shutdown
}
```

Messages are newline-delimited JSON with a maximum encoded size of 16 KiB. Reject unknown fan indices, malformed JSON, duplicate request IDs, and requests received before hardware probing succeeds.

- [ ] **Step 3: Write and run a Unix socket integration test**

Create a private temporary directory with mode `0700`, start `UnixSocketServer`, exchange one `status` request, close both sides, and assert the socket file is removed.

Run: `swift test --filter FanControlIPCTests`

Expected: PASS without root privileges.

- [ ] **Step 4: Implement the agent heartbeat and cleanup**

The agent CLI accepts only:

```text
FanControllerAgent --socket <absolute-path> --owner-uid <decimal-uid>
```

It verifies the socket parent is owned by `owner-uid` and mode `0700`, creates the socket, changes socket ownership to that UID with mode `0600`, and starts a 2-second watchdog check. Six seconds without heartbeat triggers `restoreSystemAuto`, closes the socket, and exits.

Install `SIGTERM`, `SIGINT`, and normal-defer cleanup handlers that all call `restoreSystemAuto`.

- [ ] **Step 5: Test the watchdog with a fake writer**

Inject a monotonic clock and `FanWriting` fake into `AgentServer`. Advance the fake clock by 6.1 seconds and assert one restoration call and server termination.

Run: `swift test --filter FanControlIPCTests`

Expected: PASS and no hardware access.

- [ ] **Step 6: Commit**

```bash
git add Sources/FanControlIPC Sources/FanControllerAgent Tests/FanControlIPCTests
git commit -m "feat: add privileged fan control agent"
```

## Task 7: MacThrottle-Style SwiftUI App

**Files:**

- Create: `Sources/FanControllerApp/FanControllerApp.swift`
- Create: `Sources/FanControllerApp/AppModel.swift`
- Create: `Sources/FanControllerApp/SensorPoller.swift`
- Create: `Sources/FanControllerApp/MenuBarView.swift`
- Create: `Sources/FanControllerApp/HistoryChartView.swift`
- Create: `Sources/FanControllerApp/SettingsView.swift`
- Create: `Sources/FanControllerApp/DiagnosticsView.swift`
- Create: `Sources/FanControllerApp/LaunchAtLoginController.swift`
- Create: `Tests/FanControllerAppTests/AppModelTests.swift`

**Interfaces:**

- Consumes: `SensorReader`, domain models, and `FanSettings`.
- Produces: `AppModel`, `SensorPoller`, menu bar scene, popover, settings, and diagnostics views.

- [ ] **Step 1: Write failing app-model history tests**

```swift
@MainActor
func testHistoryKeepsOnlyTenMinutes() {
    let model = AppModel()
    model.record(.fixture(date: Date(timeIntervalSince1970: 0)))
    model.record(.fixture(date: Date(timeIntervalSince1970: 601)))
    XCTAssertEqual(model.history.count, 1)
}
```

- [ ] **Step 2: Implement polling and state publication**

`SensorPoller` is an actor that reads once per second and emits `SensorSnapshot`. `AppModel` is `@MainActor`, owns no SMC connection, and publishes:

```swift
@Published var snapshot: SensorSnapshot?
@Published var history: [SensorSnapshot] = []
@Published var settings: FanSettings
@Published var controlStatus: ControlStatus = .systemAuto
@Published var diagnosticMessage: String?
```

- [ ] **Step 3: Build the menu bar UI**

Use:

```swift
MenuBarExtra {
    MenuBarView()
} label: {
    Label(model.menuBarTitle, systemImage: model.menuBarSymbol)
}
.menuBarExtraStyle(.window)
```

The 360-point-wide popover shows maximum temperature, thermal pressure, Fan 1/Fan 2 actual and target RPM, a 10-minute `Charts` graph, and a segmented mode picker for System Auto, Curve, and Manual.

- [ ] **Step 4: Build settings and diagnostics views**

Settings provide monotonic curve-point editing, a manual RPM slider constrained to the intersection of both fans' probed ranges, launch-at-login UI state, and a permanent `Return to System Auto` button. Diagnostics show model, valid sensor keys, fan descriptors, IPC status, and the latest concrete error.

Implement launch at login with `SMAppService.mainApp.register()` and
`unregister()`. Surface `.requiresApproval` by opening the Login Items settings
pane and keep the toggle off until `SMAppService.mainApp.status == .enabled`.

- [ ] **Step 5: Run app-model tests and compile**

Run: `swift test --filter FanControllerAppTests`

Expected: PASS.

Run: `swift build --product FanControllerApp`

Expected: build succeeds without Python or external packages.

- [ ] **Step 6: Commit**

```bash
git add Sources/FanControllerApp Tests/FanControllerAppTests
git commit -m "feat: add native menu bar fan UI"
```

## Task 8: Administrator Launch and Control Coordination

**Files:**

- Create: `Sources/FanControllerApp/AuthorizationLauncher.swift`
- Create: `Sources/FanControllerApp/ControlCoordinator.swift`
- Create: `Tests/FanControllerAppTests/ControlCoordinatorTests.swift`
- Modify: `Sources/FanControllerApp/AppModel.swift`
- Modify: `Sources/FanControllerApp/FanControllerApp.swift`

**Interfaces:**

- Consumes: bundled `FanControllerAgent`, `UnixSocketClient`, `CurveEngine`, and `SafetyStateMachine`.
- Produces: `AuthorizationLauncher.startAgent(...)` and `ControlCoordinator`.

- [ ] **Step 1: Write failing coordinator safety tests**

```swift
func testCurveModeSendsClampedRPMToBothFans() async throws {
    let client = RecordingControlClient()
    let coordinator = ControlCoordinator(client: client, settings: .curveFixture)
    try await coordinator.apply(snapshot: .hotFixture)
    XCTAssertEqual(client.rpmCommands, [.init(fan: 0, rpm: 5000), .init(fan: 1, rpm: 5000)])
}

func testWriteFailureImmediatelyRequestsAuto() async {
    let client = FailingControlClient()
    let coordinator = ControlCoordinator(client: client, settings: .curveFixture)
    do {
        try await coordinator.apply(snapshot: .hotFixture)
        XCTFail("expected the injected write failure")
    } catch {
        // Expected.
    }
    XCTAssertEqual(client.restoreCount, 1)
}
```

- [ ] **Step 2: Implement the one-time authorization launcher**

Create a session directory beneath `FileManager.default.temporaryDirectory` with mode `0700`. Start `/usr/bin/osascript` on a background task with:

```applescript
do shell script "exec '<bundle>/Contents/Helpers/FanControllerAgent' --socket '<session>/control.sock' --owner-uid '<uid>'" with administrator privileges
```

Construct the AppleScript from safely quoted fixed arguments; never interpolate settings, SMC keys, or shell fragments. A cancelled authorization returns `.authorizationCancelled` and leaves the app in read-only mode.

- [ ] **Step 3: Implement control coordination**

On activation, launch the agent, connect the socket, send heartbeat every 2 seconds, and wait for `status` before enabling mode controls. For curve mode, calculate one safe target from the hottest valid sensor and clamp independently for each fan. For manual mode, clamp the slider value independently for each fan.

When thermal pressure is `.critical`, bypass interpolation and request each
fan's probed maximum RPM. After every target change, compare actual RPM with
the requested target for up to 8 seconds using a tolerance of 400 RPM. A fan
that does not respond triggers immediate restoration for both fans and
disables control.

- [ ] **Step 4: Wire lifecycle restoration**

Observe `NSWorkspace.willSleepNotification`, application termination, and sensor freshness. Each path sends `restoreSystemAuto`, waits up to 1 second for acknowledgement, then sends `shutdown`. On wake, rerun read-only diagnostics and remain in system-auto mode until the user activates control again.

- [ ] **Step 5: Run coordinator tests**

Run: `swift test --filter ControlCoordinatorTests`

Expected: PASS with fake IPC clients; no authorization prompt and no SMC writes.

- [ ] **Step 6: Commit**

```bash
git add Sources/FanControllerApp Tests/FanControllerAppTests
git commit -m "feat: connect UI to privileged control agent"
```

## Task 9: Reproducible App Bundle and Local Installer

**Files:**

- Create: `script/build_and_run.sh`
- Create: `script/build_installer.sh`
- Create: `.codex/environments/environment.toml`
- Modify: `README.md`

**Interfaces:**

- Consumes: SwiftPM products `FanControllerApp`, `FanControllerAgent`, and `FanDiagnostics`.
- Produces: `dist/FanController.app`, Codex Run action, and `installer/FanController-<version>.pkg`.

- [ ] **Step 1: Create the single build/run entrypoint**

`script/build_and_run.sh` supports `run`, `--debug`, `--logs`, `--telemetry`, and `--verify`. It kills only process `FanControllerApp`, runs `swift build`, stages:

```text
dist/FanController.app/Contents/MacOS/FanControllerApp
dist/FanController.app/Contents/Helpers/FanControllerAgent
dist/FanController.app/Contents/Helpers/FanDiagnostics
dist/FanController.app/Contents/Info.plist
```

Set bundle identifier `com.local.M2MaxFanController`, `LSMinimumSystemVersion=13.0`, `LSUIElement=true`, and `NSPrincipalClass=NSApplication`. Ad-hoc sign with:

```bash
codesign --force --deep --sign - dist/FanController.app
```

Launch only through `/usr/bin/open -n dist/FanController.app`.

- [ ] **Step 2: Add the Codex Run action**

Create:

```toml
# THIS IS AUTOGENERATED. DO NOT EDIT MANUALLY
version = 1
name = "M2 Max Fan Controller"

[setup]
script = ""

[[actions]]
name = "Run"
icon = "run"
command = "./script/build_and_run.sh"
```

- [ ] **Step 3: Create the local package builder**

Stage only `Applications/FanController.app`, exclude AppleDouble `._*` files, and build:

```bash
COPYFILE_DISABLE=1 pkgbuild \
  --identifier com.local.M2MaxFanController \
  --version "$VERSION" \
  --root "$PKG_ROOT" \
  --install-location / \
  "installer/FanController-$VERSION.pkg"
```

Before reporting success, run `pkgutil --payload-files` and require `Applications/FanController.app/Contents/MacOS/FanControllerApp`.

- [ ] **Step 4: Document exact run and safety behavior**

Rewrite `README.md` for the native app. Include build, read-only diagnostics, run, local install, uninstall, administrator prompt behavior, automatic restoration guarantees, unsigned Gatekeeper limitation, and MIT attributions.

- [ ] **Step 5: Verify the bundle without launching control**

Run:

```bash
./script/build_and_run.sh --verify
codesign --verify --deep --strict --verbose=2 dist/FanController.app
plutil -lint dist/FanController.app/Contents/Info.plist
```

Expected: process verification, code-sign verification, and plist lint all succeed.

- [ ] **Step 6: Commit**

```bash
git add script .codex/environments/environment.toml README.md
git commit -m "build: package native fan controller app"
```

## Task 10: Read-Only and User-Gated Hardware Verification

**Files:**

- Create: `docs/verification/Mac14,6-read-only.json`
- Create only after explicit approval: `docs/verification/Mac14,6-write-test.md`

**Interfaces:**

- Consumes: built diagnostics, app bundle, and privileged agent.
- Produces: current-machine evidence for sensor reads, fan reads, safe write response, and system-auto restoration.

- [ ] **Step 1: Run all automated tests**

Run: `swift test`

Expected: all unit and IPC tests pass with no administrator prompt.

- [ ] **Step 2: Run and save read-only diagnostics**

Run: `mkdir -p docs/verification && swift run FanDiagnostics > docs/verification/Mac14,6-read-only.json`

Expected: JSON reports `Mac14,6`, two fans, valid RPM ranges, actual RPM values, at least one valid temperature key, and no write attempt.

- [ ] **Step 3: Launch and inspect the UI**

Run: `./script/build_and_run.sh --verify`

Expected: menu bar process exists, popover opens, temperature and two fan RPM values update once per second, and status remains `System Auto`.

- [ ] **Step 4: Stop and request explicit hardware-write approval**

Do not continue automatically. Report the probed minimum and maximum RPM for each fan and propose one exact target:

```text
testTarget = min(max(minimumRPM + 300, minimumRPM), maximumRPM)
duration = 5 seconds
scope = Fan 0 only
recovery = immediate system-auto restoration
```

Continue only after the user approves that exact test.

- [ ] **Step 5: Perform one minimal write and verify recovery**

After approval, activate Fan 0 at `testTarget` for 5 seconds, observe actual RPM movement, return both fans to system auto, and verify their mode keys are no longer manual. If any command fails, restore both fans immediately and stop.

- [ ] **Step 6: Test curve mode only after the minimal write passes**

Run curve mode for 30 seconds using the default points `55°C → minimumRPM`, `75°C → midpoint`, and `90°C → maximumRPM`. Confirm targets stay within each fan's reported range, then return to system auto.

- [ ] **Step 7: Record evidence and commit**

Record exact timestamps, model, fan ranges, requested/actual RPM, restoration result, and any SMC firmware error code.

```bash
git add docs/verification
git commit -m "test: verify M2 Max fan controller hardware"
```

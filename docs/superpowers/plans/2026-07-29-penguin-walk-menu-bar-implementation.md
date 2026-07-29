# Penguin Walking Menu Bar Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animate the PenguinFan menu bar penguin at a pace derived from the average measured fan RPM.

**Architecture:** `PenguinMenuBarIcon` renders four deterministic vector poses. A new `PenguinWalkAnimator` converts measured RPM values into a frame interval and owns a main-thread one-shot timer, while `FanControllerAppDelegate` only supplies readings and applies frames to the status item.

**Tech Stack:** Swift 6, AppKit, Foundation `Timer`, Swift Package Manager, XCTest

## Global Constraints

- Use the average valid `actualRPM` from all available fan readings.
- Use four monochrome 18-point AppKit template frames.
- Clamp frame intervals to `0.18...0.90` seconds.
- Show a stationary frame when sensor readings are unavailable.
- Do not modify fan targets, SMC writes, control modes, or the safety state machine.
- Keep macOS 13 as the minimum deployment target.
- Git operations are excluded unless the user requests them explicitly.

---

### Task 1: Walking Pose Renderer

**Files:**
- Modify: `Sources/FanControllerApp/PenguinMenuBarIcon.swift`
- Modify: `Tests/FanControllerAppTests/ProductBrandTests.swift`

**Interfaces:**
- Produces: `PenguinMenuBarIcon.make(frame: Int = 0) -> NSImage`
- Consumes: Integer frame values; values are normalized into the four-frame cycle.

- [ ] **Step 1: Add renderer tests**

Add tests that call frames `0...3` and verify every image has size
`NSSize(width: 18, height: 18)`, `isTemplate == true`, and non-nil TIFF data.
Also verify frame `4` renders successfully as the normalized equivalent of
frame `0`.

- [ ] **Step 2: Run the focused renderer tests**

Run:

```bash
swift test --filter ProductBrandTests
```

Expected: the new calls fail because `make(frame:)` does not exist.

- [ ] **Step 3: Implement four vector poses**

Change the renderer interface to:

```swift
static func make(frame: Int = 0) -> NSImage
```

Normalize with:

```swift
let phase = ((frame % 4) + 4) % 4
```

Use phase-specific body offsets `[0, 1, 0, 1]`, head tilts
`[-0.8, 0, 0.8, 0]`, and alternating foot positions. Preserve the face,
eyes, beak, 18-point canvas, accessibility description, and template flag.

- [ ] **Step 4: Run the focused renderer tests**

Run:

```bash
swift test --filter ProductBrandTests
```

Expected: all renderer and branding tests pass.

---

### Task 2: RPM-Paced Animation Engine

**Files:**
- Create: `Sources/FanControllerApp/PenguinWalkAnimator.swift`
- Create: `Tests/FanControllerAppTests/PenguinWalkAnimatorTests.swift`

**Interfaces:**
- Produces: `PenguinWalkAnimator.averageRPM(_ values: [Double]) -> Double?`
- Produces: `PenguinWalkAnimator.frameInterval(for averageRPM: Double?) -> TimeInterval`
- Produces: `start(rpmProvider:onFrame:)` and `stop()`
- Consumes: A callback returning current actual RPM values and a callback receiving an `NSImage`.

- [ ] **Step 1: Add RPM mapping tests**

Cover these exact expectations:

```swift
XCTAssertNil(PenguinWalkAnimator.averageRPM([]))
XCTAssertEqual(PenguinWalkAnimator.averageRPM([2_000, 4_000]), 3_000)
XCTAssertEqual(PenguinWalkAnimator.averageRPM([-1, 3_000]), 3_000)
XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: nil), 0.90)
XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 1_500), 0.90)
XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 3_000), 0.55)
XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 4_500), 0.32)
XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 6_000), 0.18)
```

Use `accuracy: 0.001` for floating-point interval assertions.

- [ ] **Step 2: Run the focused animator tests**

Run:

```bash
swift test --filter PenguinWalkAnimatorTests
```

Expected: compilation fails because `PenguinWalkAnimator` does not exist.

- [ ] **Step 3: Implement averaging and piecewise interpolation**

Ignore negative and non-finite RPM values. Linearly interpolate between
`(1500, 0.90)`, `(3000, 0.55)`, `(4500, 0.32)`, and `(6000, 0.18)`, clamping
outside that range.

- [ ] **Step 4: Implement timer lifecycle**

Declare the animator `@MainActor`. `start` must stop an existing timer, store
the callbacks, render frame zero immediately, and schedule a non-repeating
timer. Each timer fire must:

1. Read current RPM values.
2. Keep frame zero when no valid value exists.
3. Otherwise advance the frame modulo four.
4. Deliver `PenguinMenuBarIcon.make(frame:)`.
5. Schedule the next non-repeating timer with the current mapped interval.

`stop()` invalidates the timer and clears callbacks.

- [ ] **Step 5: Run the focused animator tests**

Run:

```bash
swift test --filter PenguinWalkAnimatorTests
```

Expected: all RPM averaging and interval tests pass.

---

### Task 3: Status Item Integration

**Files:**
- Modify: `Sources/FanControllerApp/FanControllerApp.swift`

**Interfaces:**
- Consumes: `model.snapshot?.fans.map { Double($0.actualRPM) }`
- Consumes: `PenguinWalkAnimator.start(rpmProvider:onFrame:)`
- Produces: Animated images assigned to `statusItem.button?.image`.

- [ ] **Step 1: Add animator ownership**

Add:

```swift
private let penguinAnimator = PenguinWalkAnimator()
```

to `FanControllerAppDelegate`.

- [ ] **Step 2: Start animation after status item creation**

Supply actual RPM values through a weak-self callback and update the status
button image through another weak-self callback. Keep the existing tooltip,
popover target, and click action unchanged.

- [ ] **Step 3: Stop animation at termination**

Add `applicationWillTerminate(_:)` and call `penguinAnimator.stop()` before
the process exits.

- [ ] **Step 4: Build the application target**

Run:

```bash
swift build -c release --product FanControllerApp
```

Expected: release build succeeds without changing the fan-control targets.

---

### Task 4: Package and Runtime Verification

**Files:**
- Modify: `script/build_and_run.sh`
- Modify: `script/build_installer.sh`

**Interfaces:**
- Produces: `dist-1.0.9/PenguinFan.app`
- Produces: `installer/PenguinFan-1.0.9.pkg`

- [ ] **Step 1: Increment product version**

Set the default app version to `1.0.9`, build number to `10`, and installer
default version to `1.0.9`.

- [ ] **Step 2: Run all available tests**

Run:

```bash
swift test
```

Expected: all tests pass. If the selected local toolchain still lacks
`XCTest`, record that environment limitation and continue with the independent
release build verification.

- [ ] **Step 3: Build and verify the installer**

Run:

```bash
./script/build_installer.sh 1.0.9
```

Expected: release products build, code-sign verification succeeds, and
`installer/PenguinFan-1.0.9.pkg` contains
`Applications/PenguinFan.app/Contents/MacOS/FanControllerApp`.

- [ ] **Step 4: Install and launch without exposing credentials**

Use cached non-interactive administrator authorization when available:

```bash
sudo -n installer -pkg installer/PenguinFan-1.0.9.pkg -target /
open /Applications/PenguinFan.app
```

If authorization is unavailable, open the package in macOS Installer and let
the user enter credentials directly.

- [ ] **Step 5: Visually verify the menu bar behavior**

Confirm the penguin alternates walking poses, remains monochrome in both menu
bar appearances, and accelerates when measured average fan RPM increases.
Confirm opening the popover remains responsive while the animation runs.

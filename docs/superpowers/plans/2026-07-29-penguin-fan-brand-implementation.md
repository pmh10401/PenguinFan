# PenguinFan Brand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the installed product to PenguinFan and ship the approved 2.5D application icon plus a monochrome penguin menu bar icon without changing fan-control behavior.

**Architecture:** Keep all SwiftPM target names, helper executable names, IPC messages, SMC logic, settings storage, and the global agent lock unchanged. Add a small branding boundary for user-facing names and menu bar artwork, then update the packaging scripts to generate an `.icns`, install `/Applications/PenguinFan.app`, and remove the legacy app path during upgrade.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSStatusItem`/`NSImage`, SwiftPM, shell packaging, `sips`, `iconutil`, `codesign`, `pkgbuild`

## Global Constraints

- Product display name is exactly `PenguinFan`.
- Installed path is exactly `/Applications/PenguinFan.app`.
- Installer filename is `PenguinFan-<version>.pkg`.
- The application icon uses the approved 2.5D penguin artwork.
- The menu bar uses a separate monochrome 2D penguin template with no text.
- Internal Swift target and helper names remain unchanged.
- Existing settings under `M2MaxFanController` remain readable.
- Fan-control behavior, SMC keys, watchdog, global agent lock, and automatic restore behavior remain unchanged.
- The upgrade removes only `/Applications/FanController.app`.
- No git commits are performed unless the user explicitly requests them.

---

## File Structure

- `Assets/PenguinFanIcon.png`: approved 2.5D source artwork used to build the macOS icon family.
- `Sources/FanControllerApp/ProductBrand.swift`: one source of truth for user-facing product strings.
- `Sources/FanControllerApp/PenguinMenuBarIcon.swift`: deterministic AppKit template drawing for the menu bar.
- `Tests/FanControllerAppTests/ProductBrandTests.swift`: branding and menu icon regression tests.
- `Sources/FanControllerApp/FanControllerApp.swift`: use the branding boundary and penguin status icon.
- `Sources/FanControllerApp/MenuBarView.swift`: update the popover header.
- `Sources/FanControllerApp/SettingsView.swift`: update the Settings navigation title.
- `script/build_and_run.sh`: build `PenguinFan.app`, generate `.icns`, and write updated bundle metadata.
- `script/build_installer.sh`: package the renamed app and attach the upgrade script.
- `script/package_scripts/postinstall`: remove the legacy installed app path.
- `README.md`: document the new product, paths, install command, and removal command.

---

### Task 1: Branding Boundary And Menu Bar Mark

**Files:**
- Create: `Sources/FanControllerApp/ProductBrand.swift`
- Create: `Sources/FanControllerApp/PenguinMenuBarIcon.swift`
- Create: `Tests/FanControllerAppTests/ProductBrandTests.swift`
- Modify: `Sources/FanControllerApp/FanControllerApp.swift`

**Interfaces:**
- Produces: `ProductBrand.displayName: String`
- Produces: `ProductBrand.settingsTitle: String`
- Produces: `ProductBrand.diagnosticsTitle: String`
- Produces: `PenguinMenuBarIcon.make() -> NSImage`
- Consumes: existing `NSStatusItem` setup in `FanControllerAppDelegate`

- [ ] **Step 1: Write branding regression tests**

```swift
import AppKit
import XCTest

@testable import FanControllerApp

final class ProductBrandTests: XCTestCase {
    func testPublicProductNameIsPenguinFan() {
        XCTAssertEqual(ProductBrand.displayName, "PenguinFan")
        XCTAssertEqual(
            ProductBrand.settingsTitle,
            "PenguinFan 설정"
        )
        XCTAssertEqual(
            ProductBrand.diagnosticsTitle,
            "PenguinFan 진단"
        )
    }

    func testMenuBarIconIsAValidTemplateImage() {
        let image = PenguinMenuBarIcon.make()

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertNotNil(image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ))
    }
}
```

- [ ] **Step 2: Run the new tests and confirm the missing symbols fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c debug --filter ProductBrandTests
```

Expected: compilation fails because `ProductBrand` and
`PenguinMenuBarIcon` do not exist.

- [ ] **Step 3: Add the product branding constants**

```swift
enum ProductBrand {
    static let displayName = "PenguinFan"
    static let settingsTitle = "\(displayName) 설정"
    static let diagnosticsTitle = "\(displayName) 진단"
}
```

- [ ] **Step 4: Implement the monochrome penguin template**

Create an 18-by-18 `NSImage`, draw a symmetric compact penguin silhouette with
`NSBezierPath`, cut the ivory face/chest region out using even-odd winding, and
set `image.isTemplate = true`. The drawing must contain no color literals
because macOS supplies the menu bar foreground color.

- [ ] **Step 5: Replace the status item artwork and labels**

In `FanControllerAppDelegate.applicationDidFinishLaunching`:

```swift
button.image = PenguinMenuBarIcon.make()
button.imagePosition = .imageOnly
button.title = ""
button.toolTip = ProductBrand.displayName
```

Use `ProductBrand.settingsTitle` and `ProductBrand.diagnosticsTitle` when
creating auxiliary windows.

- [ ] **Step 6: Run the focused tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c debug --filter ProductBrandTests
```

Expected: all `ProductBrandTests` pass.

---

### Task 2: User-Facing Rename

**Files:**
- Modify: `Sources/FanControllerApp/MenuBarView.swift`
- Modify: `Sources/FanControllerApp/SettingsView.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `ProductBrand.displayName`
- Produces: consistent `PenguinFan` labels in the app and documentation

- [ ] **Step 1: Replace popover and window-facing labels**

Use `ProductBrand.displayName` in the popover header:

```swift
Text(ProductBrand.displayName)
```

Use `ProductBrand.settingsTitle` in the Settings navigation title.
Do not rename `FanControllerAgent`, `FanControllerApp`, protocol types, or
diagnostic command names.

- [ ] **Step 2: Update README commands and paths**

Document these exact paths:

```text
/Applications/PenguinFan.app
installer/PenguinFan-1.0.8.pkg
```

Use:

```bash
open installer/PenguinFan-1.0.8.pkg
sudo rm -rf /Applications/PenguinFan.app
```

Explain that upgrades remove the old `/Applications/FanController.app`.

- [ ] **Step 3: Search only user-facing source and documentation**

Run:

```bash
rg -n '"Fan Controller"|/Applications/FanController.app|FanController-[0-9]' \
  Sources/FanControllerApp README.md script
```

Expected: remaining matches are limited to the intentional legacy removal path
and internal executable names.

---

### Task 3: Application Icon And Renamed Bundle

**Files:**
- Create: `Assets/PenguinFanIcon.png`
- Modify: `script/build_and_run.sh`

**Interfaces:**
- Consumes: approved 2.5D PNG artwork
- Produces: `dist-1.0.8/PenguinFan.app`
- Produces: `PenguinFan.app/Contents/Resources/PenguinFan.icns`

- [ ] **Step 1: Add the approved artwork**

Copy the approved generated asset without modifying the original:

```bash
mkdir -p Assets
cp \
  /Users/mac/.codex/generated_images/019fa7c8-b192-7fc2-9c5b-2e0137dac271/call_U5zpLmvcpvcrDT6qIM75I8hV.png \
  Assets/PenguinFanIcon.png
```

- [ ] **Step 2: Update version and output names**

Set:

```bash
APP_VERSION="${FAN_CONTROLLER_VERSION:-1.0.8}"
BUILD_NUMBER="${FAN_CONTROLLER_BUILD_NUMBER:-9}"
APP="$ROOT/dist-$APP_VERSION/PenguinFan.app"
```

Create `Contents/Resources` in addition to the existing bundle directories.

- [ ] **Step 3: Generate the macOS icon family**

Create `.build/PenguinFan.iconset` and generate:

```text
icon_16x16.png        16x16
icon_16x16@2x.png     32x32
icon_32x32.png        32x32
icon_32x32@2x.png     64x64
icon_128x128.png      128x128
icon_128x128@2x.png   256x256
icon_256x256.png      256x256
icon_256x256@2x.png   512x512
icon_512x512.png      512x512
icon_512x512@2x.png   1024x1024
```

Use `/usr/bin/sips -z HEIGHT WIDTH` for each raster and:

```bash
/usr/bin/iconutil -c icns \
  "$ICONSET" \
  -o "$CONTENTS/Resources/PenguinFan.icns"
```

- [ ] **Step 4: Update bundle metadata**

Write:

```xml
<key>CFBundleDisplayName</key>
<string>PenguinFan</string>
<key>CFBundleName</key>
<string>PenguinFan</string>
<key>CFBundleIconFile</key>
<string>PenguinFan</string>
```

Keep `CFBundleExecutable` as `FanControllerApp` and keep the existing bundle
identifier so macOS treats the package as an upgrade.

- [ ] **Step 5: Build and validate the app bundle**

Run:

```bash
FAN_CONTROLLER_VERSION=1.0.8 \
FAN_CONTROLLER_BUILD_NUMBER=9 \
  ./script/build_and_run.sh --verify
```

Expected:

```text
Built: .../dist-1.0.8/PenguinFan.app
```

Validate:

```bash
/usr/bin/codesign --verify --deep --strict \
  dist-1.0.8/PenguinFan.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' \
  dist-1.0.8/PenguinFan.app/Contents/Info.plist
```

Expected icon metadata: `PenguinFan`.

---

### Task 4: Upgrade-Safe Installer

**Files:**
- Create: `script/package_scripts/postinstall`
- Modify: `script/build_installer.sh`

**Interfaces:**
- Consumes: `dist-1.0.8/PenguinFan.app`
- Produces: `installer/PenguinFan-1.0.8.pkg`
- Produces: removal of only `/Applications/FanController.app` after install

- [ ] **Step 1: Add the post-install migration**

```bash
#!/bin/bash
set -euo pipefail

LEGACY_APP="/Applications/FanController.app"
if [[ -d "$LEGACY_APP" ]]; then
  /bin/rm -rf "$LEGACY_APP"
fi

exit 0
```

Make the script executable.

- [ ] **Step 2: Rename package paths**

Use:

```bash
APP="$ROOT/dist-$VERSION/PenguinFan.app"
DESTINATION="$PKG_ROOT/Applications/PenguinFan.app"
PACKAGE="$OUTPUT_DIR/PenguinFan-$VERSION.pkg"
```

Pass:

```bash
--scripts "$ROOT/script/package_scripts"
```

to `pkgbuild`.

- [ ] **Step 3: Update payload validation**

Require:

```text
Applications/PenguinFan.app/Contents/MacOS/FanControllerApp
```

and reject a package that contains:

```text
Applications/FanController.app
```

- [ ] **Step 4: Build the installer**

Run:

```bash
./script/build_installer.sh 1.0.8
```

Expected:

```text
Built installer: .../installer/PenguinFan-1.0.8.pkg
```

---

### Task 5: Regression And Installed-Product Validation

**Files:**
- Test: all existing Swift test targets
- Artifact: `installer/PenguinFan-1.0.8.pkg`

**Interfaces:**
- Consumes: completed renamed app and installer
- Produces: evidence that branding changed without fan-control regressions

- [ ] **Step 1: Run the full Swift suite**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c debug
```

Expected: all tests pass, including `ProductBrandTests`.

- [ ] **Step 2: Install the package with macOS authorization**

Install:

```bash
/usr/sbin/installer \
  -pkg /private/tmp/PenguinFan-1.0.8.pkg \
  -target /
```

Use the existing AppleScript administrator prompt flow rather than embedding a
password in a command.

- [ ] **Step 3: Verify migration and metadata**

Run:

```bash
test -d /Applications/PenguinFan.app
test ! -e /Applications/FanController.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' \
  /Applications/PenguinFan.app/Contents/Info.plist
/usr/bin/codesign --verify --deep --strict \
  /Applications/PenguinFan.app
```

Expected display name: `PenguinFan`.

- [ ] **Step 4: Launch and inspect the menu bar product**

Launch:

```bash
/usr/bin/open -n /Applications/PenguinFan.app
```

Verify through the accessibility tree:

```applescript
tell application "System Events"
  tell process "FanControllerApp"
    return name of every menu bar item of menu bar 2
  end tell
end tell
```

Expected: one icon-only item with accessibility name `PenguinFan`.

- [ ] **Step 5: Verify the popover and safe idle state**

Press the menu item through its standard `AXPress` action and confirm:

```text
PenguinFan
Apple Silicon Thermal Control
```

Run:

```bash
/Applications/PenguinFan.app/Contents/Helpers/FanDiagnostics
```

Expected:

```text
"check" : "ok"
"thermalPressure" : "nominal"
```

The application must remain in system-auto mode unless the user explicitly
selects curve or manual control.

---

## Self-Review Result

- Spec coverage: product naming, 2.5D app icon, monochrome menu icon, settings
  preservation, legacy app removal, and unchanged safety behavior are covered.
- Placeholder scan: no `TBD`, `TODO`, deferred implementation, or unspecified
  error-handling steps remain.
- Type consistency: `ProductBrand` and `PenguinMenuBarIcon.make()` names are
  consistent across tests and production steps.
- Scope: the plan changes branding and packaging only; no fan-control behavior
  or unrelated refactor is included.

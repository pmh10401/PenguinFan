# PenguinFan Brand Design

## Goal

Rename the macOS fan-control product to `PenguinFan` and give it a distinct,
friendly penguin identity that remains recognizable in the Dock, Finder,
installer, menu bar, and control popover.

## Product Name

- Display name: `PenguinFan`
- Bundle name: `PenguinFan`
- Installed application: `/Applications/PenguinFan.app`
- Installer name: `PenguinFan-<version>.pkg`
- Internal Swift target and helper executable names remain unchanged to avoid
  unrelated runtime and IPC changes.

## Application Icon

The approved icon uses a polished 2.5D baby emperor penguin:

- large rounded head and short body
- deep navy-charcoal outer body
- warm ivory face and chest
- small restrained orange beak
- arctic cyan rounded-square background
- cyan four-blade fan recessed into the chest as a cooling core
- shallow layer separation between the outer body and ivory face/chest
- restrained edge highlights and ambient occlusion only
- a lightly folded surface on the beak
- centered composition with enough padding for macOS icon masks
- no text, feet, extra objects, photorealistic feathers, plastic gloss, or deep
  cast shadows

The visual quality may reference Pengrid's friendly product-icon language,
but the silhouette, proportions, face, beak, and chest-fan device must remain
original and visibly distinct. The result must remain primarily graphic and
vector-like, positioned between flat 2D and full 3D.

## Menu Bar Icon

The menu bar uses a separate monochrome template mark rather than shrinking the
full-color application icon:

- compact penguin silhouette
- no visible text
- symmetric form readable at 16-18 points
- template rendering that follows light and dark menu bars
- accessibility description and tooltip: `PenguinFan`

## In-App Naming

Replace user-facing `Fan Controller` labels with `PenguinFan` in:

- popover header
- Settings and Diagnostics window titles
- navigation titles
- installer and package output
- README installation and removal instructions

Technical diagnostic names such as `FanControllerAgent` remain unchanged.

## Packaging

- Add the approved PNG source asset to the project.
- Generate a valid macOS `.icns` file during packaging.
- Add `CFBundleIconFile` to `Info.plist`.
- Install the renamed app as `/Applications/PenguinFan.app`.
- Remove the previous `/Applications/FanController.app` during upgrade so two
  menu bar applications cannot run concurrently.
- Increment the release version and build number.

## Compatibility And Safety

- Fan-control behavior, SMC keys, watchdog, global agent lock, and automatic
  restore behavior are unchanged.
- The renamed app continues using the existing settings directory so user
  curves and safety preferences are preserved.
- The installer must replace the old product path without modifying unrelated
  applications or user data.

## Acceptance Criteria

- Finder and Applications show `PenguinFan` with the approved color icon.
- The menu bar shows only the monochrome penguin mark.
- Clicking the mark opens the existing live control popover.
- Settings and Diagnostics open with the new name.
- Only one installed application remains after upgrade.
- Existing fan-control safety behavior remains intact.

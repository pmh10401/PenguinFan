# PenguinFan Menu Version Label Design

## Goal

Show the running PenguinFan version in the menu bar popover without adding
visual clutter or coupling the UI to a hard-coded release number.

## Design

- Place a centered secondary label above the footer buttons.
- Read `CFBundleShortVersionString` from the running application bundle.
- Display `PenguinFan <version>` when a non-empty version exists.
- Fall back to `PenguinFan` when bundle metadata is missing.
- Use `caption2` typography and tertiary foreground styling.
- Do not change settings, fan control, authorization, or process behavior.

## Validation

- Unit-test normal, missing, and whitespace-only version values.
- Build the release app and installer as version 1.0.12.

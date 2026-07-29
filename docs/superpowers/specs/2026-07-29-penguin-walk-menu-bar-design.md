# PenguinFan Walking Menu Bar Icon Design

## Goal

Make the PenguinFan menu bar icon feel friendlier by animating a walking
penguin whose pace reflects the Mac's measured fan speed.

## Behavior

- Use the average `actualRPM` of all available fan readings.
- Show a still, relaxed penguin when no sensor reading is available.
- Animate four vector poses: left step, center, right step, center.
- Add a small body bounce and alternating head tilt to make the walk readable
  at menu bar size.
- Keep the icon monochrome and mark every frame as an AppKit template image so
  it remains legible in light and dark menu bars.

## Speed Mapping

Animation speed is calculated continuously from the measured average RPM:

| Average fan speed | Frame interval |
| --- | --- |
| 1,500 RPM or lower | 0.90 seconds |
| 3,000 RPM | 0.55 seconds |
| 4,500 RPM | 0.32 seconds |
| 6,000 RPM or higher | 0.18 seconds |

Values between these points are linearly interpolated. The interval is clamped
to 0.18...0.90 seconds to avoid distracting motion and excessive menu bar
updates.

## Architecture

`PenguinMenuBarIcon` renders deterministic vector frames from a walking phase.
It has no dependency on sensor collection or fan control.

`PenguinWalkAnimator` owns a lightweight main-run-loop timer, reads the latest
snapshot through a callback, calculates the average actual RPM, advances the
walking phase, and provides the next image through an update callback.

`FanControllerAppDelegate` starts the animator after creating the status item
and stops it during application termination. The existing runtime controller,
SMC writes, safety state machine, and settings remain unchanged.

## Failure Handling

- Missing or empty fan readings produce the stationary frame.
- Invalid or negative RPM values are ignored.
- Timer updates occur only on the main thread.
- Animation never changes fan targets or control mode.

## Testing

- Verify the four generated images are 18-point template images.
- Verify average-RPM calculation ignores invalid values.
- Verify frame intervals at the lower, middle, and upper RPM boundaries.
- Verify interpolation remains within the defined interval range.
- Build the release app and visually confirm the icon updates in the menu bar.

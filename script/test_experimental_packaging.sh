#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/LaunchDaemons/com.local.PenguinFan.experimental.agent.plist"
BUILD="$ROOT/script/build_and_run.sh"
INSTALLER="$ROOT/script/build_installer.sh"

[[ -f "$PLIST" ]] || {
  echo "FAIL: experimental LaunchDaemon plist is missing" >&2
  exit 1
}

/usr/bin/plutil -lint "$PLIST" >/dev/null
[[ "$(/usr/bin/plutil -extract Label raw -o - "$PLIST")" == \
  "com.local.PenguinFan.experimental.agent" ]]
[[ "$(/usr/bin/plutil -extract BundleProgram raw -o - "$PLIST")" == \
  "Contents/Helpers/FanControllerAgent" ]]
[[ "$(/usr/bin/plutil -extract ProcessType raw -o - "$PLIST")" == \
  "Interactive" ]]
[[ "$(/usr/libexec/PlistBuddy \
  -c "Print :MachServices:com.local.PenguinFan.experimental.agent" \
  "$PLIST")" == "true" ]]

/bin/bash -n "$BUILD"
/bin/bash -n "$INSTALLER"
/usr/bin/grep -q -- "--experimental-helper" "$BUILD"
/usr/bin/grep -q -- "--experimental-helper" "$INSTALLER"
/usr/bin/grep -q "PenguinFan Experimental.app" "$BUILD"
/usr/bin/grep -q "PenguinFan-Experimental-1.1.0.pkg" "$INSTALLER"
/usr/bin/grep -q "com.local.PenguinFan.experimental" "$BUILD"
/usr/bin/grep -q \
  'HELPER_LABEL="com.local.PenguinFan.experimental.agent"' "$BUILD"
/usr/bin/grep -q '\$CONTENTS/Library/LaunchDaemons' "$BUILD"

if /usr/bin/grep -q "/bin/rm -rf.*PenguinFan.app" "$INSTALLER"; then
  echo "FAIL: installer may remove stable PenguinFan.app" >&2
  exit 1
fi

printf "Task 6 packaging contract checks passed.\n"

#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.3}"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  printf 'Invalid version: %s\n' "$VERSION" >&2
  exit 64
fi

FAN_CONTROLLER_BUNDLE_ID="com.local.M2MaxFanController" \
  "$ROOT/script/build_and_run.sh" --verify

APP="$ROOT/dist-1.0.3/FanController.app"
PKG_ROOT="$ROOT/.build/installer-root-1.0.3"
DESTINATION="$PKG_ROOT/Applications/FanController.app"
OUTPUT_DIR="$ROOT/installer"
PACKAGE="$OUTPUT_DIR/FanController-$VERSION.pkg"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications" "$OUTPUT_DIR"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc "$APP" "$DESTINATION"
find "$PKG_ROOT" -name '._*' -delete
rm -f "$PACKAGE"

COPYFILE_DISABLE=1 /usr/bin/pkgbuild \
  --identifier com.local.M2MaxFanController \
  --version "$VERSION" \
  --root "$PKG_ROOT" \
  --install-location / \
  "$PACKAGE"

if ! /usr/sbin/pkgutil --payload-files "$PACKAGE" \
  | /usr/bin/grep -Eq '^\.?/?Applications/FanController\.app/Contents/MacOS/FanControllerApp$'; then
  printf 'Installer payload verification failed.\n' >&2
  exit 1
fi

printf 'Built installer: %s\n' "$PACKAGE"

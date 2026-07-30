#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.0.12"
VERSION_WAS_SET=0
EXPERIMENTAL_HELPER=0

for argument in "$@"; do
  case "$argument" in
    --experimental-helper)
      EXPERIMENTAL_HELPER=1
      ;;
    [0-9]*)
      if [[ "$VERSION_WAS_SET" -eq 1 ]] \
        || [[ ! "$argument" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
        printf 'Invalid version: %s\n' "$argument" >&2
        exit 64
      fi
      VERSION="$argument"
      VERSION_WAS_SET=1
      ;;
    *)
      printf 'Unknown option: %s\n' "$argument" >&2
      exit 64
      ;;
  esac
done

if [[ "$EXPERIMENTAL_HELPER" -eq 1 ]]; then
  if [[ "$VERSION_WAS_SET" -eq 1 ]]; then
    echo "Experimental helper version is fixed at 1.1.0." >&2
    exit 64
  fi
  VERSION="1.1.0"
  APP_BUNDLE_NAME="PenguinFan Experimental.app"
  PACKAGE_NAME="PenguinFan-Experimental-1.1.0.pkg"
  PACKAGE_IDENTIFIER="com.local.PenguinFan.experimental"
  "$ROOT/script/build_and_run.sh" \
    --experimental-helper --verify
else
  APP_BUNDLE_NAME="PenguinFan.app"
  PACKAGE_NAME="PenguinFan-$VERSION.pkg"
  PACKAGE_IDENTIFIER="com.local.M2MaxFanController"
  FAN_CONTROLLER_BUNDLE_ID="$PACKAGE_IDENTIFIER" \
  FAN_CONTROLLER_VERSION="$VERSION" \
    "$ROOT/script/build_and_run.sh" --verify
fi

APP="$ROOT/dist-$VERSION/$APP_BUNDLE_NAME"
PKG_ROOT="$ROOT/.build/installer-root-$VERSION-$EXPERIMENTAL_HELPER"
DESTINATION="$PKG_ROOT/Applications/$APP_BUNDLE_NAME"
OUTPUT_DIR="$ROOT/installer"
PACKAGE="$OUTPUT_DIR/$PACKAGE_NAME"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications" "$OUTPUT_DIR"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc "$APP" "$DESTINATION"
find "$PKG_ROOT" -name '._*' -delete
rm -f "$PACKAGE"

PKGBUILD_ARGUMENTS=(
  --identifier "$PACKAGE_IDENTIFIER"
  --version "$VERSION"
  --root "$PKG_ROOT"
  --install-location /
)

if [[ "$EXPERIMENTAL_HELPER" -eq 0 ]]; then
  PKGBUILD_ARGUMENTS+=(--scripts "$ROOT/script/package_scripts")
fi

COPYFILE_DISABLE=1 /usr/bin/pkgbuild \
  "${PKGBUILD_ARGUMENTS[@]}" \
  "$PACKAGE"

ESCAPED_APP_NAME="${APP_BUNDLE_NAME//./\\.}"
if ! /usr/sbin/pkgutil --payload-files "$PACKAGE" \
  | /usr/bin/grep -Eq \
    "^\\.?/?Applications/$ESCAPED_APP_NAME/Contents/MacOS/FanControllerApp$"; then
  printf 'Installer payload verification failed.\n' >&2
  exit 1
fi

if [[ "$EXPERIMENTAL_HELPER" -eq 1 ]]; then
  if ! /usr/sbin/pkgutil --payload-files "$PACKAGE" \
    | /usr/bin/grep -Eq \
      "^\\.?/?Applications/$ESCAPED_APP_NAME/Contents/Library/LaunchDaemons/com\\.local\\.PenguinFan\\.experimental\\.agent\\.plist$"; then
    printf 'Installer is missing the experimental LaunchDaemon plist.\n' >&2
    exit 1
  fi

  if /usr/sbin/pkgutil --payload-files "$PACKAGE" \
    | /usr/bin/grep -Eq \
      '^\.?/?Applications/(PenguinFan\.app|FanController\.app)(/|$)'; then
    printf 'Experimental installer contains a stable or legacy app.\n' >&2
    exit 1
  fi
else
  if /usr/sbin/pkgutil --payload-files "$PACKAGE" \
    | /usr/bin/grep -Eq '^\.?/?Applications/FanController\.app'; then
    printf 'Installer unexpectedly contains the legacy app bundle.\n' >&2
    exit 1
  fi
fi

printf 'Built installer: %s\n' "$PACKAGE"

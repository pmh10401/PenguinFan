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
  OUTPUT_DIR="$ROOT/installer"
  FINAL_PACKAGE="$OUTPUT_DIR/$PACKAGE_NAME"
  LOCK_FILE="$OUTPUT_DIR/.PenguinFan-Experimental-1.1.0.publication.lock"
  LOCK_WAIT_SECONDS="${PENGUINFAN_TASK6_LOCK_WAIT_SECONDS:-120}"
  LOCK_OWNED=0
  PUBLICATION_STATE_MANAGED=0
  PUBLISHED=0
  STAGING_DIR=""
  PRIOR_VALID_PACKAGE=""

  if [[ ! "$LOCK_WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]] \
    || [[ "$LOCK_WAIT_SECONDS" -gt 600 ]]; then
    echo "Lock wait must be an integer from 1 through 600 seconds." >&2
    exit 64
  fi

  mkdir -p "$OUTPUT_DIR"

  cleanup_experimental_publication() {
    local result=$?

    trap - EXIT INT TERM
    if [[ "$LOCK_OWNED" -eq 1 ]] \
      && [[ "$(/bin/cat "$LOCK_FILE" 2>/dev/null || true)" == "$$" ]]; then
      if [[ "$PUBLICATION_STATE_MANAGED" -eq 1 ]] \
        && [[ "$PUBLISHED" -ne 1 ]]; then
        /bin/rm -f "$FINAL_PACKAGE"
        if [[ -n "$PRIOR_VALID_PACKAGE" ]] \
          && [[ -f "$PRIOR_VALID_PACKAGE" ]]; then
          /bin/mv "$PRIOR_VALID_PACKAGE" "$FINAL_PACKAGE"
        fi
      fi
      /bin/rm -f "$LOCK_FILE"
    fi

    if [[ -n "$STAGING_DIR" ]]; then
      /bin/rm -rf "$STAGING_DIR"
    fi
    exit "$result"
  }

  trap cleanup_experimental_publication EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  LOCK_DEADLINE=$((SECONDS + LOCK_WAIT_SECONDS))
  while ! /usr/bin/shlock -p "$$" -f "$LOCK_FILE" 2>/dev/null; do
    if [[ "$SECONDS" -ge "$LOCK_DEADLINE" ]]; then
      printf 'Timed out waiting %s seconds for package publication lock.\n' \
        "$LOCK_WAIT_SECONDS" >&2
      exit 73
    fi
    /bin/sleep 0.1
  done
  LOCK_OWNED=1

  if [[ -n "${PENGUINFAN_TASK6_HOLD_LOCK_SECONDS:-}" ]]; then
    /bin/sleep "$PENGUINFAN_TASK6_HOLD_LOCK_SECONDS"
  fi

  STAGING_DIR="$(/usr/bin/mktemp -d \
    "$OUTPUT_DIR/.PenguinFan-Experimental-1.1.0.staging.XXXXXX")"
  PRIOR_VALID_PACKAGE="$STAGING_DIR/prior-validated-package.pkg"

  if [[ -f "$FINAL_PACKAGE" ]]; then
    if "$ROOT/script/validate_experimental_package.sh" \
      "$FINAL_PACKAGE" >/dev/null; then
      /bin/mv "$FINAL_PACKAGE" "$PRIOR_VALID_PACKAGE"
    else
      /bin/rm -f "$FINAL_PACKAGE"
      PRIOR_VALID_PACKAGE=""
    fi
  else
    PRIOR_VALID_PACKAGE=""
  fi
  PUBLICATION_STATE_MANAGED=1

  FAN_CONTROLLER_OUTPUT_ROOT="$STAGING_DIR" \
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

if [[ "$EXPERIMENTAL_HELPER" -eq 1 ]]; then
  APP="$STAGING_DIR/dist-$VERSION/$APP_BUNDLE_NAME"
  PKG_ROOT="$STAGING_DIR/installer-root"
  PACKAGE="$STAGING_DIR/$PACKAGE_NAME"
else
  APP="$ROOT/dist-$VERSION/$APP_BUNDLE_NAME"
  PKG_ROOT="$ROOT/.build/installer-root-$VERSION-$EXPERIMENTAL_HELPER"
  OUTPUT_DIR="$ROOT/installer"
  PACKAGE="$OUTPUT_DIR/$PACKAGE_NAME"
fi

DESTINATION="$PKG_ROOT/Applications/$APP_BUNDLE_NAME"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications" "$OUTPUT_DIR"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc "$APP" "$DESTINATION"
/usr/bin/xattr -cr "$PKG_ROOT"
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
  INFO_PLIST="$APP/Contents/Info.plist"
  DAEMON_PLIST="$APP/Contents/Library/LaunchDaemons/com.local.PenguinFan.experimental.agent.plist"
  MAIN_EXECUTABLE="$APP/Contents/MacOS/FanControllerApp"
  HELPER_EXECUTABLE="$APP/Contents/Helpers/FanControllerAgent"

  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw \
    -o - "$INFO_PLIST")" == "com.local.PenguinFan.experimental" ]] \
    || { echo "Experimental bundle identifier verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw \
    -o - "$INFO_PLIST")" == "1.1.0" ]] \
    || { echo "Experimental version verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract CFBundleVersion raw \
    -o - "$INFO_PLIST")" == "14" ]] \
    || { echo "Experimental build verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract CFBundleDisplayName raw \
    -o - "$INFO_PLIST")" == "PenguinFan Experimental" ]] \
    || { echo "Experimental display name verification failed." >&2; exit 1; }

  [[ -f "$DAEMON_PLIST" ]] \
    || { echo "Embedded LaunchDaemon plist is missing." >&2; exit 1; }
  /usr/bin/plutil -lint "$DAEMON_PLIST" >/dev/null
  [[ "$(/usr/bin/plutil -extract Label raw \
    -o - "$DAEMON_PLIST")" == \
    "com.local.PenguinFan.experimental.agent" ]] \
    || { echo "LaunchDaemon label verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract BundleProgram raw \
    -o - "$DAEMON_PLIST")" == \
    "Contents/Helpers/FanControllerAgent" ]] \
    || { echo "LaunchDaemon BundleProgram verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract ProcessType raw \
    -o - "$DAEMON_PLIST")" == "Interactive" ]] \
    || { echo "LaunchDaemon ProcessType verification failed." >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy \
    -c "Print :MachServices:com.local.PenguinFan.experimental.agent" \
    "$DAEMON_PLIST")" == "true" ]] \
    || { echo "LaunchDaemon MachServices verification failed." >&2; exit 1; }

  [[ -x "$MAIN_EXECUTABLE" ]] \
    || { echo "Experimental main executable is missing." >&2; exit 1; }
  [[ -x "$HELPER_EXECUTABLE" ]] \
    || { echo "Experimental helper executable is missing." >&2; exit 1; }
  /usr/bin/codesign --verify --strict "$HELPER_EXECUTABLE"
  /usr/bin/codesign --verify --strict "$MAIN_EXECUTABLE"
  /usr/bin/codesign --verify --deep --strict "$APP"

  HELPER_SIGNATURE="$(/usr/bin/codesign -dvv \
    "$HELPER_EXECUTABLE" 2>&1)"
  MAIN_SIGNATURE="$(/usr/bin/codesign -dvv \
    "$MAIN_EXECUTABLE" 2>&1)"
  APP_SIGNATURE="$(/usr/bin/codesign -dvv "$APP" 2>&1)"
  [[ "$HELPER_SIGNATURE" == *"Signature=adhoc"* ]] \
    || { echo "Experimental helper is not ad-hoc signed." >&2; exit 1; }
  [[ "$MAIN_SIGNATURE" == \
    *"Identifier=com.local.PenguinFan.experimental"* ]] \
    || { echo "Signed main identifier verification failed." >&2; exit 1; }
  [[ "$MAIN_SIGNATURE" == *"Signature=adhoc"* ]] \
    || { echo "Experimental main is not ad-hoc signed." >&2; exit 1; }
  [[ "$APP_SIGNATURE" == \
    *"Identifier=com.local.PenguinFan.experimental"* ]] \
    || { echo "Signed app identifier verification failed." >&2; exit 1; }
  [[ "$APP_SIGNATURE" == *"Signature=adhoc"* ]] \
    || { echo "Experimental app is not ad-hoc signed." >&2; exit 1; }

  PAYLOAD="$(/usr/sbin/pkgutil --payload-files "$PACKAGE")"
  FOUND_MAIN=0
  FOUND_DAEMON_PLIST=0
  while IFS= read -r payload_line; do
    normalized="${payload_line#./}"
    case "$normalized" in
      .|._Applications|Applications|Applications/|\
      "Applications/._PenguinFan Experimental.app"|\
      "Applications/PenguinFan Experimental.app"|\
      "Applications/PenguinFan Experimental.app/"*)
        ;;
      *)
        printf 'Unexpected experimental payload path: %s\n' \
          "$payload_line" >&2
        exit 1
        ;;
    esac

    [[ "$normalized" != \
      "Applications/PenguinFan Experimental.app/Contents/MacOS/FanControllerApp" ]] \
      || FOUND_MAIN=1
    [[ "$normalized" != \
      "Applications/PenguinFan Experimental.app/Contents/Library/LaunchDaemons/com.local.PenguinFan.experimental.agent.plist" ]] \
      || FOUND_DAEMON_PLIST=1
  done <<< "$PAYLOAD"

  [[ "$FOUND_MAIN" -eq 1 ]] \
    || { echo "Installer payload is missing the main executable." >&2; exit 1; }
  [[ "$FOUND_DAEMON_PLIST" -eq 1 ]] \
    || { echo "Installer payload is missing the LaunchDaemon plist." >&2; exit 1; }

  "$ROOT/script/validate_experimental_package.sh" "$PACKAGE"

  if [[ "${PENGUINFAN_TASK6_FAIL_BEFORE_PUBLISH:-0}" == "1" ]]; then
    echo "Injected Task 6 failure before package publication." >&2
    exit 75
  fi

  /bin/mv "$PACKAGE" "$FINAL_PACKAGE"
  PUBLISHED=1
  PACKAGE="$FINAL_PACKAGE"

  if [[ -n "${PENGUINFAN_TASK6_HOLD_AFTER_PUBLISH_SECONDS:-}" ]]; then
    /bin/sleep "$PENGUINFAN_TASK6_HOLD_AFTER_PUBLISH_SECONDS"
  fi
else
  if /usr/sbin/pkgutil --payload-files "$PACKAGE" \
    | /usr/bin/grep -Eq '^\.?/?Applications/FanController\.app'; then
    printf 'Installer unexpectedly contains the legacy app bundle.\n' >&2
    exit 1
  fi
fi

printf 'Built installer: %s\n' "$PACKAGE"

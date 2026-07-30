#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.0.12"
VERSION_WAS_SET=0
EXPERIMENTAL_HELPER=0
SIGNING_IDENTITY=""
EXPECTED_TEAM_IDENTIFIER="UUUQNVQ67B"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --experimental-helper)
      EXPERIMENTAL_HELPER=1
      ;;
    --signing-identity)
      [[ "$#" -ge 2 ]] && [[ -n "$2" ]] \
        || { echo "Missing value for --signing-identity." >&2; exit 64; }
      SIGNING_IDENTITY="$2"
      shift
      ;;
    [0-9]*)
      if [[ "$VERSION_WAS_SET" -eq 1 ]] \
        || [[ ! "$1" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
        printf 'Invalid version: %s\n' "$1" >&2
        exit 64
      fi
      VERSION="$1"
      VERSION_WAS_SET=1
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 64
      ;;
  esac
  shift
done

validate_signing_identity() {
  local identity="$1"
  local expected_team="$2"
  local probe_dir
  local probe
  local metadata
  local authority
  local team_identifier

  if [[ -z "$identity" ]] || [[ "$identity" == "-" ]]; then
    echo "Experimental packaging requires an explicit non-ad-hoc signing identity." >&2
    return 1
  fi
  if ! /usr/bin/security find-identity -v -p codesigning \
    | /usr/bin/awk -F'"' -v expected="$identity" \
      '$2 == expected { found = 1 } END { exit(found ? 0 : 1) }'; then
    printf 'Signing identity is unavailable or invalid: %s\n' "$identity" >&2
    return 1
  fi

  mkdir -p "$ROOT/.build"
  probe_dir="$(/usr/bin/mktemp -d \
    "$ROOT/.build/experimental-signing-probe.XXXXXX")"
  probe="$probe_dir/probe"
  /bin/cp /usr/bin/true "$probe"
  if ! /usr/bin/codesign --force --options runtime --timestamp=none \
    --sign "$identity" "$probe" >/dev/null 2>&1 \
    || ! /usr/bin/codesign --verify --strict "$probe" >/dev/null 2>&1; then
    /bin/rm -rf "$probe_dir"
    printf 'Signing identity failed a signed probe: %s\n' "$identity" >&2
    return 1
  fi

  metadata="$(/usr/bin/codesign -dvvv "$probe" 2>&1)"
  authority="$(printf '%s\n' "$metadata" \
    | /usr/bin/awk -F= '/^Authority=/{sub(/^Authority=/, ""); print; exit}')"
  team_identifier="$(printf '%s\n' "$metadata" \
    | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
  /bin/rm -rf "$probe_dir"

  # Failure-only test injection: this can make a valid identity fail policy,
  # but cannot make an invalid or wrong-Team identity pass.
  if [[ "${PENGUINFAN_TASK7_TEST_FORCE_TEAM_MISMATCH:-0}" == "1" ]]; then
    team_identifier="TASK7-FORCED-MISMATCH"
  fi

  if [[ "$metadata" == *"Signature=adhoc"* ]] \
    || [[ "$authority" != "$identity" ]] \
    || [[ -z "$team_identifier" ]] \
    || [[ "$team_identifier" != "$expected_team" ]] \
    || [[ "$metadata" != *"(runtime)"* ]]; then
    printf 'Signing identity metadata did not match the experimental policy: %s\n' \
      "$identity" >&2
    return 1
  fi
}

if [[ "$EXPERIMENTAL_HELPER" -eq 1 ]]; then
  if [[ "$VERSION_WAS_SET" -eq 1 ]]; then
    echo "Experimental helper version is fixed at 1.1.0." >&2
    exit 64
  fi
  VERSION="1.1.0"
  APP_BUNDLE_NAME="PenguinFan Experimental.app"
  PACKAGE_NAME="PenguinFan-Experimental-1.1.0.pkg"
  PACKAGE_IDENTIFIER="com.local.PenguinFan.experimental"
  OUTPUT_DIR="${PENGUINFAN_EXPERIMENTAL_OUTPUT_DIR:-$ROOT/installer}"
  FINAL_PACKAGE="$OUTPUT_DIR/$PACKAGE_NAME"
  LOCK_FILE="$OUTPUT_DIR/.PenguinFan-Experimental-1.1.0.publication.lock"
  LOCK_WAIT_SECONDS="${PENGUINFAN_TASK6_LOCK_WAIT_SECONDS:-120}"
  LOCK_OWNED=0
  PUBLICATION_STATE_MANAGED=0
  PRIOR_PACKAGE_KNOWN_GOOD=0
  NEW_PACKAGE_KNOWN_GOOD=0
  PUBLISHED=0
  STAGING_DIR=""
  PRIOR_VALID_PACKAGE=""

  validate_signing_identity \
    "$SIGNING_IDENTITY" "$EXPECTED_TEAM_IDENTIFIER" || exit 64

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
        if [[ "$PRIOR_PACKAGE_KNOWN_GOOD" -eq 1 ]] \
          && [[ -f "$PRIOR_VALID_PACKAGE" ]]; then
          /bin/rm -f "$FINAL_PACKAGE"
          /bin/mv "$PRIOR_VALID_PACKAGE" "$FINAL_PACKAGE"
        elif [[ "$PRIOR_PACKAGE_KNOWN_GOOD" -eq 1 ]] \
          && [[ -f "$FINAL_PACKAGE" ]]; then
          # Signal arrived before the atomic backup move. The known-good
          # package is already at the final path and must remain untouched.
          :
        elif [[ "$NEW_PACKAGE_KNOWN_GOOD" -eq 1 ]] \
          && [[ -f "$FINAL_PACKAGE" ]]; then
          # Signal arrived after publishing a fully validated new package but
          # before the success marker. Preserve that known-good package.
          :
        else
          /bin/rm -f "$FINAL_PACKAGE"
        fi
      fi

      if [[ -n "$STAGING_DIR" ]]; then
        /bin/rm -rf "$STAGING_DIR"
      fi
      /bin/rm -f "$LOCK_FILE"
    elif [[ -n "$STAGING_DIR" ]]; then
      # Unique staging is process-owned and safe to remove without touching
      # shared publication state.
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
      "$FINAL_PACKAGE" \
      "$SIGNING_IDENTITY" \
      "$EXPECTED_TEAM_IDENTIFIER" >/dev/null; then
      PRIOR_PACKAGE_KNOWN_GOOD=1
      PUBLICATION_STATE_MANAGED=1

      if [[ "${PENGUINFAN_TASK6_SIGNAL_BEFORE_BACKUP_MOVE:-0}" == "1" ]]; then
        /bin/kill -TERM "$$"
      fi

      /bin/mv "$FINAL_PACKAGE" "$PRIOR_VALID_PACKAGE"

      if [[ "${PENGUINFAN_TASK6_SIGNAL_AFTER_BACKUP_MOVE:-0}" == "1" ]]; then
        /bin/kill -TERM "$$"
      fi
    else
      PUBLICATION_STATE_MANAGED=1
      /bin/rm -f "$FINAL_PACKAGE"
      PRIOR_VALID_PACKAGE=""
    fi
  else
    PUBLICATION_STATE_MANAGED=1
    PRIOR_VALID_PACKAGE=""
  fi

  FAN_CONTROLLER_OUTPUT_ROOT="$STAGING_DIR" \
    "$ROOT/script/build_and_run.sh" \
      --experimental-helper \
      --signing-identity "$SIGNING_IDENTITY" \
      --verify
else
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "--signing-identity is supported only with --experimental-helper." >&2
    exit 64
  fi
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

  verify_identity_signature() {
    local item="$1"
    local metadata
    local authority
    local team_identifier

    metadata="$(/usr/bin/codesign -dvvv "$item" 2>&1)"
    authority="$(printf '%s\n' "$metadata" \
      | /usr/bin/awk -F= '/^Authority=/{sub(/^Authority=/, ""); print; exit}')"
    team_identifier="$(printf '%s\n' "$metadata" \
      | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    [[ "$metadata" != *"Signature=adhoc"* ]] \
      || { echo "Experimental item is ad-hoc signed: $item" >&2; exit 1; }
    [[ "$authority" == "$SIGNING_IDENTITY" ]] \
      || { echo "Signing Authority verification failed: $item" >&2; exit 1; }
    [[ -n "$team_identifier" ]] \
      && [[ "$team_identifier" == "$EXPECTED_TEAM_IDENTIFIER" ]] \
      || { echo "TeamIdentifier verification failed: $item" >&2; exit 1; }
    [[ "$metadata" == *"(runtime)"* ]] \
      || { echo "Hardened runtime verification failed: $item" >&2; exit 1; }
  }

  MAIN_SIGNATURE="$(/usr/bin/codesign -dvvv \
    "$MAIN_EXECUTABLE" 2>&1)"
  APP_SIGNATURE="$(/usr/bin/codesign -dvvv "$APP" 2>&1)"
  verify_identity_signature "$HELPER_EXECUTABLE"
  verify_identity_signature "$MAIN_EXECUTABLE"
  verify_identity_signature "$APP"
  [[ "$MAIN_SIGNATURE" == \
    *"Identifier=com.local.PenguinFan.experimental"* ]] \
    || { echo "Signed main identifier verification failed." >&2; exit 1; }
  [[ "$APP_SIGNATURE" == \
    *"Identifier=com.local.PenguinFan.experimental"* ]] \
    || { echo "Signed app identifier verification failed." >&2; exit 1; }

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

  "$ROOT/script/validate_experimental_package.sh" \
    "$PACKAGE" "$SIGNING_IDENTITY" "$EXPECTED_TEAM_IDENTIFIER"
  NEW_PACKAGE_KNOWN_GOOD=1

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

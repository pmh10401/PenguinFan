#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.0.12"
VERSION_WAS_SET=0
PRIVILEGED_HELPER=0
SIGNING_IDENTITY=""
EXPECTED_TEAM_IDENTIFIER="UUUQNVQ67B"
CURRENT_UID="$(/usr/bin/id -u)"
TRUSTED_TEST_OUTPUT_PARENT="/private/tmp/com.local.PenguinFan.task7-tests-$CURRENT_UID"

path_has_safe_lexical_form() {
  local path="$1"
  local remainder
  local segment

  [[ -n "$path" ]] && [[ "$path" == /* ]] && [[ "$path" != "/" ]] \
    && [[ "$path" != */ ]] || return 1

  remainder="${path#/}"
  while [[ -n "$remainder" ]]; do
    segment="${remainder%%/*}"
    [[ -n "$segment" ]] && [[ "$segment" != "." ]] \
      && [[ "$segment" != ".." ]] || return 1
    if [[ "$remainder" == */* ]]; then
      remainder="${remainder#*/}"
    else
      remainder=""
    fi
  done
}

path_has_no_symlink_components() {
  local path="$1"
  local remainder="${path#/}"
  local segment
  local current=""

  path_has_safe_lexical_form "$path" || return 1
  while [[ -n "$remainder" ]]; do
    segment="${remainder%%/*}"
    current="$current/$segment"
    [[ ! -L "$current" ]] || return 1
    if [[ -e "$current" ]] && [[ ! -d "$current" ]] \
      && [[ "$remainder" == */* ]]; then
      return 1
    fi
    if [[ "$remainder" == */* ]]; then
      remainder="${remainder#*/}"
    else
      remainder=""
    fi
  done
}

validate_secure_owned_directory() {
  local path="$1"
  local owner
  local mode
  local canonical

  path_has_no_symlink_components "$path" || return 1
  [[ -d "$path" ]] && [[ ! -L "$path" ]] || return 1
  owner="$(/usr/bin/stat -f '%u' "$path" 2>/dev/null)" || return 1
  mode="$(/usr/bin/stat -f '%OLp' "$path" 2>/dev/null)" || return 1
  [[ "$owner" == "$CURRENT_UID" ]] && [[ "$mode" == "700" ]] || return 1
  canonical="$(cd "$path" 2>/dev/null && /bin/pwd -P)" || return 1
  [[ "$canonical" == "$path" ]]
}

validate_test_output_root() {
  local output_root="$1"
  local test_root="${PENGUINFAN_TASK7_TEST_ROOT:-}"
  local token="${PENGUINFAN_TASK7_TEST_ROOT_TOKEN:-}"
  local marker
  local marker_owner
  local marker_mode

  [[ "${PENGUINFAN_TASK7_ALLOW_TEST_OUTPUT_ROOT:-0}" == "1" ]] \
    || { echo "Release output overrides are disabled." >&2; return 1; }
  [[ -n "$test_root" ]] && [[ -n "$token" ]] \
    || { echo "A process-owned Task 7 test root is required." >&2; return 1; }
  [[ "$token" =~ ^[A-Za-z0-9-]{16,128}$ ]] \
    || { echo "Invalid Task 7 test-root token." >&2; return 1; }

  validate_secure_owned_directory "$TRUSTED_TEST_OUTPUT_PARENT" \
    || { echo "Task 7 trusted test parent is not secure." >&2; return 1; }
  case "$test_root" in
    "$TRUSTED_TEST_OUTPUT_PARENT"/*)
      ;;
    *)
      echo "Task 7 test root is outside the trusted parent." >&2
      return 1
      ;;
  esac
  [[ "${test_root#"$TRUSTED_TEST_OUTPUT_PARENT"/}" != */* ]] \
    || { echo "Task 7 test root must be a direct unique child." >&2; return 1; }
  validate_secure_owned_directory "$test_root" \
    || { echo "Task 7 test root is not a secure owned directory." >&2; return 1; }

  marker="$test_root/.penguinfan-task7-owner"
  [[ -f "$marker" ]] && [[ ! -L "$marker" ]] \
    || { echo "Task 7 test-root owner marker is missing." >&2; return 1; }
  marker_owner="$(/usr/bin/stat -f '%u' "$marker" 2>/dev/null)" || return 1
  marker_mode="$(/usr/bin/stat -f '%OLp' "$marker" 2>/dev/null)" || return 1
  [[ "$marker_owner" == "$CURRENT_UID" ]] && [[ "$marker_mode" == "600" ]] \
    && [[ "$(/bin/cat "$marker")" == "$token" ]] \
    || { echo "Task 7 test-root owner marker is invalid." >&2; return 1; }

  path_has_no_symlink_components "$output_root" \
    || { echo "Release output root has an unsafe path." >&2; return 1; }
  case "$output_root" in
    "$test_root"/*)
      ;;
    *)
      echo "Release output root is outside the process-owned test root." >&2
      return 1
      ;;
  esac
  if [[ -e "$output_root" ]] || [[ -L "$output_root" ]]; then
    [[ -d "$output_root" ]] && [[ ! -L "$output_root" ]] \
      || { echo "Release output root is not a directory." >&2; return 1; }
  fi
}

assert_safe_mutation_path() {
  local path="$1"
  local allowed_root="$2"

  path_has_no_symlink_components "$path" \
    || { printf 'Refusing unsafe mutation path: %s\n' "$path" >&2; return 1; }
  [[ "$path" != "$ROOT" ]] && [[ "$path" != "/Applications" ]] \
    && [[ "$path" != "$allowed_root" ]] \
    || { printf 'Refusing protected mutation path: %s\n' "$path" >&2; return 1; }
  case "$path" in
    "$allowed_root"/*)
      ;;
    *)
      printf 'Refusing mutation outside allowed root: %s\n' "$path" >&2
      return 1
      ;;
  esac
}

safe_remove_file() {
  local path="$1"
  local allowed_root="$2"

  assert_safe_mutation_path "$path" "$allowed_root" || return 1
  /bin/rm -f -- "$path"
}

safe_remove_tree() {
  local path="$1"
  local allowed_root="$2"

  assert_safe_mutation_path "$path" "$allowed_root" || return 1
  /bin/rm -rf -- "$path"
}

safe_move() {
  local source="$1"
  local destination="$2"
  local allowed_root="$3"

  assert_safe_mutation_path "$source" "$allowed_root" || return 1
  assert_safe_mutation_path "$destination" "$allowed_root" || return 1
  /bin/mv -- "$source" "$destination"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --privileged-helper)
      PRIVILEGED_HELPER=1
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
    echo "Release packaging requires an explicit non-ad-hoc signing identity." >&2
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
    "$ROOT/.build/release-signing-probe.XXXXXX")"
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
    printf 'Signing identity metadata did not match the release policy: %s\n' \
      "$identity" >&2
    return 1
  fi
}

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  if [[ "$VERSION_WAS_SET" -eq 1 ]]; then
    echo "Release helper version is fixed at 1.1.0." >&2
    exit 64
  fi
  VERSION="1.1.0"
  APP_BUNDLE_NAME="PenguinFan.app"
  PACKAGE_NAME="PenguinFan-1.1.0.pkg"
  PACKAGE_IDENTIFIER="com.local.PenguinFan"
  OUTPUT_DIR="$ROOT/installer"
  OUTPUT_DIR_IS_TEST=0
  FINAL_PACKAGE="$OUTPUT_DIR/$PACKAGE_NAME"
  LOCK_FILE="$OUTPUT_DIR/.PenguinFan-1.1.0.publication.lock"
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

  if [[ "${PENGUINFAN_RELEASE_OUTPUT_DIR+x}" == "x" ]]; then
    validate_test_output_root "${PENGUINFAN_RELEASE_OUTPUT_DIR:-}" \
      || exit 64
    OUTPUT_DIR="$PENGUINFAN_RELEASE_OUTPUT_DIR"
    OUTPUT_DIR_IS_TEST=1
    FINAL_PACKAGE="$OUTPUT_DIR/$PACKAGE_NAME"
    LOCK_FILE="$OUTPUT_DIR/.PenguinFan-1.1.0.publication.lock"
  fi

  if [[ ! "$LOCK_WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]] \
    || [[ "$LOCK_WAIT_SECONDS" -gt 600 ]]; then
    echo "Lock wait must be an integer from 1 through 600 seconds." >&2
    exit 64
  fi

  path_has_no_symlink_components "$OUTPUT_DIR" \
    || { echo "Release output directory has an unsafe path." >&2; exit 64; }
  mkdir -p "$OUTPUT_DIR"
  if [[ "$OUTPUT_DIR_IS_TEST" -eq 1 ]]; then
    validate_test_output_root "$OUTPUT_DIR" || exit 64
  fi
  assert_safe_mutation_path "$FINAL_PACKAGE" "$OUTPUT_DIR" || exit 64
  assert_safe_mutation_path "$LOCK_FILE" "$OUTPUT_DIR" || exit 64

  cleanup_release_publication() {
    local result=$?
    local cleanup_ok=1

    trap - EXIT INT TERM
    if [[ "$LOCK_OWNED" -eq 1 ]] \
      && [[ "$(/bin/cat "$LOCK_FILE" 2>/dev/null || true)" == "$$" ]]; then
      if [[ "$PUBLICATION_STATE_MANAGED" -eq 1 ]] \
        && [[ "$PUBLISHED" -ne 1 ]]; then
        if [[ "$PRIOR_PACKAGE_KNOWN_GOOD" -eq 1 ]] \
          && [[ -f "$PRIOR_VALID_PACKAGE" ]]; then
          safe_remove_file "$FINAL_PACKAGE" "$OUTPUT_DIR" || cleanup_ok=0
          if [[ "$cleanup_ok" -eq 1 ]]; then
            safe_move "$PRIOR_VALID_PACKAGE" "$FINAL_PACKAGE" "$OUTPUT_DIR" \
              || cleanup_ok=0
          fi
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
          safe_remove_file "$FINAL_PACKAGE" "$OUTPUT_DIR" || cleanup_ok=0
        fi
      fi

      if [[ "$cleanup_ok" -eq 1 ]] && [[ -n "$STAGING_DIR" ]] \
        && [[ -e "$STAGING_DIR" ]]; then
        safe_remove_tree "$STAGING_DIR" "$OUTPUT_DIR" || cleanup_ok=0
      fi
      if [[ "$cleanup_ok" -eq 1 ]] \
        && [[ "$(/bin/cat "$LOCK_FILE" 2>/dev/null || true)" == "$$" ]]; then
        safe_remove_file "$LOCK_FILE" "$OUTPUT_DIR" || cleanup_ok=0
      fi
    elif [[ -n "$STAGING_DIR" ]]; then
      # Unique staging is process-owned and safe to remove without touching
      # shared publication state.
      safe_remove_tree "$STAGING_DIR" "$OUTPUT_DIR" || cleanup_ok=0
    fi
    if [[ "$cleanup_ok" -ne 1 ]]; then
      echo "Package publication cleanup failed; publication lock retained." >&2
      result=1
    fi
    exit "$result"
  }

  trap cleanup_release_publication EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  [[ ! -L "$LOCK_FILE" ]] \
    || { echo "Package publication lock path is a symlink." >&2; exit 73; }
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
    "$OUTPUT_DIR/.PenguinFan-1.1.0.staging.XXXXXX")"
  PRIOR_VALID_PACKAGE="$STAGING_DIR/prior-validated-package.pkg"

  if [[ -L "$FINAL_PACKAGE" ]]; then
    echo "Final package path is a symlink." >&2
    exit 1
  elif [[ -f "$FINAL_PACKAGE" ]]; then
    if "$ROOT/script/validate_release_package.sh" \
      "$FINAL_PACKAGE" \
      "$SIGNING_IDENTITY" \
      "$EXPECTED_TEAM_IDENTIFIER" >/dev/null; then
      PRIOR_PACKAGE_KNOWN_GOOD=1
      PUBLICATION_STATE_MANAGED=1

      if [[ "${PENGUINFAN_TASK6_SIGNAL_BEFORE_BACKUP_MOVE:-0}" == "1" ]]; then
        /bin/kill -TERM "$$"
      fi

      safe_move "$FINAL_PACKAGE" "$PRIOR_VALID_PACKAGE" "$OUTPUT_DIR"

      if [[ "${PENGUINFAN_TASK6_SIGNAL_AFTER_BACKUP_MOVE:-0}" == "1" ]]; then
        /bin/kill -TERM "$$"
      fi
    else
      PUBLICATION_STATE_MANAGED=1
      safe_remove_file "$FINAL_PACKAGE" "$OUTPUT_DIR"
      PRIOR_VALID_PACKAGE=""
    fi
  elif [[ -e "$FINAL_PACKAGE" ]]; then
    echo "Final package path is not a regular file." >&2
    exit 1
  else
    PUBLICATION_STATE_MANAGED=1
    PRIOR_VALID_PACKAGE=""
  fi

  if [[ "$OUTPUT_DIR_IS_TEST" -eq 1 ]]; then
    FAN_CONTROLLER_OUTPUT_ROOT="$STAGING_DIR" \
      "$ROOT/script/build_and_run.sh" \
        --privileged-helper \
        --signing-identity "$SIGNING_IDENTITY" \
        --verify
  else
    "$ROOT/script/build_and_run.sh" \
      --privileged-helper \
      --signing-identity "$SIGNING_IDENTITY" \
      --verify
  fi
else
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "--signing-identity is supported only with --privileged-helper." >&2
    exit 64
  fi
  APP_BUNDLE_NAME="PenguinFan.app"
  PACKAGE_NAME="PenguinFan-$VERSION.pkg"
  PACKAGE_IDENTIFIER="com.local.M2MaxFanController"
  FAN_CONTROLLER_BUNDLE_ID="$PACKAGE_IDENTIFIER" \
  FAN_CONTROLLER_VERSION="$VERSION" \
    "$ROOT/script/build_and_run.sh" --verify
fi

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  if [[ "$OUTPUT_DIR_IS_TEST" -eq 1 ]]; then
    APP="$STAGING_DIR/dist-$VERSION/$APP_BUNDLE_NAME"
  else
    APP="$ROOT/dist-$VERSION/$APP_BUNDLE_NAME"
  fi
  PKG_ROOT="$STAGING_DIR/installer-root"
  PACKAGE="$STAGING_DIR/$PACKAGE_NAME"
else
  APP="$ROOT/dist-$VERSION/$APP_BUNDLE_NAME"
  PKG_ROOT="$ROOT/.build/installer-root-$VERSION-$PRIVILEGED_HELPER"
  OUTPUT_DIR="$ROOT/installer"
  PACKAGE="$OUTPUT_DIR/$PACKAGE_NAME"
fi

DESTINATION="$PKG_ROOT/Applications/$APP_BUNDLE_NAME"

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  safe_remove_tree "$PKG_ROOT" "$OUTPUT_DIR"
else
  rm -rf "$PKG_ROOT"
fi
mkdir -p "$PKG_ROOT/Applications" "$OUTPUT_DIR"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc "$APP" "$DESTINATION"
/usr/bin/xattr -cr "$PKG_ROOT"
find "$PKG_ROOT" -name '._*' -delete
if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  safe_remove_file "$PACKAGE" "$OUTPUT_DIR"
else
  rm -f "$PACKAGE"
fi

PKGBUILD_ARGUMENTS=(
  --identifier "$PACKAGE_IDENTIFIER"
  --version "$VERSION"
  --root "$PKG_ROOT"
  --install-location /
)

if [[ "$PRIVILEGED_HELPER" -eq 0 ]]; then
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

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  INFO_PLIST="$APP/Contents/Info.plist"
  DAEMON_PLIST="$APP/Contents/Library/LaunchDaemons/com.local.PenguinFan.agent.plist"
  MAIN_EXECUTABLE="$APP/Contents/MacOS/FanControllerApp"
  HELPER_EXECUTABLE="$APP/Contents/Helpers/FanControllerAgent"

  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw \
    -o - "$INFO_PLIST")" == "com.local.PenguinFan" ]] \
    || { echo "Release bundle identifier verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw \
    -o - "$INFO_PLIST")" == "1.1.0" ]] \
    || { echo "Release version verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract CFBundleVersion raw \
    -o - "$INFO_PLIST")" == "14" ]] \
    || { echo "Release build verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract CFBundleDisplayName raw \
    -o - "$INFO_PLIST")" == "PenguinFan" ]] \
    || { echo "Release display name verification failed." >&2; exit 1; }

  [[ -f "$DAEMON_PLIST" ]] \
    || { echo "Embedded LaunchDaemon plist is missing." >&2; exit 1; }
  /usr/bin/plutil -lint "$DAEMON_PLIST" >/dev/null
  [[ "$(/usr/bin/plutil -extract Label raw \
    -o - "$DAEMON_PLIST")" == \
    "com.local.PenguinFan.agent" ]] \
    || { echo "LaunchDaemon label verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract BundleProgram raw \
    -o - "$DAEMON_PLIST")" == \
    "Contents/Helpers/FanControllerAgent" ]] \
    || { echo "LaunchDaemon BundleProgram verification failed." >&2; exit 1; }
  [[ "$(/usr/bin/plutil -extract ProcessType raw \
    -o - "$DAEMON_PLIST")" == "Interactive" ]] \
    || { echo "LaunchDaemon ProcessType verification failed." >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy \
    -c "Print :MachServices:com.local.PenguinFan.agent" \
    "$DAEMON_PLIST")" == "true" ]] \
    || { echo "LaunchDaemon MachServices verification failed." >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy \
    -c "Print :SpawnConstraint:signing-identifier" \
    "$DAEMON_PLIST")" == \
    "com.local.PenguinFan.agent" ]] \
    || { echo "SpawnConstraint signing identifier failed." >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy \
    -c "Print :SpawnConstraint:team-identifier" \
    "$DAEMON_PLIST")" == "$EXPECTED_TEAM_IDENTIFIER" ]] \
    || { echo "SpawnConstraint TeamIdentifier failed." >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy \
    -c "Print :SpawnConstraint:validation-category" \
    "$DAEMON_PLIST")" == "3" ]] \
    || { echo "SpawnConstraint validation category failed." >&2; exit 1; }

  [[ -x "$MAIN_EXECUTABLE" ]] \
    || { echo "Release main executable is missing." >&2; exit 1; }
  [[ -x "$HELPER_EXECUTABLE" ]] \
    || { echo "Release helper executable is missing." >&2; exit 1; }
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
      || { echo "Release item is ad-hoc signed: $item" >&2; exit 1; }
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
  HELPER_SIGNATURE="$(/usr/bin/codesign -dvvv \
    "$HELPER_EXECUTABLE" 2>&1)"
  [[ "$HELPER_SIGNATURE" == \
    *"Identifier=com.local.PenguinFan.agent"* ]] \
    || { echo "Signed helper identifier verification failed." >&2; exit 1; }
  [[ "$MAIN_SIGNATURE" == \
    *"Identifier=com.local.PenguinFan"* ]] \
    || { echo "Signed main identifier verification failed." >&2; exit 1; }
  [[ "$APP_SIGNATURE" == \
    *"Identifier=com.local.PenguinFan"* ]] \
    || { echo "Signed app identifier verification failed." >&2; exit 1; }

  PAYLOAD="$(/usr/sbin/pkgutil --payload-files "$PACKAGE")"
  FOUND_MAIN=0
  FOUND_DAEMON_PLIST=0
  while IFS= read -r payload_line; do
    normalized="${payload_line#./}"
    case "$normalized" in
      .|._Applications|Applications|Applications/|\
      "Applications/._PenguinFan.app"|\
      "Applications/PenguinFan.app"|\
      "Applications/PenguinFan.app/"*)
        ;;
      *)
        printf 'Unexpected release payload path: %s\n' \
          "$payload_line" >&2
        exit 1
        ;;
    esac

    [[ "$normalized" != \
      "Applications/PenguinFan.app/Contents/MacOS/FanControllerApp" ]] \
      || FOUND_MAIN=1
    [[ "$normalized" != \
      "Applications/PenguinFan.app/Contents/Library/LaunchDaemons/com.local.PenguinFan.agent.plist" ]] \
      || FOUND_DAEMON_PLIST=1
  done <<< "$PAYLOAD"

  [[ "$FOUND_MAIN" -eq 1 ]] \
    || { echo "Installer payload is missing the main executable." >&2; exit 1; }
  [[ "$FOUND_DAEMON_PLIST" -eq 1 ]] \
    || { echo "Installer payload is missing the LaunchDaemon plist." >&2; exit 1; }

  "$ROOT/script/validate_release_package.sh" \
    "$PACKAGE" "$SIGNING_IDENTITY" "$EXPECTED_TEAM_IDENTIFIER"
  NEW_PACKAGE_KNOWN_GOOD=1

  if [[ "${PENGUINFAN_TASK6_FAIL_BEFORE_PUBLISH:-0}" == "1" ]]; then
    echo "Injected Task 6 failure before package publication." >&2
    exit 75
  fi

  safe_move "$PACKAGE" "$FINAL_PACKAGE" "$OUTPUT_DIR"
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

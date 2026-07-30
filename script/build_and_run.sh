#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="release"
SHOULD_LAUNCH=1
SHOW_LOGS=0
TELEMETRY=0
PRIVILEGED_HELPER=0
SIGNING_IDENTITY=""
EXPECTED_TEAM_IDENTIFIER="UUUQNVQ67B"
BUNDLE_ID="${FAN_CONTROLLER_BUNDLE_ID:-com.local.M2MaxFanController.dev}"
APP_VERSION="${FAN_CONTROLLER_VERSION:-1.0.12}"
BUILD_NUMBER="${FAN_CONTROLLER_BUILD_NUMBER:-13}"
APP_DISPLAY_NAME="PenguinFan"
APP_BUNDLE_NAME="PenguinFan.app"
HELPER_LABEL="com.local.PenguinFan.agent"
HELPER_PLIST_NAME="$HELPER_LABEL.plist"
CURRENT_UID="$(/usr/bin/id -u)"
TRUSTED_TEST_OUTPUT_PARENT="/private/tmp/com.local.PenguinFan.task7-tests-$CURRENT_UID"

validate_signing_identity() {
  local identity="$1"
  local expected_team="$2"
  local probe_dir
  local probe
  local metadata
  local authority
  local team_identifier

  if [[ -z "$identity" ]] || [[ "$identity" == "-" ]]; then
    echo "Release builds require an explicit non-ad-hoc signing identity." >&2
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
    "$ROOT/.build/release-app-signing-probe.XXXXXX")"
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

directory_snapshot_sha() {
  local directory="$1"

  (
    cd "$directory"
    COPYFILE_DISABLE=1 /usr/bin/tar -cf - .
  ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    run)
      SHOULD_LAUNCH=1
      ;;
    --debug)
      CONFIGURATION="debug"
      ;;
    --logs)
      SHOW_LOGS=1
      ;;
    --telemetry)
      TELEMETRY=1
      ;;
    --verify)
      SHOULD_LAUNCH=0
      ;;
    --privileged-helper)
      PRIVILEGED_HELPER=1
      ;;
    --signing-identity)
      [[ "$#" -ge 2 ]] && [[ -n "$2" ]] \
        || { echo "Missing value for --signing-identity." >&2; exit 64; }
      SIGNING_IDENTITY="$2"
      shift
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 64
      ;;
  esac
  shift
done

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  if [[ -z "$SIGNING_IDENTITY" ]] || [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Release builds require an explicit non-ad-hoc signing identity." >&2
    exit 64
  fi
  BUNDLE_ID="com.local.PenguinFan"
  APP_VERSION="1.1.0"
  BUILD_NUMBER="14"
  APP_DISPLAY_NAME="PenguinFan"
  APP_BUNDLE_NAME="PenguinFan.app"
  validate_signing_identity \
    "$SIGNING_IDENTITY" "$EXPECTED_TEAM_IDENTIFIER" || exit 64
elif [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "--signing-identity is supported only with --privileged-helper." >&2
  exit 64
fi

OUTPUT_ROOT="$ROOT"
OUTPUT_ROOT_IS_TEST=0
if [[ "$PRIVILEGED_HELPER" -eq 1 ]] \
  && [[ "${FAN_CONTROLLER_OUTPUT_ROOT+x}" == "x" ]]; then
  validate_test_output_root "${FAN_CONTROLLER_OUTPUT_ROOT:-}" || exit 64
  OUTPUT_ROOT="$FAN_CONTROLLER_OUTPUT_ROOT"
  OUTPUT_ROOT_IS_TEST=1
fi

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/XcodeModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
export FAN_CONTROLLER_TELEMETRY="$TELEMETRY"

mkdir -p "$CLANG_MODULE_CACHE_PATH"
cd "$ROOT"

/usr/bin/xcrun swift build \
  -c "$CONFIGURATION" \
  --product FanControllerApp
/usr/bin/xcrun swift build \
  -c "$CONFIGURATION" \
  --product FanControllerAgent
/usr/bin/xcrun swift build \
  -c "$CONFIGURATION" \
  --product FanDiagnostics

BIN_PATH="$(/usr/bin/xcrun swift build \
  -c "$CONFIGURATION" \
  --show-bin-path)"

APP_STAGING_ROOT=""
FINAL_APP=""
APP_BACKUP=""
APP_LOCK_FILE=""
APP_LOCK_OWNED=0
APP_PUBLICATION_MANAGED=0
APP_PUBLICATION_COMMITTED=0
PRIOR_APP_PRESENT=0
PRIOR_APP_SHA=""
APP_AT_FINAL=0
APP_LOCK_WAIT_SECONDS="${PENGUINFAN_TASK7_APP_LOCK_WAIT_SECONDS:-120}"

app_lock_is_owned() {
  [[ "$APP_LOCK_OWNED" -eq 1 ]] \
    && [[ -f "$APP_LOCK_FILE" ]] \
    && [[ ! -L "$APP_LOCK_FILE" ]] \
    && [[ "$(/bin/cat "$APP_LOCK_FILE" 2>/dev/null || true)" == "$$" ]]
}

restore_prior_app_under_lock() {
  app_lock_is_owned \
    || { echo "Cannot restore app without owning its publication lock." >&2; return 1; }

  if [[ "$PRIOR_APP_PRESENT" -eq 1 ]]; then
    if [[ -e "$APP_BACKUP" ]] || [[ -L "$APP_BACKUP" ]]; then
      if [[ -e "$FINAL_APP" ]] || [[ -L "$FINAL_APP" ]]; then
        safe_remove_tree "$FINAL_APP" "$OUTPUT_ROOT" || return 1
      fi
      safe_move "$APP_BACKUP" "$FINAL_APP" "$OUTPUT_ROOT" || return 1
    elif [[ ! -d "$FINAL_APP" ]] || [[ -L "$FINAL_APP" ]]; then
      echo "Prior app is unavailable for rollback." >&2
      return 1
    fi

    [[ "$(directory_snapshot_sha "$FINAL_APP")" == "$PRIOR_APP_SHA" ]] \
      || { echo "Restored prior app is not byte-identical." >&2; return 1; }
  elif [[ -e "$FINAL_APP" ]] || [[ -L "$FINAL_APP" ]]; then
    safe_remove_tree "$FINAL_APP" "$OUTPUT_ROOT" || return 1
  fi
}

cleanup_release_app_publication() {
  local result=$?
  local cleanup_ok=1

  trap - EXIT INT TERM
  if app_lock_is_owned; then
    if [[ "$APP_PUBLICATION_MANAGED" -eq 1 ]] \
      && [[ "$APP_PUBLICATION_COMMITTED" -ne 1 ]]; then
      restore_prior_app_under_lock || cleanup_ok=0
    fi
    if [[ "$cleanup_ok" -eq 1 ]] && [[ -n "$APP_STAGING_ROOT" ]] \
      && [[ -e "$APP_STAGING_ROOT" ]]; then
      safe_remove_tree "$APP_STAGING_ROOT" "$OUTPUT_ROOT" || cleanup_ok=0
    fi
    if [[ "$cleanup_ok" -eq 1 ]] && app_lock_is_owned; then
      assert_safe_mutation_path "$APP_LOCK_FILE" "$OUTPUT_ROOT" \
        && /bin/rm -f -- "$APP_LOCK_FILE" || cleanup_ok=0
    fi
  elif [[ -n "$APP_STAGING_ROOT" ]] && [[ -e "$APP_STAGING_ROOT" ]]; then
    # Unique staging is process-owned; a non-owner never touches final state.
    safe_remove_tree "$APP_STAGING_ROOT" "$OUTPUT_ROOT" || cleanup_ok=0
  fi
  if [[ "$cleanup_ok" -ne 1 ]]; then
    echo "App publication cleanup failed; publication lock retained." >&2
    result=1
  fi
  exit "$result"
}

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  if [[ ! "$APP_LOCK_WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]] \
    || [[ "$APP_LOCK_WAIT_SECONDS" -gt 600 ]]; then
    echo "App lock wait must be an integer from 1 through 600 seconds." >&2
    exit 64
  fi
  path_has_no_symlink_components "$OUTPUT_ROOT" \
    || { echo "Release output root has an unsafe path." >&2; exit 64; }
  mkdir -p "$OUTPUT_ROOT"
  if [[ "$OUTPUT_ROOT_IS_TEST" -eq 1 ]]; then
    validate_test_output_root "$OUTPUT_ROOT" || exit 64
  fi
  FINAL_APP="$OUTPUT_ROOT/dist-$APP_VERSION/$APP_BUNDLE_NAME"
  APP_LOCK_FILE="$OUTPUT_ROOT/.PenguinFan-1.1.0.app-publication.lock"
  assert_safe_mutation_path "$FINAL_APP" "$OUTPUT_ROOT" || exit 64
  assert_safe_mutation_path "$APP_LOCK_FILE" "$OUTPUT_ROOT" || exit 64
  APP_STAGING_ROOT="$(/usr/bin/mktemp -d \
    "$OUTPUT_ROOT/.PenguinFan-1.1.0.app-staging.XXXXXX")"
  APP_BACKUP="$APP_STAGING_ROOT/prior-app"
  APP="$APP_STAGING_ROOT/$APP_BUNDLE_NAME"
  trap cleanup_release_app_publication EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
else
  APP="$OUTPUT_ROOT/dist-$APP_VERSION/$APP_BUNDLE_NAME"
fi

CONTENTS="$APP/Contents"
ICON_SOURCE="$ROOT/Assets/PenguinFanIcon.png"
HELPER_PLIST_SOURCE="$ROOT/Resources/LaunchDaemons/$HELPER_PLIST_NAME"

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  safe_remove_tree "$APP" "$APP_STAGING_ROOT"
else
  rm -rf "$APP"
fi
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$CONTENTS/Resources"
install -m 0755 "$BIN_PATH/FanControllerApp" \
  "$CONTENTS/MacOS/FanControllerApp"
install -m 0755 "$BIN_PATH/FanControllerAgent" \
  "$CONTENTS/Helpers/FanControllerAgent"
install -m 0755 "$BIN_PATH/FanDiagnostics" \
  "$CONTENTS/Helpers/FanDiagnostics"

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  if [[ ! -f "$HELPER_PLIST_SOURCE" ]]; then
    echo "Missing LaunchDaemon plist: $HELPER_PLIST_SOURCE" >&2
    exit 1
  fi
  mkdir -p "$CONTENTS/Library/LaunchDaemons"
  install -m 0644 "$HELPER_PLIST_SOURCE" \
    "$CONTENTS/Library/LaunchDaemons/$HELPER_PLIST_NAME"
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing app icon: $ICON_SOURCE" >&2
  exit 1
fi

ICONSET="$ROOT/.build/PenguinFan.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/PenguinFan.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ko</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>FanControllerApp</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>CFBundleIconFile</key>
  <string>PenguinFan</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

xattr -cr "$APP"
if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  SIGNING_ARGUMENTS=(
    --force
    --options runtime
    --timestamp=none
    --sign "$SIGNING_IDENTITY"
  )
else
  SIGNING_ARGUMENTS=(--force --sign -)
fi

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  /usr/bin/codesign "${SIGNING_ARGUMENTS[@]}" \
    --identifier "$HELPER_LABEL" \
    "$CONTENTS/Helpers/FanControllerAgent"
else
  /usr/bin/codesign "${SIGNING_ARGUMENTS[@]}" \
    "$CONTENTS/Helpers/FanControllerAgent"
fi
/usr/bin/codesign "${SIGNING_ARGUMENTS[@]}" \
  "$CONTENTS/Helpers/FanDiagnostics"
/usr/bin/codesign "${SIGNING_ARGUMENTS[@]}" \
  "$CONTENTS/MacOS/FanControllerApp"
/usr/bin/codesign "${SIGNING_ARGUMENTS[@]}" "$APP"

test -x "$CONTENTS/MacOS/FanControllerApp"
test -x "$CONTENTS/Helpers/FanControllerAgent"
test -x "$CONTENTS/Helpers/FanDiagnostics"
/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null
/usr/bin/codesign --verify --strict "$CONTENTS/Helpers/FanControllerAgent"
/usr/bin/codesign --verify --strict "$CONTENTS/MacOS/FanControllerApp"
/usr/bin/codesign --verify --deep --strict "$APP"

if [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw \
  -o - "$CONTENTS/Info.plist")" != "$BUNDLE_ID" ]]; then
  echo "Bundle identifier verification failed." >&2
  exit 1
fi

for signed_item in \
  "$CONTENTS/Helpers/FanControllerAgent" \
  "$CONTENTS/MacOS/FanControllerApp" \
  "$APP"; do
  SIGNATURE_INFO="$(/usr/bin/codesign -dvvv "$signed_item" 2>&1)"
  if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
    if [[ "$SIGNATURE_INFO" == *"Signature=adhoc"* ]]; then
      echo "Release item is ad-hoc signed: $signed_item" >&2
      exit 1
    fi
    SIGNED_TEAM_IDENTIFIER="$(printf '%s\n' "$SIGNATURE_INFO" \
      | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    SIGNED_AUTHORITY="$(printf '%s\n' "$SIGNATURE_INFO" \
      | /usr/bin/awk -F= '/^Authority=/{sub(/^Authority=/, ""); print; exit}')"
    if [[ "$SIGNED_TEAM_IDENTIFIER" != "$EXPECTED_TEAM_IDENTIFIER" ]]; then
      echo "Unexpected TeamIdentifier for $signed_item" >&2
      exit 1
    fi
    if [[ "$SIGNED_AUTHORITY" != "$SIGNING_IDENTITY" ]]; then
      echo "Unexpected signing Authority for $signed_item" >&2
      exit 1
    fi
    if [[ "$signed_item" == "$CONTENTS/Helpers/FanControllerAgent" ]] \
      && [[ "$SIGNATURE_INFO" != *"Identifier=$HELPER_LABEL"* ]]; then
      echo "Unexpected signing identifier for $signed_item" >&2
      exit 1
    fi
    if [[ "$SIGNATURE_INFO" != *"(runtime)"* ]]; then
      echo "Hardened runtime is missing for $signed_item" >&2
      exit 1
    fi
  elif [[ "$SIGNATURE_INFO" != *"Signature=adhoc"* ]]; then
    echo "Expected ad-hoc signature: $signed_item" >&2
    exit 1
  fi
done

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  EMBEDDED_PLIST="$CONTENTS/Library/LaunchDaemons/$HELPER_PLIST_NAME"
  /usr/bin/plutil -lint "$EMBEDDED_PLIST" >/dev/null

  if [[ "$(/usr/bin/plutil -extract Label raw \
    -o - "$EMBEDDED_PLIST")" != "$HELPER_LABEL" ]]; then
    echo "LaunchDaemon label verification failed." >&2
    exit 1
  fi

  BUNDLE_PROGRAM="$(/usr/bin/plutil -extract BundleProgram raw \
    -o - "$EMBEDDED_PLIST")"
  if [[ "$BUNDLE_PROGRAM" != "Contents/Helpers/FanControllerAgent" ]] \
    || [[ ! -x "$APP/$BUNDLE_PROGRAM" ]]; then
    echo "LaunchDaemon BundleProgram verification failed." >&2
    exit 1
  fi

  if [[ "$(/usr/libexec/PlistBuddy \
    -c "Print :MachServices:$HELPER_LABEL" \
    "$EMBEDDED_PLIST")" != "true" ]]; then
    echo "LaunchDaemon MachServices verification failed." >&2
    exit 1
  fi
  if [[ "$(/usr/libexec/PlistBuddy \
    -c "Print :SpawnConstraint:signing-identifier" \
    "$EMBEDDED_PLIST")" != "$HELPER_LABEL" ]] \
    || [[ "$(/usr/libexec/PlistBuddy \
      -c "Print :SpawnConstraint:team-identifier" \
      "$EMBEDDED_PLIST")" != "$EXPECTED_TEAM_IDENTIFIER" ]] \
    || [[ "$(/usr/libexec/PlistBuddy \
      -c "Print :SpawnConstraint:validation-category" \
      "$EMBEDDED_PLIST")" != "3" ]]; then
    echo "LaunchDaemon SpawnConstraint verification failed." >&2
    exit 1
  fi
fi

if [[ "$PRIVILEGED_HELPER" -eq 1 ]]; then
  LOCK_DEADLINE=$((SECONDS + APP_LOCK_WAIT_SECONDS))
  while ! /usr/bin/shlock -p "$$" -f "$APP_LOCK_FILE" 2>/dev/null; do
    if [[ "$SECONDS" -ge "$LOCK_DEADLINE" ]]; then
      printf 'Timed out waiting %s seconds for app publication lock.\n' \
        "$APP_LOCK_WAIT_SECONDS" >&2
      exit 73
    fi
    /bin/sleep 0.1
  done
  APP_LOCK_OWNED=1
  app_lock_is_owned \
    || { echo "App publication lock ownership verification failed." >&2; exit 73; }

  if [[ -n "${PENGUINFAN_TASK7_HOLD_APP_LOCK_SECONDS:-}" ]]; then
    /bin/sleep "$PENGUINFAN_TASK7_HOLD_APP_LOCK_SECONDS"
  fi

  mkdir -p "$(/usr/bin/dirname "$FINAL_APP")"
  if [[ -e "$FINAL_APP" ]] || [[ -L "$FINAL_APP" ]]; then
    [[ -d "$FINAL_APP" ]] && [[ ! -L "$FINAL_APP" ]] \
      || { echo "Existing final app path is unsafe." >&2; exit 1; }
    PRIOR_APP_PRESENT=1
    PRIOR_APP_SHA="$(directory_snapshot_sha "$FINAL_APP")"
  fi
  APP_PUBLICATION_MANAGED=1

  if [[ "${PENGUINFAN_TASK7_FAIL_BEFORE_APP_PUBLISH:-0}" == "1" ]]; then
    echo "Injected Task 7 failure before app publication." >&2
    exit 75
  fi

  if [[ "${PENGUINFAN_TASK7_SIGNAL_BEFORE_APP_BACKUP_MOVE:-0}" == "1" ]]; then
    /bin/kill -TERM "$$"
  fi

  app_lock_is_owned \
    || { echo "Lost app publication lock before backup." >&2; exit 73; }
  if [[ "$PRIOR_APP_PRESENT" -eq 1 ]]; then
    safe_move "$FINAL_APP" "$APP_BACKUP" "$OUTPUT_ROOT"
  fi

  if [[ "${PENGUINFAN_TASK7_SIGNAL_AFTER_APP_BACKUP_MOVE:-0}" == "1" ]]; then
    /bin/kill -TERM "$$"
  fi

  app_lock_is_owned \
    || { echo "Lost app publication lock before publish." >&2; exit 73; }
  safe_move "$APP" "$FINAL_APP" "$OUTPUT_ROOT"
  APP_AT_FINAL=1

  if [[ "${PENGUINFAN_TASK7_SIGNAL_AFTER_APP_PUBLISH:-0}" == "1" ]]; then
    /bin/kill -TERM "$$"
  fi

  APP_PUBLICATION_COMMITTED=1
  APP="$FINAL_APP"
  CONTENTS="$APP/Contents"
  if [[ -n "${PENGUINFAN_TASK7_HOLD_AFTER_APP_PUBLISH_SECONDS:-}" ]]; then
    /bin/sleep "$PENGUINFAN_TASK7_HOLD_AFTER_APP_PUBLISH_SECONDS"
  fi
  app_lock_is_owned \
    || { echo "Lost app publication lock during cleanup." >&2; exit 73; }
  safe_remove_tree "$APP_STAGING_ROOT" "$OUTPUT_ROOT"
  APP_STAGING_ROOT=""
  assert_safe_mutation_path "$APP_LOCK_FILE" "$OUTPUT_ROOT"
  /bin/rm -f -- "$APP_LOCK_FILE"
  APP_LOCK_OWNED=0
  trap - EXIT INT TERM
fi

printf 'Built: %s\n' "$APP"

if [[ "$SHOULD_LAUNCH" -eq 1 ]]; then
  /usr/bin/pkill -x FanControllerApp 2>/dev/null || true
  /usr/bin/open -n "$APP"
fi

if [[ "$SHOW_LOGS" -eq 1 ]]; then
  exec /usr/bin/log stream --style compact \
    --predicate 'process == "FanControllerApp" OR process == "FanControllerAgent"'
fi

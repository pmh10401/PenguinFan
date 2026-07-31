#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISHED_PACKAGE="$ROOT/installer/PenguinFan-1.2.0.pkg"
FINAL_PACKAGE=""
LOCK_FILE=""
HELPER_LABEL="com.local.PenguinFan.agent"
HELPER_PLIST_NAME="$HELPER_LABEL.plist"
EXPECTED_BUNDLE_PROGRAM="Contents/Helpers/FanControllerAgent"
EXPECTED_TEAM_IDENTIFIER="UUUQNVQ67B"
SIGNING_IDENTITY=""
TEST_ROOT=""
TEST_INSTALLER_DIR=""
PUBLISHED_PACKAGE_EXISTED=0
PUBLISHED_PACKAGE_SHA=""
CURRENT_UID="$(/usr/bin/id -u)"
TRUSTED_TEST_OUTPUT_PARENT="/private/tmp/com.local.PenguinFan.task7-tests-$CURRENT_UID"
TEST_ROOT_TOKEN=""

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
}

file_sha() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

directory_snapshot_sha() {
  local artifact="$1"
  local parent
  local name

  parent="$(/usr/bin/dirname "$artifact")"
  name="$(/usr/bin/basename "$artifact")"
  (
    cd "$parent"
    COPYFILE_DISABLE=1 /usr/bin/tar -cf - "$name"
  ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

validate_signing_identity() {
  local identity="$1"
  local expected_team="$2"
  local probe_dir
  local probe
  local metadata
  local authority
  local team_identifier

  if [[ -z "$identity" ]] || [[ "$identity" == "-" ]]; then
    return 1
  fi
  if ! /usr/bin/security find-identity -v -p codesigning \
    | /usr/bin/awk -F'"' -v expected="$identity" \
      '$2 == expected { found = 1 } END { exit(found ? 0 : 1) }'; then
    return 1
  fi

  mkdir -p "$ROOT/.build"
  probe_dir="$(/usr/bin/mktemp -d \
    "$ROOT/.build/task7-test-signing-probe.XXXXXX")"
  probe="$probe_dir/probe"
  /bin/cp /usr/bin/true "$probe"
  if ! /usr/bin/codesign --force --options runtime --timestamp=none \
    --sign "$identity" "$probe" >/dev/null 2>&1 \
    || ! /usr/bin/codesign --verify --strict "$probe" >/dev/null 2>&1; then
    /bin/rm -rf "$probe_dir"
    return 1
  fi

  metadata="$(/usr/bin/codesign -dvvv "$probe" 2>&1)"
  authority="$(printf '%s\n' "$metadata" \
    | /usr/bin/awk -F= '/^Authority=/{sub(/^Authority=/, ""); print; exit}')"
  team_identifier="$(printf '%s\n' "$metadata" \
    | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
  /bin/rm -rf "$probe_dir"

  [[ "$metadata" != *"Signature=adhoc"* ]] \
    && [[ "$authority" == "$identity" ]] \
    && [[ "$team_identifier" == "$expected_team" ]] \
    && [[ "$metadata" == *"(runtime)"* ]]
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --signing-identity)
      [[ "$#" -ge 2 ]] && [[ -n "$2" ]] \
        || fail "missing value for --signing-identity"
      SIGNING_IDENTITY="$2"
      shift
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
  shift
done

[[ -n "$SIGNING_IDENTITY" ]] && [[ "$SIGNING_IDENTITY" != "-" ]] \
  || fail "an explicit non-ad-hoc signing identity is required"

validate_signing_identity \
  "$SIGNING_IDENTITY" "$EXPECTED_TEAM_IDENTIFIER" \
  || fail "supplied signing identity failed the real signed Team policy probe"

if [[ -f "$PUBLISHED_PACKAGE" ]]; then
  PUBLISHED_PACKAGE_EXISTED=1
  PUBLISHED_PACKAGE_SHA="$(file_sha "$PUBLISHED_PACKAGE")"
elif [[ -e "$PUBLISHED_PACKAGE" ]]; then
  fail "published package path is not a regular file"
fi

cleanup_test_state() {
  local result=$?

  trap - EXIT INT TERM
  if [[ -n "$TEST_ROOT" ]]; then
    case "$TEST_ROOT" in
      "$TRUSTED_TEST_OUTPUT_PARENT"/*)
        if [[ -d "$TEST_ROOT" ]] && [[ ! -L "$TEST_ROOT" ]]; then
          /bin/rm -rf "$TEST_ROOT"
        else
          printf 'FAIL: refusing unsafe Task 7 test-root cleanup\n' >&2
          result=1
        fi
        ;;
      *)
        printf 'FAIL: Task 7 test root escaped its trusted parent\n' >&2
        result=1
        ;;
    esac
  fi

  if [[ "$PUBLISHED_PACKAGE_EXISTED" -eq 1 ]]; then
    if [[ ! -f "$PUBLISHED_PACKAGE" ]] \
      || [[ "$(file_sha "$PUBLISHED_PACKAGE")" != "$PUBLISHED_PACKAGE_SHA" ]]; then
      printf 'FAIL: published package changed during isolated tests\n' >&2
      result=1
    fi
  elif [[ -e "$PUBLISHED_PACKAGE" ]]; then
    printf 'FAIL: isolated tests created the published package\n' >&2
    result=1
  fi
  exit "$result"
}

trap cleanup_test_state EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -e "$TRUSTED_TEST_OUTPUT_PARENT" ]] \
  || [[ -L "$TRUSTED_TEST_OUTPUT_PARENT" ]]; then
  [[ -d "$TRUSTED_TEST_OUTPUT_PARENT" ]] \
    && [[ ! -L "$TRUSTED_TEST_OUTPUT_PARENT" ]] \
    && [[ "$(/usr/bin/stat -f '%u' "$TRUSTED_TEST_OUTPUT_PARENT")" == \
      "$CURRENT_UID" ]] \
    && [[ "$(/usr/bin/stat -f '%OLp' "$TRUSTED_TEST_OUTPUT_PARENT")" == \
      "700" ]] \
    || fail "fixed Task 7 test parent is not a secure owned directory"
else
  (
    umask 077
    /bin/mkdir "$TRUSTED_TEST_OUTPUT_PARENT"
  )
fi

TEST_ROOT="$(/usr/bin/mktemp -d \
  "$TRUSTED_TEST_OUTPUT_PARENT/task7-release-packaging.XXXXXX")"
/bin/chmod 700 "$TEST_ROOT"
TEST_ROOT_TOKEN="$(/usr/bin/uuidgen)"
printf '%s\n' "$TEST_ROOT_TOKEN" > "$TEST_ROOT/.penguinfan-task7-owner"
/bin/chmod 600 "$TEST_ROOT/.penguinfan-task7-owner"
TEST_INSTALLER_DIR="$TEST_ROOT/installer"
FINAL_PACKAGE="$TEST_INSTALLER_DIR/PenguinFan-1.2.0.pkg"
LOCK_FILE="$TEST_INSTALLER_DIR/.PenguinFan-1.2.0.publication.lock"

BUILD_COMMAND=(
  /usr/bin/env
  PENGUINFAN_TASK7_ALLOW_TEST_OUTPUT_ROOT=1
  PENGUINFAN_TASK7_TEST_ROOT="$TEST_ROOT"
  PENGUINFAN_TASK7_TEST_ROOT_TOKEN="$TEST_ROOT_TOKEN"
  PENGUINFAN_RELEASE_OUTPUT_DIR="$TEST_INSTALLER_DIR"
  "$ROOT/script/build_installer.sh"
  --privileged-helper
  --signing-identity "$SIGNING_IDENTITY"
)

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1"
}

verify_identity_signature() {
  local item="$1"
  local metadata
  local authority
  local team_identifier
  /usr/bin/codesign --verify --strict "$item"
  metadata="$(/usr/bin/codesign -dvvv "$item" 2>&1)"
  authority="$(printf '%s\n' "$metadata" \
    | /usr/bin/awk -F= '/^Authority=/{sub(/^Authority=/, ""); print; exit}')"
  team_identifier="$(printf '%s\n' "$metadata" \
    | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
  [[ "$metadata" != *"Signature=adhoc"* ]] \
    || fail "ad-hoc signature is forbidden: $item"
  [[ "$authority" == "$SIGNING_IDENTITY" ]] \
    || fail "wrong signing Authority: $item"
  [[ -n "$team_identifier" ]] \
    && [[ "$team_identifier" == "$EXPECTED_TEAM_IDENTIFIER" ]] \
    || fail "wrong or missing TeamIdentifier: $item"
  [[ "$metadata" == *"(runtime)"* ]] \
    || fail "hardened runtime is missing: $item"
}

verify_helper_has_no_fallback_surface() {
  local helper="$1"
  local inspection
  local patterns
  local scan_input
  local scanner_status

  inspection="$(/usr/bin/mktemp \
    "$TEST_ROOT/helper-executable-inspection.XXXXXX")"
  patterns="$(/usr/bin/mktemp \
    "$TEST_ROOT/helper-executable-patterns.XXXXXX")"
  printf '%s\n' \
    'proc_pidpath' \
    'SecStaticCodeCreateWithPath' \
    'SecStaticCodeCheckValidity' \
    'SecStaticCodeCopySigningInformation' \
    'inspectStaticCode' \
    'LiveProcessCodeInspectionError' \
    'StaticCodeIdentity' \
    'acceptsAdHocFallback' \
    'validateAdHocFallback' \
    'adHocFallback' \
    'fallbackRoute' \
    'route=fallback' \
    'route:fallback' > "$patterns"

  if ! /usr/bin/nm "$helper" >"$inspection" 2>&1 \
    || ! /usr/bin/nm -u "$helper" >>"$inspection" 2>&1 \
    || ! /usr/bin/strings -a "$helper" >>"$inspection" 2>&1; then
    /bin/rm -f "$inspection" "$patterns"
    fail "could not inspect packaged helper executable symbols and strings"
  fi

  scan_input="$inspection"
  if [[ "${PENGUINFAN_TASK7_TEST_SCANNER_ERROR:-0}" == "1" ]]; then
    scan_input="$inspection.injected-missing-input"
  fi

  set +e
  LC_ALL=C /usr/bin/grep -aF -i -f "$patterns" -- "$scan_input" >/dev/null
  scanner_status=$?
  set -e

  case "$scanner_status" in
    0)
      /bin/rm -f "$inspection" "$patterns"
      fail "packaged helper executable contains a rejected fallback surface"
      ;;
    1)
      ;;
    *)
      /bin/rm -f "$inspection" "$patterns"
      fail "packaged helper fallback scanner failed to execute or read input"
      ;;
  esac
  /bin/rm -f "$inspection" "$patterns"
}

verify_app() {
  local app="$1"
  local contents="$app/Contents"
  local info="$contents/Info.plist"
  local daemon_plist="$contents/Library/LaunchDaemons/$HELPER_PLIST_NAME"

  [[ -d "$app" ]] || fail "release app is missing"
  [[ "$(plist_value "$info" CFBundleIdentifier)" == \
    "com.local.PenguinFan" ]] || fail "wrong bundle identifier"
  [[ "$(plist_value "$info" CFBundleShortVersionString)" == "1.2.0" ]] \
    || fail "wrong app version"
  [[ "$(plist_value "$info" CFBundleVersion)" == "15" ]] \
    || fail "wrong build number"
  [[ "$(plist_value "$info" CFBundleDisplayName)" == \
    "PenguinFan" ]] || fail "wrong display name"

  [[ -f "$daemon_plist" ]] || fail "embedded LaunchDaemon plist is missing"
  /usr/bin/plutil -lint "$daemon_plist" >/dev/null
  [[ "$(plist_value "$daemon_plist" Label)" == "$HELPER_LABEL" ]] \
    || fail "wrong LaunchDaemon label"
  [[ "$(plist_value "$daemon_plist" BundleProgram)" == \
    "$EXPECTED_BUNDLE_PROGRAM" ]] || fail "wrong BundleProgram"
  [[ "$(plist_value "$daemon_plist" ProcessType)" == "Interactive" ]] \
    || fail "wrong ProcessType"
  [[ "$(/usr/libexec/PlistBuddy \
    -c "Print :MachServices:$HELPER_LABEL" "$daemon_plist")" == "true" ]] \
    || fail "wrong MachServices entry"

  [[ -x "$contents/MacOS/FanControllerApp" ]] \
    || fail "main executable is missing"
  [[ -x "$app/$EXPECTED_BUNDLE_PROGRAM" ]] \
    || fail "helper executable is missing"

  verify_helper_has_no_fallback_surface "$app/$EXPECTED_BUNDLE_PROGRAM"
  verify_identity_signature "$app/$EXPECTED_BUNDLE_PROGRAM"
  verify_identity_signature "$contents/MacOS/FanControllerApp"
  /usr/bin/codesign --verify --deep --strict "$app"
  verify_identity_signature "$app"

  local app_metadata
  app_metadata="$(/usr/bin/codesign -dvvv "$app" 2>&1)"
  [[ "$app_metadata" == *"Identifier=com.local.PenguinFan"* ]] \
    || fail "signed app identifier is wrong"
}

verify_package() {
  local package="$1"
  local expanded
  local expanded_parent
  local payload_line
  local normalized

  [[ -f "$package" ]] || fail "final release package is missing"

  while IFS= read -r payload_line; do
    normalized="${payload_line#./}"
    case "$normalized" in
      .|._Applications|Applications|Applications/|\
      "Applications/._PenguinFan.app"|\
      "Applications/PenguinFan.app"|\
      "Applications/PenguinFan.app/"*)
        ;;
      *)
        fail "unexpected package payload path: $payload_line"
        ;;
    esac
  done < <(/usr/sbin/pkgutil --payload-files "$package")

  if /usr/sbin/pkgutil --payload-files "$package" \
    | /usr/bin/grep -Eq \
      '^\.?/?Applications/(PenguinFan\.app|FanController\.app)(/|$)'; then
    fail "package contains a stable or legacy app path"
  fi

  expanded_parent="$(/usr/bin/mktemp -d \
    "$TEST_ROOT/expanded-package.XXXXXX")"
  expanded="$expanded_parent/expanded"
  /usr/sbin/pkgutil --expand-full "$package" "$expanded"

  [[ -d "$expanded/Payload/Applications/PenguinFan.app" ]] \
    || fail "expanded package is missing the release app"
  [[ ! -e "$expanded/Payload/Applications/FanController.app" ]] \
    || fail "expanded package contains legacy FanController.app"

  verify_app "$expanded/Payload/Applications/PenguinFan.app"
  /bin/rm -rf "$expanded_parent"
}

assert_no_staging_directories() {
  if /usr/bin/find "$TEST_INSTALLER_DIR" -maxdepth 1 -type d \
    -name ".PenguinFan-1.2.0.staging.*" \
    -print -quit | /usr/bin/grep -q .; then
    fail "release staging directory was not cleaned"
  fi
}

wait_for_lock_owner() {
  local expected_pid="$1"
  local attempt
  for attempt in {1..200}; do
    if [[ -f "$LOCK_FILE" ]] \
      && [[ "$(/bin/cat "$LOCK_FILE" 2>/dev/null || true)" == \
        "$expected_pid" ]]; then
      return 0
    fi
    /bin/sleep 0.05
  done
  fail "timed out waiting for publication lock owner $expected_pid"
}

wait_for_published_package() {
  local attempt
  for attempt in {1..200}; do
    [[ ! -f "$FINAL_PACKAGE" ]] || return 0
    /bin/sleep 0.05
  done
  fail "timed out waiting for published package"
}

wait_for_app_lock_owner() {
  local lock_file="$1"
  local expected_pid="$2"
  local attempt
  for attempt in {1..600}; do
    if [[ -f "$lock_file" ]] \
      && [[ "$(/bin/cat "$lock_file" 2>/dev/null || true)" == \
        "$expected_pid" ]]; then
      return 0
    fi
    /bin/sleep 0.05
  done
  fail "timed out waiting for app publication lock owner $expected_pid"
}

wait_for_app_replacement() {
  local app="$1"
  local prior_inode="$2"
  local attempt
  local current_inode

  for attempt in {1..600}; do
    if [[ -d "$app" ]]; then
      current_inode="$(/usr/bin/stat -f '%i' "$app" 2>/dev/null || true)"
      if [[ -n "$current_inode" ]] && [[ "$current_inode" != "$prior_inode" ]]; then
        return 0
      fi
    fi
    /bin/sleep 0.05
  done
  fail "timed out waiting for direct app publication"
}

assert_no_app_staging_directories() {
  local output_root="$1"
  if /usr/bin/find "$output_root" -maxdepth 1 -type d \
    -name ".PenguinFan-1.2.0.app-staging.*" \
    -print -quit | /usr/bin/grep -q .; then
    fail "release app staging directory was not cleaned"
  fi
}

mkdir -p "$TEST_INSTALLER_DIR"

# The rejected PID/static-code fallback must not remain in the source.
if /usr/bin/grep -Eq \
  'proc_pidpath|SecStaticCodeCreateWithPath|SecStaticCodeCheckValidity|SecStaticCodeCopySigningInformation|inspectStaticCode|LiveProcessCodeInspectionError|StaticCodeIdentity|acceptsAdHocFallback|validateAdHocFallback|adHocFallback|fallbackRoute|route[=:]fallback' \
  "$ROOT/Sources/FanControllerAgent/XPCClientValidator.swift"; then
  fail "unsafe XPC client fallback symbols remain"
fi

# Missing, ad-hoc, and unavailable identities must fail before the final
# artifact can be deleted or replaced.
printf "identity gate sentinel\n" > "$FINAL_PACKAGE"
IDENTITY_GATE_SHA="$(file_sha "$FINAL_PACKAGE")"
for invalid_identity in "" "-" "Missing Signing Identity"; do
  INVALID_COMMAND=(
    /usr/bin/env
    PENGUINFAN_TASK7_ALLOW_TEST_OUTPUT_ROOT=1
    PENGUINFAN_TASK7_TEST_ROOT="$TEST_ROOT"
    PENGUINFAN_TASK7_TEST_ROOT_TOKEN="$TEST_ROOT_TOKEN"
    PENGUINFAN_RELEASE_OUTPUT_DIR="$TEST_INSTALLER_DIR"
    "$ROOT/script/build_installer.sh"
    --privileged-helper
  )
  if [[ -n "$invalid_identity" ]]; then
    INVALID_COMMAND+=(--signing-identity "$invalid_identity")
  fi
  if "${INVALID_COMMAND[@]}"; then
    fail "invalid signing identity unexpectedly succeeded"
  fi
  [[ -f "$FINAL_PACKAGE" ]] \
    && [[ "$(file_sha "$FINAL_PACKAGE")" == "$IDENTITY_GATE_SHA" ]] \
    || fail "invalid signing identity changed the final artifact"
done

if PENGUINFAN_TASK7_TEST_FORCE_TEAM_MISMATCH=1 \
  "${BUILD_COMMAND[@]}"; then
  fail "wrong-Team signing identity unexpectedly succeeded"
fi
[[ -f "$FINAL_PACKAGE" ]] \
  && [[ "$(file_sha "$FINAL_PACKAGE")" == "$IDENTITY_GATE_SHA" ]] \
  || fail "wrong-Team identity changed the final artifact"
/bin/rm -f "$FINAL_PACKAGE"

# Both legacy output environment seams reject by default. Even with the
# explicit gate, unsafe, traversing, symlinked, protected, and out-of-root
# paths must fail before any destructive operation.
OVERRIDE_SENTINEL="$TEST_ROOT/adversarial-target/sentinel"
mkdir -p "$(/usr/bin/dirname "$OVERRIDE_SENTINEL")"
printf 'adversarial path sentinel\n' > "$OVERRIDE_SENTINEL"
OVERRIDE_SENTINEL_SHA="$(file_sha "$OVERRIDE_SENTINEL")"
mkdir -p "$TEST_ROOT/symlink-target"
/bin/ln -s "$TEST_ROOT/symlink-target" "$TEST_ROOT/symlink-component"
/bin/ln -s "$TEST_ROOT/symlink-target" "$TEST_ROOT/final-symlink"

if /usr/bin/env \
  -u PENGUINFAN_TASK7_ALLOW_TEST_OUTPUT_ROOT \
  -u PENGUINFAN_TASK7_TEST_ROOT \
  -u PENGUINFAN_TASK7_TEST_ROOT_TOKEN \
  PENGUINFAN_RELEASE_OUTPUT_DIR="$TEST_ROOT/default-rejected-installer" \
  "$ROOT/script/build_installer.sh" \
    --privileged-helper \
    --signing-identity "$SIGNING_IDENTITY"; then
  fail "installer output override was accepted without the explicit test gate"
fi

if /usr/bin/env \
  -u PENGUINFAN_TASK7_ALLOW_TEST_OUTPUT_ROOT \
  -u PENGUINFAN_TASK7_TEST_ROOT \
  -u PENGUINFAN_TASK7_TEST_ROOT_TOKEN \
  FAN_CONTROLLER_OUTPUT_ROOT="$TEST_ROOT/default-rejected-app" \
  "$ROOT/script/build_and_run.sh" \
    --privileged-helper \
    --signing-identity "$SIGNING_IDENTITY" \
    --verify; then
  fail "app output override was accepted without the explicit test gate"
fi

UNSAFE_OUTPUT_PATHS=(
  ""
  "/"
  "$ROOT"
  "/Applications"
  "$TEST_ROOT/safe/../escape"
  "$TEST_ROOT/symlink-component/child"
  "$TEST_ROOT/final-symlink"
  "$TRUSTED_TEST_OUTPUT_PARENT/outside-process-root"
)
for unsafe_output in "${UNSAFE_OUTPUT_PATHS[@]}"; do
  if /usr/bin/env \
    PENGUINFAN_TASK7_ALLOW_TEST_OUTPUT_ROOT=1 \
    PENGUINFAN_TASK7_TEST_ROOT="$TEST_ROOT" \
    PENGUINFAN_TASK7_TEST_ROOT_TOKEN="$TEST_ROOT_TOKEN" \
    PENGUINFAN_RELEASE_OUTPUT_DIR="$unsafe_output" \
    "$ROOT/script/build_installer.sh" \
      --privileged-helper \
      --signing-identity "$SIGNING_IDENTITY"; then
    fail "installer accepted unsafe output path: $unsafe_output"
  fi

  if /usr/bin/env \
    PENGUINFAN_TASK7_ALLOW_TEST_OUTPUT_ROOT=1 \
    PENGUINFAN_TASK7_TEST_ROOT="$TEST_ROOT" \
    PENGUINFAN_TASK7_TEST_ROOT_TOKEN="$TEST_ROOT_TOKEN" \
    FAN_CONTROLLER_OUTPUT_ROOT="$unsafe_output" \
    "$ROOT/script/build_and_run.sh" \
      --privileged-helper \
      --signing-identity "$SIGNING_IDENTITY" \
      --verify; then
    fail "app builder accepted unsafe output path: $unsafe_output"
  fi
done
[[ "$(file_sha "$OVERRIDE_SENTINEL")" == "$OVERRIDE_SENTINEL_SHA" ]] \
  || fail "adversarial output-path tests changed their protected sentinel"

# Direct Release app builds must gate identity before touching an existing
# app and must restore the complete prior directory on publication failure.
DIRECT_OUTPUT_ROOT="$TEST_ROOT/direct-app-output"
DIRECT_APP="$DIRECT_OUTPUT_ROOT/dist-1.2.0/PenguinFan.app"
mkdir -p "$DIRECT_APP/Contents/Resources"
printf "direct app sentinel\n" \
  > "$DIRECT_APP/Contents/Resources/transaction-sentinel.txt"
DIRECT_SENTINEL_SHA="$(directory_snapshot_sha "$DIRECT_APP")"

for invalid_identity in "" "-" "Missing Signing Identity"; do
  INVALID_DIRECT_COMMAND=(
    /usr/bin/env
    PENGUINFAN_TASK7_ALLOW_TEST_OUTPUT_ROOT=1
    PENGUINFAN_TASK7_TEST_ROOT="$TEST_ROOT"
    PENGUINFAN_TASK7_TEST_ROOT_TOKEN="$TEST_ROOT_TOKEN"
    FAN_CONTROLLER_OUTPUT_ROOT="$DIRECT_OUTPUT_ROOT"
    "$ROOT/script/build_and_run.sh"
    --privileged-helper
    --verify
  )
  if [[ -n "$invalid_identity" ]]; then
    INVALID_DIRECT_COMMAND+=(--signing-identity "$invalid_identity")
  fi
  if "${INVALID_DIRECT_COMMAND[@]}"; then
    fail "direct app build accepted an invalid signing identity"
  fi
  [[ -d "$DIRECT_APP" ]] \
    && [[ "$(directory_snapshot_sha "$DIRECT_APP")" == \
      "$DIRECT_SENTINEL_SHA" ]] \
    || fail "invalid identity changed the existing direct app artifact"
done

DIRECT_BUILD_COMMAND=(
  /usr/bin/env
  PENGUINFAN_TASK7_ALLOW_TEST_OUTPUT_ROOT=1
  PENGUINFAN_TASK7_TEST_ROOT="$TEST_ROOT"
  PENGUINFAN_TASK7_TEST_ROOT_TOKEN="$TEST_ROOT_TOKEN"
  FAN_CONTROLLER_OUTPUT_ROOT="$DIRECT_OUTPUT_ROOT"
  "$ROOT/script/build_and_run.sh"
  --privileged-helper
  --signing-identity "$SIGNING_IDENTITY"
  --verify
)

if PENGUINFAN_TASK7_TEST_FORCE_TEAM_MISMATCH=1 \
  "${DIRECT_BUILD_COMMAND[@]}"; then
  fail "direct app build accepted a wrong-Team identity"
fi
[[ -d "$DIRECT_APP" ]] \
  && [[ "$(directory_snapshot_sha "$DIRECT_APP")" == \
    "$DIRECT_SENTINEL_SHA" ]] \
  || fail "wrong-Team identity changed the existing direct app artifact"

if PENGUINFAN_TASK7_FAIL_BEFORE_APP_PUBLISH=1 \
  "${DIRECT_BUILD_COMMAND[@]}"; then
  fail "direct app pre-publication failure unexpectedly succeeded"
fi
[[ -d "$DIRECT_APP" ]] \
  && [[ "$(directory_snapshot_sha "$DIRECT_APP")" == \
    "$DIRECT_SENTINEL_SHA" ]] \
  || fail "pre-publication failure changed the existing direct app artifact"
assert_no_app_staging_directories "$DIRECT_OUTPUT_ROOT"

"${DIRECT_BUILD_COMMAND[@]}"
verify_app "$DIRECT_APP"
DIRECT_VALID_SHA="$(directory_snapshot_sha "$DIRECT_APP")"
DIRECT_APP_LOCK="$DIRECT_OUTPUT_ROOT/.PenguinFan-1.2.0.app-publication.lock"

if PENGUINFAN_TASK7_SIGNAL_BEFORE_APP_BACKUP_MOVE=1 \
  "${DIRECT_BUILD_COMMAND[@]}"; then
  fail "direct app pre-backup signal injection unexpectedly succeeded"
fi
[[ -d "$DIRECT_APP" ]] \
  && [[ "$(directory_snapshot_sha "$DIRECT_APP")" == "$DIRECT_VALID_SHA" ]] \
  || fail "pre-backup signal did not preserve the complete direct app"
[[ ! -e "$DIRECT_APP_LOCK" ]] || fail "app lock remains after pre-backup signal"

if PENGUINFAN_TASK7_SIGNAL_AFTER_APP_BACKUP_MOVE=1 \
  "${DIRECT_BUILD_COMMAND[@]}"; then
  fail "direct app post-backup signal injection unexpectedly succeeded"
fi
[[ -d "$DIRECT_APP" ]] \
  && [[ "$(directory_snapshot_sha "$DIRECT_APP")" == "$DIRECT_VALID_SHA" ]] \
  || fail "post-backup signal did not restore the complete direct app"
verify_app "$DIRECT_APP"
assert_no_app_staging_directories "$DIRECT_OUTPUT_ROOT"

if PENGUINFAN_TASK7_SIGNAL_AFTER_APP_PUBLISH=1 \
  "${DIRECT_BUILD_COMMAND[@]}"; then
  fail "direct app post-publish signal injection unexpectedly succeeded"
fi
[[ -d "$DIRECT_APP" ]] \
  && [[ "$(directory_snapshot_sha "$DIRECT_APP")" == "$DIRECT_VALID_SHA" ]] \
  || fail "post-publish signal did not restore the complete direct app"
[[ ! -e "$DIRECT_APP_LOCK" ]] || fail "app lock remains after post-publish signal"
verify_app "$DIRECT_APP"
assert_no_app_staging_directories "$DIRECT_OUTPUT_ROOT"

# A live app-lock owner cannot be displaced, and a dead owner is recovered
# without allowing the non-owner attempt to modify final publication state.
/usr/bin/shlock -p "$$" -f "$DIRECT_APP_LOCK" \
  || fail "could not create live-owner app lock"
if PENGUINFAN_TASK7_APP_LOCK_WAIT_SECONDS=1 \
  "${DIRECT_BUILD_COMMAND[@]}"; then
  /bin/rm -f "$DIRECT_APP_LOCK"
  fail "direct app build displaced a live lock owner"
fi
[[ "$(directory_snapshot_sha "$DIRECT_APP")" == "$DIRECT_VALID_SHA" ]] \
  || fail "app lock non-owner modified the live owner's app"
/bin/rm -f "$DIRECT_APP_LOCK"

printf '999999\n' > "$DIRECT_APP_LOCK"
"${DIRECT_BUILD_COMMAND[@]}"
[[ ! -e "$DIRECT_APP_LOCK" ]] || fail "stale app lock remains after recovery"
verify_app "$DIRECT_APP"
DIRECT_VALID_SHA="$(directory_snapshot_sha "$DIRECT_APP")"

# A succeeds while B waits and then fails. B must restore A's exact published
# app. Two successful attempts must likewise serialize under the live owner.
DIRECT_A_LOG="$TEST_ROOT/direct-concurrency-a.log"
DIRECT_B_LOG="$TEST_ROOT/direct-concurrency-b.log"
DIRECT_BEFORE_A_INODE="$(/usr/bin/stat -f '%i' "$DIRECT_APP")"
PENGUINFAN_TASK7_HOLD_AFTER_APP_PUBLISH_SECONDS=2 \
  "${DIRECT_BUILD_COMMAND[@]}" >"$DIRECT_A_LOG" 2>&1 &
DIRECT_A_PID=$!
wait_for_app_lock_owner "$DIRECT_APP_LOCK" "$DIRECT_A_PID"
wait_for_app_replacement "$DIRECT_APP" "$DIRECT_BEFORE_A_INODE"

PENGUINFAN_TASK7_FAIL_BEFORE_APP_PUBLISH=1 \
  "${DIRECT_BUILD_COMMAND[@]}" >"$DIRECT_B_LOG" 2>&1 &
DIRECT_B_PID=$!
DIRECT_A_SHA="$(directory_snapshot_sha "$DIRECT_APP")"
wait "$DIRECT_A_PID" || fail "concurrent direct app build A failed"
if wait "$DIRECT_B_PID"; then
  fail "concurrent direct app build B unexpectedly succeeded"
fi
[[ "$(directory_snapshot_sha "$DIRECT_APP")" == "$DIRECT_A_SHA" ]] \
  || fail "failed direct app build B changed A's published app"
verify_app "$DIRECT_APP"
[[ ! -e "$DIRECT_APP_LOCK" ]] || fail "app lock remains after A/B concurrency"

DIRECT_C_LOG="$TEST_ROOT/direct-concurrency-c.log"
DIRECT_D_LOG="$TEST_ROOT/direct-concurrency-d.log"
PENGUINFAN_TASK7_HOLD_APP_LOCK_SECONDS=2 \
  "${DIRECT_BUILD_COMMAND[@]}" >"$DIRECT_C_LOG" 2>&1 &
DIRECT_C_PID=$!
wait_for_app_lock_owner "$DIRECT_APP_LOCK" "$DIRECT_C_PID"

"${DIRECT_BUILD_COMMAND[@]}" >"$DIRECT_D_LOG" 2>&1 &
DIRECT_D_PID=$!
/bin/sleep 0.25
[[ "$(/bin/cat "$DIRECT_APP_LOCK")" == "$DIRECT_C_PID" ]] \
  || fail "second successful direct build displaced the live app lock owner"
/bin/kill -0 "$DIRECT_D_PID" \
  || fail "second successful direct build did not wait for serialization"
wait "$DIRECT_C_PID" || fail "simultaneous direct app build C failed"
wait "$DIRECT_D_PID" || fail "simultaneous direct app build D failed"
verify_app "$DIRECT_APP"
[[ ! -e "$DIRECT_APP_LOCK" ]] || fail "app lock remains after serialized successes"
assert_no_app_staging_directories "$DIRECT_OUTPUT_ROOT"

# A live lock owner protects the existing final artifact. A non-owner must
# time out without deleting or replacing it.
/bin/rm -f "$LOCK_FILE"
/usr/bin/shlock -p "$$" -f "$LOCK_FILE" \
  || fail "could not create live-owner test lock"
printf "live owner sentinel\n" > "$FINAL_PACKAGE"
if PENGUINFAN_TASK6_LOCK_WAIT_SECONDS=1 \
  "${BUILD_COMMAND[@]}"; then
  /bin/rm -f "$LOCK_FILE" "$FINAL_PACKAGE"
  fail "non-owner build unexpectedly acquired a live lock"
fi
[[ "$(/bin/cat "$FINAL_PACKAGE")" == "live owner sentinel" ]] \
  || fail "non-owner modified the live owner's final artifact"
/bin/rm -f "$LOCK_FILE" "$FINAL_PACKAGE"

# A dead PID lock is stale and may be recovered. With no prior valid artifact,
# deliberate failure must leave the final path absent.
printf "999999\n" > "$LOCK_FILE"
if PENGUINFAN_TASK6_FAIL_BEFORE_PUBLISH=1 \
  "${BUILD_COMMAND[@]}"; then
  /bin/rm -f "$FINAL_PACKAGE"
  fail "deliberate pre-publication failure unexpectedly succeeded"
fi

[[ ! -e "$FINAL_PACKAGE" ]] \
  || fail "final package remains after deliberate failure"
[[ ! -e "$LOCK_FILE" ]] || fail "publication lock remains after failure"
assert_no_staging_directories

# A publishes successfully while B waits and then fails. B must restore A's
# validated package rather than removing it.
A_LOG="$TEST_ROOT/concurrency-a.log"
B_LOG="$TEST_ROOT/concurrency-b.log"
PENGUINFAN_TASK6_HOLD_AFTER_PUBLISH_SECONDS=2 \
  "${BUILD_COMMAND[@]}" \
  >"$A_LOG" 2>&1 &
A_PID=$!
wait_for_lock_owner "$A_PID"

PENGUINFAN_TASK6_FAIL_BEFORE_PUBLISH=1 \
  "${BUILD_COMMAND[@]}" \
  >"$B_LOG" 2>&1 &
B_PID=$!

wait_for_published_package
A_SHA="$(/usr/bin/shasum -a 256 "$FINAL_PACKAGE" \
  | /usr/bin/awk '{print $1}')"
wait "$A_PID" || fail "concurrent build A failed"
if wait "$B_PID"; then
  fail "concurrent build B unexpectedly succeeded"
fi

[[ -f "$FINAL_PACKAGE" ]] \
  || fail "B removed A's validated package"
[[ "$(/usr/bin/shasum -a 256 "$FINAL_PACKAGE" \
  | /usr/bin/awk '{print $1}')" == "$A_SHA" ]] \
  || fail "B replaced A's validated package"
verify_package "$FINAL_PACKAGE"

if (
  export PENGUINFAN_TASK7_TEST_SCANNER_ERROR=1
  verify_package "$FINAL_PACKAGE"
); then
  fail "injected packaged-helper scanner error was accepted as clean"
fi

assert_no_staging_directories

# TERM immediately before and immediately after the valid-final backup move
# must preserve the exact previously published package and release all state.
SIGNAL_BASELINE_SHA="$(/usr/bin/shasum -a 256 "$FINAL_PACKAGE" \
  | /usr/bin/awk '{print $1}')"

if PENGUINFAN_TASK6_SIGNAL_BEFORE_BACKUP_MOVE=1 \
  "${BUILD_COMMAND[@]}"; then
  fail "pre-backup signal injection unexpectedly succeeded"
fi
[[ -f "$FINAL_PACKAGE" ]] \
  || fail "pre-backup signal removed the valid final package"
[[ "$(/usr/bin/shasum -a 256 "$FINAL_PACKAGE" \
  | /usr/bin/awk '{print $1}')" == "$SIGNAL_BASELINE_SHA" ]] \
  || fail "pre-backup signal changed the valid final package"
[[ ! -e "$LOCK_FILE" ]] || fail "lock remains after pre-backup signal"
assert_no_staging_directories

if PENGUINFAN_TASK6_SIGNAL_AFTER_BACKUP_MOVE=1 \
  "${BUILD_COMMAND[@]}"; then
  fail "post-backup signal injection unexpectedly succeeded"
fi
[[ -f "$FINAL_PACKAGE" ]] \
  || fail "post-backup signal removed the valid final package"
[[ "$(/usr/bin/shasum -a 256 "$FINAL_PACKAGE" \
  | /usr/bin/awk '{print $1}')" == "$SIGNAL_BASELINE_SHA" ]] \
  || fail "post-backup signal changed the valid final package"
[[ ! -e "$LOCK_FILE" ]] || fail "lock remains after post-backup signal"
assert_no_staging_directories
verify_package "$FINAL_PACKAGE"

# Two successful simultaneous attempts must serialize. D remains waiting while
# C owns the lock; afterward the final package must be one complete artifact.
C_LOG="$TEST_ROOT/concurrency-c.log"
D_LOG="$TEST_ROOT/concurrency-d.log"
PENGUINFAN_TASK6_HOLD_LOCK_SECONDS=2 \
  "${BUILD_COMMAND[@]}" \
  >"$C_LOG" 2>&1 &
C_PID=$!
wait_for_lock_owner "$C_PID"

"${BUILD_COMMAND[@]}" \
  >"$D_LOG" 2>&1 &
D_PID=$!
/bin/sleep 0.25
[[ "$(/bin/cat "$LOCK_FILE")" == "$C_PID" ]] \
  || fail "second simultaneous build displaced the live lock owner"
/bin/kill -0 "$D_PID" \
  || fail "second simultaneous build did not wait for the lock"

wait "$C_PID" || fail "simultaneous build C failed"
wait "$D_PID" || fail "simultaneous build D failed"

verify_package "$FINAL_PACKAGE"
[[ ! -e "$LOCK_FILE" ]] || fail "publication lock remains after success"
assert_no_staging_directories

printf "Task 7 identity-gated transactional and artifact checks passed.\n"

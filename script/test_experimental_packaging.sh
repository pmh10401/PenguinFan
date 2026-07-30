#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FINAL_PACKAGE="$ROOT/installer/PenguinFan-Experimental-1.1.0.pkg"
LOCK_FILE="$ROOT/installer/.PenguinFan-Experimental-1.1.0.publication.lock"
HELPER_LABEL="com.local.PenguinFan.experimental.agent"
HELPER_PLIST_NAME="$HELPER_LABEL.plist"
EXPECTED_BUNDLE_PROGRAM="Contents/Helpers/FanControllerAgent"
EXPECTED_TEAM_IDENTIFIER="UUUQNVQ67B"
SIGNING_IDENTITY=""

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
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

BUILD_COMMAND=(
  "$ROOT/script/build_installer.sh"
  --experimental-helper
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

verify_app() {
  local app="$1"
  local contents="$app/Contents"
  local info="$contents/Info.plist"
  local daemon_plist="$contents/Library/LaunchDaemons/$HELPER_PLIST_NAME"

  [[ -d "$app" ]] || fail "experimental app is missing"
  [[ "$(plist_value "$info" CFBundleIdentifier)" == \
    "com.local.PenguinFan.experimental" ]] || fail "wrong bundle identifier"
  [[ "$(plist_value "$info" CFBundleShortVersionString)" == "1.1.0" ]] \
    || fail "wrong app version"
  [[ "$(plist_value "$info" CFBundleVersion)" == "14" ]] \
    || fail "wrong build number"
  [[ "$(plist_value "$info" CFBundleDisplayName)" == \
    "PenguinFan Experimental" ]] || fail "wrong display name"

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

  verify_identity_signature "$app/$EXPECTED_BUNDLE_PROGRAM"
  verify_identity_signature "$contents/MacOS/FanControllerApp"
  /usr/bin/codesign --verify --deep --strict "$app"
  verify_identity_signature "$app"

  local app_metadata
  app_metadata="$(/usr/bin/codesign -dvvv "$app" 2>&1)"
  [[ "$app_metadata" == *"Identifier=com.local.PenguinFan.experimental"* ]] \
    || fail "signed app identifier is wrong"
}

verify_package() {
  local package="$1"
  local expanded
  local expanded_parent
  local payload_line
  local normalized

  [[ -f "$package" ]] || fail "final experimental package is missing"

  while IFS= read -r payload_line; do
    normalized="${payload_line#./}"
    case "$normalized" in
      .|._Applications|Applications|Applications/|\
      "Applications/._PenguinFan Experimental.app"|\
      "Applications/PenguinFan Experimental.app"|\
      "Applications/PenguinFan Experimental.app/"*)
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
    "$ROOT/.build/task6-expanded-package.XXXXXX")"
  expanded="$expanded_parent/expanded"
  /usr/sbin/pkgutil --expand-full "$package" "$expanded"

  [[ -d "$expanded/Payload/Applications/PenguinFan Experimental.app" ]] \
    || fail "expanded package is missing the experimental app"
  [[ ! -e "$expanded/Payload/Applications/PenguinFan.app" ]] \
    || fail "expanded package contains stable PenguinFan.app"
  [[ ! -e "$expanded/Payload/Applications/FanController.app" ]] \
    || fail "expanded package contains legacy FanController.app"

  verify_app "$expanded/Payload/Applications/PenguinFan Experimental.app"
  /bin/rm -rf "$expanded_parent"
}

assert_no_staging_directories() {
  if /usr/bin/find "$ROOT/installer" -maxdepth 1 -type d \
    -name ".PenguinFan-Experimental-1.1.0.staging.*" \
    -print -quit | /usr/bin/grep -q .; then
    fail "experimental staging directory was not cleaned"
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

mkdir -p "$ROOT/installer"

# The rejected PID/static-code fallback must not remain in the source.
if /usr/bin/grep -Eq \
  'proc_pidpath|SecStaticCodeCreateWithPath|inspectStaticCode|LiveProcessCodeInspectionError|StaticCodeIdentity|acceptsAdHocFallback|route=fallback' \
  "$ROOT/Sources/FanControllerAgent/XPCClientValidator.swift"; then
  fail "unsafe XPC client fallback symbols remain"
fi

# Missing, ad-hoc, and unavailable identities must fail before the final
# artifact can be deleted or replaced.
printf "identity gate sentinel\n" > "$FINAL_PACKAGE"
for invalid_identity in "" "-" "Missing Signing Identity"; do
  INVALID_COMMAND=(
    "$ROOT/script/build_installer.sh"
    --experimental-helper
  )
  if [[ -n "$invalid_identity" ]]; then
    INVALID_COMMAND+=(--signing-identity "$invalid_identity")
  fi
  if "${INVALID_COMMAND[@]}"; then
    fail "invalid signing identity unexpectedly succeeded"
  fi
  [[ "$(/bin/cat "$FINAL_PACKAGE")" == "identity gate sentinel" ]] \
    || fail "invalid signing identity changed the final artifact"
done
/bin/rm -f "$FINAL_PACKAGE"

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
A_LOG="$ROOT/.build/task6-concurrency-a.log"
B_LOG="$ROOT/.build/task6-concurrency-b.log"
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
C_LOG="$ROOT/.build/task6-concurrency-c.log"
D_LOG="$ROOT/.build/task6-concurrency-d.log"
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

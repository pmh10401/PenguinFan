#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="${1:?release package path required}"
EXPECTED_AUTHORITY="${2:?expected signing Authority required}"
EXPECTED_TEAM_IDENTIFIER="${3:?expected TeamIdentifier required}"
HELPER_LABEL="com.local.PenguinFan.agent"
HELPER_PLIST_NAME="$HELPER_LABEL.plist"
EXPECTED_BUNDLE_PROGRAM="Contents/Helpers/FanControllerAgent"
EXPANDED_PARENT=""

fail() {
  printf "Release package validation failed: %s\n" "$1" >&2
  exit 1
}

cleanup() {
  local result=$?
  if [[ -n "$EXPANDED_PARENT" ]]; then
    /bin/rm -rf "$EXPANDED_PARENT"
  fi
  return "$result"
}
trap cleanup EXIT

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
  [[ "$authority" == "$EXPECTED_AUTHORITY" ]] \
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
  local app_metadata

  [[ -d "$app" ]] || fail "release app is missing"
  [[ "$(plist_value "$info" CFBundleIdentifier)" == \
    "com.local.PenguinFan" ]] || fail "wrong bundle identifier"
  [[ "$(plist_value "$info" CFBundleShortVersionString)" == "1.2.2" ]] \
    || fail "wrong app version"
  [[ "$(plist_value "$info" CFBundleVersion)" == "17" ]] \
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

  verify_identity_signature "$app/$EXPECTED_BUNDLE_PROGRAM"
  verify_identity_signature "$contents/MacOS/FanControllerApp"
  /usr/bin/codesign --verify --deep --strict "$app"
  verify_identity_signature "$app"
  app_metadata="$(/usr/bin/codesign -dvvv "$app" 2>&1)"
  [[ "$app_metadata" == *"Identifier=com.local.PenguinFan"* ]] \
    || fail "signed app identifier is wrong"
}

[[ -f "$PACKAGE" ]] || fail "package is missing"

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
      fail "unexpected payload path: $payload_line"
      ;;
  esac

  [[ "$normalized" != \
    "Applications/PenguinFan.app/Contents/MacOS/FanControllerApp" ]] \
    || FOUND_MAIN=1
  [[ "$normalized" != \
    "Applications/PenguinFan.app/Contents/Library/LaunchDaemons/$HELPER_PLIST_NAME" ]] \
    || FOUND_DAEMON_PLIST=1
done <<< "$PAYLOAD"

[[ "$FOUND_MAIN" -eq 1 ]] || fail "payload is missing the main executable"
[[ "$FOUND_DAEMON_PLIST" -eq 1 ]] \
  || fail "payload is missing the LaunchDaemon plist"

EXPANDED_PARENT="$(/usr/bin/mktemp -d \
  "$ROOT/.build/task6-package-validation.XXXXXX")"
EXPANDED="$EXPANDED_PARENT/expanded"
/usr/sbin/pkgutil --expand-full "$PACKAGE" "$EXPANDED"

EXPANDED_APP="$EXPANDED/Payload/Applications/PenguinFan.app"
[[ -d "$EXPANDED_APP" ]] || fail "expanded package is missing the app"
[[ ! -e "$EXPANDED/Payload/Applications/FanController.app" ]] \
  || fail "expanded package contains legacy FanController.app"

verify_app "$EXPANDED_APP"
printf "Validated release package: %s\n" "$PACKAGE"

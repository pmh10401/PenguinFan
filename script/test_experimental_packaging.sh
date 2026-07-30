#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FINAL_PACKAGE="$ROOT/installer/PenguinFan-Experimental-1.1.0.pkg"
HELPER_LABEL="com.local.PenguinFan.experimental.agent"
HELPER_PLIST_NAME="$HELPER_LABEL.plist"
EXPECTED_BUNDLE_PROGRAM="Contents/Helpers/FanControllerAgent"

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
}

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1"
}

verify_adhoc_signature() {
  local item="$1"
  local metadata
  /usr/bin/codesign --verify --strict "$item"
  metadata="$(/usr/bin/codesign -dvv "$item" 2>&1)"
  [[ "$metadata" == *"Signature=adhoc"* ]] \
    || fail "expected ad-hoc signature: $item"
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

  verify_adhoc_signature "$app/$EXPECTED_BUNDLE_PROGRAM"
  verify_adhoc_signature "$contents/MacOS/FanControllerApp"
  /usr/bin/codesign --verify --deep --strict "$app"

  local app_metadata
  app_metadata="$(/usr/bin/codesign -dvv "$app" 2>&1)"
  [[ "$app_metadata" == *"Identifier=com.local.PenguinFan.experimental"* ]] \
    || fail "signed app identifier is wrong"
  [[ "$app_metadata" == *"Signature=adhoc"* ]] \
    || fail "app is not ad-hoc signed"
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

mkdir -p "$ROOT/installer"
printf "stale package must never survive\n" > "$FINAL_PACKAGE"

if PENGUINFAN_TASK6_FAIL_BEFORE_PUBLISH=1 \
  "$ROOT/script/build_installer.sh" --experimental-helper; then
  /bin/rm -f "$FINAL_PACKAGE"
  fail "deliberate pre-publication failure unexpectedly succeeded"
fi

[[ ! -e "$FINAL_PACKAGE" ]] \
  || fail "final package remains after deliberate failure"
assert_no_staging_directories

"$ROOT/script/build_installer.sh" --experimental-helper

verify_package "$FINAL_PACKAGE"
assert_no_staging_directories

printf "Task 6 executable artifact and failure-path checks passed.\n"

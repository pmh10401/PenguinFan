#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="release"
SHOULD_LAUNCH=1
SHOW_LOGS=0
TELEMETRY=0
EXPERIMENTAL_HELPER=0
BUNDLE_ID="${FAN_CONTROLLER_BUNDLE_ID:-com.local.M2MaxFanController.dev}"
APP_VERSION="${FAN_CONTROLLER_VERSION:-1.0.12}"
BUILD_NUMBER="${FAN_CONTROLLER_BUILD_NUMBER:-13}"
APP_DISPLAY_NAME="PenguinFan"
APP_BUNDLE_NAME="PenguinFan.app"
HELPER_LABEL="com.local.PenguinFan.experimental.agent"
HELPER_PLIST_NAME="$HELPER_LABEL.plist"

for argument in "$@"; do
  case "$argument" in
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
    --experimental-helper)
      EXPERIMENTAL_HELPER=1
      ;;
    *)
      printf 'Unknown option: %s\n' "$argument" >&2
      exit 64
      ;;
  esac
done

if [[ "$EXPERIMENTAL_HELPER" -eq 1 ]]; then
  BUNDLE_ID="com.local.PenguinFan.experimental"
  APP_VERSION="1.1.0"
  BUILD_NUMBER="14"
  APP_DISPLAY_NAME="PenguinFan Experimental"
  APP_BUNDLE_NAME="PenguinFan Experimental.app"
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
APP="$ROOT/dist-$APP_VERSION/$APP_BUNDLE_NAME"
CONTENTS="$APP/Contents"
ICON_SOURCE="$ROOT/Assets/PenguinFanIcon.png"
HELPER_PLIST_SOURCE="$ROOT/Resources/LaunchDaemons/$HELPER_PLIST_NAME"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$CONTENTS/Resources"
install -m 0755 "$BIN_PATH/FanControllerApp" \
  "$CONTENTS/MacOS/FanControllerApp"
install -m 0755 "$BIN_PATH/FanControllerAgent" \
  "$CONTENTS/Helpers/FanControllerAgent"
install -m 0755 "$BIN_PATH/FanDiagnostics" \
  "$CONTENTS/Helpers/FanDiagnostics"

if [[ "$EXPERIMENTAL_HELPER" -eq 1 ]]; then
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
/usr/bin/codesign --force --sign - "$CONTENTS/Helpers/FanControllerAgent"
/usr/bin/codesign --force --sign - "$CONTENTS/Helpers/FanDiagnostics"
/usr/bin/codesign --force --sign - "$CONTENTS/MacOS/FanControllerApp"
/usr/bin/codesign --force --sign - "$APP"

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
  SIGNATURE_INFO="$(/usr/bin/codesign -dvv "$signed_item" 2>&1)"
  if [[ "$SIGNATURE_INFO" != *"Signature=adhoc"* ]]; then
    echo "Expected ad-hoc signature: $signed_item" >&2
    exit 1
  fi
done

if [[ "$EXPERIMENTAL_HELPER" -eq 1 ]]; then
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

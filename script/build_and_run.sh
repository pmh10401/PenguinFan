#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="release"
SHOULD_LAUNCH=1
SHOW_LOGS=0
TELEMETRY=0
BUNDLE_ID="${FAN_CONTROLLER_BUNDLE_ID:-com.local.M2MaxFanController.dev}"
APP_VERSION="${FAN_CONTROLLER_VERSION:-1.0.11}"
BUILD_NUMBER="${FAN_CONTROLLER_BUILD_NUMBER:-12}"

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
    *)
      printf 'Unknown option: %s\n' "$argument" >&2
      exit 64
      ;;
  esac
done

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
APP="$ROOT/dist-$APP_VERSION/PenguinFan.app"
CONTENTS="$APP/Contents"
ICON_SOURCE="$ROOT/Assets/PenguinFanIcon.png"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$CONTENTS/Resources"
install -m 0755 "$BIN_PATH/FanControllerApp" \
  "$CONTENTS/MacOS/FanControllerApp"
install -m 0755 "$BIN_PATH/FanControllerAgent" \
  "$CONTENTS/Helpers/FanControllerAgent"
install -m 0755 "$BIN_PATH/FanDiagnostics" \
  "$CONTENTS/Helpers/FanDiagnostics"

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
  <string>PenguinFan</string>
  <key>CFBundleExecutable</key>
  <string>FanControllerApp</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PenguinFan</string>
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
/usr/bin/codesign --force --deep --sign - "$APP"

test -x "$CONTENTS/MacOS/FanControllerApp"
test -x "$CONTENTS/Helpers/FanControllerAgent"
test -x "$CONTENTS/Helpers/FanDiagnostics"
/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP"

printf 'Built: %s\n' "$APP"

if [[ "$SHOULD_LAUNCH" -eq 1 ]]; then
  /usr/bin/pkill -x FanControllerApp 2>/dev/null || true
  /usr/bin/open -n "$APP"
fi

if [[ "$SHOW_LOGS" -eq 1 ]]; then
  exec /usr/bin/log stream --style compact \
    --predicate 'process == "FanControllerApp" OR process == "FanControllerAgent"'
fi

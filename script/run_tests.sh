#!/bin/bash
set -euo pipefail

XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -d "$XCODE_DEVELOPER_DIR" ]]; then
  printf 'Xcode developer directory was not found: %s\n' \
    "$XCODE_DEVELOPER_DIR" >&2
  printf 'Install Xcode or set DEVELOPER_DIR to the Xcode developer directory.\n' >&2
  exit 1
fi

export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
exec /usr/bin/xcrun swift test "$@"

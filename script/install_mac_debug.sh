#!/usr/bin/env bash
# Build the Debug Mac receiver and install it at a fixed path, ~/Applications/TypeCarrier Debug.app,
# then (re)launch it. Keeping one path and one signing identity means macOS keeps a single
# Accessibility entry for the Debug build instead of a new one per build location.
#
# Usage: script/install_mac_debug.sh [--autopair]
#   --autopair  launch with TYPECARRIER_V2_AUTOPAIR=1 (pairing stays open and auto-confirms)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/dist/DerivedData-mac-debug}"
DEST_DIR="$HOME/Applications"
APP_NAME="TypeCarrier Debug.app"

xcodebuild -project "$ROOT_DIR/TypeCarrier.xcodeproj" -scheme TypeCarrierMac -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" build -quiet

pkill -f "$APP_NAME/Contents/MacOS/" || true
mkdir -p "$DEST_DIR"
rm -rf "${DEST_DIR:?}/$APP_NAME"
ditto "$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME" "$DEST_DIR/$APP_NAME"

if [[ "${1:-}" == "--autopair" ]]; then
  open -n --env TYPECARRIER_V2_AUTOPAIR=1 "$DEST_DIR/$APP_NAME"
else
  open -n "$DEST_DIR/$APP_NAME"
fi
echo "Installed and launched $DEST_DIR/$APP_NAME"

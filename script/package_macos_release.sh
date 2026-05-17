#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${SCHEME:-TypeCarrierMac}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/release-derived-data}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
TYPECARRIER_RELEASE_CHANNEL="${TYPECARRIER_RELEASE_CHANNEL:-development}"

if [[ "$TYPECARRIER_RELEASE_CHANNEL" != "development" ]]; then
  echo "error: only TYPECARRIER_RELEASE_CHANNEL=development is supported for 0.1 Personal Team beta packaging." >&2
  echo "error: Developer ID notarization is intentionally deferred until the paid Apple Developer Program is configured." >&2
  exit 1
fi

rm -rf "$DERIVED_DATA_PATH"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project TypeCarrier.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/TypeCarrierMac.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app bundle not found: $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
ARCHIVE_NAME="TypeCarrierMac-${VERSION}-${BUILD}-${TYPECARRIER_RELEASE_CHANNEL}.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n '/Authority=/p;/TeamIdentifier=/p;/Runtime/p'

if ! spctl --assess --type execute --verbose=4 "$APP_PATH"; then
  echo "warning: Gatekeeper assessment failed." >&2
  echo "warning: This is expected for the 0.1 development package when signed with Apple Development / Personal Team." >&2
  echo "warning: Public no-warning macOS distribution requires Developer ID signing and notarization." >&2
fi

rm -f "$ARCHIVE_PATH"
ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$ARCHIVE_PATH"
shasum -a 256 "$ARCHIVE_PATH"

echo "Created $ARCHIVE_PATH"
echo "Release channel: $TYPECARRIER_RELEASE_CHANNEL"

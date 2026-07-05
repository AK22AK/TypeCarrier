#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${SCHEME:-TypeCarrierMac}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/developer-id-derived-data}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/.build/TypeCarrierMac-DeveloperID.xcarchive}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
DMG_ROOT="${DMG_ROOT:-$ROOT_DIR/.build/typecarrier-dmg-root}"
VOLUME_NAME="${VOLUME_NAME:-TypeCarrier}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-${DEVELOPMENT_TEAM:-}}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-30m}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
TYPECARRIER_BUNDLE_PREFIX="${TYPECARRIER_BUNDLE_PREFIX:-}"

if [[ -z "$APPLE_TEAM_ID" ]]; then
  echo "error: APPLE_TEAM_ID or DEVELOPMENT_TEAM is required for Developer ID signing." >&2
  exit 1
fi

xcodebuild_args=(
  -project TypeCarrier.xcodeproj
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination 'generic/platform=macOS'
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
)

if [[ -n "$TYPECARRIER_BUNDLE_PREFIX" ]]; then
  xcodebuild_args+=(TYPECARRIER_BUNDLE_PREFIX="$TYPECARRIER_BUNDLE_PREFIX")
fi

xcodebuild_args+=(archive)

rm -rf "$DERIVED_DATA_PATH" "$ARCHIVE_PATH" "$DMG_ROOT"
mkdir -p "$DIST_DIR" "$DMG_ROOT"

xcodebuild "${xcodebuild_args[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/TypeCarrierMac.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected archived app bundle not found: $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
DMG_NAME="TypeCarrierMac-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvvv "$APP_PATH" 2>&1 | tee "$DIST_DIR/TypeCarrierMac-${VERSION}-${BUILD}-codesign.txt"
ENTITLEMENTS_PATH="$DIST_DIR/TypeCarrierMac-${VERSION}-${BUILD}-entitlements.plist"
codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS_PATH" 2>/dev/null
cat "$ENTITLEMENTS_PATH"

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS_PATH" >/dev/null 2>&1; then
  echo "error: archived app unexpectedly contains get-task-allow entitlement." >&2
  exit 1
fi

ditto "$APP_PATH" "$DMG_ROOT/TypeCarrierMac.app"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"
codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=4 "$DMG_PATH"

if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
  notary_args=(submit "$DMG_PATH" --wait --timeout "$NOTARY_TIMEOUT")

  if [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
    notary_args+=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
  elif [[ -n "${NOTARYTOOL_KEY_PATH:-}" && -n "${NOTARYTOOL_KEY_ID:-}" ]]; then
    notary_args+=(--key "$NOTARYTOOL_KEY_PATH" --key-id "$NOTARYTOOL_KEY_ID")
    if [[ -n "${NOTARYTOOL_ISSUER_ID:-}" ]]; then
      notary_args+=(--issuer "$NOTARYTOOL_ISSUER_ID")
    fi
  elif [[ -n "${NOTARYTOOL_APPLE_ID:-}" && -n "${NOTARYTOOL_PASSWORD:-}" ]]; then
    notary_args+=(--apple-id "$NOTARYTOOL_APPLE_ID" --password "$NOTARYTOOL_PASSWORD" --team-id "$APPLE_TEAM_ID")
  else
    echo "error: notarization credentials are required unless SKIP_NOTARIZATION=1." >&2
    echo "error: set NOTARYTOOL_KEYCHAIN_PROFILE, or NOTARYTOOL_KEY_PATH + NOTARYTOOL_KEY_ID, or NOTARYTOOL_APPLE_ID + NOTARYTOOL_PASSWORD." >&2
    exit 1
  fi

  xcrun notarytool "${notary_args[@]}"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type install --verbose=4 "$DMG_PATH"
fi

(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME") | tee "$DMG_PATH.sha256"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "MACOS_DMG=$DMG_PATH"
    echo "MACOS_DMG_SHA256=$DMG_PATH.sha256"
  } >> "$GITHUB_ENV"
fi

echo "Created $DMG_PATH"
echo "Created $DMG_PATH.sha256"

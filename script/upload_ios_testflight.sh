#!/usr/bin/env bash
# Archive the iOS app in Release, export it for App Store Connect and upload it to TestFlight.
#
# Signing uses Xcode's automatic signing with the Apple account signed in to Xcode
# (Xcode > Settings > Accounts). The team comes from APPLE_TEAM_ID, DEVELOPMENT_TEAM or
# Configs/Signing.local.xcconfig.
#
#   script/upload_ios_testflight.sh            archive, export and upload
#   UPLOAD=0 script/upload_ios_testflight.sh   archive and export an .ipa only
#   ALLOW_DIRTY=1 ...                          allow uncommitted changes (the build then has no exact commit)
#
# After a successful upload, tag the commit as ios-v<version> (see docs/distribution.md).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${SCHEME:-TypeCarrieriOS}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build/ios-testflight}"
ARCHIVE_PATH="$BUILD_DIR/TypeCarrieriOS.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
UPLOAD="${UPLOAD:-1}"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"

local_setting() {
  local file="$ROOT_DIR/Configs/Signing.local.xcconfig"
  [[ -f "$file" ]] || return 0
  sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p" "$file" | tail -1
}

project_setting() {
  sed -n -E "s/^[[:space:]]*$1:[[:space:]]*([^[:space:]]+).*/\1/p" "$ROOT_DIR/project.yml" | head -1
}

APPLE_TEAM_ID="${APPLE_TEAM_ID:-${DEVELOPMENT_TEAM:-$(local_setting DEVELOPMENT_TEAM)}}"
if [[ -z "$APPLE_TEAM_ID" ]]; then
  echo "error: set APPLE_TEAM_ID, or DEVELOPMENT_TEAM in Configs/Signing.local.xcconfig." >&2
  exit 1
fi

# Xcode rewrites shared schemes while it has the project open; they do not affect the iOS build.
if [[ "$ALLOW_DIRTY" != "1" ]] && [[ -n "$(git status --porcelain -- . ':!TypeCarrier.xcodeproj/xcshareddata')" ]]; then
  echo "error: uncommitted changes. Commit first so the build maps to one commit, or set ALLOW_DIRTY=1." >&2
  git status --short -- . ':!TypeCarrier.xcodeproj/xcshareddata' >&2
  exit 1
fi

VERSION="$(project_setting MARKETING_VERSION)"
BUILD_NUMBER="$(project_setting CURRENT_PROJECT_VERSION)"
COMMIT="$(git rev-parse --short HEAD)"
echo "==> TypeCarrier iOS $VERSION ($BUILD_NUMBER) from $COMMIT, team $APPLE_TEAM_ID"

if git rev-parse -q --verify "refs/tags/ios-v$VERSION" >/dev/null; then
  echo "warning: tag ios-v$VERSION already exists; this version was already uploaded. Bump MARKETING_VERSION or CURRENT_PROJECT_VERSION first." >&2
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving"
export PATH="$HOME/.cargo/bin:$PATH"
xcodebuild archive \
  -project TypeCarrier.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"

APP_PLIST="$(ls -d "$ARCHIVE_PATH"/Products/Applications/*.app)/Info.plist"
ARCHIVED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
ARCHIVED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
ENCRYPTION="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$APP_PLIST" 2>/dev/null || echo "not set")"
if [[ "$ARCHIVED_VERSION" != "$VERSION" || "$ARCHIVED_BUILD" != "$BUILD_NUMBER" ]]; then
  echo "error: archive is $ARCHIVED_VERSION ($ARCHIVED_BUILD) but project.yml says $VERSION ($BUILD_NUMBER)." >&2
  exit 1
fi
echo "==> Archived $ARCHIVED_VERSION ($ARCHIVED_BUILD); ITSAppUsesNonExemptEncryption: $ENCRYPTION"

destination=export
[[ "$UPLOAD" == "1" ]] && destination=upload
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

echo "==> Exporting ($destination)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

if [[ "$UPLOAD" == "1" ]]; then
  echo "==> Uploaded $VERSION ($BUILD_NUMBER). App Store Connect is processing it."
  echo "    Next: answer any export compliance questions in TestFlight, then tag this commit:"
  echo "    git tag -a ios-v$VERSION $COMMIT -m \"TypeCarrier iOS $VERSION ($BUILD_NUMBER)\" && git push origin ios-v$VERSION"
else
  echo "==> Exported to $EXPORT_PATH (not uploaded)."
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/Apps/Android"
LOCAL_PROPERTIES="$ANDROID_DIR/local.properties"
KEYSTORE_PATH="${TYPECARRIER_ANDROID_RELEASE_STORE_FILE:-$HOME/.typecarrier/android-release.jks}"
KEY_ALIAS="${TYPECARRIER_ANDROID_RELEASE_KEY_ALIAS:-typecarrier-release}"

if ! command -v keytool >/dev/null 2>&1; then
  echo "error: keytool was not found. Install a JDK before setting up Android signing." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "error: openssl was not found. It is required to generate a local signing password." >&2
  exit 1
fi

if [ -e "$KEYSTORE_PATH" ]; then
  echo "error: keystore already exists at $KEYSTORE_PATH" >&2
  echo "Refusing to overwrite it. Set TYPECARRIER_ANDROID_RELEASE_STORE_FILE to use a different path." >&2
  exit 1
fi

KEYSTORE_PASSWORD="${TYPECARRIER_ANDROID_RELEASE_STORE_PASSWORD:-$(openssl rand -hex 32)}"
KEY_PASSWORD="${TYPECARRIER_ANDROID_RELEASE_KEY_PASSWORD:-$KEYSTORE_PASSWORD}"

mkdir -p "$(dirname "$KEYSTORE_PATH")"
mkdir -p "$ANDROID_DIR"

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -storetype PKCS12 \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -storepass "$KEYSTORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=TypeCarrier Android Release, OU=TypeCarrier, O=TypeCarrier, L=Shanghai, ST=Shanghai, C=CN"
chmod 600 "$KEYSTORE_PATH"

tmp_file="$(mktemp)"
if [ -f "$LOCAL_PROPERTIES" ]; then
  awk -F= '
    BEGIN {
      skip["typecarrier.android.release.storeFile"] = 1
      skip["typecarrier.android.release.storePassword"] = 1
      skip["typecarrier.android.release.keyAlias"] = 1
      skip["typecarrier.android.release.keyPassword"] = 1
    }
    !($1 in skip) { print }
  ' "$LOCAL_PROPERTIES" > "$tmp_file"
fi

{
  if [ -s "$tmp_file" ]; then
    cat "$tmp_file"
    printf '\n'
  fi
  printf '# TypeCarrier Android release signing. Local only; do not commit.\n'
  printf 'typecarrier.android.release.storeFile=%s\n' "$KEYSTORE_PATH"
  printf 'typecarrier.android.release.storePassword=%s\n' "$KEYSTORE_PASSWORD"
  printf 'typecarrier.android.release.keyAlias=%s\n' "$KEY_ALIAS"
  printf 'typecarrier.android.release.keyPassword=%s\n' "$KEY_PASSWORD"
} > "$LOCAL_PROPERTIES"
chmod 600 "$LOCAL_PROPERTIES"

rm -f "$tmp_file"

echo "Android release signing is configured locally."
echo "Keystore: $KEYSTORE_PATH"
echo "Gradle config: $LOCAL_PROPERTIES"
echo "Build with: cd Apps/Android && ./gradlew assembleRelease"

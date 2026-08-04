#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: ./Scripts/build-release.sh <version>" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){1,2}([.-][0-9A-Za-z.-]+)*$ ]]; then
  echo "Error: invalid version: $VERSION" >&2
  exit 1
fi

BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
BUILD_ROOT="$ROOT_DIR/.build/release"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Local MCP Tunnel.app"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
ARCHIVE_NAME="Local-MCP-Tunnel-${VERSION}-arm64.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

rm -rf "$BUILD_ROOT" "$DIST_DIR"
mkdir -p "$BUILD_ROOT" "$DIST_DIR"

xcodebuild \
  -project LocalMCPTunnel.xcodeproj \
  -scheme LocalMCPTunnel \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: app bundle not found: $APP_PATH" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Error: executable not found: $EXECUTABLE_PATH" >&2
  exit 1
fi

BINARY_ARCHS="$(lipo -archs "$EXECUTABLE_PATH")"
if [[ "$BINARY_ARCHS" != "arm64" ]]; then
  echo "Error: expected arm64-only binary, got: $BINARY_ARCHS" >&2
  exit 1
fi

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
if [[ "$PLIST_VERSION" != "$VERSION" ]]; then
  echo "Error: expected app version $VERSION, got: $PLIST_VERSION" >&2
  exit 1
fi

# Public distribution can provide a Developer ID Application identity and an
# optional notarytool Keychain profile. Without them, create an ad hoc-signed
# build like the reference project's preview release flow.
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    "$APP_PATH"
else
  codesign --force --deep --sign - "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "Error: NOTARYTOOL_PROFILE requires DEVELOPER_ID_APPLICATION." >&2
    exit 1
  fi

  xcrun notarytool submit "$ARCHIVE_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

  xcrun stapler staple "$APP_PATH"
  rm -f "$ARCHIVE_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"
fi

SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$ARCHIVE_NAME" > "$CHECKSUM_PATH"

cat <<EOF
Release package created.

Version:      $VERSION
Build:        $BUILD_NUMBER
Architecture: $BINARY_ARCHS
Archive:      $ARCHIVE_PATH
Checksum:     $CHECKSUM_PATH
SHA-256:      $SHA256
EOF

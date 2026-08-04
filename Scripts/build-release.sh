#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-1.0.0}"
BUILD_ROOT="$ROOT_DIR/.build/release"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="LocalMCPTunnelApp.app"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
ARCHIVE_NAME="Local-MCP-Tunnel-${VERSION}-arm64.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"

rm -rf "$BUILD_ROOT" "$DIST_DIR"
mkdir -p "$BUILD_ROOT" "$DIST_DIR"

xcodebuild \
  -project LocalMCPTunnelApp.xcodeproj \
  -scheme LocalMCPTunnelApp \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: app bundle not found: $APP_PATH" >&2
  exit 1
fi

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
BINARY_ARCHS="$(lipo -archs "$EXECUTABLE_PATH")"

if [[ "$BINARY_ARCHS" != "arm64" ]]; then
  echo "Error: expected arm64-only binary, got: $BINARY_ARCHS" >&2
  exit 1
fi

# Public distribution should use a Developer ID Application certificate.
# Example:
#   DEVELOPER_ID_APPLICATION='Developer ID Application: Example Inc. (TEAMID)' \
#   NOTARYTOOL_PROFILE='local-mcp-tunnel-notary' \
#   ./Scripts/build-release.sh 1.0.0
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    "$APP_PATH"

  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

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
printf '%s  %s\n' "$SHA256" "$ARCHIVE_NAME" > "$ARCHIVE_PATH.sha256"

cat <<EOF
Release package created.

Version:      $VERSION
Architecture: $BINARY_ARCHS
Archive:      $ARCHIVE_PATH
SHA-256:      $SHA256

Local Homebrew test:
  ./Scripts/generate-cask.sh \\
    "$VERSION" \\
    "$SHA256" \\
    "file://$ARCHIVE_PATH" \\
    "$DIST_DIR/local-mcp-tunnel.rb"
  brew install --cask "$DIST_DIR/local-mcp-tunnel.rb"
EOF

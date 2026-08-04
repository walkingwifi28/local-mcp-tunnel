#!/bin/bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  cat >&2 <<'EOF'
Usage:
  ./Scripts/generate-cask.sh <version> <sha256> <download-url> <output-file> [homepage]

Example:
  ./Scripts/generate-cask.sh \
    1.0.0 \
    <sha256> \
    https://github.com/OWNER/REPO/releases/download/v1.0.0/Local-MCP-Tunnel-1.0.0-arm64.zip \
    Casks/local-mcp-tunnel.rb \
    https://github.com/OWNER/REPO
EOF
  exit 1
fi

VERSION="$1"
SHA256="$2"
DOWNLOAD_URL="$3"
OUTPUT_FILE="$4"
HOMEPAGE="${5:-https://github.com/OWNER/REPO}"

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){1,2}([.-][0-9A-Za-z]+)*$ ]]; then
  echo "Error: invalid version: $VERSION" >&2
  exit 1
fi

if [[ ! "$SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "Error: SHA-256 must contain 64 hexadecimal characters." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

cat > "$OUTPUT_FILE" <<EOF
cask "local-mcp-tunnel" do
  version "$VERSION"
  sha256 "${SHA256,,}"

  url "$DOWNLOAD_URL"
  name "Local MCP Tunnel"
  desc "GUI for controlling tunnel-client and local-mcp"
  homepage "$HOMEPAGE"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "LocalMCPTunnelApp.app"

  zap trash: [
    "~/Library/Preferences/jp.co.varista.LocalMCPTunnelApp.plist",
    "~/Library/Saved Application State/jp.co.varista.LocalMCPTunnelApp.savedState",
  ]
end
EOF

echo "Cask generated: $OUTPUT_FILE"

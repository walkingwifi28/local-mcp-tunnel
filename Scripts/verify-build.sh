#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild \
  -project LocalMCPTunnel.xcodeproj \
  -scheme LocalMCPTunnel \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

#!/usr/bin/env bash
# Build MacTap and install to /Applications.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v xcodegen >/dev/null
xcodegen generate
pkill -x MacTap 2>/dev/null || true
xcodebuild -project MacTap.xcodeproj -scheme MacTap -configuration Debug \
  CONFIGURATION_BUILD_DIR=/Applications
open /Applications/MacTap.app

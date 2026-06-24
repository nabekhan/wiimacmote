#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This app build requires macOS and Xcode." >&2
  exit 1
fi

./Scripts/test-core.sh

xcodebuild \
  -project WiiMacMote.xcodeproj \
  -scheme WiiMacMote \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Built: $ROOT/build/DerivedData/Build/Products/Release/WiiMacMote.app"

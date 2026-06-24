#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="$ROOT/build/WiiMacMote.xcarchive"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Archiving requires macOS and Xcode." >&2
  exit 1
fi

./Scripts/test-core.sh
rm -rf "$ARCHIVE_PATH"

xcodebuild archive \
  -project WiiMacMote.xcodeproj \
  -scheme WiiMacMote \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO

BINARY="$ARCHIVE_PATH/Products/Applications/WiiMacMote.app/Contents/MacOS/WiiMacMote"
echo "Archive: $ARCHIVE_PATH"
echo "Architectures: $(lipo -archs "$BINARY")"

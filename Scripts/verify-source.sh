#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

plutil -lint \
  wiimacmote/Info.plist \
  wiimacmote/WiiMacMote.entitlements \
  WiiMacMote.xcodeproj/project.pbxproj

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout \
    WiiMacMote.xcodeproj/project.xcworkspace/contents.xcworkspacedata \
    WiiMacMote.xcodeproj/xcshareddata/xcschemes/WiiMacMote.xcscheme
fi

if command -v xcrun >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; then
  xcrun swiftc -frontend -parse wiimacmote/*.swift Tests/CoreTests.swift
elif command -v swiftc >/dev/null 2>&1; then
  swiftc -frontend -parse wiimacmote/*.swift Tests/CoreTests.swift
else
  echo "swiftc was not found. Install Xcode, the Command Line Tools, or a Swift toolchain." >&2
  exit 1
fi

./Scripts/test-core.sh

if grep -R --line-number --exclude='verify-source.sh' \
  -E 'pkill[[:space:]]+bluetoothd|0x045E|0x028E|DEVELOPMENT_TEAM[[:space:]]*=' \
  wiimacmote WiiMacMote.xcodeproj Scripts .github; then
  echo "Found a removed privileged action, Xbox spoof ID, or hard-coded signing team." >&2
  exit 1
fi

echo "Source verification passed."

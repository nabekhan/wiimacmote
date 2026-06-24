#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/wiimacmote-core-tests"
mkdir -p "$BUILD_DIR"

if command -v xcrun >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; then
  SWIFTC="xcrun swiftc"
elif command -v swiftc >/dev/null 2>&1; then
  SWIFTC="swiftc"
else
  echo "swiftc was not found. Install Xcode, the Command Line Tools, or a Swift toolchain." >&2
  exit 1
fi

# Word splitting is intentional here so SWIFTC can be either `swiftc` or
# `xcrun swiftc`; neither path contains shell metacharacters.
# shellcheck disable=SC2086
$SWIFTC \
  "$ROOT/wiimacmote/WiimoteProtocol.swift" \
  "$ROOT/wiimacmote/GamepadMapping.swift" \
  "$ROOT/wiimacmote/VirtualGamepadReports.swift" \
  "$ROOT/wiimacmote/DeveloperLabEnvironment.swift" \
  "$ROOT/Tests/CoreTests.swift" \
  -o "$BUILD_DIR/CoreTests"

"$BUILD_DIR/CoreTests"

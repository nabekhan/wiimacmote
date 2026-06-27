#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIGN_INSTALLED=0
for ARG in "$@"; do
  case "$ARG" in
    --sign-installed)
      SIGN_INSTALLED=1
      ;;
    --help|-h)
      echo "Usage: ./Scripts/build.sh [--sign-installed]"
      echo "Builds and ad-hoc signs the Release app."
      echo "  --sign-installed  Also refresh /Applications/WiiMacMote.app with a local ad-hoc signature."
      exit 0
      ;;
    *)
      echo "Unknown argument: $ARG" >&2
      exit 2
      ;;
  esac
done

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

APP="$ROOT/build/DerivedData/Build/Products/Release/WiiMacMote.app"
codesign --force --deep --sign - "$APP"

if [[ "$SIGN_INSTALLED" == "1" ]]; then
  INSTALLED_APP="/Applications/WiiMacMote.app"
  if [[ ! -d "$INSTALLED_APP" ]]; then
    echo "Installed app not found: $INSTALLED_APP" >&2
    exit 1
  fi
  codesign --force --deep --sign - "$INSTALLED_APP"
  echo "Refreshed local signature: $INSTALLED_APP"
fi

echo "Built and ad-hoc signed: $APP"

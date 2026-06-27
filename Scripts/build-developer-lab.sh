#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA_PATH:-$ROOT/build/DeveloperLabDerivedData}"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The Local AMFI Lab app build requires macOS and Xcode." >&2
  exit 1
fi

./Scripts/verify-source.sh

# Compile without asking Xcode for an Apple team, certificate, or provisioning
# profile. The restricted entitlement is applied explicitly in the next step.
xcodebuild \
  -project WiiMacMote.xcodeproj \
  -scheme 'WiiMacMote Developer Lab' \
  -configuration DeveloperLab \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build

APP="$DERIVED_DATA/Build/Products/DeveloperLab/WiiMacMote.app"
if [[ ! -d "$APP" ]]; then
  echo "Expected app bundle was not produced: $APP" >&2
  exit 1
fi

./Scripts/sign-developer-lab.sh "$APP"
./Scripts/diagnose-developer-lab.sh "$APP"

echo
echo "Built unsigned by Xcode, then explicitly ad-hoc signed:"
echo "  $APP"
echo "No Apple team, provisioning profile, or another project's signature was used."
echo "Launch it directly with:"
echo "  ./Scripts/run-developer-lab.sh --no-build -- --enable-virtual-gamepad --profile xbox-series --backend iohid"
echo "No included script changes SIP, AMFI, NVRAM, or Startup Security."

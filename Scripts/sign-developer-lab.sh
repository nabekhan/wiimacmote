#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/wiimacmote/WiiMacMote-DeveloperLab.entitlements"
APP="${1:-$ROOT/build/DeveloperLabDerivedData/Build/Products/DeveloperLab/WiiMacMote.app}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Code signing requires macOS." >&2
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  echo "Pass the path to WiiMacMote.app as the first argument." >&2
  exit 1
fi

# The current app has no embedded third-party frameworks, XPC services, or
# extensions. Sign the outer app explicitly rather than relying on --deep.
codesign \
  --force \
  --sign - \
  --timestamp=none \
  --entitlements "$ENTITLEMENTS" \
  "$APP"

codesign --verify --strict --verbose=2 "$APP"

ENTITLEMENT_DUMP="$(mktemp -t wiimacmote-entitlements.XXXXXX)"
trap 'rm -f "$ENTITLEMENT_DUMP"' EXIT
codesign -d --entitlements :- "$APP" >"$ENTITLEMENT_DUMP" 2>/dev/null

if ! grep -A1 -F '<key>com.apple.developer.hid.virtual.device</key>' "$ENTITLEMENT_DUMP" \
  | grep -Fq '<true/>'; then
  echo "The signed app does not contain com.apple.developer.hid.virtual.device=true." >&2
  exit 1
fi

SIGNING_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if ! print -r -- "$SIGNING_INFO" | grep -Fq 'Signature=adhoc'; then
  echo "Warning: codesign did not report an ad-hoc signature." >&2
  print -r -- "$SIGNING_INFO" >&2
fi

echo "Developer Lab ad-hoc signature applied: $APP"
echo "Verified entitlement: com.apple.developer.hid.virtual.device=true"
echo "No Apple team or provisioning profile was used."
echo "This script did not change SIP, AMFI, NVRAM, or Startup Security settings."

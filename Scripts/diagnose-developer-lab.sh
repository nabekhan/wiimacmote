#!/bin/zsh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/DeveloperLabDerivedData/Build/Products/DeveloperLab/WiiMacMote.app}"
ENTITLEMENT='com.apple.developer.hid.virtual.device'
FAILED=0

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Developer Lab diagnostics require macOS." >&2
  exit 1
fi

echo "WiiMacMote Local AMFI Lab diagnostics"
echo "======================================"
echo "App: $APP"
echo "OS: $(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unknown)"
echo "Architecture: $(/usr/bin/uname -m)"
echo

echo "SIP status:"
/usr/bin/csrutil status 2>&1 || true
echo

BOOT_ARGS="$(/usr/sbin/sysctl -n kern.bootargs 2>/dev/null || true)"
if [[ -z "$BOOT_ARGS" ]]; then
  BOOT_ARGS="$(/usr/sbin/nvram boot-args 2>/dev/null | /usr/bin/sed -E 's/^boot-args[[:space:]]+//' || true)"
fi

echo "Visible boot arguments:"
if [[ -n "$BOOT_ARGS" ]]; then
  echo "$BOOT_ARGS"
else
  echo "(none or unreadable)"
fi

case " $BOOT_ARGS " in
  *" amfi_get_out_of_my_way=0x1 "*|*" amfi_get_out_of_my_way=0X1 "*|*" amfi_get_out_of_my_way=1 "*)
    echo "AMFI relaxation hint: detected"
    ;;
  *)
    echo "AMFI relaxation hint: NOT detected"
    ;;
esac
echo

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found. Build it with:" >&2
  echo "  ./Scripts/build-developer-lab.sh" >&2
  exit 2
fi

echo "Code signature:"
if ! /usr/bin/codesign --verify --strict --verbose=2 "$APP" 2>&1; then
  FAILED=1
fi
SIGNING_INFO="$(/usr/bin/codesign -dvv "$APP" 2>&1 || true)"
echo "$SIGNING_INFO" | /usr/bin/grep -E '^(Identifier|Format|CodeDirectory|Signature|TeamIdentifier)=' || true
if echo "$SIGNING_INFO" | /usr/bin/grep -Fq 'Signature=adhoc'; then
  echo "Signature mode: ad-hoc/local"
else
  echo "Signature mode: codesign did not report ad-hoc (inspect above)"
fi
if echo "$SIGNING_INFO" | /usr/bin/grep -Eq '^TeamIdentifier=.+$' && \
   ! echo "$SIGNING_INFO" | /usr/bin/grep -Fq 'TeamIdentifier=not set'; then
  echo "Apple team identifier: present"
else
  echo "Apple team identifier: none"
fi
echo

echo "Embedded entitlements:"
ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APP" 2>&1 || true)"
echo "$ENTITLEMENTS"
if echo "$ENTITLEMENTS" | /usr/bin/grep -A1 -F "<key>$ENTITLEMENT</key>" | /usr/bin/grep -Fq '<true/>'; then
  echo "Restricted virtual-HID entitlement: present and true"
else
  echo "Restricted virtual-HID entitlement: MISSING or false" >&2
  FAILED=1
fi

echo
echo "This script only inspects the machine and app. It does not change SIP, AMFI, NVRAM, or Startup Security."
echo "The definitive test is whether the binary launches and virtual-device creation succeeds."
exit "$FAILED"

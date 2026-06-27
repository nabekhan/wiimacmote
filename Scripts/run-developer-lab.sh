#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA_PATH:-$ROOT/build/DeveloperLabDerivedData}"
APP="$DERIVED_DATA/Build/Products/DeveloperLab/WiiMacMote.app"
SKIP_BUILD=0
FORCE=0

while (( $# > 0 )); do
  case "$1" in
    --no-build)
      SKIP_BUILD=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if (( SKIP_BUILD == 0 )); then
  "$ROOT/Scripts/build-developer-lab.sh"
else
  "$ROOT/Scripts/sign-developer-lab.sh" "$APP"
  "$ROOT/Scripts/diagnose-developer-lab.sh" "$APP"
fi

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  echo "Build it first with ./Scripts/build-developer-lab.sh" >&2
  exit 1
fi

BINARY="$APP/Contents/MacOS/WiiMacMote"
if [[ ! -x "$BINARY" ]]; then
  echo "App executable not found: $BINARY" >&2
  exit 1
fi

BOOT_ARGS="$(/usr/sbin/sysctl -n kern.bootargs 2>/dev/null || true)"
if [[ -z "$BOOT_ARGS" ]]; then
  BOOT_ARGS="$(/usr/sbin/nvram boot-args 2>/dev/null | /usr/bin/sed -E 's/^boot-args[[:space:]]+//' || true)"
fi

AMFI_HINT=0
case " $BOOT_ARGS " in
  *" amfi_get_out_of_my_way=0x1 "*|*" amfi_get_out_of_my_way=0X1 "*|*" amfi_get_out_of_my_way=1 "*)
    AMFI_HINT=1
    ;;
esac

if (( AMFI_HINT == 0 && FORCE == 0 )); then
  echo "The AMFI relaxation boot argument was not visible." >&2
  echo "An ad-hoc app carrying this restricted entitlement may be terminated before main()." >&2
  echo "Use --force only after independently verifying your isolated lab configuration." >&2
  exit 78
fi

echo
echo "Launching the executable directly so AMFI, dyld, and IOKit errors remain in this terminal:"
printf '  %q' "$BINARY" --lab-diagnostics "$@"
printf '\n\n'
exec "$BINARY" --lab-diagnostics "$@"

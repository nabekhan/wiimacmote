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

if (( FORCE == 1 )); then
  exec "$ROOT/Scripts/launch-developer-lab.sh" --app "$APP" --force -- "$@"
fi
exec "$ROOT/Scripts/launch-developer-lab.sh" --app "$APP" -- "$@"

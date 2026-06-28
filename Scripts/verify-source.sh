#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

plutil -lint \
  wiimacmote/Info.plist \
  wiimacmote/WiiMacMote.entitlements \
  WiiMacMote.xcodeproj/project.pbxproj

find "$ROOT" -name ".DS_Store" -type f -delete
find "$ROOT" -name "__MACOSX" -type d -exec rm -rf {} +

python3 - <<'PY'
import json
import plistlib
import stat
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path('.')

for path in [
    root / 'WiiMacMote.xcodeproj/project.xcworkspace/contents.xcworkspacedata',
    root / 'WiiMacMote.xcodeproj/xcshareddata/xcschemes/WiiMacMote.xcscheme',
]:
    ET.parse(path)

for path in (root / 'wiimacmote/Assets.xcassets').rglob('*.json'):
    json.loads(path.read_text())

with (root / 'wiimacmote/WiiMacMote.entitlements').open('rb') as handle:
    entitlements = plistlib.load(handle)
assert 'com.apple.developer.hid.virtual.device' not in entitlements, 'The app must not declare the restricted virtual-HID entitlement'

project = (root / 'WiiMacMote.xcodeproj/project.pbxproj').read_text()
required_project_fragments = [
    'MARKETING_VERSION = 2.0.5;',
    'CURRENT_PROJECT_VERSION = 205;',
    'Security.framework in Frameworks',
    'CoreBluetooth.framework in Frameworks',
    'IOBluetooth.framework in Frameworks',
    'IOKit.framework in Frameworks',
]
for fragment in required_project_fragments:
    assert fragment in project, f'Missing project setting: {fragment}'

removed_project_fragments = [
    'GamepadMapping.swift',
    'VirtualGamepad.swift',
    'VirtualGamepadReports.swift',
    'DiagnosticDSUServer.swift',
    'DeveloperLabEnvironment.swift',
    'WiiMacMote-DeveloperLab.entitlements',
    'CoreHID.framework',
    'DeveloperLab',
]
for fragment in removed_project_fragments:
    assert fragment not in project, f'Removed output/diagnostics feature still referenced: {fragment}'

for source in sorted((root / 'wiimacmote').glob('*.swift')) + sorted((root / 'wiimacmote').glob('*.m')):
    assert f'{source.name} in Sources' in project, f'{source.name} is not in the Sources phase'

for script in [
    root / 'Scripts/build.sh',
    root / 'Scripts/archive-universal.sh',
    root / 'Scripts/test-core.sh',
    root / 'Scripts/verify-source.sh',
]:
    assert script.stat().st_mode & stat.S_IXUSR, f'{script} is not executable'

for path in root.rglob('*'):
    if path.name == '.DS_Store' and path.is_file():
        path.unlink()
        continue
    assert path.name != '__MACOSX', f'Archive debris found: {path}'
PY

if command -v xcrun >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; then
  xcrun swiftc -frontend -parse wiimacmote/*.swift Tests/CoreTests.swift
elif command -v swiftc >/dev/null 2>&1; then
  swiftc -frontend -parse wiimacmote/*.swift Tests/CoreTests.swift
else
  echo "swiftc was not found. Install Xcode, the Command Line Tools, or a Swift toolchain." >&2
  exit 1
fi

./Scripts/test-core.sh

for script in Scripts/*.sh; do
  sh -n "$script"
done

SEARCH_PATHS="wiimacmote WiiMacMote.xcodeproj Scripts"
if [ -d .github ]; then
  SEARCH_PATHS="$SEARCH_PATHS .github"
fi

if grep -R --line-number --exclude='verify-source.sh' \
  -E 'pkill[[:space:]]+bluetoothd|0x028E|DEVELOPMENT_TEAM[[:space:]]*=|VirtualGamepad|DiagnosticDSU|DeveloperLab|CoreHID|com\.apple\.developer\.hid\.virtual\.device|amfi_get_out_of_my_way|SIP' \
  $SEARCH_PATHS; then
  echo "Found removed output/diagnostics code, a privileged action, or a hard-coded signing team." >&2
  exit 1
fi

echo "Source verification passed."

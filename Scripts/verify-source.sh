#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

plutil -lint \
  wiimacmote/Info.plist \
  wiimacmote/WiiMacMote.entitlements \
  wiimacmote/WiiMacMote-DeveloperLab.entitlements \
  WiiMacMote.xcodeproj/project.pbxproj

find "$ROOT" -name ".DS_Store" -type f -delete
find "$ROOT" -name "__MACOSX" -type d -exec rm -rf {} +

python3 - <<'PY'
import json
import plistlib
import re
import stat
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path('.')

for path in [
    root / 'WiiMacMote.xcodeproj/project.xcworkspace/contents.xcworkspacedata',
    root / 'WiiMacMote.xcodeproj/xcshareddata/xcschemes/WiiMacMote.xcscheme',
    root / 'WiiMacMote.xcodeproj/xcshareddata/xcschemes/WiiMacMote Developer Lab.xcscheme',
]:
    ET.parse(path)

for path in (root / 'wiimacmote/Assets.xcassets').rglob('*.json'):
    json.loads(path.read_text())

with (root / 'wiimacmote/WiiMacMote.entitlements').open('rb') as handle:
    standard = plistlib.load(handle)
with (root / 'wiimacmote/WiiMacMote-DeveloperLab.entitlements').open('rb') as handle:
    lab = plistlib.load(handle)
restricted = 'com.apple.developer.hid.virtual.device'
assert restricted not in standard, 'Standard build must not declare the restricted virtual-HID entitlement'
assert lab.get(restricted) is True, 'Developer Lab build must declare the virtual-HID entitlement'

project = (root / 'WiiMacMote.xcodeproj/project.pbxproj').read_text()
required_project_fragments = [
    'VirtualGamepadReports.swift in Sources',
    'DeveloperLabEnvironment.swift in Sources',
    'WiiMacMote-DeveloperLab.entitlements',
    'A80000000000000000000005 /* DeveloperLab */',
    'A80000000000000000000006 /* DeveloperLab */',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG DEVELOPER_LAB $(inherited)";',
    'MARKETING_VERSION = 2.0.5;',
    'CURRENT_PROJECT_VERSION = 205;',
    'CoreHID.framework in Frameworks',
    'Security.framework in Frameworks',
]
for fragment in required_project_fragments:
    assert fragment in project, f'Missing project setting: {fragment}'

for source in sorted((root / 'wiimacmote').glob('*.swift')) + sorted((root / 'wiimacmote').glob('*.m')):
    assert f'{source.name} in Sources' in project, f'{source.name} is not in the Sources phase'

reports = (root / 'wiimacmote/VirtualGamepadReports.swift').read_text()
for fragment in ['vendorID: 0x045E', 'productID: 0x0B13', 'vendorID: 0x057E', 'productID: 0x2009']:
    assert fragment in reports, f'Missing expected experimental identity: {fragment}'
assert 'razerServal' not in reports, 'Unverified Razer compatibility profile should not be shipped'
assert reports.count('case generic') >= 1 and reports.count('case xboxSeries') >= 1 and reports.count('case switchProSimple') >= 1

for script in [
    root / 'Scripts/build.sh',
    root / 'Scripts/archive-universal.sh',
    root / 'Scripts/build-developer-lab.sh',
    root / 'Scripts/sign-developer-lab.sh',
    root / 'Scripts/diagnose-developer-lab.sh',
    root / 'Scripts/run-developer-lab.sh',
    root / 'Scripts/test-core.sh',
    root / 'Scripts/verify-source.sh',
]:
    assert script.stat().st_mode & stat.S_IXUSR, f'{script} is not executable'

assert (root / 'DEVELOPER_LAB.md').is_file(), 'DEVELOPER_LAB.md is missing'
assert (root / 'THIRD_PARTY_NOTICES.md').is_file(), 'THIRD_PARTY_NOTICES.md is missing'

build_lab = (root / 'Scripts/build-developer-lab.sh').read_text()
assert 'CODE_SIGNING_ALLOWED=NO' in build_lab, 'Developer Lab must build independently of an Apple signing team'
assert 'CODE_SIGNING_REQUIRED=NO' in build_lab, 'Developer Lab must not require an Xcode signing identity'
assert "CODE_SIGN_IDENTITY=''" in build_lab, 'Developer Lab must clear the Xcode signing identity'
assert './Scripts/sign-developer-lab.sh' in build_lab, 'Developer Lab must be explicitly ad-hoc signed after build'

sign_lab = (root / 'Scripts/sign-developer-lab.sh').read_text()
assert '--sign -' in sign_lab, 'Developer Lab must use an ad-hoc signature'
assert 'WiiMacMote-DeveloperLab.entitlements' in sign_lab, 'Developer Lab signer must use the restricted-entitlement plist'

run_lab = (root / 'Scripts/run-developer-lab.sh').read_text()
assert 'Contents/MacOS/WiiMacMote' in run_lab, 'Developer Lab runner must execute the app binary directly'
assert 'exec "$BINARY"' in run_lab, 'Developer Lab runner must preserve terminal-visible launch errors'

environment = (root / 'wiimacmote/DeveloperLabEnvironment.swift').read_text()
assert 'SecTaskCopyValueForEntitlement' in environment, 'Runtime entitlement preflight is missing'
assert 'amfi_get_out_of_my_way' in environment, 'AMFI boot-argument hint parser is missing'
assert 'teamIdentifier' in environment and 'bootArguments' in environment, 'Runtime lab diagnostics are incomplete'

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
  -E 'pkill[[:space:]]+bluetoothd|0x028E|DEVELOPMENT_TEAM[[:space:]]*=' \
  $SEARCH_PATHS; then
  echo "Found a removed privileged action, legacy Xbox 360 spoof ID, or hard-coded signing team." >&2
  exit 1
fi

echo "Source verification passed."

# Validation report

Validation date: **June 24, 2026**

## Completed in this environment

- Compiled and ran the portable Swift parser/mapping test executable. All tests passed.
- Parsed every Swift source file with the Swift frontend.
- Linted `Info.plist`, the entitlement plist, and the Xcode project file.
- Validated the workspace and shared scheme XML.
- Validated all asset-catalog JSON files.
- Confirmed every Xcode project file reference resolves and every implementation file belongs to the Sources build phase.
- Checked shell-script syntax and executable permissions.
- Checked that the source contains no `pkill bluetoothd` recovery action, Xbox 360 spoof IDs, hard-coded Apple development team, `.DS_Store`, or `__MACOSX` payload.
- Confirmed the protocol tests cover buttons, status/battery, acknowledgements, malformed packets, 0x30/0x31 acceleration input, extension payload slicing, and both controller profiles.

Run the same portable checks with:

```sh
./Scripts/test-core.sh
./Scripts/verify-source.sh
```

## Not executable in this environment

This workspace is Linux-based, so it cannot run Xcode, link Apple frameworks, access macOS private Bluetooth selectors, or communicate with physical Wii Remote hardware. The following therefore still require a Mac:

- Full Xcode compile/link with the macOS SDK.
- Debug and Release builds on Xcode 15 and Xcode 26.5.
- Apple silicon and Intel executable verification.
- First-run Bluetooth authorization behavior on macOS 14, 15, and 26.
- Red-SYNC pairing, already-paired reconnection, bounded retry, and stale-pairing recovery.
- Original `RVL-CNT-01` (PID 0x0306) and `RVL-CNT-01-TR` (PID 0x0330) input.
- Multi-controller player assignment, LEDs, battery status, rumble, disconnect, and reconnect.
- Motion filtering and centering against real accelerometer calibration variance.
- `IOHIDUserDevice` creation with an Apple-approved virtual-HID entitlement and visibility in intended games.

## Recommended first hardware pass

1. Build unsigned with `./Scripts/build.sh`; confirm the app launches, Bluetooth permission appears, and connecting a remote passes HID callback setup without an IOKit `EXC_BREAKPOINT`/activation assertion.
2. Pair one original remote using red SYNC, exercise every button, rumble, status refresh, disconnect/reconnect, and one stop/start cycle.
3. Repeat with a `-TR` remote, then with two to four simultaneous remotes.
4. Repeat steps 1–3 on one Apple silicon Mac running macOS 26 and one Intel Mac running macOS 14 or 15.
5. Keep experimental virtual HID off for baseline tests; evaluate it separately with raw HID inspection and the exact target games.

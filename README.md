# WiiMacMote 2.0

A modernized macOS utility for discovering, pairing, reading, and translating Nintendo Wii Remote input.

## What changed

- Dedicated serial queues for physical HID input and virtual HID output.
- Bounded pairing retries with cooldowns instead of a failure loop.
- Runtime-checked isolation of the private macOS binary-PIN pairing calls.
- Correct parsing for status, buttons, accelerometer reports, acknowledgements, and extension payloads.
- Up to four simultaneous Wii Remotes with player LEDs, battery estimates, rumble, status refresh, and live report-rate diagnostics.
- Sideways and upright controller profiles.
- Optional accelerometer-to-right-stick mapping with live centering.
- Experimental generic virtual HID gamepad output, without impersonating Xbox hardware.
- A conventional Xcode project that opens on Xcode 15 and newer and produces Apple silicon/Intel release builds.
- Pure Swift protocol and mapping tests that run without Bluetooth hardware.

## Important platform limits

Wii Remote pairing on current macOS still needs private `IOBluetooth` selectors because the legacy PIN is six binary bytes, not a normal text PIN. Those selectors are contained in `WiimotePairingBridge.m` and checked before use so an incompatible future macOS release fails visibly rather than crashing.

macOS also has no generally available supported API for publishing a system-wide virtual game controller. `IOHIDUserDevice` can describe a generic HID gamepad, but current macOS releases normally gate virtual-device creation behind Apple’s restricted `com.apple.developer.hid.virtual.device` entitlement, and software using Apple's Game Controller framework may still ignore virtual devices. That entitlement is deliberately **not** claimed by the default target. The toggle is therefore labelled **experimental** and fails visibly when unavailable. Physical Wii Remote input, diagnostics, LEDs, battery status, rumble, and motion reading do not depend on virtual output.

## Requirements

- macOS 14 Sonoma or newer.
- Xcode 15 or newer. Xcode 26.5 is the current stable toolchain as of June 2026.
- A Mac with Bluetooth.
- An original `Nintendo RVL-CNT-01` or `Nintendo RVL-CNT-01-TR` Wii Remote. Compatible clones may work but are not guaranteed.

## Build and run

1. Open `WiiMacMote.xcodeproj`.
2. Select the **WiiMacMote** scheme and **My Mac**.
3. Choose a signing team in **Signing & Capabilities** if Xcode requests one.
4. Build and run.
5. Approve the Bluetooth permission prompt.
6. Press the red **SYNC** button behind the Wii Remote battery cover.

The physical-controller path does **not** require Input Monitoring or Accessibility permission. The app is intentionally not sandboxed because it communicates with Classic Bluetooth and private legacy-pairing selectors. Experimental virtual HID output may require a separately approved Apple entitlement on current macOS releases.

For command-line verification:

```sh
./Scripts/test-core.sh
./Scripts/verify-source.sh
./Scripts/build.sh
```

## Pairing guidance

Use the red SYNC button for the most reliable pairing. In particular, newer `RVL-CNT-01-TR` remotes can behave differently when awakened with 1 + 2, and output reports may cause them to shut down during setup.

Already-paired remotes are not paired again. Press any button to wake one; WiiMacMote asks macOS to open its existing connection and waits for the HID service.

After two pairing failures, the app stops retrying for 30 seconds. This is deliberate protection against the repeated pairing-daemon loop seen on recent Tahoe builds. Use **Retry** after pressing SYNC again.

## Virtual output mapping

| Wii Remote | Sideways profile | Upright profile |
|---|---|---|
| D-pad | Rotated to gamepad D-pad/left stick | Direct D-pad/left stick |
| 2 / 1 | South / East | West / North |
| A / B | North / West | South / East |
| + / − | Start / Select | Start / Select |
| Home | Home | Home |
| Tilt (optional) | Right stick, rotated | Right stick, direct |

## Project layout

- `WiimoteManager.swift` — application state, Bluetooth permission gate, classic inquiry, and bounded pairing state machine.
- `WiimotePairingBridge.m` — small Objective-C boundary around the binary-PIN private selectors.
- `WiimoteHIDController.swift` — physical HID lifecycle, report I/O, throttled UI snapshots, rumble, LEDs, and motion filtering.
- `WiimoteProtocol.swift` — allocation-light Wii Remote packet parser.
- `VirtualGamepad.swift` — experimental generic virtual HID output.
- `GamepadMapping.swift` — testable controller profiles.
- `Tests/CoreTests.swift` — parser and mapping smoke tests.
- `MODERNIZATION.md` — research findings, design rationale, and remaining work.
- `VALIDATION.md` — checks completed here and the remaining macOS/hardware test matrix.

## Distribution

For a local unsigned build, use `Scripts/build.sh`. For a distributable release, select your Developer ID team, archive in Xcode, sign with Developer ID Application, and notarize. Private API use means Mac App Store submission is not appropriate.

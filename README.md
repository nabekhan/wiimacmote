# WiiMacMote 2.0.5

WiiMacMote discovers, pairs, reads, and translates Nintendo Wii Remote input on modern macOS. The physical-controller path remains useful on its own; virtual gamepad publication is an optional developer experiment.

## Highlights

- Original `RVL-CNT-01` and MotionPlus-inside `RVL-CNT-01-TR` matching.
- Bounded red-SYNC pairing with the Wii Remote's six-byte binary PIN.
- Dedicated serial queues for Bluetooth HID input and virtual output.
- Up to four remotes with player LEDs, battery estimate, rumble, status refresh, report-rate diagnostics, buttons, and accelerometer data.
- Sideways and upright mappings, plus optional filtered tilt-to-right-stick input.
- Three virtual output identities and two publication backends.
- A normal Standard scheme and an isolated Local AMFI Lab path that builds unsigned, applies an explicit ad-hoc entitlement signature, and launches from Terminal for diagnostics.
- Portable Swift tests for protocol parsing, mapping, descriptors, and report encoders.

## Requirements

- macOS 14 Sonoma or newer for physical Wii Remote support.
- Xcode 16 or newer to build this 2.0.5 project (Xcode 26 is recommended for current macOS).
- macOS 15 or newer when selecting the CoreHID backend.
- A Mac with Bluetooth and a Wii Remote.

## Build the normal app

1. Open `WiiMacMote.xcodeproj`.
2. Select the **WiiMacMote** scheme and **My Mac**.
3. Build and run.
4. Grant Bluetooth access and press the red **SYNC** button behind the Wii Remote battery cover.

The Standard scheme deliberately omits `com.apple.developer.hid.virtual.device`. Buttons, motion, LEDs, battery, rumble, and diagnostics still work; virtual device creation may fail cleanly.

Command-line checks:

```sh
./Scripts/verify-source.sh
./Scripts/build.sh
```

## Local AMFI Lab virtual output

For a Mac whose owner has already deliberately relaxed SIP and AMFI for development, run:

```sh
./Scripts/run-developer-lab.sh -- \
  --enable-virtual-gamepad \
  --profile xbox-series \
  --backend iohid
```

The script builds without any Apple team or provisioning profile, explicitly applies an ad-hoc signature containing `com.apple.developer.hid.virtual.device`, verifies it, prints SIP/boot-argument diagnostics, and launches `WiiMacMote.app/Contents/MacOS/WiiMacMote` directly so launch failures remain visible in Terminal. Run without the arguments first when you want to verify physical Wii Remote input before virtual output is enabled.

The Developer Lab configuration also disables Hardened Runtime for the lab build only, uses a separate bundle identifier, and defines `DEVELOPER_LAB` so the app displays runtime entitlement and AMFI-hint status. It does **not** borrow WaveBird's approved signature and does **not** modify SIP, AMFI, NVRAM, or Startup Security.

Detailed commands, failure meanings, and restoration guidance are in `DEVELOPER_LAB.md`. The Standard app remains usable on normally secured Macs without the restricted entitlement.

## Virtual identities

| Identity | When to try it | Current limitation |
|---|---|---|
| Generic HID Gamepad | Honest raw-HID testing and descriptor debugging | Game Controller clients may ignore an unknown virtual gamepad |
| Xbox Wireless Controller (Series) | Best first choice for broad game, Steam/SDL, and Game Controller compatibility | It is compatibility metadata, not a real Bluetooth Xbox controller; recognition is not guaranteed |
| Switch Pro Controller (simple mode) | Nintendo-like layout and a closer conceptual match to a Wii Remote | Only report `0x3F` is emitted; the full Nintendo subcommand handshake, motion, and HD rumble are not implemented |

A single Joy-Con is physically the closest modern controller to a Wii Remote, but impersonating one is not the best default for games: a lone Joy-Con has a partial control set, orientation-specific mappings, and more protocol state. Switch Pro is the more practical Nintendo identity; Xbox is the compatibility-first identity.

The Xbox profile uses the current Bluetooth Series VID/PID (`045E:0B13`), a native 17-byte input report, and a vendor GIP companion stream. It was chosen over an unverified Model 1708 dump because its descriptor/report behavior is documented by a current open-source macOS implementation. The app never promises 100% compatibility: Apple states that Game Controller contains checks that may ignore virtual HID devices.

## Publication backends

- **Automatic**: tries `IOHIDUserDevice` first, then CoreHID where available.
- **IOHIDUserDevice**: works with the macOS 14 deployment target and is the compatibility baseline.
- **CoreHID**: uses `HIDVirtualDevice` on macOS 15 or newer.

Both backends are governed by the same restricted-entitlement boundary. CoreHID is a fallback implementation, not an entitlement bypass.

## Pairing guidance

Use the red SYNC button. Holding 1 + 2 uses a different legacy pairing path and is less reliable, especially with `-TR` remotes. Already-paired remotes are opened directly. After two pairing failures, WiiMacMote pauses instead of repeatedly hammering the Bluetooth service.

## Project map

- `WiimoteManager.swift` — app state, persistence, Bluetooth permission/power gate, inquiry, and bounded pairing.
- `WiimotePairingBridge.m` — runtime-checked Objective-C boundary for binary-PIN pairing selectors.
- `WiimoteHIDController.swift` — physical HID lifecycle, report I/O, player sessions, and snapshots.
- `WiimoteProtocol.swift` — Wii Remote report parser.
- `GamepadMapping.swift` — canonical gamepad state and Wii Remote mappings.
- `VirtualGamepadReports.swift` — virtual identities, descriptors, and report encoders.
- `VirtualGamepad.swift` — IOHIDUserDevice/CoreHID publishers and lifecycle.
- `DeveloperLabEnvironment.swift` — runtime entitlement visibility and AMFI boot-argument diagnostics.
- `DEVELOPER_LAB.md` — restricted-entitlement local test procedure and validation ladder.
- `THIRD_PARTY_NOTICES.md` — source attribution and license notices.

## Distribution boundary

The private Classic Bluetooth pairing selectors make Mac App Store distribution inappropriate. A public Developer ID build that carries the virtual-HID entitlement also requires Apple authorization for that entitlement. The Developer Lab scheme is for local research, not redistribution.

# WiiMacMote 2.0.5

WiiMacMote discovers, pairs, reads, and translates Nintendo Wii Remote input on modern macOS. The physical-controller path remains useful on its own; virtual gamepad publication is an optional developer experiment.

## Highlights

- Original `RVL-CNT-01` and MotionPlus-inside `RVL-CNT-01-TR` matching.
- In-app red-SYNC pairing with the Wii Remote's six-byte binary PIN, followed by user-space HID input/output.
- Dedicated serial queues for Bluetooth HID input and virtual output.
- Up to four remotes with player LEDs, battery estimate, rumble, status refresh, report-rate diagnostics, buttons, and accelerometer data.
- Wii protocol builders/parsers for memory/register reads and writes, EEPROM calibration, IR points, speaker reports, Nunchuk, Classic Controller, MotionPlus, and Balance Board packets.
- Local DSU/Cemuhook UDP output on `127.0.0.1:26760` for emulator-compatible controller data and rumble.
- Native macOS Settings-style controller UI with grouped panes, sidebar navigation, and original vector controller artwork.
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

The Standard scheme deliberately omits `com.apple.developer.hid.virtual.device`. Buttons, motion, LEDs, battery, rumble, and diagnostics still work; virtual-output controls remain visible, but device creation fails cleanly unless the running app is signed with the restricted entitlement and accepted by host policy.

## Hardware support status

| Hardware/protocol area | Status |
|---|---|
| Wii Remote core buttons, LEDs, rumble, battery, accelerometer | Implemented; hardware validation still recommended after Bluetooth changes |
| Red-SYNC pairing | Implemented with private macOS Classic Bluetooth/CoreBluetooth selectors because the Wii Remote requires a binary PIN |
| Disconnect | Sends speaker mute/disable, IR disable, LEDs off, and rumble off, then closes HID/Bluetooth; the Wii protocol has no documented host power-off report |
| EEPROM calibration and memory/register commands | Implemented at parser/builder level and read for accelerometer calibration |
| IR camera | Initialization builders and Basic/Extended point parsing are implemented; the camera is not enabled by default |
| Speaker | Initialization/data/mute builders are implemented; disconnect mutes and disables it |
| Nunchuk, Classic Controller, MotionPlus | Extension init, identity detection, and input decoding are implemented |
| Balance Board | Device matching, extension init, calibration read, packet decoding, and weight interpolation are implemented |
| Guitar/drums/other extensions | Identified when possible, exposed as raw extension bytes |

Command-line checks:

```sh
./Scripts/verify-source.sh
./Scripts/build.sh
```

`build.sh` ad-hoc signs the built Release app. If you are testing the copy in `/Applications`, refresh that installed app's local signature with:

```sh
./Scripts/build.sh --sign-installed
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

The app displays runtime entitlement, signing, and AMFI-hint status in every build. The Developer Lab configuration additionally disables Hardened Runtime for the lab product only, uses a separate bundle identifier, and defines `DEVELOPER_LAB` for the stronger local-lab warning. It does **not** modify SIP, AMFI, NVRAM, or Startup Security.

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

Use the red SYNC button. Holding 1 + 2 or pressing other normal buttons uses a different legacy connection path and is less reliable, especially with `-TR` remotes. If macOS shows a Bluetooth **Connection Request** dialog, cancel it and press red SYNC instead; that dialog is BluetoothUIServer handling non-SYNC connection mode outside WiiMacMote's binary-PIN path. The Scan toggle keeps discovery enabled and recreates Classic inquiry after that interruption. Already-paired remotes are opened directly. If Classic inquiry returns `0xE00002E2`, the app logs CoreBluetooth state, bundle path, and entitlement visibility because that value is `kIOReturnNotPermitted` from macOS, not a Wii packet error. After two pairing failures, WiiMacMote pauses instead of repeatedly hammering the Bluetooth service.

For local copied/ad-hoc installs, macOS may deny Classic Bluetooth until the installed app bundle has a fresh local signature. Quit WiiMacMote, run this for the app you launch, then start it again:

```sh
codesign --force --deep --sign - /Applications/WiiMacMote.app
```

This is a development workaround for local app identity/TCC state. Release builds should use normal signing and notarization.

## Project map

- `WiimoteManager.swift` — app state, persistence, Bluetooth permission/power gate, inquiry, and bounded pairing.
- `WiimoteHIDController.swift` — physical HID lifecycle, report I/O, player sessions, and snapshots.
- `WiimoteProtocol.swift` — Wii Remote report parser, output report builders, extension decoders, and calibration helpers.
- `GamepadMapping.swift` — canonical gamepad state and Wii Remote mappings.
- `DiagnosticDSUServer.swift` — local DSU/Cemuhook UDP server backed by generic controller snapshots.
- `VirtualGamepadReports.swift` — virtual identities, descriptors, and report encoders.
- `VirtualGamepad.swift` — IOHIDUserDevice/CoreHID publishers and lifecycle.
- `DeveloperLabEnvironment.swift` — runtime entitlement visibility and AMFI boot-argument diagnostics.
- `DEVELOPER_LAB.md` — restricted-entitlement local test procedure and validation ladder.
- `THIRD_PARTY_NOTICES.md` — source attribution and license notices.

## Distribution boundary

Virtual-HID publication in a public Developer ID build requires Apple authorization for the restricted entitlement. The Standard app keeps physical Wii Remote input in user-space HID after WiiMacMote completes Classic Bluetooth pairing.

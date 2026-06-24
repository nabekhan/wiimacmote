# Modernization research and engineering notes

Research date: **June 24, 2026**

## Baseline audit

The uploaded project was a useful prototype, but several implementation details explained the reported rough edges:

1. **Virtual gamepad support was present, but fragile.** The code created an `IOHIDUserDevice`, then advertised Microsoft's Xbox 360 vendor/product IDs even though its HID descriptor was a different generic eight-byte format. That can confuse compatibility databases, and current macOS may ignore virtual HID devices in the Game Controller stack.
2. **Pairing could loop forever.** Any failure scheduled another private pairing attempt every three seconds, with no cap, cooldown, or distinction between transient and structural errors.
3. **The main thread did too much.** Discovery, HID callbacks, report parsing, virtual reports, and SwiftUI publication all converged on the main run loop.
4. **The input report buffer leaked.** A 64-byte callback buffer was allocated for each device and never owned or deallocated.
5. **Protocol coverage was narrow.** Only 0x20, 0x30, and 0x31 were partially handled; accelerometer data was requested but ignored, acknowledgements were not surfaced, and extension payload layouts were absent.
6. **Output state was not centralized.** LEDs and rumble share a bit in Wii Remote output reports, so independent writes could accidentally clear rumble or player LEDs.
7. **The project file was machine-specific.** It used Xcode 26's synchronized-root-group format and a hard-coded development team, contributing to reports that the project would not open or build on Intel/older Xcode installations.
8. **The UI exposed an administrator `pkill bluetoothd` action.** Restarting a system daemon is disruptive and is not an acceptable normal recovery path for a controller utility.

## Current macOS target

Apple lists **macOS Tahoe 26.5.1** as the latest stable macOS release on June 24, 2026. Apple also lists **Xcode 26.5** as the latest stable Xcode release; macOS 27 and Xcode 27 were in beta. This project targets macOS 14+ so it remains usable on supported Intel systems while being buildable and testable with current toolchains.

Sources:

- [Apple: latest macOS versions](https://support.apple.com/109033)
- [Apple Developer software releases](https://developer.apple.com/news/releases/)
- [macOS Tahoe 26 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes)

## Pairing research

A Wii Remote uses Bluetooth Classic HID. When discoverable through the red SYNC button, the legacy pairing PIN is the Mac Bluetooth controller address in reverse byte order. It is six binary bytes, which is the critical detail: ordinary text-PIN APIs alter the value.

Dolphin's `WiimotePair` utility demonstrates the modern macOS workaround:

- initialize CoreBluetooth so macOS establishes the pairing coordinator connection;
- run a **Classic** `IOBluetoothDeviceInquiry`;
- skip devices already paired;
- call the private `setUserDefinedPincode:` selector;
- obtain the private classic peer and pairing type;
- pass the reversed six-byte key to `IOBluetoothCoreBluetoothCoordinator`.

This release keeps that proven algorithm but isolates it in one Objective-C class, checks every private selector at runtime, limits retries, and emits actionable diagnostics.

Sources:

- [Dolphin WiimotePair](https://github.com/dolphin-emu/WiimotePair)
- [WiimotePair pairing implementation](https://github.com/dolphin-emu/WiimotePair/blob/master/WiimotePair/ViewController.m)
- [xwiimote protocol documentation](https://github.com/xwiimote/xwiimote/blob/master/doc/PROTOCOL)

## Dolphin input implementation

Current Dolphin uses its cross-platform HID backend for real Wii Remotes. Relevant ideas carried into this rewrite are:

- enumerate by Nintendo vendor/product IDs, then validate the device;
- keep report parsing separate from transport;
- send report mode first and request status after a short delay;
- preserve the Wii report ID as both the `IOHIDDeviceSetReport` argument and the first byte of the macOS report buffer;
- model button precision bits separately from actual buttons;
- treat extensions and high-rate features as optional layers rather than initializing everything unconditionally.

The rewrite intentionally does **not** copy Dolphin code. It follows the documented protocol and uses independently written Swift data structures and tests.

Sources:

- [Dolphin real Wii Remote backend](https://github.com/dolphin-emu/dolphin/tree/master/Source/Core/Core/HW/WiimoteReal)
- [Dolphin Wii Remote reports](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/HW/WiimoteCommon/WiimoteReport.h)
- [hidapi macOS backend](https://github.com/libusb/hidapi/blob/master/mac/hid.c)

## Virtual controller reality on macOS

Apple's Game Controller framework can consume supported physical controllers and can create on-screen virtual controls, but it does not expose a generally available system-wide virtual hardware controller API. Current CoreHID/DriverKit documentation associates virtual HID creation with the restricted `com.apple.developer.hid.virtual.device` entitlement. In January 2026 an Apple frameworks engineer also stated that `IOHIDUserDevice` or DriverKit may technically fake a controller, while warning that Game Controller contains checks that can ignore virtual HID devices and that this behavior is not guaranteed.

Accordingly, WiiMacMote 2.0:

- calls the feature **experimental virtual HID**, not guaranteed Game Controller support;
- does not claim the restricted entitlement in the default build and reports creation failure clearly;
- uses a truthful generic gamepad descriptor;
- no longer spoofs Microsoft hardware IDs;
- keeps physical input features useful when virtual output is disabled or ignored;
- deduplicates unchanged virtual reports and serializes them away from the UI thread.

Sources:

- [Apple: virtual HID entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device)
- [Apple Developer Forums: Virtual Controllers on Mac](https://developer.apple.com/forums/thread/812774)

## Legacy driver lessons

Older projects remain valuable architectural references but are not suitable dependencies on current macOS:

- **WJoy/fooHID** relied on a kernel extension and historical SIP workarounds.
- **WiiController** implemented many extensions but documents that it stopped working on macOS 12+.
- **HID Wiimote** on Windows separated transport, translators, and native gamepad exposure.
- **hid-wiimote/xwiimote** on Linux modularized features and initializes optional hardware such as IR only when requested.

Those projects support the new separation between pairing, physical transport, protocol parsing, mapping, and optional outputs.

References:

- [WJoy](https://github.com/alxn1/WJoy)
- [WiiController](https://github.com/ts1/WiiController)
- [HID Wiimote](https://github.com/jloehr/HID-Wiimote)
- [xwiimote](https://github.com/xwiimote/xwiimote)

## New architecture

### Bluetooth state machine

CoreBluetooth is used only as a permission/power gate and to establish the coordinator connection used by macOS pairing. Classic discovery remains in `IOBluetoothDeviceInquiry`. A pairing address can receive one automatic retry; the second failure creates a 30-second cooldown.

### Physical HID service

`IOHIDManagerSetDispatchQueue` and `IOHIDManagerActivate` move callbacks to a dedicated serial queue. Input reports are registered once on the manager before activation, which is required by the dispatch-backed IOKit lifecycle and avoids mutating an already active device. The manager owns report buffers and device open/close state; each device session owns only protocol/output state, its motion filter, virtual device, and diagnostics counters. A weak callback context is retained until the manager's asynchronous cancel handler runs, so stop/restart and deinitialization cannot leave a dangling Swift object pointer. SwiftUI receives immutable snapshots no more than 30 times per second.

### Protocol parser

The parser understands status (0x20), acknowledgements (0x22), normal input modes (0x30–0x37), extension-only mode (0x3D), and the button/accelerometer bit packing. It preserves X's 10-bit precision and correctly places the 9-bit Y/Z samples in the same 10-bit coordinate space instead of duplicating unavailable low bits. Extension bytes are retained for future decoders. Interleaved 0x3E/0x3F frames are deliberately ignored until their two-frame assembly is implemented correctly.

### Output pipeline

Player LEDs and rumble are composed into the same output byte. Motion mode uses report 0x31; button-only mode uses 0x30. Status is requested 200 ms after mode selection to avoid back-to-back setup transactions.

### Testable mapping

Sideways and upright mappings are pure Swift. Motion mapping uses a low-pass filter, dead zone, and user-triggered center calibration. Parser and mapping tests run without IOKit or hardware.

## Remaining high-value work

1. Test on a hardware matrix: original 0x0306, MotionPlus-inside 0x0330 / `-TR`, Apple silicon, Intel, macOS 14/15/26.
2. Read per-device accelerometer calibration from EEPROM instead of using approximate center/span values.
3. Implement Nunchuk, Classic Controller, and MotionPlus decoders as independent extension modules.
4. Add infrared camera initialization only when an IR consumer is enabled.
5. Add an SDL/HID diagnostic page that proves whether a target game sees the experimental virtual device.
6. Establish Developer ID signing, notarization, crash reporting, and an automated hardware regression checklist.
7. Track Apple's virtual-controller feedback; replace `IOHIDUserDevice` immediately if a supported system API appears.

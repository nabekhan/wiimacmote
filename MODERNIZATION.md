# Modernization notes

## Physical Wii Remote path

A Wii Remote is a Bluetooth Classic HID device. Red-SYNC pairing uses a six-byte binary PIN derived from the host Bluetooth address, so ordinary text-PIN APIs are insufficient. WiiMacMote uses the same macOS pairing shape as Dolphin's WiimotePair: Classic Bluetooth inquiry, `IOBluetoothDevicePair`, a forced PIN delegate callback, and the private CoreBluetooth coordinator to submit the raw binary PIN. After pairing, runtime input/output remains user-space HID.

The HID layer uses one dispatch-backed `IOHIDManager`, installs callbacks before activation, retains callback lifetime through asynchronous cancellation, and publishes immutable UI snapshots at a limited rate. Report parsing, memory/register report builders, extension decoders, and mapping remain independent from IOKit so they can be tested on any Swift host.

Disconnect is intentionally a quiet-and-close sequence rather than a fake power command. The Wii Remote protocol documents host shutdown as closing the L2CAP/HID connection; WiiMacMote first mutes/disables speaker output, disables IR, clears LEDs, and forces rumble off before closing HID and the Classic Bluetooth connection.

Useful references:

- https://github.com/dolphin-emu/WiimotePair
- https://github.com/dolphin-emu/dolphin/tree/master/Source/Core/Core/HW/WiimoteReal
- https://github.com/xwiimote/xwiimote/blob/master/doc/PROTOCOL
- https://github.com/libusb/hidapi/blob/master/mac/hid.c

## Virtual controller boundary

Apple provides two technically usable publication mechanisms:

- `IOHIDUserDevice`, used as the macOS 14-compatible baseline.
- CoreHID `HIDVirtualDevice`, available on macOS 15 or newer.

Both are subject to `com.apple.developer.hid.virtual.device`. CoreHID is therefore an API modernization/fallback, not a way around signing policy. Apple engineering has also stated that Game Controller contains checks intended to ignore some virtual HID devices and that compatibility with faked native controllers is not guaranteed.

For pre-approval development, the Local AMFI Lab path builds without an Apple team and then applies an explicit ad-hoc signature containing the entitlement. That path only has a chance to run on a developer-owned Mac where AMFI has deliberately been relaxed; it is not a distribution mechanism and does not reuse another project's approved signature.

References:

- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device
- https://developer.apple.com/documentation/corehid/hidvirtualdevice
- https://developer.apple.com/forums/thread/812774

## Why Xbox Series is the default

For a Wii Remote, there are two different meanings of “best”:

- **Best compatibility target:** Xbox Wireless Controller. Many games, Steam/SDL, and macOS mappings already understand Xbox-style buttons and axes.
- **Closest physical/conceptual target:** one Joy-Con. It can be held upright or sideways and includes motion, but a single half-controller is not a universal full gamepad and requires more protocol/session behavior.

Switch Pro is the practical middle ground: Nintendo identity and layout, but a conventional full gamepad. The 2.0.5 implementation exposes simple input report `0x3F`; full recognition may require Nintendo's initialization/subcommand flow and report `0x30`, which is future work.

The Xbox implementation uses Series VID/PID `045E:0B13` rather than blindly claiming the Model 1708 `045E:02FD` profile described in an unverified snippet. WiiMacMote still labels it experimental and provides no universal compatibility promise.

Attribution is listed in `THIRD_PARTY_NOTICES.md`.

## 2.0.5 architecture

`VirtualGamepadState` is the canonical, vendor-neutral state. `VirtualGamepadReports` encodes it into one of three immutable specifications. `VirtualGamepad` owns a serial output queue and one backend. Changing identity or backend resets/removes the previous device before creating the replacement. `DiagnosticDSUServer` consumes the same generic controller snapshots for local DSU/Cemuhook UDP output, so emulator diagnostics are not tied to Wii-specific parser internals.

The backend interface deliberately distinguishes synchronous IOKit publication from asynchronous CoreHID dispatch. Both send an initial neutral state, deduplicate unchanged state, and attempt a neutral report before cancellation.

The SwiftUI shell now follows macOS System Settings structure: a sidebar for controller, Bluetooth, output, saved-device, and diagnostic panes; grouped rows for settings; and original vector silhouettes for Wii Remote hardware instead of external image assets.

The Xcode project weak-links CoreHID and guards all CoreHID use by SDK import and runtime availability. The Standard and Developer Lab schemes share source but not entitlements, so virtual-output controls are available in both builds and fail cleanly when signing or host policy rejects publication. `DeveloperLabEnvironment` checks the entitlement visible to the running task and reports whether the commonly used AMFI laboratory boot-argument token is present; the direct-launch script preserves terminal-visible launch failures.

## Remaining high-value work

1. Hardware-test all profiles on macOS 14, 15, and 26, Apple silicon and Intel.
2. Add an in-app IORegistry/raw-HID/GCController diagnostic ladder.
3. Implement the full Switch Pro session handshake and output reports.
4. Add optional DualShock 4 or DualSense identities only after verifying descriptors and report behavior on current macOS.
5. Add explicit user controls for optional IR and speaker enablement instead of keeping those builders internal.
6. Feed EEPROM accelerometer calibration into the live motion filter instead of only loading/logging it.
7. Collect evidence for an Apple entitlement request and file Game Controller feedback.

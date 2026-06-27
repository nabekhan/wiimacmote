# Changelog

## Unreleased

- Restored in-app Wii Remote red-SYNC pairing through an Objective-C `WMPairingBridge` that owns the private binary-PIN IOBluetooth/CoreBluetooth selectors.
- Added CoreBluetooth permission gating and Classic Bluetooth diagnostics for bundle path, entitlement visibility, CoreBluetooth state, and `IOBluetoothDeviceInquiry` failures such as `kIOReturnNotPermitted`.
- Added saved Wii Remote rows, permission-denied UI handling, and decoded extension/IR/Balance Board status in controller cards.
- Reworked the app into a native macOS Settings-style interface with sidebar navigation, grouped panes, plain diagnostic labels, and original vector controller artwork.
- Added a saved-controller Forget action backed by macOS Bluetooth unpair/remove private-selector probes.
- Changed disconnect to mute/disable speaker output, disable IR, blank LEDs, force rumble off, then close HID and the Classic Bluetooth connection.
- Suppressed non-success Classic inquiry completion warnings when WiiMacMote intentionally stopped inquiry after finding or pairing a remote.
- Suppressed macOS `0x00000001` Classic inquiry completions that occur as benign empty/interrupted discovery results.
- Changed saved-device removal to verify the paired-device list after private selector calls instead of trusting side-effect selectors' return registers.
- Clarified that macOS Bluetooth Connection Request prompts come from Wii Remote non-SYNC button wake/connection mode and should be canceled in favor of red SYNC pairing.
- Replaced separate one-shot/continuous scan controls with a single persistent Scan toggle that recreates Classic inquiry after unintentional interruptions or start failures.
- Documented the local ad-hoc `codesign --force --deep --sign - /Applications/WiiMacMote.app` workaround for Classic Bluetooth `kIOReturnNotPermitted` on copied app bundles.
- Changed `Scripts/build.sh` to ad-hoc sign the built Release app and added `--sign-installed` for refreshing `/Applications/WiiMacMote.app`.
- Exposed the virtual-output environment status in Standard and Developer Lab builds while keeping the restricted entitlement isolated to the lab signing path.
- Added Wii protocol builders/parsers for read/write memory/register reports, read-data responses, speaker reports, IR initialization/points, EEPROM accelerometer calibration, extension initialization/identity, Nunchuk, Classic Controller, MotionPlus, and Balance Board calibration/input.
- Expanded portable core tests for protocol builders, memory reads, IR points, extension decoders, and calibration parsing.

## 2.0.5 — Explicit local AMFI developer path

- Clarified that the Developer Lab path uses only an explicit local ad-hoc signature.
- Changed the command-line Developer Lab build to compile with signing disabled, then apply an explicit ad-hoc signature containing `com.apple.developer.hid.virtual.device`.
- Added `run-developer-lab.sh` plus `launch-developer-lab.sh` to build/sign and execute the app binary directly so AMFI, dyld, and IOKit failures remain visible in Terminal.
- Added `diagnose-developer-lab.sh` (with a `preflight-developer-lab.sh` alias) to verify the app signature/entitlement and print SIP plus AMFI boot-argument hints without changing host security.
- Added runtime `SecTaskCopyValueForEntitlement` diagnostics and a `kern.bootargs` AMFI-hint check in the app banner and diagnostic log.
- Improved virtual-device creation errors to distinguish a missing runtime entitlement from an IOKit/CoreHID failure after the entitlement is visible.
- Made `IOHIDUserDevice` the default backend for a fresh Developer Lab preference domain while preserving CoreHID as a comparison backend.
- Added Security.framework linkage and updated build/source verification for the new developer-lab pipeline.
- Bumped the app to version 2.0.5 (build 205).

## 2.0.4 — Developer Lab virtual controller profiles

- Added a separate **WiiMacMote Developer Lab** scheme and build configuration.
- Added `com.apple.developer.hid.virtual.device` only to the Developer Lab entitlement file; the Standard build remains safe and entitlement-free.
- Added IOHIDUserDevice and macOS 15+ CoreHID publication backends with automatic fallback.
- Added Generic HID, Xbox Wireless Controller (Series), and Switch Pro simple-mode identities.
- Added the real Xbox Series-style 17-byte input layout, SDL GIP companion report, Guide edge report, and weak-linked CoreHID support.
- Added Switch Pro report `0x3F` output with explicit disclosure that the Nintendo handshake/motion/HD-rumble protocol is incomplete.
- Added persisted identity/backend selectors, live backend diagnostics, build-flavor lab warnings, and an Accessibility settings shortcut.
- Added local build/sign scripts that never alter SIP, AMFI, NVRAM, or Startup Security.
- Added descriptor/report tests, project/entitlement verification, Developer Lab documentation, and third-party attribution.
- Bumped the app to version 2.0.4 (build 204).

## 2.0.3 — macOS dispatch-HID runtime fix

- Registers one `IOHIDManager` input callback before activation.
- Removes per-device callback registration that trapped on current macOS.
- Retains callback context and manager lifetime through asynchronous cancellation.

## 2.0.2 — Xcode 26 callback compatibility

- Treats the callback report buffer as the non-optional pointer imported by current SDKs.

## 2.0.1 — Xcode 26 SDK compatibility

- Updated callback imports, HID property bridging, and timestamped virtual-report publication.

## 2.0.0

- Rebuilt discovery/pairing as a bounded state machine.
- Isolated private binary-PIN selectors.
- Added dedicated HID queues, multi-controller sessions, LEDs, battery, rumble, report parsing, motion mapping, diagnostics, and portable tests.

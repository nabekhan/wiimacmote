# Changelog

## 2.0.5 — Explicit local AMFI developer path

- Clarified that WaveBird is a protocol/reference source only; its Apple-authorized signature is not used by WiiMacMote.
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
- Added descriptor/report tests, project/entitlement verification, Developer Lab documentation, and WaveBird MIT attribution.
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

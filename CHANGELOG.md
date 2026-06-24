# Changelog

## 2.0.3 — macOS 26 dispatch-HID runtime fix

- Registers one `IOHIDManager` input-report callback before manager activation instead of registering per-device callbacks after activation.
- Removes the per-session report buffers and the matching unregister calls that could trap inside IOKit on current macOS.
- Keeps all matching, removal, and report callbacks serialized on the dedicated HID dispatch queue.
- Lets `IOHIDManagerOpen`/`IOHIDManagerClose` own device access and retains the manager until its asynchronous cancel handler runs.
- Uses a retained callback context with a weak controller reference so queued callbacks safely no-op during deinitialization or stop/restart.

## 2.0.2 — Xcode 26 input-report callback compatibility

- Treats the `IOHIDReportCallback` report buffer as the non-optional pointer imported by the Xcode 26 SDK.
- Continues to unwrap only the callback context and sender pointers before dispatching a report.

## 2.0.1 — Xcode 26 SDK compatibility

- Updated IOHID manager callbacks for the SDK's non-optional `IOHIDDevice` parameter.
- Bridged string-based HID property keys back to `CFString` at the IOKit call boundary.
- Replaced the unavailable legacy `IOHIDUserDeviceHandleReport` Swift symbol with `IOHIDUserDeviceHandleReportWithTimeStamp` and a monotonic Mach timestamp.

## 2.0.0 — 2026-06-24

- Rebuilt Bluetooth discovery and pairing as a bounded state machine.
- Isolated private binary-PIN selectors behind a checked Objective-C bridge.
- Added dedicated queues for IOHID input and virtual HID output.
- Fixed per-device report-buffer ownership.
- Added multi-Wii-Remote sessions, player LEDs, battery estimates, status refresh, rumble, report rate, and live button diagnostics.
- Added report parsing for buttons, status, acknowledgements, accelerometer modes, and raw extension payloads.
- Added sideways/upright mappings and optional filtered motion-to-right-stick output.
- Replaced Xbox VID/PID spoofing with a generic virtual gamepad descriptor.
- Added report deduplication and neutral-state cleanup.
- Removed the privileged Bluetooth daemon restart action.
- Replaced the Xcode 26 synchronized project with an explicit Xcode 15-compatible universal project.
- Removed hard-coded signing-team settings.
- Added pure Swift parser/mapping tests and build verification scripts.

## Verification hardening

- Rejects unassembled 0x3E/0x3F interleaved input instead of misparsing it.
- Stops and times out discovery cleanly for already-paired remotes.
- Cancels pending pairing work when Bluetooth powers off or authorization changes.
- Removes unsafe manual HID release and retains callback buffers through disconnect drain.
- Uses asynchronous cancel-lifetime ownership for virtual HID objects.
- Documents the restricted virtual-HID entitlement boundary on current macOS.
- Corrects Y/Z accelerometer reconstruction: their 9 effective bits are represented in 10-bit coordinate space without inventing missing precision.
- Restores the selected data-reporting mode after extension connect/disconnect status events.
- Uses the explicit Classic Bluetooth inquiry search value required by the current Swift importer.

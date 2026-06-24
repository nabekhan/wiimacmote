# Building and validating WiiMacMote

## Supported build hosts

- macOS 14 or newer.
- Xcode 15 or newer.
- Apple silicon or Intel.

The project file uses object version 56 and explicit file groups. It intentionally avoids Xcode 26 synchronized folders so older compatible Xcode releases and Intel Macs can open it.

## Xcode

Open `WiiMacMote.xcodeproj`, select the WiiMacMote scheme, choose My Mac, then build.

No development team is stored in source control. For an ad-hoc local run, Xcode can sign automatically. For release distribution, select a Developer ID team in the target's Signing & Capabilities pane.

## Command line

```sh
./Scripts/test-core.sh
./Scripts/verify-source.sh
./Scripts/build.sh
```

`build.sh` performs a Release build with code signing disabled and places DerivedData under `build/`. It is useful for compilation verification, not distribution.

To create a universal archive after configuring signing:

```sh
./Scripts/archive-universal.sh
```

The archive explicitly requests `arm64 x86_64` and sets `ONLY_ACTIVE_ARCH=NO`.

## Permissions and capabilities

- App Sandbox: off.
- Hardened Runtime: on.
- Bluetooth device entitlement: on.
- Bluetooth usage description: present in `Info.plist`.
- Input Monitoring: not requested.
- Accessibility: not requested.
- Restricted virtual-HID entitlement: **not included** in the default target. Apple controls access to `com.apple.developer.hid.virtual.device`; without it, experimental virtual output may fail cleanly at creation time. Raw Wii Remote input, battery, LEDs, rumble, motion, and diagnostics do not depend on that entitlement.

## Validation checklist

1. `Scripts/test-core.sh` passes.
2. Xcode builds Debug and Release with no source errors.
3. `lipo -archs` reports both `arm64` and `x86_64` for the release binary when building universal.
4. First launch shows the Bluetooth permission prompt.
5. Red-SYNC pairing succeeds without repeated error loops.
6. Existing paired remotes reconnect on a normal button press.
7. Buttons, battery, player LED, report rate, rumble, and motion update.
8. Connecting/removing four devices does not leak report buffers or leave virtual buttons held.
9. Disabling virtual output immediately sends a neutral report and removes the user device.
10. The target game's raw HID and/or Game Controller behavior is recorded, because virtual-device recognition is application-specific.

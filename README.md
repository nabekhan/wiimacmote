# WiiMacMote

WiiMacMote is a macOS utility for pairing and checking Nintendo Wii controllers over Bluetooth.

![Screenshot](screenshot.png "Screenshot")

## Features

- Pairs new Wii Remotes using the red SYNC button.
- Reconnects saved Wii Remotes and Wii Fit Balance Boards from macOS Bluetooth.
- Shows active controllers first, including buttons, battery, player LEDs, rumble, MotionPlus capability, and extension status.
- Tracks saved controllers and saved extensions with local Forget controls.
- Provides a Bluetooth page for pairing controls, current status, and diagnostic logs.

## Requirements

- macOS 14 or newer.
- Xcode 16 or newer.
- Bluetooth-capable Mac.
- Nintendo Wii Remote, Wii Remote Plus, Wii Fit Balance Board, or compatible Wii extension.

## Build

- Open `WiiMacMote.xcodeproj`.
- Select the `WiiMacMote` scheme and `My Mac` destination.
- Build and run from Xcode.
- Or run `./Scripts/build.sh`.
- Run source checks with `./Scripts/verify-source.sh`.

Local copied apps may need fresh ad-hoc signing for macOS Bluetooth permission:

```sh
codesign --force --deep --sign - /Applications/WiiMacMote.app
```

You can also run:

```sh
./Scripts/build.sh --sign-installed
```

## Pairing

- Open the Bluetooth section.
- Turn on `Scan`.
- For a new Wii Remote, press the red SYNC button behind the battery cover.
- For a saved Wii Remote, press a face button such as `1` or `2` while scanning is on.
- For a Wii Fit Balance Board, press its power button while scanning is on.
- Connection can take a moment while macOS exposes the HID service.

## Controllers

- Active controller cards appear at the top of the Controllers section.
- Saved Controllers lists macOS-paired Wii controllers and provides Forget for removing the Bluetooth pairing.
- Saved Extensions lists locally remembered extension records and provides Forget for removing only the saved app record.

## References

- https://github.com/wiiuse/wiiuse

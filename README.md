# WiiMacMote

- WARNING: Mac OS does not allow for virtual HID creation unless the app is signed with appropriate permissions or SIP is disabled. This application is a proof of concept and is only useful for pairing Wii peripherals to modern Mac OS for other applications that natively support them such as Dolphin, or use with software that support generic devices including BTT, etc.

![Screenshot](screenshot.png "Screenshot")

- macOS app for Nintendo Wii Remotes.
- Pairs new controllers with the red SYNC button and reconnects saved Wii Remotes from face buttons.
- Reads buttons, battery, LEDs, rumble, accelerometer, IR, MotionPlus, and common extensions.
- Supports Wii Remote, Wii Remote Plus, Nunchuk, Classic Controller, Balance Board, Guitar, and TaTaCon paths.
- Virtual HID output is experimental and requires Apple-restricted entitlement/signing support or SIP disabled.

## Requirements

- macOS 14 or newer.
- Xcode 16 or newer.
- Bluetooth-capable Mac.
- Nintendo Wii Remote and/or Peripherals

## Build

- Open `WiiMacMote.xcodeproj`.
- Select `WiiMacMote` and `My Mac`.
- Build and run.
- Or run `./Scripts/build.sh`.
- Local copied apps may need fresh ad-hoc signing for macOS Bluetooth permission.
- Sign the installed app with `codesign --force --deep --sign - /Applications/WiiMacMote.app`.
- Or run `./Scripts/build.sh --sign-installed`.
- Run checks with `./Scripts/verify-source.sh`.

## Pair

- Turn on `Scan`.
- Press the red SYNC button behind the battery cover for first pairing.
- For saved Wii Remotes, press a face button such as `1` or `2` while `Scan` is on.
- Press the button again if the remote turns off or the LEDs stop blinking.
- Connection can take a moment.
- Cancel macOS `Connection Request` prompts from face-button presses until the remote is saved.


## Virtual Output

- Standard builds are proof of concept for physical Wii Remote input and DSU output.
- System-wide virtual HID output may fail without `com.apple.developer.hid.virtual.device`.
- Local testing helper: `./Scripts/run-developer-lab.sh`.

## References
- https://github.com/wiiuse/wiiuse

# WiiMacMote

![Screenshot](screenshot.png "Screenshot")

- Warning: Mac OS does not allow for virtual HID creation unless the app is signed with appropriate permissions or SIP is disabled. This is only useful for pairing Wii remotes for other applications that natively support it such as Dolphin, or use with BTT, etc.
- macOS app for Nintendo Wii Remotes.
- Pairs with the red SYNC button.
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
- Cancel macOS `Connection Request` prompts from normal buttons.
- After first pairing, wake a saved remote with any normal button.
- If HID stalls after pairing, keep `Scan` on, power the remote off, then wake it with a normal button.


## Virtual Output

- Standard builds are proof of concept for physical Wii Remote input and DSU output.
- System-wide virtual HID output may fail without `com.apple.developer.hid.virtual.device`.
- Local testing helper: `./Scripts/run-developer-lab.sh`.

## References
- https://github.com/wiiuse/wiiuse
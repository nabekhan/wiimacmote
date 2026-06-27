# WiiMacMote

- macOS app for Nintendo Wii Remotes.
- Pairs with the red SYNC button.
- Reads buttons, battery, LEDs, rumble, accelerometer, IR, MotionPlus, and common extensions.
- Supports Wii Remote, Wii Remote Plus, Nunchuk, Classic Controller, Balance Board, Guitar, and TaTaCon paths.
- Exposes local DSU/Cemuhook UDP output for emulator use.
- Optional virtual HID output is experimental and requires Apple-restricted entitlement/signing support.

## Requirements

- macOS 14 or newer.
- Xcode 16 or newer.
- Bluetooth-capable Mac.
- Nintendo Wii Remote.

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

## DSU / Cemuhook

- Enable `DSU / Cemuhook` in the app.
- Endpoint: `127.0.0.1:26760`.
- Use this in Dolphin/Cemu-compatible clients.
- Enable `Read MotionPlus Gyro` if you want gyro data.
- Some emulator motion controls may need manual mapping.

## Virtual Output

- Standard builds work for physical Wii Remote input and DSU output.
- System-wide virtual HID output may fail without `com.apple.developer.hid.virtual.device`.
- Local testing helper: `./Scripts/run-developer-lab.sh`.
- Details: `DEVELOPER_LAB.md`.

## Useful Files

- `wiimacmote/WiimoteManager.swift` - app state, Bluetooth, pairing, saved remotes.
- `wiimacmote/WiimoteHIDController.swift` - HID sessions and Wii Remote reports.
- `wiimacmote/WiimoteProtocol.swift` - Wii protocol parsing/building.
- `wiimacmote/DiagnosticDSUServer.swift` - DSU/Cemuhook server.
- `Tests/CoreTests.swift` - portable core tests.

## License

- GPL-3.0-or-later.
- Wiiuse-derived protocol behavior is noted in `THIRD_PARTY_NOTICES.md`.

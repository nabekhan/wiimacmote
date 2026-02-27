# CLI Prototype - Wiimote Virtual Gamepad

A Swift Package Manager proof-of-concept that creates a virtual HID gamepad device on macOS.

## ⚠️ This is a Prototype

This CLI version was used to prove the concept works. The main project is now the **SwiftUI app** in `../wiimacmote/`.

## Status

✅ **Working** - Successfully creates virtual HID device on macOS 13.0+

## What This Proves

- `IOHIDUserDeviceCreate` works for creating virtual gamepads
- Proper code signing and entitlements allow HID device creation
- Button events can be sent successfully
- Device appears in gamepad testers

## Quick Test

```bash
swift build
.build/debug/WiimoteGamepadCLI
```

Open [gamepad-tester.com](https://gamepad-tester.com) to see the virtual gamepad.

## Building a Signed App Bundle

```bash
SIGNING_IDENTITY="Apple Development: your@email.com" ./build-app.sh
open WiimoteGamepad.app
```

## File Structure

```
CLI-Prototype/
├── Package.swift                           # Swift package manifest
├── build-app.sh                            # Build script for app bundle
├── WiimoteGamepadCLI.entitlements         # Required entitlements
├── Sources/
│   ├── CIOHIDUserDevice/                  # C bridging module
│   │   └── include/
│   │       └── CIOHIDUserDevice.h         # IOKit HID headers
│   └── WiimoteGamepadCLI/
│       ├── main.swift                      # Entry point (demo timer)
│       └── VirtualGamepad.swift            # HID device wrapper
└── Documentation/
    ├── README.md                           # Full documentation
    ├── QUICKSTART.md
    ├── XCODE-SETUP.md
    └── MIGRATION.md
```

## Key Learnings

### What Works ✅
- Building as app bundle with code signing
- Using `IOHIDUserDeviceCreate` + `IOHIDUserDeviceActivate`
- Entitlements: `com.apple.security.device.bluetooth` and `com.apple.security.device.usb`
- Input Monitoring permission (user grants once)

### What Doesn't Work ❌
- Running unsigned executables
- Using `sudo` (doesn't help with modern security)
- Ad-hoc signing (unreliable)
- Disabling SIP (unnecessary and dangerous)

## Migrating to SwiftUI

The `VirtualGamepad.swift` class can be copied directly to the SwiftUI app:

```swift
// In SwiftUI app:
@StateObject private var gamepad = VirtualGamepad()

// Use it:
gamepad.sendButtonMask(0b0000000011)  // Buttons 1 & 2
```

Just make sure to:
1. Add bridging header for IOKit
2. Link IOKit framework
3. Add same entitlements
4. Configure code signing

## Testing

Run the CLI and check:
- Console shows "✅ Device created and activated"
- Gamepad tester shows "Wiimote Virtual Gamepad"
- Buttons 1 & 2 toggle every second

## Further Reading

See the documentation files for detailed setup instructions:
- [QUICKSTART.md](QUICKSTART.md) - Fast setup guide
- [XCODE-SETUP.md](XCODE-SETUP.md) - Visual Xcode guide
- [MIGRATION.md](MIGRATION.md) - Package → Xcode project migration

---

**Next Step**: Use this knowledge to build the SwiftUI app in `../wiimacmote/`

# wiimacmote - Wiimote Virtual Gamepad

A native macOS app that turns your Wiimote into a virtual game controller.

## Status

🚧 **In Development**

- ✅ SwiftUI app structure created
- ✅ VirtualGamepad class integrated
- 🚧 Wiimote Bluetooth connection (next)
- 🚧 UI for connection and configuration (next)

## Features (Planned)

- 🎮 Connect Wiimote via Bluetooth
- 🎯 Virtual gamepad recognized by macOS and games
- ⚙️ Configurable button mapping
- 📊 Real-time button press visualization
- 💾 Save controller configurations
- 🔄 Auto-reconnect to known Wiimotes

## Running the App

### 1. Open in Xcode

```bash
open wiimacmote.xcodeproj
```

### 2. Configure Code Signing

1. Select the project in Project Navigator
2. Go to **Signing & Capabilities**
3. Check **"Automatically manage signing"**
4. Select your **Team** (Personal Team/Apple ID)

### 3. Run

Press **⌘R** or click the ▶️ button.

## Current Implementation

### ✅ VirtualGamepad Class

Located in `wiimacmote/VirtualGamepad.swift`

```swift
// Create virtual gamepad
let gamepad = VirtualGamepad()

// Send button states (10-bit mask)
gamepad?.sendButtonMask(0b0000000011)  // Buttons 1 & 2 pressed
```

### 🚧 Next: WiimoteManager Class

Will handle:
- Scanning for Wiimotes
- Bluetooth L2CAP connection
- Parsing HID reports
- Mapping buttons to gamepad

## Architecture

```
wiimacmote/
├── wiimacmoteApp.swift          # App entry point
├── ContentView.swift             # Main UI
├── VirtualGamepad.swift          # HID device wrapper
├── Models/
│   └── WiimoteManager.swift     # Bluetooth + button mapping
├── Views/
│   ├── ConnectionView.swift     # Wiimote pairing UI
│   ├── GamepadView.swift        # Visual button feedback
│   └── SettingsView.swift       # Configuration
└── CIOHIDUserDevice-Bridging-Header.h  # IOKit bridge
```

## Requirements

- **macOS 13.0+** (Ventura or later)
- **Xcode 15.0+**
- **Code signing** (free Apple ID works)
- **Permissions**:
  - Input Monitoring (for virtual HID device)
  - Bluetooth (for Wiimote connection)

## Entitlements Needed

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
<key>com.apple.security.device.usb</key>
<true/>
```

## Testing Without Wiimote

Currently, the app creates a virtual gamepad on launch. You can test it:

1. Run the app
2. Open [gamepad-tester.com](https://gamepad-tester.com)
3. You should see "Wiimote Virtual Gamepad" appear

## Development Workflow

### Quick Testing
Use the CLI prototype in `../CLI-Prototype/` for rapid testing of core functionality:

```bash
cd ../CLI-Prototype
swift build && .build/debug/WiimoteGamepadCLI
```

### UI Development
Build the SwiftUI interface in this project (wiimacmote).

### Sharing Code
Core classes like `VirtualGamepad.swift` can be updated in either project and copied over.

## Next Steps

### 1. Implement WiimoteManager
- [ ] IOBluetooth device scanning
- [ ] L2CAP channel connection (PSM 0x11 input, 0x13 output)
- [ ] Parse Wiimote HID reports
- [ ] Map buttons to virtual gamepad

### 2. Build Connection UI
- [ ] Scan for nearby Wiimotes
- [ ] Show connection status
- [ ] Display battery level
- [ ] Handle reconnection

### 3. Add Visual Feedback
- [ ] Show button presses in real-time
- [ ] Display accelerometer data (visual tilt)
- [ ] Connection strength indicator

### 4. Configuration
- [ ] Custom button mapping
- [ ] Save/load profiles
- [ ] Multiple Wiimote support

## Troubleshooting

### Virtual Gamepad Not Created

**Check permissions**:
1. System Settings → Privacy & Security → Input Monitoring
2. Add wiimacmote
3. Restart app

### Bluetooth Issues

**Make sure**:
- Wiimote is in pairing mode (hold 1+2 buttons)
- Bluetooth is enabled on Mac
- Wiimote isn't already paired to another device

### Build Errors

**Common fixes**:
- Clean build folder: **Product → Clean Build Folder** (⇧⌘K)
- Verify bridging header path is correct
- Check IOKit framework is linked

## References

- [IOHIDUserDevice Documentation](https://developer.apple.com/documentation/iokit/iohiduserdevice)
- [IOBluetooth Framework](https://developer.apple.com/documentation/iobluetooth)
- [Wiimote Protocol](http://wiibrew.org/wiki/Wiimote)
- [HID Usage Tables](https://usb.org/document-library/hid-usage-tables-13)

---

**Ready to add Wiimote support!** See `WiimoteManager.swift` implementation next.

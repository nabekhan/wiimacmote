# Wiimote Virtual Gamepad for macOS

A Swift application that creates a virtual HID gamepad device on macOS, designed to translate Wiimote inputs into standard gamepad controls.

## Project Status

✅ **Core Implementation Complete**
- ✅ Swift package with IOKit framework configured
- ✅ C bridging module for IOHIDUserDevice APIs  
- ✅ VirtualGamepad class with HID descriptor
- ✅ Main application with dummy button toggling
- ✅ Project builds successfully (`swift build`)

## ✅ The Proper Solution: Signed App Bundle

**This is the only fully Apple-supported architecture that works post-Catalina without security hacks.**

### Why This Works

On macOS 10.15+ (Catalina and later), creating virtual HID devices via `IOHIDUserDeviceCreateWithProperties` requires:

✅ **App bundle** (not just a CLI executable)  
✅ **Code signing** (free Apple ID or paid Developer account)  
✅ **Proper entitlements** for Input Monitoring  
✅ **User approval** in System Preferences → Security & Privacy  
✅ **No SIP disablement needed**  
✅ **No Terminal, no sudo**  
✅ **Works permanently once approved**

This is how real virtual HID drivers work on modern macOS.

---

## 🚀 Quick Start: Making It Work

### Step 1: Open in Xcode

```bash
open Package.swift
```

Xcode will automatically create a project from the Swift Package.

### Step 2: Configure Signing

**What is WiimoteGamepadCLI?** It's your executable target name (the app being built).

**Where is "Signing & Capabilities"?**
1. In Xcode, click on **WiimoteGamepad** in the left sidebar (Project Navigator)
2. Look for tabs at the top: **General | Signing & Capabilities | Resources**
3. Click **"Signing & Capabilities"** tab

**Configure it:**
1. ☑️ Check **"Automatically manage signing"**
2. Select your **Team** (free Apple ID works!)
   - Don't have one? Click "Add an Account..." and sign in with your Apple ID
3. Xcode will automatically provision the app

**Need help finding it?** See the detailed visual guide: [XCODE-SETUP.md](XCODE-SETUP.md)

### Step 3: Update Entitlements

The entitlements file needs to request Input Monitoring permission:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Allow Bluetooth communication with Wiimote -->
    <key>com.apple.security.device.bluetooth</key>
    <true/>
    
    <!-- Required for creating virtual HID devices -->
    <key>com.apple.security.device.usb</key>
    <true/>
</dict>
</plist>
```

**Note**: Input Monitoring permission is handled automatically by macOS when the signed app tries to create a virtual HID device.

### Step 4: Build and Run

1. In Xcode, select **Product → Run** (or press `Cmd+R`)
2. The first time you run it, macOS will show a permission dialog
3. Go to **System Preferences → Security & Privacy → Input Monitoring**
4. Grant permission to **WiimoteGamepadCLI**
5. Restart the app

**That's it!** The virtual gamepad will now be created successfully.

---

## 🎮 Testing the Virtual Gamepad

Once the app is running:

1. Open [HTML5 Gamepad Tester](https://gamepad-tester.com) in your browser
2. You should see **"Wiimote Virtual Gamepad"** appear in the list
3. Buttons 1 & 2 will toggle every second (demo mode)
4. The console will show: `✅ Device created and activated`

---

## 📦 Creating a Distributable App

### For Personal Use (Free Apple ID)

1. Build from Xcode with your free Apple ID
2. Find the built app in DerivedData:
   ```bash
   ~/Library/Developer/Xcode/DerivedData/WiimoteGamepad-*/Build/Products/Debug/WiimoteGamepadCLI
   ```
3. You can move this to `/Applications` and run it
4. App will work only on your Mac (7-day signing limit, auto-renewed by Xcode)

### For Distribution (Paid Developer Account)

1. **Get Apple Developer Program** ($99/year)
2. **Create a Developer ID certificate** in your Apple Developer account
3. **Archive and notarize** the app:
   ```bash
   xcodebuild -scheme WiimoteGamepadCLI archive -archivePath ./build/WiimoteGamepad.xcarchive
   xcodebuild -exportArchive -archivePath ./build/WiimoteGamepad.xcarchive -exportPath ./build -exportOptionsPlist ExportOptions.plist
   xcrun notarytool submit build/WiimoteGamepadCLI.zip --keychain-profile "AC_PASSWORD" --wait
   xcrun stapler staple build/WiimoteGamepadCLI.app
   ```
4. **Distribute** the notarized `.app` bundle
5. Users install and approve in System Preferences (one-time approval)

---

## 🔧 Alternative: Building from Command Line

If you prefer command-line building with proper signing:

```bash
# Build a signed executable
swift build -c release

# Sign it with your certificate
codesign --force --sign "Apple Development: your.email@example.com" \
         --entitlements WiimoteGamepadCLI.entitlements \
         .build/release/WiimoteGamepadCLI

# Verify signing
codesign -vvv .build/release/WiimoteGamepadCLI

# Run (will prompt for Input Monitoring permission)
.build/release/WiimoteGamepadCLI
```

**Note**: Command-line signing works, but wrapping in an app bundle is more reliable for permissions.

---

## ❌ What NOT to Do

### ❌ Don't Disable SIP
Disabling System Integrity Protection is a security risk and unnecessary.

### ❌ Don't Use `sudo`
Running with `sudo` doesn't help and can cause permission issues.

### ❌ Don't Use Ad-hoc Signing
Ad-hoc signing (`-`) doesn't work reliably for HID device creation.

### ❌ Don't Skip the App Bundle
Command-line executables have limited permission access compared to app bundles.

---

## 📖 Technical Details

### Architecture
- **HID Descriptor**: 10-button gamepad (Usage Page: Generic Desktop, Usage: Gamepad)
- **Report Format**: 10 bits for buttons + 6 bits padding (2 bytes total)
- **APIs Used**: 
  - `IOHIDUserDeviceCreateWithProperties` (macOS 10.15+)
  - `IOHIDUserDeviceHandleReportWithTimeStamp`
  - `IOHIDUserDeviceActivate`

### Why IOHIDUserDevice?

- **User-space virtual HID**: Perfect for software-based virtual devices
- **No kernel extensions**: Works entirely in user space
- **Apple-supported API**: Officially documented and supported
- **Cross-version compatible**: Works on macOS 10.15+ with proper signing

### What About DriverKit?

DriverKit is designed for **hardware drivers** that communicate with physical devices. For creating a purely virtual HID device (no hardware), `IOHIDUserDevice` is the correct and simpler choice.

DriverKit would be needed if:
- You were creating a USB device driver
- You needed kernel-level hardware access
- You were building a system extension for hardware

For a virtual gamepad, **IOHIDUserDevice is the right tool**.

---

## 🎯 Next Steps: Adding Real Wiimote Input

Once you have the virtual gamepad working, add Wiimote support:

### 1. Connect to Wiimote via Bluetooth

```swift
import IOBluetooth

class WiimoteManager {
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothL2CAPChannel?
    
    func connectToWiimote() {
        // Scan for Wiimote (Nintendo RVL-CNT-01)
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]
        device = devices?.first { $0.name == "Nintendo RVL-CNT-01" }
        
        // Open L2CAP channel (PSM 0x11 for input, 0x13 for output)
        device?.openL2CAPChannelSync(&channel, withPSM: 0x11, delegate: self)
    }
}
```

### 2. Read Wiimote HID Reports

```swift
extension WiimoteManager: IOBluetoothL2CAPChannelDelegate {
    func l2capChannelData(_ l2capChannel: IOBluetoothL2CAPChannel!, 
                         data dataPointer: UnsafeMutableRawPointer!, 
                         length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        
        // Parse Wiimote button report (0x30 - Core Buttons)
        if data[0] == 0xa1 && data[1] == 0x30 {
            let buttons = UInt16(data[2]) | (UInt16(data[3]) << 8)
            handleWiimoteButtons(buttons)
        }
    }
}
```

### 3. Map Wiimote Buttons to Gamepad

```swift
func handleWiimoteButtons(_ wiimoteButtons: UInt16) {
    var gamepadMask: UInt16 = 0
    
    // Wiimote button mapping (example)
    if wiimoteButtons & 0x0008 != 0 { gamepadMask |= 0x001 } // A → Button 1
    if wiimoteButtons & 0x0004 != 0 { gamepadMask |= 0x002 } // B → Button 2
    if wiimoteButtons & 0x0100 != 0 { gamepadMask |= 0x004 } // 1 → Button 3
    if wiimoteButtons & 0x0200 != 0 { gamepadMask |= 0x008 } // 2 → Button 4
    if wiimoteButtons & 0x1000 != 0 { gamepadMask |= 0x010 } // + → Button 5
    if wiimoteButtons & 0x0010 != 0 { gamepadMask |= 0x020 } // - → Button 6
    if wiimoteButtons & 0x0800 != 0 { gamepadMask |= 0x040 } // Up → Button 7
    if wiimoteButtons & 0x0400 != 0 { gamepadMask |= 0x080 } // Down → Button 8
    if wiimoteButtons & 0x0001 != 0 { gamepadMask |= 0x100 } // Left → Button 9
    if wiimoteButtons & 0x0002 != 0 { gamepadMask |= 0x200 } // Right → Button 10
    
    // Send to virtual gamepad
    virtualGamepad.sendButtonMask(gamepadMask)
}
```

### 4. Replace Timer with Real Events

In `main.swift`, replace the timer-based demo with actual Wiimote events:

```swift
let gamepad = VirtualGamepad()
let wiimote = WiimoteManager(gamepad: gamepad)

wiimote.connectToWiimote()
print("🎮 Wiimote connected! Press buttons to see gamepad input.")

// Keep running to process events
RunLoop.main.run()
```

---

## 🐛 Troubleshooting

### "IOHIDUserDeviceCreateWithProperties returned nil"

**Cause**: App is not properly signed or lacks required entitlements.

**Solution**:
1. Build from Xcode (not `swift build`)
2. Make sure signing is configured
3. Grant Input Monitoring permission in System Preferences
4. Restart the app

### "Code signing failed"

**Cause**: No signing certificate available.

**Solution**:
1. Open Xcode → Preferences → Accounts
2. Sign in with your Apple ID
3. Click "Manage Certificates..." → "+" → "Apple Development"

### "Permission denied in Input Monitoring"

**Cause**: App hasn't been granted permission.

**Solution**:
1. System Preferences → Security & Privacy → Privacy → Input Monitoring
2. Click the lock to make changes
3. Add WiimoteGamepadCLI to the list
4. Check the box next to it
5. Restart the app

### "App works in Xcode but not when distributed"

**Cause**: Ad-hoc signing doesn't work for distribution.

**Solution**:
- For personal use: Rebuild on each Mac with Xcode
- For distribution: Use paid Developer account and notarize

---

## 📁 Project Structure

```
wiicontroller2/
├── Package.swift                           # Swift package with IOKit
├── WiimoteGamepadCLI.entitlements         # App entitlements
├── Sources/
│   ├── CIOHIDUserDevice/                  # C bridging module
│   │   └── include/
│   │       └── CIOHIDUserDevice.h         # IOKit HID headers
│   └── WiimoteGamepadCLI/
│       ├── main.swift                      # Entry point (demo timer)
│       ├── VirtualGamepad.swift            # HID device wrapper
│       └── include/                        # C bridges
│           ├── IOHIDUserDeviceBridge.h
│           └── module.modulemap
└── README.md                               # This file
```

---

## 🔗 References

- [IOHIDUserDevice Documentation](https://developer.apple.com/documentation/iokit/iohiduserdevice)
- [IOBluetooth Framework](https://developer.apple.com/documentation/iobluetooth)
- [App Signing and Notarization](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements)
- [System Extensions](https://developer.apple.com/system-extensions/)

---

## 📝 License

This is a development project for personal use.

---

## 💡 Summary: The Winning Approach

✅ **Build as app bundle** (use Xcode)  
✅ **Sign with any Apple ID** (free works!)  
✅ **Add proper entitlements**  
✅ **User approves once** in System Preferences  
✅ **Works permanently** with SIP enabled  
✅ **No Terminal, no sudo, no hacks**  

**This is how professional drivers work on macOS.** 🚀

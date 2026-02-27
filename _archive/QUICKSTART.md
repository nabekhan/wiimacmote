# Quick Start Guide: Wiimote Virtual Gamepad

This guide will get your virtual gamepad working in **under 5 minutes**.

## The Problem

Running `swift run` or even `sudo swift run` doesn't work because macOS requires:
- Proper code signing
- User approval for Input Monitoring
- App bundle structure

**No SIP disablement needed. No kernel extensions. No Terminal hacks.**

---

## Solution 1: Use Xcode (Recommended - Easiest)

### Step 1: Open in Xcode
```bash
open Package.swift
```

Xcode will automatically create a project from the Swift Package.

### Step 2: Configure Signing
1. Select **WiimoteGamepadCLI** target
2. Go to **Signing & Capabilities** tab
3. Check **"Automatically manage signing"**
4. Select your **Team** (free Apple ID works!)
   - No Apple ID? Click "Add an Account..." and sign in

### Step 3: Run
1. Press **Cmd+R** (Product → Run)
2. When prompted, grant **Input Monitoring** permission:
   - System Preferences → Security & Privacy → Privacy → Input Monitoring
   - Check the box next to **WiimoteGamepadCLI**
3. Restart the app in Xcode

### Step 4: Test
Open [https://gamepad-tester.com](https://gamepad-tester.com) and you should see:
- **"Wiimote Virtual Gamepad"** device
- Buttons 1 & 2 toggling every second

✅ **That's it! Your virtual gamepad is working.**

---

## Solution 2: Build from Command Line

### Prerequisites
Find your signing identity:
```bash
security find-identity -v -p codesigning
```

Look for something like:
```
1) ABC123... "Apple Development: your@email.com (TEAMID)"
```

### Build and Sign
```bash
# Set your signing identity
export SIGNING_IDENTITY="Apple Development: your@email.com"

# Build and sign
./build-app.sh
```

### Run
```bash
open WiimoteGamepad.app
```

Grant Input Monitoring permission when prompted, then restart the app.

---

## Troubleshooting

### "IOHIDUserDeviceCreateWithProperties returned nil"
**Cause**: Not properly signed or missing permissions.

**Fix**:
1. Make sure you built with Xcode or signed with a real identity
2. Grant Input Monitoring permission in System Preferences
3. Restart the app

### "No signing identity found"
**Cause**: No Apple Developer certificate.

**Fix**:
1. Open Xcode → Preferences → Accounts
2. Sign in with your Apple ID (free)
3. Click "Manage Certificates..." → "+" → "Apple Development"

### "Permission denied in Input Monitoring"
**Cause**: Haven't granted permission yet.

**Fix**:
1. System Preferences → Security & Privacy → Privacy
2. Click **Input Monitoring** in the left sidebar
3. Click the lock and authenticate
4. Add your app and check the box
5. Restart the app

---

## What's Next?

### Add Wiimote Support
Once the virtual gamepad works, connect it to a real Wiimote:

1. **Connect Wiimote via Bluetooth**
   - Pair in System Preferences → Bluetooth
   - Press 1+2 on Wiimote to enter pairing mode

2. **Add Bluetooth Code**
   - Use `IOBluetooth` framework to read Wiimote HID reports
   - Map Wiimote buttons to gamepad buttons
   - See the full code examples in [README.md](README.md#-next-steps-adding-real-wiimote-input)

3. **Test in Games**
   - Many games support generic HID gamepads
   - Test with Steam, emulators, or HTML5 games

---

## Key Points

✅ **Works with SIP enabled** - No security compromises  
✅ **Free Apple ID works** - No paid developer account needed  
✅ **One-time permission** - User approves once, works forever  
✅ **No sudo required** - Runs as normal user  
✅ **No Terminal needed** - Standard macOS app  

This is the **only proper way** to create virtual HID devices on modern macOS.

---

## Files in This Project

- **README.md** - Full documentation with technical details
- **QUICKSTART.md** - This file
- **build-app.sh** - Command-line build script
- **Info.plist** - App bundle configuration
- **WiimoteGamepadCLI.entitlements** - Security permissions
- **ExportOptions.plist** - Distribution configuration

---

## Questions?

Check the full documentation in [README.md](README.md) for:
- Technical architecture details
- Wiimote integration code examples
- Distribution and notarization guide
- Complete troubleshooting section

**Happy gaming! 🎮**

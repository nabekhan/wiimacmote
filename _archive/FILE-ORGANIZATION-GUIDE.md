# 📁 File Organization Guide

## Current Status: Files Mixed at Root Level

This guide shows you exactly which files to move where to achieve the hybrid structure.

---

## 🎯 Target Structure

```
/repo/
├── PROJECT-README.md                    ✅ Created - Main project overview
│
├── CLI-Prototype/                       📦 Swift Package (testing/reference)
│   ├── README.md                        ← Move current README.md here
│   ├── Package.swift                    ← Move
│   ├── build-app.sh                     ← Move
│   ├── QUICKSTART.md                    ← Move
│   ├── XCODE-SETUP.md                   ← Move
│   ├── MIGRATION.md                     ← Move
│   ├── WiimoteGamepadCLI.entitlements  ← Move (if exists)
│   ├── Info.plist                       ← Move (if exists)
│   └── Sources/
│       ├── CIOHIDUserDevice/
│       │   └── include/
│       │       └── CIOHIDUserDevice.h   ← Move
│       └── WiimoteGamepadCLI/
│           ├── main.swift               ← Move
│           └── VirtualGamepad.swift     ← Move (original CLI version)
│
└── wiimacmote/                          🎯 SwiftUI App (main project)
    ├── README.md                        ✅ Created (SWIFTUI-README.md)
    ├── wiimacmote.xcodeproj/            ← Create/keep Xcode project
    └── wiimacmote/                      ← App source folder
        ├── wiimacmoteApp.swift          ✅ Already exists
        ├── ContentView.swift            ✅ Already exists
        ├── VirtualGamepad.swift         ✅ Created (VirtualGamepad-SwiftUI.swift)
        ├── WiimoteManager.swift         ✅ Created
        ├── CIOHIDUserDevice-Bridging-Header.h  ✅ Created
        ├── wiimacmote.entitlements      ✅ Created
        ├── Assets.xcassets/             ← Create in Xcode
        └── Preview Content/             ← Create in Xcode
            └── Preview Assets.xcassets/
```

---

## 📋 Step-by-Step Moving Instructions

### Step 1: Create Folder Structure

```bash
# In your project root
mkdir -p CLI-Prototype/Sources/CIOHIDUserDevice/include
mkdir -p CLI-Prototype/Sources/WiimoteGamepadCLI
mkdir -p wiimacmote/wiimacmote
```

### Step 2: Move CLI Files

**Package and build files:**
```bash
mv Package.swift CLI-Prototype/
mv build-app.sh CLI-Prototype/
```

**Documentation:**
```bash
mv README.md CLI-Prototype/
mv QUICKSTART.md CLI-Prototype/
mv XCODE-SETUP.md CLI-Prototype/
mv MIGRATION.md CLI-Prototype/
```

**Entitlements (if exists):**
```bash
# Look for: WiimoteGamepadCLI.entitlements
# If it exists:
mv WiimoteGamepadCLI.entitlements CLI-Prototype/
```

**Source files:**
```bash
mv main.swift CLI-Prototype/Sources/WiimoteGamepadCLI/
mv VirtualGamepad.swift CLI-Prototype/Sources/WiimoteGamepadCLI/
```

**C headers:**
```bash
mv CIOHIDUserDevice.h CLI-Prototype/Sources/CIOHIDUserDevice/include/
mv IOHIDUserDeviceBridge.h CLI-Prototype/Sources/CIOHIDUserDevice/include/ # if separate
```

**Module maps (if they exist):**
```bash
# Look for module.modulemap files
# Move them to appropriate locations in CLI-Prototype/Sources/
```

### Step 3: Set Up SwiftUI App Files

**Move SwiftUI files:**
```bash
mv wiimacmoteApp.swift wiimacmote/wiimacmote/
mv ContentView.swift wiimacmote/wiimacmote/
```

**Move newly created files:**
```bash
mv VirtualGamepad-SwiftUI.swift wiimacmote/wiimacmote/VirtualGamepad.swift
mv WiimoteManager.swift wiimacmote/wiimacmote/
mv CIOHIDUserDevice-Bridging-Header.h wiimacmote/wiimacmote/
mv wiimacmote.entitlements wiimacmote/
```

**Move/rename READMEs:**
```bash
mv PROJECT-README.md README.md  # Make this the main README
mv SWIFTUI-README.md wiimacmote/README.md
mv CLI-README.md CLI-Prototype/README.md  # Add this to existing or replace
```

### Step 4: Handle Duplicate Files

You have **two VirtualGamepad implementations**:

**VirtualGamepad.swift** - Original CLI version
- Uses `IOHIDUserDevice?`
- Simpler implementation
- → Move to `CLI-Prototype/Sources/WiimoteGamepadCLI/`

**WiimoteGamepadVirtualGamepad.swift** - Alternative version
- Uses `IOHIDUserDeviceRef?`
- Different API calls
- → Keep as reference or delete (prefer the CLI version)

**Recommendation:** 
```bash
# Delete the duplicate (or rename it for reference)
rm WiimoteGamepadVirtualGamepad.swift
# OR
mv WiimoteGamepadVirtualGamepad.swift CLI-Prototype/VirtualGamepad-Alternative.swift.backup
```

### Step 5: Clean Up Build Artifacts

```bash
# Remove build files (they'll be regenerated)
rm -rf .build/
rm -rf *.d
rm -rf *.emit-module.d
```

---

## ✅ Verification Checklist

After moving files, verify:

### CLI Prototype Works
```bash
cd CLI-Prototype
swift build
# Should build successfully
```

### SwiftUI App Structure
```
wiimacmote/
├── wiimacmote.xcodeproj/
└── wiimacmote/
    ├── wiimacmoteApp.swift          ✅
    ├── ContentView.swift            ✅
    ├── VirtualGamepad.swift         ✅
    ├── WiimoteManager.swift         ✅
    ├── CIOHIDUserDevice-Bridging-Header.h  ✅
    └── wiimacmote.entitlements      ✅ (at parent level)
```

---

## 🚨 Important: Xcode Project Configuration

After moving files, you need to **update your Xcode project** to reference the new locations:

### Option A: Let Xcode Help You (Recommended)

1. Open `wiimacmote.xcodeproj` in Xcode
2. Files will show as red (missing)
3. Select each red file → Show File Inspector (⌘⌥1)
4. Click the folder icon → Locate the file in new location
5. Xcode will update references

### Option B: Add Files Manually

1. Delete missing file references from project
2. Drag files from Finder into Xcode project
3. Make sure "Copy items if needed" is **unchecked** (they're already there)
4. Add to `wiimacmote` target

### Configure Bridging Header

1. Select project in navigator
2. Select `wiimacmote` target
3. Go to **Build Settings**
4. Search for "bridging"
5. Set **Objective-C Bridging Header** to: `wiimacmote/CIOHIDUserDevice-Bridging-Header.h`

### Link IOKit Framework

1. Select project → target
2. **General** tab → **Frameworks, Libraries, and Embedded Content**
3. Click **+** → Search "IOKit" → Add

### Add Entitlements

1. Select project → target
2. **Signing & Capabilities** tab
3. Click **+ Capability** → **App Sandbox** (optional)
4. File → **wiimacmote.entitlements** should appear in navigator
5. In **Build Settings**, verify **Code Signing Entitlements** points to it

---

## 🎉 What You'll Have After This

### CLI Prototype (Reference/Testing)
- Self-contained Swift Package
- Quick command-line testing
- All documentation
- Working virtual gamepad proof-of-concept

### SwiftUI App (Main Project)
- Native macOS app
- VirtualGamepad class (ObservableObject)
- WiimoteManager for Bluetooth
- Ready to build UI
- Proper code signing
- Correct entitlements

---

## 🔄 Workflow After Organization

### Testing Core Functionality
```bash
cd CLI-Prototype
swift build && .build/debug/WiimoteGamepadCLI
```

### Developing the App
```bash
cd wiimacmote
open wiimacmote.xcodeproj
# Press ⌘R to run
```

### Sharing Code
If you update `VirtualGamepad.swift` logic in CLI:
```bash
# Copy improvements to SwiftUI version
cp CLI-Prototype/Sources/WiimoteGamepadCLI/VirtualGamepad.swift \
   wiimacmote/wiimacmote/VirtualGamepad.swift
# Then adapt for SwiftUI (add @Published, ObservableObject, etc.)
```

---

## 📞 Need Help?

If files are in unexpected locations or you hit errors:

1. **Find where a file currently is:**
   ```bash
   find . -name "main.swift"
   find . -name "*.swift"
   ```

2. **List all files at root:**
   ```bash
   ls -la
   ```

3. **Check Xcode project structure:**
   Open `.xcodeproj` and see what files Xcode thinks exist

---

**Ready to organize?** Follow the steps above! 🚀

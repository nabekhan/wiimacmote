# Xcode Setup Guide - Step by Step with Screenshots

## What is WiimoteGamepadCLI?

**WiimoteGamepadCLI** is the name of your executable target in the Swift Package. When you open `Package.swift` in Xcode, this is the app/executable that gets built.

## Finding Signing & Capabilities in Xcode

### Step 1: Open the Package in Xcode

```bash
cd /Users/guillaume/development/wiicontroller2
open Package.swift
```

**What happens:** Xcode will open and automatically convert the Swift Package into a project.

---

### Step 2: Select the Target

Once Xcode opens:

1. Look at the **left sidebar** (Project Navigator)
2. You'll see a blue icon with **"WiimoteGamepad"** (the package name)
3. Click on it

**OR**

1. Look at the **top toolbar** (near the Run button)
2. You'll see a target selector showing **"WiimoteGamepadCLI"** or **"My Mac"**
3. Click on **"WiimoteGamepadCLI"** in that dropdown

---

### Step 3: Find Signing & Capabilities Tab

Once you've selected the WiimoteGamepadCLI target:

1. Look at the **top of the main editor area**
2. You'll see tabs: **General | Signing & Capabilities | Resources | ...**
3. Click on **"Signing & Capabilities"**

**This is where you configure code signing!**

---

### Step 4: Configure Signing

In the Signing & Capabilities tab, you'll see:

```
┌─────────────────────────────────────────────┐
│  ☐ Automatically manage signing             │
│                                              │
│  Team: None                                  │
│  ▼ [Select a team...]                       │
│                                              │
│  Bundle Identifier: com.wiimote.gamepad      │
│  Signing Certificate: -                      │
│  Provisioning Profile: -                     │
└─────────────────────────────────────────────┘
```

**Do this:**

1. ✅ **Check** "Automatically manage signing"
2. Click the **Team** dropdown
3. Select your **Personal Team** (your Apple ID name)
   - If you see "Add an account...", click it and sign in with your Apple ID
   - Even a **free** Apple ID works!

After selecting your team, you'll see:
```
┌─────────────────────────────────────────────┐
│  ☑ Automatically manage signing             │
│                                              │
│  Team: Your Name (Personal Team)            │
│                                              │
│  Bundle Identifier: com.wiimote.gamepad      │
│  Signing Certificate: Apple Development     │
│  Provisioning Profile: Xcode Managed...     │
└─────────────────────────────────────────────┘
```

✅ **Done! Your app is now signed.**

---

### Step 5: Build and Run

1. Press **Cmd+R** (or click the ▶️ Play button in the toolbar)
2. The app will build and run
3. Check the **console output** at the bottom of Xcode

**Expected output:**
```
✅ Device created and activated
```

**If you see:**
```
⚠️  IOHIDUserDeviceCreateWithProperties returned nil
❌ Failed to create virtual gamepad
```

**Then you need to grant Input Monitoring permission:**

1. Go to **System Preferences** (or **System Settings** on macOS 13+)
2. Click **Security & Privacy** → **Privacy**
3. Scroll down to **Input Monitoring** in the left sidebar
4. Click the 🔒 lock and authenticate
5. Click the **+** button
6. Navigate to:
   ```
   ~/Library/Developer/Xcode/DerivedData/WiimoteGamepad-[random]/Build/Products/Debug/WiimoteGamepadCLI
   ```
7. Add it and check the box
8. Go back to Xcode and press **Cmd+R** again

---

## Where Everything Is Located

```
Project Navigator (Left Sidebar)
└── 📦 WiimoteGamepad (package)
    ├── 📁 Sources
    │   ├── 📁 CIOHIDUserDevice
    │   │   └── 📁 include
    │   │       └── CIOHIDUserDevice.h
    │   └── 📁 WiimoteGamepadCLI  ← Your main code
    │       ├── main.swift
    │       └── VirtualGamepad.swift
    ├── Package.swift
    ├── README.md
    └── WiimoteGamepadCLI.entitlements ← Security permissions
```

---

## Target Names Explained

- **WiimoteGamepad** = The Swift Package name (defined in Package.swift)
- **WiimoteGamepadCLI** = The executable target name (what you run)
- **CIOHIDUserDevice** = A helper module for C bridging

When you open Package.swift in Xcode, you're configuring the **WiimoteGamepadCLI** target for signing.

---

## Can't Find Xcode?

### Install Xcode

1. Open **App Store**
2. Search for "**Xcode**"
3. Click **Get** / **Install** (it's free, but large ~15GB)
4. Wait for installation (takes 30-60 minutes)

### Install Command Line Tools (Alternative)

If you don't want the full Xcode:

```bash
xcode-select --install
```

But this won't give you the GUI for easy signing setup.

---

## Alternative: Command Line Signing

If you prefer not to use Xcode's GUI:

### 1. Find Your Signing Identity

```bash
security find-identity -v -p codesigning
```

Look for:
```
1) ABC123... "Apple Development: your@email.com (TEAM123)"
```

### 2. Build with Signing

```bash
export SIGNING_IDENTITY="Apple Development: your@email.com"
./build-app.sh
```

### 3. Run

```bash
open WiimoteGamepad.app
```

---

## Still Confused?

The **Signing & Capabilities** tab is where macOS asks:
- "**Who** created this app?" (Your Apple ID)
- "Can we **trust** this app to create virtual devices?" (Signing certificate)

Without proper signing, macOS won't let the app create virtual HID devices, even with sudo.

**This is by design for security.** The good news: a free Apple ID is enough!

---

## Quick Visual Reference

```
┌──────────────────────────────────────────────────────────┐
│ Xcode Menu Bar                                           │
├──────────────────────────────────────────────────────────┤
│                                                          │
│ ┌────────────┐  ┌──────────────────────────────────┐   │
│ │  Project   │  │  WiimoteGamepad / Package.swift  │   │
│ │ Navigator  │  │  ┌────────────────────────────┐  │   │
│ │            │  │  │ General                    │  │   │
│ │ • Package  │  │  │ Signing & Capabilities ←── │  │   │
│ │   • Source │  │  │ Resources                  │  │   │
│ │   • Tests  │  │  │ Build Settings             │  │   │
│ │            │  │  └────────────────────────────┘  │   │
│ │            │  │                                  │   │
│ │            │  │  ☑ Automatically manage signing │   │
│ │            │  │  Team: [Your Name]              │   │
│ │            │  │  Bundle ID: com.wiimote.gamepad │   │
│ └────────────┘  └──────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
                          ⬆
                    Click this tab!
```

---

Need more help? Check [README.md](README.md) or [QUICKSTART.md](QUICKSTART.md).

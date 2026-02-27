# File Organization - Visual Guide

## 📊 Current State (Before Organization)

```
/repo/
├── 📄 Package.swift
├── 📄 build-app.sh
├── 📄 main.swift
├── 📄 VirtualGamepad.swift
├── 📄 WiimoteGamepadVirtualGamepad.swift  ⚠️ Duplicate!
├── 📄 wiimacmoteApp.swift                 ⚠️ Different project!
├── 📄 ContentView.swift                   ⚠️ Different project!
├── 📄 CIOHIDUserDevice.h
├── 📄 IOHIDUserDeviceBridge.h
├── 📄 module.modulemap (multiple?)
├── 📄 README.md
├── 📄 QUICKSTART.md
├── 📄 XCODE-SETUP.md
├── 📄 MIGRATION.md
└── 🏗️ .build/ (build artifacts)

⚠️ PROBLEM: Two different projects mixed together!
```

---

## ✨ After Organization (Hybrid Structure)

```
/repo/
│
├── 📘 README.md                    ← Project overview (both projects)
├── 📘 SUMMARY.md                   ← Quick reference (this file)
├── 📘 FILE-ORGANIZATION-GUIDE.md   ← Detailed instructions
├── 🔧 organize-files.sh            ← Run this to auto-organize
│
├── 📦 CLI-Prototype/               ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
│   │                               ┃  Swift Package (Testing)   ┃
│   │                               ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
│   ├── 📘 README.md                ← CLI documentation
│   ├── 📄 Package.swift            ← SPM manifest
│   ├── 🔧 build-app.sh             ← Build script
│   ├── 📄 WiimoteGamepadCLI.entitlements
│   ├── 📘 QUICKSTART.md
│   ├── 📘 XCODE-SETUP.md
│   ├── 📘 MIGRATION.md
│   │
│   └── 📁 Sources/
│       ├── 📁 CIOHIDUserDevice/
│       │   └── 📁 include/
│       │       └── 📄 CIOHIDUserDevice.h  ← C header for IOKit
│       │
│       └── 📁 WiimoteGamepadCLI/
│           ├── 📄 main.swift              ← CLI entry point
│           └── 📄 VirtualGamepad.swift    ← HID device class
│
│
└── 🎯 wiimacmote/                  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    │                               ┃  SwiftUI App (Main Goal)   ┃
    │                               ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ├── 📘 README.md                ← SwiftUI documentation
    ├── 📄 wiimacmote.entitlements  ← App permissions
    │
    ├── 📁 wiimacmote.xcodeproj/    ← Xcode project
    │   ├── project.pbxproj
    │   └── ...
    │
    └── 📁 wiimacmote/              ← Source files
        ├── 📱 wiimacmoteApp.swift          ← App entry (@main)
        ├── 🎨 ContentView.swift            ← Main UI
        ├── 🎮 VirtualGamepad.swift         ← HID device (SwiftUI version)
        ├── 📡 WiimoteManager.swift         ← Bluetooth handler
        ├── 🔗 CIOHIDUserDevice-Bridging-Header.h  ← Swift↔️C bridge
        │
        ├── 📁 Assets.xcassets/             ← App icons, colors
        │
        └── 📁 Preview Content/
            └── 📁 Preview Assets.xcassets/
```

---

## 🔄 File Movements

### CLI Files → `CLI-Prototype/`

| From (root)                         | To                                                          |
|-------------------------------------|-------------------------------------------------------------|
| `Package.swift`                     | `CLI-Prototype/Package.swift`                               |
| `build-app.sh`                      | `CLI-Prototype/build-app.sh`                                |
| `main.swift`                        | `CLI-Prototype/Sources/WiimoteGamepadCLI/main.swift`        |
| `VirtualGamepad.swift`              | `CLI-Prototype/Sources/WiimoteGamepadCLI/VirtualGamepad.swift` |
| `CIOHIDUserDevice.h`                | `CLI-Prototype/Sources/CIOHIDUserDevice/include/...`        |
| `README.md` (original)              | `CLI-Prototype/README.md`                                   |
| `QUICKSTART.md`                     | `CLI-Prototype/QUICKSTART.md`                               |
| `XCODE-SETUP.md`                    | `CLI-Prototype/XCODE-SETUP.md`                              |
| `MIGRATION.md`                      | `CLI-Prototype/MIGRATION.md`                                |
| `WiimoteGamepadCLI.entitlements`    | `CLI-Prototype/WiimoteGamepadCLI.entitlements`              |

### SwiftUI Files → `wiimacmote/wiimacmote/`

| From (root)                         | To                                                          |
|-------------------------------------|-------------------------------------------------------------|
| `wiimacmoteApp.swift`               | `wiimacmote/wiimacmote/wiimacmoteApp.swift`                 |
| `ContentView.swift`                 | `wiimacmote/wiimacmote/ContentView.swift`                   |
| `VirtualGamepad-SwiftUI.swift` (new)| `wiimacmote/wiimacmote/VirtualGamepad.swift`                |
| `WiimoteManager.swift` (new)        | `wiimacmote/wiimacmote/WiimoteManager.swift`                |
| `CIOHIDUserDevice-Bridging-Header.h` (new) | `wiimacmote/wiimacmote/...`                      |
| `wiimacmote.entitlements` (new)     | `wiimacmote/wiimacmote.entitlements`                        |

### Documentation → Root

| From                                | To                                                          |
|-------------------------------------|-------------------------------------------------------------|
| `PROJECT-README.md` (new)           | `README.md`                                                 |
| `CLI-README.md` (new)               | `CLI-Prototype/README.md` (merged)                          |
| `SWIFTUI-README.md` (new)           | `wiimacmote/README.md`                                      |

### Deleted/Handled

| File                                | Action                                                      |
|-------------------------------------|-------------------------------------------------------------|
| `WiimoteGamepadVirtualGamepad.swift`| Delete or move to `CLI-Prototype/VirtualGamepad-Alt.backup` |
| `.build/`                           | Delete (regenerate when needed)                             |
| `*.d` files                         | Delete (build artifacts)                                    |
| `*.emit-module.d` files             | Delete (build artifacts)                                    |

---

## 🎯 Why This Structure?

### Separation of Concerns
- **CLI-Prototype**: Fast iteration, testing core functionality
- **wiimacmote**: User-facing app with UI

### Clean Namespacing
- Each project has its own `README.md`
- No file name conflicts
- Clear which files belong to which project

### Easy Development
```bash
# Test HID functionality quickly
cd CLI-Prototype && swift build

# Build the app
cd wiimacmote && open wiimacmote.xcodeproj
```

### Code Sharing
- Copy working code from CLI to SwiftUI
- VirtualGamepad class is proven in CLI
- Adapt for SwiftUI (add `@Published`, etc.)

---

## 🏗️ Project Structure Details

### CLI-Prototype (Swift Package)

```
CLI-Prototype/
├── Package.swift              ← Defines targets and dependencies
│   ├── CIOHIDUserDevice       ← C module (IOKit bridge)
│   └── WiimoteGamepadCLI      ← Executable target
│
└── Sources/
    ├── CIOHIDUserDevice/      ← Bridging C APIs
    │   └── include/
    │       └── *.h            ← Headers for Swift
    │
    └── WiimoteGamepadCLI/     ← Swift source
        ├── main.swift         ← Entry point
        └── VirtualGamepad.swift
```

**Build**: `swift build`  
**Run**: `.build/debug/WiimoteGamepadCLI`

### wiimacmote (Xcode App)

```
wiimacmote/
├── wiimacmote.xcodeproj/      ← Xcode project file
│   └── project.pbxproj        ← Project settings
│
├── wiimacmote.entitlements    ← App permissions
│
└── wiimacmote/                ← App bundle
    ├── Info.plist             ← App metadata (auto-generated)
    ├── wiimacmoteApp.swift    ← @main entry point
    ├── ContentView.swift      ← Main UI
    ├── VirtualGamepad.swift   ← Core logic
    ├── WiimoteManager.swift   ← Bluetooth
    ├── Bridging-Header.h      ← Swift↔️C bridge
    ├── Assets.xcassets/       ← Images, icons
    └── Preview Content/       ← SwiftUI previews
```

**Build**: Open in Xcode, press ⌘R  
**Output**: `.app` bundle in DerivedData

---

## 🚦 Development Workflow

### Phase 1: Organize Files
```bash
./organize-files.sh
```

### Phase 2: Verify CLI Still Works
```bash
cd CLI-Prototype
swift build
.build/debug/WiimoteGamepadCLI
# Should create virtual gamepad
```

### Phase 3: Configure Xcode
```bash
cd wiimacmote
open wiimacmote.xcodeproj
```
- Fix file references
- Set bridging header
- Link IOKit
- Configure signing

### Phase 4: Test SwiftUI App
- Press ⌘R
- Grant permissions
- See virtual gamepad in system

### Phase 5: Add Wiimote Support
- Implement connection UI in ContentView
- Use WiimoteManager to handle Bluetooth
- Test with real Wiimote

---

## ✅ Success Criteria

### CLI-Prototype ✓
- [ ] `swift build` succeeds
- [ ] `WiimoteGamepadCLI` runs and creates gamepad
- [ ] Appears in gamepad-tester.com

### wiimacmote ✓
- [ ] Xcode project opens without errors
- [ ] All files found (no red files)
- [ ] App builds successfully (⌘R)
- [ ] Virtual gamepad created on launch
- [ ] Ready to add Wiimote Bluetooth code

---

## 🎨 Visual: Two-Project Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Mac (macOS 13+)                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌───────────────────┐         ┌─────────────────────────┐  │
│  │  CLI-Prototype    │         │    wiimacmote (App)     │  │
│  │  ┌─────────────┐  │         │   ┌──────────────────┐  │  │
│  │  │ main.swift  │──┼────────────▶│ ContentView.swift│  │  │
│  │  └─────────────┘  │  Copy   │   └──────────────────┘  │  │
│  │        │          │  Code   │            │             │  │
│  │  ┌─────▼───────┐  │  ───▶   │   ┌────────▼──────────┐ │  │
│  │  │VirtualGamepad│──┼────────────▶│  VirtualGamepad   │ │  │
│  │  │  (CLI)       │  │         │   │  (SwiftUI)        │ │  │
│  │  └──────────────┘  │         │   └───────┬───────────┘ │  │
│  │        │           │         │           │              │  │
│  │        │           │         │   ┌───────▼───────────┐ │  │
│  │        │           │         │   │ WiimoteManager    │ │  │
│  │        │           │         │   │ (Bluetooth)       │ │  │
│  │        │           │         │   └───────┬───────────┘ │  │
│  └────────┼───────────┘         └───────────┼─────────────┘  │
│           │                                 │                 │
│           └─────────────┬───────────────────┘                 │
│                         ▼                                     │
│                ┌─────────────────────┐                        │
│                │   IOHIDUserDevice   │                        │
│                │  (macOS Kernel)     │                        │
│                └─────────┬───────────┘                        │
│                          ▼                                    │
│                ┌─────────────────────┐                        │
│                │ Virtual HID Gamepad │                        │
│                │  (System-wide)      │                        │
│                └─────────────────────┘                        │
│                          │                                    │
│                          ▼                                    │
│                    ┌──────────┐                               │
│                    │  Games   │                               │
│                    └──────────┘                               │
└─────────────────────────────────────────────────────────────┘

     Testing ◀────────┤├───────▶ Production
```

---

**Ready to organize?** Run `./organize-files.sh` or follow the manual guide! 🚀

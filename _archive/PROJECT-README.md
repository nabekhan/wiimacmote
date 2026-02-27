# Wiimote Virtual Gamepad for macOS

Transform your Wiimote into a virtual game controller on macOS using SwiftUI.

## Project Structure

This repository contains two projects:

### 🎯 **wiimacmote/** - Main SwiftUI App (End Goal)
The production application with a native macOS UI. This is what you'll distribute to users.

- **Technology**: SwiftUI + IOKit
- **Platform**: macOS 13.0+
- **Purpose**: User-friendly app to connect Wiimote and use it as a game controller
- **Status**: 🚧 In Development

[→ See wiimacmote/README.md](wiimacmote/README.md)

### 🔬 **CLI-Prototype/** - Command Line Proof of Concept
A Swift Package that proved the virtual HID device creation works. Used for rapid testing.

- **Technology**: Swift Package Manager + IOKit
- **Platform**: macOS 13.0+
- **Purpose**: Test virtual gamepad creation without UI overhead
- **Status**: ✅ Working - Archived as reference

[→ See CLI-Prototype/README.md](CLI-Prototype/README.md)

---

## Quick Start

### Running the SwiftUI App

```bash
cd wiimacmote
open wiimacmote.xcodeproj
```

Then press **⌘R** to build and run.

### Testing the CLI (for development)

```bash
cd CLI-Prototype
swift build
.build/debug/WiimoteGamepadCLI
```

---

## How It Works

1. **Virtual HID Device**: Creates a virtual gamepad using `IOHIDUserDevice` from IOKit
2. **Wiimote Connection**: Connects to Wiimote via Bluetooth (IOBluetooth framework)
3. **Button Mapping**: Translates Wiimote button presses to gamepad buttons
4. **System Integration**: Appears as a standard gamepad to macOS and games

---

## Development Workflow

1. **Test core functionality**: Use CLI-Prototype for quick iterations
2. **Build the UI**: Develop in wiimacmote SwiftUI app
3. **Share code**: Core classes (VirtualGamepad) are shared between both

---

## Requirements

- **macOS 13.0+** (Ventura or later)
- **Xcode 15.0+**
- **Apple ID** (for code signing, even free account works)
- **Wiimote** (Nintendo RVL-CNT-01)

---

## License

Personal development project.

---

## Next Steps

- [x] Prove virtual HID device creation works (CLI)
- [ ] Create SwiftUI interface
- [ ] Implement Wiimote Bluetooth connection
- [ ] Add button mapping configuration
- [ ] Test with actual games
- [ ] Polish UI/UX
- [ ] Distribute

---

**Current Focus**: Building SwiftUI app in `wiimacmote/`

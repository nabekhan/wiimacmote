# 🚨 FIX BUILD ERRORS - DO THIS NOW

## The Problem

Your Xcode project is trying to build **both** the Swift Package (CLI) and the SwiftUI app at the same time. This creates conflicts because they both try to produce output files.

## The Solution (2 minutes)

### Step 1: Run the fix script

```bash
chmod +x FIX-EVERYTHING.sh
./FIX-EVERYTHING.sh
```

This will:
- Clean build artifacts
- Disable Package.swift (the main culprit)
- Remove CLI files from Xcode's view
- Install clean working files

### Step 2: Clean Xcode

1. Open `wiimacmote.xcodeproj` in Xcode
2. **Product → Clean Build Folder** (⇧⌘K)
3. **File → Close Project**
4. **Re-open** the project

### Step 3: Remove CLI references

In Project Navigator (left sidebar):

If you see `main.swift` (might be red):
- Right-click → **Delete**
- Choose **Remove Reference** (not Move to Trash)

If you see `Package.swift`:
- Right-click → **Delete**
- Choose **Remove Reference**

### Step 4: Verify required files

Make sure these files ARE in the project:
- ✅ `wiimacmoteApp.swift`
- ✅ `ContentView.swift`  
- ✅ `VirtualGamepad.swift`
- ✅ `CIOHIDUserDevice-Bridging-Header.h`

### Step 5: Check Build Settings

1. Click project name (blue icon) in navigator
2. Select `wiimacmote` target
3. Go to **Build Settings** tab
4. Search for "bridging"
5. Make sure it says: `CIOHIDUserDevice-Bridging-Header.h`

### Step 6: Check Frameworks

1. **General** tab
2. **Frameworks, Libraries, and Embedded Content**
3. Make sure `IOKit.framework` is there
4. If not: Click **+** → Search "IOKit" → Add

### Step 7: Build!

Press **⌘R** (or Product → Run)

It should build successfully! 🎉

---

## If It STILL Doesn't Work

The Xcode project file itself might be corrupted. Here's what to do:

### Option A: Create Fresh Xcode Project (5 minutes)

1. **Close** current project
2. **Rename** folder: `mv wiimacmote wiimacmote-OLD`
3. Open Xcode → **File → New → Project**
4. Choose **macOS → App**
5. Product Name: **wiimacmote**
6. Interface: **SwiftUI**
7. Save next to `wiimacmote-OLD`

8. In new project:
   - Delete generated `wiimacmoteApp.swift` and `ContentView.swift`
   - Drag these files from `wiimacmote-OLD`:
     - `wiimacmoteApp.swift`
     - `ContentView.swift`
     - `VirtualGamepad.swift`
     - `CIOHIDUserDevice-Bridging-Header.h`

9. Set bridging header (Build Settings)
10. Link IOKit framework (General tab)
11. Build! (⌘R)

### Option B: Manual File Removal

If some weird files got into your Xcode project:

```bash
# Find all CLI/Package-related files
find . -name "*.d"
find . -name "*WiimoteGamepadCLI*"
find . -name "Package.swift"

# Remove them
rm -rf *.d
rm -rf *WiimoteGamepadCLI*
```

Then clean Xcode (⇧⌘K) and rebuild.

---

## What the Error Means

```
error: Multiple commands produce 'WiimoteGamepadCLI.swiftmodule'
```

This means Xcode found **TWO** build targets trying to create the same file:
1. Your SwiftUI app target
2. The Swift Package target (from Package.swift)

By disabling `Package.swift`, we remove the conflict.

---

## After It Builds Successfully

You should see:
- App launches
- Shows gamepad interface
- Console prints: "✅ Virtual gamepad created and activated"

Then:
1. Grant Input Monitoring permission (System Settings)
2. Restart app
3. Test buttons in the app
4. Visit gamepad-tester.com to verify

---

## Prevention

To avoid this in the future:

**For CLI testing:**
- Keep `Package.swift` in a separate `CLI-Prototype/` folder
- Build from there: `cd CLI-Prototype && swift build`

**For SwiftUI app:**
- Use Xcode project only
- No `Package.swift` in same directory

---

## Still Stuck?

Run this to see what's in your Xcode project:

```bash
find . -name "*.swift" -not -path "./.build/*"
```

This shows all Swift files. The only ones that should be in the app:
- `wiimacmoteApp.swift`
- `ContentView.swift`
- `VirtualGamepad.swift`

If you see `main.swift` or others, they need to be removed from Xcode.

---

**TL;DR:** Run `./FIX-EVERYTHING.sh`, clean Xcode, remove CLI files from project, build. Done! ✅

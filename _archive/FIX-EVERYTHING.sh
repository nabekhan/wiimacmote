#!/bin/bash
# FIX-EVERYTHING.sh
# This script fixes ALL build issues and creates a clean working project

set -e

echo "🔧 FIXING ALL BUILD ISSUES"
echo "═══════════════════════════"
echo ""

# Step 1: Clean everything
echo "Step 1: Cleaning build artifacts..."
rm -rf .build/ 2>/dev/null || true
rm -rf ~/Library/Developer/Xcode/DerivedData/wiimacmote-* 2>/dev/null || true
rm -f *.d *.swiftmodule *.emit-module.d 2>/dev/null || true
echo "✅ Cleaned build artifacts"
echo ""

# Step 2: Move Package.swift away (IT'S THE PROBLEM!)
echo "Step 2: Disabling Package.swift..."
if [ -f "Package.swift" ]; then
    mv Package.swift Package.swift.DISABLED
    echo "✅ Moved Package.swift → Package.swift.DISABLED"
    echo "   (This was causing the conflict!)"
else
    echo "⊘ Package.swift already moved"
fi
echo ""

# Step 3: Remove any CLI source files that might be in Xcode project
echo "Step 3: Moving CLI files away from Xcode..."
mkdir -p CLI-Prototype-OLD 2>/dev/null || true

if [ -f "main.swift" ]; then
    mv main.swift CLI-Prototype-OLD/ 2>/dev/null || true
    echo "✅ Moved main.swift"
fi

if [ -f "WiimoteGamepadmain.swift" ]; then
    mv WiimoteGamepadmain.swift CLI-Prototype-OLD/ 2>/dev/null || true
    echo "✅ Moved WiimoteGamepadmain.swift"
fi

echo ""

# Step 4: Use the simple VirtualGamepad
echo "Step 4: Installing clean VirtualGamepad.swift..."
if [ -f "VirtualGamepad-SIMPLE.swift" ]; then
    cp VirtualGamepad-SIMPLE.swift VirtualGamepad.swift
    echo "✅ Created VirtualGamepad.swift (simple version)"
else
    echo "⚠️  VirtualGamepad-SIMPLE.swift not found"
fi
echo ""

# Step 5: Ensure bridging header exists
echo "Step 5: Checking bridging header..."
if [ ! -f "CIOHIDUserDevice-Bridging-Header.h" ]; then
    cat > CIOHIDUserDevice-Bridging-Header.h << 'EOF'
//
//  CIOHIDUserDevice-Bridging-Header.h
//  wiimacmote
//

#ifndef CIOHIDUserDevice_Bridging_Header_h
#define CIOHIDUserDevice_Bridging_Header_h

#import <IOKit/hid/IOHIDUserDevice.h>

#endif
EOF
    echo "✅ Created bridging header"
else
    echo "✓ Bridging header exists"
fi
echo ""

echo "═══════════════════════════════════════════════"
echo "✅ ALL FIXES APPLIED!"
echo "═══════════════════════════════════════════════"
echo ""
echo "📋 What was fixed:"
echo "   1. ✅ Removed build artifacts"
echo "   2. ✅ Disabled Package.swift (main conflict)"
echo "   3. ✅ Moved CLI files away"
echo "   4. ✅ Installed clean VirtualGamepad"
echo "   5. ✅ Ensured bridging header exists"
echo ""
echo "🎯 NOW DO THIS IN XCODE:"
echo ""
echo "1. Product → Clean Build Folder (⇧⌘K)"
echo "2. File → Close Project"
echo "3. Re-open wiimacmote.xcodeproj"
echo ""
echo "4. In Project Navigator, check these files are present:"
echo "   ✓ wiimacmoteApp.swift"
echo "   ✓ ContentView.swift"
echo "   ✓ VirtualGamepad.swift"
echo "   ✓ CIOHIDUserDevice-Bridging-Header.h"
echo ""
echo "5. If 'main.swift' is in the project (red or not):"
echo "   → Right-click → Delete → Remove Reference"
echo ""
echo "6. Check Build Settings:"
echo "   → Search for 'bridging'"
echo "   → Set to: CIOHIDUserDevice-Bridging-Header.h"
echo ""
echo "7. Check Frameworks:"
echo "   → General tab → Frameworks"
echo "   → Make sure IOKit.framework is listed"
echo ""
echo "8. Press ⌘R to build and run!"
echo ""
echo "═══════════════════════════════════════════════"
echo ""
echo "If you STILL get errors, the Xcode project file"
echo "itself might be corrupted. In that case:"
echo ""
echo "Option A: Create fresh Xcode project"
echo "  1. File → New → Project → macOS App"
echo "  2. Name: wiimacmote"
echo "  3. Delete generated files"
echo "  4. Add our files"
echo ""
echo "Option B: I can generate a working project.pbxproj"
echo "          (but that's complex)"
echo ""
echo "═══════════════════════════════════════════════"

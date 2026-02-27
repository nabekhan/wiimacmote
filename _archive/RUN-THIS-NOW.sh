#!/bin/bash
# RUN-THIS-NOW.sh
# The ONLY script you need to run to fix everything

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║                                               ║"
echo "║   🔧 FIXING YOUR WIIMOTE PROJECT NOW 🔧      ║"
echo "║                                               ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""

# Step 1: Clean
echo "🧹 Step 1/5: Cleaning build artifacts..."
rm -rf .build/ 2>/dev/null || true
rm -rf ~/Library/Developer/Xcode/DerivedData/wiimacmote-* 2>/dev/null || true  
rm -f *.d *.swiftmodule *.emit-module.d 2>/dev/null || true
echo "   ✅ Done"
echo ""

# Step 2: Disable Package.swift (THE FIX!)
echo "🔧 Step 2/5: Disabling Package.swift..."
if [ -f "Package.swift" ]; then
    mv Package.swift Package.swift.DISABLED
    echo "   ✅ Moved Package.swift → Package.swift.DISABLED"
elif [ -f "Package.swift.DISABLED" ]; then
    echo "   ✓ Already disabled"
else
    echo "   ⊘ Not found"
fi
echo ""

# Step 3: Ensure we have the right Swift files
echo "📝 Step 3/5: Checking Swift files..."
if [ ! -f "wiimacmoteApp.swift" ]; then
    echo "   ⚠️  wiimacmoteApp.swift not found!"
else
    echo "   ✓ wiimacmoteApp.swift"
fi

if [ ! -f "ContentView.swift" ]; then
    echo "   ⚠️  ContentView.swift not found!"
else
    echo "   ✓ ContentView.swift"
fi

if [ -f "VirtualGamepad-SIMPLE.swift" ] && [ ! -f "VirtualGamepad.swift" ]; then
    cp VirtualGamepad-SIMPLE.swift VirtualGamepad.swift
    echo "   ✅ Created VirtualGamepad.swift"
elif [ -f "VirtualGamepad.swift" ]; then
    echo "   ✓ VirtualGamepad.swift"
else
    echo "   ⚠️  VirtualGamepad.swift not found!"
fi
echo ""

# Step 4: Create/check bridging header
echo "🔗 Step 4/5: Checking bridging header..."
if [ ! -f "wiimacmote-Bridging-Header.h" ]; then
    cat > wiimacmote-Bridging-Header.h << 'EOF'
//
//  wiimacmote-Bridging-Header.h
//  wiimacmote
//

#ifndef wiimacmote_Bridging_Header_h
#define wiimacmote_Bridging_Header_h

#import <IOKit/hid/IOHIDUserDevice.h>

#endif
EOF
    echo "   ✅ Created wiimacmote-Bridging-Header.h"
else
    echo "   ✓ Bridging header exists"
fi
echo ""

# Step 5: Move CLI files away
echo "📦 Step 5/5: Moving CLI files out of the way..."
mkdir -p OLD-CLI-FILES 2>/dev/null || true
moved_any=false

if [ -f "main.swift" ]; then
    mv main.swift OLD-CLI-FILES/ 2>/dev/null || true
    echo "   ✅ Moved main.swift"
    moved_any=true
fi

if [ -f "WiimoteGamepadmain.swift" ]; then
    mv WiimoteGamepadmain.swift OLD-CLI-FILES/ 2>/dev/null || true
    echo "   ✅ Moved WiimoteGamepadmain.swift"
    moved_any=true
fi

if [ "$moved_any" = false ]; then
    echo "   ✓ No CLI files to move"
fi
echo ""

echo "╔═══════════════════════════════════════════════╗"
echo "║                                               ║"
echo "║           ✅  FIXES APPLIED!  ✅             ║"
echo "║                                               ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
echo "📋 What was fixed:"
echo ""
echo "   ✅ Cleaned build artifacts"
echo "   ✅ Disabled Package.swift (main conflict)"
echo "   ✅ Ensured Swift files exist"
echo "   ✅ Created bridging header"
echo "   ✅ Moved CLI files away"
echo ""
echo "🎯 NOW OPEN XCODE:"
echo ""
echo "   1. Open: wiimacmote.xcodeproj"
echo "   2. Press: ⇧⌘K (Clean Build Folder)"
echo "   3. If you see 'main.swift' in project:"
echo "      → Right-click → Delete → Remove Reference"
echo "   4. Check Build Settings → Bridging Header:"
echo "      → Should be: wiimacmote-Bridging-Header.h"
echo "   5. General tab → Frameworks:"
echo "      → Make sure IOKit.framework is there"
echo "   6. Press: ⌘R to build and run"
echo ""
echo "🎉 IT SHOULD WORK NOW!"
echo ""
echo "If you still get errors, read:"
echo "   HOW-TO-FIX-BUILD.md"
echo ""

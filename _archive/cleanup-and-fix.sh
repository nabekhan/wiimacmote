#!/bin/bash
# cleanup-and-fix.sh
# This script will clean up the project and create a working SwiftUI app

set -e

echo "🧹 Cleaning up project and fixing build issues..."
echo ""

# Step 1: Remove build artifacts
echo "Step 1: Removing build artifacts..."
rm -rf .build/
rm -rf DerivedData/
rm -rf *.d
rm -rf *.swiftmodule
rm -rf *.emit-module.d
echo "✓ Build artifacts removed"
echo ""

# Step 2: Move Package.swift out of the way (it's causing conflicts)
echo "Step 2: Moving Package.swift to CLI-Prototype..."
if [ -f "Package.swift" ]; then
    mkdir -p CLI-Prototype
    mv Package.swift CLI-Prototype/
    echo "✓ Package.swift moved"
else
    echo "⊘ Package.swift not found (already moved?)"
fi
echo ""

# Step 3: Create clean SwiftUI app structure
echo "Step 3: Creating clean wiimacmote app structure..."
mkdir -p wiimacmote/wiimacmote

# Move SwiftUI files to correct location
if [ -f "wiimacmoteApp.swift" ]; then
    mv wiimacmoteApp.swift wiimacmote/wiimacmote/
    echo "✓ Moved wiimacmoteApp.swift"
fi

if [ -f "ContentView.swift" ]; then
    mv ContentView.swift wiimacmote/wiimacmote/
    echo "✓ Moved ContentView.swift"
fi

# Copy the SwiftUI version of VirtualGamepad
if [ -f "VirtualGamepad-SwiftUI.swift" ]; then
    cp VirtualGamepad-SwiftUI.swift wiimacmote/wiimacmote/VirtualGamepad.swift
    echo "✓ Created VirtualGamepad.swift for app"
elif [ -f "VirtualGamepad.swift" ]; then
    cp VirtualGamepad.swift wiimacmote/wiimacmote/
    echo "✓ Copied VirtualGamepad.swift"
fi

# Copy WiimoteManager if it exists
if [ -f "WiimoteManager.swift" ]; then
    cp WiimoteManager.swift wiimacmote/wiimacmote/
    echo "✓ Copied WiimoteManager.swift"
fi

# Copy bridging header
if [ -f "CIOHIDUserDevice-Bridging-Header.h" ]; then
    cp CIOHIDUserDevice-Bridging-Header.h wiimacmote/wiimacmote/
    echo "✓ Copied bridging header"
fi

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Open Xcode and create a NEW SwiftUI app:"
echo "   - File → New → Project"
echo "   - Choose 'App' under macOS"
echo "   - Product Name: wiimacmote"
echo "   - Interface: SwiftUI"
echo "   - Save in: wiimacmote/ folder"
echo ""
echo "2. Replace the generated files with our files:"
echo "   - Delete wiimacmoteApp.swift and ContentView.swift"
echo "   - Drag files from wiimacmote/wiimacmote/ into Xcode"
echo ""
echo "3. Add bridging header and frameworks"
echo ""
echo "OR... let me create a working Xcode project for you!"
echo "Run: ./create-xcode-project.sh"
echo ""

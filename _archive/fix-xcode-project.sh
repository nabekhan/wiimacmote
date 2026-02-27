#!/bin/bash
# fix-xcode-project.sh
# Fixes the "Multiple commands produce" error by cleaning up the project

set -e

echo "🔧 Fixing Xcode Project - Removing CLI Target Conflicts"
echo "======================================================="
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if we're in the right directory
if [ ! -f "wiimacmote.xcodeproj/project.pbxproj" ]; then
    echo -e "${RED}❌ Error: Must run from wiimacmote/ directory${NC}"
    echo "Usage:"
    echo "  cd wiimacmote"
    echo "  ../fix-xcode-project.sh"
    exit 1
fi

echo "Step 1: Backing up project file..."
cp wiimacmote.xcodeproj/project.pbxproj wiimacmote.xcodeproj/project.pbxproj.backup
echo -e "${GREEN}✓${NC} Backup created: project.pbxproj.backup"
echo ""

echo "Step 2: Removing Package.swift references..."
if [ -f "Package.swift" ]; then
    rm Package.swift
    echo -e "${GREEN}✓${NC} Removed Package.swift"
fi

if [ -d "Sources" ]; then
    rm -rf Sources
    echo -e "${GREEN}✓${NC} Removed Sources/ directory"
fi

echo ""
echo "Step 3: Cleaning build artifacts..."
rm -rf ~/Library/Developer/Xcode/DerivedData/wiimacmote-*
echo -e "${GREEN}✓${NC} Cleared DerivedData"

echo ""
echo "═══════════════════════════════════════════"
echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo "═══════════════════════════════════════════"
echo ""
echo "Next steps in Xcode:"
echo ""
echo "1. Open the project:"
echo "   open wiimacmote.xcodeproj"
echo ""
echo "2. Select project in navigator (blue icon)"
echo ""
echo "3. Check TARGETS list - you should see:"
echo "   ✅ wiimacmote (keep this)"
echo "   ❌ WiimoteGamepadCLI (DELETE this if present)"
echo ""
echo "4. To delete WiimoteGamepadCLI target:"
echo "   - Select it in targets list"
echo "   - Press Delete key"
echo "   - Confirm"
echo ""
echo "5. Clean and rebuild:"
echo "   Product → Clean Build Folder (⇧⌘K)"
echo "   Product → Build (⌘B)"
echo ""
echo "If you still have errors, you may need to manually"
echo "remove file references from the project."
echo ""

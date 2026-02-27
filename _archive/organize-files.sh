#!/bin/bash
# organize-files.sh
# Automatically organizes files into CLI-Prototype and wiimacmote folders

set -e  # Exit on error

echo "📁 Wiimote Project File Organization Script"
echo "==========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to safely move file if it exists
safe_move() {
    local src="$1"
    local dest="$2"
    
    if [ -f "$src" ]; then
        echo -e "${GREEN}✓${NC} Moving: $src → $dest"
        mv "$src" "$dest"
    elif [ -d "$src" ]; then
        echo -e "${GREEN}✓${NC} Moving: $src/ → $dest/"
        mv "$src" "$dest"
    else
        echo -e "${YELLOW}⊘${NC} Not found (skipping): $src"
    fi
}

# Function to create directory if it doesn't exist
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo -e "${GREEN}+${NC} Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

echo "Step 1: Creating folder structure..."
echo "────────────────────────────────────"

# Create CLI-Prototype structure
ensure_dir "CLI-Prototype"
ensure_dir "CLI-Prototype/Sources"
ensure_dir "CLI-Prototype/Sources/CIOHIDUserDevice"
ensure_dir "CLI-Prototype/Sources/CIOHIDUserDevice/include"
ensure_dir "CLI-Prototype/Sources/WiimoteGamepadCLI"

# Create wiimacmote structure
ensure_dir "wiimacmote"
ensure_dir "wiimacmote/wiimacmote"

echo ""
echo "Step 2: Moving CLI Prototype files..."
echo "────────────────────────────────────"

# Package files
safe_move "Package.swift" "CLI-Prototype/"
safe_move "build-app.sh" "CLI-Prototype/"

# Documentation
safe_move "QUICKSTART.md" "CLI-Prototype/"
safe_move "XCODE-SETUP.md" "CLI-Prototype/"
safe_move "MIGRATION.md" "CLI-Prototype/"

# Entitlements
safe_move "WiimoteGamepadCLI.entitlements" "CLI-Prototype/"
safe_move "Info.plist" "CLI-Prototype/"

# Source files - check multiple possible names
safe_move "main.swift" "CLI-Prototype/Sources/WiimoteGamepadCLI/"
safe_move "WiimoteGamepadmain.swift" "CLI-Prototype/Sources/WiimoteGamepadCLI/main.swift"

# VirtualGamepad - handle both versions
if [ -f "VirtualGamepad.swift" ] && [ -f "WiimoteGamepadVirtualGamepad.swift" ]; then
    echo -e "${YELLOW}!${NC} Found two VirtualGamepad files!"
    safe_move "VirtualGamepad.swift" "CLI-Prototype/Sources/WiimoteGamepadCLI/"
    echo -e "${YELLOW}!${NC} Keeping WiimoteGamepadVirtualGamepad.swift as backup"
    safe_move "WiimoteGamepadVirtualGamepad.swift" "CLI-Prototype/VirtualGamepad-Alternative.swift.backup"
elif [ -f "VirtualGamepad.swift" ]; then
    safe_move "VirtualGamepad.swift" "CLI-Prototype/Sources/WiimoteGamepadCLI/"
elif [ -f "WiimoteGamepadVirtualGamepad.swift" ]; then
    safe_move "WiimoteGamepadVirtualGamepad.swift" "CLI-Prototype/Sources/WiimoteGamepadCLI/VirtualGamepad.swift"
fi

# C headers
safe_move "CIOHIDUserDevice.h" "CLI-Prototype/Sources/CIOHIDUserDevice/include/"
safe_move "IOHIDUserDeviceBridge.h" "CLI-Prototype/Sources/CIOHIDUserDevice/include/"

# Module maps (check various locations)
for modulemap in module.modulemap */module.modulemap */*/module.modulemap; do
    if [ -f "$modulemap" ] && [[ "$modulemap" != "CLI-Prototype/"* ]] && [[ "$modulemap" != "wiimacmote/"* ]]; then
        # Try to determine where it should go based on parent directory
        if [[ "$modulemap" == *"CIOHIDUserDevice"* ]]; then
            safe_move "$modulemap" "CLI-Prototype/Sources/CIOHIDUserDevice/"
        else
            safe_move "$modulemap" "CLI-Prototype/Sources/WiimoteGamepadCLI/"
        fi
    fi
done

echo ""
echo "Step 3: Moving SwiftUI App files..."
echo "────────────────────────────────────"

# SwiftUI source files
safe_move "wiimacmoteApp.swift" "wiimacmote/wiimacmote/"
safe_move "ContentView.swift" "wiimacmote/wiimacmote/"

# New files created by organization
safe_move "VirtualGamepad-SwiftUI.swift" "wiimacmote/wiimacmote/VirtualGamepad.swift"
safe_move "WiimoteManager.swift" "wiimacmote/wiimacmote/"
safe_move "CIOHIDUserDevice-Bridging-Header.h" "wiimacmote/wiimacmote/"
safe_move "wiimacmote.entitlements" "wiimacmote/"

echo ""
echo "Step 4: Organizing documentation..."
echo "────────────────────────────────────"

# Move original README to CLI folder
safe_move "README.md" "CLI-Prototype/"

# Rename organized READMEs
safe_move "CLI-README.md" "CLI-Prototype/README-ORGANIZED.md"
safe_move "SWIFTUI-README.md" "wiimacmote/README.md"
safe_move "PROJECT-README.md" "README.md"

echo ""
echo "Step 5: Cleaning up build artifacts..."
echo "────────────────────────────────────"

if [ -d ".build" ]; then
    echo -e "${GREEN}✓${NC} Removing .build/ directory"
    rm -rf .build/
fi

# Remove intermediate build files at root
for file in *.d *.emit-module.d; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} Removing: $file"
        rm "$file"
    fi
done

echo ""
echo "═══════════════════════════════════════════════"
echo -e "${GREEN}✅ File organization complete!${NC}"
echo "═══════════════════════════════════════════════"
echo ""
echo "📂 Your new structure:"
echo ""
echo "  CLI-Prototype/          ← Swift Package (testing)"
echo "  wiimacmote/             ← SwiftUI App (main project)"
echo "  README.md               ← Project overview"
echo ""
echo "Next steps:"
echo ""
echo "  1. Test CLI prototype:"
echo "     cd CLI-Prototype && swift build"
echo ""
echo "  2. Open SwiftUI app in Xcode:"
echo "     cd wiimacmote && open wiimacmote.xcodeproj"
echo "     (You'll need to re-add files to Xcode project)"
echo ""
echo "  3. Configure Xcode project:"
echo "     - Add moved files to project"
echo "     - Set bridging header path"
echo "     - Link IOKit framework"
echo "     - Add entitlements"
echo ""
echo "See FILE-ORGANIZATION-GUIDE.md for detailed instructions!"
echo ""

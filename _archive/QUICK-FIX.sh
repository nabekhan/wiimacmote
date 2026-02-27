#!/bin/bash
# QUICK FIX - Run this to make your project compile

echo "🔧 Quick Fix for Build Errors"
echo "=============================="
echo ""

# The problem: Package.swift is interfering with Xcode build
# Solution: Move it away temporarily

if [ -f "Package.swift" ]; then
    echo "📦 Moving Package.swift → Package.swift.disabled"
    mv Package.swift Package.swift.disabled
    echo "✅ Done!"
    echo ""
    echo "Now try building in Xcode again (⌘B)"
    echo ""
    echo "To restore CLI functionality later:"
    echo "  mv Package.swift.disabled Package.swift"
else
    echo "⚠️  Package.swift not found. Already moved?"
fi

echo ""
echo "Also cleaning build folder..."
rm -rf ~/Library/Developer/Xcode/DerivedData/wiimacmote-*
echo "✅ Cleaned DerivedData"
echo ""
echo "🎯 Now press ⌘B in Xcode to rebuild!"

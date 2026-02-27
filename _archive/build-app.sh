#!/bin/bash
# Build script to create a signed app bundle for Wiimote Gamepad
# This allows building from the command line without Xcode

set -e  # Exit on error

echo "🔨 Building Wiimote Gamepad..."

# Configuration
APP_NAME="WiimoteGamepad"
BUNDLE_ID="com.wiimote.gamepad"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

# Build the Swift package in release mode
echo "📦 Compiling Swift package..."
swift build -c release

# Create app bundle structure
echo "🏗️  Creating app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
echo "📋 Copying executable..."
cp "${BUILD_DIR}/WiimoteGamepadCLI" "${APP_BUNDLE}/Contents/MacOS/WiimoteGamepadCLI"
chmod +x "${APP_BUNDLE}/Contents/MacOS/WiimoteGamepadCLI"

# Copy Info.plist
echo "📋 Copying Info.plist..."
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"

# Copy entitlements (for reference, not embedded in app)
cp WiimoteGamepadCLI.entitlements "${APP_BUNDLE}/Contents/Resources/"

# Check if we should sign
if [ -z "$SIGNING_IDENTITY" ]; then
    echo ""
    echo "⚠️  No signing identity specified."
    echo "    Set SIGNING_IDENTITY environment variable to sign the app."
    echo "    Example: SIGNING_IDENTITY=\"Apple Development: your@email.com\" ./build-app.sh"
    echo ""
    echo "    To list available identities: security find-identity -v -p codesigning"
    echo ""
    echo "✅ App bundle created (unsigned): ${APP_BUNDLE}"
    echo "    Note: Unsigned apps won't work for creating virtual HID devices."
else
    # Sign the app bundle
    echo "✍️  Signing app with identity: ${SIGNING_IDENTITY}..."
    codesign --force --sign "${SIGNING_IDENTITY}" \
             --entitlements WiimoteGamepadCLI.entitlements \
             --deep \
             "${APP_BUNDLE}"
    
    # Verify signing
    echo "🔍 Verifying code signature..."
    codesign -vvv --deep --strict "${APP_BUNDLE}"
    codesign -d --entitlements - "${APP_BUNDLE}"
    
    echo ""
    echo "✅ Signed app bundle created: ${APP_BUNDLE}"
    echo ""
    echo "📱 Next steps:"
    echo "   1. Run the app: open ${APP_BUNDLE}"
    echo "   2. Grant Input Monitoring permission when prompted"
    echo "   3. System Preferences → Security & Privacy → Input Monitoring"
    echo "   4. Check the box next to WiimoteGamepad"
    echo "   5. Restart the app"
fi

echo ""
echo "🎉 Build complete!"

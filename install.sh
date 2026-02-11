#!/bin/bash

set -e

echo "🐸 Pepebot Android Installer"
echo "============================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Find APK
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_DIR="$SCRIPT_DIR/termux-app/app/build/outputs/apk/debug"

if [ ! -d "$APK_DIR" ]; then
    echo "❌ Error: APK directory not found. Please run ./build.sh first."
    exit 1
fi

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "❌ Error: adb not found. Please install Android SDK platform-tools."
    exit 1
fi

# Check for connected devices
DEVICES=$(adb devices | grep -v "List" | grep "device$" | wc -l)
if [ "$DEVICES" -eq 0 ]; then
    echo "❌ Error: No Android device connected."
    echo "   Please connect your device and enable USB debugging."
    exit 1
fi

echo "📱 Found $DEVICES connected device(s)"
echo ""

# List available APKs
echo "Available APKs:"
APK_FILES=($(find "$APK_DIR" -name "*.apk" -type f))
for i in "${!APK_FILES[@]}"; do
    name=$(basename "${APK_FILES[$i]}")
    size=$(ls -lh "${APK_FILES[$i]}" | awk '{print $5}')
    echo "  [$i] $name ($size)"
done
echo ""

# Default to universal APK
UNIVERSAL_APK=$(find "$APK_DIR" -name "*universal*.apk" | head -1)

if [ -z "$UNIVERSAL_APK" ]; then
    echo "❌ Error: Universal APK not found"
    exit 1
fi

echo "Installing universal APK (recommended)..."
echo "APK: $(basename "$UNIVERSAL_APK")"
echo ""

# Install APK
if adb install -r "$UNIVERSAL_APK"; then
    echo ""
    echo -e "${GREEN}✓ Installation successful!${NC}"
    echo ""
    echo "🎉 Pepebot is now installed on your device"
    echo ""
    echo "Next steps:"
    echo "  1. Open the Pepebot app"
    echo "  2. Wait for the bootstrap to extract (first launch only)"
    echo "  3. Tap '⚙️ Configure' to set up your API keys"
    echo "  4. Tap '▶️ Start Server' to launch the gateway"
    echo ""
    echo "To view logs:"
    echo "  adb logcat | grep -E \"(TermuxActivity|PepebotInstaller)\""
else
    echo ""
    echo "❌ Installation failed"
    exit 1
fi

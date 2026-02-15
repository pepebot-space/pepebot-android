#!/bin/bash

set -e  # Exit on error

echo "🐸 Pepebot Android Builder"
echo "=========================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PEPEBOT_REPO="https://github.com/pepebot-space/pepebot.git"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEPEBOT_DIR="$SCRIPT_DIR/pepebot"
TERMUX_APP_DIR="$SCRIPT_DIR/termux-app"
ASSETS_DIR="$TERMUX_APP_DIR/app/src/main/assets"

echo "📂 Working directories:"
echo "  Pepebot: $PEPEBOT_DIR"
echo "  Termux App: $TERMUX_APP_DIR"
echo ""

# Step 0: Clone Pepebot repository if not exists
if [ ! -d "$PEPEBOT_DIR" ]; then
    echo -e "${BLUE}📥 Step 0: Cloning Pepebot repository...${NC}"
    echo "  Repository: $PEPEBOT_REPO"

    git clone "$PEPEBOT_REPO" "$PEPEBOT_DIR"
    echo -e "${GREEN}✓ Pepebot repository cloned${NC}"
    echo ""
else
    echo -e "${BLUE}📦 Step 0: Updating Pepebot repository...${NC}"
    cd "$PEPEBOT_DIR"

    # Check if it's a git repository
    if [ -d ".git" ]; then
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || echo "  Using existing version"
        echo -e "${GREEN}✓ Pepebot repository updated${NC}"
    else
        echo -e "${YELLOW}  Using local pepebot directory (not a git repo)${NC}"
    fi
    echo ""
fi

# Step 1: Build Pepebot binaries
echo "🔨 Step 1: Building Pepebot binaries..."
cd "$PEPEBOT_DIR"

if [ ! -d "cmd/pepebot" ]; then
    echo -e "${RED}❌ Error: Pepebot source not found${NC}"
    exit 1
fi

echo "  Building for arm64 (Real devices - Android GOOS)..."
GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build -o pepebot-arm64 ./cmd/pepebot

echo "  Building for x86_64 (Emulators - Linux GOOS)..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o pepebot-x86_64 ./cmd/pepebot

echo ""
echo "  Note: armv7 skipped (requires CGO). 99% of devices are arm64."

echo -e "${GREEN}✓ Pepebot binaries built successfully${NC}"
echo ""

# Step 2: Copy binaries to assets
echo "📦 Step 2: Copying binaries to assets..."
mkdir -p "$ASSETS_DIR"
cp pepebot-arm64 "$ASSETS_DIR/"
# armv7 skipped - not needed for modern devices
cp pepebot-x86_64 "$ASSETS_DIR/"

# Create a dummy armv7 binary that shows error message
cat > "$ASSETS_DIR/pepebot-armv7" << 'EOF'
#!/bin/sh
echo "ERROR: armv7 not supported. Please use arm64 device."
exit 1
EOF
chmod +x "$ASSETS_DIR/pepebot-armv7"

echo "  Binaries copied:"
ls -lh "$ASSETS_DIR"/pepebot-* | awk '{print "    " $9 " (" $5 ")"}'
echo -e "${GREEN}✓ Binaries copied to assets${NC}"
echo ""

# Step 3: Build Android APK
echo "🏗️  Step 3: Building Android APK..."
cd "$TERMUX_APP_DIR"

echo "  Cleaning previous build..."
./gradlew clean > /dev/null 2>&1

echo "  Building debug APK..."
./gradlew assembleDebug

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Android APK built successfully${NC}"
    echo ""

    # Show generated APKs
    echo "📱 Generated APKs:"
    find app/build/outputs/apk/debug -name "*.apk" -type f | while read apk; do
        size=$(ls -lh "$apk" | awk '{print $5}')
        name=$(basename "$apk")
        echo "  • $name ($size)"
    done
    echo ""

    echo -e "${GREEN}🎉 Build completed successfully!${NC}"
    echo ""
    echo "📍 APKs location: $TERMUX_APP_DIR/app/build/outputs/apk/debug/"
    echo ""
    echo "To install on device:"
    echo "  adb install -r $TERMUX_APP_DIR/app/build/outputs/apk/debug/termux-app_apt-android-7-debug_universal.apk"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

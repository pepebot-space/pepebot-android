#!/bin/bash

set -e

echo "🐸 Pepebot Android Release Builder"
echo "===================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PEPEBOT_REPO="https://github.com/pepebot-space/pepebot.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEPEBOT_DIR="$SCRIPT_DIR/pepebot"
ASSETS_DIR="$SCRIPT_DIR/app/src/main/assets"

echo "📂 Working directories:"
echo "  Pepebot: $PEPEBOT_DIR"
echo "  Assets: $ASSETS_DIR"
echo ""

if [ ! -d "$PEPEBOT_DIR" ]; then
    echo -e "${BLUE}📥 Step 0: Cloning Pepebot repository...${NC}"
    echo "  Repository: $PEPEBOT_REPO"

    git clone "$PEPEBOT_REPO" "$PEPEBOT_DIR"
    echo -e "${GREEN}✓ Pepebot repository cloned${NC}"
    echo ""
else
    echo -e "${BLUE}📦 Step 0: Updating Pepebot repository...${NC}"
    cd "$PEPEBOT_DIR"

    if [ -d ".git" ]; then
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || echo "  Using existing version"
        echo -e "${GREEN}✓ Pepebot repository updated${NC}"
    else
        echo -e "${YELLOW}  Using local pepebot directory (not a git repo)${NC}"
    fi
    echo ""
fi

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

echo "📦 Step 2: Copying binaries to assets..."
mkdir -p "$ASSETS_DIR"
cp pepebot-arm64 "$ASSETS_DIR/"
cp pepebot-x86_64 "$ASSETS_DIR/"

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

echo "🏗️  Step 3: Building Android Release APK..."
cd "$SCRIPT_DIR"

echo "  Cleaning previous build..."
./gradlew clean > /dev/null 2>&1

echo "  Building release APK..."
./gradlew :app:assembleRelease

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Android Release APK built successfully${NC}"
    echo ""

    echo "📱 Generated APKs:"
    find app/build/outputs/apk/release -name "*.apk" -type f | while read apk; do
        size=$(ls -lh "$apk" | awk '{print $5}')
        name=$(basename "$apk")
        echo "  • $name ($size)"
    done
    echo ""

    echo -e "${GREEN}🎉 Release build completed successfully!${NC}"
    echo ""
    echo "📍 APKs location: $SCRIPT_DIR/app/build/outputs/apk/release/"
    echo ""
    echo "To install on device:"
    echo "  adb install -r app/build/outputs/apk/release/*.apk"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

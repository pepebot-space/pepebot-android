#!/bin/bash

echo "🐸 Pepebot Android Setup"
echo "========================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}This script will help you configure the Pepebot Android build.${NC}"
echo ""

# Prompt for pepebot repository URL
echo "Enter the Pepebot repository URL:"
echo "  (e.g., https://github.com/username/pepebot.git)"
read -p "URL: " REPO_URL

if [ -z "$REPO_URL" ]; then
    echo -e "${YELLOW}No URL provided. You'll need to manually edit build.sh${NC}"
    exit 1
fi

# Update build.sh
echo ""
echo "Updating build.sh with repository URL..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build.sh"

# Use sed to update the PEPEBOT_REPO line
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s|PEPEBOT_REPO=\".*\"|PEPEBOT_REPO=\"$REPO_URL\"|g" "$BUILD_SCRIPT"
else
    # Linux
    sed -i "s|PEPEBOT_REPO=\".*\"|PEPEBOT_REPO=\"$REPO_URL\"|g" "$BUILD_SCRIPT"
fi

echo -e "${GREEN}✓ Configuration updated${NC}"
echo ""
echo "Next steps:"
echo "  1. Run: ./build.sh"
echo "  2. Install: ./install.sh (or use adb)"
echo ""
echo -e "${BLUE}Happy building! 🚀${NC}"

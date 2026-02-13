#!/bin/bash

##
## Build Termux packages with custom package ID (com.pepebot.terminal)
## Based on: https://hongchai.medium.com/building-your-own-termux-with-a-custom-package-name-4b2de0c09fac
##
## This script:
##   1. Clones termux-packages repo
##   2. Patches properties.sh to use com.pepebot.terminal
##   3. Downloads the local build-bootstrap.sh script
##   4. Runs the build inside Docker
##   5. Copies bootstrap-*.zip files to termux-app/app/src/main/cpp/
##

set -e

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
CUSTOM_PACKAGE_NAME="com.pepebot.terminal"

# Architectures to build (comma-separated for the bootstrap script)
# Options: aarch64, arm, i686, x86_64
ARCHITECTURES="${ARCHITECTURES:-aarch64,arm,i686,x86_64}"

# Additional packages to include in bootstrap (comma-separated)
ADDITIONAL_PACKAGES="${ADDITIONAL_PACKAGES:-}"

# Force rebuild all packages
FORCE_BUILD="${FORCE_BUILD:-0}"

# ──────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ──────────────────────────────────────────────
# Directories
# ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERMUX_PACKAGES_DIR="$SCRIPT_DIR/termux-packages"
TERMUX_APP_DIR="$SCRIPT_DIR/termux-app"
BOOTSTRAP_DEST="$TERMUX_APP_DIR/app/src/main/cpp"
BUILD_BOOTSTRAP_GIST="https://gist.githubusercontent.com/seeya/a9ce074cf560aa7113043859360b7bfc/raw/206b5f4755b65569cf4af8d92b2481258c134b74/build-bootstrap.sh"

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Termux Packages Builder${NC}"
echo -e "${CYAN}  Package ID: ${GREEN}${CUSTOM_PACKAGE_NAME}${NC}"
echo -e "${CYAN}  Architectures: ${GREEN}${ARCHITECTURES}${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# ──────────────────────────────────────────────
# Pre-flight checks
# ──────────────────────────────────────────────
echo -e "${BLUE}[1/6] Checking prerequisites...${NC}"

if ! command -v docker &>/dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH.${NC}"
    echo "  Please install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}Error: Docker daemon is not running.${NC}"
    echo "  Please start Docker and try again."
    exit 1
fi

if ! command -v git &>/dev/null; then
    echo -e "${RED}Error: git is not installed.${NC}"
    exit 1
fi

echo -e "${GREEN}  Docker and git are available.${NC}"
echo ""

# ──────────────────────────────────────────────
# Step 1: Clone termux-packages
# ──────────────────────────────────────────────
echo -e "${BLUE}[2/6] Preparing termux-packages repository...${NC}"

if [ ! -d "$TERMUX_PACKAGES_DIR" ]; then
    echo "  Cloning termux-packages..."
    git clone https://github.com/termux/termux-packages.git "$TERMUX_PACKAGES_DIR"
    echo -e "${GREEN}  Cloned successfully.${NC}"
else
    echo "  termux-packages directory already exists."
    echo -e "${YELLOW}  To re-clone, remove $TERMUX_PACKAGES_DIR and re-run.${NC}"
fi
echo ""

# ──────────────────────────────────────────────
# Step 2: Patch properties.sh with custom package name
# ──────────────────────────────────────────────
echo -e "${BLUE}[3/6] Patching properties.sh with package name '${CUSTOM_PACKAGE_NAME}'...${NC}"

PROPERTIES_FILE="$TERMUX_PACKAGES_DIR/scripts/properties.sh"

if [ ! -f "$PROPERTIES_FILE" ]; then
    echo -e "${RED}Error: $PROPERTIES_FILE not found.${NC}"
    exit 1
fi

# Check if already patched
if grep -q "TERMUX_APP__PACKAGE_NAME=\"${CUSTOM_PACKAGE_NAME}\"" "$PROPERTIES_FILE" 2>/dev/null; then
    echo -e "${GREEN}  Already patched with ${CUSTOM_PACKAGE_NAME}.${NC}"
else
    # Patch TERMUX_APP__PACKAGE_NAME (new-style double underscore)
    if grep -q 'TERMUX_APP__PACKAGE_NAME="com.termux"' "$PROPERTIES_FILE"; then
        sed -i.bak 's/TERMUX_APP__PACKAGE_NAME="com.termux"/TERMUX_APP__PACKAGE_NAME="'"${CUSTOM_PACKAGE_NAME}"'"/' "$PROPERTIES_FILE"
        echo -e "${GREEN}  Patched TERMUX_APP__PACKAGE_NAME -> ${CUSTOM_PACKAGE_NAME}${NC}"
    # Fallback: patch old-style TERMUX_APP_PACKAGE
    elif grep -q 'TERMUX_APP_PACKAGE="com.termux"' "$PROPERTIES_FILE"; then
        sed -i.bak 's/TERMUX_APP_PACKAGE="com.termux"/TERMUX_APP_PACKAGE="'"${CUSTOM_PACKAGE_NAME}"'"/' "$PROPERTIES_FILE"
        echo -e "${GREEN}  Patched TERMUX_APP_PACKAGE -> ${CUSTOM_PACKAGE_NAME}${NC}"
    else
        echo -e "${YELLOW}  Warning: Could not find default package name in properties.sh.${NC}"
        echo "  Attempting to add it..."
        # Add at the beginning of the file after the first comment block
        echo "TERMUX_APP__PACKAGE_NAME=\"${CUSTOM_PACKAGE_NAME}\"" >> "$PROPERTIES_FILE"
        echo -e "${GREEN}  Appended TERMUX_APP__PACKAGE_NAME to properties.sh${NC}"
    fi
fi

# Verify the patch
echo "  Verifying patch..."
if grep -q "${CUSTOM_PACKAGE_NAME}" "$PROPERTIES_FILE"; then
    echo -e "${GREEN}  Verified: package name is set to ${CUSTOM_PACKAGE_NAME}${NC}"
else
    echo -e "${RED}  Error: Patch verification failed!${NC}"
    exit 1
fi
echo ""

# ──────────────────────────────────────────────
# Step 3: Download build-bootstrap.sh
# ──────────────────────────────────────────────
echo -e "${BLUE}[4/6] Setting up build-bootstrap.sh...${NC}"

BUILD_BOOTSTRAP_FILE="$TERMUX_PACKAGES_DIR/scripts/build-bootstrap.sh"

if [ -f "$BUILD_BOOTSTRAP_FILE" ]; then
    echo -e "${YELLOW}  build-bootstrap.sh already exists, skipping download.${NC}"
    echo "  Delete it manually if you want to re-download."
else
    echo "  Downloading build-bootstrap.sh from gist..."
    curl -sL "$BUILD_BOOTSTRAP_GIST" -o "$BUILD_BOOTSTRAP_FILE"
    if [ $? -eq 0 ] && [ -s "$BUILD_BOOTSTRAP_FILE" ]; then
        echo -e "${GREEN}  Downloaded successfully.${NC}"
    else
        echo -e "${RED}  Error: Failed to download build-bootstrap.sh${NC}"
        exit 1
    fi
fi
chmod +x "$BUILD_BOOTSTRAP_FILE"
echo ""

# ──────────────────────────────────────────────
# Step 4: Build inside Docker
# ──────────────────────────────────────────────
echo -e "${BLUE}[5/6] Building packages inside Docker...${NC}"
echo ""
echo -e "${YELLOW}  This will take a long time (30+ minutes per architecture).${NC}"
echo -e "${YELLOW}  Architectures: ${ARCHITECTURES}${NC}"
echo ""

# Build the docker command
DOCKER_BUILD_CMD="./scripts/run-docker.sh"
BOOTSTRAP_CMD="./scripts/build-bootstrap.sh --architectures ${ARCHITECTURES}"

if [ -n "$ADDITIONAL_PACKAGES" ]; then
    BOOTSTRAP_CMD="$BOOTSTRAP_CMD --add ${ADDITIONAL_PACKAGES}"
fi

if [ "$FORCE_BUILD" = "1" ]; then
    BOOTSTRAP_CMD="$BOOTSTRAP_CMD -f"
fi

cd "$TERMUX_PACKAGES_DIR"

echo -e "${CYAN}  Running Docker build...${NC}"
echo "  Command: $BOOTSTRAP_CMD"
echo ""

# Run Docker container and execute the bootstrap build
# The run-docker.sh script starts an interactive container.
# We pipe the build command into it.
docker run \
    --rm \
    -v "$TERMUX_PACKAGES_DIR:/home/builder/termux-packages" \
    termux/package-builder:latest \
    bash -c "cd /home/builder/termux-packages && $BOOTSTRAP_CMD"

BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -ne 0 ]; then
    echo ""
    echo -e "${RED}Error: Docker build failed with exit code ${BUILD_EXIT_CODE}.${NC}"
    echo ""
    echo "Troubleshooting tips:"
    echo "  1. Make sure Docker has enough memory (at least 4GB recommended)"
    echo "  2. Try building fewer architectures: ARCHITECTURES=aarch64 $0"
    echo "  3. Check Docker logs for more details"
    echo "  4. If the Docker image is missing, it will be pulled automatically"
    exit 1
fi

echo ""
echo -e "${GREEN}  Build completed successfully!${NC}"
echo ""

# ──────────────────────────────────────────────
# Step 5: Copy bootstrap zips to termux-app
# ──────────────────────────────────────────────
echo -e "${BLUE}[6/6] Copying bootstrap archives to termux-app...${NC}"

mkdir -p "$BOOTSTRAP_DEST"

COPIED=0
for arch in $(echo "$ARCHITECTURES" | tr ',' ' '); do
    BOOTSTRAP_FILE="$TERMUX_PACKAGES_DIR/bootstrap-${arch}.zip"
    if [ -f "$BOOTSTRAP_FILE" ]; then
        cp "$BOOTSTRAP_FILE" "$BOOTSTRAP_DEST/"
        SIZE=$(ls -lh "$BOOTSTRAP_FILE" | awk '{print $5}')
        echo -e "  ${GREEN}Copied bootstrap-${arch}.zip (${SIZE})${NC}"
        COPIED=$((COPIED + 1))
    else
        echo -e "  ${YELLOW}Warning: bootstrap-${arch}.zip not found, skipping.${NC}"
    fi
done

if [ $COPIED -eq 0 ]; then
    echo -e "${RED}Error: No bootstrap archives were generated!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Build completed successfully!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Bootstrap archives are in: $BOOTSTRAP_DEST/"
echo ""
echo "Next steps:"
echo "  1. Clean your termux-app project:"
echo "     cd $TERMUX_APP_DIR && ./gradlew clean"
echo ""
echo "  2. Build the APK:"
echo "     ./build.sh"
echo ""
echo "  Or build everything at once:"
echo "     cd $SCRIPT_DIR && ./build.sh"
echo ""

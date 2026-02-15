#!/bin/bash

##
## Build APT repository from compiled .deb packages
##
## Creates a deployable APT repository structure at repos/apt/ that can be
## uploaded to packages.pepebot.space/repos/apt
##
## Requirements:
##   - Docker (running) OR dpkg-scanpackages installed locally
##   - .deb files in termux-packages/output/
##
## Usage:
##   ./build-repo.sh                           # Build repo for all arch
##   ./build-repo.sh --arch aarch64            # Specific architecture
##   ./build-repo.sh --sign                    # Sign with GPG (optional)
##   ./build-repo.sh --output /path/to/dir     # Custom output directory
##

set -e

# ─── Configuration ────────────────────────────────────────────────────
REPO_URL="https://packages.pepebot.space/repos/apt"
REPO_NAME="pepebot-main"
REPO_LABEL="Pepebot Terminal Repository"
REPO_CODENAME="stable"
REPO_COMPONENT="main"
REPO_DESCRIPTION="Pepebot Terminal packages for com.pepebot.terminal"
ARCHITECTURES="aarch64,arm,i686,x86_64"
SIGN_REPO=false
OUTPUT_DIR=""
CONTAINER_NAME="termux-package-builder"

# ─── Paths ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERMUX_PACKAGES_DIR="$SCRIPT_DIR/termux-packages"
DEFAULT_OUTPUT_DIR="$SCRIPT_DIR/repos/apt"

# ─── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Parse Arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch|--architectures)
            ARCHITECTURES="$2"
            shift 2
            ;;
        --sign)
            SIGN_REPO=true
            shift
            ;;
        --output|-o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            head -18 "$0" | grep "^##" | sed 's/^## \?//'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

REPO_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
DEB_SOURCE_DIR="$TERMUX_PACKAGES_DIR/output"

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  APT Repository Builder${NC}"
echo -e "${CYAN}  URL:  ${GREEN}${REPO_URL}${NC}"
echo -e "${CYAN}  Arch: ${GREEN}${ARCHITECTURES}${NC}"
echo -e "${CYAN}  Out:  ${GREEN}${REPO_DIR}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

# ─── Step 1: Check source debs ───────────────────────────────────────
echo -e "${BLUE}[1/4] Checking source .deb files...${NC}"

if [ ! -d "$DEB_SOURCE_DIR" ]; then
    echo -e "${RED}Error: $DEB_SOURCE_DIR not found.${NC}"
    echo "  Run ./build-bootstrap.sh first to build packages."
    exit 1
fi

DEB_COUNT=$(find "$DEB_SOURCE_DIR" -name "*.deb" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$DEB_COUNT" -eq 0 ]; then
    echo -e "${RED}Error: No .deb files found in $DEB_SOURCE_DIR${NC}"
    echo "  Run ./build-bootstrap.sh first to build packages."
    exit 1
fi

echo -e "${GREEN}  Found $DEB_COUNT .deb files.${NC}"
echo ""

# ─── Step 2: Create repository structure ─────────────────────────────
echo -e "${BLUE}[2/4] Creating repository structure...${NC}"

# Clean and create directory structure
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR/pool/$REPO_COMPONENT"

IFS=',' read -ra ARCH_LIST <<< "$ARCHITECTURES"

for arch in "${ARCH_LIST[@]}"; do
    mkdir -p "$REPO_DIR/dists/$REPO_CODENAME/$REPO_COMPONENT/binary-$arch"
done

# Copy and organize .deb files into pool
echo "  Organizing .deb files into pool..."
POOL_COUNT=0
for deb in "$DEB_SOURCE_DIR"/*.deb; do
    [ -f "$deb" ] || continue

    filename=$(basename "$deb")
    # Extract package name: everything before the first underscore
    pkg_name=$(echo "$filename" | sed -E 's/^([^_]+)_.*/\1/')
    # First letter for directory grouping
    first_letter=$(echo "$pkg_name" | cut -c1)

    # Detect architecture from filename
    deb_arch=$(echo "$filename" | sed -E 's/.*_([^_]+)\.deb$/\1/')

    # Create pool path: pool/main/{first_letter}/{package_name}/
    pool_path="$REPO_DIR/pool/$REPO_COMPONENT/$first_letter/$pkg_name"
    mkdir -p "$pool_path"
    cp "$deb" "$pool_path/"
    POOL_COUNT=$((POOL_COUNT + 1))
done

echo -e "${GREEN}  Organized $POOL_COUNT packages into pool.${NC}"
echo ""

# ─── Step 3: Generate Packages and Release files ─────────────────────
echo -e "${BLUE}[3/4] Generating repository metadata...${NC}"

# Write the metadata generation script to a file (avoids quoting issues)
cat > "$SCRIPT_DIR/termux-packages/_generate-repo-metadata.sh" << 'REPO_SCRIPT_EOF'
#!/bin/bash
set -e

REPO_DIR="$1"
CODENAME="$2"
COMPONENT="$3"
ARCHITECTURES="$4"
LABEL="$5"
DESCRIPTION="$6"

cd "$REPO_DIR"

IFS=',' read -ra ARCH_LIST <<< "$ARCHITECTURES"

# Generate Packages file for each architecture
for arch in "${ARCH_LIST[@]}"; do
    echo "[*] Generating Packages for $arch..."

    PACKAGES_FILE="dists/$CODENAME/$COMPONENT/binary-$arch/Packages"

    # Clear file
    > "$PACKAGES_FILE"

    # Scan all debs matching this architecture
    for deb in $(find pool/ -name "*_${arch}.deb" -type f | sort); do
        [ -f "$deb" ] || continue

        # Extract control information
        tmpdir=$(mktemp -d)
        (cd "$tmpdir" && ar x "$REPO_DIR/$deb" control.tar.xz control.tar.gz control.tar.zst 2>/dev/null || true)

        control_archive=""
        if [ -f "$tmpdir/control.tar.xz" ]; then
            control_archive="$tmpdir/control.tar.xz"
        elif [ -f "$tmpdir/control.tar.gz" ]; then
            control_archive="$tmpdir/control.tar.gz"
        elif [ -f "$tmpdir/control.tar.zst" ]; then
            control_archive="$tmpdir/control.tar.zst"
        fi

        if [ -z "$control_archive" ]; then
            rm -rf "$tmpdir"
            continue
        fi

        tar xf "$control_archive" -C "$tmpdir" ./control 2>/dev/null || tar xf "$control_archive" -C "$tmpdir" control 2>/dev/null || true

        if [ -f "$tmpdir/control" ]; then
            cat "$tmpdir/control" >> "$PACKAGES_FILE"
        fi

        # Add Filename, Size, MD5sum, SHA256
        filesize=$(stat -c%s "$deb" 2>/dev/null || stat -f%z "$deb" 2>/dev/null)
        md5=$(md5sum "$deb" 2>/dev/null | awk '{print $1}' || md5 -q "$deb" 2>/dev/null)
        sha256=$(sha256sum "$deb" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$deb" 2>/dev/null | awk '{print $1}')

        echo "Filename: $deb" >> "$PACKAGES_FILE"
        echo "Size: $filesize" >> "$PACKAGES_FILE"
        echo "MD5sum: $md5" >> "$PACKAGES_FILE"
        echo "SHA256: $sha256" >> "$PACKAGES_FILE"
        echo "" >> "$PACKAGES_FILE"

        rm -rf "$tmpdir"
    done

    # Also include architecture-independent packages (all)
    for deb in $(find pool/ -name "*_all.deb" -type f | sort); do
        [ -f "$deb" ] || continue

        tmpdir=$(mktemp -d)
        (cd "$tmpdir" && ar x "$REPO_DIR/$deb" control.tar.xz control.tar.gz control.tar.zst 2>/dev/null || true)

        control_archive=""
        if [ -f "$tmpdir/control.tar.xz" ]; then
            control_archive="$tmpdir/control.tar.xz"
        elif [ -f "$tmpdir/control.tar.gz" ]; then
            control_archive="$tmpdir/control.tar.gz"
        elif [ -f "$tmpdir/control.tar.zst" ]; then
            control_archive="$tmpdir/control.tar.zst"
        fi

        if [ -z "$control_archive" ]; then
            rm -rf "$tmpdir"
            continue
        fi

        tar xf "$control_archive" -C "$tmpdir" ./control 2>/dev/null || tar xf "$control_archive" -C "$tmpdir" control 2>/dev/null || true

        if [ -f "$tmpdir/control" ]; then
            cat "$tmpdir/control" >> "$PACKAGES_FILE"
        fi

        filesize=$(stat -c%s "$deb" 2>/dev/null || stat -f%z "$deb" 2>/dev/null)
        md5=$(md5sum "$deb" 2>/dev/null | awk '{print $1}' || md5 -q "$deb" 2>/dev/null)
        sha256=$(sha256sum "$deb" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$deb" 2>/dev/null | awk '{print $1}')

        echo "Filename: $deb" >> "$PACKAGES_FILE"
        echo "Size: $filesize" >> "$PACKAGES_FILE"
        echo "MD5sum: $md5" >> "$PACKAGES_FILE"
        echo "SHA256: $sha256" >> "$PACKAGES_FILE"
        echo "" >> "$PACKAGES_FILE"

        rm -rf "$tmpdir"
    done

    # Compress
    gzip -9 -k "$PACKAGES_FILE"

    pkg_count=$(grep -c "^Package:" "$PACKAGES_FILE" 2>/dev/null || echo 0)
    echo "    $arch: $pkg_count packages"
done

# Generate Release file
echo "[*] Generating Release file..."
RELEASE_FILE="dists/$CODENAME/Release"

ARCH_STRING=$(echo "${ARCH_LIST[*]}" | tr ' ' ' ')

cat > "$RELEASE_FILE" << RELEASE_EOF
Origin: $LABEL
Label: $LABEL
Suite: $CODENAME
Codename: $CODENAME
Version: 1.0
Architectures: $ARCH_STRING
Components: $COMPONENT
Description: $DESCRIPTION
Date: $(date -Ru 2>/dev/null || date -u +"%a, %d %b %Y %H:%M:%S %z")
RELEASE_EOF

# Add checksums to Release
echo "MD5Sum:" >> "$RELEASE_FILE"
for arch in "${ARCH_LIST[@]}"; do
    for f in "dists/$CODENAME/$COMPONENT/binary-$arch/Packages" \
             "dists/$CODENAME/$COMPONENT/binary-$arch/Packages.gz"; do
        if [ -f "$f" ]; then
            size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)
            md5=$(md5sum "$f" 2>/dev/null | awk '{print $1}' || md5 -q "$f" 2>/dev/null)
            rel_path="${f#dists/$CODENAME/}"
            printf " %s %16s %s\n" "$md5" "$size" "$rel_path" >> "$RELEASE_FILE"
        fi
    done
done

echo "SHA256:" >> "$RELEASE_FILE"
for arch in "${ARCH_LIST[@]}"; do
    for f in "dists/$CODENAME/$COMPONENT/binary-$arch/Packages" \
             "dists/$CODENAME/$COMPONENT/binary-$arch/Packages.gz"; do
        if [ -f "$f" ]; then
            size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)
            sha256=$(sha256sum "$f" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$f" 2>/dev/null | awk '{print $1}')
            rel_path="${f#dists/$CODENAME/}"
            printf " %s %16s %s\n" "$sha256" "$size" "$rel_path" >> "$RELEASE_FILE"
        fi
    done
done

echo "[*] Repository metadata generated."
REPO_SCRIPT_EOF

chmod +x "$SCRIPT_DIR/termux-packages/_generate-repo-metadata.sh"

# Check if we should run inside Docker or locally
USE_DOCKER=false
if ! command -v ar &>/dev/null; then
    USE_DOCKER=true
fi

if [ "$USE_DOCKER" = true ]; then
    echo "  Running metadata generation inside Docker..."

    # Copy repo dir into the volume mount so Docker can access it
    DOCKER_REPO_DIR="/home/builder/termux-packages/_repo_output"
    docker exec "$CONTAINER_NAME" bash -c "rm -rf $DOCKER_REPO_DIR"
    docker exec "$CONTAINER_NAME" bash -c "mkdir -p $DOCKER_REPO_DIR"

    # We need to copy the repo structure into the container
    # Since termux-packages is mounted, we can use it as a staging area
    STAGING_DIR="$TERMUX_PACKAGES_DIR/_repo_output"
    rm -rf "$STAGING_DIR"
    cp -r "$REPO_DIR" "$STAGING_DIR"

    docker exec "$CONTAINER_NAME" bash -c \
        "cd /home/builder/termux-packages && bash _generate-repo-metadata.sh \
        '$DOCKER_REPO_DIR' '$REPO_CODENAME' '$REPO_COMPONENT' '$ARCHITECTURES' \
        '$REPO_LABEL' '$REPO_DESCRIPTION'"

    # Copy back
    rm -rf "$REPO_DIR"
    cp -r "$STAGING_DIR" "$REPO_DIR"
    rm -rf "$STAGING_DIR"
else
    echo "  Running metadata generation locally..."
    bash "$SCRIPT_DIR/termux-packages/_generate-repo-metadata.sh" \
        "$REPO_DIR" "$REPO_CODENAME" "$REPO_COMPONENT" "$ARCHITECTURES" \
        "$REPO_LABEL" "$REPO_DESCRIPTION"
fi

echo -e "${GREEN}  Metadata generated.${NC}"
echo ""

# ─── Step 4: GPG signing (optional) ──────────────────────────────────
if [ "$SIGN_REPO" = true ]; then
    echo -e "${BLUE}[4/4] Signing repository with GPG...${NC}"
    RELEASE_FILE="$REPO_DIR/dists/$REPO_CODENAME/Release"

    if command -v gpg &>/dev/null; then
        gpg --armor --detach-sign --output "$RELEASE_FILE.gpg" "$RELEASE_FILE"
        gpg --armor --clearsign --output "${RELEASE_FILE%Release}InRelease" "$RELEASE_FILE"
        echo -e "${GREEN}  Repository signed.${NC}"
        echo ""
        echo -e "${YELLOW}  Don't forget to export your public key:${NC}"
        echo "    gpg --armor --export your@email.com > pepebot-repo.gpg"
        echo "    # Then include it in the bootstrap at \$PREFIX/etc/apt/trusted.gpg.d/"
    else
        echo -e "${YELLOW}  GPG not found. Skipping signing.${NC}"
        echo "  The repo will work with [trusted=yes] in sources.list"
    fi
else
    echo -e "${BLUE}[4/4] Skipping GPG signing (use --sign to enable).${NC}"
    echo -e "${YELLOW}  Using [trusted=yes] in sources.list for unsigned repo.${NC}"
fi

echo ""

# ─── Summary ─────────────────────────────────────────────────────────
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  APT Repository built successfully!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo "Repository directory: $REPO_DIR"
echo ""
echo "Structure:"
echo "  $REPO_DIR/"
echo "  ├── dists/$REPO_CODENAME/"
echo "  │   ├── Release"
for arch in "${ARCH_LIST[@]}"; do
    echo "  │   └── $REPO_COMPONENT/binary-$arch/"
    echo "  │       ├── Packages"
    echo "  │       └── Packages.gz"
done
echo "  └── pool/$REPO_COMPONENT/..."
echo ""
echo "Deploy this directory to your web server:"
echo "  rsync -avz $REPO_DIR/ user@packages.pepebot.space:/var/www/repos/apt/"
echo ""
echo "Or with any static file host (nginx, caddy, S3, etc)."
echo ""
echo "sources.list entry (already configured in bootstrap):"
if [ "$SIGN_REPO" = true ]; then
    echo "  deb $REPO_URL $REPO_CODENAME $REPO_COMPONENT"
else
    echo "  deb [trusted=yes] $REPO_URL $REPO_CODENAME $REPO_COMPONENT"
fi
echo ""

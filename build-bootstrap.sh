#!/bin/bash

##
## Build Termux bootstrap packages with custom package ID: com.pepebot.terminal
##
## Based on official docs: https://github.com/termux/termux-packages/wiki/Building-packages
##
## Requirements:
##   - Docker (running)
##   - git, curl
##
## Usage:
##   ./build-bootstrap.sh                              # Build all architectures
##   ./build-bootstrap.sh --arch aarch64               # Build single architecture
##   ./build-bootstrap.sh --arch aarch64,x86_64        # Build multiple architectures
##   ./build-bootstrap.sh --add vim,git,openssh         # Add extra packages
##   ./build-bootstrap.sh --force                       # Force rebuild all
##   ./build-bootstrap.sh --clean                       # Clean and start fresh
##   ./build-bootstrap.sh --shell                       # Open shell in container
##

set -e

# ─── Configuration ────────────────────────────────────────────────────
CUSTOM_PACKAGE_NAME="com.pepebot.terminal"
ARCHITECTURES="aarch64,arm,i686,x86_64"
ADDITIONAL_PACKAGES=""
FORCE_BUILD=false
CLEAN_BUILD=false
OPEN_SHELL=false
CONTAINER_NAME="termux-package-builder"
DOCKER_IMAGE="ghcr.io/termux/package-builder"

# ─── Paths ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERMUX_PACKAGES_DIR="$SCRIPT_DIR/termux-packages"
TERMUX_APP_DIR="$SCRIPT_DIR/termux-app"
BOOTSTRAP_DEST="$TERMUX_APP_DIR/app/src/main/cpp"

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
        --add)
            ADDITIONAL_PACKAGES="$2"
            shift 2
            ;;
        --force|-f)
            FORCE_BUILD=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --shell)
            OPEN_SHELL=true
            shift
            ;;
        --help|-h)
            head -20 "$0" | grep "^##" | sed 's/^## \?//'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Termux Bootstrap Builder${NC}"
echo -e "${CYAN}  Package: ${GREEN}${CUSTOM_PACKAGE_NAME}${NC}"
echo -e "${CYAN}  Arch:    ${GREEN}${ARCHITECTURES}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

# ─── Step 1: Prerequisites ───────────────────────────────────────────
echo -e "${BLUE}[1/6] Checking prerequisites...${NC}"

for cmd in docker git curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Error: '$cmd' is not installed.${NC}"
        exit 1
    fi
done

if ! docker info &>/dev/null; then
    echo -e "${RED}Error: Docker daemon is not running. Please start Docker.${NC}"
    exit 1
fi

echo -e "${GREEN}  OK${NC}"
echo ""

# ─── Step 2: Clone termux-packages ───────────────────────────────────
echo -e "${BLUE}[2/6] Preparing termux-packages repository...${NC}"

if [ "$CLEAN_BUILD" = true ] && [ -d "$TERMUX_PACKAGES_DIR" ]; then
    echo -e "${YELLOW}  Removing existing termux-packages (--clean)...${NC}"
    rm -rf "$TERMUX_PACKAGES_DIR"
fi

if [ ! -d "$TERMUX_PACKAGES_DIR" ]; then
    echo "  Cloning termux-packages..."
    git clone https://github.com/termux/termux-packages.git "$TERMUX_PACKAGES_DIR"
    echo -e "${GREEN}  Cloned.${NC}"
else
    echo "  Already exists. Skipping clone."
fi
echo ""

# ─── Step 3: Patch properties.sh ─────────────────────────────────────
echo -e "${BLUE}[3/6] Patching properties.sh -> ${CUSTOM_PACKAGE_NAME}...${NC}"

PROPERTIES_FILE="$TERMUX_PACKAGES_DIR/scripts/properties.sh"

if [ ! -f "$PROPERTIES_FILE" ]; then
    echo -e "${RED}Error: $PROPERTIES_FILE not found.${NC}"
    exit 1
fi

# Create backup
if [ ! -f "$PROPERTIES_FILE.orig" ]; then
    cp "$PROPERTIES_FILE" "$PROPERTIES_FILE.orig"
fi

# Patch: replace com.termux with custom package name
sed -i.bak \
    -e 's|TERMUX_APP__PACKAGE_NAME="com\.termux"|TERMUX_APP__PACKAGE_NAME="'"$CUSTOM_PACKAGE_NAME"'"|g' \
    "$PROPERTIES_FILE"

# Verify
if grep -q "TERMUX_APP__PACKAGE_NAME=\"${CUSTOM_PACKAGE_NAME}\"" "$PROPERTIES_FILE"; then
    echo -e "${GREEN}  Patched: TERMUX_APP__PACKAGE_NAME=\"${CUSTOM_PACKAGE_NAME}\"${NC}"
else
    echo -e "${RED}  Error: Failed to patch properties.sh${NC}"
    echo "  You may need to manually set TERMUX_APP__PACKAGE_NAME in:"
    echo "  $PROPERTIES_FILE"
    exit 1
fi

echo "  Derived paths:"
echo "    Data dir: /data/data/${CUSTOM_PACKAGE_NAME}"
echo "    Prefix:   /data/data/${CUSTOM_PACKAGE_NAME}/files/usr"
echo ""

# ─── Step 3b: Write bootstrap assembler script ───────────────────────
# Write as a separate file to avoid nested quoting issues with docker exec
cat > "$TERMUX_PACKAGES_DIR/scripts/assemble-bootstrap.sh" << 'ASSEMBLE_EOF'
#!/bin/bash
##
## Assemble bootstrap zip from built .deb files in output/
## Usage: ./scripts/assemble-bootstrap.sh <architecture>
##
set -e

ARCH="$1"
if [ -z "$ARCH" ]; then
    echo "Usage: $0 <architecture>"
    exit 1
fi

cd /home/builder/termux-packages

# Source properties to get TERMUX_PREFIX
export TERMUX_SCRIPTDIR=/home/builder/termux-packages
. scripts/properties.sh

echo "[*] Assembling bootstrap for $ARCH (prefix: $TERMUX_PREFIX)"

TMPDIR_BOOTSTRAP=$(mktemp -d /tmp/bootstrap-XXXXXX)
trap 'rm -rf "$TMPDIR_BOOTSTRAP"' EXIT

ROOTFS="$TMPDIR_BOOTSTRAP/rootfs"
PKGDIR="$TMPDIR_BOOTSTRAP/packages"

# Create dpkg directory structure
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/etc/apt/apt.conf.d"
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/etc/apt/preferences.d"
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info"
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/triggers"
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/updates"
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/var/log/apt"
touch "${ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/available"
touch "${ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/status"
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/tmp"

declare -A EXTRACTED

cd output
if ! ls *.deb 1>/dev/null 2>&1; then
    echo "[!] No .deb files found in output/"
    exit 1
fi

echo "[*] Found $(ls *.deb | wc -l) deb files"

for deb in *.deb; do
    pkg_name="$(echo "$deb" | sed -E 's/^([^_]+).*/\1/')"

    # Skip static packages
    [[ "$pkg_name" == *"-static" ]] && continue

    # Skip already extracted
    if [ -n "${EXTRACTED[$pkg_name]+x}" ]; then
        continue
    fi
    EXTRACTED[$pkg_name]=1

    echo "[*] Extracting $deb..."
    pkg_tmp="$PKGDIR/$pkg_name"
    mkdir -p "$pkg_tmp"

    (cd "$pkg_tmp"
        ar x "/home/builder/termux-packages/output/$deb"

        # Find data archive
        if [ -f data.tar.xz ]; then
            data_archive=data.tar.xz
        elif [ -f data.tar.gz ]; then
            data_archive=data.tar.gz
        elif [ -f data.tar.zst ]; then
            data_archive=data.tar.zst
        else
            echo "    No data archive in $deb, skipping"
            exit 0
        fi

        # Find control archive
        if [ -f control.tar.xz ]; then
            control_archive=control.tar.xz
        elif [ -f control.tar.gz ]; then
            control_archive=control.tar.gz
        elif [ -f control.tar.zst ]; then
            control_archive=control.tar.zst
        else
            echo "    No control archive in $deb, skipping"
            exit 0
        fi

        # Extract data files to rootfs
        tar xf "$data_archive" -C "$ROOTFS"

        # Register file list for dpkg
        tar tf "$data_archive" | sed -E \
            -e 's@^\./@/@' \
            -e 's@^/$@/.@' \
            -e 's@^([^./])@/\1@' \
            > "${ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info/${pkg_name}.list"

        # Generate md5sums
        tar xf "$data_archive"
        find data -type f -print0 | xargs -0 -r md5sum | sed 's@^\.@@g' \
            > "${ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info/${pkg_name}.md5sums"

        # Extract control and register package status
        tar xf "$control_archive"
        {
            cat control
            echo "Status: install ok installed"
            echo
        } >> "${ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/status"

        # Copy maintainer scripts
        for file in conffiles postinst postrm preinst prerm; do
            if [ -f "$file" ]; then
                cp "$file" "${ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info/${pkg_name}.${file}"
            fi
        done
    )
done

# Configure APT sources.list to point to custom repository
echo "[*] Configuring APT sources.list..."
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/etc/apt"

# Write custom sources.list pointing to packages.pepebot.space
cat > "${ROOTFS}/${TERMUX_PREFIX}/etc/apt/sources.list" << 'SOURCES_EOF'
# Pepebot Terminal repository
deb [trusted=yes] https://packages.pepebot.space/repos/apt stable main
SOURCES_EOF

# Also create sources.list.d directory for additional repos
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/etc/apt/sources.list.d"

# Configure apt to allow unsigned repo (since we use [trusted=yes])
mkdir -p "${ROOTFS}/${TERMUX_PREFIX}/etc/apt/apt.conf.d"
cat > "${ROOTFS}/${TERMUX_PREFIX}/etc/apt/apt.conf.d/99pepebot" << 'APT_CONF_EOF'
Acquire::AllowInsecureRepositories "true";
APT_CONF_EOF

# Create bootstrap zip
echo "[*] Creating bootstrap-${ARCH}.zip..."
(cd "${ROOTFS}/${TERMUX_PREFIX}"
    # Replace symlinks with SYMLINKS.txt entries
    while read -r -d '' link; do
        echo "$(readlink "$link")←${link}" >> SYMLINKS.txt
        rm -f "$link"
    done < <(find . -type l -print0)

    zip -r9 "/home/builder/termux-packages/bootstrap-${ARCH}.zip" ./*
)

echo "[*] Finished successfully (${ARCH})."
ASSEMBLE_EOF

chmod +x "$TERMUX_PACKAGES_DIR/scripts/assemble-bootstrap.sh"
echo -e "${GREEN}  Created scripts/assemble-bootstrap.sh${NC}"
echo ""

# ─── Step 4: Setup Docker Container ──────────────────────────────────
echo -e "${BLUE}[4/6] Setting up Docker container...${NC}"

# Clean up old container if doing clean build
if [ "$CLEAN_BUILD" = true ]; then
    echo "  Removing old container (--clean)..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
fi

# Determine volume mount
UNAME=$(uname)
if [ "$UNAME" = "Darwin" ]; then
    VOLUME="$TERMUX_PACKAGES_DIR:/home/builder/termux-packages"
    SEC_OPT=""
else
    VOLUME="$TERMUX_PACKAGES_DIR:/home/builder/termux-packages"
    if [ -f "$TERMUX_PACKAGES_DIR/scripts/profile.json" ]; then
        SEC_OPT="--security-opt seccomp=$TERMUX_PACKAGES_DIR/scripts/profile.json"
    else
        SEC_OPT=""
    fi
fi

# Start or create container
if docker start "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo -e "${GREEN}  Started existing container '$CONTAINER_NAME'.${NC}"
else
    echo "  Creating new container '$CONTAINER_NAME'..."
    echo "  Image: $DOCKER_IMAGE"
    docker run \
        --detach \
        --init \
        --name "$CONTAINER_NAME" \
        --volume "$VOLUME" \
        $SEC_OPT \
        --tty \
        "$DOCKER_IMAGE"
    echo -e "${GREEN}  Container created.${NC}"
fi
echo ""

# ─── Step 5: Open shell OR build ─────────────────────────────────────
if [ "$OPEN_SHELL" = true ]; then
    echo -e "${BLUE}Opening shell in container...${NC}"
    echo -e "${YELLOW}  Working directory: /home/builder/termux-packages${NC}"
    echo ""
    echo "  Useful commands:"
    echo "    ./build-package.sh -a aarch64 <package>     # Build a single package"
    echo "    ./scripts/assemble-bootstrap.sh aarch64     # Assemble bootstrap"
    echo "    exit                                         # Exit container"
    echo ""
    docker exec -it "$CONTAINER_NAME" bash
    exit 0
fi

echo -e "${BLUE}[5/6] Building packages inside Docker...${NC}"
echo ""
echo -e "${YELLOW}  This will take a LONG time (30+ minutes per architecture).${NC}"
echo -e "${YELLOW}  All packages are compiled from source (custom package name${NC}"
echo -e "${YELLOW}  cannot use the official APT repo).${NC}"
echo ""

# Build the list of base packages (same order as generate-bootstraps.sh)
# NOTE: bzip2, curl, xz-utils are subpackages, so we build their parent:
#   bzip2    -> libbz2    (bzip2.subpackage.sh)
#   curl     -> libcurl   (curl.subpackage.sh)
#   xz-utils -> liblzma   (xz-utils.subpackage.sh)
BASE_PACKAGES=(
    apt
    bash
    libbz2
    command-not-found
    coreutils
    libcurl
    dash
    diffutils
    findutils
    gawk
    grep
    gzip
    less
    procps
    psmisc
    sed
    tar
    termux-core
    termux-exec
    termux-keyring
    termux-tools
    util-linux
    liblzma
    ed
    debianutils
    dos2unix
    inetutils
    lsof
    nano
    net-tools
    patch
    unzip
)

# Add additional packages
if [ -n "$ADDITIONAL_PACKAGES" ]; then
    IFS=',' read -ra EXTRA_PKGS <<< "$ADDITIONAL_PACKAGES"
    BASE_PACKAGES+=("${EXTRA_PKGS[@]}")
    echo -e "${CYAN}  Extra packages: ${ADDITIONAL_PACKAGES}${NC}"
fi

TOTAL_PACKAGES=${#BASE_PACKAGES[@]}
echo -e "${CYAN}  Total packages to build: ${TOTAL_PACKAGES}${NC}"
echo ""

# Build for each architecture
IFS=',' read -ra ARCH_LIST <<< "$ARCHITECTURES"

for arch in "${ARCH_LIST[@]}"; do
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Building for architecture: ${arch}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    FORCE_FLAG=""
    if [ "$FORCE_BUILD" = true ]; then
        FORCE_FLAG="-f"
    fi

    # Clear output directory for this arch to avoid mixing
    docker exec "$CONTAINER_NAME" bash -c "rm -rf /home/builder/termux-packages/output/*.deb"

    # Build each package (build-package.sh handles dependencies automatically)
    COUNT=0
    FAILED_PACKAGES=()
    for pkg in "${BASE_PACKAGES[@]}"; do
        COUNT=$((COUNT + 1))
        echo -e "${BLUE}  [${COUNT}/${TOTAL_PACKAGES}] Building '${pkg}' for ${arch}...${NC}"

        set +e
        docker exec "$CONTAINER_NAME" bash -c \
            "cd /home/builder/termux-packages && ./build-package.sh ${FORCE_FLAG} -a ${arch} ${pkg}"
        BUILD_RC=$?
        set -e

        if [ $BUILD_RC -eq 0 ]; then
            echo -e "${GREEN}  OK: ${pkg}${NC}"
        else
            echo -e "${YELLOW}  WARN: Failed to build '${pkg}' (exit code: ${BUILD_RC}), continuing...${NC}"
            FAILED_PACKAGES+=("$pkg")
        fi
        echo ""
    done

    # Report failed packages
    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        echo -e "${YELLOW}  Failed packages for ${arch}: ${FAILED_PACKAGES[*]}${NC}"
        echo ""

        # Retry failed packages once (dependency might have been built by now)
        echo -e "${BLUE}  Retrying failed packages...${NC}"
        STILL_FAILED=()
        for pkg in "${FAILED_PACKAGES[@]}"; do
            echo -e "${BLUE}  Retrying '${pkg}'...${NC}"
            set +e
            docker exec "$CONTAINER_NAME" bash -c \
                "cd /home/builder/termux-packages && ./build-package.sh ${FORCE_FLAG} -a ${arch} ${pkg}"
            RETRY_RC=$?
            set -e
            if [ $RETRY_RC -eq 0 ]; then
                echo -e "${GREEN}  OK: ${pkg} (retry succeeded)${NC}"
            else
                echo -e "${RED}  FAIL: ${pkg}${NC}"
                STILL_FAILED+=("$pkg")
            fi
        done

        if [ ${#STILL_FAILED[@]} -gt 0 ]; then
            echo -e "${RED}  Still failed after retry: ${STILL_FAILED[*]}${NC}"
        fi
        echo ""
    fi

    # Assemble bootstrap archive using the separate script (avoids quoting issues)
    echo -e "${BLUE}  Assembling bootstrap-${arch}.zip...${NC}"

    set +e
    docker exec "$CONTAINER_NAME" bash -c \
        "cd /home/builder/termux-packages && bash scripts/assemble-bootstrap.sh ${arch}"
    ASSEMBLE_RC=$?
    set -e

    if [ $ASSEMBLE_RC -eq 0 ] && [ -f "$TERMUX_PACKAGES_DIR/bootstrap-${arch}.zip" ]; then
        SIZE=$(ls -lh "$TERMUX_PACKAGES_DIR/bootstrap-${arch}.zip" | awk '{print $5}')
        echo -e "${GREEN}  bootstrap-${arch}.zip created (${SIZE})${NC}"
    else
        echo -e "${RED}  Error: bootstrap-${arch}.zip was not created!${NC}"
    fi
    echo ""
done

# ─── Step 6: Copy to termux-app ──────────────────────────────────────
echo -e "${BLUE}[6/6] Copying bootstrap archives to termux-app...${NC}"

mkdir -p "$BOOTSTRAP_DEST"

COPIED=0
for arch in "${ARCH_LIST[@]}"; do
    SRC="$TERMUX_PACKAGES_DIR/bootstrap-${arch}.zip"
    if [ -f "$SRC" ]; then
        cp "$SRC" "$BOOTSTRAP_DEST/"
        SIZE=$(ls -lh "$SRC" | awk '{print $5}')
        echo -e "  ${GREEN}bootstrap-${arch}.zip -> termux-app/app/src/main/cpp/ (${SIZE})${NC}"
        COPIED=$((COPIED + 1))
    else
        echo -e "  ${YELLOW}bootstrap-${arch}.zip not found, skipped.${NC}"
    fi
done

echo ""
if [ $COPIED -gt 0 ]; then
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Build completed! ${COPIED} bootstrap archive(s) copied.${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
    echo ""
    echo "Next: run ./build.sh to build the APK."
    echo ""
    echo "Tip: to open a shell in the build container:"
    echo "  ./build-bootstrap.sh --shell"
else
    echo -e "${RED}No bootstrap archives were created.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Open a shell:  ./build-bootstrap.sh --shell"
    echo "  2. Try building a single package manually:"
    echo "     ./build-package.sh -a aarch64 bash"
    echo "  3. Check output/ directory for .deb files"
    exit 1
fi

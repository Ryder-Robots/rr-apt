#!/bin/bash
set -e

# Configuration
APT_REPO_PATH="$HOME/ws/rr-apt"
UBUNTU_CODENAME=$(grep DISTRIB_CODENAME /etc/lsb-release | cut -d= -f2)
CMAKE_INSTALL_PREFIX="/usr"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <package-source-dir>"
    echo ""
    echo "Arguments:"
    echo "  package-source-dir  Path to the CMake/CPack package source directory"
    echo ""
    echo "Version is extracted from CMakeLists.txt automatically."
    echo "A GitHub release is created before building the debian package."
    echo "The package is installed to ${CMAKE_INSTALL_PREFIX} (Debian standard)."
    echo ""
    echo "Example:"
    echo "  $0 ~/ws/rr-bno055"
    exit 1
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [ -z "$1" ]; then
    usage
fi

PACKAGE_DIR="$(realpath "$1")"

# Validate package directory
if [ ! -f "$PACKAGE_DIR/CMakeLists.txt" ]; then
    log_error "No CMakeLists.txt found in $PACKAGE_DIR"
    exit 1
fi

# Extract version from CMakeLists.txt (project VERSION field)
VERSION=$(grep -oP '(?<=VERSION\s)[0-9]+\.[0-9]+\.[0-9]+' "$PACKAGE_DIR/CMakeLists.txt" | head -1)

if [ -z "$VERSION" ]; then
    log_error "Could not extract VERSION from CMakeLists.txt"
    exit 1
fi

# Extract CPack debian package name
DEB_NAME=$(grep -oP 'CPACK_PACKAGE_NAME\s+"?\K[a-zA-Z0-9_-]+' "$PACKAGE_DIR/CMakeLists.txt" | head -1)

if [ -z "$DEB_NAME" ]; then
    log_error "Could not extract CPACK_PACKAGE_NAME from CMakeLists.txt"
    exit 1
fi

# Extract debian architecture (fall back to system arch if not set in CMakeLists.txt)
DEB_ARCH=$(grep -oP 'CPACK_DEBIAN_PACKAGE_ARCHITECTURE\s+"?\K[a-zA-Z0-9_-]+' "$PACKAGE_DIR/CMakeLists.txt" | head -1)
if [ -z "$DEB_ARCH" ]; then
    DEB_ARCH=$(dpkg --print-architecture)
fi

TAG_NAME="v${VERSION}"

log_info "Package name: $DEB_NAME"
log_info "Version: $VERSION"
log_info "Architecture: $DEB_ARCH"
log_info "Install prefix: $CMAKE_INSTALL_PREFIX"

# Create GitHub release before building
log_info "Creating GitHub release ${TAG_NAME}..."
cd "$PACKAGE_DIR"

# Check if we're in a git repository
if [ ! -d ".git" ] && ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_error "Not a git repository: $PACKAGE_DIR"
    exit 1
fi

# Check if tag already exists
if git tag -l | grep -q "^${TAG_NAME}$"; then
    log_warn "Tag ${TAG_NAME} already exists, skipping release creation"
else
    log_info "Creating tag ${TAG_NAME}..."
    git tag -a "${TAG_NAME}" -m "Release ${VERSION}"
    git push origin "${TAG_NAME}"

    log_info "Creating GitHub release..."
    if ! gh release create "${TAG_NAME}" \
        --title "Release ${VERSION}" \
        --generate-notes \
        --notes "Release ${VERSION} of ${DEB_NAME}"; then
        log_error "Failed to create GitHub release"
        git tag -d "${TAG_NAME}"
        git push origin --delete "${TAG_NAME}" 2>/dev/null || true
        exit 1
    fi
    log_info "GitHub release ${TAG_NAME} created successfully"
fi

# Create temporary build directory
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

log_info "Build directory: $BUILD_DIR"

# Configure with CMake
log_info "Configuring with CMake..."
cmake -S "$PACKAGE_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX"

# Build
log_info "Building..."
cmake --build "$BUILD_DIR" --parallel "$(nproc)"

# Generate Debian package with CPack
log_info "Generating Debian package with CPack..."
cd "$BUILD_DIR"
cpack -G DEB

# Locate the generated .deb
DEB_FILE=$(find "$BUILD_DIR" -maxdepth 1 -name "*.deb" | head -1)

if [ -z "$DEB_FILE" ]; then
    log_error "CPack did not produce a .deb file"
    exit 1
fi

log_info "Package built: $(basename "$DEB_FILE")"

# Verify the .deb
log_info "Package contents:"
dpkg -c "$DEB_FILE" | head -20

# Add to apt repository
if [ -d "$APT_REPO_PATH" ]; then
    log_info "Adding to apt repository at $APT_REPO_PATH..."

    NEW_VERSION=$(dpkg-deb -f "$DEB_FILE" Version)
    CURRENT_VERSION=$(reprepro -b "$APT_REPO_PATH" list "$UBUNTU_CODENAME" "$DEB_NAME" 2>/dev/null | awk '{print $3}')

    if [ -n "$CURRENT_VERSION" ]; then
        if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
            log_warn "Updating $DEB_NAME: $CURRENT_VERSION -> $NEW_VERSION"
            mkdir -p "$APT_REPO_PATH/archive/$DEB_NAME"
            find "$APT_REPO_PATH/pool" -name "${DEB_NAME}_${CURRENT_VERSION}_*.deb" \
                -exec cp {} "$APT_REPO_PATH/archive/$DEB_NAME/" \;
            reprepro -b "$APT_REPO_PATH" remove "$UBUNTU_CODENAME" "$DEB_NAME"
        else
            log_warn "Version $NEW_VERSION already exists, skipping"
            exit 0
        fi
    fi

    reprepro -b "$APT_REPO_PATH" includedeb "$UBUNTU_CODENAME" "$DEB_FILE"

    log_info "Package added successfully!"
    log_info "Repository contents:"
    reprepro -b "$APT_REPO_PATH" list "$UBUNTU_CODENAME"
else
    log_warn "APT repository not found at $APT_REPO_PATH"
    log_warn "Copying .deb to current directory instead"
    cp "$DEB_FILE" .
    log_info "Created: $(basename "$DEB_FILE")"
fi

log_info "Done!"

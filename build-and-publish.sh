#!/bin/bash
set -e

# Configuration
APT_REPO_PATH="$HOME/ws/rr-apt"
ROS_DISTRO="${ROS_DISTRO:-kilted}"
UBUNTU_CODENAME=$(grep DISTRIB_CODENAME /etc/lsb-release | cut -d= -f2)
ARCH=$(dpkg --print-architecture)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <package-source-dir>"
    echo ""
    echo "Arguments:"
    echo "  package-source-dir  Path to the ROS2 package source directory"
    echo ""
    echo "Version is extracted from package.xml automatically."
    echo "A GitHub release is created before building the debian package."
    echo ""
    echo "Example:"
    echo "  $0 ~/ws/rr_mousebot/src/rr_common_base"
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
if [ ! -f "$PACKAGE_DIR/package.xml" ]; then
    log_error "No package.xml found in $PACKAGE_DIR"
    exit 1
fi

# Extract package name and version from package.xml
PACKAGE_NAME=$(grep -oP '(?<=<name>)[^<]+' "$PACKAGE_DIR/package.xml" | head -1)
VERSION=$(grep -oP '(?<=<version>)[^<]+' "$PACKAGE_DIR/package.xml" | head -1)

if [ -z "$PACKAGE_NAME" ]; then
    log_error "Could not extract package name from package.xml"
    exit 1
fi

if [ -z "$VERSION" ]; then
    log_warn "Could not extract version from package.xml, defaulting to 0.1.0"
    VERSION="0.1.0"
fi

# Convert ROS package name to Debian name (underscores to hyphens)
DEB_NAME="ros-${ROS_DISTRO}-$(echo "$PACKAGE_NAME" | tr '_' '-')"
TAG_NAME="v${VERSION}"

log_info "Building package: $PACKAGE_NAME"
log_info "Debian name: $DEB_NAME"
log_info "Version: $VERSION"

# Create GitHub release before building debian package
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
    # Create and push tag
    log_info "Creating tag ${TAG_NAME}..."
    git tag -a "${TAG_NAME}" -m "Release ${VERSION}"
    git push origin "${TAG_NAME}"
    
    # Create GitHub release
    log_info "Creating GitHub release..."
    if ! gh release create "${TAG_NAME}" \
        --title "Release ${VERSION}" \
	--generate-notes \
        --notes "Release ${VERSION} of ${PACKAGE_NAME}"; then
        log_error "Failed to create GitHub release"
        # Clean up tag if release failed
        git tag -d "${TAG_NAME}"
        git push origin --delete "${TAG_NAME}" 2>/dev/null || true
        exit 1
    fi
    log_info "GitHub release ${TAG_NAME} created successfully"
fi

# Create temporary workspace
BUILD_DIR=$(mktemp -d)
INSTALL_DIR="$BUILD_DIR/install"
DEB_ROOT="$BUILD_DIR/deb-root"

trap "rm -rf $BUILD_DIR" EXIT

log_info "Build directory: $BUILD_DIR"

# Create a temporary workspace and build
WS_DIR="$BUILD_DIR/ws"
mkdir -p "$WS_DIR/src"
ln -s "$PACKAGE_DIR" "$WS_DIR/src/$PACKAGE_NAME"

cd "$WS_DIR"

log_info "Building with colcon..."
source /opt/ros/$ROS_DISTRO/setup.bash
colcon build \
    --packages-select "$PACKAGE_NAME" \
    --allow-overriding "$PACKAGE_NAME" \
    --install-base "$INSTALL_DIR" \
    --merge-install \
    --cmake-args -DCMAKE_BUILD_TYPE=Release

# Create Debian package structure
log_info "Creating Debian package structure..."
mkdir -p "$DEB_ROOT/opt/ros/$ROS_DISTRO"
mkdir -p "$DEB_ROOT/DEBIAN"

# Copy installed files
cp -r "$INSTALL_DIR"/* "$DEB_ROOT/opt/ros/$ROS_DISTRO/"

# Remove files that belong to ros-workspace package
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/local_setup.bash"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/local_setup.sh"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/local_setup.zsh"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/setup.bash"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/setup.sh"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/setup.zsh"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/local_setup.ps1"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/setup.ps1"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/_local_setup_util_sh.py"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/_local_setup_util_ps1.py"
rm -f "$DEB_ROOT/opt/ros/$ROS_DISTRO/COLCON_IGNORE"

# Generate dependencies from package.xml
DEPENDS="ros-${ROS_DISTRO}-ros-base"
for dep in $(grep -oP '(?<=<depend>)[^<]+' "$PACKAGE_DIR/package.xml"); do
    dep_deb="ros-${ROS_DISTRO}-$(echo "$dep" | tr '_' '-')"
    DEPENDS="$DEPENDS, $dep_deb"
done
for dep in $(grep -oP '(?<=<exec_depend>)[^<]+' "$PACKAGE_DIR/package.xml"); do
    dep_deb="ros-${ROS_DISTRO}-$(echo "$dep" | tr '_' '-')"
    DEPENDS="$DEPENDS, $dep_deb"
done

# Remove duplicates from dependencies
DEPENDS=$(echo "$DEPENDS" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//' | sed 's/^,//')

# Create control file
cat > "$DEB_ROOT/DEBIAN/control" << EOF
Package: $DEB_NAME
Version: $VERSION
Section: misc
Priority: optional
Architecture: $ARCH
Depends: $DEPENDS
Maintainer: Aaron Spiteri <azzmosphere@gmail.com>
Description: ROS2 $ROS_DISTRO package $PACKAGE_NAME
 Auto-generated Debian package for ROS2 package $PACKAGE_NAME.
EOF

log_info "Control file:"
cat "$DEB_ROOT/DEBIAN/control"

# Build the .deb
DEB_FILE="$BUILD_DIR/${DEB_NAME}_${VERSION}_${ARCH}.deb"
log_info "Building .deb..."
dpkg-deb --build "$DEB_ROOT" "$DEB_FILE"

# Verify the .deb
log_info "Package contents:"
dpkg -c "$DEB_FILE" | head -20

# Add to apt repository
if [ -d "$APT_REPO_PATH" ]; then
    log_info "Adding to apt repository at $APT_REPO_PATH..."
    
    # Check if package already exists and remove it
    NEW_VERSION=$(dpkg-deb -f "$DEB_FILE" Version)
    CURRENT_VERSION=$(reprepro -b "$APT_REPO_PATH" list "$UBUNTU_CODENAME" "$DEB_NAME" 2>/dev/null | awk '{print $3}')

   if [ -n "$CURRENT_VERSION" ]; then
      if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
        log_warn "Updating $DEB_NAME: $CURRENT_VERSION -> $NEW_VERSION"
        # Archive old deb before reprepro removes it
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

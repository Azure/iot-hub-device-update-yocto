#!/bin/bash
# Setup developer-specific BitBake configuration
# This creates a developer.conf file that gets included in local.conf

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONF_DIR="$PROJECT_ROOT/conf"
DEV_CONF="$CONF_DIR/developer.conf"
BUILD_DIR="${1:-$HOME/adu_yocto/out/build}"
LOCAL_CONF="$BUILD_DIR/build/conf/local.conf"

echo "Setting up developer configuration..."
echo ""

# Check if template exists
if [ ! -f "$CONF_DIR/developer.conf.template" ]; then
    echo "❌ ERROR: Template not found: $CONF_DIR/developer.conf.template"
    exit 1
fi

# Create developer.conf if it doesn't exist
if [ ! -f "$DEV_CONF" ]; then
    echo "Creating developer.conf from template..."
    cp "$CONF_DIR/developer.conf.template" "$DEV_CONF"
    echo "✓ Created: $DEV_CONF"
    echo ""
    echo "Please edit $DEV_CONF and customize for your environment."
    echo ""
else
    echo "✓ Developer config already exists: $DEV_CONF"
    echo ""
fi

# Check if build directory exists
if [ ! -d "$BUILD_DIR/build/conf" ]; then
    echo "⚠️  Build directory not initialized: $BUILD_DIR"
    echo "   Run a build first to create the build directory, then re-run this script."
    exit 0
fi

# Check if local.conf already includes developer.conf
if grep -q "require.*developer.conf" "$LOCAL_CONF" 2>/dev/null; then
    echo "✓ local.conf already includes developer.conf"
else
    echo "Adding developer.conf include to local.conf..."
    
    # Calculate relative path from build/conf to project root
    REL_PATH=$(realpath --relative-to="$BUILD_DIR/build/conf" "$DEV_CONF")
    
    echo "" >> "$LOCAL_CONF"
    echo "# Developer-specific configuration" >> "$LOCAL_CONF"
    echo "# Edit $DEV_CONF to customize" >> "$LOCAL_CONF"
    echo "require $REL_PATH" >> "$LOCAL_CONF"
    
    echo "✓ Added include to: $LOCAL_CONF"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Configuration files:"
echo "  Template:   $CONF_DIR/developer.conf.template"
echo "  Your config: $DEV_CONF"
echo "  Local conf: $LOCAL_CONF"
echo ""
echo "Next steps:"
echo "  1. Edit $DEV_CONF"
echo "  2. Set your ADU_IMPORTMANIFEST_* variables"
echo "  3. Run build: ./scripts/quick-build.sh --build adu-delta-test-package"
echo ""
echo "To share configuration with team:"
echo "  - Copy your developer.conf to teammates"
echo "  - They can use it as their starting point"
echo "  - OR commit a team-shared config (e.g., conf/team-defaults.conf)"

#!/bin/bash
# Quick build wrapper - sources your dev-config.sh and runs build.sh
# Usage: ./scripts/quick-build.sh [build.sh arguments]
# Example: ./scripts/quick-build.sh --build adu-delta-image
# Example: ./scripts/quick-build.sh --parse-only  (verify recipes only)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_TEMPLATES="$PROJECT_ROOT/yocto/config-templates"

# Check for parse-only mode
PARSE_ONLY=0
if [[ "$1" == "--parse-only" ]]; then
    PARSE_ONLY=1
    shift  # Remove --parse-only from arguments
fi

# Check if dev-config.sh exists in scripts folder
if [ -f "$SCRIPT_DIR/dev-config.sh" ]; then
    echo "Loading developer configuration from scripts/dev-config.sh..."
    source "$SCRIPT_DIR/dev-config.sh"
else
    echo "⚠️  WARNING: scripts/dev-config.sh not found"
    echo "Creating from template..."
    cp "$CONFIG_TEMPLATES/dev-config.sh.template" "$SCRIPT_DIR/dev-config.sh"
    echo "✓ Created scripts/dev-config.sh from template"
    echo ""
    echo "Please customize scripts/dev-config.sh for your environment, then re-run this script."
    exit 1
fi

# Build arguments from environment variables if set
BUILD_ARGS=()

# Add local sources if configured
if [ -n "$ADU_LOCAL_SOURCE_DIR" ] && [ -n "$ADU_DELTA_LOCAL_SOURCE_DIR" ]; then
    BUILD_ARGS+=(--local-sources ADU,ADU_DELTA)
fi

# Add output directory
if [ -n "$ADU_BUILD_OUTPUT_DIR" ]; then
    BUILD_ARGS+=(-o "$ADU_BUILD_OUTPUT_DIR")
fi

# Note: Parallelism settings (-j, --parallel-make) are now handled in conf/developer.conf
# via BB_NUMBER_THREADS and PARALLEL_MAKE. You can override them here if needed:
# BUILD_ARGS+=(-j 8)
# BUILD_ARGS+=(--parallel-make 8)

# Add any command-line arguments passed to this script
BUILD_ARGS+=("$@")

echo ""
echo "Running: ./scripts/build.sh ${BUILD_ARGS[@]}"
echo ""

# Handle parse-only mode
if [ "$PARSE_ONLY" -eq 1 ]; then
    echo "📋 Parse-only mode: Verifying recipes without building..."
    echo ""
    
    # Initialize BitBake environment
    source "$SCRIPT_DIR/build.sh" "${BUILD_ARGS[@]}" <<< "exit" 2>/dev/null || true
    
    # Now run bitbake -p
    cd "$ADU_BUILD_OUTPUT_DIR" 2>/dev/null || cd ~/adu_yocto/out/build
    source poky/oe-init-build-env build >/dev/null
    
    # Parse specific recipes if provided, otherwise parse all
    if [ $# -gt 0 ]; then
        echo "Parsing recipes: $@"
        bitbake -p "$@"
    else
        echo "Parsing all recipes..."
        bitbake -p
    fi
    
    echo ""
    echo "✅ Recipe parsing complete!"
    exit 0
fi

# Run the build
exec "$SCRIPT_DIR/build.sh" "${BUILD_ARGS[@]}"

#!/bin/bash
# build-docker-delta-tools.sh — Build Docker image for ADU delta tools
#
# Prerequisites:
#   1. Complete a Yocto build
#   2. Run scripts/package-delta-tools.sh to create the tarball
#   3. Run this script to build the Docker image
#
# Usage:
#   ./docker/build-docker-delta-tools.sh
#   ./docker/build-docker-delta-tools.sh --version 3.0.0 --tag adu-delta-tools:3.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$REPO_DIR/artifacts"

VERSION="3.0.0"
IMAGE_TAG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)   VERSION="$2"; shift 2 ;;
        --tag)       IMAGE_TAG="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: build-docker-delta-tools.sh [--version <ver>] [--tag <image:tag>]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

GEN_PKG_NAME="adu-delta-gen-tools-x86_64-${VERSION}"
GEN_PKG_TAR="$ARTIFACTS_DIR/${GEN_PKG_NAME}.tar.gz"

if [[ -z "$IMAGE_TAG" ]]; then
    IMAGE_TAG="adu-delta-tools:${VERSION}"
fi

# Check prerequisites
if [[ ! -f "$GEN_PKG_TAR" ]]; then
    echo "ERROR: Package not found: $GEN_PKG_TAR"
    echo ""
    echo "Run the packaging script first:"
    echo "  ./scripts/package-delta-tools.sh --build-dir ~/adu_yocto/out/build --version $VERSION"
    exit 1
fi

# Extract tarball into artifacts dir (Docker COPY needs unpacked dir)
echo "Preparing build context..."
(cd "$ARTIFACTS_DIR" && tar xzf "$GEN_PKG_TAR")

echo "Building Docker image: $IMAGE_TAG"
docker build \
    -t "$IMAGE_TAG" \
    -f "$SCRIPT_DIR/Dockerfile.delta-tools" \
    --build-arg "GEN_PKG_DIR=$GEN_PKG_NAME" \
    "$ARTIFACTS_DIR"

echo ""
echo "✅ Docker image built: $IMAGE_TAG"
echo ""
echo "Usage examples:"
echo "  # Show help"
echo "  docker run --rm $IMAGE_TAG"
echo ""
echo "  # Generate delta"
echo "  docker run --rm -v \$PWD:/data $IMAGE_TAG \\"
echo "      diffgentool /data/source.swu /data/target.swu /data/delta.diff /data/work"
echo ""
echo "  # Apply delta"
echo "  docker run --rm -v \$PWD:/data $IMAGE_TAG \\"
echo "      applydiff /data/source.swu /data/delta.diff /data/reconstructed.swu"

#!/bin/bash
# package-delta-tools.sh — Package ADU delta tools for customer distribution
#
# Collects built artifacts from a completed Yocto build and creates
# self-contained tarballs for delta generation and reconstitution.
#
# Usage:
#   ./scripts/package-delta-tools.sh --build-dir ~/adu_yocto/out/build
#   ./scripts/package-delta-tools.sh --build-dir ~/adu_yocto/out/build --output-dir ./artifacts
#   ./scripts/package-delta-tools.sh --build-dir ~/adu_yocto/out/build --version 3.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
BUILD_DIR=""
OUTPUT_DIR="${REPO_DIR}/artifacts"
VERSION=""
ARCH="x86_64"

print_help() {
    cat << 'EOF'
Usage: package-delta-tools.sh [options]

Options:
  --build-dir <path>       Path to Yocto build output directory (required).
                           Example: ~/adu_yocto/out/build
  --output-dir <path>      Output directory for packages. Default: ./artifacts
  --version <version>      Version string for the package. Default: auto-detect from recipe.
  -h, --help               Show this help message.

Examples:
  ./scripts/package-delta-tools.sh --build-dir ~/adu_yocto/out/build
  ./scripts/package-delta-tools.sh --build-dir ~/adu_yocto/out/build --version 3.0.0
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-dir)   BUILD_DIR="$2"; shift 2 ;;
        --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
        --version)     VERSION="$2"; shift 2 ;;
        -h|--help)     print_help; exit 0 ;;
        *)             echo "Unknown option: $1"; print_help; exit 1 ;;
    esac
done

if [[ -z "$BUILD_DIR" ]]; then
    echo "ERROR: --build-dir is required"
    print_help
    exit 1
fi

# Resolve paths
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
SYSROOT_NATIVE="$BUILD_DIR/build/tmp/sysroots-components/x86_64"

if [[ ! -d "$SYSROOT_NATIVE" ]]; then
    echo "ERROR: Native sysroot not found at: $SYSROOT_NATIVE"
    echo "  Have you completed a Yocto build?"
    exit 1
fi

# Auto-detect version if not specified
if [[ -z "$VERSION" ]]; then
    VERSION="3.0"
    echo "Using default version: $VERSION"
fi

echo "============================================"
echo "  ADU Delta Tools Packaging"
echo "============================================"
echo "  Build dir:  $BUILD_DIR"
echo "  Output dir: $OUTPUT_DIR"
echo "  Version:    $VERSION"
echo "  Arch:       $ARCH"
echo "============================================"

mkdir -p "$OUTPUT_DIR"

# ---- Dependency Manifest (explicit, not ldd-based) ----

# Native tool binaries
declare -A GEN_TOOLS=(
    ["diffgentool.bin"]="iot-hub-device-update-delta-diffgentool-native/usr/bin/diffgentool.bin"
    ["diffgentool.wrapper"]="iot-hub-device-update-delta-diffgentool-native/usr/bin/diffgentool"
    ["applydiff"]="iot-hub-device-update-delta-processor-native/usr/bin/applydiff"
    ["dumpdiff"]="iot-hub-device-update-delta-processor-native/usr/bin/dumpdiff"
    ["dumpextfs"]="iot-hub-device-update-delta-processor-native/usr/bin/dumpextfs"
    ["extract"]="iot-hub-device-update-delta-processor-native/usr/bin/extract"
    ["makecpio"]="iot-hub-device-update-delta-processor-native/usr/bin/makecpio"
    ["recompress"]="iot-hub-device-update-delta-processor-native/usr/bin/recompress"
    ["zstd_compress_file"]="iot-hub-device-update-delta-processor-native/usr/bin/zstd_compress_file"
    ["bsdiff"]="bsdiff-native/usr/bin/bsdiff"
    ["bspatch"]="bsdiff-native/usr/bin/bspatch"
)

# Apply-only tools (subset)
declare -A APPLY_TOOLS=(
    ["applydiff"]="iot-hub-device-update-delta-processor-native/usr/bin/applydiff"
    ["dumpdiff"]="iot-hub-device-update-delta-processor-native/usr/bin/dumpdiff"
)

# Shared libraries (explicit manifest — do NOT use ldd)
declare -A NATIVE_LIBS=(
    ["libadudiffapi.so"]="iot-hub-device-update-delta-processor-native/usr/lib/libadudiffapi.so"
    ["libz.so.1"]="zlib-native/usr/lib/libz.so.1"
    ["libzstd.so.1"]="zstd-native/usr/lib/libzstd.so.1"
    ["libbz2.so.1"]="bzip2-native/usr/lib/libbz2.so.1"
    ["libjsoncpp.so.25"]="jsoncpp-native/usr/lib/libjsoncpp.so.25"
    ["libgcrypt.so.20"]="libgcrypt-native/usr/lib/libgcrypt.so.20"
    ["libfmt.so.10"]="fmt-native/usr/lib/libfmt.so.10"
    ["libconfig.so.11"]="libconfig-native/usr/lib/libconfig.so.11"
    ["libcrypto.so.3"]="openssl-native/usr/lib/libcrypto.so.3"
    ["libssl.so.3"]="openssl-native/usr/lib/libssl.so.3"
)

# Also check for libgpg-error (transitive dep of libgcrypt)
if [[ -f "$SYSROOT_NATIVE/libgpg-error-native/usr/lib/libgpg-error.so.0" ]]; then
    NATIVE_LIBS["libgpg-error.so.0"]="libgpg-error-native/usr/lib/libgpg-error.so.0"
fi

# ---- Helper Functions ----

copy_resolve_symlink() {
    local src="$1"
    local dst="$2"

    if [[ -L "$src" ]]; then
        # Resolve the symlink chain and copy the actual file
        local real_file
        real_file="$(readlink -f "$src")"
        local real_name
        real_name="$(basename "$real_file")"
        local link_name
        link_name="$(basename "$src")"

        cp "$real_file" "$dst/$real_name"
        if [[ "$link_name" != "$real_name" ]]; then
            ln -sf "$real_name" "$dst/$link_name"
        fi
    else
        cp "$src" "$dst/$(basename "$src")"
    fi
}

verify_file() {
    local label="$1"
    local path="$2"
    if [[ ! -e "$path" ]]; then
        echo "  ❌ MISSING: $label → $path"
        return 1
    fi
    echo "  ✓ $label"
    return 0
}

# ---- Build Generation Package ----

echo ""
echo "=== Building: adu-delta-gen-tools-${ARCH} ==="

GEN_PKG_NAME="adu-delta-gen-tools-${ARCH}-${VERSION}"
GEN_PKG_DIR="$OUTPUT_DIR/$GEN_PKG_NAME"
rm -rf "$GEN_PKG_DIR"
mkdir -p "$GEN_PKG_DIR/bin" "$GEN_PKG_DIR/lib"

echo "Collecting tools..."
MISSING=0
for tool_name in "${!GEN_TOOLS[@]}"; do
    src_path="$SYSROOT_NATIVE/${GEN_TOOLS[$tool_name]}"
    if ! verify_file "$tool_name" "$src_path"; then
        MISSING=$((MISSING + 1))
        continue
    fi

    if [[ "$tool_name" == "diffgentool.wrapper" ]]; then
        # Skip the Yocto wrapper — we'll create our own
        continue
    fi
    cp "$src_path" "$GEN_PKG_DIR/bin/$tool_name"
    chmod +x "$GEN_PKG_DIR/bin/$tool_name"
done

echo "Collecting libraries..."
for lib_name in "${!NATIVE_LIBS[@]}"; do
    src_path="$SYSROOT_NATIVE/${NATIVE_LIBS[$lib_name]}"
    if ! verify_file "$lib_name" "$src_path"; then
        MISSING=$((MISSING + 1))
        continue
    fi
    copy_resolve_symlink "$src_path" "$GEN_PKG_DIR/lib"
done

if [[ $MISSING -gt 0 ]]; then
    echo ""
    echo "⚠️  WARNING: $MISSING files missing. Package may be incomplete."
    echo "  Ensure you have completed a full Yocto build first."
fi

# Create wrapper script for DiffGenTool
cat > "$GEN_PKG_DIR/bin/diffgentool" << 'WRAPPER_EOF'
#!/bin/bash
# DiffGenTool wrapper — sets up library paths and helper tool discovery
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TOOL_DIR/../lib" && pwd)"

export LD_LIBRARY_PATH="${LIB_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="${TOOL_DIR}:${PATH}"

# .NET single-file apps extract to a temp directory and look for native
# helpers in the same directory as the assembly. We detect the extraction
# directory and symlink our tools/libs into it on first run.
setup_dotnet_helpers() {
    # Run --help to trigger extraction and find the directory
    local extract_dir
    extract_dir=$("$TOOL_DIR/diffgentool.bin" --help 2>/dev/null | head -1 || true)

    # Find the .NET extraction directory
    local net_dir=""
    for d in /tmp/.net/DiffGenTool/*/; do
        if [[ -d "$d" ]]; then
            net_dir="$d"
        fi
    done

    if [[ -n "$net_dir" ]]; then
        # Symlink native helpers into .NET extraction directory
        for helper in bsdiff zstd_compress_file dumpextfs libadudiffapi.so; do
            local src=""
            if [[ -f "$TOOL_DIR/$helper" ]]; then
                src="$TOOL_DIR/$helper"
            elif [[ -f "$LIB_DIR/$helper" ]]; then
                src="$LIB_DIR/$helper"
            fi
            if [[ -n "$src" ]] && [[ ! -e "$net_dir/$helper" ]]; then
                ln -sf "$src" "$net_dir/$helper" 2>/dev/null || true
            fi
        done

        # Symlink libjsoncpp into extraction dir
        for lib in "$LIB_DIR"/libjsoncpp.so*; do
            local base
            base="$(basename "$lib")"
            if [[ ! -e "$net_dir/$base" ]]; then
                ln -sf "$lib" "$net_dir/$base" 2>/dev/null || true
            fi
        done
    fi
}

setup_dotnet_helpers

exec "$TOOL_DIR/diffgentool.bin" "$@"
WRAPPER_EOF
chmod +x "$GEN_PKG_DIR/bin/diffgentool"

# Create applydiff wrapper
cat > "$GEN_PKG_DIR/bin/applydiff-wrapper" << 'WRAPPER_EOF'
#!/bin/bash
# applydiff wrapper — sets up library paths
TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TOOL_DIR/../lib" && pwd)"
export LD_LIBRARY_PATH="${LIB_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$TOOL_DIR/applydiff" "$@"
WRAPPER_EOF
chmod +x "$GEN_PKG_DIR/bin/applydiff-wrapper"

# Create VERSION file
cat > "$GEN_PKG_DIR/VERSION" << EOF
Package: adu-delta-gen-tools
Version: $VERSION
Architecture: $ARCH
Build-Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Build-Host: $(hostname)
Yocto-Release: scarthgap
EOF

# Create SBOM
cat > "$GEN_PKG_DIR/SBOM.json" << EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "component": {
      "type": "application",
      "name": "adu-delta-gen-tools",
      "version": "$VERSION"
    }
  },
  "components": [
    {"type": "application", "name": "DiffGenTool", "version": "$VERSION", "description": "ADU delta generation tool (.NET 8.0)"},
    {"type": "application", "name": "applydiff", "version": "$VERSION", "description": "Delta reconstitution tool"},
    {"type": "application", "name": "bsdiff", "version": "1.0.0", "description": "Binary diff tool", "licenses": [{"license": {"id": "BSD-2-Clause"}}]},
    {"type": "library", "name": "libadudiffapi", "version": "$VERSION", "description": "ADU diff/patch API", "licenses": [{"license": {"id": "MIT"}}]},
    {"type": "library", "name": "zlib", "version": "1.3.1", "licenses": [{"license": {"id": "Zlib"}}]},
    {"type": "library", "name": "zstd", "version": "1.5.5", "licenses": [{"license": {"id": "BSD-3-Clause"}}]},
    {"type": "library", "name": "bzip2", "version": "1.0.8", "licenses": [{"license": {"id": "bzip2-1.0.6"}}]},
    {"type": "library", "name": "jsoncpp", "version": "1.9.5", "licenses": [{"license": {"id": "MIT"}}]},
    {"type": "library", "name": "libgcrypt", "version": "1.10.3", "licenses": [{"license": {"id": "LGPL-2.1-only"}}]},
    {"type": "library", "name": "fmt", "version": "10.2.1", "licenses": [{"license": {"id": "MIT"}}]},
    {"type": "library", "name": "libconfig", "version": "1.7.3", "licenses": [{"license": {"id": "LGPL-2.1-only"}}]},
    {"type": "library", "name": "openssl", "version": "3.x", "licenses": [{"license": {"id": "Apache-2.0"}}]}
  ]
}
EOF

# Create package README
cat > "$GEN_PKG_DIR/README.md" << 'README_EOF'
# ADU Delta Generation & Apply Tools

Self-contained package for generating and applying ADU delta updates.

## Quick Start

```bash
# Add tools to PATH
export PATH="$PWD/bin:$PATH"

# Generate a delta diff
diffgentool source.swu target.swu delta.diff ./work-dir

# Reconstitute target from source + delta
applydiff-wrapper source.swu delta.diff target-reconstructed.swu

# Verify
sha256sum target.swu target-reconstructed.swu
```

## Requirements

- Linux x86_64 (Ubuntu 22.04+, Debian 12+, or RHEL 9+)
- glibc ≥ 2.34

## Package Contents

- `bin/` — Executable tools and wrapper scripts
- `lib/` — Bundled shared libraries
- `SBOM.json` — Software Bill of Materials
- `VERSION` — Build metadata

## Notes

- All shared library dependencies are bundled in `lib/`.
- Wrapper scripts (`diffgentool`, `applydiff-wrapper`) set `LD_LIBRARY_PATH` automatically.
- Bundled OpenSSL/libgcrypt are NOT FIPS-validated.
README_EOF

# Patch ELF interpreters and RPATH for portability outside Yocto sysroot
echo ""
echo "Patching ELF binaries for portability..."
if command -v patchelf &>/dev/null; then
    for bin in "$GEN_PKG_DIR/bin/"*; do
        if file "$bin" | grep -q 'ELF.*dynamically linked'; then
            patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 "$bin" 2>/dev/null || true
            patchelf --set-rpath '$ORIGIN/../lib' "$bin" 2>/dev/null || true
            echo "  ✓ Patched: $(basename "$bin")"
        fi
    done
else
    echo "  ⚠️  patchelf not found — binaries will require LD_LIBRARY_PATH and may not"
    echo "     work outside the Yocto build host. Install with: pip install patchelf"
fi

# Create tarball
echo ""
echo "Creating tarball..."
echo "✅ Created: $OUTPUT_DIR/${GEN_PKG_NAME}.tar.gz"

# ---- Build Apply-Only Package ----

echo ""
echo "=== Building: adu-delta-apply-tools-${ARCH} ==="

APPLY_PKG_NAME="adu-delta-apply-tools-${ARCH}-${VERSION}"
APPLY_PKG_DIR="$OUTPUT_DIR/$APPLY_PKG_NAME"
rm -rf "$APPLY_PKG_DIR"
mkdir -p "$APPLY_PKG_DIR/bin" "$APPLY_PKG_DIR/lib"

echo "Collecting tools..."
for tool_name in "${!APPLY_TOOLS[@]}"; do
    src_path="$SYSROOT_NATIVE/${APPLY_TOOLS[$tool_name]}"
    if verify_file "$tool_name" "$src_path"; then
        cp "$src_path" "$APPLY_PKG_DIR/bin/$tool_name"
        chmod +x "$APPLY_PKG_DIR/bin/$tool_name"
    fi
done

echo "Collecting libraries..."
for lib_name in "${!NATIVE_LIBS[@]}"; do
    src_path="$SYSROOT_NATIVE/${NATIVE_LIBS[$lib_name]}"
    if [[ -e "$src_path" ]]; then
        copy_resolve_symlink "$src_path" "$APPLY_PKG_DIR/lib"
    fi
done

# Create applydiff wrapper
cat > "$APPLY_PKG_DIR/bin/applydiff-wrapper" << 'WRAPPER_EOF'
#!/bin/bash
TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TOOL_DIR/../lib" && pwd)"
export LD_LIBRARY_PATH="${LIB_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$TOOL_DIR/applydiff" "$@"
WRAPPER_EOF
chmod +x "$APPLY_PKG_DIR/bin/applydiff-wrapper"

cp "$GEN_PKG_DIR/VERSION" "$APPLY_PKG_DIR/VERSION"
sed 's/adu-delta-gen-tools/adu-delta-apply-tools/' -i "$APPLY_PKG_DIR/VERSION"
cp "$GEN_PKG_DIR/SBOM.json" "$APPLY_PKG_DIR/SBOM.json"

# Patch ELF binaries in apply package
echo ""
echo "Patching apply-tools ELF binaries..."
if command -v patchelf &>/dev/null; then
    for bin in "$APPLY_PKG_DIR/bin/"*; do
        if file "$bin" | grep -q 'ELF.*dynamically linked'; then
            patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 "$bin" 2>/dev/null || true
            patchelf --set-rpath '$ORIGIN/../lib' "$bin" 2>/dev/null || true
            echo "  ✓ Patched: $(basename "$bin")"
        fi
    done
fi

cat > "$APPLY_PKG_DIR/README.md" << 'README_EOF'
# ADU Delta Apply Tools

Minimal package for applying ADU delta updates (reconstitution).

## Quick Start

```bash
export PATH="$PWD/bin:$PATH"
applydiff-wrapper source.swu delta.diff target-reconstructed.swu
```

## Requirements

- Linux x86_64 (Ubuntu 22.04+, Debian 12+, or RHEL 9+)
- glibc ≥ 2.34
README_EOF

echo ""
echo "Creating tarball..."
(cd "$OUTPUT_DIR" && tar czf "${APPLY_PKG_NAME}.tar.gz" "$APPLY_PKG_NAME")
echo "✅ Created: $OUTPUT_DIR/${APPLY_PKG_NAME}.tar.gz"

# ---- Summary ----

echo ""
echo "============================================"
echo "  Packaging Complete"
echo "============================================"
echo ""
echo "  Generation tools: $OUTPUT_DIR/${GEN_PKG_NAME}.tar.gz"
echo "  Apply tools:      $OUTPUT_DIR/${APPLY_PKG_NAME}.tar.gz"
echo ""
echo "  Generation package contents:"
(cd "$OUTPUT_DIR" && du -sh "${GEN_PKG_NAME}.tar.gz")
echo "  Apply package contents:"
(cd "$OUTPUT_DIR" && du -sh "${APPLY_PKG_NAME}.tar.gz")
echo ""
echo "  To verify, extract and run:"
echo "    tar xzf ${GEN_PKG_NAME}.tar.gz"
echo "    ./${GEN_PKG_NAME}/bin/diffgentool --help"
echo "============================================"

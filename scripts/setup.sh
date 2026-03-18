#!/usr/bin/env bash
#
# setup.sh - Clone all Yocto meta-layers required to build Azure Device Update
#
# This script clones poky, meta-openembedded, and all ADU-related layers into
# the yocto/ directory. Run this once to set up your build environment.
#
# Usage: ./scripts/setup.sh
#

yocto_release='scarthgap'
adu_release='feature/vnext-delta'
project_root="$HOME/adu_yocto"

repo_base="${project_root}/iot-hub-device-update-yocto"
layers_base="${repo_base}/yocto"

mkdir -vp ${layers_base}

uri_poky='git://git.yoctoproject.org/poky'
uri_meta_swu='https://github.com/sbabic/meta-swupdate'
uri_meta_oe='git://git.openembedded.org/meta-openembedded'
uri_meta_rpi='git://git.yoctoproject.org/meta-raspberrypi'


uri_meta_clang='https://github.com/kraj/meta-clang'
uri_meta_dotnet='https://github.com/RDunkley/meta-dotnet-core'

# Specific commits for reproducible builds
meta_clang_commit='731488911f55ebfe746068512b426351192f82f2'


# Helper: clone a repo only if the target directory doesn't already exist
clone_if_missing() {
    local dest="$1"
    shift
    if [ -d "$dest" ]; then
        echo "⏭ Skipping $(basename "$dest") (already exists)"
    else
        git clone "$@" "$dest" || exit 1
    fi
}

# Skip cloning iot-hub-device-update-yocto if it already exists (i.e., we're running from within it)
if [ ! -d "${project_root}/iot-hub-device-update-yocto" ]; then
    git clone \
        git@github.com:azure/iot-hub-device-update-yocto \
        -b "$adu_release" \
        "${project_root}/iot-hub-device-update-yocto" || exit 1
fi

pushd "${layers_base}" || exit 1

# Poky and base layers
clone_if_missing poky          --depth 1 --branch $yocto_release $uri_poky
clone_if_missing meta-swupdate --depth 1 --branch $yocto_release $uri_meta_swu
clone_if_missing meta-openembedded --depth 1 --branch $yocto_release $uri_meta_oe
clone_if_missing meta-raspberrypi  --depth 1 --branch $yocto_release $uri_meta_rpi

#
# Device Update Layers
#
# meta-azure-device-update: Core ADU agent, extensions, and download handlers
clone_if_missing meta-azure-device-update --branch $adu_release https://github.com/azure/meta-azure-device-update

# meta-iot-hub-device-update-delta: Delta update processor and diff generation tools
clone_if_missing meta-iot-hub-device-update-delta --branch $adu_release https://github.com/azure/meta-iot-hub-device-update-delta

# Dependencies for meta-iot-hub-device-update-delta layer
# meta-clang is required for building delta processor native components
echo "Cloning meta-clang (dependency of meta-iot-hub-device-update-delta)..."
clone_if_missing meta-clang --branch $yocto_release $uri_meta_clang
pushd meta-clang
git checkout $meta_clang_commit || exit 1
echo "✓ meta-clang checked out at commit $meta_clang_commit"
popd

# meta-dotnet-core - optional, not currently in bblayers.conf but available for future use
echo "Cloning meta-dotnet-core (optional - for .NET target builds)..."
clone_if_missing meta-dotnet-core $uri_meta_dotnet
echo "✓ meta-dotnet-core cloned (not added to bblayers.conf by default)"

# meta-azure-device-update-samples: Sample images, test packages, and reference configurations
clone_if_missing meta-azure-device-update-samples --branch $adu_release https://github.com/azure/meta-azure-device-update-samples

# meta-raspberrypi-adu: Raspberry Pi specific A/B update support and boot configuration
updateclone_if_missing meta-raspberrypi-adu --branch $adu_release https://github.com/azure/meta-raspberrypi-adu

popd

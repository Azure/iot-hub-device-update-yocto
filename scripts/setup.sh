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

uri_poky='https://git.yoctoproject.org/poky'
uri_meta_swu='https://github.com/sbabic/meta-swupdate'
uri_meta_oe='https://git.openembedded.org/meta-openembedded'
uri_meta_rpi='https://git.yoctoproject.org/meta-raspberrypi'


uri_meta_clang='https://github.com/kraj/meta-clang'
uri_meta_dotnet='https://github.com/dotnet/meta-dotnet-core'

# Specific commits for reproducible builds
meta_clang_commit='731488911f55ebfe746068512b426351192f82f2'
meta_dotnet_branch='trunk'

git clone \
    git@github.com/azure/iot-hub-device-update-yocto \
    -b "$yocto_release" \
    "${project_root}/iot-hub-device-update-yocto"

pushd "${layers_base}" || exit 1

# Poky and base layers
git clone --depth 1 --branch $yocto_release $uri_poky      || exit 1
git clone --depth 1 --branch $yocto_release $uri_meta_swu  || exit 1
git clone --depth 1 --branch $yocto_release $uri_meta_oe   || exit 1
git clone --depth 1 --branch $yocto_release $uri_meta_rpi  || exit 1


#
# Device Update Layers
#
# meta-azure-device-update: Core ADU agent, extensions, and download handlers
git clone --branch $adu_release http://github.com/azure/meta-azure-device-update

# meta-iot-hub-device-update-delta: Delta update processor and diff generation tools
git clone --branch $adu_release http://github.com/azure/meta-iot-hub-device-update-delta

# Dependencies for meta-iot-hub-device-update-delta layer
# meta-clang is required for building delta processor native components
echo "Cloning meta-clang (dependency of meta-iot-hub-device-update-delta)..."
git clone --branch $yocto_release $uri_meta_clang || exit 1
pushd meta-clang
git checkout $meta_clang_commit || exit 1
echo "✓ meta-clang checked out at commit $meta_clang_commit"
popd

# meta-dotnet-core - optional, not currently in bblayers.conf but available for future use
echo "Cloning meta-dotnet-core (optional - for .NET target builds)..."
git clone --branch $meta_dotnet_branch $uri_meta_dotnet || exit 1
echo "✓ meta-dotnet-core cloned (not added to bblayers.conf by default)"

# meta-azure-device-update-samples: Sample images, test packages, and reference configurations
git clone --branch $adu_release http://github.com/azure/meta-azure-device-update-samples

# meta-raspberrypi-adu: Raspberry Pi specific A/B update support and boot configuration
git clone --branch $adu_release http://github.com/azure/meta-raspberrypi-adu

popd

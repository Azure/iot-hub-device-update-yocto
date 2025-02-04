#!/usr/bin/env bash

yocto_release='scarthgap'
adu_release='main'
project_root="$HOME/adu_yocto"

repo_base="${project_root}/iot-hub-device-update-yocto"
layers_base="${repo_base}/yocto"

mkdir -vp ${layers_base}

uri_poky='git://git.yoctoproject.org/poky'
uri_meta_swu='https://github.com/sbabic/meta-swupdate'
uri_meta_oe='git://git.openembedded.org/meta-openembedded'
uri_meta_rpi='git://git.yoctoproject.org/meta-raspberrypi'

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

# Device Update Layers
git clone --branch $yocto_release http://github.com/azure/meta-azure-device-update
git clone --branch $yocto_release http://github.com/azure/meta-raspberrypi-adu
git clone --branch $yocto_release http://github.com/azure/meta-iot-hub-device-update-delta

popd

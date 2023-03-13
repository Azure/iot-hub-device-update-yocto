# Building a Custom Linux-based System with Device Update for IotHub Agent using the Yocto Project

## Introduction

This repository contains a `Configuration Files` which hold various information that tells the Yocto build system what to build and put into the image to support Raspberry Pi 3B+ hardware.

The build system generates a base image and an update image (armv7l, or arm32), both containing the Device Update agent and its (runtime) dependencies.

This is a showcase of Device Update's Image-based updating capability. 

For more information about the Device Update for IoT Hub, see the link to the source code of [Device Update Agent](https://github.com/Azure/iot-hub-device-update)

## Prerequisites

Before getting started with this project, please get yourself familiar with the following topics:

- [The Yocto Project Software Overview](https://www.yoctoproject.org/software-overview/)
- [The Device Update for IoTHub Overview](http://github.com/azure/iot-hub-device-update)

## Getting Started

- [Clone The Source Code](#clone-source-code)
- [How Building The Project Locally](#how-to-build-the-project-locally)
- [How To Build The Project using Azure DevOp Build Pipeline](#how-to-build-the-project-using-azure-devop-build-pipeline)


### Get Source Code

Please note that, at the time of this writing, we only support `honister` release of the Yocto Project. Keep in mind the following environment variables that will be referenced throughout this document:


| Variable Name | Description |
|---|---|
| $yocto_release | A name of the version of the Yocto Project used to build the images.<br/>(Only support `honister` at the moment) |
| $proj_root | A root directory where this project will be cloned into.|



- Clone the Yocto (Poky) project
    
    ```shell
    yocto_release=honister
    adu_release=main
    
    # Clone project with Yocto configuration files
    git clone <github url> -b <branchname> $proj_root

    cd $project_root/yocto

    # Clone the Yocto Project (poky) into 'yocto' dir
    git clone --depth 1 --branch $yocto_release git://git.yoctoproject.org/poky
    ```

- Clone SWUpdate meta layer. SWUpdate provides an image-based update that support dual-partition.
  
    ```shell
    # Clone swupdate meta layer 
    git clone --depth 1 --branch $yocto_release  https://github.com/sbabic/meta-swupdate
    ```

- Clone the Open Embedded meta layer. This layer include many modules (or layers) needed for building a Linux-base system.

    ```shell
    git clone --depth 1 --branch $yocto_release  git://git.openembedded.org/meta-openembedded
    ```

- Clone the Raspberry Pi meta layer. Since, the reference image that we are building is for a Raspberry Pi 3B+ hardware.

    ```shell
    git clone --depth 1 --branch $yocto_release git://git.yoctoproject.org/meta-raspberrypi
    ```

- Clone the Azure Device Update meta layer.

    ```shell
    git clone --branch $adu_release http://github.com/azure/meta-azure-device-update
    ```

- Clone the IoT Hub Device Update Delta meta layer.

    ```shell
    git clone --branch $adu_release http://github.com/azure/meta-iot-hub-device-update-delta
    ```

- Clone the Raspberry Pi with ADU meta layer.
  
    ```shell
    git clone --branch $adu_release http://github.com/azure/meta-raspberrypi-adu
    ```

### How To Build The Project Locally

#### Install Build Dependencies and Tools

For more information, see [Yocto Project Quick Build](https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html#yocto-project-quick-build)

```sh
# Install build dependencies
sudo ./scripts/install-deps.h

# Checkout a desired 'poky' branch
cd yocto/poky
git fetch
git checkout -t origin/honister -b my-honister
git pull

# Initialize build environment
source oe-init-build-env
```

### Build The Project

```sh
# Run from project root folder
./scripts/build.sh -c -t $BUILD_TYPE -v $BUILD_NUMBER -o $BUILD_OUTPUT_DIR [optional build arguments]
         
```

For example, the following arguments were used to build the IoT Hub Device Update from the ['develop'](https://github.com/Azure/iot-hub-device-update/tree/e099aaca0ad2b8849de24a13b1aa8e3ddf009251) branch at the commit#e099aac

```sh
# Run following commands from <projectroot> directory
yocto_release=honister
adu_release=honister
adu_src_uri="gitsm://github.com/azure/iot-hub-device-update"
# NOTE: Must specify the specific 'branch' and 'commit' for iot-hub-device-update here
adu_git_branch=develop
adu_git_commit=e099aaca0ad2b8849de24a13b1aa8e3ddf009251
do_src_uri="gitsm://github.com/microsoft/do-client.git"
do_git_branch=main
do_git_commit=b61de2d347c8032562056b18f90ec710e531baf8
adu_delta_src_uri="gitsm://github.com/azure/iot-hub-device-update-delta"
adu_delta_git_branch=main
adu_delta_git_commit=b581e92458f458969b427051a2ac5d18d3528dc6
build_type=debug
build_number=1.0.1
build_output_dir=~/adu-yocto-build-output

./scripts/build.sh -c -t $build_type -v $build_number --adu-src-uri $adu_src_uri --adu-git-branch $adu_git_branch --adu-git-commit $adu_git_commit --do-src-uri $do_src_uri --do-git-branch $do_git_branch  --do-git-commit $do_git_commit --adu-delta-src-uri $adu_delta_src_uri --adu-delta-git-branch $adu_delta_git_branch --adu-delta-git-commit $adu_delta_git_commit -o $build_output_dir
```

If success, the output image file (adu-base-image-raspberrypi3.wic.gz) and example .swu update file (adu-update-image-raspberrypi3.swu) shold be located in `$build_output_dir/tmp/deploy/images/raspberrypi3` directory

```sh
.
├── adu-base-image-raspberrypi3.wic.gz
├── adu-update-image-raspberrypi3.swu
```

## Build Pipelines Status

| Board | Branch | Status |
|---|---|---|
| Raspberry Pi 3 | honister | [![Build Status](https://dev.azure.com/azure-device-update/adu-linux-client/_apis/build/status/azure.iot-hub-device-update-yocto?branchName=honister)](https://dev.azure.com/azure-device-update/adu-linux-client/_build/latest?definitionId=57&branchName=honister)|

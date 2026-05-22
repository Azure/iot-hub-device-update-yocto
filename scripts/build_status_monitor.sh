#!/bin/bash
# Script to cross-compile status_monitor using Yocto toolchain
#
# The status_monitor is a command-line utility that continuously monitors the
# Azure Device Update (ADU) agent status. It's useful for:
# - Debugging update issues on the device
# - Monitoring agent state during OTA deployments
# - System integration testing
#
# Prerequisites:
# - Successful Yocto build with azure-device-update recipe
# - The SDK library (libaducsdk.a) must be built
#
# Usage:
#   ./build_status_monitor.sh                          # Uses default build output dir
#   BUILD_OUTPUT_DIR=~/my_build ./build_status_monitor.sh  # Custom build output dir

set -e

# Build output directory - set via environment variable or use default
# This should match the -o option used with build.sh
BUILD_OUTPUT_DIR="${BUILD_OUTPUT_DIR:-$HOME/adu_yocto/out/build}"

# Yocto build paths - supports both flat and nested build directory structures
if [ -d "${BUILD_OUTPUT_DIR}/build/tmp" ]; then
    # Nested structure: <output>/build/tmp (from build.sh with -o option)
    YOCTO_BUILD_DIR="${BUILD_OUTPUT_DIR}/build"
elif [ -d "${BUILD_OUTPUT_DIR}/tmp" ]; then
    # Flat structure: <output>/tmp
    YOCTO_BUILD_DIR="${BUILD_OUTPUT_DIR}"
else
    echo "ERROR: Cannot find Yocto build directory. Expected one of:"
    echo "  ${BUILD_OUTPUT_DIR}/build/tmp"
    echo "  ${BUILD_OUTPUT_DIR}/tmp"
    echo ""
    echo "Set BUILD_OUTPUT_DIR to match the -o option used with build.sh:"
    echo "  BUILD_OUTPUT_DIR=~/your_build_dir ./scripts/build_status_monitor.sh"
    exit 1
fi

ADU_WORK_DIR="${YOCTO_BUILD_DIR}/tmp/work/cortexa72-poky-linux/azure-device-update/1.1+git"
SYSROOT="${ADU_WORK_DIR}/recipe-sysroot"
LIB_BUILD_DIR="${ADU_WORK_DIR}/build/src"
GIT_SRC_DIR="${ADU_WORK_DIR}/git/src"

SDK_SRC_DIR="${GIT_SRC_DIR}/sdk/examples"
SDK_BUILD_DIR="${LIB_BUILD_DIR}/sdk"
SDK_INC_DIR="${GIT_SRC_DIR}/sdk/inc"

ZLOG_BUILD_DIR="${LIB_BUILD_DIR}/logging/zlog"
ZLOG_INC_DIR="${GIT_SRC_DIR}/logging/inc"

# Cross-compiler from Yocto
CROSS_COMPILE="aarch64-poky-linux-"
CC="${YOCTO_BUILD_DIR}/tmp/work/cortexa72-poky-linux/azure-device-update/1.1+git/recipe-sysroot-native/usr/bin/aarch64-poky-linux/aarch64-poky-linux-gcc"
CFLAGS="-mcpu=cortex-a72+crc -mbranch-protection=standard -fstack-protector-strong -O2 -D_FORTIFY_SOURCE=2 -Wformat -Wformat-security -Werror=format-security --sysroot=${SYSROOT}"

# Lib paths
SDK_LIB="${SDK_BUILD_DIR}/libaducsdk.a"
ZLOG_LIB="${ZLOG_BUILD_DIR}/libzlog.a"

echo "=== Building status_monitor for ARM64 ==="
echo "Using cross-compiler: ${CC}"
echo "SDK library: ${SDK_LIB}"
echo "SDK include: ${SDK_INC_DIR}"
echo "ZLOG library: ${ZLOG_BUILD_DIR}/libzlog.a"
echo ""

# Check if SDK lib exists
if [ ! -f "${SDK_LIB}" ]; then
    echo "ERROR: SDK library not found at ${SDK_LIB}"
    exit 1
fi

# Check if SDK header exists
if [ ! -f "${SDK_INC_DIR}/aduc/aducsdk.h" ]; then
    echo "ERROR: SDK header not found at ${SDK_INC_DIR}/aduc/aducsdk.h"
    exit 1
fi

# Create output directory
OUTPUT_DIR="$HOME/adu_yocto/sdk_examples"
mkdir -p ${OUTPUT_DIR}

# Build status_monitor
echo "Building status_monitor..."
${CC} ${CFLAGS} \
    -Wall -Wextra -std=c99 -g \
    -I${SDK_INC_DIR} \
    -I${ZLOG_INC_DIR} \
    -o ${OUTPUT_DIR}/status_monitor \
    ${SDK_SRC_DIR}/status_monitor.c \
    ${SDK_LIB} \
    ${ZLOG_LIB}

echo ""
echo "Build successful!"
echo "Output: ${OUTPUT_DIR}/status_monitor"
echo ""
echo "To verify it's ARM64:"
file ${OUTPUT_DIR}/status_monitor
echo ""
echo "To copy to Raspberry Pi:"
echo "scp ${OUTPUT_DIR}/status_monitor root@<rpi-ip>:/usr/local/bin/"

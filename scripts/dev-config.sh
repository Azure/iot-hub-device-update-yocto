#!/bin/bash
# Developer-specific build configuration
# Customize this file for your environment
# Add scripts/dev-config.sh to .gitignore so it stays local
# Template: yocto/config-templates/dev-config.sh.template

# Local source directories (required if using --local-sources)
export ADU_LOCAL_SOURCE_DIR=~/adu_yocto/sources/iot-hub-device-update
export ADU_DELTA_LOCAL_SOURCE_DIR=~/adu_yocto/sources/iot-hub-device-update-delta

# Build output directory
export ADU_BUILD_OUTPUT_DIR=~/adu_yocto/out/build

# Build parallelism
export ADU_BUILD_JOBS=6
export ADU_PARALLEL_MAKE=6

# Import manifest customization
export ADU_DELTA_TEST_IMPORTMANIFEST_UPDATE_ID_PROVIDER="contoso"
export ADU_DELTA_TEST_IMPORTMANIFEST_UPDATE_ID_NAME="adu-yocto-rpi4-poc-1"
export ADU_DELTA_TEST_IMPORTMANIFEST_COMPAT_MANUFACTURER="contoso"
export ADU_DELTA_TEST_IMPORTMANIFEST_COMPAT_MODEL="adu-yocto-rpi4-poc-1"

# Optional: Set your Azure IoT Hub connection string for testing
# export ADUC_IOTHUB_CONNECTION_STRING="your-connection-string-here"

echo "✓ Developer config loaded:"
echo "  Build output: $ADU_BUILD_OUTPUT_DIR"
echo "  Jobs: $ADU_BUILD_JOBS / Parallel make: $ADU_PARALLEL_MAKE"
echo "  Provider: $ADU_DELTA_TEST_IMPORTMANIFEST_UPDATE_ID_PROVIDER"
echo "  Name: $ADU_DELTA_TEST_IMPORTMANIFEST_UPDATE_ID_NAME"

#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR=$SCRIPT_DIR/..

print_help()
{
    echo "Usage: build.sh [options...]"
    echo "-c, --clean                   Execute a (somewhat) clean build."
    echo "-t, --type <build_type>       The type of build to produce. Passed to CMAKE_BUILD_TYPE."
    echo "                              Options are Debug, Release, RelWithDebInfo, MinSizeRel. Default is Debug."
    echo ""
    echo "--rebuild                     Execute a full rebuild from scratch. The build will take around 7 hours."
    echo "-b, --adu-branch <branch>     Sets the ADU client branch to build. Default is master."
    echo "--adu-uri <uri>               Sets the URI for the ADU client repo. Useful to build ADUC source from local path."
    echo "--do-uri <uri>                Sets the URI for the DO client repo. Useful to build DO source from local path."
    echo "--adu-delta-uri <uri>         Sets the URI for the AzureDeviceUpdateDiffs (FIT) repo. Useful to build FIT source from local path."
    echo "-v, --version <sw_version>    Sets the software version of this build. This version is baked into the image."
    echo "--core-image-only             Build the core-image only."
    echo "--aziot-c-sdk-only            Build Azure IoT C SDK only."
    echo "--adu-delta-only              Build Azure Device Update Delta library only."
    echo "-o, --out-dir <build_dir>     Set the build output directory. Default is build."
    echo ""
    echo "-p, --private-preview         Build private preview version (use docs before renamed to deliveryoptimization-agent."
    echo ""
    echo "-h, --help                    Show this help message."
}

# Defaults
ADUC_GIT_BRANCH=master
BUILD_DIR=$ROOT_DIR/build
CLEAN=false
BUILD_TYPE=Debug
REBUILD=false
BUILD_CORE_IMAGE_ONLY=0
BUILD_AZIOT_C_SDK_ONLY=0
BUILD_ADU_DELTA_ONLY=0
SET_ENV_ONLY=0

while [[ $1 != "" ]]; do
    case $1 in
    -h | --help)
        print_help
        exit 0
        ;;
    -b | --adu-branch)
        shift
        ADUC_GIT_BRANCH=$1
        ;;
    --adu-uri)
        shift
        ADUC_SRC_URI=$1
        ;;
    --do-uri)
        shift
        DO_SRC_URI=$1
        ;;
    --adu-delta-uri)
        shift
        ADUC_DELTA_SRC_URI=$1
        ;;
    --core-image-only)
        BUILD_CORE_IMAGE_ONLY=1
        ;;
    --aziot-c-sdk-only)
        BUILD_AZIOT_C_SDK_ONLY=1
        ;;
    --adu-delta-only)
        echo "build ADU Delta lib only..."
        BUILD_ADU_DELTA_ONLY=1
        ;;
    --set-env-only)
        SET_ENV_ONLY=1
        ;;
    -v | --version)
        shift
        VERSION=$1
        ;;
    -c | --clean)
        CLEAN=true
        ;;
    -t | --type)
        shift
        BUILD_TYPE=$1
        ;;
    --rebuild)
        REBUILD=true
        ;;
    -o | --out-dir)
        shift
        BUILD_DIR=$1
        ;;
    -p | --private-preview)
        shift
        PRIVATE_PREVIEW=true
        ;;
    *)
        print_help
        exit 1
        ;;
    esac
    shift
done

export MACHINE=raspberrypi3
export TEMPLATECONF=$ROOT_DIR/yocto/config-templates/$MACHINE
export ADUC_GIT_BRANCH
export BUILD_TYPE

if [ -n "${ADUC_SRC_URI}" ]; then
    export ADUC_SRC_URI
fi

if [ -n "${DO_SRC_URI}" ]; then
    export DO_SRC_URI
fi

if [ -n "${ADUC_DELTA_SRC_URI}" ]; then
    export ADUC_DELTA_SRC_URI
fi

if [ -n "${VERSION}" ]; then
    export ADU_SOFTWARE_VERSION=$VERSION
fi

ADUC_KEY_DIR=$(realpath $SCRIPT_DIR/../keys)
export ADUC_PRIVATE_KEY=$ADUC_KEY_DIR/priv.pem
export ADUC_PRIVATE_KEY_PASSWORD=$ADUC_KEY_DIR/priv.pass

# Remove the conf dir before sourcing oe-init-build-env
if [[ $CLEAN == "true" ]]; then
    rm -rf $BUILD_DIR/conf
fi

# Remove all build output files for a full rebuild.
if [[ $REBUILD == "true" ]]; then
    rm -rf $BUILD_DIR/*
fi

export SSTATE_DIR=$BUILD_DIR/sstate-cache

# We need to tell bitbake about any env vars it should read in.
export BB_ENV_EXTRAWHITE="$BB_ENV_EXTRAWHITE ADUC_GIT_BRANCH ADUC_SRC_URI DO_SRC_URI ADUC_DELTA_SRC_URI BUILD_TYPE ADU_SOFTWARE_VERSION ADUC_PRIVATE_KEY ADUC_PRIVATE_KEY_PASSWORD SSTATE_DIR"
source $ROOT_DIR/yocto/poky/oe-init-build-env $BUILD_DIR

if [[ $BUILD_CORE_IMAGE_ONLY == 1 ]]; then
    bitbake \
        core-image-full-cmdline \
        core-image-minimal
elif [[ $BUILD_AZIOT_C_SDK_ONLY == 1 ]]; then
    bitbake azure-iot-sdk-c
elif [[ $BUILD_ADU_DELTA_ONLY == 1 ]]; then
    bitbake -c clean -C compile -f azure-device-update-diffs
else
    if [[ $CLEAN == "true" ]]; then
        bitbake -c clean -f \
            azure-device-update \
            adu-agent-service \
            azure-iot-sdk-c \
            deliveryoptimization-agent \
            deliveryoptimization-agent-service \
            swupdate \
            core-image-full-cmdline \
            core-image-minimal

        bitbake -c clean -f \
            adu-base-image \
            adu-update-image
    fi

    bitbake adu-update-image
fi

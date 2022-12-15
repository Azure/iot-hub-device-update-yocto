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
    echo ""
    echo "--adu-git-branch <branch>        Sets the ADU client branch to build. Default is main."
    echo "--adu-src-uri <uri>              Sets the URI for the ADU client repo. Useful to build ADUC source from local path."
    echo "--adu-git-commit <commit hash>   Sets the commit hash for the ADU client repo. Useful to build ADUC source from local path."
    echo "--do-git-branch <branch>         Sets the DL client branch to build. Default is main."
    echo "--do-src-uri <uri>               Sets the URI for the DO client repo. Useful to build DO source from local path."
    echo "--do-git-commit <commit hash>    Sets the commit hash for the DO client repo. Useful to build ADUC source from local path."
    echo "--adu-delta-git-branch <branch>  Sets the ADU Delta branch to build. Default is main."
    echo "--adu-delta-src-uri <uri>        Sets the URI for the ADU Delta (FIT) repo. Useful to build FIT source from local path."
    echo "--adu-delta-git-commit <hash>    Sets the commit hash for the ADU Delta repo. Useful to build ADUC source from local path."
    echo ""
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
ADU_GIT_BRANCH=main
ADU_GIT_COMMIT=33554d29476eab2447234528c8aed186e2b6423d
ADU_SRC_URI=gitsm://github.com/Azure/iot-hub-device-update

DO_GIT_BRANCH=main
DO_GIT_COMMIT=b61de2d347c8032562056b18f90ec710e531baf8
DO_SRC_URI=gitsm://github.com/microsoft/do-client

ADU_DELTA_GIT_BRANCH=main
ADU_DELTA_GIT_COMMIT=57efe4360f52b297ae54323271c530239fb1d1c7
ADU_DELTA_SRC_URI=gitsm://github.com/Azure/iot-hub-device-update-delta

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
    --adu-git-branch)
        shift
        ADU_GIT_BRANCH=$1
        ;;
    --adu-src-uri)
        shift
        ADU_SRC_URI=$1
        ;;
    --adu-git-commit)
        shift
        ADU_GIT_COMMIT=$1
        ;;
    --do-git-branch)
        shift
        DO_GIT_BRANCH=$1
        ;;
    --do-src-uri)
        shift
        DO_SRC_URI=$1
        ;;
    --do-git-commit)
        shift
        DO_GIT_COMMIT=$1
        ;;
    --adu-delta-git-branch)
        shift
        ADU_DELTA_GIT_BRANCH=$1
        ;;
    --adu-delta-src-uri)
        shift
        ADU_DELTA_SRC_URI=$1
        ;;
    --adu-delta-git-commit)
        shift
        ADU_DELTA_GIT_COMMIT=$1
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

if [ -n "${ADU_SRC_URI}" ]; then
    export ADU_SRC_URI
fi

if [ -n "${ADU_GIT_BRANCH}" ]; then
    export ADU_GIT_BRANCH
fi

if [ -n "${ADU_GIT_COMMIT}" ]; then
    export ADU_GIT_COMMIT
fi

if [ -n "${DO_SRC_URI}" ]; then
    export DO_SRC_URI
fi

if [ -n "${DO_GIT_BRANCH}" ]; then
    export DO_GIT_BRANCH
fi

if [ -n "${DO_GIT_COMMIT}" ]; then
    export DO_GIT_COMMIT
fi

if [ -n "${ADU_DELTA_SRC_URI}" ]; then
    export ADU_DELTA_SRC_URI
fi

if [ -n "${ADU_DELTA_GIT_BRANCH}" ]; then
    export ADU_DELTA_GIT_BRANCH
fi

if [ -n "${ADU_DELTA_GIT_COMMIT}" ]; then
    export ADU_DELTA_GIT_COMMIT
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
export BB_ENV_EXTRAWHITE="$BB_ENV_EXTRAWHITE ADU_GIT_BRANCH ADU_SRC_URI ADU_GIT_COMMIT DO_GIT_BRANCH DO_SRC_URI DO_GIT_COMMIT ADU_DELTA_GIT_BRANCH ADU_DELTA_SRC_URI ADU_DELTA_GIT_COMMIT BUILD_TYPE ADU_SOFTWARE_VERSION ADUC_PRIVATE_KEY ADUC_PRIVATE_KEY_PASSWORD SSTATE_DIR"
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

#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR=$SCRIPT_DIR/../yocto/

print_help()
{
    cat << ENDOFUSAGE
Usage: build.sh [options...]
    -c, --clean                      Clean build.
    -t, --type <build_type>          CMAKE_BUILD_TYPE
                                     Options are Debug, Release, RelWithDebInfo, MinSizeRel. Default is Debug.
    --rebuild                        Execute a full rebuild

    --adu-generation                 The device update agent. Options are 1 and 2. Default is 1.

    --adu-git-branch <branch>        Set the ADU Client (ADUC) branch to build. Default is 'develop'.
    --adu-src-uri <uri>              Set the URI for the ADUC repo.
    --adu-git-commit <commit hash>   Set the commit hash for the ADUC repo.
    --do-git-branch <branch>         Set the DO client branch to build. Default is main.
    --do-src-uri <uri>               Set the URI for the DO client repo.
    --do-git-commit <commit hash>    Set the commit hash for the DO client repo.

    --with-delta-update '1'|'0'      Allows enabling and disabling delta recipe. Default is '0' to disable.
    --adu-delta-git-branch <branch>  Set the ADU Delta branch to build. Default is main.
    --adu-delta-src-uri <uri>        Set the URI for the ADU Delta (FIT) repo.
    --adu-delta-git-commit <hash>    Set the commit hash for the ADU Delta repo.

    -v, --version <sw_version>       Set the software version of this build that is baked into the image.

    --core-image-only                Build the core-image only.
    --aziot-c-sdk-only               Build Azure IoT C SDK only.
    --adu-delta-only                 Build Azure Device Update Delta library only.

    -o, --out-dir <build_dir>        Set the build output directory. Default is build.

    -h, --help                       Show this help message.
ENDOFUSAGE
}

# Defaults - Gen 1
ADU_GIT_BRANCH='develop'
ADU_SRC_URI='https://github.com/Azure/iot-hub-device-update'
SRC_URI="${ADU_SRC_URI};protocol=https;branch=${ADU_GIT_BRANCH}"
ADU_GIT_COMMIT='350a551dd9d3f5639eddceb75ef5b10e834865fe'
BUILD_TYPE='Debug'
WITH_FEATURE_DELTA_UPDATE='0'

# Example - Gen 2 to use via cmdline args such as:
#   --adu-generation 2
# with:
#   --adu-git-branch
#   --adu-src-uri
#   -- adu-git-commit
# ADU_GIT_BRANCH='main'
# ADU_SRC_URI='git://github.com/Azure/device-update'
# SRC_URI="${ADU_SRC_URI};protocol=https;branch=${ADU_GIT_BRANCH}"
# ADU_GIT_COMMIT='e981f7a9af5f561f98a3be9ea9563f4d0f256e63'
# BUILD_TYPE='Debug'
# WITH_FEATURE_DELTA_UPDATE='0'

# Defaults - Gen 1 and Gen 2
ADU_DELTA_GIT_BRANCH='main'
ADU_DELTA_GIT_COMMIT='57efe4360f52b297ae54323271c530239fb1d1c7'
ADU_DELTA_SRC_URI='gitsm://github.com/Azure/iot-hub-device-update-delta'

# vars for cmdline arg parsing
BUILD_DIR=$ROOT_DIR/build
CLEAN=false
BUILD_TYPE=Debug
REBUILD=false
BUILD_CORE_IMAGE_ONLY=0
BUILD_AZIOT_C_SDK_ONLY=0
BUILD_ADU_DELTA_ONLY=0
ADU_GEN=1
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
        echo 'build ADU Delta lib only...'
        BUILD_ADU_DELTA_ONLY=1
        ;;
    --adu-generation)
        shift
        ADU_GEN="$1"
        if [[ $ADU_GEN != '1' && $ADU_GEN != '2' ]]; then
            echo "Invalid --adu-generation value: $ADU_GEN" >&2
            exit 1
        fi
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
    *)
        print_help
        exit 1
        ;;
    esac
    shift
done

export MACHINE='raspberrypi4-64'
export ADU_GENERATION="$ADU_GEN"

# Need to work on what this is
export TEMPLATECONF=$ROOT_DIR/meta-raspberrypi-adu/conf/templates/$MACHINE/

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

# Remove all build output files for a full rebuild.
if [[ $REBUILD == 'true' ]]; then
    rm -rf $BUILD_DIR/*
fi

export SSTATE_DIR=$BUILD_DIR/sstate-cache

# export TOP_DIR=$ROOT_DIR/yocto
# We need to tell bitbake about any env vars it should read in.
export BB_ENV_PASSTHROUGH_ADDITIONS="$BB_ENV_PASSTHROUGH_ADDITIONS ADU_GIT_BRANCH ADU_SRC_URI ADU_GIT_COMMIT DO_GIT_BRANCH DO_SRC_URI DO_GIT_COMMIT ADU_DELTA_GIT_BRANCH ADU_DELTA_SRC_URI ADU_DELTA_GIT_COMMIT BUILD_TYPE ADU_SOFTWARE_VERSION ADUC_PRIVATE_KEY ADUC_PRIVATE_KEY_PASSWORD SSTATE_DIR"
source $ROOT_DIR/poky/oe-init-build-env $BUILD_DIR

if [[ $BUILD_CORE_IMAGE_ONLY == 1 ]]; then
    bitbake \
        core-image-full-cmdline \
        core-image-minimal
elif [[ $BUILD_AZIOT_C_SDK_ONLY == 1 ]]; then
    bitbake azure-iot-sdk-c
elif [[ $BUILD_ADU_DELTA_ONLY == 1 ]]; then
    bitbake -c clean -C compile -f azure-device-update-diffs
else
    if [[ $CLEAN == 'true' ]]; then
        bitbake -c cleanall  -f \
            azure-device-update \
            adu-agent-service \
            azure-iot-sdk-c \
            deliveryoptimization-agent \
            deliveryoptimization-agent-service \
            swupdate \
            core-image-full-cmdline \
            core-image-minimal 

        bitbake -c cleanall  -f \
            adu-base-image \
            adu-update-image
    fi

    #bitbake -D adu-update-image
    bitbake adu-update-image
fi

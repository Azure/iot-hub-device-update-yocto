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
    --adu-key-dir <dir>              Set the directory where the ADU keys are stored. Default is \$SCRIPT_DIR/../keys.
    --adu-use-test-root-keys         Use test root keys instead of prod root keys and enable e2e testing.
    
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
    --clean-fetch-recipe <recipe>    Does bitbake -c cleanall <recipe>; bitbake -c fetch <recipe> -v
                                     e.g. --clean-fetch-recipe azure-device-update

    -o, --out-dir <build_dir>        Set the build output directory. Default is build.
    --verbose                        Add -v to bitbake cmdline for verbose output.

    -h, --help                       Show this help message.
ENDOFUSAGE
}

# Defaults - Gen 1
ADU_GIT_BRANCH='develop'
ADU_SRC_URI='git://github.com/Azure/iot-hub-device-update'
ADU_GIT_COMMIT='370da9993c2391be4c80f0698522572aa5ad3b2d'
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
CLEAN_FETCH_RECIPE=''
ADU_GEN=1
VERBOSE=''
SET_ENV_ONLY=0
ADUC_KEY_DIR=''
ADUC_PUBLIC_KEY=''

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
    --adu-use-test-root-keys)
        shift
        ADU_USE_TEST_ROOT_KEYS=$1
        echo -e "ADU_EMBED_TEST_ROOT_KEYS:$ADU_USE_TEST_ROOT_KEYS"
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
    --clean-fetch-recipe)
        shift
        CLEAN_FETCH_RECIPE="$1"
        echo "debugging fetch of recipe '${FETCH_RECIPE}' ..."
        ;;
    --adu-key-dir)
        shift
        ADUC_KEY_DIR=$1
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
        echo "Using VERSION -> $VERSION ..."
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
    --verbose)
        VERBOSE='-v'
        ;;
    *)
        echo "Unknown option: $1" >&2
        print_help
        exit 1
        ;;
    esac
    shift
done

export MACHINE='raspberrypi4-64'
export ADU_GENERATION="$ADU_GEN"
export ADUC_USE_TEST_ROOT_KEYS="$ADU_USE_TEST_ROOT_KEYS"


# Need to work on what this is
export TEMPLATECONF=$ROOT_DIR/meta-raspberrypi-adu/conf/templates/$MACHINE/

if [ -n "${ADU_SRC_URI}" ]; then
    export ADU_SRC_URI
fi

if [ -n "${ADU_GIT_BRANCH}" ]; then
    export ADU_GIT_BRANCH
fi

# if ADU_GIT_COMMIT is not set and not equal "AUTOREV", then use the latest commit
if [ "${ADU_GIT_COMMIT}" = "AUTOREV" ]; then
    echo "ADU_GIT_COMMIT is set to AUTOREV, using latest commit."
    export ADU_GIT_COMMIT=""
elif [ -z "${ADU_GIT_COMMIT}" ]; then
    export ADU_GIT_COMMIT
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

# Set ADUC_KEY_DIR to the directory where the keys are stored, if not set.
if [ -z "${ADUC_KEY_DIR}" ]; then
    echo "ADUC_KEY_DIR not set. Using default directory."
    ADUC_KEY_DIR=$(realpath $SCRIPT_DIR/../keys)
else
    echo "ADUC_KEY_DIR set to $ADUC_KEY_DIR"
fi

# Check if ADUC_KEY_DIR exists, if not, exit.
if [ ! -d "$ADUC_KEY_DIR" ]; then
    echo "ADUC_KEY_DIR does not exist: $ADUC_KEY_DIR"
    exit 1
else
    echo "ADU_KEY_DIR contains:"
    ls -l $ADUC_KEY_DIR
fi

# By convension, if public.pem exists in the ADUC_KEY_DIR, then use it.
# This is to avoid using the private key for signing.
if [ -f "$ADUC_KEY_DIR/public.pem" ]; then
    echo "Using public key from $ADUC_KEY_DIR"
    export ADUC_PUBLIC_KEY=$ADUC_KEY_DIR/public.pem
else
    echo "Public key not found in $ADUC_KEY_DIR. Using private key instead."
fi

# Check if ADUC_PUBLIC_KEY is set and exists, if not, make sure that private key is set.
if [ -z "$ADUC_PUBLIC_KEY" ] || [ ! -f "$ADUC_PUBLIC_KEY" ]; then
    export ADUC_PUBLIC_KEY=''
    export ADUC_PRIVATE_KEY=$ADUC_KEY_DIR/priv.pem
    export ADUC_PRIVATE_KEY_PASSWORD=$ADUC_KEY_DIR/priv.pass

    if (( [ -z "$ADUC_PRIVATE_KEY" ] || [ ! -f "$ADUC_PRIVATE_KEY" ] ) || \
        ( [ -z "$ADUC_PRIVATE_KEY_PASSWORD" ] || [ ! -f "$ADUC_PRIVATE_KEY_PASSWORD" ] ) ); then
        echo "ADUC_PRIVATE_KEY or ADUC_PRIVATE_KEY_PASSWORD not set or not found."
        exit 1
    fi
fi

# Remove all build output files for a full rebuild.
if [[ $REBUILD == 'true' ]]; then
    rm -rf $BUILD_DIR/*
fi

export SSTATE_DIR=$BUILD_DIR/sstate-cache

# export TOP_DIR=$ROOT_DIR/yocto
# We need to tell bitbake about any env vars it should read in.
export BB_ENV_PASSTHROUGH_ADDITIONS="$BB_ENV_PASSTHROUGH_ADDITIONS ADUC_USE_TEST_ROOT_KEYS ADU_GENERATION ADU_GIT_BRANCH ADU_SRC_URI ADU_GIT_COMMIT DO_GIT_BRANCH DO_SRC_URI DO_GIT_COMMIT ADU_DELTA_GIT_BRANCH ADU_DELTA_SRC_URI ADU_DELTA_GIT_COMMIT BUILD_TYPE ADU_SOFTWARE_VERSION ADUC_PUBLIC_KEY ADUC_PRIVATE_KEY ADUC_PRIVATE_KEY_PASSWORD SSTATE_DIR"
source $ROOT_DIR/poky/oe-init-build-env $BUILD_DIR

if [[ $CLEAN_FETCH_RECIPE != '' ]]; then
    bitbake $VERBOSE -c cleanall "$CLEAN_FETCH_RECIPE"
    bitbake $VERBOSE -c fetch "$CLEAN_FETCH_RECIPE"
elif [[ $BUILD_CORE_IMAGE_ONLY == 1 ]]; then
    bitbake $VERBOSE \
        core-image-full-cmdline \
        core-image-minimal
elif [[ $BUILD_AZIOT_C_SDK_ONLY == 1 ]]; then
    bitbake $VERBOSE azure-iot-sdk-c
elif [[ $BUILD_ADU_DELTA_ONLY == 1 ]]; then
    bitbake $VERBOSE -c clean -C compile -f azure-device-update-diffs
else
    if [[ $CLEAN == 'true' ]]; then
        bitbake $VERBOSE -c cleanall  -f \
            azure-device-update \
            adu-agent-service \
            azure-iot-sdk-c \
            deliveryoptimization-agent \
            deliveryoptimization-agent-service \
            swupdate \
            core-image-full-cmdline \
            core-image-minimal 

        bitbake $VERBOSE -c cleanall  -f \
            adu-base-image \
            adu-update-image
    fi

    bitbake $VERBOSE adu-update-image
fi

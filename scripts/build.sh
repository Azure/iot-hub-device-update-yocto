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
    --adu-embed-test-root-keys       Use test root keys instead of production root keys and enable e2e testing.
    
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

    --clean-sstate <recipe>          Cleans the SState Cache for the given recipe.
                                     Clean just ADU:
                                         ./scripts/build.sh --clean-sstate azure-device-update
                                     e.g. To also clean delta update sstate cache entries use:
                                         ./scripts/build.sh --clean-sstate azure-device-update azure-device-update-diffs

    --show-recipes                   Runs bitbake-layers show-recipes.
                                     e.g. script.sh --show-recipes | grep -i azure

    -o, --out-dir <build_dir>        Set the build output directory. Default is build.
    --verbose                        Add -v to bitbake cmdline for verbose output.
    
    -j, --jobs <number>              Number of parallel tasks BitBake should run. Default is number of CPU cores.
    --parallel-make <number>         Number of processes 'make' should run in parallel. Default is number of CPU cores.

    -h, --help                       Show this help message.
ENDOFUSAGE
}

# Defaults - Gen 1
ADU_GIT_BRANCH='develop'
ADU_SRC_URI='git://github.com/Azure/iot-hub-device-update'
ADU_GIT_COMMIT=''
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
ADU_EMBED_TEST_ROOT_KEYS=0
CLEAN_SSTATE_RECIPE_NAME=''
SHOW_RECIPES=0
BB_NUMBER_THREADS=''
PARALLEL_MAKE=''

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
    --adu-embed-test-root-keys)
        shift
        ADU_EMBED_TEST_ROOT_KEYS =$1
        echo -e "ADU_EMBED_TEST_ROOT_KEYS:$ADU_EMBED_TEST_ROOT_KEYS "
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
    --clean-sstate)
        shift
        CLEAN_SSTATE_RECIPE_NAME="$1"
        ;;
    --show-recipes)
        SHOW_RECIPES=1
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
    -j | --jobs)
        shift
        BB_NUMBER_THREADS="$1"
        ;;
    --parallel-make)
        shift
        PARALLEL_MAKE="$1"
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
export ADU_EMBED_TEST_ROOT_KEYS="$ADU_EMBED_TEST_ROOT_KEYS"

# Need to work on what this is
export TEMPLATECONF=$ROOT_DIR/meta-raspberrypi-adu/conf/templates/$MACHINE/

if [ -n "${ADU_SRC_URI}" ]; then
    export ADU_SRC_URI
fi

if [ -n "${ADU_GIT_BRANCH}" ]; then
    export ADU_GIT_BRANCH
fi

# if ADU_GIT_COMMIT is not set and not equal "AUTOREV", then fetch the HEAD commit of the branch
if [ "${ADU_GIT_COMMIT}" = "AUTOREV" ]; then
    echo "ADU_GIT_COMMIT is set to AUTOREV, using latest commit."
    export ADU_GIT_COMMIT=""
elif [ -z "${ADU_GIT_COMMIT}" ]; then
    echo "ADU_GIT_COMMIT not set, fetching HEAD commit hash for branch '${ADU_GIT_BRANCH}'..."
    
    # Validate ADU_SRC_URI is set
    if [ -z "${ADU_SRC_URI}" ]; then
        echo "ERROR: ADU_SRC_URI is not set. Cannot fetch commit hash."
        exit 1
    fi
    
    # Extract repo URL and convert to HTTPS format for git ls-remote
    # Handle git://, https://, and http:// protocols
    REPO_URL="${ADU_SRC_URI}"
    if [[ "${REPO_URL}" == git://* ]]; then
        REPO_URL="https://${REPO_URL#git://}"
    elif [[ "${REPO_URL}" == http://* ]]; then
        REPO_URL="https://${REPO_URL#http://}"
    fi
    
    # Validate the URL format
    if [[ ! "${REPO_URL}" =~ ^https://[a-zA-Z0-9.-]+/[a-zA-Z0-9._/-]+$ ]]; then
        echo "ERROR: Invalid repository URL format: ${ADU_SRC_URI}"
        echo "Expected format: git://github.com/owner/repo or https://github.com/owner/repo"
        exit 1
    fi
    
    echo "Fetching from: ${REPO_URL}"
    
    # Fetch the commit hash for the specified branch
    ADU_GIT_COMMIT=$(git ls-remote "${REPO_URL}" "refs/heads/${ADU_GIT_BRANCH}" 2>&1 | grep -v "^fatal:" | cut -f1)
    
    if [ -z "${ADU_GIT_COMMIT}" ]; then
        echo "ERROR: Failed to fetch commit hash for branch '${ADU_GIT_BRANCH}' from ${REPO_URL}"
        echo "Please check that:"
        echo "  1. The repository URL is correct and accessible"
        echo "  2. The branch '${ADU_GIT_BRANCH}' exists"
        echo "  3. You have network connectivity"
        echo "Alternatively, specify --adu-git-commit manually."
        exit 1
    fi
    
    echo "✓ Using ADU_GIT_COMMIT: ${ADU_GIT_COMMIT} (HEAD of branch '${ADU_GIT_BRANCH}')"
    export ADU_GIT_COMMIT
fi

if [ -n "${ADU_GIT_COMMIT}" ]; then
    echo "ADU_GIT_COMMIT is set to: ${ADU_GIT_COMMIT}"
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
fi

# Check if ADUC_PUBLIC_KEY is set and exists, if not, make sure that private key is set.
if [ -z "$ADUC_PUBLIC_KEY" ] || [ ! -f "$ADUC_PUBLIC_KEY" ]; then
    export ADUC_PUBLIC_KEY=''
fi

export ADUC_PRIVATE_KEY=$ADUC_KEY_DIR/priv.pem
export ADUC_PRIVATE_KEY_PASSWORD=$ADUC_KEY_DIR/priv.pass

if (( [ -z "$ADUC_PRIVATE_KEY" ] || [ ! -f "$ADUC_PRIVATE_KEY" ] ) || \
    ( [ -z "$ADUC_PRIVATE_KEY_PASSWORD" ] || [ ! -f "$ADUC_PRIVATE_KEY_PASSWORD" ] ) ); then
    echo "ADUC_PRIVATE_KEY or ADUC_PRIVATE_KEY_PASSWORD not set or not found."
    exit 1
fi

# Remove all build output files for a full rebuild.
# Note: We preserve the sstate-cache in a separate location to speed up rebuilds
if [[ $REBUILD == 'true' ]]; then
    echo "Performing full rebuild - removing build directory contents (preserving sstate cache)..."
    # Remove everything except sstate-cache if it exists
    find $BUILD_DIR -mindepth 1 -maxdepth 1 ! -name 'sstate-cache' -exec rm -rf {} + 2>/dev/null || true
fi

# Use persistent sstate cache location outside the tmp build directory
# This allows the cache to survive full rebuilds
export SSTATE_DIR=$BUILD_DIR/sstate-cache
mkdir -p $SSTATE_DIR
echo "Using SSTATE_DIR: $SSTATE_DIR"

# Set parallel build options for faster builds
# BB_NUMBER_THREADS: Number of parallel BitBake tasks
# PARALLEL_MAKE: Number of processes make should run in parallel (e.g., -j 8)
NPROC=$(nproc 2>/dev/null || echo "4")

if [ -z "${BB_NUMBER_THREADS}" ]; then
    BB_NUMBER_THREADS="${NPROC}"
fi

if [ -z "${PARALLEL_MAKE}" ]; then
    PARALLEL_MAKE="${NPROC}"
fi

export BB_NUMBER_THREADS
export PARALLEL_MAKE="-j ${PARALLEL_MAKE}"

echo "Parallel build settings:"
echo "  BB_NUMBER_THREADS: ${BB_NUMBER_THREADS} (BitBake parallel tasks)"
echo "  PARALLEL_MAKE: ${PARALLEL_MAKE} (make parallel processes)"

# export TOP_DIR=$ROOT_DIR/yocto
# We need to tell bitbake about any env vars it should read in.
export BB_ENV_PASSTHROUGH_ADDITIONS="$BB_ENV_PASSTHROUGH_ADDITIONS ADUC_USE_TEST_ROOT_KEYS ADU_GENERATION ADU_GIT_BRANCH ADU_SRC_URI ADU_GIT_COMMIT DO_GIT_BRANCH DO_SRC_URI DO_GIT_COMMIT ADU_DELTA_GIT_BRANCH ADU_DELTA_SRC_URI ADU_DELTA_GIT_COMMIT BUILD_TYPE ADU_SOFTWARE_VERSION ADUC_PUBLIC_KEY ADUC_PRIVATE_KEY ADUC_PRIVATE_KEY_PASSWORD SSTATE_DIR BB_NUMBER_THREADS PARALLEL_MAKE"
source $ROOT_DIR/poky/oe-init-build-env $BUILD_DIR

if [[ $SHOW_RECIPES == 1 ]]; then
    bitbake-layers show-recipes
elif [[ $CLEAN_SSTATE_RECIPE_NAME != '' ]]; then
    echo -e "\nCleaning SSTATE Cache for Recipe '$CLEAN_SSTATE_RECIPE_NAME' ..."
    bitbake -c cleansstate "$CLEAN_SSTATE_RECIPE_NAME"
elif [[ $CLEAN_FETCH_RECIPE != '' ]]; then
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

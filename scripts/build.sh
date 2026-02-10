#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR=$SCRIPT_DIR/../yocto/

print_help()
{
    cat << ENDOFUSAGE
Usage: build.sh [options...]
    -c, --clean                      Clean build.
    --clean [recipe1,recipe2,...]    Clean specific recipes only (comma-separated, no spaces).
                                     Examples:
                                       --clean azure-device-update,azure-sdk-for-cpp
                                       --clean adu-delta-image
                                       --clean adu-update-image-v1,adu-update-image-v2
                                     If no recipes specified, does full clean.
    -t, --type <build_type>          CMAKE_BUILD_TYPE
                                     Options are Debug, Release, RelWithDebInfo, MinSizeRel. Default is Debug.
    --rebuild                        Execute a full rebuild
    --rebuild [recipe1,recipe2,...]  Clean and rebuild specific recipes (comma-separated, no spaces).
                                     Examples:
                                       --rebuild azure-device-update,azure-sdk-for-cpp
                                       --rebuild adu-config-setup
                                       --rebuild adu-base-image  (clean and rebuild base image)
                                     If no recipes specified, does full rebuild.
    --build [target1,target2,...]    Build specific BitBake targets without cleaning (comma-separated, no spaces).
                                     Examples:
                                       --build adu-base-image  (build base image only)
                                       --build azure-device-update,adu-base-image
                                       --build adu-update-image-v1,adu-update-image-v2
                                       --build azure-iot-sdk-c  (build Azure IoT C SDK only)
                                       --build azure-device-update-diffs  (build delta library only)
                                       --build core-image-minimal  (build minimal core image)

    --adu-generation                 The device update agent. Options are 1 and 2. Default is 1.
    --adu-key-dir <dir>              Set the directory where the ADU keys are stored. Default is \$SCRIPT_DIR/../keys.
    --adu-embed-test-root-keys       Use test root keys instead of production root keys and enable e2e testing.

    --adu-git-branch <branch>        Set the ADU Client (ADUC) branch to build. Default is 'develop'.
    --adu-src-uri <uri>              Set the URI for the ADUC repo.
    --adu-git-commit <commit hash>   Set the commit hash for the ADUC repo.
    --local-sources <repos>          Use local source directories instead of fetching from GitHub.
                                     Comma-separated list of: ADU, ADU_DELTA, DO, AZIOT_SDK_C
                                     Examples:
                                       --local-sources ADU
                                       --local-sources ADU,DO
                                       --local-sources ADU,ADU_DELTA,DO,AZIOT_SDK_C
                                     Default paths:
                                       ADU         = ~/adu_yocto/sources/iot-hub-device-update
                                       ADU_DELTA   = ~/adu_yocto/sources/iot-hub-device-update-delta
                                       DO          = ~/adu_yocto/sources/do-client
                                       AZIOT_SDK_C = ~/adu_yocto/sources/azure-iot-sdk-c
                                     Override with environment variables:
                                       ADU_LOCAL_SOURCE_DIR, ADU_DELTA_LOCAL_SOURCE_DIR,
                                       DO_LOCAL_SOURCE_DIR, AZIOT_SDK_C_LOCAL_SOURCE_DIR
                                     Note: Patches from meta-layer will NOT be applied to local source.
    --do-git-branch <branch>         Set the DO client branch to build. Default is main.
    --do-src-uri <uri>               Set the URI for the DO client repo.
    --do-git-commit <commit hash>    Set the commit hash for the DO client repo.

    --with-delta-update '1'|'0'      Allows enabling and disabling delta recipe. Default is '1' to enable.
    --adu-delta-git-branch <branch>  Set the ADU Delta branch to build. Default is v2/scarthgap.
    --enable-wifi-bluetooth          Enable WiFi/Bluetooth support (requires accepting proprietary BCM43455 firmware license).
    --build-uboot-debug-script       Build and deploy debug version of U-Boot boot script (boot.scr.debug).
                                     Provides verbose logging for troubleshooting boot issues.
    --root-password <password>       Set root password (plaintext, will be SHA512 encrypted).
    --root-password-sha512 <hash>    Set root password using pre-encrypted SHA512 hash.
                                     If both specified, --root-password-sha512 takes precedence.
    --adu-delta-src-uri <uri>        Set the URI for the ADU Delta (FIT) repo.
    --adu-delta-git-commit <hash>    Set the commit hash for the ADU Delta repo.
    --adu-delta-local-src <path>     Use local source directory for ADU Delta (for development).
                                     If directory doesn't exist, will clone from git.
                                     Example: --adu-delta-local-src \$BUILD_DIR/../sources/iot-hub-device-update-delta
    --adu-delta-skip-patches         Skip applying patches when using local source (useful for active development).
                                     Only effective with --adu-delta-local-src.

    -v, --version <sw_version>       Set the software version of this build that is baked into the image.

    --build-uboot-only               Build only U-Boot boot scripts (normal and debug versions).
                                     Useful for quickly testing boot script changes.
    --clean-fetch-recipe <recipe>    Does bitbake -c cleanall <recipe>; bitbake -c fetch <recipe> -v
                                     e.g. --clean-fetch-recipe azure-device-update

    --clean-sstate <recipe>          Cleans the SState Cache for the given recipe.
                                     Clean just ADU:
                                         ./scripts/build.sh --clean-sstate azure-device-update
                                     e.g. To also clean delta update sstate cache entries use:
                                         ./scripts/build.sh --clean-sstate azure-device-update azure-device-update-diffs

    --show-recipes                   Runs bitbake-layers show-recipes.
                                     e.g. script.sh --show-recipes | grep -i azure

    --nuget-source <source>          Set NuGet package source for diffgentool build.
                                     Options:
                                       microsoft-internal  - Use Microsoft internal ADU-Diffs feed
                                       nuget-org          - Use public nuget.org (default)
                                       <custom-url>       - Use custom NuGet feed URL
                                     Example: --nuget-source microsoft-internal

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
WITH_FEATURE_DELTA_UPDATE='1'

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
ADU_DELTA_GIT_BRANCH='user/nox-msft/scarthgap'
ADU_DELTA_GIT_COMMIT=''
ADU_DELTA_SRC_URI='gitsm://github.com/Azure/iot-hub-device-update-delta'
ADU_DELTA_LOCAL_SRC=''
ADU_DELTA_SKIP_PATCHES='0'

# WiFi/Bluetooth support (disabled by default due to proprietary license)
ENABLE_WIFI_BLUETOOTH='0'

# U-Boot debug script (disabled by default)
BUILD_UBOOT_DEBUG_SCRIPT='0'

# Root password (empty by default - no password change)
ROOT_PASSWORD=''
ROOT_PASSWORD_SHA512=''

# NuGet source (empty by default - uses nuget.org)
NUGET_SOURCE=''

# vars for cmdline arg parsing
BUILD_DIR=$ROOT_DIR/build
CLEAN=false
CLEAN_RECIPES=''
BUILD_TYPE=Debug
REBUILD=false
REBUILD_RECIPES=''
BUILD_TARGETS=''
BUILD_UBOOT_ONLY=0
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
UNATTENDED=false

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
    --local-sources)
        shift
        LOCAL_SOURCES="$1"
        ;;
    --adu-embed-test-root-keys)
        shift
        # Accept 1/0, true/false, True/False
        case "$1" in
            1|true|True|TRUE) ADU_EMBED_TEST_ROOT_KEYS=1 ;;
            0|false|False|FALSE) ADU_EMBED_TEST_ROOT_KEYS=0 ;;
            *)
                echo "ERROR: Invalid value for --adu-embed-test-root-keys: $1"
                echo "Valid values: 1, 0, true, false"
                exit 1
                ;;
        esac
        echo "ADU_EMBED_TEST_ROOT_KEYS: $ADU_EMBED_TEST_ROOT_KEYS"
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
    --adu-delta-local-src)
        shift
        ADU_DELTA_LOCAL_SRC=$1
        ;;
    --adu-delta-skip-patches)
        ADU_DELTA_SKIP_PATCHES='1'
        ;;
    --build-uboot-only)
        BUILD_UBOOT_ONLY=1
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
    --nuget-source)
        shift
        NUGET_SOURCE="$1"
        case "$NUGET_SOURCE" in
            microsoft-internal|nuget-org)
                ;; # Valid values
            *)
                # Assume it's a custom URL
                if [[ ! "$NUGET_SOURCE" =~ ^https?:// ]]; then
                    echo "ERROR: --nuget-source must be 'microsoft-internal', 'nuget-org', or a valid https:// URL"
                    exit 1
                fi
                ;;
        esac
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
        # Check if next argument exists and doesn't start with --
        if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
            shift
            CLEAN_RECIPES="$1"
            echo "Will clean recipes: $CLEAN_RECIPES"
        else
            CLEAN=true
        fi
        ;;
    -t | --type)
        shift
        BUILD_TYPE=$1
        ;;
    --rebuild)
        # Check if next argument exists and doesn't start with --
        if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
            shift
            REBUILD_RECIPES="$1"
            echo "Will rebuild recipes: $REBUILD_RECIPES"
        else
            REBUILD=true
        fi
        ;;
    --build)
        # Check if next argument exists and doesn't start with --
        if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
            shift
            BUILD_TARGETS="$1"
            echo "Will build targets: $BUILD_TARGETS"
        else
            echo "ERROR: --build requires target list" >&2
            echo "Example: --build adu-base-image" >&2
            echo "Example: --build azure-device-update,adu-base-image" >&2
            exit 1
        fi
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
    --with-delta-update)
        shift
        WITH_FEATURE_DELTA_UPDATE="$1"
        ;;
    --enable-wifi-bluetooth)
        ENABLE_WIFI_BLUETOOTH='1'
        ;;
    --build-uboot-debug-script)
        BUILD_UBOOT_DEBUG_SCRIPT='1'
        ;;
    --root-password)
        shift
        ROOT_PASSWORD="$1"
        ;;
    --root-password-sha512)
        shift
        ROOT_PASSWORD_SHA512="$1"
        ;;
    --unattended | -y)
        UNATTENDED=true
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

# Process --local-sources argument
if [ -n "${LOCAL_SOURCES}" ]; then
    IFS=',' read -ra REPOS <<< "$LOCAL_SOURCES"
    for repo in "${REPOS[@]}"; do
        case "$repo" in
            ADU)
                USE_LOCAL_ADU_SOURCE='1'
                echo "✓ Will use local source for ADU (iot-hub-device-update)"
                ;;
            ADU_DELTA)
                USE_LOCAL_ADU_DELTA_SOURCE='1'
                echo "✓ Will use local source for ADU_DELTA (iot-hub-device-update-delta)"
                ;;
            DO)
                USE_LOCAL_DO_SOURCE='1'
                echo "✓ Will use local source for DO (do-client)"
                ;;
            AZIOT_SDK_C)
                USE_LOCAL_AZIOT_SDK_C_SOURCE='1'
                echo "✓ Will use local source for AZIOT_SDK_C (azure-iot-sdk-c)"
                ;;
            *)
                echo "ERROR: Unknown repository '$repo' in --local-sources"
                echo "Valid values: ADU, ADU_DELTA, DO, AZIOT_SDK_C"
                exit 1
                ;;
        esac
    done
fi

# Need to work on what this is
export TEMPLATECONF=$ROOT_DIR/meta-raspberrypi-adu/conf/templates/$MACHINE/

if [ -n "${ADU_SRC_URI}" ]; then
    export ADU_SRC_URI
fi

if [ -n "${ADU_GIT_BRANCH}" ]; then
    export ADU_GIT_BRANCH
fi

# if ADU_GIT_COMMIT is not set or equals "AUTOREV" or "HEAD", then fetch the HEAD commit of the branch
if [ "${ADU_GIT_COMMIT}" = "AUTOREV" ] || [ "${ADU_GIT_COMMIT}" = "HEAD" ] || [ -z "${ADU_GIT_COMMIT}" ]; then
    if [ "${ADU_GIT_COMMIT}" = "AUTOREV" ] || [ "${ADU_GIT_COMMIT}" = "HEAD" ]; then
        echo "ADU_GIT_COMMIT is set to ${ADU_GIT_COMMIT}, fetching HEAD commit from branch '${ADU_GIT_BRANCH}'..."
    else
        echo "ADU_GIT_COMMIT not set, fetching HEAD commit hash for branch '${ADU_GIT_BRANCH}'..."
    fi

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

# Handle local source for ADU (development workflow)
if [ "${USE_LOCAL_ADU_SOURCE}" = "1" ]; then
    # Allow override via environment variable
    if [ -z "${ADU_LOCAL_SOURCE_DIR}" ]; then
        ADU_LOCAL_SOURCE_DIR=$(realpath -m "${BUILD_DIR}/../../../sources/iot-hub-device-update")
    else
        ADU_LOCAL_SOURCE_DIR=$(realpath -m "${ADU_LOCAL_SOURCE_DIR}")
    fi
    ADU_LOCAL_SRC_DIR="${ADU_LOCAL_SOURCE_DIR}"

    if [ ! -d "${ADU_LOCAL_SRC_DIR}" ]; then
        echo ""
        echo "ERROR: USE_LOCAL_ADU_SOURCE=1 but source directory not found:"
        echo "  ${ADU_LOCAL_SRC_DIR}"
        echo ""
        echo "Please clone the ADU repository:"
        echo "  mkdir -p ~/adu_yocto/sources"
        echo "  cd ~/adu_yocto/sources"
        echo "  git clone https://github.com/Azure/iot-hub-device-update"
        echo ""
        exit 1
    fi

    echo ""
    echo "========================================"
    echo "Using LOCAL ADU source (Development Mode)"
    echo "========================================"
    echo "Source: ${ADU_LOCAL_SRC_DIR}"

    # Show git status
    cd "${ADU_LOCAL_SRC_DIR}"
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    echo "Branch: ${CURRENT_BRANCH}"
    echo "Commit: ${CURRENT_COMMIT}"

    # Count uncommitted/untracked changes
    MODIFIED_COUNT=$(git diff --name-only 2>/dev/null | wc -l)
    STAGED_COUNT=$(git diff --cached --name-only 2>/dev/null | wc -l)
    UNTRACKED_COUNT=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
    TOTAL_CHANGES=$((MODIFIED_COUNT + STAGED_COUNT + UNTRACKED_COUNT))

    if [ "$TOTAL_CHANGES" -gt 0 ]; then
        echo "Status: 🔧 Development mode ($TOTAL_CHANGES local changes/new files)"
        echo "  Modified: $MODIFIED_COUNT | Staged: $STAGED_COUNT | Untracked: $UNTRACKED_COUNT"
    else
        echo "Status: Clean working directory"
    fi

    echo ""
    echo "Note: GitHub fetch DISABLED - building from local source tree"
    echo "Note: Patches NOT applied (apply manually if needed)"
    echo "Note: Untracked/uncommitted files are NORMAL in development mode"
    echo "========================================"
    echo ""
    cd - > /dev/null

    export USE_LOCAL_ADU_SOURCE
    export ADU_LOCAL_SOURCE_DIR
fi

if [ -n "${DO_SRC_URI}" ]; then
    export DO_SRC_URI
fi

if [ -n "${DO_GIT_BRANCH}" ]; then
    export DO_GIT_BRANCH
fi

# Handle HEAD keyword for DO_GIT_COMMIT
if [ "${DO_GIT_COMMIT}" = "HEAD" ]; then
    echo "DO_GIT_COMMIT is set to HEAD, using latest commit from branch."
    export DO_GIT_COMMIT=""
elif [ -n "${DO_GIT_COMMIT}" ]; then
    export DO_GIT_COMMIT
fi

# Handle local source for DO (DeliveryOptimization client)
if [ "${USE_LOCAL_DO_SOURCE}" = "1" ]; then
    # Allow override via environment variable
    if [ -z "${DO_LOCAL_SOURCE_DIR}" ]; then
        DO_LOCAL_SOURCE_DIR=$(realpath -m "${BUILD_DIR}/../../../sources/do-client")
    else
        DO_LOCAL_SOURCE_DIR=$(realpath -m "${DO_LOCAL_SOURCE_DIR}")
    fi

    if [ ! -d "${DO_LOCAL_SOURCE_DIR}" ]; then
        echo ""
        echo "ERROR: USE_LOCAL_DO_SOURCE=1 but source directory not found:"
        echo "  ${DO_LOCAL_SOURCE_DIR}"
        echo ""
        echo "Please clone the DO client repository:"
        echo "  mkdir -p ~/adu_yocto/sources"
        echo "  cd ~/adu_yocto/sources"
        echo "  git clone https://github.com/microsoft/do-client"
        echo ""
        exit 1
    fi

    echo ""
    echo "========================================"
    echo "Using LOCAL DO source (Development Mode)"
    echo "========================================"
    echo "Source: ${DO_LOCAL_SOURCE_DIR}"

    # Show git status
    cd "${DO_LOCAL_SOURCE_DIR}"
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    echo "Branch: ${CURRENT_BRANCH}"
    echo "Commit: ${CURRENT_COMMIT}"

    # Count uncommitted/untracked changes
    MODIFIED_COUNT=$(git diff --name-only 2>/dev/null | wc -l)
    STAGED_COUNT=$(git diff --cached --name-only 2>/dev/null | wc -l)
    UNTRACKED_COUNT=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
    TOTAL_CHANGES=$((MODIFIED_COUNT + STAGED_COUNT + UNTRACKED_COUNT))

    if [ "$TOTAL_CHANGES" -gt 0 ]; then
        echo "Status: 🔧 Development mode ($TOTAL_CHANGES local changes/new files)"
        echo "  Modified: $MODIFIED_COUNT | Staged: $STAGED_COUNT | Untracked: $UNTRACKED_COUNT"
    else
        echo "Status: Clean working directory"
    fi

    echo ""
    echo "Note: GitHub fetch DISABLED - building from local source tree"
    echo "Note: Patches NOT applied (apply manually if needed)"
    echo "Note: Untracked/uncommitted files are NORMAL in development mode"
    echo "========================================"
    echo ""
    cd - > /dev/null

    export USE_LOCAL_DO_SOURCE
    export DO_LOCAL_SOURCE_DIR
fi

# Handle local source for IoT Hub C SDK
if [ "${USE_LOCAL_AZIOT_SDK_C_SOURCE}" = "1" ]; then
    # Allow override via environment variable
    if [ -z "${AZIOT_SDK_C_LOCAL_SOURCE_DIR}" ]; then
        AZIOT_SDK_C_LOCAL_SOURCE_DIR=$(realpath -m "${BUILD_DIR}/../../../sources/azure-iot-sdk-c")
    else
        AZIOT_SDK_C_LOCAL_SOURCE_DIR=$(realpath -m "${AZIOT_SDK_C_LOCAL_SOURCE_DIR}")
    fi

    if [ ! -d "${AZIOT_SDK_C_LOCAL_SOURCE_DIR}" ]; then
        echo ""
        echo "ERROR: USE_LOCAL_AZIOT_SDK_C_SOURCE=1 but source directory not found:"
        echo "  ${AZIOT_SDK_C_LOCAL_SOURCE_DIR}"
        echo ""
        echo "Please clone the Azure IoT SDK C repository:"
        echo "  mkdir -p ~/adu_yocto/sources"
        echo "  cd ~/adu_yocto/sources"
        echo "  git clone --recursive https://github.com/Azure/azure-iot-sdk-c"
        echo ""
        exit 1
    fi

    echo ""
    echo "========================================"
    echo "Using LOCAL AZIOT_SDK_C source (Development Mode)"
    echo "========================================"
    echo "Source: ${AZIOT_SDK_C_LOCAL_SOURCE_DIR}"

    # Show git status
    cd "${AZIOT_SDK_C_LOCAL_SOURCE_DIR}"
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    echo "Branch: ${CURRENT_BRANCH}"
    echo "Commit: ${CURRENT_COMMIT}"

    # Count uncommitted/untracked changes
    MODIFIED_COUNT=$(git diff --name-only 2>/dev/null | wc -l)
    STAGED_COUNT=$(git diff --cached --name-only 2>/dev/null | wc -l)
    UNTRACKED_COUNT=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
    TOTAL_CHANGES=$((MODIFIED_COUNT + STAGED_COUNT + UNTRACKED_COUNT))

    if [ "$TOTAL_CHANGES" -gt 0 ]; then
        echo "Status: 🔧 Development mode ($TOTAL_CHANGES local changes/new files)"
        echo "  Modified: $MODIFIED_COUNT | Staged: $STAGED_COUNT | Untracked: $UNTRACKED_COUNT"
    else
        echo "Status: Clean working directory"
    fi

    echo ""
    echo "Note: GitHub fetch DISABLED - building from local source tree"
    echo "Note: Patches NOT applied (apply manually if needed)"
    echo "Note: Untracked/uncommitted files are NORMAL in development mode"
    echo "========================================"
    echo ""
    cd - > /dev/null

    export USE_LOCAL_AZIOT_SDK_C_SOURCE
    export AZIOT_SDK_C_LOCAL_SOURCE_DIR
fi

if [ -n "${ADU_DELTA_SRC_URI}" ]; then
    export ADU_DELTA_SRC_URI
fi

if [ -n "${ADU_DELTA_GIT_BRANCH}" ]; then
    export ADU_DELTA_GIT_BRANCH
fi

# Handle HEAD keyword for ADU_DELTA_GIT_COMMIT
if [ "${ADU_DELTA_GIT_COMMIT}" = "HEAD" ]; then
    echo "ADU_DELTA_GIT_COMMIT is set to HEAD, using latest commit from branch."
    export ADU_DELTA_GIT_COMMIT=""
elif [ -n "${ADU_DELTA_GIT_COMMIT}" ]; then
    export ADU_DELTA_GIT_COMMIT
fi

# Handle local source for ADU Delta (development workflow)
# Support both old --adu-delta-local-src flag and new --local-sources ADU_DELTA
if [ "${USE_LOCAL_ADU_DELTA_SOURCE}" = "1" ] || [ -n "${ADU_DELTA_LOCAL_SRC}" ]; then
    # Allow override via environment variable or --adu-delta-local-src flag
    if [ -n "${ADU_DELTA_LOCAL_SRC}" ]; then
        # Old flag takes precedence
        ADU_DELTA_LOCAL_SRC=$(realpath -m "${ADU_DELTA_LOCAL_SRC}")
    elif [ -z "${ADU_DELTA_LOCAL_SOURCE_DIR}" ]; then
        ADU_DELTA_LOCAL_SOURCE_DIR=$(realpath -m "${BUILD_DIR}/../../../sources/iot-hub-device-update-delta")
        ADU_DELTA_LOCAL_SRC="${ADU_DELTA_LOCAL_SOURCE_DIR}"
    else
        ADU_DELTA_LOCAL_SRC=$(realpath -m "${ADU_DELTA_LOCAL_SOURCE_DIR}")
    fi

    # Check if directory exists
    if [ ! -d "${ADU_DELTA_LOCAL_SRC}" ]; then
        echo "Local ADU Delta source directory does not exist: ${ADU_DELTA_LOCAL_SRC}"
        echo "Cloning from ${ADU_DELTA_SRC_URI} branch ${ADU_DELTA_GIT_BRANCH}..."

        # Create parent directory if needed
        mkdir -p "$(dirname "${ADU_DELTA_LOCAL_SRC}")"

        # Clone the repository
        CLONE_URL="${ADU_DELTA_SRC_URI}"
        # Convert gitsm:// to https:// for cloning
        if [[ "${CLONE_URL}" == gitsm://* ]]; then
            CLONE_URL="https://${CLONE_URL#gitsm://}"
        elif [[ "${CLONE_URL}" == git://* ]]; then
            CLONE_URL="https://${CLONE_URL#git://}"
        fi

        git clone --branch "${ADU_DELTA_GIT_BRANCH}" "${CLONE_URL}" "${ADU_DELTA_LOCAL_SRC}"

        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to clone ADU Delta repository"
            exit 1
        fi

        echo "✓ Cloned ADU Delta to ${ADU_DELTA_LOCAL_SRC}"
    else
        echo "Using local ADU Delta source: ${ADU_DELTA_LOCAL_SRC}"

        # Show current branch and status
        cd "${ADU_DELTA_LOCAL_SRC}"
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo "  Branch: ${CURRENT_BRANCH}"
        echo "  Commit: ${CURRENT_COMMIT}"

        # Check for uncommitted changes
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            echo "  ⚠️  WARNING: Local source has uncommitted changes"
        fi
        cd - > /dev/null
    fi

    # Override SRC_URI to use local source
    export ADU_DELTA_SRC_URI="file://${ADU_DELTA_LOCAL_SRC}"
    export ADU_DELTA_LOCAL_SRC
    export ADU_DELTA_SKIP_PATCHES

    if [ "${ADU_DELTA_SKIP_PATCHES}" = "1" ]; then
        echo "ADU Delta will be built from local source (patches will be skipped): ${ADU_DELTA_LOCAL_SRC}"
    else
        echo "ADU Delta will be built from local source (patches will be applied): ${ADU_DELTA_LOCAL_SRC}"
    fi
fi

if [ -n "${VERSION}" ]; then
    export ADU_SOFTWARE_VERSION=$VERSION
fi

# Process root password options
if [ -n "${ROOT_PASSWORD_SHA512}" ]; then
    # Use pre-encrypted SHA512 hash (takes precedence)
    export ADU_ROOT_PASSWD="${ROOT_PASSWORD_SHA512}"
    echo "Using pre-encrypted SHA512 root password"
elif [ -n "${ROOT_PASSWORD}" ]; then
    # Convert plaintext password to SHA512
    echo "Encrypting root password with SHA512..."
    export ADU_ROOT_PASSWD=$(openssl passwd -6 "${ROOT_PASSWORD}")
    if [ -z "${ADU_ROOT_PASSWD}" ]; then
        echo "ERROR: Failed to encrypt password"
        exit 1
    fi
    echo "Root password encrypted successfully"
else
    # No password specified - will use default from image
    export ADU_ROOT_PASSWD=''
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
    echo "⚠️  WARNING: Full rebuild will remove ALL build directory contents!"
    echo "  Build directory: $BUILD_DIR"
    echo ""
    echo "This operation will:"
    echo "  ✗ Remove tmp/ directory (all compiled binaries, images, work files)"
    echo "  ✗ Remove conf/ directory (build configuration)"
    echo "  ✗ Remove cache/ directory (build metadata)"
    echo "  ✗ Remove downloads/ directory (source tarballs)"
    echo "  ✓ Preserve sstate-cache/ (for faster rebuilds)"
    echo ""
    echo "⚠️  This is a DESTRUCTIVE operation and will require a complete rebuild!"
    echo "   Consider using '-c' (clean) instead to clean specific recipes only."
    echo ""

    if [[ $UNATTENDED == 'false' ]]; then
        read -p "Are you sure you want to proceed? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]] && [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Rebuild cancelled."
            exit 0
        fi
    else
        echo "Running in unattended mode - proceeding without confirmation."
    fi

    echo "Performing full rebuild - removing build directory contents (preserving sstate cache)..."
    # Remove everything except sstate-cache if it exists
    find $BUILD_DIR -mindepth 1 -maxdepth 1 ! -name 'sstate-cache' -exec rm -rf {} + 2>/dev/null || true
fi

# Use persistent sstate cache and downloads location outside the tmp build directory
# This allows the cache to survive full rebuilds and can be shared across builds
export SSTATE_DIR=$BUILD_DIR/sstate-cache
export DL_DIR=$BUILD_DIR/downloads

mkdir -p $SSTATE_DIR
mkdir -p $DL_DIR

echo "========================================"
echo "Yocto Build Cache Configuration"
echo "========================================"
echo "SSTATE_DIR: $SSTATE_DIR"
echo "DL_DIR: $DL_DIR"

# Show cache statistics if caches exist
if [ -d "$SSTATE_DIR" ] && [ "$(ls -A $SSTATE_DIR 2>/dev/null)" ]; then
    SSTATE_SIZE=$(du -sh $SSTATE_DIR 2>/dev/null | cut -f1)
    SSTATE_FILES=$(find $SSTATE_DIR -type f 2>/dev/null | wc -l)
    echo "Existing sstate cache: $SSTATE_SIZE ($SSTATE_FILES files)"
    echo "  ✓ Sstate cache will accelerate build"
else
    echo "No existing sstate cache (first build will populate)"
fi

if [ -d "$DL_DIR" ] && [ "$(ls -A $DL_DIR 2>/dev/null)" ]; then
    DL_SIZE=$(du -sh $DL_DIR 2>/dev/null | cut -f1)
    DL_FILES=$(find $DL_DIR -type f 2>/dev/null | wc -l)
    echo "Existing downloads cache: $DL_SIZE ($DL_FILES files)"
    echo "  ✓ Downloads cache will skip re-downloading sources"
else
    echo "No existing downloads cache (sources will be downloaded)"
fi
echo "========================================"
echo ""

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

# Export delta update feature flag
export WITH_FEATURE_DELTA_UPDATE

# Export WiFi/Bluetooth feature flag
export ENABLE_WIFI_BLUETOOTH=1

# Export U-Boot debug script flag
export BUILD_UBOOT_DEBUG_SCRIPT

export WITH_ADUC_TESTS=1

# Export NuGet source configuration (if set)
if [[ -n "$NUGET_SOURCE" ]]; then
    export NUGET_SOURCE
    echo "NuGet Source: $NUGET_SOURCE"
fi

# export TOP_DIR=$ROOT_DIR/yocto
# We need to tell bitbake about any env vars it should read in.
export BB_ENV_PASSTHROUGH_ADDITIONS="$BB_ENV_PASSTHROUGH_ADDITIONS ADUC_USE_TEST_ROOT_KEYS ADU_GENERATION ADU_GIT_BRANCH ADU_SRC_URI ADU_GIT_COMMIT DO_GIT_BRANCH DO_SRC_URI DO_GIT_COMMIT ADU_DELTA_GIT_BRANCH ADU_DELTA_SRC_URI ADU_DELTA_GIT_COMMIT ADU_DELTA_LOCAL_SRC ADU_DELTA_SKIP_PATCHES BUILD_TYPE ADU_SOFTWARE_VERSION ADUC_PUBLIC_KEY ADUC_PRIVATE_KEY ADUC_PRIVATE_KEY_PASSWORD SSTATE_DIR DL_DIR BB_NUMBER_THREADS PARALLEL_MAKE WITH_FEATURE_DELTA_UPDATE ENABLE_WIFI_BLUETOOTH BUILD_UBOOT_DEBUG_SCRIPT USE_LOCAL_ADU_SOURCE ADU_LOCAL_SOURCE_DIR USE_LOCAL_ADU_DELTA_SOURCE ADU_DELTA_LOCAL_SOURCE_DIR USE_LOCAL_DO_SOURCE DO_LOCAL_SOURCE_DIR USE_LOCAL_AZIOT_SDK_C_SOURCE AZIOT_SDK_C_LOCAL_SOURCE_DIR ADU_ROOT_PASSWD WITH_ADUC_TESTS NUGET_SOURCE NUGET_CONFIG_PATH"

echo "Initializing Yocto/OpenEmbedded build environment..."
echo "  Build directory: $BUILD_DIR"
echo "  Template config: $TEMPLATECONF"

source $ROOT_DIR/poky/oe-init-build-env $BUILD_DIR



# Handle recipe-specific clean (after BitBake environment is initialized)
if [[ -n "$CLEAN_RECIPES" ]]; then
    echo "🧹 Cleaning specific recipes: $CLEAN_RECIPES"
    echo ""

    # Convert comma-separated list to array
    IFS=',' read -ra RECIPE_ARRAY <<< "$CLEAN_RECIPES"

    # Clean all specified recipes at once - BitBake can handle multiple targets
    echo "Cleaning recipes..."
    echo "  🧹 Cleaning: ${RECIPE_ARRAY[*]}"
    bitbake -c cleansstate "${RECIPE_ARRAY[@]}" || {
        echo "❌ ERROR: Failed to clean recipes: ${RECIPE_ARRAY[*]}" >&2
        exit 1
    }

    echo ""
    echo "✅ All recipes cleaned successfully!"
    exit 0
fi

# Handle recipe-specific rebuild (after BitBake environment is initialized)
if [[ -n "$REBUILD_RECIPES" ]]; then
    echo "🔄 Rebuilding specific recipes: $REBUILD_RECIPES"
    echo ""

    # Convert comma-separated list to array
    IFS=',' read -ra RECIPE_ARRAY <<< "$REBUILD_RECIPES"

    # First, clean all specified recipes at once - BitBake can handle multiple targets
    echo "Step 1/2: Cleaning recipes..."
    echo "  🧹 Cleaning: ${RECIPE_ARRAY[*]}"
    bitbake -c cleansstate "${RECIPE_ARRAY[@]}" || {
        echo "❌ ERROR: Failed to clean recipes: ${RECIPE_ARRAY[*]}" >&2
        exit 1
    }

    echo ""
    echo "✅ All recipes cleaned successfully"
    echo ""
    echo "Step 2/2: Building all recipes together..."
    # Build all recipes at once - BitBake will parallelize and optimize dependencies
    echo "  🔨 Building: ${RECIPE_ARRAY[*]}"
    bitbake "${RECIPE_ARRAY[@]}" || {
        echo "❌ ERROR: Failed to build recipes: ${RECIPE_ARRAY[*]}" >&2
        exit 1
    }

    echo ""
    echo "✅ All recipes rebuilt successfully!"
    exit 0
fi

# Handle building specific targets (after BitBake environment is initialized)
if [[ -n "$BUILD_TARGETS" ]]; then
    echo "🔨 Building specific targets: $BUILD_TARGETS"
    echo ""

    # Convert comma-separated list to array
    IFS=',' read -ra TARGET_ARRAY <<< "$BUILD_TARGETS"

    for target in "${TARGET_ARRAY[@]}"; do
        target=$(echo "$target" | xargs)  # Trim whitespace
        echo "  🔨 Building: $target"
        bitbake $VERBOSE "$target" || {
            echo "❌ ERROR: Failed to build target: $target" >&2
            exit 1
        }
    done

    echo ""
    echo "✅ All targets built successfully!"
    exit 0
fi

if [[ $SHOW_RECIPES == 1 ]]; then
    bitbake-layers show-recipes
elif [[ $CLEAN_SSTATE_RECIPE_NAME != '' ]]; then
    echo -e "\nCleaning SSTATE Cache for Recipe '$CLEAN_SSTATE_RECIPE_NAME' ..."
    bitbake -c cleansstate "$CLEAN_SSTATE_RECIPE_NAME"
elif [[ $CLEAN_FETCH_RECIPE != '' ]]; then
    echo "Cleaning and re-fetching recipe: $CLEAN_FETCH_RECIPE"
    bitbake $VERBOSE -c cleanall "$CLEAN_FETCH_RECIPE" || {
        echo "❌ ERROR: Failed to clean recipe: $CLEAN_FETCH_RECIPE" >&2
        exit 1
    }
    bitbake $VERBOSE -c fetch "$CLEAN_FETCH_RECIPE" || {
        echo "❌ ERROR: Failed to fetch recipe: $CLEAN_FETCH_RECIPE" >&2
        exit 1
    }
    echo "✅ Recipe $CLEAN_FETCH_RECIPE cleaned and fetched successfully"
    exit 0
elif [[ $BUILD_UBOOT_ONLY == 1 ]]; then
    echo "Building U-Boot boot scripts (normal and debug versions)..."
    echo "Enabling debug script build..."
    export BUILD_UBOOT_DEBUG_SCRIPT='1'

    # Clean and rebuild rpi-u-boot-scr
    bitbake $VERBOSE -c cleansstate rpi-u-boot-scr
    bitbake $VERBOSE rpi-u-boot-scr

    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ U-Boot boot scripts built successfully!"
        echo ""
        echo "Files deployed to:"
        echo "  Normal: $(ls -lh $BUILD_DIR/build/tmp/deploy/images/raspberrypi4-64/boot.scr 2>/dev/null | awk '{print $9, "("$5")"}')"
        echo "  Debug:  $(ls -lh $BUILD_DIR/build/tmp/deploy/images/raspberrypi4-64/boot.scr.debug 2>/dev/null | awk '{print $9, "("$5")"}')"
        echo ""
        echo "To use debug script on SD card:"
        echo "  sudo mount /dev/sdX1 /mnt"
        echo "  sudo cp /mnt/boot.scr /mnt/boot.scr.backup"
        echo "  sudo cp $BUILD_DIR/build/tmp/deploy/images/raspberrypi4-64/boot.scr.debug /mnt/boot.scr"
        echo "  sudo umount /mnt"
    else
        echo ""
        echo "❌ ERROR: U-Boot boot script build failed!"
        exit 1
    fi
elif [[ $BUILD_BASE_IMAGE_ONLY == 1 ]]; then
    echo "Building base image only (adu-base-image)..."
    echo "Update images (SWU) and delta artifacts will NOT be built."
    echo ""
    bitbake $VERBOSE adu-base-image

    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Base image built successfully!"
        echo ""
        echo "WIC image deployed to:"
        WIC_FILE=$(ls -t $BUILD_DIR/build/tmp/deploy/images/raspberrypi4-64/adu-base-image-raspberrypi4-64.rootfs.wic* 2>/dev/null | head -1)
        if [ -n "$WIC_FILE" ]; then
            echo "  $(ls -lh "$WIC_FILE" | awk '{print $9, \"(\"$5\")\"}')"
        fi
        echo ""
        echo "Flash to SD card:"
        echo "  sudo dd if=$WIC_FILE of=/dev/sdX bs=4M status=progress conv=fsync"
    else
        echo ""
        echo "❌ ERROR: Base image build failed!"
        exit 1
    fi
else
    if [[ $CLEAN == 'true' ]]; then
        echo "⚠️  WARNING: Clean build will remove all build artifacts for the following recipes:"
        echo "  - azure-device-update, adu-agent-service, azure-iot-sdk-c"
        echo "  - deliveryoptimization-agent, swupdate"
        echo "  - core-image-full-cmdline, core-image-minimal"
        echo "  - adu-base-image, adu-update-image, adu-delta-image"
        echo ""
        echo "This operation will:"
        echo "  ✗ Remove all compiled binaries and intermediate files"
        echo "  ✗ Remove all generated images and SWU files"
        echo "  ✓ Preserve sstate cache (for faster rebuilds)"
        echo ""

        if [[ $UNATTENDED == 'false' ]]; then
            read -p "Do you want to proceed? (yes/no): " -r
            echo
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]] && [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Clean build cancelled."
                exit 0
            fi
        else
            echo "Running in unattended mode - proceeding without confirmation."
        fi

        echo "Performing clean build - removing all build artifacts..."
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
            adu-update-image \
            adu-delta-image
    fi

    echo "Building ADU update images (v1, v2, v3)..."
    bitbake $VERBOSE adu-update-image-v1 adu-update-image-v2 adu-update-image-v3
    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ ERROR: Update image build failed!"
        echo ""
        echo "This usually means:"
        echo "  1. Timestamp validation detected stale artifacts (base image missing/changed)"
        echo "  2. Compilation or packaging errors"
        echo ""
        echo "If timestamp validation failed, run:"
        echo "  ./scripts/build.sh --rebuild adu-base-image"
        echo ""
        echo "This will clean and rebuild the base image and all dependent artifacts."
        exit 1
    fi

    if [[ $WITH_FEATURE_DELTA_UPDATE == '1' ]]; then
        echo "Building delta update artifacts (v1→v2, v2→v3, v1→v3)..."
        bitbake $VERBOSE adu-delta-image
        if [ $? -ne 0 ]; then
            echo ""
            echo "❌ ERROR: Delta image build failed!"
            echo ""
            echo "Common causes:"
            echo "  1. Out of memory (increase swap file)"
            echo "  2. Timestamp validation failed"
            echo "  3. Delta generation tool errors"
            echo ""
            echo "Check the log for details."
            exit 1
        fi
    else
        echo "Delta update feature disabled (--with-delta-update '0')"
    fi

fi

#!/bin/bash
set -euo pipefail

#
# install-deps.sh - Install build dependencies for Azure Device Update Yocto builds
#
# Supports Ubuntu 20.04, 22.04, and 24.04+
# Can be run as root or as a regular user (auto-detects and uses sudo when needed)
#

# Use sudo only when not already root
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if ! command -v sudo &> /dev/null; then
        echo "Error: Not running as root and sudo is not available."
        exit 1
    fi
    SUDO="sudo"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Fix Azure CLI apt source conflict ---
if [ -f /etc/apt/sources.list.d/azure-cli.list ] && [ -f /etc/apt/sources.list.d/azure-cli.sources ]; then
    echo "Removing duplicate Azure CLI apt source..."
    $SUDO rm -f /etc/apt/sources.list.d/azure-cli.list
fi

# --- Detect Ubuntu version ---
get_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$VERSION_ID"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        echo "$DISTRIB_RELEASE"
    else
        echo "Unknown"
    fi
}

UBUNTU_VERSION=$(get_ubuntu_version)
echo "Detected Ubuntu version: $UBUNTU_VERSION"

# --- Install apt packages ---
$SUDO apt-get update

# Common packages for all supported Ubuntu versions
PACKAGES=(
    gawk
    wget
    git
    git-lfs
    diffstat
    unzip
    texinfo
    gcc
    build-essential
    chrpath
    socat
    cpio
    python3
    python3-pip
    python3-pexpect
    xz-utils
    debianutils
    iputils-ping
    python3-git
    python3-jinja2
    xterm
    python3-subunit
    mesa-common-dev
    zstd
    liblz4-tool
    libcpprest-dev
    libssl-dev
    libproxy-dev
    libncurses5-dev
    zlib1g-dev
    tmux
    bmap-tools
    autoconf
    autopoint
)

# libsdl1.2-dev was removed in Ubuntu 22.04+; use libsdl2-dev instead
case "$UBUNTU_VERSION" in
    20.04)
        PACKAGES+=(libsdl1.2-dev pylint3 libegl1-mesa)
        ;;
    22.04)
        PACKAGES+=(libsdl2-dev pylint libegl1-mesa)
        ;;
    24.04|24.10|25.*)
        PACKAGES+=(libsdl2-dev pylint libegl-dev)
        ;;
    *)
        echo "Warning: Untested Ubuntu version $UBUNTU_VERSION — attempting with 22.04+ package list."
        PACKAGES+=(libsdl2-dev pylint)
        ;;
esac

$SUDO apt-get install -y "${PACKAGES[@]}"

# --- Install kas (Yocto build tool) ---
echo "Installing kas build tool..."
pip install --user --break-system-packages kas 2>/dev/null || pip install --user kas 2>/dev/null || $SUDO pip install kas

# --- Ubuntu 24.04+: Fix AppArmor restriction on unprivileged user namespaces ---
# BitBake requires unprivileged user namespaces for pseudo and other build isolation.
# Ubuntu 24.04 restricts this by default via AppArmor. Without this fix, BitBake will
# fail with: "ERROR: User namespaces are not usable by BitBake, possibly due to AppArmor."
# See: https://discourse.ubuntu.com/t/ubuntu-24-04-lts-noble-numbat-release-notes/39890
if [[ "$UBUNTU_VERSION" == 24.* || "$UBUNTU_VERSION" == 25.* ]]; then
    CURRENT_VALUE=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo "0")
    if [ "$CURRENT_VALUE" = "1" ]; then
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────────┐"
        echo "│ Ubuntu $UBUNTU_VERSION: AppArmor restricts unprivileged user namespaces      │"
        echo "│                                                                     │"
        echo "│ BitBake requires user namespaces for build isolation. This setting   │"
        echo "│ must be relaxed for Yocto builds to work.                           │"
        echo "│                                                                     │"
        echo "│ This will:                                                          │"
        echo "│   • Allow unprivileged user namespace creation (used by BitBake)    │"
        echo "│   • Persist across reboots via /etc/sysctl.d/99-bitbake-userns.conf │"
        echo "│   • NOT affect other AppArmor protections                           │"
        echo "└─────────────────────────────────────────────────────────────────────┘"
        echo ""
        read -p "Apply this fix? (yes/no): " -r
        if [[ "$REPLY" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$REPLY" =~ ^[Yy]$ ]]; then
            echo 'kernel.apparmor_restrict_unprivileged_userns=0' | $SUDO tee /etc/sysctl.d/99-bitbake-userns.conf > /dev/null
            $SUDO sysctl --system > /dev/null 2>&1
            echo "✓ AppArmor user namespace restriction relaxed (persistent across reboots)."
        else
            echo "⚠ Skipped. BitBake builds will fail until this is resolved."
            echo "  To apply manually later:"
            echo "    echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee /etc/sysctl.d/99-bitbake-userns.conf"
            echo "    sudo sysctl --system"
        fi
    else
        echo "✓ AppArmor user namespace restriction already relaxed."
    fi
fi

# --- Setup git-lfs ---
echo "Setting up git-lfs in repo: $REPO_ROOT"
pushd "$REPO_ROOT" > /dev/null
git lfs install
popd > /dev/null

# --- Install .NET SDK (for delta DiffGenTool) ---
install_dotnet_sdk() {
    echo "Checking for .NET SDK..."
    if command -v dotnet &> /dev/null; then
        DOTNET_VERSION=$(dotnet --version 2>/dev/null)
        echo "✓ .NET SDK already installed: $DOTNET_VERSION"
        return 0
    fi

    echo "Installing .NET 8 SDK..."

    wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh

    $SUDO /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet

    if [ ! -f /usr/bin/dotnet ]; then
        $SUDO ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet
    fi

    if command -v dotnet &> /dev/null; then
        echo "✓ .NET SDK installed successfully: $(dotnet --version)"
    else
        echo "⚠ .NET SDK installation may have failed. Please verify manually."
        echo "  You can also install via: sudo apt-get install -y dotnet-sdk-8.0"
    fi

    rm -f /tmp/dotnet-install.sh
}

install_dotnet_sdk

echo ""
echo "✓ All dependencies installed successfully."


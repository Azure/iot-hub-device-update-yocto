#!/bin/bash

# If both /etc/apt/sources.list.d/azure-cli.list and /etc/apt/sources.list.d/azure-cli.sources exist, delete azure-cli.list
if [ -f /etc/apt/sources.list.d/azure-cli.list ] && [ -f /etc/apt/sources.list.d/azure-cli.sources ]; then
    echo "Both /etc/apt/sources.list.d/azure-cli.list and /etc/apt/sources.list.d/azure-cli.sources exist." 
    echo "Deleting /etc/apt/sources.list.d/azure-cli.list"
    sudo rm -f /etc/apt/sources.list.d/azure-cli.list
fi

# Remove deadsnakes PPA if present — it is sometimes pre-installed on CI agent
# images but unreachable from certain networks, causing apt-get update to timeout
# and emit stderr warnings that fail Azure DevOps Bash tasks.
for f in /etc/apt/sources.list.d/deadsnakes-*; do
    if [ -f "$f" ]; then
        echo "Removing unreachable deadsnakes PPA source: $f"
        sudo rm -f "$f"
    fi
done

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

sudo apt-get update

# Common packages for all supported Ubuntu versions
# FIT Dependencies: autoconf autopoint git-lfs zlib1g-dev
PACKAGES=(
    gawk wget git-core git-lfs diffstat unzip texinfo gcc build-essential
    chrpath socat cpio python3 python3-pip python3-pexpect xz-utils
    debianutils iputils-ping python3-git python3-jinja2 xterm
    python3-subunit mesa-common-dev zstd liblz4-tool libcpprest-dev
    libssl-dev libproxy-dev libncurses5-dev tmux bmap-tools autoconf
    autopoint
)

# Version-specific packages
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
        echo "Warning: Untested Ubuntu version $UBUNTU_VERSION — using 24.04+ package list."
        PACKAGES+=(libsdl2-dev pylint libegl-dev)
        ;;
esac

sudo apt-get install -y "${PACKAGES[@]}"

#
# Install git-lfs because recipe for iot-hub-device-update-delta requires it
#
echo "Running 'git lfs install' in current dir: $(pwd). Assuming it is root of repo..."
git lfs install

#
# Install .NET SDK for meta-iot-hub-device-update-delta native build tools
# The DiffGenTool (delta diff generation) requires .NET 6 or 8 SDK on the host
#
install_dotnet_sdk() {
    echo "Checking for .NET SDK..."
    if command -v dotnet &> /dev/null; then
        DOTNET_VERSION=$(dotnet --version 2>/dev/null)
        echo "✓ .NET SDK already installed: $DOTNET_VERSION"
        return 0
    fi

    echo "Installing .NET 8 SDK..."
    
    # Download and run the official dotnet install script
    wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    
    # Install to /usr/share/dotnet (system-wide)
    sudo /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet
    
    # Create symlink if not exists
    if [ ! -f /usr/bin/dotnet ]; then
        sudo ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet
    fi
    
    # Verify installation
    if command -v dotnet &> /dev/null; then
        echo "✓ .NET SDK installed successfully: $(dotnet --version)"
    else
        echo "⚠ .NET SDK installation may have failed. Please verify manually."
        echo "  You can also install via: sudo apt-get install -y dotnet-sdk-8.0"
    fi
    
    rm -f /tmp/dotnet-install.sh
}

install_dotnet_sdk


#!/bin/bash

# If both /etc/apt/sources.list.d/azure-cli.list and /etc/apt/sources.list.d/azure-cli.sources exist, delete azure-cli.list
if [ -f /etc/apt/sources.list.d/azure-cli.list ] && [ -f /etc/apt/sources.list.d/azure-cli.sources ]; then
    echo "Both /etc/apt/sources.list.d/azure-cli.list and /etc/apt/sources.list.d/azure-cli.sources exist." 
    echo "Deleting /etc/apt/sources.list.d/azure-cli.list"
    sudo rm -f /etc/apt/sources.list.d/azure-cli.list
fi

sudo apt-get update

# FIT Dependencies: autoconf autopoint git-lfs zlib1g-dev

sudo apt-get install -y \
gawk \
wget \
git-core \
git-lfs \
diffstat \
unzip \
texinfo \
gcc \
build-essential \
chrpath \
socat \
cpio \
python3 \
python3-pip \
python3-pexpect \
xz-utils \
debianutils \
iputils-ping \
python3-git \
python3-jinja2 \
libegl1-mesa \
libsdl1.2-dev \
xterm \
python3-subunit \
mesa-common-dev \
zstd \
liblz4-tool \
libcpprest-dev \
libssl-dev \
libproxy-dev \
libncurses5-dev \
tmux \
bmap-tools \
autoconf \
autopoint

#
# Install git-lfs because recipe for iot-hub-device-update-delta requires it
#
echo "Running 'git lfs install' in current dir: $(pwd). Assuming it is root of repo..."
git lfs install

#
# Install pylint3 on ubuntu 20.04; otherwise, install pylint 
#
#
get_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo $VERSION_ID
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        echo $DISTRIB_RELEASE
    else
        echo "Unknown"
    fi
}

UBUNTU_VERSION=$(get_ubuntu_version)

# Check the version and install the appropriate package
if [ "$UBUNTU_VERSION" == "20.04" ]; then
    echo "Detected Ubuntu 20.04. Installing pylint3..."
    sudo apt-get update
    sudo apt-get install -y pylint3
elif [ "$UBUNTU_VERSION" == "22.04" ]; then
    echo "Detected Ubuntu 22.04. Installing pylint..."
    sudo apt-get update
    sudo apt-get install -y pylint
else
    echo "Unsupported Ubuntu version: $UBUNTU_VERSION"
    exit 1
fi

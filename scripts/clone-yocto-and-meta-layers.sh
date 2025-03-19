#!/bin/bash

## Set project root directory to the parent of this script's directory
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
proj_root=$script_dir/..

# Show the project root directory and ask the user if they want to change it
echo "Project root directory is set to: $proj_root"
read -p "Do you want to change it? (y/n): " change_proj_root
if [ "$change_proj_root" == "y" ]; then
    read -p "Enter the new project root directory: " new_proj_root
    proj_root=$new_proj_root
fi

# Check that the 'yocto' subdirectory exists
if [ ! -d "$proj_root/yocto" ]; then
    echo "Error: 'yocto' subdirectory does not exist in the project root directory."
    exit 1
fi

# Check that the yocto_release variable is set. If not, ask the user to use the default (scarathgap)
# if the user doesn't want to use the default, ask them to enter a new one

if [ -z "$yocto_release" ]; then
    echo "yocto_release is not set."
    # Ask the user if they want to use the default value
    read -p "Do you want to use the default yocto release (scarthgap)? (y/n): " use_default
    if [ "$use_default" == "y" ]; then
        yocto_release='scarthgap'
    else
        # Ask the user to enter a new value
        read -p "Enter the yocto release: " yocto_release
    fi
fi

# If the user does not enter anything, set it to 'scarthgap'
if [ -z "$yocto_release" ]; then
    read -p "Enter the yocto release (scarthgap): " yocto_release
fi
if [ -z "$yocto_release" ]; then
    echo "Error: yocto_release is not set. (supported: scarthgap)"
    exit 1
fi

# Check that meta-layer-adu variable is set. If not, ask the user to enter it
# Ether scarthgap or user/user_name/branch_name
if [ -z "$meta_layer_adu" ]; then
    echo "meta_layer_adu is not set."
    # Ask the user if they want to use scarthgap? If so, set it to scarthgap
    read -p "Do you want to use scarthgap for meta-layer-adu? (y/n): " use_scarthgap
    if [ "$use_scarthgap" == "y" ]; then
        meta_layer_adu="scarthgap"
    else
        # Ask the user to enter the meta-layer-adu
        read -p "Enter the meta-layer-adu (user/user_name/branch_name): " meta_layer_adu
    fi
fi

# Check that the meta-layer-adu variable again, if not set, exit
if [ -z "$meta_layer_adu" ]; then
    echo "Error: meta_layer_adu is not set. (supported: scarthgap or user/...)"
    exit 1
fi

# Check that the meta-layer-raspberrypi variable is set. If not, ask the user to..
# User 'scarthgap' or same as meta-layer-adu, or user/user_name/branch_name
if [ -z "$meta_layer_raspberrypi" ]; then
    # Aks if user want to use scarthgap? If so, set it to scarthgap
    read -p "Do you want to use scarthgap for meta-layer-raspberrypi? (y/n): " use_scarthgap
    if [ "$use_scarthgap" == "y" ]; then
        meta_layer_raspberrypi="scarthgap"
    else
        # ask if user want to to set it to the same as meta-layer-adu
        read -p "Do you want to set meta-layer-raspberrypi to the same as meta-layer-adu? (y/n): " use_same_as_adu
        if [ "$use_same_as_adu" == "y" ]; then
            meta_layer_raspberrypi="$meta_layer_adu"
        else
            # Ask user to enter the meta-layer-raspberrypi
            read -p "Enter the meta-layer-raspberrypi (user/user_name/branch_name): " meta_layer_raspberrypi
        fi
    fi
fi

# Check that the meta-layer-raspberrypi variable again, if not set, exit
if [ -z "$meta_layer_raspberrypi" ]; then
    echo "Error: meta_layer_raspberrypi is not set. (supported: scarthgap or user/...)"
    exit 1
fi

# Check that the meta-layer-adu-delta variable is set. If not, ask the user to..
# User 'scarthgap' or same as meta-layer-adu, or user/user_name/branch_name
if [ -z "$meta_layer_adu_delta" ]; then
    # Aks if user want to use scarthgap? If so, set it to scarthgap
    read -p "Do you want to use scarthgap for meta-layer-adu-delta? (y/n): " use_scarthgap
    if [ "$use_scarthgap" == "y" ]; then
        meta_layer_adu_delta="scarthgap"
    else
        # ask if user want to to set it to the same as meta-layer-adu
        read -p "Do you want to set meta-layer-adu-delta to the same as meta-layer-adu? (y/n): " use_same_as_adu
        if [ "$use_same_as_adu" == "y" ]; then
            meta_layer_adu_delta="$meta_layer_adu"
        else
            # Ask user to enter the meta-layer-raspberry
            read -p "Enter the meta-layer-adu-delta (user/user_name/branch_name): " meta_layer_adu_delta
        fi
    fi
fi
# Check that the meta-layer-adu-delta variable again, if not set, exit
if [ -z "$meta_layer_adu_delta" ]; then
    echo "Error: meta_layer_adu_delta is not set. (supported: scarthgap or user/...)"
    exit 1
fi

# Show the list of meta layers to clone including the branch names
# And ask the user if they want to clone them, if not, exit
echo "The following meta layers will be cloned:"
echo "1. meta-azure-device-update:$meta_layer_adu"
echo "2. meta-raspberrypi-adu:$meta_layer_adu"
echo "3. meta-iot-hub-device-update-delta:$meta_layer_adu_delta"
read -p "Do you want to clone these meta layers? (y/n): " clone_meta_layers
if [ "$clone_meta_layers" == "n" ]; then
    echo "Skipping meta layers cloning."
    echo "You can clone them manually later."
    goto do_build
fi


# Define the tuple of  meta layers to clone (meta-layer:uri:branch)
# Here's the URIs for the meta layers
# http://github.com/azure/meta-azure-device-update
# http://github.com/azure/meta-raspberrypi-adu
# http://github.com/azure/meta-iot-hub-device-update-delta

meta_layers=(
    "meta-azure-device-update,http://github.com/azure/meta-azure-device-update,$meta_layer_adu"
    "meta-raspberrypi-adu,http://github.com/azure/meta-raspberrypi-adu,$meta_layer_adu"
    "meta-iot-hub-device-update-delta,http://github.com/azure/meta-iot-hub-device-update-delta,$meta_layer_adu_delta"
)

# Clone the meta layers into the layers_base directory
for meta_layer in "${meta_layers[@]}"; do
    IFS=','  # Set comma as the delimiter
    read -r layer_name layer_uri layer_branch <<< "$meta_layer"
    echo "Layer Name: $layer_name"
    echo "Layer URI: $layer_uri"
    echo "Layer Branch: $layer_branch"
    unset IFS  # Reset to default

    echo "Cloning $layer_name from $layer_uri (branch: $layer_branch)"
    git clone --branch "$layer_branch" "$layer_uri" "$proj_root/yocto/$layer_name"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone $layer_name from $layer_uri (branch: $layer_branch)"
        exit 1
    fi
    echo "Successfully cloned $layer_name from $layer_uri (branch: $layer_branch)"
    
done

echo "All meta layers cloned successfully."

do_build:

# Check if the user wants to build the image
read -p "Do you want to build the image? (y/n): " build_image
if [ "$build_image" != "y" ]; then
    echo "Skipping image build."
    goto all_done
fi


# Clone Poke and all base layers
uri_poky='git://git.yoctoproject.org/poky'
uri_meta_swu='https://github.com/sbabic/meta-swupdate'
uri_meta_oe='git://git.openembedded.org/meta-openembedded'
uri_meta_rpi='git://git.yoctoproject.org/meta-raspberrypi'

# Clone poky
layer_base="$proj_root/yocto"
if [ ! -d "$layer_base" ]; then
    echo "Error: Layer base directory '$layer_base' does not exist."
    exit 1
fi

cd $layer_base

git clone --depth 1 --branch $yocto_release $uri_poky || exit 1
git clone --depth 1 --branch $yocto_release $uri_meta_swu || exit 1
git clone --depth 1 --branch $yocto_release $uri_meta_oe || exit 1
git clone --depth 1 --branch $yocto_release $uri_meta_rpi || exit 1
echo "Poky and base layers cloned successfully."


# Setup build environment
poky_dir="$layer_base/poky"
if [ ! -d "$poky_dir" ]; then
    echo "Error: Poky directory '$poky_dir' does not exist."
    exit 1
fi

# Stop bitbake server
sudo pkill -f bitbake

cd $poky_dir
source oe-init-build-env

# Add meta-openembedded to bblayers.conf
bitbake-layers add-layer $layer_base/meta-openembedded/meta-oe
bitbake-layers add-layer $layer_base/meta-openembedded/meta-python
bitbake-layers add-layer $layer_base/meta-openembedded/meta-networking
bitbake-layers add-layer $layer_base/meta-openembedded/meta-multimedia
bitbake-layers add-layer $layer_base/meta-openembedded/meta-filesystems

# Add meta-swupdate to bblayers.conf
bitbake-layers add-layer $layer_base/meta-swupdate

# Add meta-raspberrypi to bblayers.conf
bitbake-layers add-layer $layer_base/meta-raspberrypi


# Update local.conf to set MACHINE to raspberrypi4-64
sed -i 's/MACHINE ??= "qemux86-64"/MACHINE ??= "raspberrypi4-64"/' conf/local.conf

:all_done
echo "All done!"


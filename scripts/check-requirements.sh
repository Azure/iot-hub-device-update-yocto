#!/bin/bash

# Check disk space
disk_space=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
required_disk_space=90
if [ $disk_space -lt $required_disk_space ]; then
    echo "Error: Insufficient disk space. Actual: ${disk_space}G, Expected: ${required_disk_space}G"

    # Show current logical volumn
    echo "Current logical volume:"
    sudo lvdisplay

    # Get lv path from lvdisplay output, then show how to expand disk space using lvextend and resize2fs command
    # Example output:
    #   --- Logical volume ---
    #   LV Path                /dev/ubuntu-vg/ubuntu-lv
    #   LV Name                ubuntu-lv
    #   VG Name                ubuntu-vg
    #   LV UUID                0b2b4b-3f5d-4c28-8c6b-6b3f-6b3f-6b3f
    #   LV Write Access        read/write
    #   LV Creation host, time ubuntu, 2021-07-07 09:09:09 +0000
    #   LV Status              available
    #   # open                 1
    #   LV Size                <9.00 GiB
    #   Current LE             2304
    #   Segments               1
    #   Allocation             inherit
    #   Read ahead sectors     auto
    #   - currently set to     256

    # Show how to expand disk space
    echo "To expand disk space, run the following commands:"
    echo "sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv"
    echo "sudo resize2fs /dev/ubuntu-vg/ubuntu-lv"


else
    echo "Disk space check passed. Actual: ${disk_space}G, Expected: ${required_disk_space}G"
fi

# Check RAM
ram=$(free -g | awk 'NR==2 {print $2}')
required_ram=6
if [ $ram -lt $required_ram ]; then
    echo "Error: Insufficient RAM. Actual: ${ram}G, Expected: ${required_ram}G"
else
    echo "RAM check passed. Actual: ${ram}G, Expected: ${required_ram}G"
fi

# Check supported Linux distribution
supported_distributions=("Fedora" "openSUSE" "CentOS" "Debian" "Ubuntu")
current_distribution=$(lsb_release -is)
if [[ ! " ${supported_distributions[@]} " =~ " ${current_distribution} " ]]; then
    echo "Error: Unsupported Linux distribution. Actual: ${current_distribution}, Expected: ${supported_distributions[@]}"
else
    echo "Linux distribution check passed. Actual: ${current_distribution}, Expected: ${supported_distributions[@]}"
fi

# Check Git version
git_version=$(git --version | awk '{print $3}')
required_git_version="1.8.3.1"
if [ "$(printf '%s\n' "$required_git_version" "$git_version" | sort -V | head -n1)" != "$required_git_version" ]; then
    echo "Error: Unsupported Git version. Actual: ${git_version}, Expected: ${required_git_version} or greater"
else
    echo "Git version check passed. Actual: ${git_version}, Expected: ${required_git_version} or greater"
fi

# Check tar version
tar_version=$(tar --version | awk 'NR==1 {print $4}')
required_tar_version="1.28"
if [ "$(printf '%s\n' "$required_tar_version" "$tar_version" | sort -V | head -n1)" != "$required_tar_version" ]; then
    echo "Error: Unsupported tar version. Actual: ${tar_version}, Expected: ${required_tar_version} or greater"
else
    echo "Tar version check passed. Actual: ${tar_version}, Expected: ${required_tar_version} or greater"
fi

# Check Python version
python_version=$(python3 --version | awk '{print $2}')
required_python_version="3.8.0"
if [ "$(printf '%s\n' "$required_python_version" "$python_version" | sort -V | head -n1)" != "$required_python_version" ]; then
    echo "Error: Unsupported Python version. Actual: ${python_version}, Expected: ${required_python_version} or greater"
    
    # Echo how to install the python version 3.8.1
    echo "To install Python 3.8.1, run the following commands:"
    echo "sudo apt update"
    echo "sudo apt install software-properties-common"
    echo "sudo add-apt-repository ppa:deadsnakes/ppa"
    echo "sudo apt update"
    echo "sudo apt install python3.8"
    echo "sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 1"
    echo "sudo update-alternatives --config python3"
    echo "python3 --version"

    ## Use Python 3.8.1 by default

    # Install Python 3.8.1

    sudo apt install software-properties-common
    sudo add-apt-repository ppa:deadsnakes/ppa
    sudo apt update
    sudo apt install python3.8

    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 1
    sudo update-alternatives --config python3
    python3 --version

else
    echo "Python version check passed. Actual: ${python_version}, Expected: ${required_python_version} or greater"
fi


# Check gcc version
gcc_version=$(gcc --version | awk 'NR==1 {print $4}')
required_gcc_version="8.0"
if [ "$(printf '%s\n' "$required_gcc_version" "$gcc_version" | sort -V | head -n1)" != "$required_gcc_version" ]; then
    echo "Error: Unsupported gcc version. Actual: ${gcc_version}, Expected: ${required_gcc_version} or greater"

    # Echo how to install the gcc version 8.0
    echo "To install gcc 8.0, run the following commands:"
    echo "sudo apt update"
    echo "sudo apt install gcc"
    echo "gcc --version"

else
    echo "gcc version check passed. Actual: ${gcc_version}, Expected: ${required_gcc_version} or greater"
fi

# Check GNU make version
make_version=$(make --version | awk 'NR==1 {print $3}')
required_make_version="4.0"
if [ "$(printf '%s\n' "$required_make_version" "$make_version" | sort -V | head -n1)" != "$required_make_version" ]; then
    echo "Error: Unsupported GNU make version. Actual: ${make_version}, Expected: ${required_make_version} or greater"

    # Echo how to install the GNU make version 4.0
    echo "To install GNU make 4.0, run the following commands:"
    echo "sudo apt update"
    echo "sudo apt install make"
    echo "make --version"
else
    echo "GNU make version check passed. Actual: ${make_version}, Expected: ${required_make_version} or greater"
fi
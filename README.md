# Building a Custom Linux-based System with Device Update for IotHub Agent using the Yocto Project
> **DISCLAIMER:**  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Introduction

This repository is a tool for experimenting with the integration of Device Update with a Yocto build system. Within this repo there are scripts for helping with builds, a directory structure for supplying keys to the swupdate signing process, and the azurepipelines definitions which can be used for setting up an Azure Dev Ops pipeline for generating the proof of concept image. 

None of the instructions, Azure Pipelines, scripts, or process described here is intended for production use. Do not use this repository as a basis for a production pipeline for integrating images. There are no promises made about the security and stability of the pipeline held within this repository. 

The repository and instructions create an image for the RaspberryPi 4 which can run script and image based updates using Device Update for IoT Hub. It's just to give you a taste of the power and utility of Device Update for IoT Hub.

For more information about the Device Update for IoT Hub, see the link to the source code of [Device Update Agent](https://github.com/Azure/iot-hub-device-update)

## Quick Start

On a machine installed with [Ubuntu 20.04 LTS (Focal Fossa) Server ISO](https://cdimage.ubuntu.com/ubuntu-legacy-server/releases/20.04/release/ubuntu-20.04.1-legacy-server-amd64.iso),
ensure at least 100GB of space on the partition where /home is mounted (or adjust the `base_yocto_path` var in the steps below and in scripts/setup.sh accordingly).

### Directory Structure After Quick Steps

The final directory structure as per the "quick step" exports below  are as follows:
```
$HOME
  └ adu_yocto/
    ├── iot-hub-device-update-yocto               # github repo with scripts
    │   ├── azurepipelines
    │   ├── keys
    │   ├── scripts
    │   └── yocto
    │       ├── config-templates
    │       ├── meta-azure-device-update          # DU Agent yocto recipes
    │       ├── meta-iot-hub-device-update-delta  # Delta updates recipe - (Currently NOT working)
    │       ├── meta-openembedded                 # OpenEmbedded layers
    │       ├── meta-raspberrypi                  # RPi layers
    │       ├── meta-raspberrypi-adu              # ADU-specific RPi layer
    │       ├── meta-swupdate                     # swupdate layer
    │       └── poky
    └── out
        ├── build                                 # post successful yocto build
        ├── cache                                 # post successful yocto build
        ├── conf                                  # post successful yocto build
        └── sstate-cache                          # post successful yocto build
```

### Quick Steps - Gen 1

```sh
# Clone the main yocto repo that has install-deps.sh, setup.sh, and build.sh scripts.
git clone 'git@github.com:azure/iot-hub-device-update-yocto.git' --branch scarthgap "$HOME/adu_yocto/iot-hub-device-update-yocto"
git clone 'https://github.com/azure/iot-hub-device-update-yocto' --branch scarthgap "$HOME/adu_yocto/iot-hub-device-update-yocto"

cd $HOME/adu_yocto/iot-hub-device-update-yocto

# Install dev dependencies via ubuntu 20.04 APT packages.
./scripts/install-deps.sh

# Clones poky and the meta layers to dirs under $HOME/adu_yocto/yocto/
./scripts/setup.sh

# Create private/public key pair with password-protected private key in the "keys" folder
#
# The private cert, keys/priv.pem, is what should be used when creating the sw-description signature file in swupdate CPIO package.
# The public cert, keys/pub.pem, will be installed into the .wic raw image file produced by bitbake.
# The script update payload (side-by-side with the .swu swupdate payload) would call out to swupdate utility with the path to this
# public cert. swupdate on the device will use it to verify sw-description signature file in the .swu swupdate CPIO archive.
pushd keys
echo "PUT A PASSWORD FOR swupdate sw-description signing HERE" > ./priv.pass
openssl genrsa -out ./priv.pem -passout file:./priv.pass
openssl rsa -in ./priv.pem -passin file:priv.pass -out public.pem -outform PEM -pubout
popd

# Launch bitbake to build the .wic image as per the yocto recipes.
#
# Build with default branches (automatically fetches latest commit from branch):
# ./scripts/build.sh -c -t Debug -o ~/yocto_build_dir
#
# Build with specific branch (automatically fetches HEAD commit):
# ./scripts/build.sh -c -t Debug -o ~/yocto_build_dir --adu-git-branch feature/v-next
#
# Optional: Specify ADU Branch and Commit explicitly
# ./scripts/build.sh -c -t Debug -o ~/yocto_build_dir --adu-git-branch release/1.2.0 --adu-git-commit 9cf04c49d49b587712d01e9db6e1870a70959682
#
# Use parallel builds for faster compilation (uses all CPU cores by default):
# ./scripts/build.sh -c -t Debug -o ~/yocto_build_dir -j 8 --parallel-make 8
#
# Full rebuild (preserves sstate cache for faster rebuilds):
# ./scripts/build.sh --rebuild -t Debug -o ~/yocto_build_dir --adu-git-branch feature/v-next

./scripts/build.sh -c -t Debug -o ~/yocto_build_dir

# List the deployment .wic file and symlink to it.
pushd ~/yocto_build_dir
find . -type f -name '*.wic' | grep -i deploy
```

### Build and Run Status Monitor for ARM64 using Yocto Toolchain

```sh
# After building the .wic above

./scripts/build_status_monitor.sh
file ../sdk_examples/status_monitor
ls -la ../sdk_examples/status_monitor

# After flashing the RPi4 device with the .wic from above:

# copy to rpi4
scp ../sdk_examples/user@<IP of rpi4device>:/var/lib/adu/

# run status monitor
ssh user@<IP of rpi4device>
rpi4> cd /var/lib/adu
rpi4> chown adu:adu status_monitor
rpi4> su -p adu
rpi4> ./status_monitor
```

## Prerequisites

Before getting started with this project, please get yourself familiar with the following topics:

- [The Yocto Project Software Overview](https://www.yoctoproject.org/software-overview/)
- [The Device Update for IoTHub Overview](http://github.com/azure/iot-hub-device-update)

### Get Source Code

Please note that, at the time of this writing, we only support `scarthgap` release of the Yocto Project. 

The following variables are referenced in the below section setting up the build. 

| Variable Name | Description |
|---|---|
| $yocto_release | A name of the version of the Yocto Project used to build the images.<br/>(Only support `scarthgap` at the moment) |
| $project_root  | A root directory where this project will be cloned into.|
| $adu_release   | The release of Device Update you're planning on using (should default to `'main'`) | 

You can either just include the string wholesale in the terminal (eg for `$yocto_release` just use `'scarthgap'`) or set the variable at the beginning and then copy the command from this screen.

You can set a bash variable like `yocto_release` like this:

```sh
yocto_release=scarthgap
```
and for `adu_release` like this: 

```sh
adu_release=main
```
and for `project_root` like this:

```sh
project_root=~/
```

The first step for building the project is cloning this repository onto your device using the following command:

1. Clone this repository onto your device:
    
```sh
git clone https://github.com/Azure/iot-hub-device-update-yocto -b <branchname> $project_root/iot-hub-device-update-yocto
```

2. Once you've cloned the project you next need to change into our "working directory" where the individual layers (in Yocto these layers build up to an image like a cake or foundation). 

```sh
cd $project_root/iot-hub-device-update/yocto 
```

3. Once you're in the `yocto` directory we need to check out the Yocto Build "engine" or base layer so we can build with it. 

```sh
git clone --depth 1 --branch $yocto_release git://git.yoctoproject.org/poky
```

4. Next we need to checkout the rest of the dependency layers into the `yocto` directory

    1. Clone the SwUpdate meta layer 

    ```sh
    git clone --depth 1 --branch $yocto_release  https://github.com/sbabic/meta-swupdate
    ```

    2. Clone the Open Embedded meta layer. This layer include many modules (or layers) needed for building a Linux-base system.

    ```sh
    git clone --depth 1 --branch $yocto_release  git://git.openembedded.org/meta-openembedded
    ```

    3. Clone the Raspberry Pi meta layer. Since, the reference image that we are building is for a Raspberry Pi 4 hardware.

    ```sh
    git clone --depth 1 --branch $yocto_release git://git.yoctoproject.org/meta-raspberrypi
    ```

5. Within the same directory we are now going to include the Device Update for IotHub layers which builds Device Update agent and provides those artifacts for the `meta-raspberrypi-adu` layer. The `meta-raspberrypi-adu` layer then integrates the Device Update agent and modifies the image build instructions within `meta-raspberrypi` to output the `adu-base-image-<machine-name>.wic.gz` and `adu-update-image-<machine-name>.swu`. These are artifacts are what is used to test out Device Update for IotHub. For more information on these layers and their outputs please read the `README.md` in each of the repos. 

    1. From within the `yocto` directory checkout `meta-azure-device-update` at the version of Device Update you plan to use in your test. 

    ```sh
    git clone --branch $adu_release http://github.com/azure/meta-azure-device-update
    ```

    2. From within the `yocto` directory checkout `meta-raspberrypi-adu` at the version of Device Update you plan to use in your test. 

    ```sh
    git clone --branch $adu_release http://github.com/azure/meta-raspberrypi-adu
    ```

    3. (optional) If you're planning on using delta updates you can checkout the `meta-iot-hub-device-update-delta` layer that integrates that functionality into that agent. Please read the you can read more [here](https://learn.microsoft.com/azure/iot-hub-device-update/delta-updates) on learn.ms.com and [here](http://github.com/azure/meta-iot-hub-device-update-delta) within the meta-layer repository if you want to know more. 

    ```sh
    git clone --branch $adu_release http://github.com/azure/meta-iot-hub-device-update-delta
    ```

Next we move on to how to build the project assuming you've setup the project like above instructions. If you don't follow the setup instructions you will have to make modifications to `scripts/build.sh` to make sure the build works. 

### Building The Project Locally

#### Install Build Dependencies and Tools

For more information on the Yocto build system, the open embedded base image, and example builds please see [Yocto Project Quick Build](https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html#yocto-project-quick-build). 

Please look into `scripts/install-deps.sh` to determine what you may need to integrate into your build as you move forward with the project. 


1. From the `project_root` please execute the following command in your terminal

```sh
sudo ./scripts/install-deps.h
```

### Creating the Private Key for Sw Update Signing

To create the `*.swu` file you will need to provide the build system with a private key and password file so that it can sign the generated image and then create the Sw Update file. This is REQUIRED for a Sw Update update to function. You MUST put the private key and password file inside of the `repo-root-directory/keys` directory. The build will break if you do not complete this step. 

You can find the instructions for generating the private key and creating the password file [here](./keys/README.md). 


### Build The Project

To build the project you can either use our helper script or read the `build.sh` script and use your own terminal commands to build the layer. Keep in mind Yocto builds can take time depending on your machine. It's best to use a local cache if you're going to be running multiple builds. We use the `-o` option to specify the output directory which in turn builds a local cache that can expedite your local builds. An example invocation is specified below. It is executed from the repositories root folder. NOT the `yocto` directory.

```sh
./scripts/build.sh -c -t Debug -o ~/yocto_build_dir
```

#### New Features in build.sh

**Automatic Commit Hash Fetching**: When you specify `--adu-git-branch` without `--adu-git-commit`, the script automatically fetches and uses the HEAD commit hash of that branch. This ensures reproducible builds while staying current with your development branch.

**Parallel Builds**: Use `-j` and `--parallel-make` options to speed up compilation by using multiple CPU cores. By default, the script detects and uses all available CPU cores.

**Persistent SState Cache**: The `--rebuild` flag now preserves the sstate-cache directory, making subsequent full rebuilds much faster by reusing unchanged compilation artifacts.

```sh
# Use all CPU cores for parallel builds (auto-detected)
./scripts/build.sh -c -t Debug -o ~/yocto_build_dir

# Explicitly set parallel jobs
./scripts/build.sh -c -t Debug -o ~/yocto_build_dir -j 8 --parallel-make 8

# Full rebuild with cache preservation
./scripts/build.sh --rebuild -t Debug -o ~/yocto_build_dir --adu-git-branch feature/v-next
```

You can use:

```sh
./scripts/build.sh -h
```
to see the list of all options for the build.

If successful, the output image file (adu-base-image-raspberrypi4-64.wic.gz) and example .swu update file (adu-update-image.swu) should be located in `~/yocto_build_dir/tmp/deploy/images/raspberrypi4-64` directory. If you built for version 0.0.0.1 you will need to copy the base file out and run the build again to produce a Sw Update update (file ending `.swu`) to be used for the update. You need to do this to make a usable base and update image. 

```sh
.
├── adu-base-image-raspberrypi4-64.wic.gz
├── adu-update-image-raspberrypi4-64.swu
```

## Software Bill of Materials (SBOM)

### Overview

Yocto automatically generates comprehensive Software Bill of Materials (SBOM) in SPDX 2.2 format for all builds. The SBOM provides complete dependency tracking, license information, and package metadata for compliance and security auditing.

### SBOM Location

After a successful build, SBOM files are located at:

```sh
# Main SBOM archive (compressed, contains all packages)
~/yocto_build_dir/tmp/deploy/images/raspberrypi4-64/adu-base-image-raspberrypi4-64.spdx.tar.zst

# Individual SPDX JSON files for each package
~/yocto_build_dir/tmp/deploy/spdx/
```

### Extracting and Viewing SBOM

To extract and view the SBOM:

```sh
cd ~/yocto_build_dir/tmp/deploy/images/raspberrypi4-64

# Extract the SBOM archive
tar -xf adu-base-image-raspberrypi4-64.spdx.tar.zst

# List all SPDX files
ls -lh *.spdx.json | wc -l  # Shows total number of packages

# View Azure Device Update dependencies
python3 -m json.tool recipe-azure-device-update.spdx.json | less
```

### SBOM Contents

Each SPDX file contains:

- **Package Information**: Name, version, description, homepage
- **License Information**: SPDX license identifiers and copyright text
- **Dependencies**: Complete build and runtime dependency trees
- **Source Information**: Download URLs, Git repositories, commit hashes
- **File Checksums**: SHA1, SHA256 checksums for verification
- **Relationships**: Package relationships (DEPENDS, RDEPENDS, CONTAINS)

### Tracking meta-azure-device-update Dependencies

The `azure-device-update` package has the following direct build dependencies:

- azure-iot-sdk-c
- azure-sdk-for-cpp
- curl
- deliveryoptimization-agent
- deliveryoptimization-sdk
- catch2 (test framework)
- glibc, gcc-runtime (core libraries)

To view all dependencies:

```sh
cd ~/yocto_build_dir/tmp/deploy/images/raspberrypi4-64

# View recipe dependencies
python3 -c "
import json
with open('recipe-azure-device-update.spdx.json') as f:
    data = json.load(f)
    print('Build Dependencies:')
    for ref in data['externalDocumentRefs']:
        print('  -', ref['externalDocumentId'].replace('DocumentRef-dependency-recipe-', ''))
"

# View runtime dependencies
cat runtime-azure-device-update.spdx.json | python3 -m json.tool
```

### SBOM Format Details

The build generates SPDX 2.2 JSON format, which includes:

- **SPDX-2.2 Specification**: Industry-standard format recognized by security scanning tools
- **Namespace URIs**: Unique identifiers for each document
- **External References**: Links between packages showing dependency relationships
- **Creation Info**: Build timestamp, tool information, and creator details

### Using SBOM for Compliance

The generated SBOM can be used for:

1. **License Compliance**: Identify all open source licenses in your image
2. **Security Scanning**: Feed into vulnerability scanners (e.g., Grype, Trivy)
3. **Supply Chain Security**: Track component provenance
4. **Export Control**: Identify restricted components
5. **Regulatory Compliance**: Meet software transparency requirements

Example using with security scanners:

```sh
# Using Grype (example)
grype sbom:./adu-base-image-raspberrypi4-64.spdx.tar.zst

# Using Syft to convert formats (example)
syft convert ./adu-base-image-raspberrypi4-64.spdx.tar.zst -o cyclonedx-json
```

## Build Pipelines Status

| Board | Branch | Status |
|---|---|---|
| Raspberry Pi 4 | scarthgap | [![Build Status](https://dev.azure.com/azure-device-update/adu-linux-client/_apis/build/status/azure.iot-hub-device-update-yocto?branchName=scarthgap)](https://dev.azure.com/azure-device-update/adu-linux-client/_build/latest?definitionId=57&branchName=scarthgap)|

## GitHub Actions Workflows

GitHub Actions workflows are available in `.github/workflows/` for automated builds:

- **`yocto-build.yml`** - Standard builds on GitHub-hosted runners
- **`yocto-build-incremental.yml`** - Fast incremental builds for PRs
- **`yocto-build-self-hosted.yml`** - Production builds on self-hosted runners

**Note:** The GitHub Actions workflows automatically generate **test signing keys** for demonstration purposes. For production builds:
1. Generate secure keys following the instructions in `keys/README.md`
2. Store them in GitHub Secrets (`ADU_PRIVATE_KEY` and `ADU_KEY_PASSWORD`)
3. The self-hosted workflow will automatically use your production keys

See `.github/workflows/README.md` for detailed documentation on setup, usage, and configuration.


## Using Your Own Board and Guidance for Production Images

### Using Your Own Board

If you've tried out Device Update on RaspberryPi 4 and decided you want to try and use it on other hardware you will need to port the `meta-raspberrypi-adu` layer to support your own board. You can find information on what changes may be required [here](https://github.com/Azure/meta-raspberrypi-adu/README.md). Keep in mind the `meta-raspberrypi-adu` layer is provided as is. It's a proof of concept. The repository contains information on how to port the existing proof of concept but you will likely need to add better u-boot scripts, include proper signing key information, and many other small things to get your board up to snuff. These are board dependent and are not under the purview of the Device Update team. If you have a question/comment please make a GitHub issue and we can take a look at it. 


### Recommendations for Adapting for Production Images
Like is said at the beginning of this document this repository is intended to be a proof-of-concept. It is not intended to be a production ready drag and drop solution for building images to be used in the field. Within this repository We've made some recommendations for what might need to be changed but these recommendations should be taken as just that, recommendations. 


## Question? Comment? Bug?

Please create a GitHub issue and we'll get back to you as soon as we're able. Your feedback is integral to improving the agent, our software practices, and product direction. We're always happy to chat.

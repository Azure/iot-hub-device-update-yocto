# Building a Custom Linux-based System with Device Update for IotHub Agent using the Yocto Project
> **DISCLAIMER:**  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Introduction

This repository is a tool for experimenting with the integration of Device Update with a Yocto build system. Within this repo there are scripts for helping with builds, a directory structure for supplying keys to the swupdate signing process, and the azurepipelines definitions which can be used for setting up an Azure Dev Ops pipeline for generating the proof of concept image. 

None of the instructions, Azure Pipelines, scripts, or process described here is intended for production use. Do not use this repository as a basis for a production pipeline for integrating images. There are no promises made about the security and stability of the pipeline held within this repository. 

The repository and instructions create an image for the RaspberryPi 4 which can run script and image based updates using Device Update for IoT Hub. It's just to give you a taste of the power and utility of Device Update for IoT Hub.

For more information about the Device Update for IoT Hub, see the link to the source code of [Device Update Agent](https://github.com/Azure/iot-hub-device-update)

See [why we chose Raspberry Pi 4](#why-raspberry-pi-4) as the reference platform below.

## Table of Contents

- [Yocto Layers Overview](#yocto-layers-overview)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Delta Updates](#delta-updates-binary-diffpatch)
- [Software Bill of Materials (SBOM)](#software-bill-of-materials-sbom)
- [Build Pipelines](#build-pipelines-status)
- [Using Your Own Board](#using-your-own-board-and-guidance-for-production-images)
- [Why Raspberry Pi 4?](#why-raspberry-pi-4)

## Yocto Layers Overview

This repository integrates multiple Yocto/OpenEmbedded layers for building ADU-enabled images. Each layer has comprehensive documentation - please refer to the individual layer README files for detailed information.

### ADU-Specific Layers

| Layer | Purpose | Key Components | Documentation |
|-------|---------|----------------|---------------|
| **meta-azure-device-update** | Core ADU agent and Azure SDK infrastructure | ADU agent, Azure IoT SDK C, Azure SDK for C++, Delivery Optimization agent/SDK, systemd services | [README](yocto/meta-azure-device-update/README.md), [OOBE Service](yocto/meta-azure-device-update/docs/README-ADU-OOBE-SERVICE.md) |
| **meta-iot-hub-device-update-delta** | Delta update processing library | `libadudiffapi.so`, native diffgen tools, applydiff utility, e2fsprogs/jsoncpp patches | [README](yocto/meta-iot-hub-device-update-delta/README.md) |
| **meta-raspberrypi-adu** | Raspberry Pi 4 reference implementation | A/B partition management, U-Boot scripts, boot health validation, SWUpdate handlers | [README](yocto/meta-raspberrypi-adu/README.md), [A/B Architecture](yocto/meta-raspberrypi-adu/ADU-AB-UPDATE-ARCHITECTURE-GUIDE.md), [Porting Guide](yocto/meta-raspberrypi-adu/PORTING-GUIDE.md) |
| **meta-azure-device-update-samples** | Board-agnostic samples and delta generation workflow | Versioned update images (v1/v2/v3), automated delta generation, test packages, import manifests | [README](yocto/meta-azure-device-update-samples/README.md) |

### Third-Party Dependency Layers

| Layer | Purpose | Branch |
|-------|---------|--------|
| **poky** | Yocto reference distribution (bitbake, oe-core) | scarthgap |
| **meta-openembedded** | Common utilities (meta-oe, meta-python, meta-networking) | scarthgap |
| **meta-raspberrypi** | Raspberry Pi BSP support | scarthgap |
| **meta-swupdate** | SWUpdate framework for atomic image updates | scarthgap |
| **meta-clang** | LLVM/Clang toolchain (required for delta builds) | scarthgap |
| **meta-dotnet-core** | .NET Core runtime (optional, for advanced tooling) | scarthgap |

> **Note:** For detailed layer-specific documentation including recipes, configuration options, and troubleshooting, please refer to each layer's README file.

## Quick Start

On a machine installed with [Ubuntu 22.04 LTS (Jammy Jellyfish)](https://releases.ubuntu.com/22.04/),
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
    │       ├── meta-azure-device-update-samples  # Board-agnostic samples & delta demos
    │       ├── meta-iot-hub-device-update-delta  # Delta updates library
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

### Quick Steps

```sh
# Clone the main yocto repo that has install-deps.sh, setup.sh, and build.sh scripts.
git clone 'git@github.com:azure/iot-hub-device-update-yocto.git' --branch scarthgap "$HOME/adu_yocto/iot-hub-device-update-yocto"
git clone 'https://github.com/azure/iot-hub-device-update-yocto' --branch scarthgap "$HOME/adu_yocto/iot-hub-device-update-yocto"

cd $HOME/adu_yocto/iot-hub-device-update-yocto

# Install dev dependencies via APT packages.
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

### Build and Run Status Monitor for ARM64

The **Status Monitor** is a command-line diagnostic tool that continuously monitors the Azure Device Update agent's status on the device. It's useful for:

- **Debugging**: Watch agent state transitions during updates in real-time
- **Integration Testing**: Verify agent behavior during automated test runs
- **Troubleshooting**: Identify connectivity or deployment issues

The tool uses the ADU SDK to query agent status and supports multiple output formats (human-readable, JSON, CSV).

#### Build the Status Monitor

After a successful Yocto build, compile the status_monitor for ARM64:

```sh
cd ~/adu_yocto/iot-hub-device-update-yocto

# Build using Yocto cross-compiler
./scripts/build_status_monitor.sh

# Verify it's built for ARM64
file ~/adu_yocto/sdk_examples/status_monitor
```

#### Deploy and Run on Device

```sh
# Copy to Raspberry Pi
scp ~/adu_yocto/sdk_examples/status_monitor root@<rpi-ip>:/home/adu/

# SSH to device and run
ssh root@<rpi-ip>
cd /home/adu
chown adu:adu status_monitor
su -p adu
./status_monitor --help          # Show usage
./status_monitor -i 5            # Monitor every 5 seconds
./status_monitor -f json -c      # JSON format, changes only
```

## Prerequisites

Before getting started with this project, please get yourself familiar with the following topics:

- [The Yocto Project Software Overview](https://www.yoctoproject.org/software-overview/)
- [The Device Update for IoTHub Overview](http://github.com/azure/iot-hub-device-update)

### WiFi/Bluetooth Support (Optional)

**By default, WiFi and Bluetooth are DISABLED** in the built images. This is because enabling these features requires accepting a proprietary firmware license.

#### Why is WiFi/Bluetooth disabled by default?

The Raspberry Pi 4's onboard WiFi/Bluetooth chip (Broadcom BCM43455) requires proprietary firmware distributed under the **"synaptics-killswitch" license**. This is a non-open-source license with specific terms that must be explicitly accepted.

To ensure you are aware of and consent to these licensing terms, WiFi/Bluetooth support is disabled by default and must be explicitly enabled during the build.

#### How to enable WiFi/Bluetooth

Add the `--enable-wifi-bluetooth` flag to your build command:

```sh
./scripts/build.sh -c -t Debug -o ~/yocto_build_dir --enable-wifi-bluetooth
```

This will:
1. Accept the `synaptics-killswitch` license on your behalf
2. Include the BCM43455 WiFi/Bluetooth firmware in the image
3. Enable WiFi and Bluetooth hardware features

#### Alternative: Use Ethernet or USB WiFi/Bluetooth

If you prefer not to accept the proprietary license, you can:
- **Use wired Ethernet** for network connectivity (recommended for OTA updates)
- **Use USB WiFi/Bluetooth dongles** with open-source driver support (e.g., Atheros, RTL8188 chipsets)

#### License Information

- **License Name**: synaptics-killswitch
- **Firmware Package**: linux-firmware-rpidistro-bcm43455
- **What it controls**: WiFi and Bluetooth functionality on Raspberry Pi 4
- **License details**: [Raspberry Pi Firmware Repository](https://github.com/RPi-Distro/firmware-nonfree)

### Get Source Code

> **Note:** The recommended approach is to use `./scripts/setup.sh` which automates all layer cloning. The manual instructions below are provided for reference.

We only support the `scarthgap` release of the Yocto Project.

#### Automated Setup (Recommended)

```sh
# Clone this repository
git clone https://github.com/Azure/iot-hub-device-update-yocto -b scarthgap ~/adu_yocto/iot-hub-device-update-yocto
cd ~/adu_yocto/iot-hub-device-update-yocto

# Clone all required meta-layers automatically
./scripts/setup.sh
```

#### Manual Setup (Reference)

If you prefer manual control, clone layers individually into the `yocto/` directory:

```sh
cd ~/adu_yocto/iot-hub-device-update-yocto/yocto

# Core Yocto layers
git clone --depth 1 --branch scarthgap git://git.yoctoproject.org/poky
git clone --depth 1 --branch scarthgap git://git.openembedded.org/meta-openembedded
git clone --depth 1 --branch scarthgap https://github.com/sbabic/meta-swupdate
git clone --depth 1 --branch scarthgap git://git.yoctoproject.org/meta-raspberrypi

# ADU layers (use 'main' or specific release branch)
git clone --branch main https://github.com/azure/meta-azure-device-update
git clone --branch main https://github.com/azure/meta-raspberrypi-adu

# Optional: Delta update support (requires meta-clang)
git clone --branch scarthgap https://github.com/kraj/meta-clang
git clone --branch main https://github.com/azure/meta-iot-hub-device-update-delta
git clone --branch main https://github.com/azure/meta-azure-device-update-samples
```

### Building The Project Locally

#### Install Build Dependencies and Tools

For more information on the Yocto build system, the open embedded base image, and example builds please see [Yocto Project Quick Build](https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html#yocto-project-quick-build). 

```sh
sudo ./scripts/install-deps.sh
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

## Delta Updates (Binary Diff/Patch)

Delta updates dramatically reduce download sizes by generating small differential update files between SWU images (typically 90%+ bandwidth reduction).

### Architecture Overview

The delta update system uses a **dual-build approach**:

| Component | Purpose | Built For |
|-----------|---------|-----------|
| **Native tools** | Generate `.diff` files during Yocto build | x86_64 build host |
| **Target library** | Apply `.diff` files on device | ARM64 target |

**Key layers:**
- **meta-iot-hub-device-update-delta** — C++ delta processing library and native tools
- **meta-azure-device-update-samples** — Automated delta generation workflow with versioned images

### Quick Start

```sh
# Build base image, versioned update images, and delta files
./scripts/build.sh --local-sources ADU,ADU_DELTA \
  -o ~/adu_yocto/out/build -j 6 --parallel-make 6 \
  --rebuild adu-base-image,adu-update-image-v1,adu-update-image-v2,adu-update-image-v3,adu-delta-image
```

### Generated Artifacts

```sh
~/adu_yocto/out/build/tmp/deploy/images/raspberrypi4-64/
├── adu-base-image-raspberrypi4-64.wic.gz    # Base flashable image
├── adu-update-image-v1-*.swu                # Version 1 update package
├── adu-update-image-v2-*.swu                # Version 2 update package
├── adu-update-image-v3-*.swu                # Version 3 update package
├── adu-delta-v1-to-v2.diff                  # Delta: v1 → v2
├── adu-delta-v2-to-v3.diff                  # Delta: v2 → v3
└── adu-delta-v1-to-v3.diff                  # Delta: v1 → v3 (skip v2)
```

### Prerequisites

1. **.NET SDK 8.0** — Required for DiffGenTool (run `./scripts/install-deps.sh` to install)
2. **Pre-cache NuGet packages** — Run `dotnet restore` before BitBake (see layer docs)
3. **meta-clang** layer — Required dependency for delta builds

### Detailed Documentation

For comprehensive delta update documentation including:
- Build prerequisites and troubleshooting
- DiffGenTool architecture (C# → C++ interop)
- PAMZ format specification
- Verification and testing procedures

**See:** [meta-azure-device-update-samples/README.md](yocto/meta-azure-device-update-samples/README.md) and [meta-iot-hub-device-update-delta/README.md](yocto/meta-iot-hub-device-update-delta/README.md)

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

## Why Raspberry Pi 4?

We chose **Raspberry Pi 4** as the reference platform to demonstrate Azure Device Update (ADU) integration for several key reasons:

### Rationale
- **Accessibility**: Raspberry Pi 4 is widely available, affordable, and familiar to developers and IoT enthusiasts worldwide
- **Representative Architecture**: Demonstrates OTA update integration patterns applicable to a broad range of embedded Linux devices
- **ARM Cortex-A72 Baseline**: Provides a realistic example for mid-to-high performance embedded systems using modern ARM architecture

This implementation serves as a **reference example** showing how to integrate ADU into customer devices, enabling secure over-the-air (OTA) updates with SWUpdate and delta update capabilities.

### About ARM Cortex-A72

The Raspberry Pi 4 uses the **Broadcom BCM2711** SoC featuring a quad-core **ARM Cortex-A72** CPU clocked at up to 1.8 GHz [[Raspberry Pi 4 Tech Specs](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/specifications/)].

**Cortex-A72** [[ARM Official Docs](https://developer.arm.com/Processors/Cortex-A72)] is a high-performance, power-efficient 64-bit ARM processor core designed for:
- Mid-to-high performance mobile, embedded, and enterprise applications
- Out-of-order superscalar pipeline with advanced power management
- ARMv8-A architecture with support for AArch64 (64-bit) and AArch32 (32-bit) execution states

### Popular Platforms Using Cortex-A72

The Cortex-A72 architecture is used across diverse industries, making this reference implementation relevant to many real-world deployment scenarios:

#### 📟 Consumer & Development Platforms
- **Raspberry Pi 4** - Broadcom BCM2711 SoC with quad-core Cortex-A72 @ 1.8 GHz [[Wikipedia](https://en.wikipedia.org/wiki/Raspberry_Pi)] [[RaspberryPi.com](https://www.raspberrypi.com)]

#### 📱 Mobile & Embedded SoCs
- **Qualcomm Snapdragon 650/652/653** - Mid-tier smartphone chips with Cortex-A72 cores [[Wikipedia](https://en.wikipedia.org/wiki/List_of_Qualcomm_Snapdragon_systems_on_chips)]

#### 🔧 Industrial, Automotive & Networking SoCs
- **NXP i.MX8 family** - High-performance automotive and industrial processors [[Wikipedia](https://en.wikipedia.org/wiki/I.MX)] [[NXP.com](https://www.nxp.com/products/processors-and-microcontrollers/arm-processors/i-mx-applications-processors:IMX_HOME)]
- **NXP Layerscape series** - Edge networking and NFV platforms:
  - LS1026A, LS1046A, LS2044A/LS2084A, LS2048A/LS2088A
  - LX2160A, LX2120A, LX2080A - Up to 16 Cortex-A72 cores [[Wikipedia](https://en.wikipedia.org/wiki/QorIQ)] [[NXP.com](https://www.nxp.com/products/processors-and-microcontrollers/arm-processors/layerscape-processors:LAYERSCAPE)] [[SolidRun](https://www.solid-run.com)]
- **Texas Instruments Jacinto 7** - Automotive ADAS and gateway platforms [[Wikipedia](https://en.wikipedia.org/wiki/Texas_Instruments_DRA7xx)]

#### 🎥 Media & AI Edge SoCs
- **Rockchip RK3399, RK3576** - Chromebooks, edge AI devices, and media processors [[Wikipedia](https://en.wikipedia.org/wiki/Rockchip)]


#### 🔌 Industrial Vision & Multimedia SoCs
- **Texas Instruments AM68x family** - Dual-core Cortex-A72 @ 2 GHz for vision/multimedia applications [[TI.com](https://www.ti.com)]

### Summary by Category

| Category | Common SoCs / Platforms |
|----------|------------------------|
| **Single-board computers** | Raspberry Pi 4 (Broadcom BCM2711) |
| **Smartphones / mobile devices** | Snapdragon 650/652/653 |
| **Embedded / automotive SoCs** | NXP i.MX8, TI Jacinto 7 |
| **Enterprise / networking chips** | NXP Layerscape LX/LS series |
| **Media/vision processing SoCs** | Rockchip RK3399/3576, TI AM68x series |

By building on Raspberry Pi 4, developers gain insights applicable to a wide ecosystem of Cortex-A72-based devices across consumer, industrial, automotive, and cloud infrastructure domains.


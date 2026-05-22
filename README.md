# Azure Device Update for IoT Hub - Yocto Integration Reference
> **DISCLAIMER:**
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Introduction

This repository serves as a **reference implementation** for device builders who want to integrate **Azure Device Update (ADU)** for IoT Hub into their custom Linux-based operating systems built with the Yocto Project. It demonstrates how to enable secure, reliable over-the-air (OTA) firmware updates using **A/B partition rootfs update strategies** for embedded Linux devices.

### What This Repository Provides

This repository offers high-level guidance and reference materials for integrating Azure Device Update into your custom embedded Linux OS:

- **Overview of A/B firmware update flow** — Understanding how dual-partition rootfs updates work, including boot switching, health validation, and automatic rollback mechanisms
- **Reference OS image build guide** — High-level instructions for building an ADU-enabled Yocto image for Raspberry Pi 4
- **Meta-layer overview** — Explanation of each Yocto layer's purpose, including Microsoft-provided ADU layers and third-party dependencies
- **Build scripts and tooling** — Helper scripts to automate layer cloning, dependency installation, and image compilation
- **Pipeline examples** — CI/CD templates demonstrating automated build workflows
- **Delta update capabilities** — Introduction to bandwidth-efficient OTA updates using binary diff/patch

### Important Notes

⚠️ **This is a reference implementation, NOT production-ready**:
- The Raspberry Pi 4 implementation (`meta-raspberrypi-adu`) is intended as a **learning example** and **reference architecture**
- It demonstrates concepts and patterns that can be adapted to your custom hardware
- **Do not deploy this implementation to production devices without significant hardening and customization**
- Each hardware platform requires specific adaptations for bootloader integration, partition management, and recovery mechanisms

For more information about Azure Device Update for IoT Hub, see the [Device Update Agent source code](https://github.com/Azure/iot-hub-device-update/tree/feature/vnext-delta).

See [Why Raspberry Pi 4?](#why-raspberry-pi-4) for rationale behind the reference platform choice.

## Table of Contents

- [Introduction](#introduction)
- [A/B Rootfs Update Architecture Overview](#ab-rootfs-update-architecture-overview)
  - [What is A/B Update?](#what-is-ab-update)
  - [Industry Implementation Guidelines](#industry-implementation-guidelines)
  - [Microsoft Reference Implementation](#microsoft-reference-implementation)
- [Microsoft-Provided Yocto Layers](#microsoft-provided-yocto-layers)
- [Third-Party Dependency Layers](#third-party-dependency-layers)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Delta Updates](#delta-updates-binary-diffpatch)
- [Software Bill of Materials (SBOM)](#software-bill-of-materials-sbom)
- [Build Pipelines](#build-pipelines-status)
- [Porting to Your Own Hardware](#porting-to-your-own-hardware)
- [Why Raspberry Pi 4?](#why-raspberry-pi-4)

## A/B Rootfs Update Architecture Overview

### What is A/B Update?

**A/B update** (also called dual-bank or dual-copy update) is a robust firmware update strategy that maintains **two independent copies of the root filesystem** on the device. At any given time:
- **Active partition (Slot A or B)**: Currently running the operating system
- **Inactive partition (Slot B or A)**: Available for receiving updates

During an OTA update:
1. New firmware is written to the **inactive partition** while the system continues running
2. Bootloader switches to the **newly updated partition** on next reboot
3. Boot health checks verify the system is functional
4. If verification fails, bootloader automatically **rolls back** to the previous working partition

This approach provides:
- **Zero-downtime updates**: System remains operational during download/installation
- **Atomic updates**: Either fully succeeds or fully rolls back—no partial/broken states
- **Fast recovery**: Instant rollback to last-known-good partition on failure
- **Safe experimentation**: Test updates without risking device bricking

### Industry Implementation Guidelines

Implementing A/B updates for production embedded Linux devices requires careful design across multiple system components:

#### 1. Partition Layout

A typical A/B partition scheme includes:

| Partition | Purpose | Size Considerations |
|-----------|---------|-------------------|
| **Boot** | Bootloader, kernel, device trees | Fixed size (typically 64-256 MB) |
| **RootFS A** | Primary root filesystem (Slot A) | Full OS image size + ~10% headroom |
| **RootFS B** | Secondary root filesystem (Slot B) | Same as RootFS A |
| **Data** | User data, persistent config, logs | Device-specific requirements |
| **Recovery** (optional) | Minimal recovery environment | Minimal size (100-500 MB) |

**Storage overhead**: A/B updates require approximately **2.2-2.5x** the rootfs size compared to single-partition designs.

**Partition alignment**: Use 4 MB boundaries for optimal flash wear-leveling on eMMC/SD cards.

#### 2. Bootloader Requirements

The bootloader is **critical** for A/B update reliability. It must support:

| Feature | Purpose | Example Implementation |
|---------|---------|----------------------|
| **Dual-boot selection** | Choose between Slot A/B | U-Boot `boot_partition` variable (e.g., "rootA", "rootB") |
| **Boot attempt counter** | Track consecutive failed boots | U-Boot `boot_attempts` variable (incremented per boot) |
| **Rollback trigger** | Revert to previous slot on failure | U-Boot logic comparing `boot_attempts` vs `max_boot_attempts` |
| **Update status flags** | Track update validation state | U-Boot `upgrade_available` flag and `boot_result` status |
| **Last known good tracking** | Remember last successful partition | U-Boot `last_known_good_partition` variable |
| **Secure boot** (production) | Verify kernel/rootfs signatures | U-Boot Verified Boot (FIT images) or custom solution |

> **Note:** The "Example Implementation" column shows actual variable names from the Raspberry Pi 4 reference implementation in `meta-raspberrypi-adu`. Your bootloader may use different variable names, state values, or mechanisms to achieve the same functionality.

**Common bootloaders with A/B support**:
- **U-Boot** (recommended for embedded Linux): Flexible scripting, wide hardware support
- **GRUB**: x86/ARM platforms, supports BLS (Boot Loader Specification)
- **Barebox**: Alternative to U-Boot, strong A/B support
- **Custom bootloaders**: Hardware-specific implementations (e.g., Qualcomm LK, TI MLO)

#### 3. Boot Health Validation

After switching to a new partition, the system must **prove** it's healthy before committing the update:

**Recommended validation stages** (customize based on your device requirements):

1. **Early boot checks** (in bootloader):
   - Verify filesystem integrity (ext4 `e2fsck`, SquashFS checksums)
   - Check kernel/DTB signatures (secure boot)

2. **System initialization checks** (during systemd startup):
   - Critical services started successfully
   - Network connectivity established
   - Required hardware devices present

3. **Application-level checks**:
   - ADU agent successfully connects to IoT Hub
   - Application-specific health checks pass

> **Note:** These validation stages are recommendations. You can add additional checks specific to your device (e.g., sensor readings, peripheral functionality, database connectivity, license validation) or remove checks that don't apply to your use case. The key requirement is that your system can reliably determine whether the new partition is functional before committing the update.

**Validation timeout and rollback mechanism**:
- The **OS-level boot validation service** enforces a time-based timeout (default: 5 minutes via systemd `TimeoutStartSec`)
- If validation doesn't complete within this window, the service fails and the system reboots
- The **bootloader** tracks failed boot attempts using a counter (`boot_attempts`)
- After consecutive failures exceed the threshold (default: 5 attempts via `max_boot_attempts`), the bootloader automatically rolls back to the last-known-good partition
- This two-tier approach ensures reliable recovery: immediate timeout detection at the OS level, followed by count-based rollback at the bootloader level

#### 4. Atomic Update Mechanisms

To ensure reliability, updates must be **atomic**—either fully applied or fully rolled back:

- **SWUpdate** (chosen for demonstration purposes): Supports compressed images.
- **RAUC**: Alternative update framework with bundle encryption and adaptive updates
- **OSTree**: Git-like rootfs versioning (used by Fedora IoT, Automotive Grade Linux)
- **Custom solutions**: Block-level imaging with integrity verification

#### 5. Persistent Data Handling

Separate **user data** from the root filesystem to avoid data loss during updates:

- **Dedicated data partition**: Mount at `/data`, `/var/lib`, or custom paths
- **Overlay filesystems**: Use `overlayfs` to merge read-only rootfs with writable data layer
- **Bind mounts**: Map persistent directories (e.g., `/etc`, `/home`) to data partition
- **Database migrations**: Handle schema changes gracefully across updates

### Microsoft Reference Implementation

The **`meta-raspberrypi-adu`** layer included in this repository demonstrates a **complete A/B update implementation** for Raspberry Pi 4. It is provided as a **reference architecture** to help developers understand how to integrate ADU into their own hardware platforms.

#### What meta-raspberrypi-adu Demonstrates

| Component | Implementation Details | Purpose |
|-----------|----------------------|---------|
| **Partition Layout** | 3-partition scheme: boot, rootfs_a, rootfs_b | Dual-bank rootfs strategy |
| **U-Boot Integration** | Custom boot scripts with health validation | A/B selection and rollback logic |
| **SWUpdate Handler** | Atomic image updates with streaming | Reliable OTA mechanism |
| **ADU Agent Integration** | systemd service for IoT Hub connectivity | Cloud-orchestrated updates |
| **Boot Health Checks** | Systemd targets for validation | Automatic rollback on failure |

**Key files to review**:
- [A/B Update Architecture Guide](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/ADU-AB-UPDATE-ARCHITECTURE-GUIDE.md)
- [Porting Guide](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/PORTING-GUIDE.md)
- [README.md](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/README.md)

#### ⚠️ Production Deployment Warning

**The `meta-raspberrypi-adu` implementation is NOT suitable for production use without significant modifications:**

1. **Security hardening required**:
   - Replace example signing keys with production HSM-backed keys
   - Enable U-Boot verified boot (FIT image signatures)
   - Implement secure storage for IoT Hub credentials
   - Harden SSH access and disable debug interfaces

2. **Hardware-specific adaptations needed**:
   - Raspberry Pi's SD card storage is unsuitable for industrial/automotive use
   - Replace with eMMC, SPI NOR, or NAND flash with wear-leveling
   - Adjust partition sizes for your application footprint
   - Implement watchdog timer integration for recovery

3. **Reliability enhancements required**:
   - Add power-loss recovery mechanisms
   - Implement factory reset capabilities
   - Enhance logging and diagnostics for field troubleshooting
   - Add redundancy for critical boot components

4. **Regulatory compliance**:
   - Validate against industry standards (IEC 62443, ISO 26262 for automotive)
   - Perform extensive stress testing (power-loss, network interruption, flash wear)
   - Implement audit logging for security certifications

**Recommendation**: Treat `meta-raspberrypi-adu` as a **learning tool** and **architectural blueprint**. Use it to understand the concepts, then design a production implementation tailored to your hardware, security requirements, and operational environment.

For detailed porting guidance, see [Porting to Your Own Hardware](#porting-to-your-own-hardware).

## Microsoft-Provided Yocto Layers

These layers are developed and maintained by Microsoft to enable Azure Device Update integration. **All Microsoft layers should use the `feature/vnext-delta` branch** for the latest delta update capabilities:

| Layer | Purpose | Branch | Key Components | Documentation |
|-------|---------|--------|----------------|---------------|
| **[meta-azure-device-update](https://github.com/Azure/meta-azure-device-update)** | Core ADU agent and Azure SDK infrastructure | `feature/vnext-delta` | ADU agent, Azure IoT SDK C, Azure SDK for C++, Delivery Optimization agent/SDK, systemd services | [README](https://github.com/Azure/meta-azure-device-update/blob/feature/vnext-delta/README.md) |
| **[meta-iot-hub-device-update-delta](https://github.com/Azure/meta-iot-hub-device-update-delta)** | Delta update processing library | `feature/vnext-delta` | `libadudiffapi.so`, native diffgen tools, applydiff utility, e2fsprogs/jsoncpp patches | [README](https://github.com/Azure/meta-iot-hub-device-update-delta/blob/feature/vnext-delta/README.md) |
| **[meta-raspberrypi-adu](https://github.com/Azure/meta-raspberrypi-adu)** | Raspberry Pi 4 reference implementation | `feature/vnext-delta` | A/B partition management, U-Boot scripts, boot health validation, SWUpdate handlers | [README](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/README.md), [A/B Architecture](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/ADU-AB-UPDATE-ARCHITECTURE-GUIDE.md), [Porting Guide](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/PORTING-GUIDE.md) |
| **[meta-azure-device-update-samples](https://github.com/Azure/meta-azure-device-update-samples)** | Board-agnostic samples and delta generation workflow | `feature/vnext-delta` | Versioned update images (v1/v2/v3), automated delta generation, test packages, import manifests | [README](https://github.com/Azure/meta-azure-device-update-samples/blob/feature/vnext-delta/README.md) |

### Layer Purposes Explained

#### meta-azure-device-update
**Core ADU functionality**: Provides the Device Update agent that runs on the device, communicates with Azure IoT Hub, downloads updates, and orchestrates the update process. Includes all necessary Azure SDKs and the Delivery Optimization client for efficient downloads.

**Use case**: Required for all ADU-enabled devices.

#### meta-iot-hub-device-update-delta
**Bandwidth optimization**: Enables delta updates by providing libraries to generate and apply binary diffs between update packages. Reduces OTA download sizes by 90%+ for incremental updates.

**Use case**: Optional but recommended for devices with bandwidth constraints or metered connections.

#### meta-raspberrypi-adu
**Reference implementation**: Demonstrates a complete A/B update architecture specifically for Raspberry Pi 4. Shows how to integrate bootloader scripting, partition management, and recovery mechanisms with ADU.

**Use case**: Learning tool and reference for porting ADU to custom hardware. **Not for production use as-is.**

#### meta-azure-device-update-samples
**Testing and CI/CD**: Provides versioned image recipes and automated delta generation for building test update sequences (v1→v2→v3) and verifying end-to-end update workflows.

**Use case**: Development, testing, and CI/CD pipeline automation.

## Third-Party Dependency Layers

These community-maintained layers provide essential Yocto/OpenEmbedded functionality. **Use the `scarthgap` branch** (latest Yocto LTS release) for all third-party layers:

| Layer | Purpose | Branch |
|-------|---------|--------|
| **[poky](https://git.yoctoproject.org/poky)** | Yocto reference distribution (BitBake, OE-Core) | `scarthgap` |
| **[meta-openembedded](https://git.openembedded.org/meta-openembedded)** | Common utilities (meta-oe, meta-python, meta-networking) | `scarthgap` |
| **[meta-raspberrypi](https://git.yoctoproject.org/meta-raspberrypi)** | Raspberry Pi BSP support | `scarthgap` |
| **[meta-swupdate](https://github.com/sbabic/meta-swupdate)** | SWUpdate framework for atomic image updates | `scarthgap` |
| **[meta-clang](https://github.com/kraj/meta-clang)** | LLVM/Clang toolchain (required for delta builds) | `scarthgap` |

> **Note:** For detailed layer-specific documentation including recipes, configuration options, and troubleshooting, please refer to each layer's README file.

## Prerequisites

Before getting started with this project, please get yourself familiar with the following topics:

- [The Yocto Project Software Overview](https://www.yoctoproject.org/software-overview/)
- [The Device Update for IoTHub Overview](http://github.com/azure/iot-hub-device-update)

### Get Source Code

> **Note:** The recommended approach is to use `./scripts/setup.sh` which automates all layer cloning. The manual instructions below are provided for reference.

We only support the `scarthgap` release of the Yocto Project.

#### Automated Setup (Recommended)

```sh
# Clone this repository
git clone https://github.com/Azure/iot-hub-device-update-yocto -b feature/vnext-delta ~/adu_yocto/iot-hub-device-update-yocto
cd ~/adu_yocto/iot-hub-device-update-yocto

# Clone all required meta-layers automatically
./scripts/setup.sh
```

The `setup.sh` script automatically clones:
- **Microsoft ADU layers** using branch `feature/vnext-delta`
- **Third-party layers** using branch `scarthgap`

#### Manual Setup (Reference)

If you prefer manual control, clone layers individually into the `yocto/` directory:

```sh
cd ~/adu_yocto/iot-hub-device-update-yocto/yocto

# Core Yocto layers (use scarthgap branch)
git clone --depth 1 --branch scarthgap git://git.yoctoproject.org/poky
git clone --depth 1 --branch scarthgap git://git.openembedded.org/meta-openembedded
git clone --depth 1 --branch scarthgap https://github.com/sbabic/meta-swupdate
git clone --depth 1 --branch scarthgap git://git.yoctoproject.org/meta-raspberrypi
git clone --depth 1 --branch scarthgap https://github.com/kraj/meta-clang

# Microsoft ADU layers (use feature/vnext-delta branch)
git clone --branch feature/vnext-delta https://github.com/Azure/meta-azure-device-update
git clone --branch feature/vnext-delta https://github.com/Azure/meta-iot-hub-device-update-delta
git clone --branch feature/vnext-delta https://github.com/Azure/meta-raspberrypi-adu
git clone --branch feature/vnext-delta https://github.com/Azure/meta-azure-device-update-samples
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
~/adu_yocto/out/build/tmp/deploy/images/raspberrypi4-64/
├── adu-base-image-raspberrypi4-64.wic.gz
```

## Delta Updates (Binary Diff/Patch)

Delta updates dramatically reduce download sizes by generating small differential update files between SWU images (typically 40%+ bandwidth reduction).

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
./scripts/build.sh \
  -o ~/adu_yocto/out -j 6 --parallel-make 6 \
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

### Customer Distribution

To package the delta tools for customer delivery (standalone, without requiring a Yocto build environment):

```sh
./scripts/package-delta-tools.sh --build-dir ~/adu_yocto/out/build --version 3.0.0
```

This produces self-contained tarballs with all dependencies bundled. See the [Delta Tools Distribution Guide](docs/delta-tools-distribution.md) for full details including architecture, dependency inventory, supported platforms, and security considerations.

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
| Raspberry Pi 4 | feature/vnext-delta | [![Build Status](https://dev.azure.com/msazure/One/_apis/build/status%2FOneBranch%2Fazure-iot-adu%2FClient%2Fazure-iot-adu-client.gen1.yocto?repoName=ADUGen1.YoctoBuildPipeline&branchName=feature%2Fvnext-delta)](https://dev.azure.com/msazure/One/_build/latest?definitionId=438576&repoName=ADUGen1.YoctoBuildPipeline&branchName=feature%2Fvnext-delta)|

## Porting to Your Own Hardware

### Overview

The `meta-raspberrypi-adu` layer provided in this repository demonstrates a complete A/B update implementation for Raspberry Pi 4. To enable Azure Device Update on your custom hardware, you'll need to **port** this reference implementation by adapting it to your device's specific characteristics.

### Prerequisites for Porting

Before starting, ensure you have:

1. **Working Yocto BSP** for your target hardware
2. **Bootloader with A/B support** (U-Boot recommended, or custom bootloader with equivalent capabilities)
3. **Sufficient storage** for dual rootfs partitions (2.2-2.5x single rootfs size)
4. **Network connectivity** (Ethernet, WiFi, cellular, etc.)
5. **Understanding of your hardware's boot process** (bootloader, partition layout, firmware loading)

### Porting Steps

#### 1. Create a Custom ADU Layer

Create a new meta-layer for your device (e.g., `meta-mydevice-adu`):

```sh
# Create layer structure
mkdir -p meta-mydevice-adu/recipes-{bsp,core,support}
mkdir -p meta-mydevice-adu/conf

# Create layer.conf
cat > meta-mydevice-adu/conf/layer.conf << 'EOF'
BBPATH .= ":${LAYERDIR}"
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "mydevice-adu"
BBFILE_PATTERN_mydevice-adu = "^${LAYERDIR}/"
BBFILE_PRIORITY_mydevice-adu = "10"

LAYERDEPENDS_mydevice-adu = "core swupdate azure-device-update"
LAYERSERIES_COMPAT_mydevice-adu = "scarthgap"
EOF
```

#### 2. Adapt Partition Layout

Modify your device's partition table to support A/B updates. Refer to the [Industry Implementation Guidelines](#industry-implementation-guidelines) above.

**Example for eMMC (adjust sizes for your device)**:

```
/dev/mmcblk0p1  -  64 MB   - Boot (kernel, DTB, bootloader env)
/dev/mmcblk0p2  -  2 GB    - RootFS A (Slot A)
/dev/mmcblk0p3  -  2 GB    - RootFS B (Slot B)
/dev/mmcblk0p4  -  4 GB    - Data (persistent storage)
```

Create a WKS file in your layer:

```sh
# recipes-bsp/images/mydevice-image.wks
part /boot --source bootimg --ondisk mmcblk0 --fstype=vfat --label boot --active --align 4096 --size 64M
part / --source rootfs --ondisk mmcblk0 --fstype=ext4 --label rootfs_a --align 4096 --size 2048M
part / --source rootfs --ondisk mmcblk0 --fstype=ext4 --label rootfs_b --align 4096 --size 2048M
part /data --ondisk mmcblk0 --fstype=ext4 --label data --align 4096 --size 4096M --fsoptions "defaults,noatime"
```

#### 3. Customize Bootloader Integration

**If using U-Boot**, adapt the boot scripts from `meta-raspberrypi-adu` to your device:

- Review [recipes-bsp/rpi-u-boot-scr](https://github.com/Azure/meta-raspberrypi-adu/tree/feature/vnext-delta/recipes-bsp/rpi-u-boot-scr)
- Modify environment variables for your partition scheme
- Adjust device tree and kernel loading commands
- Implement rollback logic based on boot counters

**If using a custom bootloader**, implement equivalent functionality:

- Boot slot selection (A/B switching)
- Boot attempt counter and automatic rollback
- Update status flags (unverified/verified/corrupted)
- Environment persistence across reboots

#### 4. Integrate SWUpdate

Configure SWUpdate for your device's update strategy:

```sh
# recipes-support/swupdate/swupdate_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://swupdate.cfg \
    file://09-swupdate-args \
"

# Add device-specific SWUpdate configuration
do_install:append() {
    install -d ${D}${sysconfdir}/swupdate
    install -m 0644 ${WORKDIR}/swupdate.cfg ${D}${sysconfdir}/swupdate/
}
```

Create `sw-description` handler for your partition layout (adapt from `meta-raspberrypi-adu` examples).

#### 5. Configure ADU Agent

Create a device-specific ADU configuration:

```sh
# recipes-azure/azure-device-update/azure-device-update_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://du-config.json"

do_install:append() {
    install -m 0644 ${WORKDIR}/du-config.json ${D}${sysconfdir}/adu/
}
```

Update `du-config.json` with your device's capabilities:

```json
{
  "schemaVersion": "1.2",
  "aduShellTrustedUsers": ["adu", "do"],
  "manufacturer": "MyCompany",
  "model": "MyDevice-v1",
  "compatPropertyNames": ["manufacturer", "model"],
  "agents": [
    {
      "name": "main",
      "runas": "adu",
      "connectionSource": {
        "connectionType": "AIS",
        "connectionData": ""
      },
      "manufacturer": "MyCompany",
      "model": "MyDevice-v1"
    }
  ]
}
```

#### 6. Implement Boot Health Validation

The Raspberry Pi 4 reference implementation provides a complete boot validation system that you can adapt for your device.

**Reference implementation**: [recipes-support/adu-boot-validation](https://github.com/Azure/meta-raspberrypi-adu/tree/feature/vnext-delta/recipes-support/adu-boot-validation)

Key components to review and adapt:

- **[adu-boot-validation.bb](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/recipes-support/adu-boot-validation/adu-boot-validation.bb)** — Recipe for boot validation service
- **[adu-boot-validation.service](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/recipes-support/adu-boot-validation/files/adu-boot-validation.service)** — systemd service unit with timeout configuration
- **[adu-boot-validation.sh](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/recipes-support/adu-boot-validation/files/adu-boot-validation.sh)** — Main validation script with configurable checks
- **[boot-validation.conf](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/recipes-support/adu-boot-validation/files/boot-validation.conf)** — Configuration file for timeout and validation stages

The reference implementation includes:
- Configurable validation timeout (default: 5 minutes)
- Health check framework with critical/warning severity levels
- U-Boot environment variable integration for boot confirmation
- Automatic rollback on validation failure
- Manual override capability for debugging

Adapt these components to your device's specific requirements (network connectivity, critical services, hardware sensors, etc.).

### Detailed Porting Documentation

For comprehensive guidance on porting ADU to your hardware, refer to:

- **[meta-raspberrypi-adu Porting Guide](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/PORTING-GUIDE.md)** — Step-by-step instructions for adapting the reference implementation
- **[A/B Update Architecture Guide](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/ADU-AB-UPDATE-ARCHITECTURE-GUIDE.md)** — Deep dive into the architecture and design decisions
- **[meta-raspberrypi-adu README](https://github.com/Azure/meta-raspberrypi-adu/blob/feature/vnext-delta/README.md)** — Layer overview and configuration options

### Common Porting Challenges

| Challenge | Solution |
|-----------|----------|
| **Different bootloader** | Implement equivalent A/B logic in your bootloader's scripting language |
| **Limited storage** | Use SquashFS for read-only rootfs, optimize image size, consider read-only overlays |
| **No dual partition support** | Implement container-based updates (Docker/Podman) or OSTree atomic updates |
| **Secure boot requirements** | Enable U-Boot verified boot (FIT images) or implement hardware-backed secure boot |
| **Power-loss recovery** | Add watchdog timer integration, implement atomic update commits, enhance rollback logic |

### Testing Your Port

After porting, thoroughly test:

1. **Initial deployment**: Flash base image and verify device boots
2. **Successful update**: Deploy update package, verify it applies and boots correctly
3. **Failed update**: Simulate failures (corrupted image, network interruption, power loss)
4. **Rollback**: Verify automatic rollback to previous working partition
5. **Multi-generation updates**: Test v1→v2→v3 update sequences
6. **Delta updates**: Verify delta update download and application

### Getting Help

If you encounter issues during porting:

1. **Review layer documentation** linked above
2. **Search existing GitHub issues** in Microsoft ADU layer repositories
3. **Create a GitHub issue** with details about your hardware, Yocto version, and specific problem
4. **Join the community** — We're here to help!

⚠️ **Production Reminder**: Even after successful porting, perform extensive field testing before production deployment. See [Production Deployment Warning](#️-production-deployment-warning) above.


## Questions? Feedback? Issues?

While this reference implementation is provided as-is without warranty (see disclaimer above), we genuinely welcome your feedback, questions, and contributions!

**We're here to help:**

- **Questions or discussions?** [Open a GitHub Discussion](https://github.com/Azure/iot-hub-device-update-yocto/discussions) — Ask about architecture, porting challenges, or best practices
- **Found a bug or issue?** [Create a GitHub Issue](https://github.com/Azure/iot-hub-device-update-yocto/issues) — We'll investigate and work to address it
- **Have suggestions?** We'd love to hear them! Your feedback helps improve this reference implementation and guide future development

The development team is actively monitoring this repository and genuinely happy to chat about Azure Device Update, A/B update architectures, Yocto integration patterns, or any challenges you're facing. Your real-world experiences help us make this reference implementation more useful for the entire community.

**Community contributions are welcome!** If you've solved a porting challenge, optimized a recipe, or improved documentation, consider submitting a pull request to help others.

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


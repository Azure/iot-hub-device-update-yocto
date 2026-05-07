# Building the ADU Yocto Project

This guide covers how to build Yocto Linux images with
[Azure Device Update](https://learn.microsoft.com/en-us/azure/iot-hub-device-update/)
(ADU) agent support for multiple hardware boards.

## Supported Boards

| Board | Machine | BSP Layer | Board Integration Layer |
|---|---|---|---|
| Raspberry Pi 4 (64-bit) | `raspberrypi4-64` | `meta-raspberrypi` | `meta-raspberrypi-adu` |
| QEMU ARM64 | `qemuarm64` | *(built-in)* | `meta-qemu-adu` |
| NXP i.MX8ULP EVK | `imx8ulp-lpddr4-evk` | `meta-freescale` | `meta-imx8ulp-adu` |

## Prerequisites

### WSL2 Setup (Windows)

Builds run inside WSL2 with Ubuntu 22.04 or later.

```bash
# Import an Ubuntu rootfs
wsl --import yocto-build C:\wsl\yocto-build ubuntu.wsl
```

Allocate sufficient resources in `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
memory=48GB
processors=14
```

### Install Build Dependencies

```bash
apt-get update && apt-get install -y \
  gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat \
  cpio python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping \
  python3-git python3-jinja2 python3-subunit zstd liblz4-tool file locales libacl1

locale-gen en_US.UTF-8
```

### Install kas

[kas](https://kas.readthedocs.io/) is the declarative build tool that composes
Yocto layers and settings from YAML config files.

```bash
pip3 install --break-system-packages kas
```

### Create a Non-Root Build User

Bitbake refuses to run as root. Create a dedicated user:

```bash
useradd -m yocto
su - yocto
```

### Clone Repositories

All repos live under a common `sources/` directory:

```bash
cd /path/to/sources

# Yocto core + community layers (scarthgap release)
git clone -b scarthgap https://git.yoctoproject.org/poky
git clone -b scarthgap https://git.openembedded.org/meta-openembedded
git clone -b scarthgap https://github.com/kraj/meta-clang.git
git clone -b scarthgap https://github.com/sbabic/meta-swupdate.git
git clone -b scarthgap https://git.yoctoproject.org/meta-raspberrypi
git clone -b scarthgap https://github.com/Freescale/meta-freescale.git

# Azure ADU repos
git clone https://github.com/Azure/iot-hub-device-update-yocto.git
git clone https://github.com/Azure/meta-azure-device-update.git
git clone https://github.com/Azure/meta-raspberrypi-adu.git
git clone https://github.com/Azure/meta-qemu-adu.git
git clone https://github.com/Azure/meta-imx8ulp-adu.git
```

The final directory tree should look like this:

```
sources/
├── iot-hub-device-update-yocto/   # Build orchestrator + kas configs
├── poky/                          # Yocto core (scarthgap)
├── meta-openembedded/             # OE layers
├── meta-clang/                    # Clang toolchain
├── meta-swupdate/                 # SWUpdate framework
├── meta-freescale/                # NXP BSP (for i.MX8ULP)
├── meta-raspberrypi/              # RPi BSP
├── meta-azure-device-update/      # ADU agent (board-agnostic)
├── meta-iot-hub-device-update-delta/ # Delta updates (optional)
├── meta-raspberrypi-adu/          # RPi board integration
├── meta-qemu-adu/                 # QEMU board integration
└── meta-imx8ulp-adu/              # i.MX8ULP board integration
```

## Build System Overview

### kas Config Files

All kas configs live in `kas/` inside the `iot-hub-device-update-yocto` repo.
You combine them by separating paths with `:` on the command line.

| Config | Purpose |
|---|---|
| `base.yml` | Common layers (poky, meta-oe, meta-clang, meta-swupdate, meta-azure-device-update), systemd init, shared cache settings |
| `machine-rpi4.yml` | Raspberry Pi 4: adds `meta-raspberrypi` + `meta-raspberrypi-adu` |
| `machine-qemu.yml` | QEMU ARM64: adds `meta-qemu-adu` |
| `machine-imx8ulp.yml` | NXP i.MX8ULP: adds `meta-freescale` + `meta-imx8ulp-adu` |
| `debug.yml` | Adds debug tools (gdb, strace) to the image |
| `delta.yml` | Adds delta update support (requires .NET SDK on build host) |
| `remote.yml` | Adds git URLs so kas auto-clones repos (for CI) |

### Build Isolation

Each machine **must** have its own build directory. This enables incremental
builds and prevents configuration collisions between machines.

| Machine | Build Directory |
|---|---|
| Raspberry Pi 4 | `build_rpi4/` |
| QEMU ARM64 | `build_qemu/` |
| NXP i.MX8ULP | `build_imx8ulp/` |

Downloaded sources and shared-state caches are safe to share across machines.
The kas configs set these automatically:

```
DL_DIR = "${TOPDIR}/../downloads"
SSTATE_DIR = "${TOPDIR}/../sstate-cache"
```

As long as all build directories share the same parent, the `downloads/` and
`sstate-cache/` directories are reused.

## Building

All `kas` commands run from the `sources/iot-hub-device-update-yocto/` directory.

### Local Development

For local builds where all repos are already cloned:

```bash
cd sources/iot-hub-device-update-yocto

# QEMU ARM64
KAS_BUILD_DIR=build_qemu kas build kas/base.yml:kas/machine-qemu.yml

# Raspberry Pi 4
KAS_BUILD_DIR=build_rpi4 kas build kas/base.yml:kas/machine-rpi4.yml

# NXP i.MX8ULP EVK
KAS_BUILD_DIR=build_imx8ulp kas build kas/base.yml:kas/machine-imx8ulp.yml
```

### CI Builds

Include `kas/remote.yml` so kas clones the repos automatically:

```bash
KAS_BUILD_DIR=build_qemu kas build kas/base.yml:kas/machine-qemu.yml:kas/remote.yml
```

### Adding Debug Tools

Append `kas/debug.yml` to include gdb, strace, and other debug utilities:

```bash
KAS_BUILD_DIR=build_rpi4 kas build kas/base.yml:kas/machine-rpi4.yml:kas/debug.yml
```

### Adding Delta Update Support

Append `kas/delta.yml` (requires .NET SDK on the build host):

```bash
KAS_BUILD_DIR=build_rpi4 kas build kas/base.yml:kas/machine-rpi4.yml:kas/delta.yml
```

### Combining Multiple Overlays

Overlays stack freely:

```bash
KAS_BUILD_DIR=build_qemu kas build kas/base.yml:kas/machine-qemu.yml:kas/debug.yml:kas/delta.yml
```

## Board-Specific Notes

### Raspberry Pi 4

- **Storage**: SD card at `/dev/mmcblk0`
- **Boot**: U-Boot is enabled via `RPI_USE_U_BOOT = "1"` (RPi defaults to
  direct kernel boot without U-Boot)
- **BSP**: `meta-raspberrypi` provides firmware, kernel config, and device trees

### QEMU ARM64

QEMU is the virtual reference board used for CI and testing. It has several
differences from physical hardware:

- **Storage**: virtio block device at `/dev/vda` (not `/dev/mmcblk0`)
- **Pflash firmware**: Two 64 MB pflash units are required:
  - `flash0.img` — U-Boot firmware
  - `flash1.img` — U-Boot environment storage
  - **Do not use `-bios`** — it makes the U-Boot environment volatile
- **MTD kernel config**: CFI/physmap flash drivers must be enabled so
  `fw_printenv` / `fw_setenv` can access the U-Boot environment from Linux
- **Boot script**: Uses DM-aware commands (`load virtio 0:1` instead of `fatload`)
- **Device tree**: QEMU provides the DT via `fdtcontroladdr`; the boot script
  does not load a DTB file

### NXP i.MX8ULP EVK

- **Storage**: eMMC at `/dev/mmcblk0`
- **Boot**: NXP's U-Boot fork (`u-boot-imx`), not upstream U-Boot
- **EULA**: You must accept the Freescale/NXP EULA. The kas config sets
  `ACCEPT_FSL_EULA = "1"` — review the license before building.
- **BSP**: `meta-freescale` provides SoC support and firmware

## Testing with QEMU

After building the QEMU image, validate the A/B boot lifecycle without hardware:

```bash
# Launch the QEMU instance interactively
./sources/meta-qemu-adu/scripts/run-adu-qemu.sh

# Or run the automated A/B boot test suite
./sources/meta-qemu-adu/scripts/test-qemu-ab-boot.sh
```

The test suite validates:

- U-Boot environment initialization
- Environment persistence across reboots (via pflash)
- `fw_printenv` / `fw_setenv` from Linux
- Partition switching (rootA → rootB)
- Rollback after maximum boot attempts exceeded
- Catastrophic failure with rescue latch

## Adding a New Board

To add support for a new hardware board, follow the pattern established by
`meta-qemu-adu` and `meta-imx8ulp-adu`.

### 1. Create the Board Integration Layer

Create `meta-<board>-adu/` with the following structure:

```
meta-<board>-adu/
├── conf/
│   ├── layer.conf                              # Layer metadata
│   └── templates/<machine>/
│       ├── local.conf.sample                   # Machine config
│       └── bblayers.conf.sample                # Layer list
├── recipes-bsp/
│   ├── u-boot/                                 # Boot script, U-Boot config
│   └── libubootenv/
│       └── files/fw_env.config                 # Env storage location + offsets
├── recipes-core/
│   └── images/
│       └── adu-base-image.bb                   # Image recipe
├── recipes-support/
│   └── adu-board-config/
│       └── files/board.conf                    # Board-specific parameters
└── wic/
    └── <board>-adu-ab.wks.in                   # WIC partition layout
```

### 2. Create the kas Machine Config

Add `kas/machine-<board>.yml`:

```yaml
header:
  version: 14
  includes:
    - base.yml

machine: <yocto-machine-name>
target: adu-base-image

repos:
  meta-<board>-adu:
    path: ../meta-<board>-adu
```

### 3. Build

```bash
KAS_BUILD_DIR=build_<board> kas build kas/base.yml:kas/machine-<board>.yml
```

### What Must Be Customized Per Board

| Item | Why |
|---|---|
| **`board.conf`** | Partition device paths differ (e.g., `/dev/mmcblk0p2` vs `/dev/vda2`) |
| **Boot script** | Load commands, device tree handling, and console vary by SoC |
| **`fw_env.config`** | U-Boot environment storage location and offsets are board-specific |
| **WIC partition layout** | Device naming and alignment requirements differ |

## Development Workflow

- All Azure repos share a topic branch (e.g., `user/msft/nox-msft/new-yocto-poc`)
- Edit your local clones directly; kas builds from local paths by default
- For CI pipelines, include `kas/remote.yml` to have kas auto-clone from git

## Troubleshooting

### Bitbake refuses to run

Bitbake will not run as root. Switch to a non-root user:

```bash
su - yocto
```

### Build fails with missing layers

Make sure all repos are cloned at the correct branch and located under the same
`sources/` parent directory. Verify with:

```bash
ls ../meta-azure-device-update ../meta-raspberrypi-adu  # etc.
```

For CI, ensure `kas/remote.yml` is included so kas clones missing repos.

### Incremental builds are broken

Each machine must use a separate build directory. Mixing machines in a single
build directory corrupts the configuration. Set `KAS_BUILD_DIR` explicitly:

```bash
KAS_BUILD_DIR=build_rpi4 kas build kas/base.yml:kas/machine-rpi4.yml
```

### QEMU: fw_printenv fails

The kernel must have CFI/physmap MTD drivers enabled. Verify the QEMU instance
was launched with two pflash units (`-pflash` or `-drive if=pflash`), not `-bios`.

### i.MX8ULP: EULA error

Set `ACCEPT_FSL_EULA = "1"` in your kas config or `local.conf`. The
`machine-imx8ulp.yml` kas config sets this automatically.

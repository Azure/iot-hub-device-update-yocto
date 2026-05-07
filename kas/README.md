# kas Build Configurations

[kas](https://kas.readthedocs.io/) is the standard Yocto community build tool.
It uses YAML to declaratively configure layers, machines, and build settings.

## Installation

```bash
pip install kas
```

## Environment Requirements

- WSL2 with Ubuntu 22.04+
- Standard Yocto build dependencies installed
- Run all `kas` commands from inside WSL2

## Quick Start

Run from the `iot-hub-device-update-yocto/` directory:

```bash
# QEMU ARM64 build
kas build kas/base.yml:kas/machine-qemu.yml

# Raspberry Pi 4 build
kas build kas/base.yml:kas/machine-rpi4.yml

# i.MX8ULP EVK build
kas build kas/base.yml:kas/machine-imx8ulp.yml
```

## Composing Configurations

kas merges multiple YAML files left-to-right. Add optional includes:

```bash
# Debug build for QEMU
kas build kas/base.yml:kas/machine-qemu.yml:kas/debug.yml

# RPi4 with local sources (no git fetch)
kas build kas/base.yml:kas/machine-rpi4.yml:kas/local-sources.yml
```

## Configuration Files

| File | Purpose |
|------|---------|
| `base.yml` | Common layers, distro config, shared settings |
| `machine-qemu.yml` | QEMU ARM64 target |
| `machine-rpi4.yml` | Raspberry Pi 4 (64-bit) target |
| `machine-imx8ulp.yml` | NXP i.MX8ULP EVK target |
| `local-sources.yml` | Use pre-cloned local repos (skip fetch) |
| `debug.yml` | Debug build with gdb/strace |

## Local Sources

When developing with already-cloned repositories under `sources/`, append
`local-sources.yml` to skip git operations. This sets `url: null` for all
repos so kas uses existing checkouts as-is:

```bash
kas build kas/base.yml:kas/machine-qemu.yml:kas/local-sources.yml
```

## Build Output

Build artifacts are placed in `build/tmp/deploy/images/<MACHINE>/`.
